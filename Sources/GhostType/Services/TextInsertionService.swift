import AppKit
import Carbon.HIToolbox

class TextInsertionService {
    func insertText(_ text: String, method: SettingsManager.InsertionMethod = .clipboard) {
        switch method {
        case .clipboard:
            insertViaClipboard(text)
        case .accessibility:
            if !insertViaAccessibility(text) {
                insertViaClipboard(text)
            }
        }
    }

    // MARK: - Clipboard Paste

    func prepareClipboard(with text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save all current clipboard items (not just plain text)
        let savedItems: [(NSPasteboard.PasteboardType, Data)] = pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        } ?? []

        // Set new text
        prepareClipboard(with: text)

        // Simulate Cmd+V
        simulatePaste()

        // Restore clipboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                let item = NSPasteboardItem()
                for (type, data) in savedItems {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility Insertion

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success else { return false }

        let element = focusedElement as! AXUIElement

        // Try to insert at selected text range (non-destructive) first
        var rangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if rangeResult == .success {
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setResult == .success { return true }
        }

        // Fallback: set entire value (destructive)
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        return setResult == .success
    }

    // MARK: - Utility

    static func focusedAppBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
