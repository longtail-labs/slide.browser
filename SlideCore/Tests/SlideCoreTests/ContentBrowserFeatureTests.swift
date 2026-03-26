import ComposableArchitecture
import Sharing
import XCTest

@testable import AppFeature
@testable import SlideDatabase

@MainActor
final class ContentBrowserFeatureTests: XCTestCase {
    func testCloseFocusedPanelKeepsObjectAndFocusesPreviousPanel() async {
        let first = makeLink(uuid: "00000000-0000-0000-0000-000000000001", title: "First")
        let second = makeNote(uuid: "00000000-0000-0000-0000-000000000002", title: "Second")
        let third = makeLink(uuid: "00000000-0000-0000-0000-000000000003", title: "Third")

        let store = TestStore(initialState: {
            var state = ContentBrowserFeature.State()
            state.objects = [first, second, third]
            state.visiblePanelIds = [first.uuidValue, second.uuidValue, third.uuidValue]
            state.focusedPanelIndex = 1
            return state
        }()) {
            ContentBrowserFeature()
        }
        store.exhaustivity = .off

        await store.send(.closeFocusedPanel)
        await store.receive(\.closePanel)

        XCTAssertEqual(store.state.visiblePanelIds, [first.uuidValue, third.uuidValue])
        XCTAssertEqual(store.state.focusedPanelIndex, 0)
        XCTAssertEqual(store.state.objects.map(\.uuidValue), [first.uuidValue, second.uuidValue, third.uuidValue])
    }

    func testDeleteObjectRemovesItFromLibrary() async {
        let parent = makeLink(uuid: "00000000-0000-0000-0000-000000000011", title: "Parent")
        let other = makeLink(uuid: "00000000-0000-0000-0000-000000000012", title: "Other")

        let store = TestStore(initialState: {
            var state = ContentBrowserFeature.State()
            state.objects = [parent, other]
            state.visiblePanelIds = [parent.uuidValue]
            state.focusedPanelIndex = 0
            return state
        }()) {
            ContentBrowserFeature()
        }
        store.exhaustivity = .off

        await store.send(.deleteObject(parent.uuidValue))

        XCTAssertEqual(store.state.objects.map(\.uuidValue), [other.uuidValue])
    }

    func testActiveProjectAutoAppliesToNewObjects() async {
        let note = makeNote(uuid: "00000000-0000-0000-0000-000000000021", title: "Daily")
        let projectId = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        var capturedProjectId: UUID?

        let store = TestStore(initialState: {
            var state = ContentBrowserFeature.State()
            state.activeProjectId = projectId
            return state
        }()) {
            ContentBrowserFeature()
        } withDependencies: { values in
            values.slideDatabase.createNoteObject = { title, content, projId in
                capturedProjectId = projId
                return note
            }
        }
        store.exhaustivity = .off

        await store.send(.addNoteObject("Daily", ""))
        await store.receive(\.objectAdded)
        await store.receive(\.selectObjectId)

        XCTAssertEqual(capturedProjectId, projectId)
        XCTAssertEqual(store.state.visiblePanelIds, [note.uuidValue])
    }

    func testOpenInNewPanelAddsSplitView() async {
        let first = makeLink(uuid: "00000000-0000-0000-0000-000000000031", title: "First")
        let second = makeLink(uuid: "00000000-0000-0000-0000-000000000032", title: "Second")

        let store = TestStore(initialState: {
            var state = ContentBrowserFeature.State()
            state.objects = [first, second]
            state.visiblePanelIds = [first.uuidValue]
            state.focusedPanelIndex = 0
            return state
        }()) {
            ContentBrowserFeature()
        }
        store.exhaustivity = .off

        await store.send(.openInNewPanel(second.uuidValue))

        XCTAssertEqual(store.state.visiblePanelIds, [first.uuidValue, second.uuidValue])
        XCTAssertEqual(store.state.focusedPanelIndex, 1)
    }

    func testSelectProjectFiltersObjects() async {
        let projectId = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!

        let inProject = makeLink(uuid: "00000000-0000-0000-0000-000000000041", title: "In Project")
        // Simulate project assignment by setting project target
        let project = OBXProject()
        project.uuid = projectId.uuidString
        project.name = "Test"
        inProject.project.target = project

        let outside = makeLink(uuid: "00000000-0000-0000-0000-000000000042", title: "Outside")

        let store = TestStore(initialState: {
            var state = ContentBrowserFeature.State()
            state.objects = [inProject, outside]
            return state
        }()) {
            ContentBrowserFeature()
        }
        store.exhaustivity = .off

        await store.send(.selectProject(projectId))

        XCTAssertEqual(store.state.activeProjectId, projectId)
        XCTAssertEqual(store.state.filteredObjects.count, 1)
        XCTAssertEqual(store.state.filteredObjects.first?.uuidValue, inProject.uuidValue)
    }

    func testMoveObjectToProject() async {
        let objectId = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let projectId = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        var capturedObjectId: UUID?
        var capturedProjectId: UUID?

        let store = TestStore(initialState: {
            ContentBrowserFeature.State()
        }()) {
            ContentBrowserFeature()
        } withDependencies: { values in
            values.slideDatabase.assignObjectToProject = { objId, projId in
                capturedObjectId = objId
                capturedProjectId = projId
            }
        }
        store.exhaustivity = .off

        await store.send(.moveObjectToProject(objectId, projectId))

        // Wait for the effect to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(capturedObjectId, objectId)
        XCTAssertEqual(capturedProjectId, projectId)
    }

    private func makeLink(uuid: String, title: String) -> TaskObject {
        let object = TaskObject(
            uuid: uuid,
            kind: .link,
            payload: .link(.init(url: "https://example.com/\(title.lowercased())", favicon: nil, preview: nil))
        )
        object.displayName = title
        return object
    }

    private func makeNote(uuid: String, title: String) -> TaskObject {
        let object = TaskObject(uuid: uuid, kind: .note, payload: .note(.init(content: "")))
        object.displayName = title
        return object
    }
}
