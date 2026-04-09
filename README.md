# macOS CLI Prompter

A lightweight macOS menubar app that lets you highlight text anywhere on screen, type a prompt, and instantly send it to [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in a new iTerm tab — with your selected text as context.

## Demo

1. Highlight any text on screen
2. **Double-copy** (`Cmd+C Cmd+C` quickly), press `Cmd+Shift+C`, or right-click → Services → "Send to Claude"
3. A popup appears showing your copied text and a prompt field — type what you want Claude to do
4. Hit Enter — a new iTerm tab opens with Claude Code running your prompt (with `--dangerously-skip-permissions`)

## Features

- **Double-copy trigger** (`Cmd+C Cmd+C`) — copy twice within 500ms to trigger. Most reliable method — no extra permissions needed
- **Menubar popover** — click the `>_` icon to see your copied text, type a prompt, and browse recent history
- **Global hotkey** (`Cmd+Shift+C`) — works in any app (requires Accessibility permission)
- **Right-click Services menu** — "Send to Claude" appears when text is selected
- **Light/Dark mode** — follows macOS system appearance automatically
- **Prompt history** — menubar popover shows your last 5 prompts, click to re-send
- **Structured prompts** — selected text is automatically wrapped as context for Claude
- **New iTerm tab** — each prompt opens a fresh tab (launches iTerm if not running)
- **Auto-accept mode** — runs Claude Code with `--dangerously-skip-permissions` for zero-friction execution

## Requirements

- macOS 14.0+
- [iTerm2](https://iterm2.com/)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed at `/opt/homebrew/bin/claude`

## Permissions

| Permission | Required for | How to grant |
|---|---|---|
| **Automation (iTerm)** | Sending commands to iTerm | macOS prompts on first use — click OK |
| **Accessibility** | Global hotkey (`Cmd+Shift+C`) only | System Settings → Privacy & Security → Accessibility |

The **double-copy trigger works without any permissions** — it's the recommended way to use the app.

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
  ClaudePrompt/StatusBarPopover.swift \
  ClaudePrompt/iTermBridge.swift \
  ClaudePrompt/PromptHistoryManager.swift \
  ClaudePrompt/ClipboardWatcher.swift \
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

1. macOS will ask to allow ClaudePrompt to control iTerm — click **OK**
2. (Optional) For the global hotkey: **System Settings → Privacy & Security → Accessibility** → enable ClaudePrompt, then relaunch

## Usage

| Action | How |
|---|---|
| **Double-copy** | Select text → `Cmd+C Cmd+C` quickly → popover opens from menubar |
| **Hotkey** | Select text → `Cmd+Shift+C` → floating popup appears on screen |
| **Menubar** | Click `>_` icon → see copied text, type prompt, browse history |
| **Services** | Select text → right-click → Services → "Send to Claude" |
| **Re-send** | Click any prompt in the history section of the popover |

## How It Works

1. **Double-copy detection** — Polls `NSPasteboard.changeCount` every 200ms. Two copies within 500ms triggers the menubar popover with copied text as context.
2. **Global hotkey** — Carbon `RegisterEventHotKey` captures `Cmd+Shift+C`. Simulates `Cmd+C` to grab selected text, then shows a floating panel.
3. **Menubar popover** — Shows three sections: copied text preview, prompt input field, and recent prompt history.
4. **iTerm bridge** — AppleScript opens a new iTerm tab and runs:
   ```
   claude --dangerously-skip-permissions "Given this context:\n<copied text>\n\nTask: <your prompt>"
   ```
5. **History** — Prompts saved to `UserDefaults` (max 20), last 5 shown in popover.

## Tech Stack

- **Language:** Swift 5
- **UI Framework:** AppKit (pure, no SwiftUI)
- **Double-Copy Detection:** `NSPasteboard.changeCount` polling (200ms interval, 500ms window)
- **Menubar Popover:** `NSPopover` with custom `NSViewController`
- **Global Hotkey:** Carbon `RegisterEventHotKey` + `NSEvent` monitors as fallback
- **Text Capture:** `CGEvent`-based `Cmd+C` simulation + `NSPasteboard`
- **Floating Panel:** Borderless `NSPanel` with `NSVisualEffectView` (vibrancy)
- **iTerm Integration:** `NSAppleScript`
- **Storage:** `UserDefaults`
- **macOS Services:** `NSServices` via `Info.plist` for right-click integration
- **Dependencies:** None (zero third-party dependencies)

## Project Structure

```
ClaudePrompt/
  main.swift                 # App entry point
  AppDelegate.swift          # Menubar, popover, coordination
  HotkeyManager.swift        # Global hotkey + text capture
  ClipboardWatcher.swift     # Double-copy detection
  StatusBarPopover.swift     # Menubar popover UI
  PromptPanel.swift          # Floating popup UI (hotkey trigger)
  iTermBridge.swift          # AppleScript bridge to iTerm
  PromptHistoryManager.swift # UserDefaults-backed history
  Info.plist                 # LSUIElement, Services, Automation
```

## License

MIT
