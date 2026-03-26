import Foundation
@preconcurrency import ObjectBox

// MARK: - Debug Data Models

struct DebugTask: Codable {
    let title: String
    let emoji: String
    let objects: [DebugObject]
}

struct DebugObject: Codable {
    let title: String
    let url: String
}

struct DebugData: Codable {
    let tasks: [DebugTask]
}

// MARK: - Debug Data Loader

public enum DebugDataLoader {

    /// Loads debug data from JSON and populates the database
    /// Only runs in DEBUG builds and if the database is empty
    public static func loadDebugDataIfNeeded() async {
        #if DEBUG
        guard let database = ObjectBoxDatabase.shared else {
            print("[DebugDataLoader] Database not initialized")
            return
        }

        // Check if database already has objects
        do {
            let existingObjects = try database.fetchAllObjects()
            if !existingObjects.isEmpty {
                print("[DebugDataLoader] Database already has \(existingObjects.count) objects, skipping debug data")
                return
            }
        } catch {
            print("[DebugDataLoader] Error checking existing objects: \(error)")
            return
        }

        // Load debug data
        await loadDebugData()
        #endif
    }

    #if DEBUG
    private static func loadDebugData() async {
        guard let database = ObjectBoxDatabase.shared else { return }

        // Find the JSON file
        guard let url = Bundle.module.url(forResource: "DebugData", withExtension: "json") else {
            print("[DebugDataLoader] DebugData.json not found in bundle")

            // Try loading from the source directory as fallback
            let sourceURL = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .appendingPathComponent("DebugData.json")

            if FileManager.default.fileExists(atPath: sourceURL.path) {
                await loadDebugDataFromURL(sourceURL, database: database)
            } else {
                print("[DebugDataLoader] DebugData.json not found at \(sourceURL.path)")
            }
            return
        }

        await loadDebugDataFromURL(url, database: database)
    }

    private static func loadDebugDataFromURL(_ url: URL, database: ObjectBoxDatabase) async {
        do {
            let data = try Data(contentsOf: url)
            let debugData = try JSONDecoder().decode(DebugData.self, from: data)

            // Ensure Scratchpad exists
            try database.ensureScratchpadExists()

            print("[DebugDataLoader] Loading \(debugData.tasks.count) debug tasks as projects...")

            // Each debug task becomes a project
            for (index, debugTask) in debugData.tasks.enumerated() {
                let project = try database.createProject(
                    name: debugTask.title,
                    icon: debugTask.emoji,
                    colorHex: randomProjectColor()
                )

                for debugObject in debugTask.objects {
                    if let objectURL = URL(string: debugObject.url) {
                        _ = try database.createLinkObject(
                            debugObject.title,
                            objectURL,
                            projectId: project.uuidValue
                        )
                        print("[DebugDataLoader]   - Added link: \(debugObject.title) [project: \(debugTask.title)]")
                    }
                }
                print("[DebugDataLoader] Loaded project \(index + 1)/\(debugData.tasks.count): \(debugTask.title)")
            }

            print("[DebugDataLoader] Successfully loaded debug data")

        } catch {
            print("[DebugDataLoader] Error loading debug data: \(error)")
        }
    }

    private static func randomProjectColor() -> String {
        let colors = [
            "#EF4444", "#F97316", "#F59E0B", "#84CC16",
            "#22C55E", "#14B8A6", "#06B6D4", "#3B82F6",
            "#6366F1", "#8B5CF6", "#A855F7", "#EC4899"
        ]
        return colors.randomElement() ?? "#6B7280"
    }
    #endif

    /// Clears all data from the database (DEBUG only)
    public static func clearAllData() async {
        #if DEBUG
        guard let database = ObjectBoxDatabase.shared else {
            print("[DebugDataLoader] Database not initialized")
            return
        }

        do {
            let objects = try database.fetchAllObjects()
            for obj in objects {
                try database.deleteObject(obj.uuidValue)
            }
            print("[DebugDataLoader] Cleared all data from database")
        } catch {
            print("[DebugDataLoader] Error clearing data: \(error)")
        }
        #endif
    }

    /// Reloads debug data (clears existing and loads fresh)
    public static func reloadDebugData() async {
        #if DEBUG
        print("[DebugDataLoader] Reloading debug data...")
        await clearAllData()
        await loadDebugData()
        #endif
    }
}
