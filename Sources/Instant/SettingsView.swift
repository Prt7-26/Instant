import AppKit
import SwiftUI
import InstantCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let registerShortcut: (UInt32, UInt32) -> Bool
    private var words: L10n { settings.l10n }
    static var contentHeight: CGFloat { min(550, (NSScreen.main?.visibleFrame.height ?? 900) - 90) }

    private func shortcutAvailable(_ code: UInt32, _ modifiers: UInt32, editing: String) -> Bool {
        let config = settings.value
        var used: [(UInt32, UInt32)] = []
        if editing != "global" { used.append((config.hotKeyCode, config.hotKeyModifiers)) }
        if editing != "archive" { used.append((config.archiveKeyCode, config.archiveModifiers)) }
        if editing != "translation", config.translationShortcut != "doubleSpace" {
            used.append((config.translationShortcut == "custom" ? config.translationKeyCode : 17,
                         config.translationShortcut == "custom" ? config.translationModifiers : (config.translationShortcut == "commandT" ? 256 : 768)))
        }
        let available = !used.contains { $0.0 == code && $0.1 == modifiers }
        settings.shortcutError = !available
        return available
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(words["archive"])
                    Spacer()
                    TextField("", value: $settings.value.archiveMinutes, format: .number)
                        .multilineTextAlignment(.trailing).frame(width: 52)
                        .onChange(of: settings.value.archiveMinutes) { _, value in
                            if value < 1 { settings.value.archiveMinutes = 1 }
                            if value > 1440 { settings.value.archiveMinutes = 1440 }
                        }
                    Text(words["minutes"]).foregroundStyle(.secondary)
                }
                HStack {
                    Text(words["manualArchiveShortcut"])
                    Spacer()
                    Recorder(code: settings.value.archiveKeyCode, modifiers: settings.value.archiveModifiers,
                             prompt: words["record"]) { code, modifiers in
                        guard shortcutAvailable(code, modifiers, editing: "archive") else { return false }
                        var value = settings.value
                        value.archiveKeyCode = code
                        value.archiveModifiers = modifiers
                        settings.value = value
                        return true
                    }.frame(width: 160, height: 27)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(words["archiveFolder"])
                        Spacer()
                        Button(words["chooseFolder"]) { settings.chooseArchiveFolder() }
                    }
                    Text((settings.archiveDirectory.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    HStack {
                        Button(words["openFolder"]) { settings.openArchiveFolder() }
                        Spacer()
                        if !settings.value.archiveFolderPath.isEmpty {
                            Button(words["defaultFolder"]) { settings.value.archiveFolderPath = "" }
                        }
                    }
                }
            }
            Section {
                HStack {
                    Text(words["shortcut"])
                    Spacer()
                    Recorder(code: settings.value.hotKeyCode, modifiers: settings.value.hotKeyModifiers,
                             prompt: words["record"]) { code, modifiers in
                        guard shortcutAvailable(code, modifiers, editing: "global") else { return false }
                        guard registerShortcut(code, modifiers) else { settings.shortcutError = true; return false }
                        settings.shortcutError = false
                        var value = settings.value
                        value.hotKeyCode = code
                        value.hotKeyModifiers = modifiers
                        settings.value = value
                        return true
                    }.frame(width: 160, height: 27)
                }
                if settings.shortcutError { Text(words["conflict"]).font(.caption).foregroundStyle(.red) }
            }
            Section {
                SecureField("API Key", text: $settings.apiKey)
                TextField("Base URL", text: $settings.value.baseURL)
                    .textContentType(.URL)
                TextField(words["model"], text: $settings.value.model)
                if !settings.value.baseURL.isEmpty, (try? ChatService.endpoint(for: settings.value.baseURL)) == nil {
                    Text("Base URL · https://…/v1").font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Picker(words["translationShortcut"], selection: $settings.value.translationShortcut) {
                    Text(words["doubleSpace"]).tag("doubleSpace")
                    Text("⌘ T").tag("commandT")
                    Text("⌘ ⇧ T").tag("commandShiftT")
                    Text(words["custom"]).tag("custom")
                }
                .onChange(of: settings.value.translationShortcut) { previous, current in
                    guard current != "doubleSpace" else { return }
                    let code: UInt32 = current == "custom" ? settings.value.translationKeyCode : 17
                    let modifiers: UInt32 = current == "custom" ? settings.value.translationModifiers : (current == "commandT" ? 256 : 768)
                    if !shortcutAvailable(code, modifiers, editing: "translation") { settings.value.translationShortcut = previous }
                }
                if settings.value.translationShortcut == "custom" {
                    HStack {
                        Spacer()
                        Recorder(code: settings.value.translationKeyCode, modifiers: settings.value.translationModifiers,
                                 prompt: words["record"]) { code, modifiers in
                            guard shortcutAvailable(code, modifiers, editing: "translation") else { return false }
                            var value = settings.value
                            value.translationKeyCode = code
                            value.translationModifiers = modifiers
                            settings.value = value
                            return true
                        }.frame(width: 160, height: 27)
                    }
                }
                Picker(words["language"], selection: $settings.value.language) {
                    Text(words["system"]).tag("system")
                    ForEach(Language.supported) { language in Text(language.name).tag(language.id) }
                }
            }
            if let error = settings.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .environment(\.layoutDirection, settings.language.isRTL ? .rightToLeft : .leftToRight)
        .frame(width: 580, height: Self.contentHeight)
        .padding(4)
    }
}

struct Recorder: NSViewRepresentable {
    let code: UInt32
    let modifiers: UInt32
    let prompt: String
    let onCapture: (UInt32, UInt32) -> Bool
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcutTitle = Shortcut.label(code: code, modifiers: modifiers)
        button.prompt = prompt
        button.onCapture = onCapture
        if !button.recording { button.title = button.shortcutTitle }
    }
}

final class RecorderButton: NSButton {
    var shortcutTitle = ""
    var prompt = ""
    var onCapture: ((UInt32, UInt32) -> Bool)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        font = .systemFont(ofSize: 13)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func beginRecording() {
        recording = true
        title = prompt
        window?.makeFirstResponder(self)
        NotificationCenter.default.post(name: .shortcutRecording, object: true)
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let code = UInt32(event.keyCode), modifiers = Shortcut.carbon(event.modifierFlags)
        guard Shortcut.isValid(code: code, modifiers: modifiers) else { NSSound.beep(); return }
        if onCapture?(code, modifiers) == true { shortcutTitle = Shortcut.label(code: code, modifiers: modifiers); finish() }
        else { NSSound.beep() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    private func finish() {
        guard recording else { return }
        recording = false
        title = shortcutTitle
        NotificationCenter.default.post(name: .shortcutRecording, object: false)
    }
}

extension Notification.Name { static let shortcutRecording = Notification.Name("InstantShortcutRecording") }

final class SettingsController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    init(settings: SettingsStore, register: @escaping (UInt32, UInt32) -> Bool) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 588, height: SettingsView.contentHeight + 8),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = settings.l10n["settings"]
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, registerShortcut: register))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() {
        window?.title = settings.l10n["settings"]
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { settings.flushKey() }
}
