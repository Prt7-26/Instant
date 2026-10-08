import Foundation
import Testing
@testable import InstantCore

private final class StreamProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "instant.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let unauthorized = request.url!.path.contains("unauthorized")
        let truncated = request.url!.path.contains("truncated")
        let response = HTTPURLResponse(url: request.url!, statusCode: unauthorized ? 401 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = ": keepalive\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"你好 🌱\"}}]}\r\n\r\n"
            + (truncated ? "" : "data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}\r\n\r\ndata: [DONE]\r\n\r\n")
        // Split inside UTF-8 scalars as a real network transport can.
        for byte in body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor CollectedText {
    var text = ""
    func append(_ value: String) { text += value }
}

struct ChatServiceTests {
    private func service() -> ChatService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamProtocol.self]
        return ChatService(configuration: configuration)
    }
    @Test func streamedBytesPreserveUTF8AndEventBoundaries() async throws {
        let output = CollectedText()
        try await service().stream(baseURL: "https://instant.test/success/v1", key: "test-only", model: "test",
                                   messages: [ChatMessage(role: "user", content: "test")]) { await output.append($0) }
        #expect(await output.text == "你好 🌱 world")
    }
    @Test func truncatedStreamKeepsTextAndReportsFailure() async throws {
        let output = CollectedText()
        do {
            try await service().stream(baseURL: "https://instant.test/truncated/v1", key: "test-only", model: "test", messages: []) { await output.append($0) }
            Issue.record("An incomplete stream must not be marked complete")
        } catch ChatError.failure(.interrupted) {
            #expect(await output.text == "你好 🌱")
        }
    }
    @Test func authenticationFailureDoesNotBecomeAnEmptyAnswer() async throws {
        do {
            try await service().stream(baseURL: "https://instant.test/unauthorized/v1", key: "test-only", model: "test", messages: []) { _ in }
            Issue.record("Expected the HTTP authentication error")
        } catch ChatError.status(let code) {
            #expect(code == 401)
        }
    }
}
