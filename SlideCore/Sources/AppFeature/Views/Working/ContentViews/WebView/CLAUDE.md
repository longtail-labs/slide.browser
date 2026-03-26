WebView Architecture: Mount One, Keep Many Alive

Overview
- Problem: Multiple `WKWebView`s mounted at once were fighting over AppKit tracking areas, causing incorrect pointer cursors. Hiding background web views with opacity/zIndex didn’t help because they still remained in the view hierarchy and kept updating cursor rects.
- Goal: Avoid reloads when switching tabs, but ensure only the active tab affects input and cursor.

Design
- Registry (`WebViewRegistry`):
  - Holds a persistent `WKWebView` per tab/object ID.
  - Reuses web views on subsequent selections; updates the URL only if it changed.
  - Keeps inactive web views alive but detached from any superview, so they don’t impact cursor or hit testing.
  - Provides `sync(with:)` to remove orphaned entries when tabs close.

- Host (`WebViewHost`):
  - A minimal `NSViewRepresentable` that re-parents a given `WKWebView` into its container.
  - On update, it clears any previously hosted view then attaches the new one. This guarantees exactly one web view is mounted.

- Per-tab controller (`WebTabController`):
  - Sets `navigationDelegate` and `uiDelegate` for its tab’s web view and manages observers.
  - Listens for `find/back/forward/reload/zoom` notifications filtered by objectId, so global UI (toolbar, find bar) can control only the active tab.
  - Emits metadata (title, current URL, favicon) to SwiftUI when navigation finishes.

SwiftUI integration
- `WebContentView`:
  - Creates a single `WebViewHost` for the currently selected link tab.
  - Uses `WebViewRegistry.ensureWebView(objectId:initialURL:onMetadata:)` to obtain the tab’s persistent web view.
  - Keeps non-web content (notes, PDFs) unchanged.
- On `objects` change, prunes the registry to remove only tabs that no longer exist; unopened tabs are not prewarmed to avoid upfront cost.

Why this fixes the cursor
- Inactive `WKWebView`s are detached from the view hierarchy. Detached views can’t install tracking areas or influence the cursor. Only the mounted (active) web view participates in event handling and pointer updates.

Why no reloads on tab switch
- We never destroy the `WKWebView` for a tab. Switching tabs simply re-parents the existing instance into the visible host container. Session state, scroll position, and navigation stack remain intact.

Alternatives considered
- Keep multiple web views mounted but set `ignoresMouseEvents = true` on background ones: reduces interaction, but tracking/cursor artifacts can still happen and increases complexity.
- Snapshot background tabs into images: eliminates cursor issues but loses live state; rehydration required.
- Single `WKWebView` for all tabs with state serialization (`interactionState`): not robust across diverse sites and loses per-tab histories.

Key APIs
- `NSViewRepresentable` re-parenting of `WKWebView`.
- `NotificationCenter`-based control for find/back/forward/reload/zoom with `objectId` scoping.
- Minimal constraints-based pinning of web view to the host container.
- Force desktop content mode via `WKWebpagePreferences.preferredContentMode = .desktop`.
- Present a Safari-like User-Agent via `WKWebView.customUserAgent` for better site compatibility.
- Navigation policy: allow inline display for PDF/audio/video; only download on explicit user intent or `Content-Disposition: attachment`.

Usage tips
- Default is lazy: only the active tab creates a `WKWebView`; as you visit more, they stay alive.
- To free memory when a tab is actually closed, call `registry.remove(objectId:)`.
- If you add animations around selection, avoid adding/removing additional layers/views over the host container that might retain the previous `WKWebView`.

Gotchas
- Always clear the host container’s subviews before attaching a new `WKWebView` to prevent stacked views or constraints conflicts.
- Ensure notification payloads include the correct `objectId` so actions route to the intended tab only.
- If you add custom menus/popups, they’re managed by `WebTabController` via `WKUIDelegate`—keep it attached to each web view.

Testing checklist
- Open multiple tabs, switch rapidly; cursor remains correct and content matches selection.
- Navigate within a tab; switching away and back preserves scroll and history.
- Use find/zoom/back/forward from toolbar; actions only affect the active tab.
- Close tabs; memory should drop and no orphaned views remain mounted.

Directory
- `WebView.swift` (contains `WebViewHost`, `WebViewRegistry`, `WebTabController`) and `WebContentView.swift` live under `ContentViews/WebView/` with this document.
