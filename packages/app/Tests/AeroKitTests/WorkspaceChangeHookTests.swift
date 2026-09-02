import XCTest
@testable import AeroKitCore

final class WorkspaceChangeHookTests: XCTestCase {
    /// A double quote.
    private let dq = "\""

    func testClassifyWithoutConfigIsAbsent() {
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: nil), .absent)
    }

    func testClassifyWithoutKeyIsAbsent() {
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: "gap = 4\n"), .absent)
    }

    func testClassifyForeignHookNeedsMerge() {
        let text = "exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --trigger change']"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: text), .needsMerge)
    }

    func testClassifyAeroKitHookIsWired() {
        let text = "exec-on-workspace-change = ['/opt/AeroKit.app/MacOS/AeroKit', '--workspace-changed']\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: text), .wired)
    }

    func testCommentedOutKeyIsAbsent() {
        let text = "# exec-on-workspace-change = ['/opt/AeroKit', '--workspace-changed']\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: text), .absent)
    }

    func testTrailingCommentStillClassifies() {
        let foreign = "exec-on-workspace-change = ['/bin/bash', '-c', 'x'] # sketchybar\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: foreign), .needsMerge)
        let wired = "exec-on-workspace-change = ['/opt/AeroKit', '--workspace-changed'] # note\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: wired), .wired)
    }

    func testMultilineArrayIsNeedsMergeNotAbsent() {
        // A multi-line array is an assignment this parser can't merge; the
        // pane must not suggest a fresh paste line (duplicate TOML key).
        let text = "exec-on-workspace-change = [\n  '/bin/bash', '-c', 'x'\n]\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: text), .needsMerge)
    }

    func testTrailingCommentCannotFakeWired() {
        // The invocation only counts inside the argv array, never in a
        // trailing comment.
        let text = "exec-on-workspace-change = ['/bin/bash', '-c', 'x'] # TODO add --workspace-changed\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: text), .needsMerge)
    }

    func testMultilineWiredArrayClassifiesWired() {
        let text = "exec-on-workspace-change = [\n  '/opt/AeroKit', '--workspace-changed'\n]\n"
        XCTAssertEqual(WorkspaceChangeHook.classify(configText: text), .wired)
    }

    func testArrayFollowedByCommentLinesStillMerges() {
        // The real-world layout that broke the first attempt: the array's
        // own line, then comment lines using double quotes. The \s in the
        // trailing-whitespace slot must never cross newlines.
        let config = "exec-on-workspace-change = ['/bin/bash', '-lc', "
            + "'~/dotfiles/scripts/aerospace-workspace-snapshot-request.sh workspace-change']\n"
            + "\n# You can effectively turn off macOS \"Hide application\" (cmd-h) feature\n"
            + "automatically-unhide-macos-hidden-apps = false\n"
        let merged = WorkspaceChangeHook.mergedHookLine(
            configText: config,
            executablePath: "/Users/jomatsuda/Applications/AeroKit Dev.app/Contents/MacOS/AeroKit"
        )
        XCTAssertEqual(
            merged,
            "exec-on-workspace-change = ['/bin/bash', '-lc', "
                + "'~/dotfiles/scripts/aerospace-workspace-snapshot-request.sh workspace-change; "
                + "\"/Users/jomatsuda/Applications/AeroKit Dev.app/Contents/MacOS/AeroKit\" "
                + "--workspace-changed']"
        )
    }

    func testHookLineFormat() {
        XCTAssertEqual(
            WorkspaceChangeHook.hookLine(executablePath: "/Applications/AeroKit.app/Contents/MacOS/AeroKit"),
            "exec-on-workspace-change = ['/Applications/AeroKit.app/Contents/MacOS/AeroKit', "
                + "'--workspace-changed']"
        )
    }

    func testMergesIntoExistingShellCommand() {
        let config = "gap = 4\n"
            + "exec-on-workspace-change = ['/bin/bash', '-lc', '~/dotfiles/scripts/snapshot.sh workspace-change']\n"
            + "mode.main.binding = {}\n"
        let merged = WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit")
        XCTAssertEqual(
            merged,
            "exec-on-workspace-change = ['/bin/bash', '-lc', "
                + "'~/dotfiles/scripts/snapshot.sh workspace-change; /opt/AeroKit --workspace-changed']"
        )
    }

    func testMergedLineKeepsDoubleQuoteStyle() {
        let config = "exec-on-workspace-change = [\"/bin/bash\", \"-c\", \"echo hi\"]\n"
        let merged = WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit")
        XCTAssertEqual(
            merged,
            "exec-on-workspace-change = [\"/bin/bash\", \"-c\", \"echo hi; /opt/AeroKit --workspace-changed\"]"
        )
    }

    func testNonShellHookHasNoMergedLine() {
        let config = "exec-on-workspace-change = ['some-binary', '--flag']\n"
        XCTAssertNil(WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit"))
    }

    func testMultilineArrayHasNoMergedLine() {
        let config = "exec-on-workspace-change = [\n  '/bin/bash', '-c', 'x'\n]\n"
        XCTAssertNil(WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit"))
    }

    func testSpacedExecutablePathMergesShellQuoted() {
        let config = "exec-on-workspace-change = ['/bin/bash', '-c', 'echo hi']\n"
        let merged = WorkspaceChangeHook.mergedHookLine(
            configText: config,
            executablePath: "/opt/Apps AeroKit/AeroKit"
        )
        XCTAssertEqual(
            merged,
            "exec-on-workspace-change = ['/bin/bash', '-c', "
                + "'echo hi; \"/opt/Apps AeroKit/AeroKit\" --workspace-changed']"
        )
    }

    func testPathWithDoubleQuoteBailsMerge() {
        let config = "exec-on-workspace-change = ['/bin/bash', '-c', 'echo hi']\n"
        XCTAssertNil(
            WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/A\"eroKit")
        )
    }

    func testMergesIntoRealWorldDotfilesHook() {
        let config = "exec-on-workspace-change = ['/bin/bash', '-lc', "
            + "'~/dotfiles/scripts/aerospace-workspace-snapshot-request.sh workspace-change']\n"
        let merged = WorkspaceChangeHook.mergedHookLine(
            configText: config,
            executablePath: "/Users/jomatsuda/Applications/AeroKit Dev.app/Contents/MacOS/AeroKit"
        )
        let devPath = "/Users/jomatsuda/Applications/AeroKit Dev.app/Contents/MacOS/AeroKit"
        let quotedDevPath = dq + devPath + dq
        let expected =
            "exec-on-workspace-change = ['/bin/bash', '-lc', "
                + "'~/dotfiles/scripts/aerospace-workspace-snapshot-request.sh workspace-change; "
                + quotedDevPath + " --workspace-changed']"
        XCTAssertEqual(merged, expected)
    }

    func testLongFlagBailsMerge() {
        let config = "exec-on-workspace-change = ['/bin/bash', '--norc', 'echo hi']\n"
        XCTAssertNil(WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit"))
    }

    func testCommandWithCommentBailsMerge() {
        let config = "exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --trigger x # note']\n"
        XCTAssertNil(WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit"))
    }

    func testCommandEndingInBackgroundBailsMerge() {
        let config = "exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --reload &']\n"
        XCTAssertNil(WorkspaceChangeHook.mergedHookLine(configText: config, executablePath: "/opt/AeroKit"))
    }

    func testHookLineQuotesApostrophePathsAsBasicStrings() {
        let line = WorkspaceChangeHook.hookLine(executablePath: "/Users/o'brien/Apps/AeroKit")
        XCTAssertTrue(line.contains("\"/Users/o'brien/Apps/AeroKit\""))
        XCTAssertTrue(line.contains("\"--workspace-changed\"]"))
    }
}
