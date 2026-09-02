import Foundation

/// Read-only inspection of AeroSpace's `exec-on-workspace-change` hook so
/// the settings pane can show the exact wiring line for this install.
/// AeroKit never writes the user's config: it composes the correct line —
/// merged into the existing hook when one already runs — and the user
/// pastes it themselves.
public enum WorkspaceChangeHook {
    /// The classification of the user's AeroSpace config.
    public enum Wiring: Equatable, Sendable {
        /// An exec-on-workspace-change invocation of this binary exists.
        case wired
        /// The key exists but doesn't call AeroKit — the pane offers a
        /// merged replacement line when the hook is a recognized shell
        /// command, manual instructions otherwise.
        case needsMerge
        /// No exec-on-workspace-change anywhere (or no config file at all).
        case absent
    }

    /// Read-only snapshot of the hook state for the settings pane.
    public struct Status: Equatable, Sendable {
        public var wiring: Wiring
        public var configPath: String?
        /// The existing hook rewritten to chain AeroKit; nil when the hook
        /// is absent or not a recognized `shell -c` command.
        public var mergedHookLine: String?
        /// The raw existing assignment line (when one exists) — included
        /// verbatim in the manual-merge AI prompt.
        public var existingHookLine: String?
        /// For a fresh two-element hook line, the AeroKit path it names —
        /// used to warn when the config still points at a moved or deleted
        /// binary. nil for merged inline calls, where the path is embedded
        /// in a shell string and can't be told apart reliably.
        public var wiredPath: String?
        /// Whether `wiredPath` exists and is executable; true when unknown.
        public var wiredPathExists: Bool
    }

    /// Marker that splits "the hook calls AeroKit" from "the key exists for
    /// something else (SketchyBar, snapshot requests, …)".
    public static let invocation = "--workspace-changed"
    private static let key = "exec-on-workspace-change"

    // MARK: - Classification (pure, unit-tested)

    /// Line-scoped on purpose: a commented-out key means "not wired", and
    /// TOML allows the key only once, so the first active assignment is
    /// authoritative. A trailing comment after the array is fine; a
    /// multi-line array (no `]` on the key's line) is an assignment this
    /// parser can't read — classify() routes it to manual instructions
    /// rather than "not wired", so the pane never suggests a duplicate key.
    private static func hookLineText(in configText: String) -> String? {
        // [^\]\n] keeps the match on the key's line: a multi-line array is
        // an assignment the merger can't reconstruct.
        // [ \t] (not \s) after the array: \s would let the match cross
        // newlines and swallow the comment lines that follow it.
        let pattern = "(?m)^\\s*" + key + "\\s*=\\s*\\[[^\\]\\n]*\\][ \\t]*(?:#.*)?$"
        guard let range = configText.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(configText[range])
    }

    /// The key is assigned in a layout this parser can't read (e.g. a
    /// multi-line array) — still an assignment, so never "absent".
    private static func hasAssignmentLine(in configText: String) -> Bool {
        configText.range(of: "(?m)^\\s*" + key + "\\s*=", options: .regularExpression) != nil
    }

    public static func classify(configText: String?) -> Wiring {
        guard let configText else {
            return .absent
        }
        if let line = hookLineText(in: configText) {
            // Judge only the argv array — a trailing comment mentioning the
            // invocation must not fake "wired".
            guard let open = line.firstIndex(of: "["),
                  let close = line[open...].firstIndex(of: "]")
            else {
                return .needsMerge
            }
            return callsAeroKit(line[open ... close]) ? .wired : .needsMerge
        }
        if hasAssignmentLine(in: configText) {
            // Multi-line array: slice from the key to the first `]` across
            // lines so a wired config isn't misread as foreign.
            guard let keyRange = configText.range(of: "(?m)^\\s*" + key + "\\s*=", options: .regularExpression) else {
                return .needsMerge
            }
            let afterKey = configText[keyRange.upperBound...]
            guard let close = afterKey.firstIndex(of: "]") else {
                return .needsMerge
            }
            return callsAeroKit(afterKey[..<close]) ? .wired : .needsMerge
        }
        return .absent
    }

    /// Token-level check: the invocation counts only as its own shell word
    /// ("…; /path --workspace-changed"). A bare mention inside a longer
    /// flag ("--workspace-changed-disabled") or an arbitrary argument does
    /// not — the failure direction is always the safe one: manual
    /// instructions instead of a false "Configured".
    private static func callsAeroKit(_ slice: some StringProtocol) -> Bool {
        slice
            .split { $0 == " " || $0 == "\t" || $0 == ";" || $0 == "'" || $0 == "\"" }
            .contains { $0 == invocation }
    }

    /// The hook line a fresh config needs. Paths containing a single quote
    /// can't live in a TOML literal string, so those switch to basic-string
    /// quoting.
    public static func hookLine(executablePath: String) -> String {
        if executablePath.contains("'") {
            // Basic strings escape backslashes and quotes.
            let escaped = executablePath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\(key) = [\"\(escaped)\", \"\(invocation)\"]"
        }
        return "\(key) = ['\(executablePath)', '\(invocation)']"
    }

    /// Reads the config and classifies it; also composes the merged
    /// replacement line when an existing hook is recognizable. Blocking
    /// file IO — call off the main actor.
    public static func status(executablePath: String) -> Status {
        let configPath = configFilePath()
        let text = configPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        let wiring = classify(configText: text)
        let line = text.flatMap { hookLineText(in: $0) }

        // "Configured" on paper but a hook that spawns nothing: a fresh
        // two-element line naming a binary that has since moved or been
        // deleted (e.g. a Homebrew path after a reinstall).
        var wiredPath: String?
        if wiring == .wired, let line {
            let elements = quotedElements(in: line)
            if elements.count == 2 {
                wiredPath = elements[0].content
            }
        }
        let wiredPathExists = wiredPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? true

        return Status(
            wiring: wiring,
            configPath: configPath,
            mergedHookLine: text.flatMap { mergedHookLine(configText: $0, executablePath: executablePath) },
            existingHookLine: wiring == .needsMerge ? line : nil,
            wiredPath: wiredPath,
            wiredPathExists: wiredPathExists
        )
    }

    /// The merged replacement for an existing hook line, with AeroKit
    /// chained after the original command ("…; AeroKit
    /// --workspace-changed"). AeroSpace executes the hook array as one
    /// command's argv, so chaining inside the shell string is the only
    /// non-destructive merge. Returns nil when the layout isn't a
    /// recognized single-line `shell -c` command — the caller then shows
    /// manual instructions instead of guessing at TOML it doesn't
    /// fully understand.
    public static func mergedHookLine(configText: String, executablePath: String) -> String? {
        // The chain lands inside a shell command string, where the path is
        // no longer a bare argv element. A path the shell can carry bare
        // (charset-checked) is appended as-is; anything else — e.g. the
        // space in "AeroKit Dev.app" — is wrapped in shell double quotes,
        // which a TOML literal-string element passes through untouched.
        // Paths that would survive neither form (quotes, backslashes,
        // shell expansions) bail to manual instructions.
        let shellSafe = isShellSafePath(executablePath)
        guard let line = hookLineText(in: configText) else {
            return nil
        }
        let elements = quotedElements(in: line)
        guard elements.count == 3 else {
            return nil
        }
        let shell = elements[0]
        let flag = elements[1]
        let command = elements[2]
        // Short flag clusters only ("-lc"): a long option like "--norc"
        // means the third element isn't a shell command string.
        guard shell.content.hasSuffix("sh"),
              flag.content.range(of: "^-[a-zA-Z]*c[a-zA-Z]*$", options: .regularExpression) != nil,
              command.quote != "\"" || !command.content.contains("\\")
        else {
            return nil
        }

        // Bail on anything that could swallow or break the appended chain:
        // comments, backgrounding, dangling separators, or an exec that
        // replaces the shell before the chain runs.
        let trimmed = command.content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.contains("#"),
              !trimmed.hasPrefix("exec "),
              !trimmed.hasSuffix("&"),
              !trimmed.hasSuffix(";"),
              !trimmed.hasSuffix("|")
        else {
            return nil
        }

        // Shell-level quoting for a path the bare charset check rejects:
        // double quotes carry spaces safely, but only when the path hides
        // no shell expansions and the TOML element can represent them.
        let chain: String
        if shellSafe {
            chain = "; \(executablePath) \(invocation)"
        } else if command.quote == "'",
                  !executablePath.contains("\""),
                  !executablePath.contains("\\"),
                  !executablePath.contains("$"),
                  !executablePath.contains("`")
        {
            chain = "; \"\(executablePath)\" \(invocation)"
        } else {
            return nil
        }

        // A stray quote (or, in a basic string, a backslash sequence) would
        // end or corrupt the TOML string early.
        switch command.quote {
        case "'" where chain.contains("'"):
            return nil
        case "\"" where chain.contains("\"") || chain.contains("\\"):
            return nil
        default:
            break
        }

        let joined = elements.map { element -> String in
            let content = element == command ? element.content + chain : element.content
            return "\(element.quote)\(content)\(element.quote)"
        }
        .joined(separator: ", ")
        return "\(key) = [\(joined)]"
    }

    /// Paths embeddable in a shell command string without quoting.
    static func isShellSafePath(_ path: String) -> Bool {
        path.range(of: "^[A-Za-z0-9/._+@-]+$", options: .regularExpression) != nil
    }

    private struct QuotedElement: Equatable {
        /// The TOML quote style the element was written with.
        var quote: Character
        var content: String
    }

    private static func quotedElements(in line: String) -> [QuotedElement] {
        let pattern = #"'[^']*'|"(?:[^"\\]|\\.)*""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: line) else {
                return nil
            }
            let literal = String(line[matchRange])
            guard let quote = literal.first else {
                return nil
            }
            return QuotedElement(quote: quote, content: String(literal.dropFirst().dropLast()))
        }
    }

    // MARK: - Filesystem (read-only; blocking, call off the main actor)

    /// AeroSpace's config lookup order: the home-dotfile first, then the
    /// XDG location. nil when neither exists.
    public static func configFilePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String? {
        let xdgConfig = environment["XDG_CONFIG_HOME"].map { "\($0)/aerospace/aerospace.toml" }
            ?? "\(home)/.config/aerospace/aerospace.toml"
        let candidates = ["\(home)/.aerospace.toml", xdgConfig]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// This binary's own absolute path — what the hook must name, because
    /// AeroSpace spawns it directly with no shell and no PATH lookup.
    public static func currentExecutablePath() -> String {
        if let path = Bundle.main.executableURL?.path {
            return path
        }
        return CommandLine.arguments.first ?? "/Applications/AeroKit.app/Contents/MacOS/AeroKit"
    }
}
