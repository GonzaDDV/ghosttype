import AppKit

class SettingsWindowController: NSWindowController {
    private let settings: SettingsManager
    private var deepgramField: NSSecureTextField!
    private var openRouterField: NSSecureTextField!
    private var modelField: NSTextField!
    private var modePopup: NSPopUpButton!
    private var insertionPopup: NSPopUpButton!
    private var historyPathField: NSTextField!
    private var launchAtLoginCheckbox: NSButton!

    var onSettingsSaved: (() -> Void)?

    init(settings: SettingsManager) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostType Settings"
        window.center()

        super.init(window: window)
        setupUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])

        // Deepgram API Key
        stackView.addArrangedSubview(makeLabel("Deepgram API Key"))
        deepgramField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        deepgramField.placeholderString = "Enter Deepgram API key"
        deepgramField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(deepgramField)

        // OpenRouter API Key
        stackView.addArrangedSubview(makeLabel("OpenRouter API Key"))
        openRouterField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        openRouterField.placeholderString = "Enter OpenRouter API key"
        openRouterField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(openRouterField)

        // Model
        stackView.addArrangedSubview(makeLabel("LLM Model (OpenRouter model ID)"))
        modelField = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        modelField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(modelField)

        // Dictation Mode
        stackView.addArrangedSubview(makeLabel("Dictation Mode"))
        modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopup.addItems(withTitles: ["Toggle (press to start/stop)", "Hold to Talk"])
        stackView.addArrangedSubview(modePopup)

        // Text Insertion Method
        stackView.addArrangedSubview(makeLabel("Text Insertion Method"))
        insertionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        insertionPopup.addItems(withTitles: ["Clipboard Paste (recommended)", "Accessibility API"])
        stackView.addArrangedSubview(insertionPopup)

        // History Path
        stackView.addArrangedSubview(makeLabel("Transcription History Path"))
        historyPathField = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        historyPathField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(historyPathField)

        // Launch at Login
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
        stackView.addArrangedSubview(launchAtLoginCheckbox)

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        stackView.addArrangedSubview(saveButton)
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private func loadValues() {
        deepgramField.stringValue = settings.deepgramApiKey ?? ""
        openRouterField.stringValue = settings.openRouterApiKey ?? ""
        modelField.stringValue = settings.llmModel
        modePopup.selectItem(at: settings.dictationMode == .toggle ? 0 : 1)
        insertionPopup.selectItem(at: settings.insertionMethod == .clipboard ? 0 : 1)
        historyPathField.stringValue = settings.historyPath
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
    }

    @objc private func saveSettings() {
        let dgKey = deepgramField.stringValue
        let orKey = openRouterField.stringValue

        if !dgKey.isEmpty { settings.deepgramApiKey = dgKey }
        if !orKey.isEmpty { settings.openRouterApiKey = orKey }

        settings.llmModel = modelField.stringValue
        settings.dictationMode = modePopup.indexOfSelectedItem == 0 ? .toggle : .holdToTalk
        settings.insertionMethod = insertionPopup.indexOfSelectedItem == 0 ? .clipboard : .accessibility
        settings.historyPath = historyPathField.stringValue
        settings.launchAtLogin = launchAtLoginCheckbox.state == .on

        onSettingsSaved?()
        window?.close()
    }
}
