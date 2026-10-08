import Foundation

public enum ConversationMode: String, Codable { case chat, translation }
public enum TurnState: String, Codable { case generating, complete, interrupted, failed }

public struct Turn: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var question: String
    public var answer = ""
    public var mode: ConversationMode
    public var state: TurnState = .generating
    public var error: String?
    public var sources: [SearchSource]?
    public init(question: String, mode: ConversationMode) {
        self.question = question
        self.mode = mode
    }
}

public struct Conversation: Codable, Equatable {
    public var id = UUID()
    public var startedAt = Date()
    public var turns: [Turn] = []
    public var lastQuestionAt: Date? { turns.last?.date }
    public init() {}
    public func isExpired(minutes: Int, now: Date = Date()) -> Bool {
        guard let lastQuestionAt else { return false }
        return now.timeIntervalSince(lastQuestionAt) >= Double(max(1, minutes)) * 60
    }
}

public struct ChatMessage: Codable, Equatable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct Language: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let englishName: String
    public var isRTL: Bool { ["ar", "he", "fa", "ur"].contains(id) }
    public static let supported: [Language] = [
        .init(id: "zh-Hans", name: "简体中文", englishName: "Simplified Chinese"),
        .init(id: "zh-Hant", name: "繁體中文", englishName: "Traditional Chinese"),
        .init(id: "en", name: "English", englishName: "English"),
        .init(id: "es", name: "Español", englishName: "Spanish"),
        .init(id: "fr", name: "Français", englishName: "French"),
        .init(id: "de", name: "Deutsch", englishName: "German"),
        .init(id: "pt", name: "Português", englishName: "Portuguese"),
        .init(id: "it", name: "Italiano", englishName: "Italian"),
        .init(id: "ru", name: "Русский", englishName: "Russian"),
        .init(id: "uk", name: "Українська", englishName: "Ukrainian"),
        .init(id: "ja", name: "日本語", englishName: "Japanese"),
        .init(id: "ko", name: "한국어", englishName: "Korean"),
        .init(id: "ar", name: "العربية", englishName: "Arabic"),
        .init(id: "hi", name: "हिन्दी", englishName: "Hindi"),
        .init(id: "bn", name: "বাংলা", englishName: "Bengali"),
        .init(id: "ur", name: "اردو", englishName: "Urdu"),
        .init(id: "pa", name: "ਪੰਜਾਬੀ", englishName: "Punjabi"),
        .init(id: "fa", name: "فارسی", englishName: "Persian"),
        .init(id: "tr", name: "Türkçe", englishName: "Turkish"),
        .init(id: "id", name: "Bahasa Indonesia", englishName: "Indonesian"),
        .init(id: "ms", name: "Bahasa Melayu", englishName: "Malay"),
        .init(id: "vi", name: "Tiếng Việt", englishName: "Vietnamese"),
        .init(id: "th", name: "ไทย", englishName: "Thai"),
        .init(id: "fil", name: "Filipino", englishName: "Filipino"),
        .init(id: "nl", name: "Nederlands", englishName: "Dutch"),
        .init(id: "pl", name: "Polski", englishName: "Polish"),
        .init(id: "sv", name: "Svenska", englishName: "Swedish"),
        .init(id: "el", name: "Ελληνικά", englishName: "Greek"),
        .init(id: "he", name: "עברית", englishName: "Hebrew"),
        .init(id: "sw", name: "Kiswahili", englishName: "Swahili")
    ]

    public static func resolve(_ identifier: String, preferred: [String] = Locale.preferredLanguages) -> Language {
        let value = identifier == "system" ? (preferred.first ?? "en") : identifier
        if value.hasPrefix("zh") {
            return supported[value.contains("Hant") || value.contains("TW") || value.contains("HK") ? 1 : 0]
        }
        return supported.first { value == $0.id || value.hasPrefix($0.id + "-") } ?? supported[2]
    }
}

public struct AppConfiguration: Codable, Equatable {
    public var archiveMinutes = 5
    public var baseURL = ""
    public var model = ""
    public var language = "system"
    public var hotKeyCode: UInt32 = 49
    public var hotKeyModifiers: UInt32 = 2048 // Carbon optionKey
    public var translationShortcut = "doubleSpace"
    public var translationKeyCode: UInt32 = 17
    public var translationModifiers: UInt32 = 768 // Carbon cmdKey | shiftKey
    public var archiveKeyCode: UInt32 = 34 // I, local to the floating panel
    public var archiveModifiers: UInt32 = 2048
    public var archiveFolderPath = ""
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case archiveMinutes, baseURL, model, language, hotKeyCode, hotKeyModifiers
        case translationShortcut, translationKeyCode, translationModifiers
        case archiveKeyCode, archiveModifiers, archiveFolderPath
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        archiveMinutes = try values.decodeIfPresent(Int.self, forKey: .archiveMinutes) ?? archiveMinutes
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? baseURL
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? model
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? language
        hotKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? hotKeyCode
        hotKeyModifiers = try values.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? hotKeyModifiers
        translationShortcut = try values.decodeIfPresent(String.self, forKey: .translationShortcut) ?? translationShortcut
        translationKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .translationKeyCode) ?? translationKeyCode
        translationModifiers = try values.decodeIfPresent(UInt32.self, forKey: .translationModifiers) ?? translationModifiers
        archiveKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .archiveKeyCode) ?? archiveKeyCode
        archiveModifiers = try values.decodeIfPresent(UInt32.self, forKey: .archiveModifiers) ?? archiveModifiers
        archiveFolderPath = try values.decodeIfPresent(String.self, forKey: .archiveFolderPath) ?? archiveFolderPath
    }
}
