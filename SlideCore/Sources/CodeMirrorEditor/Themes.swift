import Foundation

/// Available CodeMirror 6 themes.
public enum CodeTheme: String, CaseIterable, Sendable {
    case oneDark = "one-dark"
    case solarizedDark = "solarized-dark"
    case dracula = "dracula"
    case basicLight = "basic-light"
    case basicDark = "basic-dark"

    /// Default dark theme used by Slide.
    public static let `default`: CodeTheme = .oneDark
}
