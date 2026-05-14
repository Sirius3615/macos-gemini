# GeminiContext — macOS AI Context Utility

A lightweight macOS menu bar utility that detects mouse shakes and spawns a floating AI chat window with screen context, powered by Google's Gemini API.

## Features

- **Menu Bar Only** — Runs as an LSUIElement (no Dock icon)
- **Mouse Shake Detection** — 4+ rapid X-axis direction reversals within 0.5s triggers the AI panel
- **Screen Capture** — Uses ScreenCaptureKit (macOS 14+) for performant single-frame capture
- **Real Gemini AI** — Full integration with Gemini REST API (streaming SSE responses)
- **Model Selection** — Switch between Gemini 2.5 Flash and Pro in the chat UI
- **Markdown Rendering** — Rich formatting: headers, bold, italic, code blocks with copy buttons, lists, links
- **LaTeX Math** — Display math rendered via KaTeX in native WKWebView blocks
- **Streaming Responses** — Token-by-token streaming with typing indicator and stop button
- **Multi-turn Chat** — Full conversation history sent as context
- **Secure API Key** — Stored in macOS Keychain, never in plain text
- **Floating AI Chat** — Borderless NSPanel with glass-morphism SwiftUI interface
- **Permission Management** — Guides users through Accessibility and Screen Recording setup

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ / Swift 5.9+
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)

## Building

### Option A: Command Line (SPM)

```bash
cd GeminiContext
swift build --disable-sandbox
.build/debug/GeminiContext
```

### Option B: Xcode Project

```bash
cd GeminiContext
swift package generate-xcodeproj
open GeminiContext.xcodeproj
```

Set **Info.plist File** to `Sources/GeminiContext/Resources/Info.plist`, then Build & Run (⌘R).

### Option C: App Bundle

```bash
swift build -c release --disable-sandbox
mkdir -p GeminiContext.app/Contents/MacOS
cp .build/release/GeminiContext GeminiContext.app/Contents/MacOS/
cp Sources/GeminiContext/Resources/Info.plist GeminiContext.app/Contents/
```

## Setup

1. Launch the app — a ✨ icon appears in the menu bar
2. Click the icon → grant Accessibility and Screen Recording permissions
3. Enter your Gemini API key (stored securely in Keychain)
4. Shake your mouse rapidly left-right — the AI chat panel appears!

## Required Permissions (Info.plist)

| Key | Value | Purpose |
|-----|-------|---------|
| `LSUIElement` | `true` | Menu bar only, no Dock icon |
| `NSScreenCaptureUsageDescription` | String | Screen Recording prompt |

Both **Accessibility** and **Screen Recording** must be granted in System Settings → Privacy & Security.

## Architecture

```
Sources/GeminiContext/
├── GeminiContextApp.swift       # @main, MenuBarExtra scene
├── AppDelegate.swift            # Orchestration: shake → capture → panel
├── ShakeDetector.swift          # NSEvent global monitor, rolling window
├── ScreenCaptureManager.swift   # SCScreenshotManager wrapper
├── GeminiService.swift          # REST API client with SSE streaming
├── SettingsManager.swift        # Keychain API key + UserDefaults prefs
├── FloatingPanel.swift          # Custom NSPanel subclass
├── FloatingPanelManager.swift   # Panel lifecycle & positioning
├── ChatView.swift               # SwiftUI chat: Markdown, LaTeX, streaming
├── MenuBarView.swift            # Menu bar: settings, permissions, model picker
├── PermissionsManager.swift     # Accessibility & Screen Recording checks
└── Resources/Info.plist
```
