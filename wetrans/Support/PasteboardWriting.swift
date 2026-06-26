import AppKit
import Foundation

public protocol PasteboardWriting: Sendable {
    func writeString(_ value: String)
}

public struct SystemPasteboardWriter: PasteboardWriting {
    public init() {}

    public func writeString(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
