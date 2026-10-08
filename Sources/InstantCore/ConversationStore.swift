import Foundation

public final class ConversationStore {
    public let directory: URL
    private let currentURL: URL
    public init(directory: URL, checkpointURL: URL? = nil) throws {
        self.directory = directory
        currentURL = checkpointURL ?? directory.appendingPathComponent(".current.json")
        for folder in [directory, currentURL.deletingLastPathComponent()] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw CocoaError(.fileWriteFileExists) }
            } else {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
            }
        }
    }
    public func recover() throws -> Conversation? {
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return nil }
        var value = try JSONDecoder().decode(Conversation.self, from: Data(contentsOf: currentURL))
        for index in value.turns.indices where value.turns[index].state == .generating {
            value.turns[index].state = .interrupted
        }
        return value
    }
    public func save(_ conversation: Conversation) throws {
        guard !conversation.turns.isEmpty else { return }
        try write(JSONEncoder().encode(conversation), to: currentURL)
        try write(Data(markdown(conversation).utf8), to: fileURL(conversation))
    }
    public func archive(_ conversation: Conversation) throws {
        guard !conversation.turns.isEmpty else { return }
        try save(conversation)
        if FileManager.default.fileExists(atPath: currentURL.path) { try FileManager.default.removeItem(at: currentURL) }
    }
    public func fileURL(_ conversation: Conversation) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return directory.appendingPathComponent("\(formatter.string(from: conversation.startedAt))_\(conversation.id.uuidString.prefix(8)).md")
    }
    public func markdown(_ conversation: Conversation) -> String {
        let date = ISO8601DateFormatter()
        var text = "# Instant\n\n\(date.string(from: conversation.startedAt))\n"
        for turn in conversation.turns {
            text += "\n---\n\n## \(turn.mode == .translation ? "Translation" : "Question") · \(date.string(from: turn.date))\n\n\(turn.question)\n\n\(turn.answer)\n"
            if turn.state == .interrupted { text += "\n_Interrupted_\n" }
            if turn.state == .failed { text += "\n_\(turn.error ?? "Failed")_\n" }
            if let sources = turn.sources, !sources.isEmpty {
                text += "\n### Sources\n\n"
                for source in sources {
                    let title = source.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                    text += "- [\(title)](<\(source.url.absoluteString)>)\n"
                }
            }
        }
        return text
    }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
