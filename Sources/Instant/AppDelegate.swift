import AppKit
import InstantCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var conversations: ConversationController!
    private var panelController: PanelController!
    private var settingsController: SettingsController?
    private var hotKey = GlobalHotKey()
    private var recordingShortcut = false
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    var startupDraft: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.arguments.contains("--ui-test"),
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.instant.app").first(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated && kill($0.processIdentifier, 0) == 0
           }) {
            existing.activate(options: [])
            DistributedNotificationCenter.default().postNotificationName(.init("com.instant.app.show"), object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        settings = SettingsStore()
        let testDirectory = ProcessInfo.processInfo.arguments.contains("--ui-test")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Instant-UITests") : nil
        do { conversations = try ConversationController(settings: settings, directory: testDirectory, draft: startupDraft ?? "") }
        catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        panelController = PanelController(settings: settings, conversation: conversations)
        if let startupDraft { panelController.restoreDraft(startupDraft) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard NSApp.modalWindow == nil else { return event }
            if !recordingShortcut, UInt32(event.keyCode) == settings.value.hotKeyCode,
               Shortcut.carbon(event.modifierFlags) == settings.value.hotKeyModifiers {
                if !event.isARepeat { panelController.toggle() }
                return nil
            }
            return panelController.recoverUnroutedKey(event)
        }
        panelController.openSettings = { [weak self] in self?.showSettings(nil) }
        hotKey.onPress = { [weak self] in
            guard NSApp.modalWindow == nil else { return }
            self?.panelController.toggle()
        }
        settings.onChange = { [weak self] in self?.settingsChanged() }
        NotificationCenter.default.addObserver(self, selector: #selector(recordingChanged(_:)), name: .shortcutRecording, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showPanel), name: .init("com.instant.app.show"), object: nil)
        configureMenu()
        configureStatusItem()
        settingsChanged()
        panelController.present()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.present(); return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { panelController?.restoreInputFocus() }
    func applicationWillTerminate(_ notification: Notification) {
        conversations?.shutdown()
        settings?.flushKey()
    }
    @objc private func showPanel() { panelController?.present() }
    private func settingsChanged() {
        do { try conversations?.updateArchiveDirectory() }
        catch {
            let current = conversations.archiveDirectory
            settings.value.archiveFolderPath = current == SettingsStore.defaultArchiveDirectory ? "" : current.path
            settings.error = error.localizedDescription
        }
        if !recordingShortcut {
            let code = settings.value.hotKeyCode, modifiers = settings.value.hotKeyModifiers
            if !hotKey.register(code: code, modifiers: modifiers) { settings.error = settings.l10n["conflict"] }
        }
        panelController?.updateSettings()
        settingsController?.window?.title = settings.l10n["settings"]
        configureMenu()
        conversations?.checkExpiry()
    }
    @objc private func recordingChanged(_ notification: Notification) {
        recordingShortcut = notification.object as? Bool ?? false
        if recordingShortcut { hotKey.suspend() }
        else { settingsChanged() }
    }
    @objc private func showSettings(_ sender: Any?) {
        panelController.dismiss(restoreFocus: false)
        if settingsController == nil {
            settingsController = SettingsController(settings: settings) { [weak self] code, modifiers in
                self?.hotKey.register(code: code, modifiers: modifiers) ?? false
            }
        }
        settingsController?.present()
    }
    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Instant")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        symbol?.isTemplate = true
        item.button?.image = symbol
        item.button?.toolTip = "Instant"
        item.button?.setAccessibilityLabel("Instant")
        item.button?.setAccessibilityIdentifier("instant.status")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Instant-UITests/menu-state.json")
            let state: [String: Any] = ["visible": item.isVisible, "hasButton": item.button != nil,
                                       "actions": utilityMenu().items.filter { !$0.isSeparatorItem }.map(\.title)]
            if let data = try? JSONSerialization.data(withJSONObject: state) { try? data.write(to: url, options: .atomic) }
        }
    }
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let item = statusItem, let button = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            item.menu = utilityMenu()
            button.performClick(nil)
            item.menu = nil
        } else { panelController.present() }
    }
    private func utilityMenu() -> NSMenu {
        let menu = NSMenu()
        let preferences = NSMenuItem(title: settings.l10n["settings"] + "…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        let restart = NSMenuItem(title: settings.l10n["restart"], action: #selector(restartApplication), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: settings.l10n["quit"], action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }
    @objc private func restartApplication() {
        settings.flushKey()
        settings.save()
        guard conversations.shutdown() else { showSettings(nil); return }
        do {
            let task = Process()
            task.executableURL = Bundle.main.executableURL
            task.arguments = ["--relaunch", String(ProcessInfo.processInfo.processIdentifier)]
            if ProcessInfo.processInfo.arguments.contains("--ui-test") { task.arguments?.append("--ui-test") }
            let handoff = Pipe()
            task.standardInput = handoff
            try task.run()
            let data = try JSONSerialization.data(withJSONObject: ["draft": panelController.draftText])
            handoff.fileHandleForWriting.write(data)
            try handoff.fileHandleForWriting.close()
            NSApp.terminate(nil)
        } catch {
            settings.error = error.localizedDescription
            showSettings(nil)
        }
    }
    private func configureMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = utilityMenu()
        menu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
