import AppKit
import Testing
import InstantCore
@testable import Instant

/// AppKit's rubber-band machinery can place a clip outside its normal range.
/// A direct public setBoundsOrigin call normally clamps instead, so this test
/// clip permits only injected native-animation samples to bypass that clamp.
/// Application scroll(to:) calls retain AppKit's ordinary constraints.
private final class ElasticSampleClipView: NSClipView {
    private var injectingSample = false
    func sample(_ y: CGFloat) {
        injectingSample = true
        setBoundsOrigin(NSPoint(x: 0, y: y))
        injectingSample = false
    }
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        injectingSample ? proposedBounds : super.constrainBoundsRect(proposedBounds)
    }
}

@MainActor @Suite(.serialized)
struct TranscriptScrollTests {
    private func fixture() -> (TranscriptView, Conversation) {
        _ = NSApplication.shared
        let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 680, height: 240), clipView: ElasticSampleClipView())
        view.maximumViewportHeight = 240
        var conversation = Conversation()
        var turn = Turn(question: "Scrolling regression fixture", mode: .chat)
        turn.answer = (1...70).map { "Line \($0): enough content to scroll past the viewport." }.joined(separator: "\n")
        turn.state = .complete
        conversation.turns = [turn]
        view.render(conversation, forceFollow: true)
        view.layout()
        return (view, conversation)
    }

    private func end(_ view: TranscriptView) -> CGFloat {
        max(0, view.text.frame.height - view.contentView.bounds.height)
    }

    @Test func layoutPreservesEachBottomReboundPosition() {
        let (view, _) = fixture()
        let bottom = end(view)
        #expect(bottom > 0)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(bottom + 48)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        for displacement: CGFloat in [48, 24, 8, 2, 0.25, 0] {
            let expected = bottom + displacement
            (view.contentView as! ElasticSampleClipView).sample(expected)
            #expect(abs(view.contentView.bounds.minY - expected) < 0.001)
            view.layout()
            #expect(abs(view.contentView.bounds.minY - expected) < 0.001)
        }
    }

    @Test func layoutPreservesTopReboundAndOrdinaryReadingPosition() {
        let (view, _) = fixture()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        for position: CGFloat in [-40, -10, -0.25, 0, 150] {
            (view.contentView as! ElasticSampleClipView).sample(position)
            view.layout()
            #expect(abs(view.contentView.bounds.minY - position) < 0.001)
        }
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
    }

    @Test func textUpdatesDuringReboundWhileDocumentBoundaryWaits() async throws {
        let (view, conversation) = fixture()
        let previousText = view.text.string
        let previousHeight = view.text.frame.height
        let previousShellMeasurement = view.contentHeight
        let bottom = end(view)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(bottom + 30)
        var updated = conversation
        updated.turns[0].answer += "\nNewly streamed answer."
        view.render(updated)
        #expect(view.text.string.count > previousText.count)
        #expect(view.text.frame.height == previousHeight)
        #expect(view.contentHeight == previousShellMeasurement)
        #expect(abs(view.contentView.bounds.minY - (bottom + 30)) < 0.001)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        try await Task.sleep(for: .milliseconds(20))
        #expect(view.text.frame.height == previousHeight)
        (view.contentView as! ElasticSampleClipView).sample(bottom)
        try await Task.sleep(for: .milliseconds(30))
        #expect(view.text.string.contains("Newly streamed answer."))
        #expect(view.text.frame.height > previousHeight)
        #expect(view.contentHeight > previousShellMeasurement)
        #expect(abs(view.contentView.bounds.minY - end(view)) < 0.001)
    }

    @Test func liveChunksArriveWithoutDraggingAReaderToTheBottom() async throws {
        let (view, conversation) = fixture()
        var didApplyDeferredContent = false
        view.onDeferredContentChange = { didApplyDeferredContent = true }
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(150)
        var updated = conversation
        updated.turns[0].answer += "\nFirst chunk."
        view.render(updated)
        updated.turns[0].answer += "\nLast chunk."
        view.render(updated)
        #expect(view.text.string.contains("First chunk.\nLast chunk."))
        #expect(abs(view.contentView.bounds.minY - 150) < 0.001)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        try await Task.sleep(for: .milliseconds(30))
        #expect(view.text.string.contains("First chunk.\nLast chunk."))
        #expect(abs(view.contentView.bounds.minY - 150) < 0.001)
        #expect(didApplyDeferredContent)
    }

    @Test func clearingDuringScrollCannotRestoreAStaleConversation() async throws {
        let (view, conversation) = fixture()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        view.render(conversation)
        view.render(Conversation())
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        try await Task.sleep(for: .milliseconds(30))
        #expect(view.text.string.isEmpty)
        #expect(view.contentView.bounds.minY == 0)
    }

    @Test func freshRevealRecoversFromAnInterruptedGesture() {
        let (view, conversation) = fixture()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(end(view) + 30)
        var updated = conversation
        updated.turns[0].answer += "\nCompleted while hidden."
        view.render(updated)
        view.prepareForPresentation()
        view.render(updated)
        #expect(view.text.string.contains("Completed while hidden."))
        #expect(abs(view.contentView.bounds.minY - end(view)) < 0.001)
    }

    @Test func settledScrollCommitsTheFinalChunkWithoutAnEndNotificationOrReopening() async throws {
        let (view, conversation) = fixture()
        let originalBottom = end(view)
        let originalHeight = view.text.frame.height
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(originalBottom + 32)
        var updated = conversation
        updated.turns[0].answer += "\n" + String(repeating: "Final streamed lines must remain reachable.\n", count: 30)
        view.render(updated)
        #expect(view.text.frame.height == originalHeight)
        // AppKit returned the clip, but didEndLiveScroll never arrived. There
        // are no more model chunks to incidentally trigger another render.
        (view.contentView as! ElasticSampleClipView).sample(originalBottom)
        try await Task.sleep(for: .milliseconds(700))
        #expect(view.text.frame.height > originalHeight)
        #expect(abs(view.contentView.bounds.minY - end(view)) < 1)
        let manager = try #require(view.text.layoutManager)
        let container = try #require(view.text.textContainer)
        let range = (view.text.string as NSString).range(of: "Final streamed lines must remain reachable.", options: .backwards)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: view.text.textContainerOrigin.x, dy: view.text.textContainerOrigin.y)
        #expect(rect.intersects(view.documentVisibleRect))
    }

    @Test func interruptedReboundCannotLeaveFinalTextOutsideTheDocumentForever() async throws {
        let (view, conversation) = fixture()
        let bottom = end(view)
        let originalHeight = view.text.frame.height
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(bottom + 18)
        var updated = conversation
        updated.turns[0].answer += "\n" + String(repeating: "Completed answer after an interrupted return.\n", count: 25)
        view.render(updated)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        // The native spring stopped delivering samples before reaching zero.
        try await Task.sleep(for: .milliseconds(700))
        #expect(view.text.frame.height > originalHeight)
        #expect(abs(view.contentView.bounds.minY - end(view)) < 1)
    }

    @Test func recoveryWaitsForAnActuallyMovingSpringAndForAHeldScrollbar() async throws {
        let (view, conversation) = fixture()
        let bottom = end(view)
        let originalHeight = view.text.frame.height
        let clip = view.contentView as! ElasticSampleClipView
        let scroller = try #require(view.verticalScroller as? TranscriptScroller)
        scroller.onTrackingChange?(true)
        clip.sample(bottom + 50)
        var updated = conversation
        updated.turns[0].answer += "\nA delayed final line."
        view.render(updated)
        try await Task.sleep(for: .milliseconds(400))
        #expect(view.text.frame.height == originalHeight)
        #expect(view.contentView.bounds.minY == bottom + 50)
        scroller.onTrackingChange?(false)
        for offset: CGFloat in [40, 30, 20, 10, 5] {
            clip.sample(bottom + offset)
            try await Task.sleep(for: .milliseconds(100))
            #expect(view.text.frame.height == originalHeight)
            #expect(view.contentView.bounds.minY == bottom + offset)
        }
        clip.sample(bottom)
        try await Task.sleep(for: .milliseconds(50))
        #expect(view.text.frame.height > originalHeight)
    }

    @Test func continuousChunksDoNotStarveRecoveryOrMoveAReaderFromTheMiddle() async throws {
        let (view, conversation) = fixture()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(150)
        var updated = conversation
        var reconciled = false
        view.onDeferredContentChange = { reconciled = true }
        for index in 1...12 {
            updated.turns[0].answer += "\nContinuing chunk \(index)."
            view.render(updated)
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reconciled)
        #expect(view.text.string.contains("Continuing chunk 12."))
        #expect(view.contentView.bounds.minY == 150)
    }

    @Test func growingAnswerViewportStillKeepsTheFirstLineFixed() {
        _ = NSApplication.shared
        let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 680, height: 54))
        view.maximumViewportHeight = 480
        var conversation = Conversation()
        var turn = Turn(question: "Question stays at the top", mode: .chat)
        turn.answer = "First line\nSecond line\nThird line\nFourth line"
        turn.state = .complete
        conversation.turns = [turn]
        view.render(conversation, forceFollow: true)
        for height: CGFloat in [54, 80, 120, 180, 240] {
            view.setFrameSize(NSSize(width: 680, height: height))
            view.layout()
            #expect(view.contentView.bounds.minY == 0)
        }
    }

    @Test func restingFractionalOffsetDoesNotBlockNewOutput() {
        let (view, conversation) = fixture()
        // AppKit can rest on a backing-pixel boundary fractionally beyond our
        // arithmetic content-height boundary, without any active gesture.
        (view.contentView as! ElasticSampleClipView).sample(end(view) + 0.25)
        var updated = conversation
        updated.turns[0].answer += "\nOutput after pixel alignment."
        view.render(updated)
        #expect(view.text.string.contains("Output after pixel alignment."))
    }

    @Test func completedReboundWithSubpixelRemainderCommitsDocumentGrowth() async throws {
        let (view, conversation) = fixture()
        let bottom = end(view)
        let previousHeight = view.text.frame.height
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(bottom + 30)
        var updated = conversation
        updated.turns[0].answer += "\nSettled on a physical pixel."
        view.render(updated)
        #expect(view.text.frame.height == previousHeight)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(bottom + 0.25)
        try await Task.sleep(for: .milliseconds(30))
        #expect(view.text.string.contains("Settled on a physical pixel."))
        #expect(view.text.frame.height > previousHeight)
    }

    @Test func explicitQuestionOverridesAnUnfinishedScrollSession() {
        let (view, conversation) = fixture()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(end(view) + 24)
        view.text.setSelectedRange(NSRange(location: 0, length: 8))
        var updated = conversation
        updated.turns.append(Turn(question: "A newly submitted question", mode: .chat))
        view.render(updated, forceFollow: true)
        #expect(view.text.string.contains("A newly submitted question"))
        updated.turns[1].answer = "Visible streamed answer."
        view.render(updated)
        #expect(view.text.string.contains("Visible streamed answer."))
        #expect(view.text.selectedRange().length == 0)
        #expect(abs(view.contentView.bounds.minY - end(view)) < 1)
    }

    @Test func longConversationCanKeepShowingSuccessiveQuestionsAndReplies() {
        let (view, initial) = fixture()
        var conversation = initial
        for index in 1...12 {
            (view.contentView as! ElasticSampleClipView).sample(end(view) + 0.25)
            conversation.turns.append(Turn(question: "Follow-up question \(index)", mode: .chat))
            view.render(conversation, forceFollow: true)
            #expect(view.text.string.contains("Follow-up question \(index)"))
            conversation.turns[index].answer = "Answer \(index), first chunk."
            view.render(conversation)
            conversation.turns[index].answer += "\nLast chunk \(index)."
            conversation.turns[index].state = .complete
            view.render(conversation)
            #expect(view.text.string.contains("Last chunk \(index)."))
            #expect(abs(view.contentView.bounds.minY - end(view)) < 1)
        }
    }

    @Test func nativeFractionalViewportKeepsNewTurnGlyphsVisible() {
        _ = NSApplication.shared
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 474.5),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 680, height: 474.5))
        host.contentView = view
        view.maximumViewportHeight = 474.4
        var conversation = Conversation()
        var first = Turn(question: "Long conversation", mode: .chat)
        first.answer = (1...80).map { "Earlier content \($0)." }.joined(separator: "\n")
        first.state = .complete
        conversation.turns = [first]
        view.render(conversation, forceFollow: true)
        view.layoutSubtreeIfNeeded()
        for index in 1...8 {
            let question = "原生窗口追问 \(index)"
            let answer = "回答 \(index)：这段应出现在可见区域。"
            conversation.turns.append(Turn(question: question, mode: .chat))
            view.render(conversation, forceFollow: true)
            conversation.turns[index].answer = answer
            conversation.turns[index].state = .complete
            view.render(conversation)
            view.layoutSubtreeIfNeeded()
            for marker in [question, answer] {
                let range = (view.text.string as NSString).range(of: marker, options: .backwards)
                #expect(range.location != NSNotFound)
                if range.location != NSNotFound, let manager = view.text.layoutManager, let container = view.text.textContainer {
                    let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                        .offsetBy(dx: view.text.textContainerOrigin.x, dy: view.text.textContainerOrigin.y)
                    #expect(rect.intersects(view.documentVisibleRect))
                }
            }
        }
    }

    @Test func draggingScrollbarDoesNotSuspendIncomingTextOrDocumentGrowth() {
        let (view, conversation) = fixture()
        let initialHeight = view.text.frame.height
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        (view.contentView as! ElasticSampleClipView).sample(150)
        var updated = conversation
        for index in 1...5 {
            updated.turns[0].answer += "\nNew text while dragging \(index)."
            view.render(updated)
            let visibleInDocument = view.text.string.contains("New text while dragging \(index).")
            #expect(visibleInDocument)
            #expect(view.text.frame.height > initialHeight)
            #expect(abs(view.contentView.bounds.minY - 150) < 0.001)
        }
        // The user can drag all the way into the newly appended content before
        // AppKit sends didEndLiveScroll, even if that notification is delayed.
        (view.contentView as! ElasticSampleClipView).sample(end(view))
        let lastRange = (view.text.string as NSString).range(of: "New text while dragging 5.")
        #expect(lastRange.location != NSNotFound)
        if lastRange.location != NSNotFound, let manager = view.text.layoutManager, let container = view.text.textContainer {
            let glyphs = manager.glyphRange(forCharacterRange: lastRange, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: view.text.textContainerOrigin.x, dy: view.text.textContainerOrigin.y)
            #expect(rect.intersects(view.documentVisibleRect))
        }
    }

    @Test func releasingScrollbarAtBottomResumesFollowingTheStream() async throws {
        let (view, conversation) = fixture()
        let scroller = try #require(view.verticalScroller as? TranscriptScroller)
        #expect(view.scrollerStyle == .overlay)
        scroller.onTrackingChange?(true)
        (view.contentView as! ElasticSampleClipView).sample(end(view))
        var updated = conversation
        updated.turns[0].answer += "\nArrived while holding the bottom."
        view.render(updated)
        let receivedWhileDragging = view.text.string.contains("Arrived while holding the bottom.")
        #expect(receivedWhileDragging)
        // The knob tracking scope ends even without a didEnd notification.
        scroller.onTrackingChange?(false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(abs(view.contentView.bounds.minY - end(view)) < 1)
        updated.turns[0].answer += "\nStream continues after release."
        view.render(updated)
        #expect(abs(view.contentView.bounds.minY - end(view)) < 1)
        let receivedAfterRelease = view.text.string.contains("Stream continues after release.")
        #expect(receivedAfterRelease)
    }
}
