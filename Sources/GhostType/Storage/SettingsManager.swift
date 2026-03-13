import Foundation

class SettingsManager {
    enum DictationMode: String {
        case toggle
        case holdToTalk
    }

    enum InsertionMethod: String {
        case clipboard
        case accessibility
    }

    private let defaults: UserDefaults
    private let keychainService: String

    init(defaults: UserDefaults = .standard, keychainService: String = "com.ghosttype.keys") {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    var dictationMode: DictationMode {
        get {
            guard let raw = defaults.string(forKey: "dictationMode"),
                  let mode = DictationMode(rawValue: raw) else { return .toggle }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "dictationMode") }
    }

    var insertionMethod: InsertionMethod {
        get {
            guard let raw = defaults.string(forKey: "insertionMethod"),
                  let method = InsertionMethod(rawValue: raw) else { return .clipboard }
            return method
        }
        set { defaults.set(newValue.rawValue, forKey: "insertionMethod") }
    }

    var llmModel: String {
        get { defaults.string(forKey: "llmModel") ?? "google/gemini-2.0-flash-exp" }
        set { defaults.set(newValue, forKey: "llmModel") }
    }

    var historyPath: String {
        get {
            let defaultPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ghosttype/history").path
            return defaults.string(forKey: "historyPath") ?? defaultPath
        }
        set { defaults.set(newValue, forKey: "historyPath") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var deepgramApiKey: String? {
        get { KeychainHelper.retrieve(service: keychainService, account: "deepgram") }
        set {
            if let value = newValue {
                KeychainHelper.save(service: keychainService, account: "deepgram", data: value)
            } else {
                KeychainHelper.delete(service: keychainService, account: "deepgram")
            }
        }
    }

    var openRouterApiKey: String? {
        get { KeychainHelper.retrieve(service: keychainService, account: "openrouter") }
        set {
            if let value = newValue {
                KeychainHelper.save(service: keychainService, account: "openrouter", data: value)
            } else {
                KeychainHelper.delete(service: keychainService, account: "openrouter")
            }
        }
    }

    var hasRequiredApiKeys: Bool {
        deepgramApiKey != nil && openRouterApiKey != nil
    }
}
