# macOS CLI Prompter

A lightweight macOS menubar app that lets you highlight text anywhere on screen, type a prompt, and instantly send it to [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in a new iTerm tab — with your selected text as context.

## Demo

1. Highlight any text on screen
2. **Double-copy** (`Cmd+C Cmd+C` quickly), press `Cmd+Shift+C`, or right-click → Services → "Send to Claude"
3. A minimal popup appears — type what you want Claude to do
4. Hit Enter — a new iTerm tab opens with Claude Code running your prompt

## Features

- **Double-copy trigger** (`Cmd+C Cmd+C`) — copy twice within 500ms to trigger the popup. Most reliable method — no extra permissions needed
- **Global hotkey** (`Cmd+Shift+C`) — works in any app
- **Right-click Services menu** — "Send to Claude" appears when text is selected
- **Minimal floating popup** — just a text field, no clutter
- **Light/Dark mode** — follows macOS system appearance automatically
- **Prompt history** — menubar dropdown shows your last 10 prompts, click to re-send
- **Structured prompts** — selected text is automatically wrapped as context for Claude
- **New iTerm tab** — each prompt opens a fresh tab (launches iTerm if not running)

## Requirements

- macOS 14.0+
- [iTerm2](https://iterm2.com/)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed at `/opt/homebrew/bin/claude`
- Accessibility permission (granted on first launch)

## Installation

### Build from source

```bash
git clone https://github.com/ichen27/macos-cli-prompter.git
cd macos-cli-prompter
mkdir -p build/ClaudePrompt.app/Contents/MacOS build/ClaudePrompt.app/Contents/Resources
cp ClaudePrompt/Info.plist build/ClaudePrompt.app/Contents/
swiftc -o build/ClaudePrompt.app/Contents/MacOS/ClaudePrompt \
  ClaudePrompt/main.swift \
  ClaudePrompt/AppDelegate.swift \
  ClaudePrompt/HotkeyManager.swift \
  ClaudePrompt/PromptPanel.swift \
  ClaudePrompt/iTermBridge.swift \
  ClaudePrompt/PromptHistoryManager.swift \
  -framework AppKit \
  -framework Carbon \
  -target arm64-apple-macosx14.0 \
  -swift-version 5
```

### Run

```bash
open build/ClaudePrompt.app
```

### First launch

macOS will prompt you to grant **Accessibility permission**. This is required for the global hotkey (`Cmd+Shift+C`). The double-copy trigger works without any permissions.

1. Go to **System Settings → Privacy & Security → Accessibility**
2. Enable **ClaudePrompt**
3. Relaunch the app

## How It Works

1. **Double-copy detection** — A clipboard watcher polls `NSPasteboard.changeCount` every 200ms. If two copies happen within 500ms, it triggers the popup with the copied text as context. No permissions required.
2. **Global hotkey** — Carbon `RegisterEventHotKey` captures `Cmd+Shift+C` globally. When triggered, simulates `Cmd+C` to grab selected text.
3. **Popup** — A borderless floating `NSPanel` appears on the screen where your mouse cursor is.
3. **iTerm bridge** — On submit, an AppleScript tells iTerm to open a new tab and runs:
   ```
   claude --prompt "Given this context:\n<selected text>\n\nTask: <your prompt>"
   ```
4. **History** — Prompts are saved to `UserDefaults` (max 20) and shown in the menubar dropdown.

## Tech Stack

- **Language:** Swift 5
- **UI Framework:** AppKit (pure, no SwiftUI)
- **Double-Copy Detection:** `NSPasteboard.changeCount` polling (200ms interval, 500ms window)
- **Global Hotkey:** Carbon `RegisterEventHotKey` + `NSEvent` monitors as fallback
- **Text Capture:** `CGEvent`-based `Cmd+C` simulation + `NSPasteboard`
- **Popup:** Borderless `NSPanel` with `NSVisualEffectView` (vibrancy)
- **iTerm Integration:** `NSAppleScript`
- **Storage:** `UserDefaults`
- **macOS Services:** `NSServices` via `Info.plist` for right-click integration
- **Dependencies:** None (zero third-party dependencies)

## Project Structure

```
ClaudePrompt/
  main.swift                 # App entry point
  AppDelegate.swift          # Menubar, menu, coordination
  HotkeyManager.swift        # Global hotkey + text capture
  ClipboardWatcher.swift     # Double-copy detection
  PromptPanel.swift          # Floating popup UI
  iTermBridge.swift          # AppleScript bridge to iTerm
  PromptHistoryManager.swift # UserDefaults-backed history
  Info.plist                 # LSUIElement, Services config
```

## License

MIT
