import AppKit
import Foundation

public protocol FileRevealer: Sendable {
    func reveal(path: String)
}

public struct NSWorkspaceFileRevealer: FileRevealer {
    public init() {}

    public func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
