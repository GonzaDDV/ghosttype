# GhostType — Cloud-Powered Voice Dictation for macOS

A native macOS menu bar app that captures speech, transcribes it via Deepgram, cleans it up with a fast LLM via OpenRouter, and inserts the result at the cursor. Solves Wispr Flow's limitations: works with laptop closed (any mic), no local CPU impact (no music stuttering).

## Architecture

### Data Flow

1. **Audio Capture** — `AVAudioEngine` captures mic input as Linear PCM 16kHz mono
2. **Deepgram STT** — Raw audio streams via WebSocket to Deepgram for real-time transcription
3. **LLM Cleanup** — Final transcript sent to OpenRouter (fastest available model) to remove filler words, fix punctuation and capitalization
4. **Text Insertion** — Cleaned text inserted at cursor via clipboard paste (default) or Accessibility API (optional)

### Components

- **AudioCaptureManager** — Manages `AVAudioEngine`, provides raw PCM audio chunks via callback
- **DeepgramService** — WebSocket connection to Deepgram, streams audio, receives interim/final transcripts
- **LLMCleanupService** — HTTP client for OpenRouter API, sends raw transcript, returns cleaned text
- **TextInsertionService** — Handles text insertion via clipboard paste (primary) or `AXUIElement` (optional)
- **HotkeyManager** — Global hotkey registration via `CGEvent` tap, supports toggle and hold-to-talk modes
- **TranscriptionLogger** — Appends each transcription to daily `.jsonl` files in `~/.ghosttype/history/`
- **AppState** — State machine managing Idle → Recording → Processing → Inserting → Idle
- **MenuBarController** — `NSStatusItem` with state-aware icon and settings dropdown

## Audio Capture

- `AVAudioEngine` with input tap on mic node
- Format: Linear PCM, 16kHz, mono (Deepgram's preferred input)
- Raw audio chunks streamed directly to Deepgram — no local encoding
- Audio session configured to not interrupt other audio playback
- Microphone permission via `Info.plist` `NSMicrophoneUsageDescription`

## Speech-to-Text (Deepgram)

- WebSocket connection to Deepgram's streaming API
- Send raw PCM audio chunks as they arrive from `AVAudioEngine`
- Receive interim results (for potential future live preview) and final transcript on stream close
- Connection opened when recording starts, closed when recording stops
- Deepgram handles VAD, punctuation, and language detection

## LLM Cleanup (OpenRouter)

- HTTP POST to OpenRouter API after receiving final transcript from Deepgram
- System prompt: "Clean up this dictated text. Remove filler words (um, uh, like, you know), fix punctuation and capitalization. Return only the cleaned text. Do not change the meaning or add anything."
- Model: configurable, default to fastest cheap model (benchmark Gemini 2.0 Flash, Llama 3.1 8B, etc.)
- Target latency: < 100ms for typical dictation length

## Text Insertion

### Primary: Clipboard Paste (Default)

1. Save current clipboard contents
2. Copy cleaned text to clipboard
3. Simulate `Cmd+V` via `CGEvent`
4. Restore original clipboard after 500ms delay

### Secondary: Accessibility API (Opt-in)

1. Get focused app via `NSWorkspace`
2. Get focused UI element via `AXUIElementCopyAttributeValue`
3. Set `AXValue` or insert at `AXSelectedTextRange`
4. Configurable in settings

## Hotkey System

### State Machine

| State | Icon | Description |
|-------|------|-------------|
| Idle | Default mic icon | Waiting for hotkey |
| Recording | Red dot | Mic active, streaming to Deepgram |
| Processing | Activity indicator | Waiting for transcript + cleanup |
| Inserting | Brief flash | Pasting text, then → Idle |

### Modes

- **Toggle** (default): Press hotkey → start recording. Press again → stop and process.
- **Hold-to-talk**: Hold hotkey → recording. Release → stop and process.
- Default hotkey: `Option + Space` (configurable)
- Registered via `CGEvent` tap (requires Accessibility permission)

### Edge Cases

- App switch during recording: keep recording, insert into whatever app is focused on stop
- Text insertion failure: fall back to clipboard paste, show brief error in menu bar
- API failure (Deepgram or LLM): insert raw transcript, show error indicator in menu bar
- LLM failure specifically: insert Deepgram's raw transcript (still useful)

## Transcription History

- Stored in `~/.ghosttype/history/` (configurable)
- One `.jsonl` file per day (e.g., `2026-03-13.jsonl`)
- Each entry contains:
  ```json
  {
    "timestamp": "2026-03-13T14:30:00Z",
    "raw_transcript": "um so I think we should like refactor the auth module",
    "cleaned_text": "I think we should refactor the auth module",
    "focused_app": "com.apple.Terminal",
    "model": "google/gemini-2.0-flash-exp",
    "duration_ms": 3200
  }
  ```
- Accessible from menu bar: "Recent Transcriptions" submenu (last 10), click to copy
- Safety net for paste failures or re-use

## Settings

Stored in `UserDefaults`, API keys in macOS Keychain.

| Setting | Default | Storage |
|---------|---------|---------|
| Deepgram API key | — | Keychain |
| OpenRouter API key | — | Keychain |
| Hotkey combo | `Option + Space` | UserDefaults |
| Dictation mode | Toggle | UserDefaults |
| LLM model | (fastest benchmarked) | UserDefaults |
| Text insertion method | Clipboard paste | UserDefaults |
| History path | `~/.ghosttype/history/` | UserDefaults |
| Launch at login | Off | UserDefaults |

Settings UI: simple native `NSWindow` with fields, opened from menu bar dropdown.

## Permissions & First Launch

### Required Permissions

1. **Microphone** — `AVCaptureDevice` permission, standard macOS dialog on first use
2. **Accessibility** — Required for global hotkey and paste simulation. User enables manually in System Settings > Privacy & Security > Accessibility

### First Launch Flow

1. App appears in menu bar
2. Click icon → "Set up API keys" prompt
3. After entering keys, prompt to configure hotkey
4. First dictation attempt triggers macOS mic permission dialog
5. If Accessibility not granted, show alert with button to open System Settings

No onboarding wizard — contextual prompts as needed.

## Technology Stack

- **Language:** Swift
- **UI Framework:** AppKit (menu bar app, settings window)
- **Audio:** AVAudioEngine
- **Networking:** URLSessionWebSocketTask (Deepgram), URLSession (OpenRouter)
- **Hotkeys:** CGEvent tap
- **Text insertion:** NSPasteboard + CGEvent (primary), AXUIElement (optional)
- **Storage:** UserDefaults + Keychain
- **Build:** Xcode / Swift Package Manager
- **Target:** macOS 13+ (Ventura)
