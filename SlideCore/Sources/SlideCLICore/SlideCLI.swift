import Foundation

/// Minimal CLI entry point for the `slide` command.
/// When the Slide binary is invoked as "slide" (via symlink), it enters CLI mode.
public enum SlideCLI {
    /// Returns true if the current process should run in CLI mode.
    public static var isCLIMode: Bool {
        let args = CommandLine.arguments
        if args.contains("--cli") { return true }
        // Only exact lowercase "slide" (via symlink) triggers CLI mode
        // The app binary is "Slide" (capital S), so normal launches skip this
        return ProcessInfo.processInfo.processName == "slide"
    }

    /// Run the CLI, send the appropriate JSON-RPC request, print the result, and exit.
    public static func run() -> Never {
        var args = Array(CommandLine.arguments.dropFirst()) // drop binary name
        args.removeAll { $0 == "--cli" } // strip before AP sees it
        SlideCommand.main(args)
        exit(0) // unreachable: AP's main() calls exit
    }
}

/// Empty params for methods that take no arguments.
struct Empty: Codable {}
