import Foundation

public enum ChatError: Error, LocalizedError {
    case invalidURL, missingKey, status(Int), emptyResponse, invalidResponse, serverError
    case configuration(ConnectionIssue), failure(ModelFailureReason)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Check Base URL in Settings."
        case .missingKey: return "Add an API Key in Settings."
        case .status(let code): return "Service returned HTTP \(code)."
        case .emptyResponse: return "The service returned no answer."
        case .invalidResponse: return "The service returned an invalid response."
        case .serverError: return "The service could not complete this answer."
        case .configuration: return "Complete or correct the connection settings."
        case .failure(let reason): return "Request failed: \(reason.rawValue)."
        }
    }
}

public struct StreamEvent: Equatable {
    public var text: String = ""
    public var done = false
    public var sources: [SearchSource] = []
    public var failure: ModelFailureReason?
    public init(text: String = "", done: Bool = false, sources: [SearchSource] = [], failure: ModelFailureReason? = nil) {
        self.text = text; self.done = done; self.sources = sources; self.failure = failure
    }
}

/// Decode SSE event boundaries, including multiple data lines and comment keepalives.
public struct SSEDecoder {
    private var dataLines: [String] = []
    private var bufferedBytes = 0
    public init() {}
    public mutating func consume(line: String) throws -> StreamEvent? {
        if line.isEmpty { return try flush() }
        if line.hasPrefix("data:") {
            let value = line.dropFirst(5)
            bufferedBytes += value.utf8.count
            guard bufferedBytes <= 1_048_576 else { throw ChatError.invalidResponse }
            dataLines.append(String(value.first == " " ? value.dropFirst() : value))
        }
        return nil
    }
    public mutating func flush() throws -> StreamEvent? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll()
        bufferedBytes = 0
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { return StreamEvent(done: true) }
        guard let bytes = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
            throw ChatError.invalidResponse
        }
        if let failure = ModelFailureReason.providerError(in: object) { throw ChatError.failure(failure) }
        let output = object["output"] as? [String: Any] ?? object
        let info = output["search_info"] as? [String: Any] ?? object["search_info"] as? [String: Any]
        let sources = SearchSource.unique((info?["search_results"] as? [[String: Any]] ?? []).compactMap {
            guard let url = $0["url"] as? String else { return nil }
            return SearchSource(title: $0["title"] as? String ?? "", address: url)
        })
        let choices = output["choices"] as? [[String: Any]] ?? []
        guard let choice = choices.first else { return StreamEvent(sources: sources) }
        let delta = choice["delta"] as? [String: Any]
        let message = choice["message"] as? [String: Any]
        let content = (delta ?? message)?["content"]
        let contentText = content as? String ?? (content as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        let text = contentText.isEmpty ? ((delta ?? message)?["refusal"] as? String ?? "") : contentText
        let finish = choice["finish_reason"] as? String ?? ""
        let failure: ModelFailureReason? = finish == "length" ? .outputLimit : finish == "content_filter" ? .filtered : nil
        return StreamEvent(text: text, done: !finish.isEmpty && finish != "null", sources: sources, failure: failure)
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        completionHandler(request.url?.host == original?.host && request.url?.scheme == original?.scheme && request.url?.port == original?.port ? request : nil)
    }
}

public final class ChatService: @unchecked Sendable {
    private let session: URLSession
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    public static func endpoint(for base: String) throws -> URL {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw ChatError.invalidURL
        }
        return url.path.hasSuffix("/chat/completions") ? url : url.appendingPathComponent("chat/completions")
    }

    public static func supportsSearch(baseURL: String, model: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased(), model.lowercased().hasPrefix("qwen") else { return false }
        return host.hasSuffix(".maas.aliyuncs.com") || host == "dashscope.aliyuncs.com" || host == "dashscope-intl.aliyuncs.com"
    }
    public static func searchEndpoint(baseURL: String, model: String) throws -> URL {
        _ = try endpoint(for: baseURL)
        guard supportsSearch(baseURL: baseURL, model: model), var parts = URLComponents(string: baseURL) else { throw ChatError.invalidURL }
        let multimodal = ["qwen3.8", "qwen3.7-flash", "qwen3.7-plus", "qwen3.6", "qwen3.5", "qwen-vl", "qwen2.5-vl"].contains { model.lowercased().hasPrefix($0) }
        parts.path = "/api/v1/services/aigc/\(multimodal ? "multimodal-generation" : "text-generation")/generation"
        guard let url = parts.url else { throw ChatError.invalidURL }
        return url
    }

    public func stream(baseURL: String, key: String, model: String, messages: [ChatMessage],
                       webSearch: Bool = false, forceSearch: Bool = false,
                       onSources: @escaping @Sendable ([SearchSource]) async -> Void = { _ in },
                       onText: @escaping @Sendable (String) async -> Void) async throws {
        let config = ConnectionConfiguration(baseURL: baseURL, key: key, model: model)
        if let issue = config.issue { throw ChatError.configuration(issue) }
        let key = config.key, model = config.model, baseURL = config.baseURL
        let endpoint = try webSearch ? Self.searchEndpoint(baseURL: baseURL, model: model) : Self.endpoint(for: baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["model": model, "stream": true,
                                   "messages": messages.map { ["role": $0.role, "content": $0.content] }]
        if model.lowercased().hasPrefix("qwen") { body["enable_thinking"] = false }
        if webSearch {
            request.setValue("enable", forHTTPHeaderField: "X-DashScope-SSE")
            let multimodal = endpoint.path.contains("multimodal-generation")
            let input: [[String: Any]] = messages.map {
                ["role": $0.role, "content": multimodal ? [["text": $0.content]] as Any : $0.content as Any]
            }
            body = ["model": model, "input": ["messages": input], "parameters": [
                "enable_search": true, "enable_thinking": false, "incremental_output": true,
                "result_format": "message", "search_options": [
                    "enable_source": true, "enable_citation": false, "search_strategy": "turbo",
                    "prepend_search_result": true, "forced_search": forceSearch
                ]
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if let failure = await Self.diagnosticFailure(from: bytes), failure != .unknown,
               failure != .rejected || [400, 422].contains(response.statusCode) {
                throw ChatError.failure(failure)
            }
            throw ChatError.status(response.statusCode)
        }
        if let mime = response.mimeType?.lowercased(), mime != "text/event-stream" {
            if let failure = await Self.diagnosticFailure(from: bytes), failure != .unknown { throw ChatError.failure(failure) }
            throw ChatError.invalidResponse
        }
        var decoder = SSEDecoder()
        var receivedText = false
        var receivedCompletion = false
        var lineBytes = Data()
        // AsyncBytes.lines omits blank lines on some Foundation releases. SSE needs
        // those delimiters, so preserve them while decoding complete UTF-8 lines.
        for try await byte in bytes {
            try Task.checkCancellation()
            guard byte == 10 else {
                lineBytes.append(byte)
                guard lineBytes.count <= 1_048_576 else { throw ChatError.invalidResponse }
                continue
            }
            if lineBytes.last == 13 { lineBytes.removeLast() }
            guard let line = String(data: lineBytes, encoding: .utf8) else { throw ChatError.invalidResponse }
            lineBytes.removeAll(keepingCapacity: true)
            if let event = try decoder.consume(line: line) {
                if !event.sources.isEmpty { await onSources(event.sources) }
                if !event.text.isEmpty {
                    receivedText = receivedText || !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    await onText(event.text)
                }
                if let failure = event.failure { throw ChatError.failure(failure) }
                if event.done { receivedCompletion = true; break }
            }
        }
        if !lineBytes.isEmpty {
            guard let line = String(data: lineBytes, encoding: .utf8) else { throw ChatError.invalidResponse }
            _ = try decoder.consume(line: line)
        }
        if let event = try decoder.flush() {
            if !event.sources.isEmpty { await onSources(event.sources) }
            if !event.text.isEmpty {
                receivedText = receivedText || !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                await onText(event.text)
            }
            if let failure = event.failure { throw ChatError.failure(failure) }
            receivedCompletion = receivedCompletion || event.done
        }
        try Task.checkCancellation()
        if !receivedText { throw ChatError.emptyResponse }
        if !receivedCompletion { throw ChatError.failure(.interrupted) }
    }

    private static func diagnosticFailure(from bytes: URLSession.AsyncBytes) async -> ModelFailureReason? {
        var body = Data()
        // Inspect bounded structured codes only. Never return provider messages.
        do {
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 16_384 { break }
            }
        } catch { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return ModelFailureReason.providerError(in: object)
    }
}
