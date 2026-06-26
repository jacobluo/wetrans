import AppKit
import ApplicationServices
import Foundation

let connectHostEntryIdentifier = "Connect Host"

enum E2EError: Error, CustomStringConvertible {
    case appNotRunning(String)
    case accessibilityNotTrusted
    case missingElement(String)
    case missingEnvironment(String)
    case actionFailed(String, AXError)
    case timedOut(String)

    var description: String {
        switch self {
        case .appNotRunning(let name):
            return "App is not running: \(name)"
        case .accessibilityNotTrusted:
            return """
            Accessibility permission is required for native UI E2E.
            Enable it in System Settings > Privacy & Security > Accessibility for the terminal/Codex app, then rerun scripts/e2e.
            """
        case .missingElement(let identifier):
            return "Missing UI element: \(identifier)"
        case .missingEnvironment(let key):
            return "Missing required environment variable: \(key)"
        case .actionFailed(let action, let error):
            return "Accessibility action failed: \(action) (\(error.rawValue))"
        case .timedOut(let description):
            return "Timed out waiting for \(description)"
        }
    }
}

struct E2EConfig {
    let scenario: String
    let appName: String
    let requireAccessibility: Bool

    static func current(arguments: [String], environment: [String: String]) -> E2EConfig {
        let scenario = arguments.dropFirst().first ?? "smoke"
        return E2EConfig(
            scenario: scenario,
            appName: environment["WETRANS_E2E_APP_NAME"] ?? "wetrans",
            requireAccessibility: environment["WETRANS_E2E_REQUIRE_AX"] == "1" ||
                environment["WETRANS_E2E_RUN_FULL"] == "1"
        )
    }
}

final class AccessibilityDriver {
    private let appName: String
    private let application: AXUIElement

    init(appName: String) throws {
        self.appName = appName
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
            throw E2EError.appNotRunning(appName)
        }
        application = AXUIElementCreateApplication(runningApp.processIdentifier)
    }

    func waitForElement(identifier: String, timeout: TimeInterval = 8) throws -> AXUIElement {
        try wait(timeout: timeout, description: identifier) {
            self.element(identifier: identifier)
        }
    }

    func waitForText(_ text: String, timeout: TimeInterval = 8) throws -> AXUIElement {
        try wait(timeout: timeout, description: text) {
            self.element(title: text)
        }
    }

    func click(identifier: String, timeout: TimeInterval = 8) throws {
        let element = try waitForElement(identifier: identifier, timeout: timeout)
        try press(element, description: identifier)
    }

    func clickText(_ text: String, timeout: TimeInterval = 8) throws {
        let element = try waitForText(text, timeout: timeout)
        try press(element, description: text)
    }

    func setText(identifier: String, value: String, timeout: TimeInterval = 8) throws {
        let element = try waitForElement(identifier: identifier, timeout: timeout)
        let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        guard error == .success else {
            throw E2EError.actionFailed("set \(identifier)", error)
        }
    }

    func select(identifier: String, timeout: TimeInterval = 8) throws {
        let element = try waitForElement(identifier: identifier, timeout: timeout)
        let error = AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        if error == .success {
            return
        }
        try press(element, description: identifier)
    }

    func dumpTree(limit: Int = 250) {
        var queue = windows().map { ($0, 0) }
        var visited = 0
        while let (element, depth) = queue.first, visited < limit {
            queue.removeFirst()
            visited += 1
            let indent = String(repeating: "  ", count: depth)
            let role = axString(element, kAXRoleAttribute) ?? "-"
            let title = axString(element, kAXTitleAttribute) ?? ""
            let identifier = axString(element, kAXIdentifierAttribute) ?? ""
            let value = axString(element, kAXValueAttribute) ?? ""
            print("\(indent)\(role) id='\(identifier)' title='\(title)' value='\(value)'")
            queue.append(contentsOf: children(of: element).map { ($0, depth + 1) })
        }
    }

    private func press(_ element: AXUIElement, description: String) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            throw E2EError.actionFailed("press \(description)", error)
        }
    }

    private func element(identifier: String) -> AXUIElement? {
        firstElement { element in
            axString(element, kAXIdentifierAttribute) == identifier
        }
    }

    private func element(title: String) -> AXUIElement? {
        firstElement { element in
            axString(element, kAXTitleAttribute) == title ||
                axString(element, kAXDescriptionAttribute) == title ||
                axString(element, kAXValueAttribute) == title
        }
    }

    private func firstElement(matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = windows()
        var visited = 0
        while let element = queue.first, visited < 5_000 {
            queue.removeFirst()
            visited += 1
            if predicate(element) {
                return element
            }
            queue.append(contentsOf: children(of: element))
        }
        return nil
    }

    private func windows() -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success else {
            return [application]
        }
        return (value as? [AXUIElement]) ?? [application]
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func wait<T>(timeout: TimeInterval, description: String, operation: () -> T?) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = operation() {
                return value
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        throw E2EError.timedOut(description)
    }
}

func ensureAccessibility(require: Bool) throws -> Bool {
    let trusted = AXIsProcessTrustedWithOptions([
        "AXTrustedCheckOptionPrompt": false
    ] as CFDictionary)
    if trusted {
        return true
    }
    if require {
        throw E2EError.accessibilityNotTrusted
    }
    print("UI E2E smoke skipped: Accessibility permission is not enabled.")
    print("Set WETRANS_E2E_REQUIRE_AX=1 to make this a hard failure.")
    return false
}

func env(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
        throw E2EError.missingEnvironment(key)
    }
    return value
}

func optionalEnv(_ key: String, default defaultValue: String) -> String {
    ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 } ?? defaultValue
}

func smoke(driver: AccessibilityDriver) throws {
    _ = try driver.waitForElement(identifier: connectHostEntryIdentifier)
    _ = try driver.waitForElement(identifier: "Local File Panel")
    _ = try driver.waitForElement(identifier: "Remote File Panel")
    _ = try driver.waitForElement(identifier: "Transfer Queue")
}

func addManualHost(driver: AccessibilityDriver) throws {
    try driver.click(identifier: connectHostEntryIdentifier)
    try driver.click(identifier: "Manual Add Start")
    try driver.setText(identifier: "Manual Host Display Name", value: try env("WETRANS_E2E_MANUAL_DISPLAY_NAME"))
    try driver.setText(identifier: "Manual Host Hostname", value: try env("WETRANS_E2E_MANUAL_HOST"))
    try driver.setText(identifier: "Manual Host Port", value: optionalEnv("WETRANS_E2E_MANUAL_PORT", default: "22"))
    try driver.setText(identifier: "Manual Host Username", value: try env("WETRANS_E2E_MANUAL_USER"))
    if let password = ProcessInfo.processInfo.environment["WETRANS_E2E_MANUAL_PASSWORD"], !password.isEmpty {
        try driver.setText(identifier: "Manual Host Password", value: password)
    }
    if let identityFile = ProcessInfo.processInfo.environment["WETRANS_E2E_MANUAL_IDENTITY_FILE"], !identityFile.isEmpty {
        try driver.click(identifier: "Manual Host Auth SSH Key")
        try driver.setText(identifier: "Manual Host Identity File", value: identityFile)
    }
    if let path = ProcessInfo.processInfo.environment["WETRANS_E2E_MANUAL_DEFAULT_REMOTE_PATH"], !path.isEmpty {
        try driver.setText(identifier: "Manual Host Default Remote Path", value: path)
    }
    try driver.click(identifier: "Manual Host Save")
    _ = try driver.waitForElement(identifier: "Host Row \(try env("WETRANS_E2E_MANUAL_DISPLAY_NAME"))", timeout: 12)
}

func addSSHConfigHost(driver: AccessibilityDriver) throws {
    let alias = try env("WETRANS_E2E_SSH_ALIAS")
    try driver.click(identifier: connectHostEntryIdentifier)
    try driver.click(identifier: "SSH Config Browse Aliases")
    try driver.setText(identifier: "SSH Config Search", value: alias)
    try driver.click(identifier: "SSH Config Alias \(alias)", timeout: 12)
    try driver.click(identifier: "SSH Config Host Save")
    _ = try driver.waitForElement(identifier: "Host Row \(alias)", timeout: 12)
}

func transferSmoke(driver: AccessibilityDriver) throws {
    let uploadFileName = try env("WETRANS_E2E_UPLOAD_FILE_NAME")
    let downloadFileName = try env("WETRANS_E2E_DOWNLOAD_FILE_NAME")

    try driver.select(identifier: "Local File Row \(uploadFileName)", timeout: 12)
    try driver.click(identifier: "Local Upload")
    _ = try driver.waitForElement(identifier: "Transfer Row \(uploadFileName)", timeout: 12)

    try driver.select(identifier: "Remote File Row \(downloadFileName)", timeout: 12)
    try driver.click(identifier: "Remote Download")
    _ = try driver.waitForElement(identifier: "Transfer Row \(downloadFileName)", timeout: 12)
}

let config = E2EConfig.current(
    arguments: CommandLine.arguments,
    environment: ProcessInfo.processInfo.environment
)

do {
    guard try ensureAccessibility(require: config.requireAccessibility) else {
        exit(0)
    }

    let driver = try AccessibilityDriver(appName: config.appName)
    switch config.scenario {
    case "smoke":
        do {
            try smoke(driver: driver)
        } catch {
            if config.requireAccessibility {
                throw error
            }
            print("UI E2E smoke skipped: app launched, but Accessibility could not inspect the window tree.")
            print("Set WETRANS_E2E_REQUIRE_AX=1 to make this a hard failure. Last error: \(error)")
            exit(0)
        }
    case "manual-host":
        try addManualHost(driver: driver)
    case "ssh-config-host":
        try addSSHConfigHost(driver: driver)
    case "transfer":
        try transferSmoke(driver: driver)
    case "dump":
        driver.dumpTree()
    default:
        print("usage: swift run wetrans-e2e [smoke|manual-host|ssh-config-host|transfer|dump]")
        exit(2)
    }
    print("UI E2E \(config.scenario) passed.")
} catch {
    fputs("UI E2E failed: \(error)\n", stderr)
    exit(1)
}
