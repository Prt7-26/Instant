import AppKit
import InstantCore

var resumedDraft: String?
if let index = CommandLine.arguments.firstIndex(of: "--relaunch"),
   CommandLine.arguments.indices.contains(index + 1), let parent = Int32(CommandLine.arguments[index + 1]), parent > 0 {
    for _ in 0..<100 {
        if kill(parent, 0) != 0 { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    guard kill(parent, 0) != 0 else { exit(1) }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    resumedDraft = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["draft"]
}

if CommandLine.arguments.contains("--configure") {
    // Read credentials over stdin, never from process arguments or project files.
    struct ConfigurationInput: Decodable { let apiKey: String; let baseURL: String; let model: String }
    do {
        guard let line = readLine(), let data = line.data(using: .utf8) else { throw ChatError.missingKey }
        let input = try JSONDecoder().decode(ConfigurationInput.self, from: data)
        let connection = ConnectionConfiguration(baseURL: input.baseURL, key: input.apiKey, model: input.model)
        if let issue = connection.issue { throw ChatError.configuration(issue) }
        let settings = SettingsStore()
        settings.value.baseURL = connection.baseURL
        settings.value.model = connection.model
        try Keychain.save(connection.key)
        print("Connection configured; API Key stored in macOS Keychain.")
        exit(0)
    } catch { fputs("Could not save connection configuration.\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--smoke-test") {
    let verificationKey = CommandLine.arguments.contains("--key-stdin") ? readLine() : nil
    Task { @MainActor in
        do {
            let settings = SettingsStore(readKeychain: verificationKey == nil)
            var conversation = Conversation()
            let translating = CommandLine.arguments.contains("--translation")
            let searching = CommandLine.arguments.contains("--search")
            conversation.turns.append(Turn(question: searching ? "请联网查询今天杭州的天气，简短回答。" : (translating ? "serendipity" : "只回答：连接正常"), mode: translating ? .translation : .chat))
            let service = ChatService()
            let start = Date()
            let counter = SmokeResult()
            try await service.stream(baseURL: settings.value.baseURL, key: verificationKey ?? settings.apiKey,
                                     model: settings.value.model,
                                     messages: PromptBuilder.messages(conversation: conversation, language: Language.resolve("zh-Hans"), searchAvailable: searching),
                                     webSearch: searching, forceSearch: searching,
                                     onSources: { await counter.appendSources($0) }) { part in
                await counter.append(part)
            }
            let output = await counter.text
            print("Stream OK · \(output.count) characters · \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            print(output)
            if searching {
                let sources = await counter.sources
                print("Search sources: \(sources.count)")
                for source in sources.prefix(5) { print("\(source.title) · \(source.url.absoluteString)") }
                if sources.isEmpty { exit(2) }
            }
            exit(0)
        } catch { print("Stream failed: \(error.localizedDescription)"); exit(1) }
    }
    dispatchMain()
}

actor SmokeResult {
    var text = ""
    var sources: [SearchSource] = []
    func append(_ value: String) { text += value }
    func appendSources(_ value: [SearchSource]) { sources = SearchSource.unique(sources + value) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    delegate.startupDraft = resumedDraft
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
