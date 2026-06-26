import Foundation

public final class ProcessSSHConfigResolver: SSHConfigResolver, @unchecked Sendable {
    private let sshURL: URL

    public init(sshURL: URL = URL(fileURLWithPath: "/usr/bin/ssh")) {
        self.sshURL = sshURL
    }

    public func resolve(alias: String) async throws -> ResolvedSSHConfig {
        let process = Process()
        process.executableURL = sshURL
        process.arguments = ["-G", alias]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            throw SSHConfigResolverError.processFailed(
                exitCode: process.terminationStatus,
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        }

        return try Self.parse(alias: alias, output: String(decoding: stdout, as: UTF8.self))
    }

    public static func parse(alias: String, output: String) throws -> ResolvedSSHConfig {
        var values: [String: [String]] = [:]

        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else {
                continue
            }
            values[String(parts[0]).lowercased(), default: []].append(String(parts[1]))
        }

        guard let hostname = values["hostname"]?.first, !hostname.trimmedForValidation.isEmpty else {
            throw SSHConfigResolverError.missingHostname
        }

        let portText = values["port"]?.first ?? "22"
        guard let port = Int(portText), (1...65_535).contains(port) else {
            throw SSHConfigResolverError.invalidPort(portText)
        }

        return ResolvedSSHConfig(
            alias: alias,
            hostname: hostname,
            user: nonNone(values["user"]?.first),
            port: port,
            identityFiles: (values["identityfile"] ?? []).filter { nonNone($0) != nil },
            proxyJump: nonNone(values["proxyjump"]?.first),
            proxyCommand: nonNone(values["proxycommand"]?.first)
        )
    }

    public static func makeDraft(from resolved: ResolvedSSHConfig, resolvedAt: Date = Date()) -> HostDraft {
        let identityFile = resolved.identityFiles.first
        return HostDraft(
            source: .sshConfigGenerated,
            displayName: resolved.alias,
            hostname: resolved.hostname,
            port: resolved.port,
            username: resolved.user ?? NSUserName(),
            authType: identityFile == nil ? .password : .sshKey,
            identityFile: identityFile,
            password: nil,
            keyPassphrase: nil,
            defaultRemotePath: nil,
            originSSHConfigAlias: resolved.alias,
            resolvedAt: resolvedAt,
            unsupportedOptions: unsupportedWarnings(from: resolved)
        )
    }

    private static func unsupportedWarnings(from resolved: ResolvedSSHConfig) -> [SSHConfigWarning] {
        var warnings: [SSHConfigWarning] = []
        if let proxyJump = resolved.proxyJump {
            warnings.append(
                SSHConfigWarning(
                    key: "proxyjump",
                    value: proxyJump,
                    message: "ProxyJump is not supported in the MVP."
                )
            )
        }
        if let proxyCommand = resolved.proxyCommand {
            warnings.append(
                SSHConfigWarning(
                    key: "proxycommand",
                    value: proxyCommand,
                    message: "ProxyCommand is not supported in the MVP."
                )
            )
        }
        return warnings
    }
}

private func nonNone(_ value: String?) -> String? {
    guard let value = value?.trimmedNilIfEmpty, value.lowercased() != "none" else {
        return nil
    }
    return value
}
