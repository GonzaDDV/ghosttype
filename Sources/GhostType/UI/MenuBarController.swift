import AppKit

class MenuBarController {
    private var statusItem: NSStatusItem!
    private let settings: SettingsManager
    private let logger: TranscriptionLogger
    var onSettingsClicked: (() -> Void)?

    init(settings: SettingsManager, logger: TranscriptionLogger) {
        self.settings = settings
        self.logger = logger
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)
        buildMenu()
    }

    func updateIcon(for state: AppState.State) {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "GhostType")
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        case .processing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processing")
            button.contentTintColor = .systemOrange
        case .inserting:
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Done")
            button.contentTintColor = .systemGreen
        }

        if state == .idle {
            button.contentTintColor = nil
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let recentItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        if let entries = try? logger.recentEntries(count: 10) {
            if entries.isEmpty {
                recentMenu.addItem(NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: ""))
            } else {
                for entry in entries {
                    let preview = String(entry.cleanedText.prefix(50))
                    let item = NSMenuItem(title: preview, action: #selector(copyTranscription(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = entry.cleanedText
                    recentMenu.addItem(item)
                }
            }
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit GhostType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshMenu() {
        buildMenu()
    }

    @objc private func copyTranscription(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openSettings() {
        onSettingsClicked?()
    }
}
