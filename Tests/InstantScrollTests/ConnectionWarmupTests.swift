import Foundation
import Testing
import InstantCore
@testable import Instant

private final class WarmupRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    private var cancellations = 0
    func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; stored.append(request) }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancellations += 1 }
    func reset() { lock.lock(); defer { lock.unlock() }; stored = []; cancellations = 0 }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
    var cancelled: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
}

private final class WarmupProtocol: URLProtocol, @unchecked Sendable {
    static let log = WarmupRequestLog()
    override class func canInit(with request: URLRequest) -> Bool {
        ["warmup.test", "dashscope.aliyuncs.com"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.log.append(request)
        let warmingUp = request.value(forHTTPHeaderField: "Accept") == "application/json"
        if warmingUp && request.url!.path.contains("held") { return }
        if warmingUp && request.url!.path.contains("offline") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": warmingUp ? "application/json" : "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = warmingUp ? "{\"choices\":[{\"message\":{\"content\":\"INVISIBLE PLACEHOLDER\"}}]}"
            : "data: {\"choices\":[{\"delta\":{\"content\":\"Real answer.\"},\"finish_reason\":\"stop\"}]}\n\n"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.log.cancel() }
}

@MainActor @Suite(.serialized)
struct ConnectionWarmupTests {
    private func environment(route: String = "success", now: @escaping () -> Date = Date.init) throws
        -> (URL, SettingsStore, ConversationController) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Instant-WarmupTests-" + UUID().uuidString)
        let settings = SettingsStore(readKeychain: false, configurationFile: root.appendingPathComponent("settings.json"))
        settings.value.baseURL = "https://warmup.test/\(route)/v1"
        settings.value.model = "test-model"
        settings.apiKey = "test-only"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WarmupProtocol.self]
        let controller = try ConversationController(settings: settings, directory: root.appendingPathComponent("Conversations"),
            draft: "private retained draft", service: ChatService(configuration: config), now: now)
        WarmupProtocol.log.reset()
        return (root, settings, controller)
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The stubbed network operation did not finish")
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func showingWarmsTheConnectionWithoutChangingOrSavingTheConversation() async throws {
        let (root, _, controller) = try environment()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        var changes = 0
        var errors: [String] = []
        controller.onChange = { _ in changes += 1 }
        controller.onError = { errors.append($0) }
        controller.willShow()
        #expect(controller.isVisible && !controller.isGenerating)
        try await waitFor { !controller.isWarmingUp }
        #expect(changes == 0 && errors.isEmpty && controller.connectionGuidance == nil)
        #expect(controller.conversation.turns.isEmpty && controller.draft == "private retained draft")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Conversations/.current.json").path))
        let request = try #require(WarmupProtocol.log.requests.first)
        #expect(request.url?.path == "/success/v1/chat/completions")
        #expect(request.httpMethod == "POST" && request.timeoutInterval == 8)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        let payload = try body(request)
        #expect(payload["stream"] as? Bool == false && payload["max_tokens"] as? Int == 1)
        #expect(payload["model"] as? String == "test-model")
        #expect(payload["messages"] as? [[String: String]] == [["role": "user", "content": "."]])
    }

    @Test func failedWarmupIsSilentAndTheNextQuestionStillWorks() async throws {
        let (root, _, controller) = try environment(route: "offline")
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        var errors: [String] = []
        controller.onError = { errors.append($0) }
        controller.willShow()
        try await waitFor { !controller.isWarmingUp }
        #expect(errors.isEmpty && controller.connectionGuidance == nil && controller.conversation.turns.isEmpty)
        #expect(controller.submit("Actual question"))
        try await waitFor { !controller.isGenerating }
        #expect(controller.conversation.turns.last?.state == .complete)
        #expect(controller.conversation.turns.last?.answer == "Real answer.")
    }

    @Test func sendingDoesNotWaitForWarmupAndNeverIncludesItsPlaceholder() async throws {
        let (root, _, controller) = try environment(route: "held")
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        controller.willShow()
        try await waitFor { WarmupProtocol.log.requests.count == 1 }
        #expect(controller.isWarmingUp)
        controller.didHide(); controller.willShow()
        #expect(controller.submit("Actual question"))
        try await waitFor { !controller.isGenerating }
        #expect(controller.isWarmingUp && WarmupProtocol.log.requests.count == 2)
        #expect(controller.conversation.turns.count == 1 && controller.conversation.turns[0].answer == "Real answer.")
        let payload = try body(WarmupProtocol.log.requests[1])
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages.last?["content"] == "Actual question")
        #expect(!messages.contains { $0["content"] == "." || $0["content"] == "INVISIBLE PLACEHOLDER" })
        let saved = try String(contentsOf: root.appendingPathComponent("Conversations/.current.json"), encoding: .utf8)
        #expect(!saved.contains("INVISIBLE PLACEHOLDER"))
        controller.shutdown()
        try await waitFor { WarmupProtocol.log.cancelled > 0 }
    }

    @Test func rapidReopeningIsThrottledButIdleReopeningWarmsAgain() async throws {
        var time = Date()
        let (root, _, controller) = try environment(now: { time })
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        controller.willShow()
        try await waitFor { !controller.isWarmingUp }
        for _ in 0..<5 { controller.didHide(); controller.willShow() }
        #expect(!controller.isWarmingUp && WarmupProtocol.log.requests.count == 1)
        time = time.addingTimeInterval(31)
        controller.didHide(); controller.willShow()
        try await waitFor { !controller.isWarmingUp }
        #expect(WarmupProtocol.log.requests.count == 2)
        #expect(controller.submit("Question"))
        try await waitFor { !controller.isGenerating }
        time = time.addingTimeInterval(29)
        controller.didHide(); controller.willShow()
        #expect(!controller.isWarmingUp && WarmupProtocol.log.requests.count == 3)
    }

    @Test func changedCredentialsAndModelsBypassTheCooldown() async throws {
        let (root, settings, controller) = try environment()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        controller.willShow()
        try await waitFor { !controller.isWarmingUp }
        settings.apiKey = "replacement-test-key"
        settings.value.model = "replacement-model"
        controller.didHide(); controller.willShow()
        try await waitFor { !controller.isWarmingUp }
        #expect(WarmupProtocol.log.requests.count == 2)
        let request = try #require(WarmupProtocol.log.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer replacement-test-key")
        #expect(try body(request)["model"] as? String == "replacement-model")
    }

    @Test func invalidConfigurationNeverStartsWarmup() throws {
        let (root, settings, controller) = try environment()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        settings.apiKey = ""
        controller.willShow()
        #expect(!controller.isWarmingUp)
        settings.apiKey = "test-only"
        settings.value.baseURL = "https://user:password@warmup.test/v1"
        controller.willShow()
        #expect(!controller.isWarmingUp && WarmupProtocol.log.requests.isEmpty)
    }

    @Test func qwenWarmsTheNativeChatEndpointWithoutSearchOrThinking() async throws {
        let (root, settings, controller) = try environment()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        settings.value.baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        for model in ["qwen-plus", "qwen3.5-plus"] {
            settings.value.model = model
            controller.willShow()
            try await waitFor { !controller.isWarmingUp }
            let request = try #require(WarmupProtocol.log.requests.last)
            let multimodal = model == "qwen3.5-plus"
            #expect(request.url?.path == "/api/v1/services/aigc/\(multimodal ? "multimodal-generation" : "text-generation")/generation")
            #expect(request.value(forHTTPHeaderField: "X-DashScope-SSE") == nil)
            let payload = try body(request)
            let parameters = try #require(payload["parameters"] as? [String: Any])
            #expect(parameters["enable_search"] as? Bool == false && parameters["enable_thinking"] as? Bool == false)
            #expect(parameters["max_tokens"] as? Int == 1 && parameters["search_options"] == nil)
            let input = try #require(payload["input"] as? [String: Any])
            let messages = try #require(input["messages"] as? [[String: Any]])
            #expect(messages.count == 1 && messages[0]["role"] as? String == "user")
            if multimodal {
                #expect(messages[0]["content"] as? [[String: String]] == [["text": "."]])
            } else {
                #expect(messages[0]["content"] as? String == ".")
            }
        }
    }
}
