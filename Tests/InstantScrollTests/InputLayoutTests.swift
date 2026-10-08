import AppKit
import Testing
import InstantCore
@testable import Instant

@MainActor @Suite(.serialized)
struct InputLayoutTests {
    private func fixture() -> (NSWindow, ComposerView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 68),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let composer = ComposerView(frame: NSRect(x: 0, y: 0, width: 680, height: 68))
        window.contentView = composer
        composer.wantsLayer = true
        composer.onHeightChange = { [weak window, weak composer] height in
            window?.setContentSize(NSSize(width: 680, height: height))
            composer?.layoutSubtreeIfNeeded()
        }
        composer.layoutSubtreeIfNeeded()
        window.makeFirstResponder(composer.editor)
        return (window, composer)
    }
    private func replace(_ value: String, in composer: ComposerView) {
        composer.editor.insertText(value, replacementRange: NSRange(location: 0, length: (composer.editor.string as NSString).length))
        composer.layoutSubtreeIfNeeded()
    }
    private func caretRect(_ editor: NSTextView, in window: NSWindow) -> NSRect {
        let screen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        return editor.convert(window.convertFromScreen(screen), from: nil)
    }
    private func baseline(_ composer: ComposerView) throws -> CGFloat {
        let manager = try #require(composer.editor.layoutManager)
        let point = NSPoint(x: 0, y: composer.editor.textContainerOrigin.y + manager.location(forGlyphAt: 0).y)
        return composer.editor.convert(point, to: composer).y
    }

    @Test func collapsingLongInputRemovesTheOldScrollableDocumentImmediately() throws {
        let (window, composer) = fixture()
        defer { window.close() }
        replace(String(repeating: "多行输入内容\n", count: 20), in: composer)
        #expect(composer.desiredHeight == 124)
        composer.editor.scrollRangeToVisible(composer.editor.selectedRange())
        composer.clear()
        let clip = try #require(composer.editor.enclosingScrollView?.contentView)
        #expect(composer.desiredHeight == 68)
        #expect(composer.editor.frame.height == clip.bounds.height)
        #expect(clip.bounds.minY == 0)
        replace("帮我写一段", in: composer)
        composer.editor.scrollRangeToVisible(composer.editor.selectedRange())
        #expect(clip.bounds.minY == 0)
        #expect(composer.editor.visibleRect.insetBy(dx: -1, dy: -1).contains(caretRect(composer.editor, in: window)))
    }

    @Test func chineseLatinAndAccentsKeepOneBaselineAndAnUnclippedCaret() throws {
        let (window, composer) = fixture()
        defer { window.close() }
        var reference: CGFloat?
        for value in ["Agjp", "帮我写一段", "Ag 帮我写一段 jp", "ÁÉ Ångström", "日本語 한국어", "🙂 👩‍💻"] {
            replace(value, in: composer)
            composer.editor.scrollRangeToVisible(composer.editor.selectedRange())
            let current = try baseline(composer)
            if let reference { #expect(abs(current - reference) < 0.5) }
            else { reference = current }
            #expect(composer.desiredHeight == 68)
            #expect(composer.editor.visibleRect.insetBy(dx: -1, dy: -1).contains(caretRect(composer.editor, in: window)))
        }
    }

    @Test func markedChineseAndThreeLinesStayVisibleWhileCommittingAndShrinking() throws {
        let (window, composer) = fixture()
        defer { window.close() }
        let editor = composer.editor
        editor.setMarkedText("帮我写一段", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        composer.layoutSubtreeIfNeeded()
        #expect(editor.hasMarkedText())
        #expect(editor.visibleRect.insetBy(dx: -1, dy: -1).contains(caretRect(editor, in: window)))
        editor.unmarkText()
        let firstBaseline = try baseline(composer)
        replace("帮我写一段\n第二行中文\n第三行 Agjp", in: composer)
        #expect(composer.desiredHeight == 124)
        #expect(abs(try baseline(composer) - firstBaseline) < 0.5)
        #expect(editor.visibleRect.insetBy(dx: -1, dy: -1).contains(caretRect(editor, in: window)))
        replace("帮我写一段", in: composer)
        #expect(composer.desiredHeight == 68)
        #expect(editor.enclosingScrollView?.contentView.bounds.minY == 0)
        #expect(abs(try baseline(composer) - firstBaseline) < 0.5)
    }

    @Test func fittingTextCannotScrollButLongInputStillReachesBothEnds() throws {
        let (window, composer) = fixture()
        defer { window.close() }
        replace("帮我写一段", in: composer)
        let clip = try #require(composer.editor.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: 20))
        #expect(clip.bounds.minY == 0)
        clip.scroll(to: NSPoint(x: 0, y: -20))
        #expect(clip.bounds.minY == 0)
        clip.setBoundsOrigin(NSPoint(x: 0, y: 12))
        #expect(clip.bounds.minY == 0)
        replace((1...12).map { "第 \($0) 行中文输入" }.joined(separator: "\n"), in: composer)
        composer.editor.scrollRangeToVisible(composer.editor.selectedRange())
        #expect(clip.bounds.minY > 0)
        #expect(composer.editor.visibleRect.insetBy(dx: -1, dy: -1).contains(caretRect(composer.editor, in: window)))
        composer.editor.setSelectedRange(NSRange(location: 0, length: 0))
        composer.editor.scrollRangeToVisible(composer.editor.selectedRange())
        #expect(clip.bounds.minY == 0)
    }
}
