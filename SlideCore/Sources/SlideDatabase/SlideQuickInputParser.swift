import Foundation

public enum SlideQuickInputAction: Equatable {
    case filter(String)
    case openURL(URL)
    case createNote(title: String, content: String)
    case createTerminal(title: String, workingDirectory: String)
}

public enum SlideQuickInputParser {
    public static func action(for query: String) -> SlideQuickInputAction {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .filter("")
        }

        if let content = commandPayload(prefix: "/note", in: trimmed) {
            let title = content.isEmpty ? "Untitled Note" : content
            return .createNote(title: title, content: content)
        }

        if let workingDirectory = commandPayload(prefix: "/term", in: trimmed)
            ?? commandPayload(prefix: "/terminal", in: trimmed) {
            return .createTerminal(
                title: "Terminal",
                workingDirectory: workingDirectory.isEmpty ? "~" : workingDirectory
            )
        }

        if let url = detectedURL(from: trimmed) {
            return .openURL(url)
        }

        return .filter(trimmed)
    }

    public static func detectedURL(from query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if trimmed.contains("."), !trimmed.contains(" "),
           let url = URL(string: "https://\(trimmed)") {
            return url
        }

        let patterns = [
            "^[a-zA-Z0-9-]+\\.[a-zA-Z]{2,}(/.*)?$",
            "^www\\.[a-zA-Z0-9-]+\\.[a-zA-Z]{2,}(/.*)?$",
            "^localhost(:[0-9]+)?(/.*)?$",
            "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}(:[0-9]+)?(/.*)?$"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else {
                continue
            }
            if let url = URL(string: "https://\(trimmed)") {
                return url
            }
        }

        return nil
    }

    private static func commandPayload(prefix: String, in query: String) -> String? {
        guard query == prefix || query.hasPrefix("\(prefix) ") else {
            return nil
        }

        return String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
