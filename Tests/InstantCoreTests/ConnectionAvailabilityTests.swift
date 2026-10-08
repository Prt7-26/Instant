import Foundation
import Testing
@testable import InstantCore

struct ConnectionAvailabilityTests {
    @Test func newInstallationStartsWithNoProviderPreset() {
        let value = AppConfiguration()
        #expect(value.baseURL.isEmpty && value.model.isEmpty)
        #expect(ConnectionConfiguration(baseURL: value.baseURL, key: "", model: value.model).issue == .missing(ConnectionField.allCases))
    }
    @Test func allSevenMissingFieldCombinationsAreSpecific() {
        for mask in 1...7 {
            let config = ConnectionConfiguration(baseURL: mask & 1 == 0 ? "https://example.test/v1" : " \n",
                                                 key: mask & 2 == 0 ? "test-key" : "\t",
                                                 model: mask & 4 == 0 ? "test-model" : " ")
            let fields = ConnectionField.allCases.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil }
            #expect(config.issue == .missing(fields))
        }
    }
    @Test func pastedOuterWhitespaceIsNormalizedButHeaderAndModelWhitespaceIsRejected() throws {
        let config = ConnectionConfiguration(baseURL: " https://example.test/v1/ \n", key: " test-key\n", model: " test-model ")
        #expect(config.issue == nil)
        #expect(config.key == "test-key" && config.model == "test-model")
        #expect(try ChatService.endpoint(for: "https://example.test/v1/chat/completions/").path == "/v1/chat/completions")
        #expect(ConnectionConfiguration(baseURL: "https://example.test/v1", key: "Bearer test-key", model: "model").issue == .invalidKey)
        #expect(ConnectionConfiguration(baseURL: "https://example.test/v1", key: "test\r\nInjected: header", model: "model").issue == .invalidKey)
        #expect(ConnectionConfiguration(baseURL: "https://example.test/v1", key: "key", model: "model\nname").issue == .invalidModel)
        #expect(ConnectionConfiguration(baseURL: "http://example.test/v1", key: "key", model: "model").issue == .invalidURL)
    }
    @Test func structuredCodesDistinguishActionableFailuresAndIgnoreRawMessages() {
        let cases: [(String, ModelFailureReason)] = [
            ("invalid_api_key", .authentication), ("AccessDenied.Unpurchased", .permission),
            ("ModelNotFound", .model), ("Arrearage", .quota), ("insufficient_quota", .quota),
            ("Throttling.AllocationQuota", .rateLimited), ("Throttling.RateQuota", .rateLimited),
            ("context_length_exceeded", .contextLimit), ("DataInspectionFailed", .filtered),
            ("InvalidParameter", .rejected), ("InternalError", .unavailable)
        ]
        for (code, expected) in cases {
            #expect(ModelFailureReason.providerError(in: ["error": ["code": code, "message": "untrusted request echo"]]) == expected)
        }
        #expect(ModelFailureReason.providerError(in: ["error": ["code": "not-recognized", "message": "invalid_api_key secret-echo"]]) == .unknown)
        #expect(ModelFailureReason.providerError(in: ["code": "200", "choices": []]) == nil)
    }
    @Test func transportFailuresOfferDifferentRecoveryPaths() {
        #expect(ModelFailureReason.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(ModelFailureReason.classify(URLError(.timedOut)) == .timeout)
        #expect(ModelFailureReason.classify(URLError(.cannotFindHost)) == .network)
        #expect(ModelFailureReason.classify(URLError(.serverCertificateUntrusted)) == .certificate)
        #expect(ModelFailureReason.classify(URLError(.networkConnectionLost)) == .interrupted)
        #expect(ModelFailureReason.http(401) == .authentication)
        #expect(ModelFailureReason.http(403) == .permission)
        #expect(ModelFailureReason.http(404) == .endpoint)
        #expect(ModelFailureReason.http(429) == .rateLimited)
        #expect(ModelFailureReason.http(503) == .unavailable)
        #expect(ModelFailureReason.http(413) == .contextLimit)
    }
    @Test func terminalLimitsKeepTheirLastTextAndRefusalTextIsDisplayable() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"content\":\"last words\"},\"finish_reason\":\"length\"}]}")
        let limit = try #require(try decoder.flush())
        #expect(limit.text == "last words" && limit.failure == .outputLimit)
        _ = try decoder.consume(line: "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"content_filter\"}]}")
        #expect(try decoder.flush()?.failure == .filtered)
        _ = try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"content\":null,\"refusal\":\"Cannot answer that request.\"},\"finish_reason\":\"stop\"}]}")
        #expect(try decoder.flush()?.text == "Cannot answer that request.")
    }
    @Test func unansweredFailuresAreNotResentAsConversationHistory() {
        var conversation = Conversation()
        var failed = Turn(question: "old failed request", mode: .chat)
        failed.state = .failed; failed.error = "local instructions"
        var answered = Turn(question: "earlier successful question", mode: .chat)
        answered.answer = "earlier answer"; answered.state = .complete
        conversation.turns = [failed, answered, Turn(question: "new question", mode: .chat)]
        let messages = PromptBuilder.messages(conversation: conversation, language: Language.resolve("en"))
        #expect(!messages.contains { $0.content.contains("old failed request") || $0.content.contains("local instructions") })
        #expect(messages.map(\.role) == ["system", "user", "assistant", "user"])
    }
}
