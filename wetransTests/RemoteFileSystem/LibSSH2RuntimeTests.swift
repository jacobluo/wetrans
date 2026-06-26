import XCTest
@testable import wetrans

final class LibSSH2RuntimeTests: XCTestCase {
    func testCandidatePathsPutEnvironmentOverrideFirst() {
        let environment = ["WETRANS_LIBSSH2_DYLIB": "/tmp/libssh2.dylib"]

        let paths = LibSSH2Runtime.defaultCandidatePaths(environment: environment)

        XCTAssertEqual(paths.first, "/tmp/libssh2.dylib")
        XCTAssertTrue(paths.contains("libssh2.dylib"))
    }

    func testInitializeLoadsAndInitializesOnlyOnce() throws {
        let loader = FakeLibSSH2Loader(
            loadedLibrary: FakeLoadedLibSSH2Library(
                info: LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: "1.11.1")
            )
        )
        let runtime = LibSSH2Runtime(loader: loader, candidatePaths: ["/fake/libssh2.dylib"])

        XCTAssertEqual(try runtime.initialize(), LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: "1.11.1"))
        XCTAssertEqual(try runtime.initialize(), LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: "1.11.1"))

        XCTAssertEqual(loader.loadCalls, [["/fake/libssh2.dylib"]])
        XCTAssertEqual(loader.loadedLibrary.initializeCount, 1)
    }

    func testShutdownCallsLoadedLibraryShutdownOnlyOnce() throws {
        let loader = FakeLibSSH2Loader(
            loadedLibrary: FakeLoadedLibSSH2Library(
                info: LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: nil)
            )
        )
        let runtime = LibSSH2Runtime(loader: loader, candidatePaths: ["/fake/libssh2.dylib"])

        _ = try runtime.initialize()
        runtime.shutdown()
        runtime.shutdown()

        XCTAssertEqual(loader.loadedLibrary.shutdownCount, 1)
    }

    func testMissingLibraryThrowsLibraryNotFound() {
        let loader = FakeLibSSH2Loader(loadError: LibSSH2Error.libraryNotFound(["/missing/libssh2.dylib"]))
        let runtime = LibSSH2Runtime(loader: loader, candidatePaths: ["/missing/libssh2.dylib"])

        XCTAssertThrowsError(try runtime.initialize()) { error in
            XCTAssertEqual(error as? LibSSH2Error, .libraryNotFound(["/missing/libssh2.dylib"]))
        }
    }

    func testSymbolProviderReturnsLoadedLibrarySymbols() throws {
        let presentSymbol = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let loadedLibrary = FakeLoadedLibSSH2Library(
            info: LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: nil),
            symbols: ["present": presentSymbol]
        )
        let runtime = LibSSH2Runtime(
            loader: FakeLibSSH2Loader(loadedLibrary: loadedLibrary),
            candidatePaths: ["/fake/libssh2.dylib"]
        )

        _ = try runtime.initialize()
        let provider = try runtime.symbolProvider()

        XCTAssertEqual(provider.symbol(named: "present"), presentSymbol)
        XCTAssertNil(provider.symbol(named: "missing"))
    }
}

final class LibSSH2RuntimeRealProbeTests: XCTestCase {
    func testRealProbeWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["WETRANS_RUN_LIBSSH2_REAL_PROBE"] == "1" else {
            throw XCTSkip("Set WETRANS_RUN_LIBSSH2_REAL_PROBE=1 to run the real libssh2 probe.")
        }

        let runtime = LibSSH2Runtime()
        let info = try runtime.initialize()

        XCTAssertFalse(info.path.isEmpty)

        runtime.shutdown()
    }
}

private final class FakeLibSSH2Loader: LibSSH2LibraryLoading {
    let loadedLibrary: FakeLoadedLibSSH2Library
    let loadError: Error?
    private(set) var loadCalls: [[String]] = []

    init(
        loadedLibrary: FakeLoadedLibSSH2Library = FakeLoadedLibSSH2Library(
            info: LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: nil)
        ),
        loadError: Error? = nil
    ) {
        self.loadedLibrary = loadedLibrary
        self.loadError = loadError
    }

    func load(candidates: [String]) throws -> LoadedLibSSH2Library {
        loadCalls.append(candidates)
        if let loadError {
            throw loadError
        }
        return loadedLibrary
    }
}

private final class FakeLoadedLibSSH2Library: LibSSH2SymbolProviding {
    let info: LibSSH2LibraryInfo
    let symbols: [String: UnsafeMutableRawPointer]
    private(set) var initializeCount = 0
    private(set) var shutdownCount = 0

    init(info: LibSSH2LibraryInfo, symbols: [String: UnsafeMutableRawPointer] = [:]) {
        self.info = info
        self.symbols = symbols
    }

    func initialize() throws {
        initializeCount += 1
    }

    func shutdown() {
        shutdownCount += 1
    }

    func symbol(named name: String) -> UnsafeMutableRawPointer? {
        symbols[name]
    }
}
