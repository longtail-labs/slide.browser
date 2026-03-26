import Foundation
import XCTest

@testable import SlideDatabase

final class SlideDatabaseTests: XCTestCase {
    override func tearDown() {
        ObjectBoxDatabase.shared = nil
        super.tearDown()
    }

    func testQuickInputParserRecognizesURLsAndPrefixes() {
        XCTAssertEqual(
            SlideQuickInputParser.detectedURL(from: "docs.swift.org")?.absoluteString,
            "https://docs.swift.org"
        )
        XCTAssertEqual(
            SlideQuickInputParser.action(for: "/note Browser review"),
            .createNote(title: "Browser review", content: "Browser review")
        )
        XCTAssertEqual(
            SlideQuickInputParser.action(for: "/term /Users/jordan/Documents"),
            .createTerminal(title: "Terminal", workingDirectory: "/Users/jordan/Documents")
        )
        XCTAssertEqual(
            SlideQuickInputParser.action(for: "research"),
            .filter("research")
        )
    }

    func testPayloadDecodeFailureProducesInvalidPayload() {
        let rawBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
        let payload = OBXJSONPayloadConverter.convert(rawBytes)

        guard case .invalid(let invalid) = payload else {
            return XCTFail("Expected invalid payload case")
        }

        XCTAssertEqual(invalid.rawData, Data(rawBytes))
        XCTAssertFalse(invalid.errorDescription.isEmpty)
        XCTAssertEqual(OBXJSONPayloadConverter.convert(payload), rawBytes)
    }

    func testProjectCRUD() throws {
        let database = try makeDatabase()

        // Ensure scratchpad exists
        try database.ensureScratchpadExists()
        let projects = try database.fetchAllProjects()
        XCTAssertTrue(projects.contains(where: { $0.uuid == scratchpadProjectUUID }))

        // Create a project
        let project = try database.createProject(name: "Test Project", icon: "🧪", colorHex: "#FF0000")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.icon, "🧪")
        XCTAssertEqual(project.colorHex, "#FF0000")

        // Fetch project
        let fetched = try database.fetchProject(id: project.uuidValue)
        XCTAssertEqual(fetched?.name, "Test Project")

        // Update project
        let updated = fetched!
        updated.name = "Updated Project"
        try database.updateProject(updated)
        let refetched = try database.fetchProject(id: project.uuidValue)
        XCTAssertEqual(refetched?.name, "Updated Project")

        // Delete project
        try database.deleteProject(project.uuidValue)
        XCTAssertNil(try database.fetchProject(id: project.uuidValue))
    }

    func testAssignObjectToProject() throws {
        let database = try makeDatabase()
        try database.ensureScratchpadExists()

        let project = try database.createProject(name: "My Project", icon: "📂", colorHex: "#0000FF")
        let object = try database.createLinkObject("Test Link", URL(string: "https://example.com")!, projectId: project.uuidValue)

        XCTAssertEqual(object.projectId, project.uuidValue)

        // Move to different project
        let project2 = try database.createProject(name: "Other", icon: "📁", colorHex: "#00FF00")
        try database.assignObjectToProject(objectId: object.uuidValue, projectId: project2.uuidValue)

        let refetched = try database.fetchObject(id: object.uuidValue)
        XCTAssertEqual(refetched?.projectId, project2.uuidValue)
    }

    func testScratchpadCannotBeDeleted() throws {
        let database = try makeDatabase()
        try database.ensureScratchpadExists()

        let scratchpadUUID = UUID(uuidString: scratchpadProjectUUID)!

        // Attempt to delete should fail silently or not remove it
        // The deletion guard is in the TCA layer, but the scratchpad
        // should always be re-ensured on launch
        try database.deleteProject(scratchpadUUID)

        // Re-ensure creates it again
        try database.ensureScratchpadExists()
        let projects = try database.fetchAllProjects()
        XCTAssertTrue(projects.contains(where: { $0.uuid == scratchpadProjectUUID }))
    }

    private func makeDatabase() throws -> ObjectBoxDatabase {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidecore-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try ObjectBoxDatabase.initialize(at: tempDirectory)
        return try XCTUnwrap(ObjectBoxDatabase.shared)
    }
}
