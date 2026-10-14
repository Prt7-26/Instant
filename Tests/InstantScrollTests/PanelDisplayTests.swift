import AppKit
import Testing
import InstantCore
@testable import Instant

@MainActor @Suite(.serialized)
struct PanelDisplayTests {
    @Test func movingThePanelBetweenSimulatedDisplaysPreservesInputAndFocus() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Instant-DisplayTests-" + UUID().uuidString)
        let settings = SettingsStore(readKeychain: false, configurationFile: root.appendingPathComponent("settings.json"))
        let controller = try ConversationController(settings: settings, directory: root.appendingPathComponent("Conversations"))
        let panel = PanelController(settings: settings, conversation: controller)
        defer { panel.panel.close(); controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        panel.restoreDraft("保留未发送的草稿")
        #expect(panel.panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.panel.canBecomeKey && !panel.panel.canBecomeMain)
        for frame in [NSRect(x: 0, y: 0, width: 1440, height: 900),
                      NSRect(x: -1920, y: -120, width: 1920, height: 1080),
                      NSRect(x: 1440, y: 200, width: 2560, height: 1440),
                      NSRect(x: 0, y: -1080, width: 1920, height: 1080)] {
            panel.present(on: PanelDisplay(frame: frame, visibleFrame: frame, scale: 1))
            #expect(panel.panel.isVisible)
            #expect(abs(panel.panel.frame.midX - frame.midX) < 1)
            #expect(frame.contains(panel.panel.frame))
            #expect(panel.draftText == "保留未发送的草稿" && controller.draft == panel.draftText)
            #expect(panel.panel.firstResponder === panel.composer.editor)
            #expect(controller.isVisible && controller.conversation.turns.isEmpty)
        }
    }
}
