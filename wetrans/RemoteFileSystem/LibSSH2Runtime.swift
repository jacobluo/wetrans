import Darwin
import Foundation

public struct LibSSH2LibraryInfo: Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

public enum LibSSH2Error: Error, Equatable {
    case libraryNotFound([String])
    case missingSymbol(String)
    case initializationFailed(Int32)
    case operationUnsupported(String)
    case symbolProviderUnavailable
}

public protocol LoadedLibSSH2Library: AnyObject {
    var info: LibSSH2LibraryInfo { get }
    func initialize() throws
    func shutdown()
}

public protocol LibSSH2SymbolProviding: LoadedLibSSH2Library {
    func symbol(named name: String) -> UnsafeMutableRawPointer?
}

public protocol LibSSH2LibraryLoading {
    func load(candidates: [String]) throws -> LoadedLibSSH2Library
}

public protocol LibSSH2RuntimeManaging {
    @discardableResult
    func initialize() throws -> LibSSH2LibraryInfo
    func symbolProvider() throws -> LibSSH2SymbolProviding
    func shutdown()
}

public extension LibSSH2RuntimeManaging {
    func symbolProvider() throws -> LibSSH2SymbolProviding {
        throw LibSSH2Error.symbolProviderUnavailable
    }
}

public final class LibSSH2Runtime: LibSSH2RuntimeManaging {
    private let loader: LibSSH2LibraryLoading
    private let candidatePaths: [String]
    private var loadedLibrary: LoadedLibSSH2Library?
    private var isInitialized = false
    private var isShutdown = false

    public init(
        loader: LibSSH2LibraryLoading = DarwinLibSSH2LibraryLoader(),
        candidatePaths: [String] = LibSSH2Runtime.defaultCandidatePaths()
    ) {
        self.loader = loader
        self.candidatePaths = candidatePaths
    }

    public static func defaultCandidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var paths: [String] = []
        if let override = environment["WETRANS_LIBSSH2_DYLIB"], !override.isEmpty {
            paths.append(override)
        }
        paths.append(contentsOf: [
            "/opt/homebrew/opt/libssh2/lib/libssh2.dylib",
            "/usr/local/opt/libssh2/lib/libssh2.dylib",
            "/opt/homebrew/lib/libssh2.dylib",
            "/usr/local/lib/libssh2.dylib",
            "libssh2.dylib"
        ])
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    @discardableResult
    public func initialize() throws -> LibSSH2LibraryInfo {
        if let loadedLibrary, isInitialized {
            return loadedLibrary.info
        }

        let library = try loadedLibrary ?? loader.load(candidates: candidatePaths)
        if loadedLibrary == nil {
            loadedLibrary = library
        }
        try library.initialize()
        isInitialized = true
        isShutdown = false
        return library.info
    }

    public func shutdown() {
        guard isInitialized, !isShutdown, let loadedLibrary else {
            return
        }
        loadedLibrary.shutdown()
        isShutdown = true
        isInitialized = false
    }

    public func symbolProvider() throws -> LibSSH2SymbolProviding {
        _ = try initialize()
        guard let provider = loadedLibrary as? LibSSH2SymbolProviding else {
            throw LibSSH2Error.symbolProviderUnavailable
        }
        return provider
    }
}

public final class DarwinLibSSH2LibraryLoader: LibSSH2LibraryLoading {
    public init() {}

    public func load(candidates: [String]) throws -> LoadedLibSSH2Library {
        for path in candidates {
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                do {
                    return try DarwinLoadedLibSSH2Library(handle: handle, path: path)
                } catch {
                    dlclose(handle)
                    throw error
                }
            }
        }
        throw LibSSH2Error.libraryNotFound(candidates)
    }
}

private final class DarwinLoadedLibSSH2Library: LibSSH2SymbolProviding {
    typealias VersionFunction = @convention(c) (Int32) -> UnsafePointer<CChar>?
    typealias InitFunction = @convention(c) (Int32) -> Int32
    typealias ExitFunction = @convention(c) () -> Void

    let info: LibSSH2LibraryInfo

    private let handle: UnsafeMutableRawPointer
    private let initializeFunction: InitFunction
    private let exitFunction: ExitFunction

    init(handle: UnsafeMutableRawPointer, path: String) throws {
        self.handle = handle

        guard let initSymbol = dlsym(handle, "libssh2_init") else {
            throw LibSSH2Error.missingSymbol("libssh2_init")
        }
        guard let exitSymbol = dlsym(handle, "libssh2_exit") else {
            throw LibSSH2Error.missingSymbol("libssh2_exit")
        }

        self.initializeFunction = unsafeBitCast(initSymbol, to: InitFunction.self)
        self.exitFunction = unsafeBitCast(exitSymbol, to: ExitFunction.self)

        let version: String?
        if let versionSymbol = dlsym(handle, "libssh2_version") {
            let versionFunction = unsafeBitCast(versionSymbol, to: VersionFunction.self)
            version = versionFunction(0).map { String(cString: $0) }
        } else {
            version = nil
        }

        self.info = LibSSH2LibraryInfo(path: path, version: version)
    }

    deinit {
        dlclose(handle)
    }

    func initialize() throws {
        let status = initializeFunction(0)
        guard status == 0 else {
            throw LibSSH2Error.initializationFailed(status)
        }
    }

    func shutdown() {
        exitFunction()
    }

    func symbol(named name: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, name)
    }
}
