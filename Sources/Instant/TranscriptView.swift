import AppKit
import InstantCore

enum MarkdownRenderer {
    static func render(_ text: String, color: NSColor = .labelColor, size: CGFloat = 16, allowSettingsLink: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var codeBlock = false
        let lines = text.components(separatedBy: "\n")
        for (index, original) in lines.enumerated() {
            if original.hasPrefix("```") { codeBlock.toggle(); continue }
            var line = original
            var heading = false
            if !codeBlock {
                while line.hasPrefix("#") { heading = true; line.removeFirst() }
                if heading { line = line.trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 3
            paragraph.baseWritingDirection = .natural
            if codeBlock {
                paragraph.lineSpacing = 3
                result.append(NSAttributedString(string: line, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: color, .paragraphStyle: paragraph
                ]))
            } else if let parsed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                for run in parsed.runs {
                    let intent = run.inlinePresentationIntent ?? []
                    var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
                        : NSFont.systemFont(ofSize: size, weight: heading || intent.contains(.stronglyEmphasized) ? .semibold : .regular)
                    if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
                    if let url = run.link, ["https", "http"].contains(url.scheme ?? "") || (allowSettingsLink && url.absoluteString == "instant://settings") { attributes[.link] = url }
                    result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
                }
            } else {
                result.append(NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph]))
            }
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph])) }
        }
        return result
    }
}

final class TranscriptScroller: NSScroller {
    var onTrackingChange: ((Bool) -> Void)?
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func trackKnob(with event: NSEvent) {
        onTrackingChange?(true)
        defer { onTrackingChange?(false) }
        super.trackKnob(with: event)
    }
}

final class TranscriptView: NSScrollView, NSTextViewDelegate {
    let text = SourceTextView()
    let sourcePopover = SourcesPopover()
    var sourceLabel = "Sources" { didSet { sourcePopover.label = sourceLabel } }
    var copyLabel = "Copy answer"
    var contentHeight: CGFloat = 0
    var maximumViewportHeight: CGFloat = 480
    var notice: String?
    var connectionGuidance: String?
    var onOpenSettings: (() -> Void)?
    var onDeferredContentChange: (() -> Void)?
    private let transcriptClip: NSClipView
    private var scrollOrigin: CGFloat = 0
    private var lastWidth: CGFloat = 0
    private var shouldFollow = true
    private var cachedTurns: [UUID: (Turn, NSAttributedString)] = [:]
    private var lastConversation = Conversation()
    private var suppressScrollTracking = false
    private var lastViewportSize = NSSize.zero
    private var liveScrolling = false
    private var settlingScroll = false
    private var pendingLayout = false
    private var deferredUpdate: DispatchWorkItem?
    private var refreshAttributes = false
    private var scrollbarTracking = false
    private var wheelContactActive = false
    private var lastScrollInput: TimeInterval = 0
    private var lastClipMotion: TimeInterval = 0
    private var observedClipOrigin = NSPoint.zero
    private var scrollRecoveryTimer: Timer?

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, clipView: NSClipView())
    }
    init(frame frameRect: NSRect, clipView: NSClipView) {
        transcriptClip = clipView
        super.init(frame: frameRect)
        contentView = transcriptClip
        transcriptClip.drawsBackground = false
        automaticallyAdjustsContentInsets = false
        contentInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
        drawsBackground = false
        borderType = .noBorder
        let scroller = TranscriptScroller()
        scroller.onTrackingChange = { [weak self] tracking in
            guard let self else { return }
            scrollbarTracking = tracking
            if tracking { beginLiveScroll() }
            else { endLiveScroll() }
        }
        verticalScroller = scroller
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 27, height: 0)
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = false
        text.isHorizontallyResizable = false
        text.autoresizingMask = []
        text.textContainer?.widthTracksTextView = false
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        text.setAccessibilityIdentifier("instant.transcript")
        text.delegate = self
        text.onSourceHover = { [weak self] id, rect in self?.showSources(id, rect: rect) }
        text.onSourceClick = { [weak self] id, rect in
            self?.showSources(id, rect: rect)
            self?.sourcePopover.activate()
        }
        text.onSourceExit = { [weak self] in self?.sourcePopover.scheduleClose() }
        text.onCopyClick = { [weak self] id in self?.copyAnswer(id) }
        documentView = text
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(beginLiveScroll), name: NSScrollView.willStartLiveScrollNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(endLiveScroll), name: NSScrollView.didEndLiveScrollNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(didLiveScroll), name: NSScrollView.didLiveScrollNotification, object: self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        lastScrollInput = ProcessInfo.processInfo.systemUptime
        if !event.phase.intersection([.began, .changed, .stationary]).isEmpty { wheelContactActive = true }
        if !event.phase.intersection([.ended, .cancelled]).isEmpty { wheelContactActive = false }
        super.scrollWheel(with: event)
        // Notifications can finish early or go missing when a gesture changes
        // into momentum or is cancelled. The event's phase closes that path too.
        if !event.phase.intersection([.began, .changed, .stationary]).isEmpty ||
            !event.momentumPhase.intersection([.began, .changed, .stationary]).isEmpty {
            liveScrolling = true
        } else if !event.momentumPhase.intersection([.ended, .cancelled]).isEmpty ||
            (!wheelContactActive && event.momentumPhase.isEmpty) {
            liveScrolling = false
            settlingScroll = hasElasticDisplacement
        }
        scheduleDeferredUpdate()
    }

    @objc private func didScroll() {
        guard !suppressScrollTracking else { return }
        recordClipMotion()
        scrollOrigin = contentView.bounds.minY
        let end = max(0, text.frame.height - contentView.bounds.height)
        shouldFollow = scrollOrigin >= end - 12
        if settlingScroll, !hasElasticDisplacement { settlingScroll = false }
        scheduleDeferredUpdate()
    }
    private var hasElasticDisplacement: Bool {
        let position = contentView.bounds.minY
        let end = max(0, text.frame.height - contentView.bounds.height)
        // Resting scroll positions are aligned to backing pixels, not necessarily
        // to the exact arithmetic height. A subpixel remainder is not a bounce.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let tolerance = 1 / max(1, scale)
        return position < -tolerance || position > end + tolerance
    }
    private var nativeScrollInProgress: Bool {
        // Position alone cannot establish ownership: layout and pixel alignment
        // can also place the clip fractionally outside its computed boundary.
        scrollbarTracking || liveScrolling || (settlingScroll && hasElasticDisplacement)
    }
    @objc private func beginLiveScroll() {
        liveScrolling = true
        settlingScroll = false
        lastScrollInput = ProcessInfo.processInfo.systemUptime
        deferredUpdate?.cancel(); deferredUpdate = nil
    }
    @objc private func endLiveScroll() {
        liveScrolling = false
        settlingScroll = hasElasticDisplacement
        lastScrollInput = ProcessInfo.processInfo.systemUptime
        scheduleDeferredUpdate()
    }
    @objc private func didLiveScroll() {
        // Legacy scroll devices may deliver didLiveScroll without a begin/end pair.
        if !liveScrolling { settlingScroll = hasElasticDisplacement }
        didScroll()
    }
    func prepareForPresentation() {
        // A hidden window may stop receiving the tail of a scroll gesture.
        // Resolve its offscreen position before a fresh reveal, never mid-bounce.
        liveScrolling = false
        settlingScroll = false
        wheelContactActive = false
        scrollbarTracking = false
        stopScrollRecovery()
        deferredUpdate?.cancel(); deferredUpdate = nil
        let wasSuppressing = suppressScrollTracking
        suppressScrollTracking = true
        scrollOrigin = contentView.bounds.minY
        restoreScrollOrigin()
        suppressScrollTracking = wasSuppressing
    }
    private func scheduleDeferredUpdate() {
        guard pendingLayout else { stopScrollRecovery(); return }
        guard !nativeScrollInProgress else { startScrollRecovery(); return }
        stopScrollRecovery()
        guard deferredUpdate == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            deferredUpdate = nil
            guard !nativeScrollInProgress else { return }
            if pendingLayout {
                layout()
                onDeferredContentChange?()
            }
        }
        deferredUpdate = work
        // Do not move the clip reentrantly from AppKit's bounds notification.
        DispatchQueue.main.async(execute: work)
    }
    private func recordClipMotion() {
        let origin = contentView.bounds.origin
        if origin != observedClipOrigin {
            observedClipOrigin = origin
            lastClipMotion = ProcessInfo.processInfo.systemUptime
        }
    }
    private func startScrollRecovery() {
        guard scrollRecoveryTimer == nil else { return }
        observedClipOrigin = contentView.bounds.origin
        lastClipMotion = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.recoverSettledScroll() }
        scrollRecoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func stopScrollRecovery() {
        scrollRecoveryTimer?.invalidate()
        scrollRecoveryTimer = nil
    }
    private func recoverSettledScroll() {
        guard pendingLayout else { stopScrollRecovery(); return }
        recordClipMotion()
        // Follow actual movement, not incoming model chunks. Never interfere
        // with a held scrollbar or a moving spring. A lost gesture tail must
        // not freeze the document forever after its last text packet arrives.
        let quietInterval: TimeInterval = wheelContactActive ? 1.2 : 0.25
        guard !scrollbarTracking,
              ProcessInfo.processInfo.systemUptime - max(lastClipMotion, lastScrollInput) >= quietInterval else { return }
        liveScrolling = false
        settlingScroll = false
        wheelContactActive = false
        scheduleDeferredUpdate()
    }
    func render(_ conversation: Conversation, forceFollow: Bool = false) {
        if conversation.id != lastConversation.id {
            cachedTurns.removeAll()
            refreshAttributes = true
        }
        lastConversation = conversation
        if forceFollow || conversation.turns.isEmpty {
            // Enter is explicit navigation to a new turn. It must not inherit
            // a previous gesture's deferral or an old transcript selection.
            liveScrolling = false
            settlingScroll = false
            wheelContactActive = false
            scrollbarTracking = false
            stopScrollRecovery()
        }
        let preserveNativePosition = nativeScrollInProgress
        let deferDocumentResize = preserveNativePosition && hasElasticDisplacement
        deferredUpdate?.cancel(); deferredUpdate = nil
        let selection = text.selectedRange()
        let origin = contentView.bounds.origin
        let following = forceFollow || (shouldFollow && selection.length == 0)
        let result = NSMutableAttributedString(string: "")
        for (index, turn) in conversation.turns.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 16)])) }
            if let (cached, attributed) = cachedTurns[turn.id], cached == turn {
                result.append(attributed)
            } else {
                let value = NSMutableAttributedString(string: "")
                let questionStyle = NSMutableParagraphStyle()
                questionStyle.lineSpacing = 4
                questionStyle.paragraphSpacing = 12
                value.append(NSAttributedString(string: turn.question + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: questionStyle
                ]))
                if !turn.answer.isEmpty { value.append(MarkdownRenderer.render(turn.answer)) }
                else if turn.state == .generating {
                    value.append(NSAttributedString(string: "…", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.tertiaryLabelColor]))
                }
                if let error = turn.error {
                    if !turn.answer.isEmpty { value.append(NSAttributedString(string: "\n\n")) }
                    value.append(MarkdownRenderer.render(error, color: .secondaryLabelColor, size: 14, allowSettingsLink: true))
                }
                if !turn.answer.isEmpty {
                    value.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
                    value.append(actionIcon("doc.on.doc", label: copyLabel, scheme: "instant-copy", id: turn.id))
                    if let sources = turn.sources, !sources.isEmpty, turn.state != .generating {
                        value.append(NSAttributedString(string: "  ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
                        value.append(actionIcon("globe", label: sourceLabel, scheme: "instant-source", id: turn.id))
                    }
                }
                cachedTurns[turn.id] = (turn, value)
                result.append(value)
            }
        }
        if let connectionGuidance {
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            result.append(MarkdownRenderer.render(connectionGuidance, allowSettingsLink: true))
        }
        if let notice {
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            result.append(MarkdownRenderer.render(notice, color: .secondaryLabelColor, size: 14))
        }
        let wasSuppressing = suppressScrollTracking
        suppressScrollTracking = true
        defer { suppressScrollTracking = wasSuppressing }
        // Keep already displayed runs intact instead of replacing the text view
        // contents on every streamed chunk (which resets selection and scrolling).
        if let storage = text.textStorage {
            if refreshAttributes {
                storage.setAttributedString(result)
                refreshAttributes = false
            } else {
                let prefix = (storage.string as NSString).commonPrefix(with: result.string, options: .literal).utf16.count
                storage.beginEditing()
                storage.replaceCharacters(in: NSRange(location: prefix, length: storage.length - prefix),
                                          with: result.attributedSubstring(from: NSRange(location: prefix, length: result.length - prefix)))
                storage.endEditing()
            }
        }
        // Text always advances, even while a scrollbar is being dragged. Only
        // keep the document's old extent during an actual rubber-band return;
        // changing that boundary mid-return would interrupt AppKit's spring.
        measure(resizeDocument: !deferDocumentResize)
        if forceFollow {
            text.setSelectedRange(NSRange(location: result.length, length: 0))
        } else if selection.length > 0, NSMaxRange(selection) <= result.length {
            text.setSelectedRange(selection)
        }
        if preserveNativePosition {
            scrollOrigin = contentView.bounds.minY
            // Keep shouldFollow as user intent until the gesture ends. Incoming
            // text moving the bottom is not a deliberate scroll away from it.
        } else if following {
            scrollOrigin = TextViewport.followingOrigin(contentHeight: contentHeight, maximumViewportHeight: maximumViewportHeight)
            shouldFollow = true
        } else {
            scrollOrigin = origin.y
        }
        if !preserveNativePosition {
            restoreScrollOrigin()
        } else if !deferDocumentResize {
            reflectScrolledClipView(contentView)
        }
        lastViewportSize = contentView.bounds.size
        lastWidth = bounds.width
        pendingLayout = preserveNativePosition
        scheduleDeferredUpdate()
        if conversation.turns.isEmpty { cachedTurns.removeAll(); sourcePopover.close() }
    }
    override func layout() {
        let wasSuppressing = suppressScrollTracking
        let preserveNativeScroll = nativeScrollInProgress
        suppressScrollTracking = true
        defer { suppressScrollTracking = wasSuppressing }
        super.layout()
        guard !wasSuppressing else { return }
        let geometryChanged = contentView.bounds.size != lastViewportSize || abs(bounds.width - lastWidth) > 0.5
        // Scroller fade and elastic frames also request layout. They are not
        // reasons to reapply a saved origin or constrain the bouncing content.
        guard geometryChanged || pendingLayout else { return }
        guard !preserveNativeScroll else { pendingLayout = true; startScrollRecovery(); return }
        lastViewportSize = contentView.bounds.size
        lastWidth = bounds.width
        pendingLayout = false
        stopScrollRecovery()
        measure()
        if shouldFollow && text.selectedRange().length == 0 {
            scrollOrigin = TextViewport.followingOrigin(contentHeight: contentHeight, maximumViewportHeight: maximumViewportHeight)
        }
        restoreScrollOrigin()
    }
    func invalidateAppearance() {
        cachedTurns.removeAll()
        // System appearance changes can update attributes without changing text.
        refreshAttributes = true
        render(lastConversation)
    }
    private func measure(resizeDocument: Bool = true) {
        guard let manager = text.layoutManager, let container = text.textContainer else { return }
        let width = max(1, contentSize.width - text.textContainerInset.width * 2)
        if container.containerSize.width != width {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        manager.ensureLayout(for: container)
        // The panel also uses contentHeight to resize its shell. Freeze that
        // measurement with the document extent during a true elastic return.
        guard resizeDocument else { return }
        contentHeight = ceil(manager.usedRect(for: container).height) + 10
        let size = NSSize(width: contentSize.width, height: max(contentHeight, contentSize.height))
        if text.frame.size != size {
            text.setFrameSize(size)
            text.needsDisplay = true
        }
    }
    private func restoreScrollOrigin() {
        let end = max(0, text.frame.height - contentView.bounds.height)
        let destination = NSPoint(x: 0, y: min(end, max(0, scrollOrigin)))
        guard contentView.bounds.origin != destination else { return }
        contentView.scroll(to: destination)
        reflectScrolledClipView(contentView)
    }
    private func showSources(_ id: UUID, rect: NSRect) {
        guard let turn = lastConversation.turns.first(where: { $0.id == id }), let sources = turn.sources else { return }
        sourcePopover.show(id: id, sources: sources, rect: rect, in: text)
    }
    func updateActionLabels(copy: String, sources: String) {
        guard copy != copyLabel || sources != sourceLabel else { return }
        copyLabel = copy
        sourceLabel = sources
        invalidateAppearance()
    }
    private func actionIcon(_ symbol: String, label: String, scheme: String, id: UUID) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(hierarchicalColor: .secondaryLabelColor))
        attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
        let icon = NSMutableAttributedString(attachment: attachment)
        icon.addAttributes([.link: URL(string: "\(scheme)://\(id.uuidString)")!, .toolTip: label,
                            .underlineStyle: 0], range: NSRange(location: 0, length: icon.length))
        return icon
    }
    @discardableResult
    func copyAnswer(_ id: UUID, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let turn = lastConversation.turns.first(where: { $0.id == id }), !turn.answer.isEmpty else { return false }
        pasteboard.clearContents()
        guard pasteboard.setString(turn.answer, forType: .string) else { return false }
        sourcePopover.close()
        text.showCopyFeedback(for: id)
        return true
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL, url.absoluteString == "instant://settings" {
            onOpenSettings?()
            return true
        }
        if let url = link as? URL, url.scheme == "instant-copy", let host = url.host,
           let id = UUID(uuidString: host) {
            return copyAnswer(id)
        }
        guard let url = link as? URL, url.scheme == "instant-source", let host = url.host,
              let id = UUID(uuidString: host), let manager = text.layoutManager, let container = text.textContainer else { return false }
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        showSources(id, rect: rect)
        sourcePopover.activate()
        return true
    }
    var layoutMetrics: [String: Double] {
        ["transcriptClipY": Double(contentView.bounds.minY), "transcriptHeight": Double(contentHeight),
         "maximumViewport": Double(maximumViewportHeight)]
    }
    deinit {
        scrollRecoveryTimer?.invalidate()
        deferredUpdate?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
