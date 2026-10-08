import Foundation
import InstantCore

@MainActor final class ConversationController {
    private(set) var conversation = Conversation()
    private(set) var mode: ConversationMode = .chat
    var draft = ""
    var isVisible = false
    var onChange: ((Bool) -> Void)?
    var onModeChange: (() -> Void)?
    var onError: ((String) -> Void)?
    private let settings: SettingsStore
    private let service: ChatService
    private var store: ConversationStore
    private let testDirectory: URL?
    private let checkpointURL: URL
    var archiveDirectory: URL { store.directory }
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    private var refresh: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var timer: Timer?
    private var expired = false
    private var setupGuidanceVisible = false
    private var replacingFailedAnswer = false
    private var replacementPrefix = ""
    private var replacementSources: [SearchSource] = []
    var isGenerating: Bool { requestID != nil }
    var connectionGuidance: String? {
        guard setupGuidanceVisible else { return nil }
        if let issue = settings.connectionIssue { return settings.l10n.connectionGuidance(issue) }
        return settings.l10n.connectionCopy[.ready]
    }

    init(settings: SettingsStore, directory: URL? = nil, draft: String = "", service: ChatService = ChatService()) throws {
        self.settings = settings
        self.service = service
        self.draft = draft
        testDirectory = directory
        checkpointURL = (directory ?? SettingsStore.defaultArchiveDirectory).appendingPathComponent(".current.json")
        store = try ConversationStore(directory: directory ?? settings.archiveDirectory, checkpointURL: checkpointURL)
        if let recovered = try store.recover() {
            conversation = recovered
            if let last = conversation.turns.last, last.state == .interrupted {
                conversation.turns[conversation.turns.count - 1].error = settings.l10n.modelFailureGuidance(
                    ChatError.failure(.interrupted), hasPartialAnswer: !last.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               conversation.isExpired(minutes: settings.value.archiveMinutes) { try archive() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkExpiry() }
        }
    }
    func toggleMode() { mode = mode == .chat ? .translation : .chat; onModeChange?() }
    func setMode(_ value: ConversationMode) { mode = value; onModeChange?() }
    func checkExpiry() {
        guard !isGenerating, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        expired = conversation.isExpired(minutes: settings.value.archiveMinutes)
        if expired && !isVisible { archiveReportingErrors() }
    }
    func willShow() { checkExpiry(); setMode(.chat); isVisible = true }
    func didHide() { isVisible = false; checkExpiry() }

    @discardableResult func archiveNow() -> Bool {
        guard !conversation.turns.isEmpty else { return true }
        cancel()
        return archiveReportingErrors()
    }

    func updateArchiveDirectory() throws {
        // UI tests keep their conversation files isolated regardless of preferences.
        var destination = settings.archiveDirectory
        if let testDirectory, !destination.resolvingSymlinksInPath().path.hasPrefix(testDirectory.resolvingSymlinksInPath().path + "/") {
            destination = testDirectory
        }
        guard destination.standardizedFileURL != store.directory.standardizedFileURL else { return }
        let next = try ConversationStore(directory: destination, checkpointURL: checkpointURL)
        try next.save(conversation)
        store = next
    }

    @discardableResult
    func submit(_ text: String, onAccept: () -> Void = {}) -> Bool {
        draft = text
        if settings.connectionIssue != nil {
            setupGuidanceVisible = true
            onChange?(true)
            return false
        }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.isEmpty {
            guard let last = conversation.turns.last, last.state == .failed || last.state == .interrupted else {
                if setupGuidanceVisible { onChange?(true) }
                return false
            }
            setupGuidanceVisible = false
            retry(); return true
        }
        if expired {
            let requestedMode = mode
            guard archiveReportingErrors() else { return false }
            mode = requestedMode
        }
        cancel()
        setupGuidanceVisible = false
        onAccept()
        conversation.turns.append(Turn(question: question, mode: mode))
        draft = ""
        persist()
        onChange?(true)
        startRequest()
        return true
    }
    private func retry() {
        guard !conversation.turns.isEmpty else { return }
        cancel()
        let index = conversation.turns.count - 1
        setMode(conversation.turns[index].mode)
        replacingFailedAnswer = true
        conversation.turns[index].error = nil
        conversation.turns[index].state = .generating
        conversation.turns[index].date = Date()
        expired = false
        onChange?(true)
        startRequest()
    }
    private func startRequest() {
        guard let last = conversation.turns.last else { return }
        let id = UUID()
        requestID = id
        let turnID = last.id
        let config = settings.connection
        let key = config.key
        let search = last.mode == .chat && ChatService.supportsSearch(baseURL: config.baseURL, model: config.model)
        var promptConversation = conversation
        // Retain a failed partial answer onscreen until a retry receives text,
        // but never send that old answer as the current request's completion.
        promptConversation.turns[promptConversation.turns.count - 1].answer = ""
        let messages = PromptBuilder.messages(conversation: promptConversation, language: settings.language, searchAvailable: search)
        request = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.stream(baseURL: config.baseURL, key: key, model: config.model, messages: messages,
                                         webSearch: search, onSources: { [weak self] sources in
                    await self?.receiveSources(sources, request: id, turn: turnID)
                }) { [weak self] text in
                    await self?.receive(text, request: id, turn: turnID)
                }
                guard requestID == id else { return }
                conversation.turns[conversation.turns.count - 1].state = .complete
            } catch {
                guard requestID == id else { return }
                if Task.isCancelled { return }
                conversation.turns[conversation.turns.count - 1].state = .failed
                let partial = !conversation.turns[conversation.turns.count - 1].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                conversation.turns[conversation.turns.count - 1].error = settings.l10n.modelFailureGuidance(error, hasPartialAnswer: partial)
            }
            requestID = nil
            replacingFailedAnswer = false
            replacementPrefix = ""
            replacementSources = []
            refresh?.cancel()
            onChange?(false)
            persist()
            checkExpiry()
        }
    }
    private func receive(_ text: String, request id: UUID, turn turnID: UUID) {
        guard requestID == id, conversation.turns.last?.id == turnID else { return }
        var addition = text
        if replacingFailedAnswer {
            // Whitespace alone is not a replacement for the saved partial text.
            replacementPrefix += text
            guard !replacementPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            addition = replacementPrefix
            replacementPrefix = ""
            conversation.turns[conversation.turns.count - 1].answer = ""
            conversation.turns[conversation.turns.count - 1].sources = replacementSources.isEmpty ? nil : replacementSources
            replacementSources = []
            replacingFailedAnswer = false
        }
        conversation.turns[conversation.turns.count - 1].answer += addition
        if refresh == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.refresh = nil
                self?.onChange?(false)
            }
            refresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
        }
        if saveWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.saveWork = nil; self?.persist() }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
        }
    }
    private func receiveSources(_ sources: [SearchSource], request id: UUID, turn turnID: UUID) {
        guard requestID == id, conversation.turns.last?.id == turnID else { return }
        if replacingFailedAnswer {
            replacementSources = SearchSource.unique(replacementSources + sources)
            return
        }
        let index = conversation.turns.count - 1
        conversation.turns[index].sources = SearchSource.unique((conversation.turns[index].sources ?? []) + sources)
        onChange?(false)
    }
    func cancel() {
        request?.cancel()
        request = nil
        if requestID != nil, !conversation.turns.isEmpty { conversation.turns[conversation.turns.count - 1].state = .interrupted }
        requestID = nil
        replacingFailedAnswer = false
        replacementPrefix = ""
        replacementSources = []
        refresh?.cancel(); refresh = nil
        saveWork?.cancel(); saveWork = nil
    }
    @discardableResult func shutdown() -> Bool { cancel(); return persist() }
    @discardableResult private func persist() -> Bool {
        do { try store.save(conversation); return true }
        catch { onError?(error.localizedDescription); return false }
    }
    @discardableResult private func archiveReportingErrors() -> Bool {
        do { try archive(); return true }
        catch { onError?(error.localizedDescription); return false }
    }
    private func archive() throws {
        try store.archive(conversation)
        conversation = Conversation()
        expired = false
        mode = .chat
        onChange?(false)
        onModeChange?()
    }
    deinit {
        timer?.invalidate()
        refresh?.cancel()
        saveWork?.cancel()
        request?.cancel()
    }
}
