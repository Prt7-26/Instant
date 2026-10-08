import AppKit
import InstantCore

final class InputTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onToggleTranslation: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onSettings: (() -> Void)?
    var onArchive: (() -> Void)?
    var configuration: (() -> AppConfiguration)?
    private var lastSpace: TimeInterval?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if !hasMarkedText(), event.keyCode == 53 { onDismiss?(); return }
        if !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 {
            lastSpace = nil
            if modifiers.contains(.shift) { insertNewline(nil) }
            else { onSubmit?() }
            return
        }
        if !hasMarkedText(), event.keyCode == 49, modifiers.isEmpty,
           configuration?().translationShortcut == "doubleSpace" {
            if (string.isEmpty || string == " "), let previous = lastSpace,
                      event.timestamp - previous <= 0.35, !event.isARepeat {
                string = ""
                didChangeText()
                lastSpace = nil
                onToggleTranslation?()
                return
            } else if string.isEmpty { lastSpace = event.timestamp }
            else { lastSpace = nil }
        } else { lastSpace = nil }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleShortcut(event) || super.performKeyEquivalent(with: event)
    }
    func handleShortcut(_ event: NSEvent) -> Bool {
        guard !hasMarkedText() else { return false }
        let flags = Shortcut.carbon(event.modifierFlags)
        if event.keyCode == 43, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command {
            onSettings?(); return true
        }
        if let config = configuration?() {
            if UInt32(event.keyCode) == config.archiveKeyCode, flags == config.archiveModifiers {
                onArchive?(); return true
            }
            let shortcut = config.translationShortcut
            let code: UInt32 = shortcut == "custom" ? config.translationKeyCode : 17
            let target: UInt32 = shortcut == "commandT" ? 256 : (shortcut == "custom" ? config.translationModifiers : 768)
            if shortcut != "doubleSpace", UInt32(event.keyCode) == code, flags == target {
                onToggleTranslation?(); return true
            }
        }
        return false
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var onAppearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onAppearanceChanged?() }
}

final class StableClipView: NSClipView {
    var expectedViewportHeight: CGFloat = 28
    // Caret scrolling can call these setters without asking AppKit to constrain
    // the proposed bounds. The input never needs elastic out-of-range origins.
    override func scroll(to newOrigin: NSPoint) {
        var proposed = bounds
        proposed.origin = newOrigin
        super.scroll(to: constrainBoundsRect(proposed).origin)
    }
    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        var proposed = bounds
        proposed.origin = newOrigin
        super.setBoundsOrigin(constrainBoundsRect(proposed).origin)
    }
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        let height = documentView?.frame.height ?? 0
        let maximumOrigin = max(0, height - max(constrained.height, expectedViewportHeight))
        constrained.origin.y = min(maximumOrigin, max(0, constrained.origin.y))
        return constrained
    }
}

final class ComposerView: NSView, NSTextViewDelegate, NSLayoutManagerDelegate {
    private static let drawingInset: CGFloat = 6
    let editor = InputTextView()
    private let scroll = NSScrollView()
    private let modeIcon = NSImageView()
    private let archiveButton = NSButton()
    private let clip = StableClipView()
    private var measuring = false
    var onTextChange: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onArchive: (() -> Void)?
    private(set) var desiredHeight: CGFloat = 68
    private var translation = false
    private var iconOffset: CGFloat = 0
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
        scroll.drawsBackground = false
        scroll.contentView = clip
        clip.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = editor
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 22, weight: .regular)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        // Keep the 28 pt line grid, but give glyph overhangs and IME marks
        // room outside the line fragment instead of clipping at its edge.
        editor.textContainerInset = NSSize(width: 0, height: Self.drawingInset)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = false
        editor.autoresizingMask = []
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.delegate = self
        editor.layoutManager?.delegate = self
        editor.layoutManager?.usesFontLeading = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 28
        paragraph.maximumLineHeight = 28
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 22), .paragraphStyle: paragraph,
                                   .foregroundColor: NSColor.labelColor]
        editor.setAccessibilityIdentifier("instant.input")
        modeIcon.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Translate")
        modeIcon.symbolConfiguration = .init(pointSize: 19, weight: .regular)
        modeIcon.contentTintColor = .secondaryLabelColor
        modeIcon.alphaValue = 0
        modeIcon.isHidden = true
        modeIcon.setAccessibilityElement(false)
        addSubview(modeIcon)
        addSubview(scroll)
        archiveButton.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        archiveButton.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        archiveButton.imagePosition = .imageOnly
        archiveButton.isBordered = false
        archiveButton.refusesFirstResponder = true
        archiveButton.contentTintColor = .secondaryLabelColor
        archiveButton.target = self
        archiveButton.action = #selector(archiveClicked)
        archiveButton.isEnabled = false
        archiveButton.setAccessibilityIdentifier("instant.archive")
        addSubview(archiveButton)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setLanguage(_ language: Language) {
        let words = L10n(language: language)
        editor.setAccessibilityLabel(words["input"])
        modeIcon.setAccessibilityLabel(words["translation"])
        archiveButton.setAccessibilityLabel(words["archiveNow"])
        editor.baseWritingDirection = .natural
    }
    func updateArchiveButton(enabled: Bool, label: String, shortcut: String) {
        archiveButton.isEnabled = enabled
        archiveButton.toolTip = "\(label) · \(shortcut)"
    }
    @objc private func archiveClicked() { onArchive?() }
    func setMode(_ mode: ConversationMode, animated: Bool) {
        translation = mode == .translation
        modeIcon.isHidden = !translation
        modeIcon.setAccessibilityElement(translation)
        iconOffset = translation ? 33 : 0
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !reduced ? 0.16 : 0
            modeIcon.animator().alphaValue = translation ? 1 : 0
        }
        editor.setAccessibilityHelp(translation ? modeIcon.accessibilityLabel() : nil)
        needsLayout = true
        layoutSubtreeIfNeeded()
        recalculateHeight()
    }
    private var editorFrame: NSRect {
        NSRect(x: 27 + iconOffset, y: 20 - Self.drawingInset, width: max(40, bounds.width - 87 - iconOffset),
               height: max(28, bounds.height - 40) + Self.drawingInset * 2)
    }
    override func layout() {
        super.layout()
        modeIcon.frame = NSRect(x: 26, y: 23, width: 22, height: 22)
        archiveButton.frame = NSRect(x: bounds.width - 51, y: 22, width: 24, height: 24)
        if scroll.frame != editorFrame { scroll.frame = editorFrame }
        scroll.layoutSubtreeIfNeeded()
        let width = scroll.contentSize.width
        if editor.textContainer?.containerSize.width != width {
            editor.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        recalculateHeight()
    }
    func textDidChange(_ notification: Notification) {
        recalculateHeight()
        onTextChange?(editor.string)
    }
    func clear() {
        editor.string = ""
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        recalculateHeight()
        onTextChange?("")
    }
    private func recalculateHeight() {
        guard !measuring, let container = editor.textContainer, let manager = editor.layoutManager else { return }
        measuring = true
        defer { measuring = false }
        manager.ensureLayout(for: container)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
        if editor.string.hasSuffix("\n") { lines += 1 }
        let height = TextViewport.inputHeight(lineCount: lines)
        clip.expectedViewportHeight = height - 40 + Self.drawingInset * 2
        let textHeight = max(CGFloat(max(1, lines)) * 28, manager.usedRect(for: container).height) + Self.drawingInset * 2
        // Use the target viewport, not the old scroll view height during a
        // multi-line collapse. A stale tall document permits caret scrolling
        // to crop a single line even though the input should fit completely.
        let frame = NSRect(origin: .zero, size: NSSize(width: scroll.contentSize.width,
                                                     height: max(textHeight, clip.expectedViewportHeight)))
        if editor.frame != frame { editor.frame = frame }
        if lines <= 3 {
            clip.scroll(to: .zero)
            scroll.reflectScrolledClipView(clip)
        }
        if abs(height - desiredHeight) > 1 { desiredHeight = height; onHeightChange?(height) }
    }
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        lineFragmentRect.pointee.size.height = 28
        lineFragmentUsedRect.pointee.size.height = 28
        baselineOffset.pointee = 22
        return true
    }

    var layoutMetrics: [String: Double] {
        guard let manager = editor.layoutManager, manager.numberOfGlyphs > 0 else { return ["inputClipY": Double(clip.bounds.minY)] }
        let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let location = manager.location(forGlyphAt: 0)
        let point = editor.convert(NSPoint(x: 0, y: editor.textContainerOrigin.y + fragment.minY + location.y), to: nil)
        return ["inputClipY": Double(clip.bounds.minY), "inputBaselineY": Double(window?.convertPoint(toScreen: point).y ?? 0)]
    }
}
