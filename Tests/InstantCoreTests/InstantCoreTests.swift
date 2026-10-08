import Testing
import Foundation
@testable import InstantCore

struct InstantCoreTests {
    @Test func testSSEHandlesUnicodeKeepalivesAndDone() throws {
        var decoder = SSEDecoder()
        #expect(try decoder.consume(line: ": ping") == nil)
        #expect(try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"content\":\"你好🌱\"}}]}") == nil)
        #expect(try decoder.consume(line: "") == StreamEvent(text: "你好🌱"))
        #expect(try decoder.consume(line: "data: [DONE]") == nil)
        #expect(try decoder.consume(line: "") == StreamEvent(done: true))
    }
    @Test func testReasoningIsNotDisplayed() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"internal reasoning\"}}]}")
        #expect(try decoder.flush()?.text == "")
    }
    @Test func testFinishReasonCompletesStreamWithoutTerminalSentinel() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
        #expect(try decoder.flush()?.done == true)
    }
    @Test func testSSEMultilineAndInBandErrors() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: {\"choices\":")
        _ = try decoder.consume(line: "data: [{\"delta\":{\"content\":\"answer\"}}]}")
        #expect(try decoder.consume(line: "")?.text == "answer")
        _ = try decoder.consume(line: "data: {\"error\":{\"message\":\"failed\"}}")
        #expect(throws: (any Error).self) { try decoder.consume(line: "") }
    }
    @Test func testMalformedEventsFailInsteadOfSilentlyFinishing() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: broken")
        #expect(throws: (any Error).self) { try decoder.flush() }
    }
    @Test func testEndpointsPreserveBasePathAndRejectCredentialURLs() throws {
        #expect(try ChatService.endpoint(for: "https://example.com/compatible-mode/v1/").absoluteString == "https://example.com/compatible-mode/v1/chat/completions")
        #expect(try ChatService.endpoint(for: "https://example.com/v1/chat/completions").path == "/v1/chat/completions")
        #expect(throws: (any Error).self) { try ChatService.endpoint(for: "https://secret@example.com/v1") }
        #expect(throws: (any Error).self) { try ChatService.endpoint(for: "http://example.com/v1") }
        #expect(throws: (any Error).self) { try ChatService.endpoint(for: "https://example.com/v1?key=secret") }
        _ = try ChatService.endpoint(for: "http://localhost:1234/v1")
    }
    @Test func testTranslationIsBilingualAndIsolatedFromChatHistory() {
        var conversation = Conversation()
        var first = Turn(question: "private previous question", mode: .chat)
        first.answer = "old answer"
        conversation.turns = [first, Turn(question: "hello", mode: .translation)]
        let messages = PromptBuilder.messages(conversation: conversation, language: Language.resolve("ja"))
        #expect(messages.count == 2)
        #expect(messages[0].content.contains("Japanese"))
        #expect(messages[0].content.contains("English"))
        #expect(messages[1].content == "hello")
        #expect(!(messages.contains { $0.content.contains("private previous") }))
    }
    @Test func testEnglishUsesExplicitBilingualFallback() {
        var conversation = Conversation()
        conversation.turns = [Turn(question: "hello", mode: .translation)]
        #expect(PromptBuilder.messages(conversation: conversation, language: Language.resolve("en"))[0].content.contains("Simplified Chinese"))
    }
    @Test func testFollowUpKeepsChatContextAndOmitsTranslationTurns() {
        var conversation = Conversation()
        var first = Turn(question: "first", mode: .chat)
        first.answer = "answer"
        conversation.turns = [first, Turn(question: "translate", mode: .translation), Turn(question: "follow up", mode: .chat)]
        let messages = PromptBuilder.messages(conversation: conversation, language: Language.resolve("fr"))
        #expect(messages.map(\.role) == ["system", "user", "assistant", "user"])
        #expect(messages.last?.content == "follow up")
    }
    @Test func testLanguageResolutionAndWritingDirection() {
        #expect(Language.resolve("system", preferred: ["zh-TW"]).id == "zh-Hant")
        #expect(Language.resolve("system", preferred: ["fr-CA"]).id == "fr")
        #expect(Language.resolve("unknown").id == "en")
        #expect(Language.resolve("ar-SA").isRTL)
        #expect(!(Language.resolve("ja").isRTL))
    }
    @Test func testIdleBoundaryAndEmptyConversation() {
        var conversation = Conversation()
        #expect(!(conversation.isExpired(minutes: 5)))
        var turn = Turn(question: "question", mode: .chat)
        turn.date = Date(timeIntervalSince1970: 1000)
        conversation.turns = [turn]
        #expect(!(conversation.isExpired(minutes: 5, now: Date(timeIntervalSince1970: 1299))))
        #expect(conversation.isExpired(minutes: 5, now: Date(timeIntervalSince1970: 1300)))
    }
    @Test func testArchiveRecoveryAndEmptySessions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ConversationStore(directory: directory)
        try store.save(Conversation())
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        var conversation = Conversation()
        var turn = Turn(question: "保留问题", mode: .translation)
        turn.answer = "答案\nAnswer"
        conversation.turns = [turn]
        try store.save(conversation)
        let recovered = try #require(try store.recover())
        #expect(recovered.turns[0].state == .interrupted)
        #expect(recovered.turns[0].answer == turn.answer)
        try store.archive(recovered)
        #expect(try store.recover() == nil)
        let markdown = try String(contentsOf: store.fileURL(conversation), encoding: .utf8)
        #expect(markdown.contains("答案\nAnswer"))
        #expect(markdown.contains("Translation"))
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL(conversation).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    @Test func testConfigurationDoesNotContainCredentials() throws {
        let data = try JSONEncoder().encode(AppConfiguration())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["apiKey"] == nil)
    }
}
