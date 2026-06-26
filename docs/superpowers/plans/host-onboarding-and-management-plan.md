# Host Onboarding and Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement host onboarding and management so users can create manual hosts, generate hosts from SSH Config, save them as `SavedHost`, organize them in the sidebar, edit/delete/favorite them, and keep secrets out of JSON.

**Architecture:** This plan assumes the macOS project foundation and core domain model files from M1/M2 exist. The feature is implemented through deep modules: `HostCatalog`, `CredentialStore`, `SSHConfigScanner`, `SSHConfigResolver`, sidebar view model, and connect-host dialog view model. UI calls view models; view models call module interfaces; persistence and shell execution stay behind adapters.

**Tech Stack:** Swift, SwiftUI, AppKit-ready view models, XCTest, JSON persistence, Keychain through `CredentialStore`, `/usr/bin/ssh -G` through `SSHConfigResolver`.

---

## Prerequisites

This plan should be executed after these baseline milestones exist:

- M1: macOS project foundation.
- M2: domain models and JSON persistence.

Expected project layout:

```text
wetrans/
  Domain/
  Persistence/
  SSHConfig/
  Security/
  UI/
    HostManagement/
wetransTests/
  Domain/
  Persistence/
  SSHConfig/
  Security/
  UI/
```

If the project layout differs, keep the same module boundaries and adapt paths consistently.

## Source Spec

- Focused spec: `docs/superpowers/specs/host-onboarding-and-management-spec.md`
- Data model: `docs/data-model.md`
- Architecture: `docs/architecture-design.md`

## File Map

Create or modify these files:

```text
wetrans/Domain/SavedHost.swift
wetrans/Domain/HostDraft.swift
wetrans/Domain/HostValidation.swift
wetrans/Persistence/HostCatalog.swift
wetrans/Persistence/FileHostCatalog.swift
wetrans/Security/CredentialStore.swift
wetrans/Security/InMemoryCredentialStore.swift
wetrans/SSHConfig/SSHConfigAlias.swift
wetrans/SSHConfig/SSHConfigScanner.swift
wetrans/SSHConfig/FileSSHConfigScanner.swift
wetrans/SSHConfig/ResolvedSSHConfig.swift
wetrans/SSHConfig/SSHConfigResolver.swift
wetrans/SSHConfig/ProcessSSHConfigResolver.swift
wetrans/UI/HostManagement/HostSidebarViewModel.swift
wetrans/UI/HostManagement/ConnectHostViewModel.swift
wetrans/UI/HostManagement/HostFormViewModel.swift
wetrans/UI/HostManagement/HostOnboardingViews.swift
wetransTests/Domain/HostValidationTests.swift
wetransTests/Persistence/HostCatalogTests.swift
wetransTests/SSHConfig/SSHConfigScannerTests.swift
wetransTests/SSHConfig/SSHConfigResolverTests.swift
wetransTests/UI/HostSidebarViewModelTests.swift
wetransTests/UI/ConnectHostViewModelTests.swift
```

## Task 1: Validate HostDraft Before Save

**Files:**

- Create or modify: `wetrans/Domain/HostDraft.swift`
- Create or modify: `wetrans/Domain/HostValidation.swift`
- Test: `wetransTests/Domain/HostValidationTests.swift`

- [x] **Step 1: Write failing validation tests**

```swift
import XCTest
@testable import wetrans

final class HostValidationTests: XCTestCase {
    func testManualPasswordHostWithRequiredFieldsIsValid() {
        let draft = HostDraft(
            source: .manual,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            identityFile: nil,
            password: "secret",
            keyPassphrase: nil,
            defaultRemotePath: "/home/ubuntu",
            originSSHConfigAlias: nil,
            resolvedAt: nil,
            unsupportedOptions: []
        )

        XCTAssertNoThrow(try HostValidator.validate(draft))
    }

    func testDisplayNameIsRequired() {
        var draft = HostDraft.validManualFixture()
        draft.displayName = " "

        XCTAssertThrowsError(try HostValidator.validate(draft)) { error in
            XCTAssertEqual(error as? HostValidationError, .missingDisplayName)
        }
    }

    func testPortMustBeInRange() {
        var draft = HostDraft.validManualFixture()
        draft.port = 70000

        XCTAssertThrowsError(try HostValidator.validate(draft)) { error in
            XCTAssertEqual(error as? HostValidationError, .invalidPort)
        }
    }

    func testSSHKeyRequiresIdentityFile() {
        var draft = HostDraft.validManualFixture()
        draft.authType = .sshKey
        draft.identityFile = nil

        XCTAssertThrowsError(try HostValidator.validate(draft)) { error in
            XCTAssertEqual(error as? HostValidationError, .missingIdentityFile)
        }
    }
}

private extension HostDraft {
    static func validManualFixture() -> HostDraft {
        HostDraft(
            source: .manual,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            identityFile: nil,
            password: nil,
            keyPassphrase: nil,
            defaultRemotePath: nil,
            originSSHConfigAlias: nil,
            resolvedAt: nil,
            unsupportedOptions: []
        )
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostValidationTests
```

Expected: fails because `HostDraft` or `HostValidator` is missing.

- [x] **Step 3: Implement HostDraft and HostValidator**

```swift
import Foundation

struct HostDraft: Equatable {
    var source: HostSource
    var displayName: String
    var hostname: String
    var port: Int
    var username: String
    var authType: AuthType
    var identityFile: String?
    var password: String?
    var keyPassphrase: String?
    var defaultRemotePath: String?
    var originSSHConfigAlias: String?
    var resolvedAt: Date?
    var unsupportedOptions: [SSHConfigWarning]
}

struct SSHConfigWarning: Codable, Equatable {
    var key: String
    var value: String
    var message: String
}

enum HostValidationError: Error, Equatable {
    case missingDisplayName
    case missingHostname
    case invalidPort
    case missingUsername
    case missingIdentityFile
}

enum HostValidator {
    static func validate(_ draft: HostDraft) throws {
        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HostValidationError.missingDisplayName
        }
        if draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HostValidationError.missingHostname
        }
        if draft.port < 1 || draft.port > 65_535 {
            throw HostValidationError.invalidPort
        }
        if draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HostValidationError.missingUsername
        }
        if draft.authType == .sshKey &&
            (draft.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            throw HostValidationError.missingIdentityFile
        }
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostValidationTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Domain/HostDraft.swift wetrans/Domain/HostValidation.swift wetransTests/Domain/HostValidationTests.swift
git commit -m "Add host draft validation"
```

## Task 2: Convert HostDraft to SavedHost Without Secrets

**Files:**

- Modify: `wetrans/Domain/SavedHost.swift`
- Modify: `wetrans/Domain/HostDraft.swift`
- Test: `wetransTests/Domain/HostDraftConversionTests.swift`

- [x] **Step 1: Write failing conversion tests**

```swift
import XCTest
@testable import wetrans

final class HostDraftConversionTests: XCTestCase {
    func testManualDraftConvertsToSavedHostWithoutSecrets() throws {
        let draft = HostDraft(
            source: .manual,
            displayName: "prod",
            hostname: "prod.example.com",
            port: 2222,
            username: "deploy",
            authType: .password,
            identityFile: nil,
            password: "secret",
            keyPassphrase: "phrase",
            defaultRemotePath: "/var/www",
            originSSHConfigAlias: nil,
            resolvedAt: nil,
            unsupportedOptions: []
        )

        let host = try draft.makeSavedHost(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

        XCTAssertEqual(host.displayName, "prod")
        XCTAssertEqual(host.hostname, "prod.example.com")
        XCTAssertEqual(host.port, 2222)
        XCTAssertEqual(host.username, "deploy")
        XCTAssertEqual(host.authType, .password)
        XCTAssertEqual(host.defaultRemotePath, "/var/www")
        XCTAssertNil(host.originSSHConfigAlias)
        XCTAssertNil(host.resolvedAt)
    }

    func testGeneratedDraftPreservesSSHConfigMetadata() throws {
        let resolvedAt = Date(timeIntervalSince1970: 100)
        let draft = HostDraft(
            source: .sshConfigGenerated,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            authType: .sshKey,
            identityFile: "~/.ssh/id_ed25519",
            password: nil,
            keyPassphrase: nil,
            defaultRemotePath: nil,
            originSSHConfigAlias: "dev",
            resolvedAt: resolvedAt,
            unsupportedOptions: []
        )

        let host = try draft.makeSavedHost(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

        XCTAssertEqual(host.source, .sshConfigGenerated)
        XCTAssertEqual(host.originSSHConfigAlias, "dev")
        XCTAssertEqual(host.resolvedAt, resolvedAt)
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostDraftConversionTests
```

Expected: fails because `makeSavedHost` is missing.

- [x] **Step 3: Implement conversion**

```swift
import Foundation

extension HostDraft {
    func makeSavedHost(id: UUID = UUID()) throws -> SavedHost {
        try HostValidator.validate(self)
        return SavedHost(
            id: id,
            source: source,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: authType,
            identityFile: identityFile?.trimmingCharacters(in: .whitespacesAndNewlines),
            isFavorite: false,
            lastConnectedAt: nil,
            lastRemotePath: nil,
            lastLocalPath: nil,
            defaultRemotePath: defaultRemotePath?.trimmingCharacters(in: .whitespacesAndNewlines),
            favoriteRemotePaths: [],
            originSSHConfigAlias: originSSHConfigAlias,
            resolvedAt: resolvedAt,
            note: nil
        )
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostDraftConversionTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Domain/SavedHost.swift wetrans/Domain/HostDraft.swift wetransTests/Domain/HostDraftConversionTests.swift
git commit -m "Convert host drafts to saved hosts"
```

## Task 3: Implement HostCatalog Behavior

**Files:**

- Create or modify: `wetrans/Persistence/HostCatalog.swift`
- Create or modify: `wetrans/Persistence/FileHostCatalog.swift`
- Test: `wetransTests/Persistence/HostCatalogTests.swift`

- [x] **Step 1: Write failing catalog tests**

```swift
import XCTest
@testable import wetrans

final class HostCatalogTests: XCTestCase {
    func testSaveLoadFavoriteAndPathUpdates() throws {
        let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let catalog = FileHostCatalog(rootDirectory: directory)
        var host = SavedHost.fixture(displayName: "dev")

        try catalog.save(host)
        try catalog.setFavorite(hostId: host.id, isFavorite: true)
        try catalog.updatePaths(hostId: host.id, local: "/Users/me/Downloads", remote: "/home/ubuntu")

        let loaded = try XCTUnwrap(catalog.load().first)
        XCTAssertTrue(loaded.isFavorite)
        XCTAssertEqual(loaded.lastLocalPath, "/Users/me/Downloads")
        XCTAssertEqual(loaded.lastRemotePath, "/home/ubuntu")
    }

    func testMarkConnectedUpdatesLastConnectedAt() throws {
        let directory = try temporaryDirectory()
        let catalog = FileHostCatalog(rootDirectory: directory)
        let host = SavedHost.fixture(displayName: "prod")
        let date = Date(timeIntervalSince1970: 200)

        try catalog.save(host)
        try catalog.markConnected(hostId: host.id, at: date)

        XCTAssertEqual(try catalog.load().first?.lastConnectedAt, date)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private extension SavedHost {
    static func fixture(displayName: String) -> SavedHost {
        SavedHost(
            id: UUID(),
            source: .manual,
            displayName: displayName,
            hostname: "\(displayName).example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            identityFile: nil,
            isFavorite: false,
            lastConnectedAt: nil,
            lastRemotePath: nil,
            lastLocalPath: nil,
            defaultRemotePath: nil,
            favoriteRemotePaths: [],
            originSSHConfigAlias: nil,
            resolvedAt: nil,
            note: nil
        )
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostCatalogTests
```

Expected: fails because `FileHostCatalog` is missing.

- [x] **Step 3: Implement catalog interface and file-backed adapter**

```swift
import Foundation

protocol HostCatalog {
    func load() throws -> [SavedHost]
    func save(_ host: SavedHost) throws
    func delete(hostId: UUID) throws
    func markConnected(hostId: UUID, at date: Date) throws
    func updatePaths(hostId: UUID, local: String?, remote: String?) throws
    func setFavorite(hostId: UUID, isFavorite: Bool) throws
}

struct HostsDocument: Codable {
    var schemaVersion: Int
    var hosts: [SavedHost]
}

final class FileHostCatalog: HostCatalog {
    private let fileURL: URL

    init(rootDirectory: URL) {
        self.fileURL = rootDirectory.appendingPathComponent("hosts.json")
    }

    func load() throws -> [SavedHost] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.wetrans.decode(HostsDocument.self, from: data).hosts
    }

    func save(_ host: SavedHost) throws {
        var hosts = try load().filter { $0.id != host.id }
        hosts.append(host)
        try write(hosts)
    }

    func delete(hostId: UUID) throws {
        try write(try load().filter { $0.id != hostId })
    }

    func markConnected(hostId: UUID, at date: Date) throws {
        try mutate(hostId: hostId) { $0.lastConnectedAt = date }
    }

    func updatePaths(hostId: UUID, local: String?, remote: String?) throws {
        try mutate(hostId: hostId) {
            if let local { $0.lastLocalPath = local }
            if let remote { $0.lastRemotePath = remote }
        }
    }

    func setFavorite(hostId: UUID, isFavorite: Bool) throws {
        try mutate(hostId: hostId) { $0.isFavorite = isFavorite }
    }

    private func mutate(hostId: UUID, change: (inout SavedHost) -> Void) throws {
        var hosts = try load()
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        change(&hosts[index])
        try write(hosts)
    }

    private func write(_ hosts: [SavedHost]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = HostsDocument(schemaVersion: 1, hosts: hosts)
        let data = try JSONEncoder.wetrans.encode(document)
        let tempURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }
}

extension JSONEncoder {
    static var wetrans: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var wetrans: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostCatalogTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Persistence/HostCatalog.swift wetrans/Persistence/FileHostCatalog.swift wetransTests/Persistence/HostCatalogTests.swift
git commit -m "Add file-backed host catalog"
```

## Task 4: Implement SSH Config Scanner

**Files:**

- Create: `wetrans/SSHConfig/SSHConfigAlias.swift`
- Create: `wetrans/SSHConfig/SSHConfigScanner.swift`
- Create: `wetrans/SSHConfig/FileSSHConfigScanner.swift`
- Test: `wetransTests/SSHConfig/SSHConfigScannerTests.swift`

- [x] **Step 1: Write failing scanner tests**

```swift
import XCTest
@testable import wetrans

final class SSHConfigScannerTests: XCTestCase {
    func testFiltersWildcardsAndNegatedAliases() throws {
        let text = """
        Host dev
          HostName dev.example.com

        Host prod staging
          HostName prod.example.com

        Host *
          User ubuntu

        Host prod-*
          User deploy

        Host !bad *
          User blocked
        """

        let aliases = try FileSSHConfigScanner.scanAliases(in: text)

        XCTAssertEqual(aliases.map(\.alias), ["dev", "prod", "staging"])
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/SSHConfigScannerTests
```

Expected: fails because scanner is missing.

- [x] **Step 3: Implement scanner**

```swift
import Foundation

struct SSHConfigAlias: Identifiable, Equatable {
    var id: String { alias }
    let alias: String
}

protocol SSHConfigScanner {
    func scanDefaultConfig() throws -> [SSHConfigAlias]
}

final class FileSSHConfigScanner: SSHConfigScanner {
    private let configURL: URL

    init(configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")) {
        self.configURL = configURL
    }

    func scanDefaultConfig() throws -> [SSHConfigAlias] {
        let text = try String(contentsOf: configURL, encoding: .utf8)
        return try Self.scanAliases(in: text)
    }

    static func scanAliases(in text: String) throws -> [SSHConfigAlias] {
        var result: [SSHConfigAlias] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("host ") else { continue }
            let tokens = trimmed.dropFirst(5).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            for token in tokens where isSelectableAlias(token) {
                result.append(SSHConfigAlias(alias: token))
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.alias).inserted }
    }

    private static func isSelectableAlias(_ alias: String) -> Bool {
        if alias.hasPrefix("!") { return false }
        if alias.contains("*") || alias.contains("?") { return false }
        return !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/SSHConfigScannerTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/SSHConfig/SSHConfigAlias.swift wetrans/SSHConfig/SSHConfigScanner.swift wetrans/SSHConfig/FileSSHConfigScanner.swift wetransTests/SSHConfig/SSHConfigScannerTests.swift
git commit -m "Add SSH config alias scanner"
```

## Task 5: Implement SSH Config Resolver

**Files:**

- Create: `wetrans/SSHConfig/ResolvedSSHConfig.swift`
- Create: `wetrans/SSHConfig/SSHConfigResolver.swift`
- Create: `wetrans/SSHConfig/ProcessSSHConfigResolver.swift`
- Test: `wetransTests/SSHConfig/SSHConfigResolverTests.swift`

- [x] **Step 1: Write failing resolver parser tests**

```swift
import XCTest
@testable import wetrans

final class SSHConfigResolverTests: XCTestCase {
    func testParsesSSHResolvedOutput() throws {
        let output = """
        hostname dev.example.com
        user ubuntu
        port 22
        identityfile ~/.ssh/id_ed25519
        proxyjump bastion
        """

        let resolved = try ProcessSSHConfigResolver.parse(alias: "dev", output: output)

        XCTAssertEqual(resolved.alias, "dev")
        XCTAssertEqual(resolved.hostname, "dev.example.com")
        XCTAssertEqual(resolved.user, "ubuntu")
        XCTAssertEqual(resolved.port, 22)
        XCTAssertEqual(resolved.identityFiles, ["~/.ssh/id_ed25519"])
        XCTAssertEqual(resolved.proxyJump, "bastion")
    }

    func testMakesDraftFromResolvedConfig() throws {
        let resolved = ResolvedSSHConfig(
            alias: "dev",
            hostname: "dev.example.com",
            user: "ubuntu",
            port: 22,
            identityFiles: ["~/.ssh/id_ed25519"],
            proxyJump: nil,
            proxyCommand: nil
        )

        let draft = ProcessSSHConfigResolver.makeDraft(from: resolved, resolvedAt: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(draft.source, .sshConfigGenerated)
        XCTAssertEqual(draft.displayName, "dev")
        XCTAssertEqual(draft.hostname, "dev.example.com")
        XCTAssertEqual(draft.username, "ubuntu")
        XCTAssertEqual(draft.authType, .sshKey)
        XCTAssertEqual(draft.identityFile, "~/.ssh/id_ed25519")
        XCTAssertEqual(draft.originSSHConfigAlias, "dev")
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/SSHConfigResolverTests
```

Expected: fails because resolver types are missing.

- [x] **Step 3: Implement parser and draft mapping**

```swift
import Foundation

struct ResolvedSSHConfig: Equatable {
    let alias: String
    let hostname: String
    let user: String?
    let port: Int
    let identityFiles: [String]
    let proxyJump: String?
    let proxyCommand: String?
}

protocol SSHConfigResolver {
    func resolve(alias: String) async throws -> ResolvedSSHConfig
}

enum SSHConfigResolverError: Error, Equatable {
    case missingHostname
    case invalidPort(String)
}

final class ProcessSSHConfigResolver: SSHConfigResolver {
    func resolve(alias: String) async throws -> ResolvedSSHConfig {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-G", alias]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return try Self.parse(alias: alias, output: output)
    }

    static func parse(alias: String, output: String) throws -> ResolvedSSHConfig {
        var values: [String: [String]] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            values[String(parts[0]).lowercased(), default: []].append(String(parts[1]))
        }

        guard let hostname = values["hostname"]?.first else {
            throw SSHConfigResolverError.missingHostname
        }
        let portText = values["port"]?.first ?? "22"
        guard let port = Int(portText) else {
            throw SSHConfigResolverError.invalidPort(portText)
        }

        return ResolvedSSHConfig(
            alias: alias,
            hostname: hostname,
            user: values["user"]?.first,
            port: port,
            identityFiles: values["identityfile"] ?? [],
            proxyJump: values["proxyjump"]?.first,
            proxyCommand: values["proxycommand"]?.first
        )
    }

    static func makeDraft(from resolved: ResolvedSSHConfig, resolvedAt: Date = Date()) -> HostDraft {
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
            warnings.append(SSHConfigWarning(key: "proxyjump", value: proxyJump, message: "ProxyJump is not supported in the MVP."))
        }
        if let proxyCommand = resolved.proxyCommand {
            warnings.append(SSHConfigWarning(key: "proxycommand", value: proxyCommand, message: "ProxyCommand is not supported in the MVP."))
        }
        return warnings
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/SSHConfigResolverTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/SSHConfig/ResolvedSSHConfig.swift wetrans/SSHConfig/SSHConfigResolver.swift wetrans/SSHConfig/ProcessSSHConfigResolver.swift wetransTests/SSHConfig/SSHConfigResolverTests.swift
git commit -m "Add SSH config resolver"
```

## Task 6: Implement Host Sidebar View Model

**Files:**

- Create: `wetrans/UI/HostManagement/HostSidebarViewModel.swift`
- Test: `wetransTests/UI/HostSidebarViewModelTests.swift`

- [x] **Step 1: Write failing grouping tests**

```swift
import XCTest
@testable import wetrans

final class HostSidebarViewModelTests: XCTestCase {
    func testGroupsHostsByFavoriteRecentThenMyHosts() {
        let favorite = SavedHost.fixture(displayName: "fav", isFavorite: true, lastConnectedAt: Date(timeIntervalSince1970: 10))
        let recent = SavedHost.fixture(displayName: "recent", isFavorite: false, lastConnectedAt: Date(timeIntervalSince1970: 20))
        let mine = SavedHost.fixture(displayName: "mine", isFavorite: false, lastConnectedAt: nil)

        let groups = HostSidebarViewModel.makeGroups(hosts: [mine, recent, favorite])

        XCTAssertEqual(groups.favorites.map(\.displayName), ["fav"])
        XCTAssertEqual(groups.recent.map(\.displayName), ["recent"])
        XCTAssertEqual(groups.myHosts.map(\.displayName), ["mine"])
    }

    func testRecentHostsAreSortedAndLimited() {
        let hosts = (0..<12).map {
            SavedHost.fixture(displayName: "h\($0)", isFavorite: false, lastConnectedAt: Date(timeIntervalSince1970: TimeInterval($0)))
        }

        let groups = HostSidebarViewModel.makeGroups(hosts: hosts)

        XCTAssertEqual(groups.recent.count, 10)
        XCTAssertEqual(groups.recent.first?.displayName, "h11")
    }
}

private extension SavedHost {
    static func fixture(displayName: String, isFavorite: Bool, lastConnectedAt: Date?) -> SavedHost {
        SavedHost(
            id: UUID(),
            source: .manual,
            displayName: displayName,
            hostname: "\(displayName).example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            identityFile: nil,
            isFavorite: isFavorite,
            lastConnectedAt: lastConnectedAt,
            lastRemotePath: nil,
            lastLocalPath: nil,
            defaultRemotePath: nil,
            favoriteRemotePaths: [],
            originSSHConfigAlias: nil,
            resolvedAt: nil,
            note: nil
        )
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostSidebarViewModelTests
```

Expected: fails because `HostSidebarViewModel` is missing.

- [x] **Step 3: Implement grouping**

```swift
import Foundation

struct HostSidebarGroups: Equatable {
    var favorites: [SavedHost]
    var recent: [SavedHost]
    var myHosts: [SavedHost]
}

final class HostSidebarViewModel: ObservableObject {
    @Published private(set) var groups = HostSidebarGroups(favorites: [], recent: [], myHosts: [])
    @Published var selectedHostId: UUID?

    func update(hosts: [SavedHost]) {
        groups = Self.makeGroups(hosts: hosts)
    }

    static func makeGroups(hosts: [SavedHost]) -> HostSidebarGroups {
        let favorites = hosts
            .filter(\.isFavorite)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let recent = hosts
            .filter { !$0.isFavorite && $0.lastConnectedAt != nil }
            .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
            .prefix(10)

        let myHosts = hosts
            .filter { !$0.isFavorite && $0.lastConnectedAt == nil }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return HostSidebarGroups(favorites: favorites, recent: Array(recent), myHosts: myHosts)
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/HostSidebarViewModelTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/UI/HostManagement/HostSidebarViewModel.swift wetransTests/UI/HostSidebarViewModelTests.swift
git commit -m "Add host sidebar grouping"
```

## Task 7: Implement Connect Host View Model

**Files:**

- Create: `wetrans/UI/HostManagement/ConnectHostViewModel.swift`
- Create: `wetrans/Security/InMemoryCredentialStore.swift`
- Test: `wetransTests/UI/ConnectHostViewModelTests.swift`

- [ ] **Step 1: Write failing save-flow tests**

```swift
import XCTest
@testable import wetrans

final class ConnectHostViewModelTests: XCTestCase {
    func testSavingManualDraftSavesHostAndPasswordThroughCredentialStore() async throws {
        let catalog = InMemoryHostCatalog()
        let credentials = InMemoryCredentialStore()
        let viewModel = ConnectHostViewModel(catalog: catalog, credentialStore: credentials)

        viewModel.draft = HostDraft.validManualFixture()
        viewModel.draft.password = "secret"

        try await viewModel.saveDraft()

        let host = try XCTUnwrap(catalog.hosts.first)
        XCTAssertEqual(host.displayName, "dev")
        XCTAssertEqual(credentials.passwords[host.id], "secret")
    }
}

private final class InMemoryHostCatalog: HostCatalog {
    var hosts: [SavedHost] = []

    func load() throws -> [SavedHost] { hosts }

    func save(_ host: SavedHost) throws {
        hosts.removeAll { $0.id == host.id }
        hosts.append(host)
    }

    func delete(hostId: UUID) throws {
        hosts.removeAll { $0.id == hostId }
    }

    func markConnected(hostId: UUID, at date: Date) throws {
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        hosts[index].lastConnectedAt = date
    }

    func updatePaths(hostId: UUID, local: String?, remote: String?) throws {
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        if let local { hosts[index].lastLocalPath = local }
        if let remote { hosts[index].lastRemotePath = remote }
    }

    func setFavorite(hostId: UUID, isFavorite: Bool) throws {
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        hosts[index].isFavorite = isFavorite
    }
}

private extension HostDraft {
    static func validManualFixture() -> HostDraft {
        HostDraft(
            source: .manual,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            identityFile: nil,
            password: nil,
            keyPassphrase: nil,
            defaultRemotePath: nil,
            originSSHConfigAlias: nil,
            resolvedAt: nil,
            unsupportedOptions: []
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/ConnectHostViewModelTests
```

Expected: fails because `ConnectHostViewModel` and fakes are missing.

- [ ] **Step 3: Implement view model and fake credential store**

```swift
import Foundation

protocol CredentialStore {
    func savePassword(_ password: String, hostId: UUID) throws
    func loadPassword(hostId: UUID) throws -> String?
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws
    func loadKeyPassphrase(hostId: UUID) throws -> String?
    func deleteCredentials(hostId: UUID) throws
}

final class InMemoryCredentialStore: CredentialStore {
    var passwords: [UUID: String] = [:]
    var passphrases: [UUID: String] = [:]
    var deletedHostIds: [UUID] = []

    func savePassword(_ password: String, hostId: UUID) throws { passwords[hostId] = password }
    func loadPassword(hostId: UUID) throws -> String? { passwords[hostId] }
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws { passphrases[hostId] = passphrase }
    func loadKeyPassphrase(hostId: UUID) throws -> String? { passphrases[hostId] }
    func deleteCredentials(hostId: UUID) throws { deletedHostIds.append(hostId) }
}

@MainActor
final class ConnectHostViewModel: ObservableObject {
    @Published var draft = HostDraft(
        source: .manual,
        displayName: "",
        hostname: "",
        port: 22,
        username: NSUserName(),
        authType: .password,
        identityFile: nil,
        password: nil,
        keyPassphrase: nil,
        defaultRemotePath: nil,
        originSSHConfigAlias: nil,
        resolvedAt: nil,
        unsupportedOptions: []
    )

    private let catalog: HostCatalog
    private let credentialStore: CredentialStore

    init(catalog: HostCatalog, credentialStore: CredentialStore) {
        self.catalog = catalog
        self.credentialStore = credentialStore
    }

    func saveDraft() async throws {
        let host = try draft.makeSavedHost()
        try catalog.save(host)
        if let password = draft.password, !password.isEmpty {
            try credentialStore.savePassword(password, hostId: host.id)
        }
        if let passphrase = draft.keyPassphrase, !passphrase.isEmpty {
            try credentialStore.saveKeyPassphrase(passphrase, hostId: host.id)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransTests/ConnectHostViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add wetrans/UI/HostManagement/ConnectHostViewModel.swift wetrans/Security/CredentialStore.swift wetrans/Security/InMemoryCredentialStore.swift wetransTests/UI/ConnectHostViewModelTests.swift
git commit -m "Add connect host save flow"
```

## Task 8: Wire Minimal SwiftUI Host Management Views

**Files:**

- Create: `wetrans/UI/HostManagement/HostOnboardingViews.swift`
- Modify: `wetrans/App/wetransApp.swift`
- UI Test: `wetransUITests/HostOnboardingUITests.swift`

- [ ] **Step 1: Add UI smoke test**

```swift
import XCTest

final class HostOnboardingUITests: XCTestCase {
    func testConnectHostButtonIsVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Connect Host"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Run UI test to verify it fails**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransUITests/HostOnboardingUITests
```

Expected: fails because the view is not wired.

- [ ] **Step 3: Add minimal host management views**

```swift
import SwiftUI

struct HostSidebarView: View {
    @ObservedObject var viewModel: HostSidebarViewModel
    let onConnectHost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.groups.favorites.isEmpty &&
                viewModel.groups.recent.isEmpty &&
                viewModel.groups.myHosts.isEmpty {
                Text("No hosts yet")
                    .foregroundStyle(.secondary)
            }

            Button("Connect Host", action: onConnectHost)
                .accessibilityIdentifier("Connect Host")
        }
        .padding()
        .frame(minWidth: 220, alignment: .topLeading)
    }
}

struct ConnectHostDialogView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Host")
                .font(.headline)
            Button("Manual Add") {}
            Button("Select from SSH Config") {}
        }
        .padding()
        .frame(width: 360)
    }
}
```

- [ ] **Step 4: Wire app shell**

```swift
import SwiftUI

@main
struct wetransApp: App {
    @StateObject private var sidebarViewModel = HostSidebarViewModel()
    @State private var isShowingConnectHost = false

    var body: some Scene {
        WindowGroup {
            HostSidebarView(viewModel: sidebarViewModel) {
                isShowingConnectHost = true
            }
            .sheet(isPresented: $isShowingConnectHost) {
                ConnectHostDialogView()
            }
        }
    }
}
```

- [ ] **Step 5: Run UI test to verify it passes**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransUITests/HostOnboardingUITests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add wetrans/UI/HostManagement/HostOnboardingViews.swift wetrans/App/wetransApp.swift wetransUITests/HostOnboardingUITests.swift
git commit -m "Add host onboarding UI shell"
```

## Task 9: Final Verification

**Files:**

- Verify all files from this plan.

- [ ] **Step 1: Run all unit tests**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -skip-testing:wetransUITests
```

Expected: PASS.

- [ ] **Step 2: Run host onboarding UI tests**

Run:

```bash
xcodebuild test -scheme wetrans -destination 'platform=macOS' -only-testing:wetransUITests/HostOnboardingUITests
```

Expected: PASS.

- [ ] **Step 3: Inspect hosts.json manually in a debug run**

Run the app, save a host with a password, then inspect:

```bash
cat "$HOME/Library/Application Support/wetrans/hosts.json"
```

Expected:

- Host metadata is present.
- Password is not present.
- Private key passphrase is not present.

- [ ] **Step 4: Commit verification fixes if needed**

```bash
git status --short
git add <changed-files>
git commit -m "Verify host onboarding flow"
```

Expected: commit only if verification required fixes.

## Self-Review Notes

Spec coverage:

- Manual host creation: Tasks 1, 2, 3, 7, 8.
- SSH Config alias scanning: Task 4.
- SSH Config resolution and draft generation: Task 5.
- Sidebar grouping: Task 6.
- Credential boundary: Tasks 2, 7, 9.
- UI smoke path: Task 8.
- Deletion and favorite flows: Task 3 provides catalog behavior; Task 6 provides grouping behavior; full UI interactions can be expanded in the next UI-focused plan if needed.

Known limitation:

- This plan assumes M1/M2 baseline project and model files exist. If they do not, execute the project foundation and data model milestones first.
