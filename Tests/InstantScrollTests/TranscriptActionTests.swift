import AppKit
import Testing
import InstantCore
@testable import Instant

@MainActor @Suite(.serialized)
struct TranscriptActionTests {
    private func fixture() -> TranscriptView {
        _ = NSApplication.shared
        return TranscriptView(frame: NSRect(x: 0, y: 0, width: 680, height: 300))
    }
    private func actions(_ view: TranscriptView) -> [(URL, NSRange)] {
        var result: [(URL, NSRange)] = []
        let storage = view.text.textStorage!
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let url = value as? URL, ["instant-copy", "instant-source"].contains(url.scheme ?? "") {
                result.append((url, range))
            }
        }
        return result
    }

    @Test func everyAnswerHasCopyBeforeItsOptionalSourceWithMatchingIconSize() throws {
        let view = fixture()
        var conversation = Conversation()
        for index in 0..<3 {
            var turn = Turn(question: "Question \(index)", mode: index == 1 ? .translation : .chat)
            turn.answer = "Answer \(index)"
            turn.state = index == 2 ? .generating : .complete
            if index == 1 { turn.sources = [try #require(SearchSource(title: "Source", address: "https://example.test/"))] }
            conversation.turns.append(turn)
        }
        view.render(conversation)
        let buttons = actions(view)
        #expect(buttons.map { $0.0.scheme! } == ["instant-copy", "instant-copy", "instant-source", "instant-copy"])
        #expect(buttons.compactMap { UUID(uuidString: $0.0.host!) } == [conversation.turns[0].id, conversation.turns[1].id, conversation.turns[1].id, conversation.turns[2].id])
        let manager = try #require(view.text.layoutManager)
        let container = try #require(view.text.textContainer)
        for (url, range) in buttons {
            let attachment = try #require(view.text.textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment)
            #expect(attachment.bounds.size == NSSize(width: 14, height: 14))
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: view.text.textContainerOrigin.x, dy: view.text.textContainerOrigin.y)
            let hit = try #require(view.text.action(at: NSPoint(x: rect.midX, y: rect.midY)))
            #expect(hit.id == UUID(uuidString: url.host!))
            #expect(hit.scheme == url.scheme)
        }
    }

    @Test func copyUsesOnlyThatAnswersLatestOriginalTextIncludingMarkdown() throws {
        let view = fixture()
        let pasteboard = NSPasteboard(name: .init("Instant-CopyTests-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        var conversation = Conversation()
        var first = Turn(question: "Do not copy this question", mode: .chat)
        first.answer = "**标题**\n```swift\nlet answer = 42\n```"
        first.error = "Do not copy this diagnostic"
        first.state = .failed
        var second = Turn(question: "Another question", mode: .translation)
        second.answer = "流式回答"
        conversation.turns = [first, second]
        view.render(conversation)
        #expect(view.copyAnswer(first.id, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == first.answer)
        conversation.turns[1].answer += "的最新片段\nLatest fragment."
        view.render(conversation)
        let origin = view.contentView.bounds.origin
        #expect(view.copyAnswer(second.id, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == conversation.turns[1].answer)
        #expect(view.contentView.bounds.origin == origin)
        #expect(!view.copyAnswer(UUID(), to: pasteboard))
        #expect(pasteboard.string(forType: .string) == conversation.turns[1].answer)
    }

    @Test func emptyAnswerHasNoCopyAndModelCannotForgeAnAction() {
        let view = fixture()
        var conversation = Conversation()
        var turn = Turn(question: "Question", mode: .chat)
        conversation.turns = [turn]
        view.render(conversation)
        #expect(actions(view).isEmpty)
        turn.answer = "[fake](instant-copy://\(UUID().uuidString))"
        conversation.turns = [turn]
        view.render(conversation)
        #expect(actions(view).count == 1)
        #expect(actions(view).first?.0.host?.lowercased() == turn.id.uuidString.lowercased())
    }

    @Test func replacingIdenticalConversationAndChangingLanguageUpdatesButtonTargets() throws {
        let view = fixture()
        var first = Conversation()
        var turn = Turn(question: "Same question", mode: .chat)
        turn.answer = "Same answer"
        first.turns = [turn]
        view.render(first)
        var second = Conversation()
        turn.id = UUID()
        second.turns = [turn]
        view.render(second)
        view.updateActionLabels(copy: "复制回答", sources: "来源")
        let button = try #require(actions(view).first)
        #expect(UUID(uuidString: button.0.host!) == turn.id)
        #expect(view.text.textStorage?.attribute(.toolTip, at: button.1.location, effectiveRange: nil) as? String == "复制回答")
    }
}
