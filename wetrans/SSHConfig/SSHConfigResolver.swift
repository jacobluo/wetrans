import Foundation

public protocol SSHConfigResolver {
    func resolve(alias: String) async throws -> ResolvedSSHConfig
}

public enum SSHConfigResolverError: Error, Equatable {
    case missingHostname
    case invalidPort(String)
    case processFailed(exitCode: Int32, stderr: String)
}

