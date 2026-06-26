import Foundation

public extension FileManager {
    static var wetransApplicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wetrans", isDirectory: true)
    }
}
