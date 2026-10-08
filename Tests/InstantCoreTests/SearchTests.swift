import Foundation
import Testing
@testable import InstantCore

struct SearchTests {
    @Test func sourcePacketCanArriveBeforeAnyAnswerText() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: {\"output\":{\"search_info\":{\"search_results\":[{\"title\":\"Source\",\"url\":\"https://example.com/page\"}]}}}")
        let event = try #require(try decoder.flush())
        #expect(event.text.isEmpty && !event.done)
        #expect(event.sources.count == 1)
    }
    @Test func dashScopeMultimodalDeltasAndNullFinishReason() throws {
        var decoder = SSEDecoder()
        _ = try decoder.consume(line: "data: {\"output\":{\"choices\":[{\"message\":{\"content\":[{\"text\":\"搜索结果\"}]},\"finish_reason\":\"null\"}]}}")
        let event = try #require(try decoder.flush())
        #expect(event.text == "搜索结果" && !event.done)
        _ = try decoder.consume(line: "data: {\"output\":{\"choices\":[{\"message\":{\"content\":[{\"text\":\"完成\"}]},\"finish_reason\":\"stop\"}]}}")
        #expect(try decoder.flush()?.done == true)
    }
    @Test func unsafeSourcesAreRejectedAndDuplicatePagesCollapse() throws {
        #expect(SearchSource(title: "bad", address: "javascript:alert(1)") == nil)
        #expect(SearchSource(title: "bad", address: "file:///etc/passwd") == nil)
        #expect(SearchSource(title: "bad", address: "https://secret@example.com/") == nil)
        let a = try #require(SearchSource(title: "A", address: "https://example.com/page#one"))
        let b = try #require(SearchSource(title: "B", address: "https://example.com/page#two"))
        #expect(SearchSource.unique([a,b]).count == 1)
        let invalid = Data("{\"title\":\"bad\",\"url\":\"file:///etc/passwd\"}".utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SearchSource.self, from: invalid) }
    }
    @Test func aliEndpointKeepsTheConfiguredOrigin() throws {
        let base = "https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
        let url = try ChatService.searchEndpoint(baseURL: base, model: "qwen3.8-flash")
        #expect(url.host == URL(string: base)?.host)
        #expect(url.path == "/api/v1/services/aigc/multimodal-generation/generation")
        #expect(try ChatService.searchEndpoint(baseURL: base, model: "qwen-plus").path.contains("text-generation"))
        #expect(!ChatService.supportsSearch(baseURL: "https://example.com/v1", model: "qwen3.8-flash"))
    }
    @Test func oldConversationsStillDecodeAndNewArchivesKeepSources() throws {
        var turn = Turn(question: "question", mode: .chat)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(turn)) as? [String: Any])
        json.removeValue(forKey: "sources")
        #expect(try JSONDecoder().decode(Turn.self, from: JSONSerialization.data(withJSONObject: json)).sources == nil)
        turn.answer = "answer"
        turn.sources = [try #require(SearchSource(title: "Source", address: "https://example.com/page"))]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ConversationStore(directory: directory)
        var conversation = Conversation(); conversation.turns = [turn]
        try store.save(conversation)
        #expect(try store.recover()?.turns.first?.sources?.count == 1)
        #expect(store.markdown(conversation).contains("https://example.com/page"))
    }
}
