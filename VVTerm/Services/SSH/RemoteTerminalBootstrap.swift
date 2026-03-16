import Foundation

struct RemoteTerminalEnvironmentVariable: Hashable, Sendable {
    let name: String
    let value: String
}

enum RemoteShellLaunchPlan: Hashable, Sendable {
    case shell
    case exec(String)
}

enum RemoteTerminalBootstrap {
    static let terminalType = "xterm-256color"
    static let termProgram = "vvterm"

    static func appVersion(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    static func terminalEnvironment(bundle: Bundle = .main) -> [RemoteTerminalEnvironmentVariable] {
        [
            RemoteTerminalEnvironmentVariable(name: "COLORTERM", value: "truecolor"),
            RemoteTerminalEnvironmentVariable(name: "TERM_PROGRAM", value: termProgram),
            RemoteTerminalEnvironmentVariable(name: "TERM_PROGRAM_VERSION", value: appVersion(bundle: bundle))
        ]
    }

    static func terminalEnvironmentNames(bundle: Bundle = .main) -> [String] {
        terminalEnvironment(bundle: bundle).map(\.name)
    }

    static func environmentExportScript(bundle: Bundle = .main) -> String {
        let assignments = terminalEnvironment(bundle: bundle)
            .map { "\($0.name)=\(shellQuoted($0.value))" }
            .joined(separator: " ")
        return "export \(assignments);"
    }

    static func defaultLoginShellCommand() -> String {
        """
        if [ -n "$SHELL" ]; then exec "$SHELL" -l; fi;
        if command -v bash >/dev/null 2>&1; then exec bash -l; fi;
        if command -v zsh >/dev/null 2>&1; then exec zsh -l; fi;
        exec sh -l
        """
    }

    static func launchPlan(startupCommand: String?, bundle: Bundle = .main) -> RemoteShellLaunchPlan {
        let command = trimmedStartupCommand(startupCommand) ?? defaultLoginShellCommand()
        let script = prefixedScript(for: command, bundle: bundle)
        return .exec(wrapPOSIXShellCommand(script))
    }

    static func moshStartupScript(startCommand: String?, bundle: Bundle = .main) -> String {
        let command = trimmedStartupCommand(startCommand)
            .flatMap { unwrapPOSIXShellInvocationIfNeeded($0) ?? $0 }
            ?? defaultLoginShellCommand()
        return prefixedScript(for: command, bundle: bundle)
    }

    static func wrapPOSIXShellCommand(_ script: String) -> String {
        "/bin/sh -lc \(shellQuoted(script))"
    }

    static func shellQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func shellPathExport() -> String {
        "export PATH=\"\(shellPathValue())\""
    }

    static func tmuxUpdateEnvironmentVariables(bundle: Bundle = .main) -> [String] {
        ["LANG", "LC_ALL", "LC_CTYPE"] + terminalEnvironmentNames(bundle: bundle)
    }

    static func tmuxArrayOptionCommands(option: String, values: [String]) -> [String] {
        let reset = "set -gu \(option)"
        let assignments = values.enumerated().map { index, value in
            "set -g \(option)[\(index)] \"\(value)\""
        }
        return [reset] + assignments
    }

    static func tmuxEnvironmentCommands(bundle: Bundle = .main) -> [String] {
        terminalEnvironment(bundle: bundle).map { variable in
            "set-environment -g \(variable.name) \"\(variable.value)\""
        }
    }

    private static func prefixedScript(for command: String, bundle: Bundle = .main) -> String {
        "\(environmentExportScript(bundle: bundle)) \(command)"
    }

    private static func trimmedStartupCommand(_ startupCommand: String?) -> String? {
        let trimmed = startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unwrapPOSIXShellInvocationIfNeeded(_ command: String) -> String? {
        let prefixes = ["sh -lc ", "/bin/sh -lc "]
        guard let prefix = prefixes.first(where: { command.hasPrefix($0) }) else {
            return nil
        }

        let payload = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }

        if payload.hasPrefix("'"), payload.hasSuffix("'"), payload.count >= 2 {
            let start = payload.index(after: payload.startIndex)
            let end = payload.index(before: payload.endIndex)
            let quoted = String(payload[start..<end])
            return quoted.replacingOccurrences(of: "'\\''", with: "'")
        }

        if payload.hasPrefix("\""), payload.hasSuffix("\""), payload.count >= 2 {
            let start = payload.index(after: payload.startIndex)
            let end = payload.index(before: payload.endIndex)
            let quoted = String(payload[start..<end])
            let unescapedQuotes = quoted.replacingOccurrences(of: "\\\"", with: "\"")
            return unescapedQuotes.replacingOccurrences(of: "\\\\", with: "\\")
        }

        return payload
    }

    private static func shellPathValue() -> String {
        let paths = [
            "$HOME/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin",
            "/snap/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return paths.joined(separator: ":") + ":$PATH"
    }
}
