import Foundation

public struct SSHConfigAlias: Identifiable, Equatable {
    public var id: String { alias }
    public let alias: String
    public let sourcePath: String?

    public init(alias: String, sourcePath: String? = nil) {
        self.alias = alias
        self.sourcePath = sourcePath
    }
}

