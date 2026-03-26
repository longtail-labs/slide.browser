# SlideCore – MilkdownEditor

This package adds a SwiftUI component that embeds a Milkdown editor via `WKWebView`.

- Module: `MilkdownEditor`
- Platforms: macOS 14+ (WebKit), iOS supported if integrated in an iOS target
- Resources: Ships with a minimal fallback (textarea) so the view works before you build the real Milkdown bundle.

## Usage

```
import MilkdownEditor

struct EditorScreen: View {
    @State private var markdown = "# Hello\n\nStart editing..."

    var body: some View {
        MilkdownEditor(value: $markdown)
            .onContentChange { updated in
                // Persist to your DB here
            }
            .onLoadSuccess { print("Milkdown ready") }
            .onLoadFailed { print("Milkdown failed: \($0)") }
    }
}
```

## Building the real Milkdown web bundle

The package includes a fallback bundle (simple textarea) at `Sources/MilkdownEditor/Resources/`. To use the actual Milkdown editor, build the web assets:

1. Install Node (18+ recommended)
2. `cd SlideCore/web`
3. `npm install`
4. `npm run build`

This writes `milkdown.bundle.js` and `milkdown.bundle.css` into `Sources/MilkdownEditor/Resources/` (overwriting the fallback). Next build of the Swift package will embed the real editor.

## Notes

- The web bundle posts messages to Swift via `window.webkit.messageHandlers` using these names:
  - `milkdownReady`, `milkdownContentChanged`, `milkdownFocused`, `milkdownBlurred`.
- The Swift bridge de-duplicates updates to avoid feedback loops.
- You can control read-only, focus, and theme via the `MilkdownEditorViewModel`.
