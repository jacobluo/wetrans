import Foundation

public protocol SSHConfigScanner {
    func scanDefaultConfig() throws -> [SSHConfigAlias]
}

