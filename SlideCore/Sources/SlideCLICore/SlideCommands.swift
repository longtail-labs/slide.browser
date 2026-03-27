import ArgumentParser
import Foundation

// MARK: - Helpers

/// Send a JSON-RPC call to the Slide app and return the pretty-printed result.
func callMethod<P: Encodable>(_ method: SlideMethod, params: P) throws -> String {
    let socketPath = ProcessInfo.processInfo.environment["SLIDE_SOCKET_PATH"]
        ?? CommandServer.socketPath
    let client = SocketClient(socketPath: socketPath)
    let request = JSONRPCRequest(
        method: method.rawValue,
        params: AnyCodable(params),
        id: .int(1)
    )
    let response = try client.send(request)
    if let error = response.error {
        throw CommandServerError.rpcError(error.code, error.message)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let result = response.result {
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    return "{}"
}

/// Resolve an optional positional object ID against the SLIDE_OBJECT_ID env var.
func resolvedObjectId(_ explicitId: String?) throws -> String {
    if let id = explicitId ?? ProcessInfo.processInfo.environment["SLIDE_OBJECT_ID"] {
        return id
    }
    throw ValidationError(
        "No object ID provided and SLIDE_OBJECT_ID is not set. "
        + "Pass an <id> argument or run from a Slide terminal."
    )
}

// MARK: - Root Command

struct SlideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slide",
        abstract: "Control the Slide workspace",
        version: CommandServer.slideVersion,
        subcommands: [
            Status.self,
            ObjectGroup.self,
            ProjectGroup.self,
            Notify.self,
            Identify.self,
            Version.self,
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Status

extension SlideCommand {
    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check if Slide is running"
        )

        func run() throws {
            print(try callMethod(.status, params: Empty()))
        }
    }
}

// MARK: - Object

struct ObjectGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "object",
        abstract: "Manage objects (tabs) in the workspace",
        subcommands: [
            Open.self,
            Focus.self,
            Close.self,
            Badge.self,
            Start.self,
            Stop.self,
            Attention.self,
            Rename.self,
            List.self,
        ]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a new object")

        @Option(help: "Object type (browser, terminal, note, etc.)")
        var type: String = "browser"

        @Option(help: "URL to open")
        var url: String?

        @Option(help: "Initial content")
        var content: String?

        @Option(help: "Working directory for terminals")
        var cwd: String?

        @Option(help: "Project ID to open in")
        var project: String?

        func run() throws {
            let params = SlideParams.ObjectOpen(
                type: type, url: url, content: content, cwd: cwd, projectId: project
            )
            print(try callMethod(.objectOpen, params: params))
        }
    }

    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Focus an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectFocus, params: SlideParams.ObjectId(id: objectId)))
        }
    }

    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Close an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectClose, params: SlideParams.ObjectId(id: objectId)))
        }
    }

    struct Badge: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set badge count on an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        @Option(help: "Badge count")
        var count: Int = 1

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectBadge, params: SlideParams.ObjectBadge(id: objectId, count: count)))
        }
    }

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show working indicator on an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectStart, params: SlideParams.ObjectId(id: objectId)))
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Clear working indicator on an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        @Option(help: "Optional badge count to set after stopping")
        var badge: Int?

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectStop, params: SlideParams.ObjectStop(id: objectId, badge: badge)))
        }
    }

    struct Attention: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show needs-attention indicator on an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectAttention, params: SlideParams.ObjectId(id: objectId)))
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename an object")

        @Argument(help: "Object ID (defaults to SLIDE_OBJECT_ID)")
        var id: String?

        @Option(help: "New title for the object")
        var title: String

        func run() throws {
            let objectId = try resolvedObjectId(id)
            print(try callMethod(.objectRename, params: SlideParams.ObjectRename(id: objectId, title: title)))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List objects in the workspace")

        @Option(help: "Filter by project ID")
        var project: String?

        func run() throws {
            print(try callMethod(.objectList, params: SlideParams.ObjectList(projectId: project)))
        }
    }
}

// MARK: - Project

struct ProjectGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Manage projects",
        subcommands: [
            List.self,
            Select.self,
            Create.self,
        ]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all projects")

        func run() throws {
            print(try callMethod(.projectList, params: Empty()))
        }
    }

    struct Select: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch to a project")

        @Argument(help: "Project ID")
        var id: String

        func run() throws {
            print(try callMethod(.projectSelect, params: SlideParams.ProjectSelect(id: id)))
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new project")

        @Option(help: "Project name")
        var name: String

        @Option(help: "Project icon (emoji)")
        var icon: String = "📁"

        @Option(help: "Project color (hex, e.g. #6B7280)")
        var color: String = "#6B7280"

        func run() throws {
            let params = SlideParams.ProjectCreate(name: name, icon: icon, color: color)
            print(try callMethod(.projectCreate, params: params))
        }
    }
}

// MARK: - Notify

extension SlideCommand {
    struct Notify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Send a notification to Slide"
        )

        @Argument(help: "Notification title (alternative to --title)")
        var positionalTitle: String?

        @Option(help: "Notification title")
        var title: String?

        @Option(help: "Notification body text")
        var body: String?

        @Option(help: "Object ID to associate with the notification")
        var object: String?

        func run() throws {
            let resolvedTitle = title ?? positionalTitle ?? "Notification"
            let objectId = object ?? ProcessInfo.processInfo.environment["SLIDE_OBJECT_ID"]
            let params = SlideParams.Notify(title: resolvedTitle, body: body, objectId: objectId)
            print(try callMethod(.notify, params: params))
        }
    }
}

// MARK: - Identify

extension SlideCommand {
    struct Identify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show current context (object ID, project, socket)"
        )

        func run() throws {
            print(try callMethod(.identify, params: Empty()))
        }
    }
}

// MARK: - Version

extension SlideCommand {
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show slide version"
        )

        func run() throws {
            print("slide \(CommandServer.slideVersion)")
        }
    }
}
