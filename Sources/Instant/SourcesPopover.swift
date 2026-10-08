import AppKit
import InstantCore

final class SourceTextView: NSTextView {
    var onSourceHover: ((UUID, NSRect) -> Void)?
    var onSourceClick: ((UUID, NSRect) -> Void)?
    var onSourceExit: (() -> Void)?
    var onCopyClick: ((UUID) -> Void)?
    private var copyFeedback: DispatchWorkItem?
    private var restoreCopyImage: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        if let action = action(at: convert(event.locationInWindow, from: nil)), action.scheme == "instant-source" { onSourceHover?(action.id, action.rect) }
        else { onSourceExit?() }
        super.mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) { onSourceExit?(); super.mouseExited(with: event) }
    override func mouseDown(with event: NSEvent) {
        if let action = action(at: convert(event.locationInWindow, from: nil)) {
            if action.scheme == "instant-copy" { onCopyClick?(action.id) }
            else { onSourceClick?(action.id, action.rect) }
            return
        }
        super.mouseDown(with: event)
    }
    func action(at point: NSPoint) -> (scheme: String, id: UUID, rect: NSRect)? {
        guard let manager = layoutManager, let container = textContainer, manager.numberOfGlyphs > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let character = manager.characterIndexForGlyph(at: glyph)
        guard character < (textStorage?.length ?? 0),
              let link = textStorage?.attribute(.link, at: character, effectiveRange: nil) as? URL,
              let scheme = link.scheme, ["instant-source", "instant-copy"].contains(scheme),
              let host = link.host, let id = UUID(uuidString: host) else { return nil }
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return rect.insetBy(dx: -4, dy: -4).contains(point) ? (scheme, id, rect) : nil
    }
    func showCopyFeedback(for id: UUID) {
        copyFeedback?.cancel()
        restoreCopyImage?()
        restoreCopyImage = nil
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { link, range, stop in
            guard let url = link as? URL, url.scheme == "instant-copy", url.host?.lowercased() == id.uuidString.lowercased(),
                  let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return }
            let original = attachment.image
            attachment.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(hierarchicalColor: .secondaryLabelColor))
            needsDisplay = true
            restoreCopyImage = { [weak self, weak attachment] in
                attachment?.image = original
                self?.needsDisplay = true
            }
            stop.pointee = true
        }
        let work = DispatchWorkItem { [weak self] in
            self?.restoreCopyImage?()
            self?.restoreCopyImage = nil
            self?.copyFeedback = nil
        }
        copyFeedback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}

private final class SourcePopupRoot: NSView {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
}

private final class SourceLinkButton: NSButton { var sourceURL: URL? }

final class SourcesPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var selectedID: UUID?
    private var closeWork: DispatchWorkItem?
    private var markerScreenRect = NSRect.zero
    var onOpenURL: (() -> Void)?
    var label = "Sources"

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }
    var window: NSWindow? { popover.contentViewController?.view.window }
    func contains(_ point: NSPoint) -> Bool { popover.isShown && window?.frame.contains(point) == true }
    func show(id: UUID, sources: [SearchSource], rect: NSRect, in text: NSView) {
        closeWork?.cancel()
        guard !sources.isEmpty else { return }
        if selectedID == id && popover.isShown { return }
        popover.close()
        selectedID = id
        markerScreenRect = text.window?.convertToScreen(text.convert(rect, to: nil)) ?? .zero
        let width: CGFloat = 360
        let documentHeight = CGFloat(sources.count) * 46 + 24
        let height = min(310, documentHeight)
        let root = SourcePopupRoot(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.entered = { [weak self] in self?.closeWork?.cancel() }
        root.exited = { [weak self] in self?.scheduleClose() }
        root.setAccessibilityLabel(label)
        let scroll = NSScrollView(frame: root.bounds)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: documentHeight))
        for (index, source) in sources.enumerated() {
            let y = 12 + CGFloat(index) * 46
            let button = SourceLinkButton(frame: NSRect(x: 14, y: y, width: width - 28, height: 20))
            button.title = source.title
            button.font = .systemFont(ofSize: 13)
            button.alignment = .left
            button.isBordered = false
            button.lineBreakMode = .byTruncatingTail
            button.sourceURL = source.url
            button.target = self
            button.action = #selector(openSource(_:))
            button.toolTip = source.url.absoluteString
            button.setAccessibilityLabel("\(source.title), \(source.url.absoluteString)")
            let address = SourceLinkButton(frame: NSRect(x: 14, y: y + 21, width: width - 28, height: 17))
            address.title = source.url.absoluteString
            address.font = .systemFont(ofSize: 11)
            address.contentTintColor = .secondaryLabelColor
            address.alignment = .left
            address.isBordered = false
            address.refusesFirstResponder = true
            address.lineBreakMode = .byTruncatingMiddle
            address.sourceURL = source.url
            address.target = self
            address.action = #selector(openSource(_:))
            address.toolTip = source.url.absoluteString
            document.addSubview(button)
            document.addSubview(address)
        }
        scroll.documentView = document
        root.addSubview(scroll)
        let controller = NSViewController()
        controller.view = root
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: width, height: height)
        popover.show(relativeTo: rect, of: text, preferredEdge: .maxY)
        window?.title = label
        window?.setAccessibilityIdentifier("instant.sources")
    }
    func activate() { window?.makeKey() }
    func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !contains(NSEvent.mouseLocation), !markerScreenRect.insetBy(dx: -5, dy: -5).contains(NSEvent.mouseLocation) else { return }
            popover.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    func close() { closeWork?.cancel(); popover.close() }
    func popoverDidClose(_ notification: Notification) { selectedID = nil; closeWork?.cancel() }
    @objc private func openSource(_ sender: SourceLinkButton) {
        guard let url = sender.sourceURL, ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return }
        close()
        onOpenURL?()
        NSWorkspace.shared.open(url)
    }
}
