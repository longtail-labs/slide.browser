# Slide

**A unified content browser for people who work across many sources at once.**

## What is Slide?

Slide is a native macOS app that treats every content type — web pages, PDFs, notes, terminals, images, video, audio — as a first-class object in a single workspace. Instead of juggling browser tabs, a file manager, a terminal app, and a note-taking app, you open everything in Slide and organize it by what you're working on.

## The Problem

Knowledge workers live in too many apps. A typical research session involves:

- 6 browser tabs across 3 topics
- A PDF open in Preview
- A terminal running a build
- Notes scattered in a separate app
- No relationship between any of them

Switching between apps is friction. Losing context is the default.

## How Slide Works

### Everything is an Object

Every piece of content — a URL, a PDF, a note, a terminal session — is an **object**. Objects live in a flat sidebar, tagged and filterable. There are no folders, no nested hierarchies. Tags are your scope.

### Panels, Not Tabs

Objects open as **panels** in a horizontal strip. You can view multiple panels side-by-side. Click a group to fan out its children as split panels. This is how you compare, reference, and work across sources simultaneously.

### Groups for Context

When you open a link from a webpage, the new link automatically groups with its origin. The sidebar stays clean — one row with a badge showing how many related objects it contains. Click the group to see all of them as panels.

### Keyboard-First

| Shortcut | Action |
|----------|--------|
| Cmd+K | Command palette — search commands, create objects |
| Cmd+T | Quick links + new terminal |
| Cmd+P | Switch between objects |
| Cmd+L | Focus the filter bar |
| Cmd+N | New note |
| Cmd+W | Close + delete the focused object |
| Cmd+F | Find on page |
| Tab | Cycle through tag filters |
| h/l | Navigate panels (vim-style) |
| j/k | Navigate sidebar (vim-style) |

### Filter Bar

The filter bar is a universal input. Type to filter objects. Paste a URL to open it. Type `/note` to create a note. Type `/terminal` to open a shell. Start with `#` to filter by tag.

### Command Palette

Cmd+K opens a VS Code-style command palette. Search for any action, object, or command. Providers are pluggable — quick links, Google search with autocomplete, tag filtering, object operations.

## Object Types

| Type | What it does |
|------|-------------|
| Link | Full web browsing via WKWebView with navigation history, favicons, downloads |
| PDF | Page-tracking viewer with metadata |
| Note | Native markdown editor (STTextView) with auto-save |
| Terminal | Real PTY shell (zsh/bash) with proper keyboard layout support |
| Image | Viewer with dimension/size metadata |
| Video | Player with duration tracking |
| Audio | Player with artist/album metadata |
| Group | Collection of objects that expand as split panels |

## Architecture

- **SwiftUI** on macOS 14+
- **The Composable Architecture (TCA)** for state management — every action is testable
- **ObjectBox** embedded database — all objects stored locally with real-time streaming
- **WKWebView** with a registry pattern: web views are cached per-tab to preserve scroll position, history, and session state across tab switches
- **SwiftTerm** for terminal emulation with a custom keyboard layout fix
- **Kingfisher** for favicon caching (100MB memory, 200MB disk)
- **Firebase** for analytics and remote config

## What Makes Slide Different

1. **Truly unified.** Web, PDFs, terminals, notes — all equal citizens in one interface. Not a browser with plugins bolted on.

2. **Tag-scoped, not folder-nested.** Tags define your working context. Switch tags and your entire workspace changes. No dragging files between folders.

3. **Groups emerge from use.** Open a link from a page and it automatically groups with the source. Your research threads form naturally.

4. **Native performance.** SwiftUI + WKWebView = smooth scrolling and instant tab switching. No Electron. No web-based terminal emulator.

5. **Keyboard-driven.** Every action has a shortcut. Vim-style navigation. Command palette for discovery.

6. **Privacy-first.** Everything stored locally. No cloud required. Non-sandboxed for full file system access.

## Target Users

- **Developers** working with docs + code + web references + terminals
- **Researchers** comparing papers, articles, and data sources
- **Content creators** managing assets and references in one place
- **Power users** of Arc Browser, Notion, or VS Code who want integrated content management

## Status

Pre-launch. Version 0.1.0. Private beta.

Built by [longtail LABS](https://longtaillabs.com).
