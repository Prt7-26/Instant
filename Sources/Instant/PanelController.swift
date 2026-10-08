import AppKit
import QuartzCore
import InstantCore
import MaterialView

final class FloatingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Retargetable: each new transition starts at the currently visible geometry.
final class Motion: NSObject {
    private var link: CADisplayLink?
    private var startupDriver: Timer?
    private var lastDisplayTick: CFTimeInterval = 0
    private var update: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?
    private var started: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0
    private var generation = 0
    func stop() {
        generation += 1
        link?.invalidate()
        link = nil
        startupDriver?.invalidate()
        startupDriver = nil
        update = nil
        completion = nil
    }
    func animate(in window: NSWindow, duration: TimeInterval, update: @escaping (CGFloat) -> Void, completion: (() -> Void)? = nil) {
        stop()
        guard duration > 0 else { update(1); completion?(); return }
        self.duration = duration
        self.started = CACurrentMediaTime()
        self.lastDisplayTick = 0
        self.update = update
        self.completion = completion
        let token = generation
        update(0)
        guard token == generation else { return }
        // A fully transparent window may not receive window display-link ticks.
        // Use its screen so the first reveal frame can always become visible.
        guard let screen = window.screen ?? NSScreen.main else {
            stop(); update(1); completion?(); return
        }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
        // A newly ordered transparent window can remain occluded until its first
        // nontransparent frame. Bootstrap that frame without waiting on visibility.
        let driver = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, lastDisplayTick == 0 || CACurrentMediaTime() - lastDisplayTick > 0.1 else { return }
            advance()
        }
        startupDriver = driver
        RunLoop.main.add(driver, forMode: .common)
    }
    @objc private func tick(_ link: CADisplayLink) {
        lastDisplayTick = CACurrentMediaTime()
        advance()
    }
    private func advance() {
        let token = generation
        let progress = CGFloat(min(1, (CACurrentMediaTime() - started) / duration))
        update?(progress)
        guard token == generation, progress >= 1 else { return }
        let finished = completion
        stop()
        finished?()
    }
    deinit { stop() }
}

@MainActor final class PanelController: NSWindowController, NSWindowDelegate {
    let panel: FloatingPanel
    let composer = ComposerView(frame: NSRect(x: 0, y: 0, width: 680, height: 68))
    let transcript = TranscriptView(frame: NSRect(x: 0, y: 74, width: 680, height: 1))
    let glass = NSGlassEffectView()
    private let desktopBackdrop = NSMaterialView()
    private let surface = FlippedView()
    private let root = FlippedView()
    private let glassShadow = CAShapeLayer()
    private let edgeHighlight = DirectionalHighlightView(frame: .zero)
    private let settings: SettingsStore
    private let conversation: ConversationController
    private let heightMotion = Motion()
    private let visibilityMotion = Motion()
    private var inputHeight: CGFloat = 68
    private var maxHeight: CGFloat = 540
    private var targetHeight: CGFloat = 68
    private var contentHeight: CGFloat = 68
    private var contentWidth: CGFloat = 680
    private var screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    private var anchorTop: CGFloat = 700
    private var backingScale: CGFloat = 2
    private var visualState = PanelVisualState.visible
    private var preparingPresentation = false
    private var previousApp: NSRunningApplication?
    private var dismissing = false
    private var globalMouse: Any?
    private var localMouse: Any?
    private var tracePhase: String?
    private var traceStart: CFTimeInterval = 0
    private var traceFrames: [[String: Double]] = []
    private var traceRuns: [[String: Any]] = []
    private var layoutSamples: [[String: Double]] = []
    private var layoutTraceWrite: DispatchWorkItem?
    var openSettings: (() -> Void)?

    init(settings: SettingsStore, conversation: ConversationController) {
        self.settings = settings
        self.conversation = conversation
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 68),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.title = "Instant"
        panel.setAccessibilityIdentifier("instant.panel")
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.clipsToBounds = false
        root.autoresizesSubviews = false
        surface.autoresizesSubviews = false
        surface.wantsLayer = true
        surface.layer?.masksToBounds = true
        // Match the accepted H03 experiment: behind-window sampling beneath
        // regular glass, with full-resolution sampling and a faint white tint.
        desktopBackdrop.isContentView = true
        desktopBackdrop.scale = 1
        desktopBackdrop.rimOpacity = 0
        desktopBackdrop.state = .active
        desktopBackdrop.alphaValue = 1
        desktopBackdrop.wantsLayer = true
        desktopBackdrop.layer?.masksToBounds = true
        root.addSubview(desktopBackdrop)
        glass.style = .regular
        glass.cornerRadius = 34
        glass.contentView = surface
        root.addSubview(glass)
        root.addSubview(edgeHighlight)
        glassShadow.fillColor = NSColor.clear.cgColor
        glassShadow.shadowColor = NSColor.black.cgColor
        glassShadow.shadowOpacity = 0.18
        glassShadow.shadowRadius = 10
        glassShadow.shadowOffset = CGSize(width: 0, height: 5)
        root.layer?.insertSublayer(glassShadow, at: 0)
        surface.addSubview(composer)
        surface.addSubview(transcript)
        transcript.onDeferredContentChange = { [weak self] in self?.adjustHeight() }
        transcript.onOpenSettings = { [weak self] in self?.openSettings?() }
        transcript.sourcePopover.onOpenURL = { [weak self] in self?.dismiss(restoreFocus: false) }
        composer.onTextChange = { [weak self] text in
            self?.conversation.draft = text
            self?.recordLayoutSample()
        }
        composer.onHeightChange = { [weak self] height in
            guard let self else { return }
            inputHeight = height
            adjustHeight()
        }
        composer.editor.configuration = { [weak settings] in settings?.value ?? AppConfiguration() }
        composer.editor.onSubmit = { [weak self] in self?.submit() }
        composer.editor.onToggleTranslation = { [weak self] in self?.conversation.toggleMode() }
        composer.editor.onDismiss = { [weak self] in self?.dismiss(restoreFocus: true) }
        composer.editor.onSettings = { [weak self] in self?.openSettings?() }
        composer.editor.onArchive = { [weak self] in self?.archiveCurrentConversation() }
        composer.onArchive = { [weak self] in self?.archiveCurrentConversation() }
        conversation.onChange = { [weak self] follow in self?.refresh(follow: follow) }
        conversation.onModeChange = { [weak self] in
            guard let self else { return }
            composer.setMode(conversation.mode, animated: panel.isVisible && !preparingPresentation)
        }
        conversation.onError = { [weak self] error in
            guard let self else { return }
            settings.error = error
            transcript.notice = error
            refresh(follow: false)
        }
        root.onAppearanceChanged = { [weak self] in self?.appearanceChanged() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, panel.isVisible else { return }
            if !visibleGlassFrame.contains(NSEvent.mouseLocation), !transcript.sourcePopover.contains(NSEvent.mouseLocation) { dismiss(restoreFocus: false) }
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.panel.isVisible, event.window !== self.transcript.sourcePopover.window,
               event.window !== self.panel || !self.visibleGlassFrame.contains(NSEvent.mouseLocation) {
                self.dismiss(restoreFocus: false)
            }
            return event
        }
        updateSettings()
        layout(height: 68)
        refresh(follow: true)
    }
    required init?(coder: NSCoder) { fatalError() }
    func toggle() {
        if panel.isVisible && !dismissing { dismiss(restoreFocus: true) }
        else { present() }
    }
    func present() {
        let wasVisible = panel.isVisible
        guard !wasVisible || dismissing else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(composer.editor)
            return
        }
        visibilityMotion.stop()
        heightMotion.stop()
        preparingPresentation = true
        dismissing = false
        if !wasVisible {
            transcript.prepareForPresentation()
            if let app = NSWorkspace.shared.frontmostApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
            let visible = screen.visibleFrame
            screenFrame = screen.frame
            backingScale = screen.backingScaleFactor
            anchorTop = ((visible.maxY - visible.height * 0.22) * backingScale).rounded() / backingScale
            maxHeight = min(600, visible.height * 0.6)
            contentWidth = min(680, visible.width - 64 - PanelGeometry.margin * 2)
            visualState = reducedMotion ? .visible : .entering
            visualState.opacity = 0
            resizeContent(to: targetHeight)
        }
        conversation.willShow()
        refresh(follow: false)
        preparingPresentation = false
        let from = visualState
        applyVisualState()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(composer.editor)
        beginTrace("show")
        visibilityMotion.animate(in: panel, duration: reducedMotion ? 0.12 : 0.38, update: { [weak self] progress in
            guard let self else { return }
            visualState = .interpolate(from: from, to: .visible,
                                      geometry: reducedMotion ? progress : PanelMotionCurve.reveal(progress),
                                      opacity: PanelMotionCurve.easeOut(min(1, progress * 2)))
            applyVisualState()
            recordTraceFrame()
        }, completion: { [weak self] in
            self?.visualState = .visible
            self?.applyVisualState()
            self?.finishTrace(interrupted: false)
        })
    }
    func dismiss(restoreFocus: Bool) {
        guard panel.isVisible, !dismissing else { return }
        transcript.sourcePopover.close()
        dismissing = true
        let from = visualState
        var destination = reducedMotion ? PanelVisualState.visible : .exiting
        destination.opacity = 0
        beginTrace("hide")
        visibilityMotion.animate(in: panel, duration: reducedMotion ? 0.10 : 0.24, update: { [weak self] progress in
            guard let self else { return }
            visualState = .interpolate(from: from, to: destination,
                                      geometry: PanelMotionCurve.smooth(progress),
                                      opacity: PanelMotionCurve.smooth(progress))
            applyVisualState()
            recordTraceFrame()
        }, completion: { [weak self] in
            guard let self else { return }
            finishTrace(interrupted: false)
            panel.orderOut(nil)
            dismissing = false
            conversation.didHide()
            if restoreFocus, let previousApp,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previousApp.activate(options: [])
            }
        })
    }
    func windowDidBecomeKey(_ notification: Notification) {
        panel.makeFirstResponder(composer.editor)
    }
    func restoreInputFocus() {
        guard NSApp.modalWindow == nil, panel.isVisible, !dismissing, NSApp.keyWindow == nil else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(composer.editor)
    }
    func recoverUnroutedKey(_ event: NSEvent) -> NSEvent? {
        guard NSApp.modalWindow == nil else { return event }
        if let keyWindow = NSApp.keyWindow, keyWindow !== panel { return event }
        // A borderless accessory window can receive activation and keystrokes
        // together, with the event still referring to the previous key window.
        // Route through its actual responder so the first keystroke is preserved.
        if !panel.isVisible || dismissing { present() }
        restoreInputFocus()
        if event.keyCode == 53, !composer.editor.hasMarkedText() { dismiss(restoreFocus: true); return nil }
        if composer.editor.handleShortcut(event) { return nil }
        if event.modifierFlags.contains(.command) {
            if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return nil }
        }
        (panel.firstResponder ?? composer.editor).keyDown(with: event)
        return nil
    }
    func updateSettings() {
        composer.setLanguage(settings.language)
        transcript.updateActionLabels(copy: settings.l10n["copyAnswer"], sources: settings.l10n["sources"])
        composer.updateArchiveButton(enabled: !conversation.conversation.turns.isEmpty,
                                     label: settings.l10n["archiveNow"],
                                     shortcut: Shortcut.label(code: settings.value.archiveKeyCode, modifiers: settings.value.archiveModifiers))
        accessibilityChanged()
        if transcript.connectionGuidance != conversation.connectionGuidance { refresh(follow: false) }
    }
    var draftText: String { composer.editor.string }
    func restoreDraft(_ value: String) {
        composer.editor.string = value
        composer.editor.didChangeText()
    }
    private func archiveCurrentConversation() {
        composer.editor.unmarkText()
        conversation.draft = composer.editor.string
        if conversation.archiveNow() {
            transcript.notice = nil
            refresh(follow: false)
        }
        panel.makeFirstResponder(composer.editor)
    }
    private func submit() {
        guard !composer.editor.hasMarkedText() else { return }
        let question = composer.editor.string
        conversation.submit(question) { [self] in composer.clear() }
    }
    private func refresh(follow: Bool) {
        transcript.maximumViewportHeight = max(1, maxHeight - inputHeight - 27)
        transcript.connectionGuidance = conversation.connectionGuidance
        transcript.render(conversation.conversation, forceFollow: follow)
        composer.updateArchiveButton(enabled: !conversation.conversation.turns.isEmpty,
                                     label: settings.l10n["archiveNow"],
                                     shortcut: Shortcut.label(code: settings.value.archiveKeyCode, modifiers: settings.value.archiveModifiers))
        adjustHeight()
    }
    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var visibleGlassFrame: NSRect {
        let pivot = PanelGeometry.margin + 34
        let top = panel.frame.maxY - (pivot + visualState.offsetY + (PanelGeometry.margin - pivot) * visualState.scaleY)
        return NSRect(x: panel.frame.midX - contentWidth * visualState.scaleX / 2,
               y: top - contentHeight * visualState.scaleY,
               width: contentWidth * visualState.scaleX, height: contentHeight * visualState.scaleY)
    }
    private func adjustHeight() {
        let expanded = !conversation.conversation.turns.isEmpty || transcript.notice != nil || transcript.connectionGuidance != nil
        let desired = TextViewport.snappedHeight(expanded ? min(maxHeight, inputHeight + max(54, transcript.contentHeight) + 30) : inputHeight, scale: backingScale)
        guard abs(desired - targetHeight) > 0.1 || abs(contentHeight - desired) > 0.1 else { layout(height: contentHeight); return }
        targetHeight = desired
        let initialHeight = contentHeight
        heightMotion.animate(in: panel, duration: panel.isVisible && !reducedMotion && !preparingPresentation ? 0.28 : 0) { [weak self] progress in
            guard let self else { return }
            resizeContent(to: initialHeight + (desired - initialHeight) * PanelMotionCurve.easeOut(progress))
        }
    }
    private func resizeContent(to height: CGFloat) {
        contentHeight = TextViewport.snappedHeight(height, scale: backingScale)
        panel.setFrame(PanelGeometry.frame(contentSize: NSSize(width: contentWidth, height: contentHeight),
                                          screenFrame: screenFrame, top: anchorTop), display: panel.isVisible)
        contentHeight = panel.frame.height - PanelGeometry.margin * 2
        layout(height: contentHeight)
    }
    private func layout(height: CGFloat) {
        let width = contentWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = NSRect(origin: .zero, size: panel.frame.size)
        glass.frame = NSRect(x: PanelGeometry.margin, y: PanelGeometry.margin, width: width, height: height)
        desktopBackdrop.frame = glass.frame
        // The capsule's caps retain their curvature while its straight middle stretches.
        glass.cornerRadius = min(inputHeight, height) / 2
        updateBackdropMask(radius: glass.cornerRadius)
        surface.layer?.cornerRadius = glass.cornerRadius
        edgeHighlight.update(frame: glass.frame, cornerRadius: glass.cornerRadius, scale: backingScale)
        glassShadow.frame = root.bounds
        glassShadow.shadowPath = CGPath(roundedRect: glass.frame, cornerWidth: glass.cornerRadius,
                                       cornerHeight: glass.cornerRadius, transform: nil)
        surface.frame = glass.bounds
        composer.frame = NSRect(x: 0, y: 0, width: width, height: inputHeight)
        transcript.maximumViewportHeight = max(1, maxHeight - inputHeight - 27)
        transcript.frame = NSRect(x: 0, y: inputHeight + 6, width: width, height: max(0, height - inputHeight - 27))
        transcript.alphaValue = min(1, max(0, (height - inputHeight) / 48))
        transcript.isHidden = height <= inputHeight + 1
        root.layoutSubtreeIfNeeded()
        CATransaction.commit()
        applyVisualState()
        recordLayoutSample()
    }
    private func applyVisualState() {
        // The pivot belongs to the input row, never the growing answer body.
        let center = NSPoint(x: root.bounds.midX, y: PanelGeometry.margin + 34)
        var transform = CATransform3DMakeTranslation(center.x, center.y + visualState.offsetY, 0)
        transform = CATransform3DScale(transform, visualState.scaleX, visualState.scaleY, 1)
        transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.layer?.sublayerTransform = transform
        CATransaction.commit()
        panel.alphaValue = visualState.opacity
    }
    @objc private func appearanceChanged() { transcript.invalidateAppearance(); accessibilityChanged() }
    private func recordLayoutSample() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test"), panel.isVisible, visualState == .visible else { return }
        var sample = composer.layoutMetrics.merging(transcript.layoutMetrics) { _, new in new }
        sample["time"] = CACurrentMediaTime()
        sample["panelTop"] = Double(panel.frame.maxY - PanelGeometry.margin)
        sample["inputHeight"] = Double(inputHeight)
        sample["shadowWidthError"] = Double((glassShadow.shadowPath?.boundingBoxOfPath.width ?? 0) - glass.frame.width)
        sample["shadowHeightError"] = Double((glassShadow.shadowPath?.boundingBoxOfPath.height ?? 0) - glass.frame.height)
        sample["glassTintAlpha"] = Double(glass.tintColor?.alphaComponent ?? 0)
        sample["backdropWidthError"] = Double(desktopBackdrop.frame.width - glass.frame.width)
        sample["backdropHeightError"] = Double(desktopBackdrop.frame.height - glass.frame.height)
        sample["samplesDesktop"] = desktopBackdrop.blendingMode == .behindWindow ? 1 : 0
        sample["blurRadius"] = Double(desktopBackdrop.blurRadius)
        sample["samplingScale"] = Double(desktopBackdrop.scale)
        sample["saturation"] = Double(desktopBackdrop.saturationFactor)
        sample["regularGlass"] = glass.style == .regular ? 1 : 0
        sample["edgeWidthError"] = Double(edgeHighlight.frame.width - glass.frame.width)
        sample["edgeHeightError"] = Double(edgeHighlight.frame.height - glass.frame.height)
        sample["edgeLineWidth"] = Double(edgeHighlight.lineWidth)
        sample["edgeStrength"] = Double(edgeHighlight.highlightOpacity)
        if let tint = desktopBackdrop.effect.active.tintColor().usingColorSpace(.deviceRGB) {
            sample["tintRed"] = Double(tint.redComponent)
            sample["tintGreen"] = Double(tint.greenComponent)
            sample["tintBlue"] = Double(tint.blueComponent)
            sample["tintAlpha"] = Double(tint.alphaComponent)
        }
        layoutSamples.append(sample)
        layoutSamples = Array(layoutSamples.suffix(800))
        layoutTraceWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Instant-UITests/layout-trace.json")
            if let data = try? JSONSerialization.data(withJSONObject: layoutSamples) { try? data.write(to: url, options: .atomic) }
        }
        layoutTraceWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    // Test-mode diagnostics contain geometry and timing only, never conversation text.
    private func beginTrace(_ phase: String) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test") else { return }
        finishTrace(interrupted: true)
        tracePhase = phase
        traceStart = CACurrentMediaTime()
        traceFrames = []
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Instant-UITests/presentation-trace.json")
        if let data = try? JSONSerialization.data(withJSONObject: [["phase": phase, "running": true]]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    private func recordTraceFrame() {
        guard tracePhase != nil else { return }
        traceFrames.append(["time": CACurrentMediaTime() - traceStart,
                            "scaleX": Double(visualState.scaleX), "scaleY": Double(visualState.scaleY),
                            "opacity": Double(panel.alphaValue),
                            "horizontalError": Double(panel.frame.midX - screenFrame.midX),
                            "topError": Double(panel.frame.maxY - PanelGeometry.margin - anchorTop)])
    }
    private func finishTrace(interrupted: Bool) {
        guard let phase = tracePhase else { return }
        tracePhase = nil
        traceRuns.append(["phase": phase, "interrupted": interrupted, "mode": conversation.mode.rawValue,
                          "reducedMotion": reducedMotion, "frames": traceFrames])
        traceRuns = Array(traceRuns.suffix(20))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Instant-UITests/presentation-trace.json")
        if let data = try? JSONSerialization.data(withJSONObject: traceRuns, options: .prettyPrinted) {
            try? data.write(to: url, options: .atomic)
        }
    }
    @objc private func accessibilityChanged() {
        glass.style = .regular
        glass.tintColor = nil
        desktopBackdrop.state = .active
        updateBackdropEffect()
        if reducedMotion {
            heightMotion.stop()
            visualState.scaleX = 1
            visualState.scaleY = 1
            visualState.offsetY = 0
            adjustHeight()
        }
    }
    private func updateBackdropMask(radius: CGFloat) {
        desktopBackdrop.cornerRadius = radius
    }
    private func updateBackdropEffect() {
        let tint = NSColor(white: 1, alpha: 0.01)
        let style = NSMaterialView.Effect.MaterialStyle(backgroundColor: .clear, tintColor: tint,
                                                       saturationFactor: 1, brightnessFactor: 0,
                                                       blurRadius: 4, bleedAmount: 8)
        desktopBackdrop.effect = .init(active: style, inactive: style, emphasized: style)
    }
}
