import Foundation

/// Supported CodeMirror 6 languages with file-extension detection.
public enum CodeLanguage: String, CaseIterable, Sendable {
    case plain = "plain"
    case c = "c"
    case cpp = "cpp"
    case csharp = "csharp"
    case css = "css"
    case dart = "dart"
    case go = "go"
    case html = "html"
    case java = "java"
    case javascript = "javascript"
    case json = "json"
    case jsx = "jsx"
    case kotlin = "kotlin"
    case lua = "lua"
    case markdown = "markdown"
    case objectivec = "objectivec"
    case perl = "perl"
    case php = "php"
    case python = "python"
    case r = "r"
    case ruby = "ruby"
    case rust = "rust"
    case scala = "scala"
    case shell = "shell"
    case sql = "sql"
    case swift = "swift"
    case toml = "toml"
    case tsx = "tsx"
    case typescript = "typescript"
    case xml = "xml"
    case yaml = "yaml"
    case zig = "zig"

    /// Detect language from a file extension (e.g. "swift", "py").
    public static func from(extension ext: String) -> CodeLanguage {
        switch ext.lowercased() {
        case "c", "h": return .c
        case "cc", "cpp", "cxx", "hpp", "hxx", "hh": return .cpp
        case "cs": return .csharp
        case "css": return .css
        case "dart": return .dart
        case "go": return .go
        case "htm", "html": return .html
        case "java": return .java
        case "js", "mjs", "cjs": return .javascript
        case "json", "jsonl": return .json
        case "jsx": return .jsx
        case "kt", "kts": return .kotlin
        case "lua": return .lua
        case "md", "markdown": return .markdown
        case "m": return .objectivec
        case "pl", "pm": return .perl
        case "php": return .php
        case "py", "pyw": return .python
        case "r", "R": return .r
        case "rb": return .ruby
        case "rs": return .rust
        case "scala": return .scala
        case "sh", "bash", "zsh", "fish": return .shell
        case "sql": return .sql
        case "swift": return .swift
        case "toml": return .toml
        case "tsx": return .tsx
        case "ts", "mts", "cts": return .typescript
        case "xml", "plist", "svg": return .xml
        case "yml", "yaml": return .yaml
        case "zig": return .zig
        default: return .plain
        }
    }

    /// Detect language from a full file path or URL.
    public static func from(filePath: String) -> CodeLanguage {
        let ext = (filePath as NSString).pathExtension
        return from(extension: ext)
    }
}
