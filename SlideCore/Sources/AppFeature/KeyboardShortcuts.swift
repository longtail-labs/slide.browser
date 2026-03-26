import ComposableArchitecture
import SwiftUI
import AppKit

// MARK: - Centralized Keyboard Shortcuts

public extension View {
    /// Attaches global and context-specific keyboard shortcuts for the content browser.
    func appKeyboardShortcuts(store: StoreOf<SlideAppFeature>) -> some View {
        self
            // Global: Command Bar toggle (⌘K)
            .onKeyPress(keys: [.init("k")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.toggleCommandBar)
                    return .handled
                }
                return .ignored
            }
            // Quick switch objects (⌘P) / Project switcher (⇧⌘P)
            .onKeyPress(keys: [.init("p"), .init("P")], phases: .down) { keyPress in
                guard store.commandPalette == nil, keyPress.modifiers.contains(.command) else { return .ignored }
                if keyPress.modifiers.contains(.shift) {
                    store.send(.openCommandBarProjects)
                    return .handled
                } else {
                    store.send(.openCommandBarObjects)
                    return .handled
                }
            }
            // Escape: close command bar, hide find bar, or return focus
            .onKeyPress(.escape) {
                if store.commandPalette != nil {
                    store.send(.commandPalette(.presented(.close)))
                    return .handled
                }
                if store.browser.isFindBarVisible {
                    store.send(.browser(.hideFindBar))
                    return .handled
                }
                return .ignored
            }
            // Find in page (⌘F)
            .onKeyPress(keys: [.init("f")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    store.send(.browser(.showFindBar))
                    return .handled
                }
                return .ignored
            }
            // Focus filter bar (⇧⌘F)
            .onKeyPress(keys: [.init("f")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) {
                    store.send(.focusFilterBar)
                    return .handled
                }
                return .ignored
            }
            // Navigate previous (⌘⌥↑)
            .onKeyPress(.upArrow, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.option) {
                    store.send(.browser(.selectPreviousObject))
                    return .handled
                }
                return .ignored
            }
            // Navigate next (⌘⌥↓)
            .onKeyPress(.downArrow, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.option) {
                    store.send(.browser(.selectNextObject))
                    return .handled
                }
                return .ignored
            }
            // Sidebar navigation (⇧⌘↑/⇧⌘↓)
            .onKeyPress(.upArrow, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) {
                    store.send(.browser(.selectPreviousObject))
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) {
                    store.send(.browser(.selectNextObject))
                    return .handled
                }
                return .ignored
            }
            // Focus panel left (⌘⌥←)
            .onKeyPress(.leftArrow, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.option) {
                    store.send(.browser(.focusPanelLeft))
                    return .handled
                }
                return .ignored
            }
            // Focus panel right (⌘⌥→)
            .onKeyPress(.rightArrow, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.option) {
                    store.send(.browser(.focusPanelRight))
                    return .handled
                }
                return .ignored
            }
            // Address bar (⌘L) — opens command palette in cmdL scope with current URL
            .onKeyPress(keys: [.init("l")], phases: .down) { keyPress in
                if store.commandPalette == nil,
                   keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    store.send(.openCommandBarForCurrentObject)
                    return .handled
                }
                return .ignored
            }
            // New Tab (⌘T)
            .onKeyPress(keys: [.init("t")], phases: .down) { keyPress in
                if store.commandPalette == nil,
                   keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    store.send(.openCommandBarNewTab)
                    return .handled
                }
                return .ignored
            }
            // New Note (⌘N)
            .onKeyPress(keys: [.init("n")], phases: .down) { keyPress in
                if store.commandPalette == nil,
                   keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    store.send(.createNewNote)
                    return .handled
                }
                return .ignored
            }
            // Close focused panel (⌘W)
            .onKeyPress(keys: [.init("w")], phases: .down) { keyPress in
                if store.commandPalette == nil,
                   keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    store.send(.closeCurrentObject)
                    return .handled
                }
                return .ignored
            }
            // Duplicate Tab (⌘D) — links only
            .onKeyPress(keys: [.init("d")], phases: .down) { keyPress in
                if store.commandPalette == nil,
                   keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    if let selectedId = store.browser.selectedObjectId,
                       let obj = store.browser.objects.first(where: { $0.uuidValue == selectedId }),
                       obj.objectType == .link {
                        store.send(.duplicateCurrentObject)
                        return .handled
                    }
                }
                return .ignored
            }
            // Copy Current URL (⌘⇧C)
            .onKeyPress(keys: [.init("c")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) {
                    store.send(.copyCurrentUrl)
                    return .handled
                }
                return .ignored
            }
            // Save Selection to Note (⌘S)
            .onKeyPress(keys: [.init("s")], phases: .down) { keyPress in
                if store.commandPalette == nil,
                   keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                    store.send(.saveSelectionToNote)
                    return .handled
                }
                return .ignored
            }
            // Cmd+1–9 for project switching
            .onKeyPress(keys: [.init("1"), .init("2"), .init("3"), .init("4"), .init("5"), .init("6"), .init("7"), .init("8"), .init("9")], phases: .down) { keyPress in
                guard store.commandPalette == nil,
                      keyPress.modifiers.contains(.command),
                      !keyPress.modifiers.contains(.shift),
                      !keyPress.modifiers.contains(.option) else { return .ignored }
                if let char = keyPress.characters.first, let digit = Int(String(char)), digit >= 1, digit <= 9 {
                    let projects = store.browser.projects.sorted(by: { $0.sortOrder < $1.sortOrder })
                    if digit <= projects.count {
                        let project = projects[digit - 1]
                        store.send(.browser(.selectProject(project.uuidValue)))
                        return .handled
                    }
                }
                return .ignored
            }
            // Go Back (⌘[)
            .onKeyPress(keys: [.init("[")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.goBack)
                    return .handled
                }
                return .ignored
            }
            // Go Forward (⌘])
            .onKeyPress(keys: [.init("]")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.goForward)
                    return .handled
                }
                return .ignored
            }
            // Reload (⌘R)
            .onKeyPress(keys: [.init("r")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.reload)
                    return .handled
                }
                return .ignored
            }
            // Zoom In (⌘=)
            .onKeyPress(keys: [.init("=")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.zoomIn)
                    return .handled
                }
                return .ignored
            }
            // Zoom Out (⌘-)
            .onKeyPress(keys: [.init("-")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.zoomOut)
                    return .handled
                }
                return .ignored
            }
            // Reset Zoom (⌘0)
            .onKeyPress(keys: [.init("0")], phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    store.send(.resetZoom)
                    return .handled
                }
                return .ignored
            }
            // Find next/previous when find bar visible
            .onKeyPress(.return, phases: .down) { keyPress in
                if store.browser.isFindBarVisible {
                    if keyPress.modifiers.contains(.shift) {
                        store.send(.browser(.findPrevious))
                    } else {
                        store.send(.browser(.findNext))
                    }
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - Browser Keyboard Monitor (NSEvent)

/// A robust keyboard monitor for when focus is inside NSView-backed content (e.g., web views)
private struct BrowserKeyboardMonitor: ViewModifier {
    let store: StoreOf<SlideAppFeature>
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { install() }
            .onDisappear { uninstall() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // When command bar is visible, only handle escape to close it
            if store.commandPalette != nil {
                if event.keyCode == 53 { // Escape
                    store.send(.commandPalette(.presented(.close)))
                    return nil
                }
                return event
            }

            // Handle ⇧⌘↑/↓ for sidebar navigation
            if event.modifierFlags.contains([.command, .shift]) {
                switch event.keyCode {
                case 126: // Up arrow
                    store.send(.browser(.selectPreviousObject))
                    return nil
                case 125: // Down arrow
                    store.send(.browser(.selectNextObject))
                    return nil
                default:
                    break
                }
            }

            // Handle ⌘⌥↑/↓ for object navigation, ⌘⌥←/→ for panel navigation
            if event.modifierFlags.contains([.command, .option]) {
                switch event.keyCode {
                case 126: // Up arrow
                    store.send(.browser(.selectPreviousObject))
                    return nil
                case 125: // Down arrow
                    store.send(.browser(.selectNextObject))
                    return nil
                case 123: // Left arrow
                    store.send(.browser(.focusPanelLeft))
                    return nil
                case 124: // Right arrow
                    store.send(.browser(.focusPanelRight))
                    return nil
                default:
                    break
                }
            }

            // Handle ⌘W for closing the focused panel
            if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                if event.charactersIgnoringModifiers?.lowercased() == "w" {
                    store.send(.closeCurrentObject)
                    return nil
                }
            }

            // Handle ⌘L for address bar (command palette in cmdL scope)
            if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                if event.charactersIgnoringModifiers?.lowercased() == "l" {
                    store.send(.openCommandBarForCurrentObject)
                    return nil
                }
            }

            // Handle ⇧⌘F for filter bar focus
            if event.modifierFlags.contains([.command, .shift]) {
                if event.charactersIgnoringModifiers?.lowercased() == "f" {
                    store.send(.focusFilterBar)
                    return nil
                }
            }

            return event
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

public extension View {
    func browserKeyboardMonitor(store: StoreOf<SlideAppFeature>) -> some View {
        modifier(BrowserKeyboardMonitor(store: store))
    }
}
