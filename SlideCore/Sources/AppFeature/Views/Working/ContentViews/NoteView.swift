import SlideDatabase
import SlideEditor
import SwiftUI
import Dependencies

// MARK: - Note View (STTextView with Markdown Highlighting)

struct NoteView: View {
    let object: TaskObject
    let isDarkMode: Bool
    @State private var content: String = ""
    @State private var saveTask: Task<Void, Never>?
    @Dependency(\.slideDatabase) var database

    var body: some View {
        SlideEditorView(
            text: $content,
            objectId: object.uuidValue,
            font: .monospacedSystemFont(ofSize: 14, weight: .regular),
            textColor: isDarkMode ? .white : .textColor,
            backgroundColor: isDarkMode ? NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1) : .textBackgroundColor,
            insertionPointColor: isDarkMode ? .white : .textColor
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: content) { _, newValue in
            // Debounced auto-save (1 second)
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                var updated = object
                updated.content = newValue
                try? await database.updateObject(updated)
            }
        }
        .onAppear {
            content = object.content ?? ""
        }
        .onDisappear {
            // Save immediately on disappear
            saveTask?.cancel()
            var updated = object
            updated.content = content
            Task {
                try? await database.updateObject(updated)
            }
        }
    }
}
