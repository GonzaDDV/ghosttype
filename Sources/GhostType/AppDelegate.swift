import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let settings = SettingsManager()
    private lazy var logger = TranscriptionLogger(historyDirectory: settings.historyPath)
    private lazy var menuBar = MenuBarController(settings: settings, logger: logger)
    private var settingsWindow: SettingsWindowController?

    private var audioCapture: AudioCaptureManager?
    private var deepgram: DeepgramService?
    private var llmCleanup: LLMCleanupService?
    private let textInsertion = TextInsertionService()
    private let hotkeyManager = HotkeyManager()

    private var recordingStartTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up menu bar
        menuBar.setup()
        menuBar.onSettingsClicked = { [weak self] in self?.showSettings() }

        // Set up state change handler
        appState.onChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.menuBar.updateIcon(for: state)
            }
        }

        // Set up hotkey
        hotkeyManager.mode = settings.dictationMode == .toggle ? .toggle : .holdToTalk
        hotkeyManager.onRecordStart = { [weak self] in self?.startDictation() }
        hotkeyManager.onRecordStop = { [weak self] in self?.stopDictation() }

        if !hotkeyManager.start() {
            showAccessibilityAlert()
        }

        // Show settings if no API keys
        if !settings.hasRequiredApiKeys {
            showSettings()
        }
    }

    // MARK: - Dictation Pipeline

    private func startDictation() {
        guard appState.transition(to: .recording) else { return }
        guard let apiKey = settings.deepgramApiKey else {
            appState.transition(to: .idle)
            showSettings()
            return
        }

        recordingStartTime = Date()

        // Set up Deepgram
        deepgram = DeepgramService(apiKey: apiKey)
        deepgram?.onError = { [weak self] error in
            print("Deepgram error: \(error)")
            DispatchQueue.main.async { self?.appState.transition(to: .idle) }
        }
        deepgram?.startStreaming()

        // Set up audio capture
        audioCapture = AudioCaptureManager()
        audioCapture?.onAudioData = { [weak self] data in
            self?.deepgram?.sendAudio(data)
        }

        do {
            try audioCapture?.startCapturing()
        } catch {
            print("Audio capture error: \(error)")
            appState.transition(to: .idle)
        }
    }

    private func stopDictation() {
        guard appState.transition(to: .processing) else { return }

        // Stop audio capture and tear down to prevent tap leak on next cycle
        audioCapture?.stopCapturing()
        let capturedDeepgram = deepgram
        audioCapture = nil
        deepgram = nil

        // Get final transcript from Deepgram
        capturedDeepgram?.stopStreaming { [weak self] rawTranscript in
            guard let self = self else { return }

            if rawTranscript.isEmpty {
                DispatchQueue.main.async { self.appState.transition(to: .idle) }
                return
            }

            // Clean up via LLM
            guard let orKey = self.settings.openRouterApiKey else {
                // No OpenRouter key — insert raw
                self.insertAndLog(raw: rawTranscript, cleaned: rawTranscript)
                return
            }

            let cleanup = LLMCleanupService(apiKey: orKey, model: self.settings.llmModel)
            cleanup.cleanup(rawTranscript) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let cleaned):
                    self.insertAndLog(raw: rawTranscript, cleaned: cleaned)
                case .failure(let error):
                    print("LLM cleanup error: \(error)")
                    // Fallback: insert raw transcript
                    self.insertAndLog(raw: rawTranscript, cleaned: rawTranscript)
                }
            }
        }
    }

    private func insertAndLog(raw: String, cleaned: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appState.transition(to: .inserting)

            // Insert text
            self.textInsertion.insertText(cleaned, method: self.settings.insertionMethod)

            // Log transcription
            let duration = Int((Date().timeIntervalSince(self.recordingStartTime ?? Date())) * 1000)
            let entry = TranscriptionEntry(
                timestamp: Date(),
                rawTranscript: raw,
                cleanedText: cleaned,
                focusedApp: TextInsertionService.focusedAppBundleId() ?? "unknown",
                model: self.settings.llmModel,
                durationMs: duration
            )
            try? self.logger.log(entry)
            self.menuBar.refreshMenu()

            // Back to idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.appState.transition(to: .idle)
            }
        }
    }

    // MARK: - UI

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings)
            settingsWindow?.onSettingsSaved = { [weak self] in
                guard let self = self else { return }
                self.hotkeyManager.mode = self.settings.dictationMode == .toggle ? .toggle : .holdToTalk
            }
        }
        // Switch to regular app so the window gets full keyboard focus (Cmd+V etc.)
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Watch for window close to switch back to accessory (menu bar only)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow?.window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "GhostType needs Accessibility permission to register global hotkeys and paste text. Please enable it in System Settings > Privacy & Security > Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
