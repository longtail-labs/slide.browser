import Foundation
import SlideCLICore

/// Installs the `slide` CLI symlink and Claude Code skill file.
public enum CLIInstaller {
    private static let binDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".slide/bin")
    private static let symlink = binDir.appendingPathComponent("slide")

    private static let skillDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills/slide")
    private static let skillFile = skillDir.appendingPathComponent("SKILL.md")

    private static let hooksDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    private static let hooksFile = hooksDir.appendingPathComponent("hooks.json")

    /// Install CLI symlink and skill file if not already present.
    public static func installIfNeeded() {
        installSymlink()
        installSkill()
    }

    // MARK: - Symlink

    private static func installSymlink() {
        let fm = FileManager.default

        // Create ~/.slide/bin/
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        // Find the current app binary
        guard let executablePath = Bundle.main.executablePath else {
            print("[CLIInstaller] Cannot find executable path")
            return
        }

        // Remove existing symlink if it points somewhere different
        if let existing = try? fm.destinationOfSymbolicLink(atPath: symlink.path) {
            if existing == executablePath {
                return // already correct
            }
            try? fm.removeItem(at: symlink)
        }

        do {
            try fm.createSymbolicLink(atPath: symlink.path, withDestinationPath: executablePath)
            // Make executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: symlink.path)
            print("[CLIInstaller] Installed CLI symlink: \(symlink.path) -> \(executablePath)")
        } catch {
            print("[CLIInstaller] Failed to create symlink: \(error)")
        }
    }

    // MARK: - Claude Code Skill

    private static func installSkill() {
        let fm = FileManager.default

        try? fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillContent = """
        ---
        name: slide
        description: Control the Slide workspace - open pages, create notes, manage terminals
        allowed-tools: Bash(slide:*)
        ---

        # Slide Workspace Control

        When running inside a Slide terminal, you have access to the `slide` CLI.

        ## Environment
        - $SLIDE_OBJECT_ID — your terminal's object ID
        - $SLIDE_PROJECT_ID — current project ID
        - $SLIDE_PROJECT_NAME — current project name

        ## Commands

        ### Object Management
        - `slide object open --type browser --url <url>` — open a web page
        - `slide object open --type note --content "..."` — create a note
        - `slide object open --type terminal --cwd <dir>` — open a new terminal
        - `slide object open --type code-editor --url <filepath>` — open a code editor
        - `slide object focus <id>` — focus an object
        - `slide object close <id>` — close an object
        - `slide object rename "$SLIDE_OBJECT_ID" --title "..."` — rename an object
        - `slide object list [--project <id>]` — list objects

        ### Activity Indicators
        - `slide object start "$SLIDE_OBJECT_ID"` — show working indicator (pulsing blue)
        - `slide object stop "$SLIDE_OBJECT_ID"` — clear working indicator
        - `slide object stop "$SLIDE_OBJECT_ID" --badge 1` — clear indicator + set badge
        - `slide object attention "$SLIDE_OBJECT_ID"` — show needs-attention indicator (amber)
        - `slide object badge "$SLIDE_OBJECT_ID" --count <n>` — set badge count

        ### Notifications
        - `slide notify --title "..." --body "..."` — show a toast notification
        - `slide notify --title "..." --object "$SLIDE_OBJECT_ID"` — toast with "Go to" action

        ### Projects
        - `slide project list` — list all projects
        - `slide project select <id>` — switch to a project

        ### Status
        - `slide status` — check if Slide is running
        - `slide identify` — show current context
        """

        do {
            try skillContent.write(to: skillFile, atomically: true, encoding: .utf8)
            print("[CLIInstaller] Installed Claude Code skill: \(skillFile.path)")
        } catch {
            print("[CLIInstaller] Failed to write skill file: \(error)")
        }
    }

    /// Install Claude Code hooks for activity lifecycle.
    /// Call this explicitly when the user opts in.
    public static func installHooks() {
        let fm = FileManager.default
        try? fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        // Read existing hooks or start fresh
        var hooks: [String: Any] = [:]
        if fm.fileExists(atPath: hooksFile.path),
           let data = try? Data(contentsOf: hooksFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hooks = existing
        }

        // Only install if not already present
        if hooks["hooks"] != nil {
            print("[CLIInstaller] Hooks already configured, skipping")
            return
        }

        let hooksConfig: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["hooks": [["type": "command",
                                "command": "command -v slide &>/dev/null && slide object start \"$SLIDE_OBJECT_ID\""]]]
                ],
                "Stop": [
                    ["hooks": [["type": "command",
                                "command": "command -v slide &>/dev/null && slide object stop \"$SLIDE_OBJECT_ID\" --badge 1"]]]
                ],
                "Notification": [
                    ["matcher": "permission_prompt",
                     "hooks": [["type": "command",
                                "command": "command -v slide &>/dev/null && slide object attention \"$SLIDE_OBJECT_ID\""]]],
                    ["matcher": "idle_prompt",
                     "hooks": [["type": "command",
                                "command": "command -v slide &>/dev/null && slide object stop \"$SLIDE_OBJECT_ID\" --badge 1"]]]
                ]
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: hooksConfig, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: hooksFile)
            print("[CLIInstaller] Installed Claude Code hooks: \(hooksFile.path)")
        } catch {
            print("[CLIInstaller] Failed to write hooks file: \(error)")
        }
    }
}
