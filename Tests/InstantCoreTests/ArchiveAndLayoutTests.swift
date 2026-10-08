import Foundation
import CoreGraphics
import Testing
@testable import InstantCore

struct ArchiveAndLayoutTests {
    @Test func olderPreferencesKeepTheConnectionAndGainNewDefaults() throws {
        let json = Data("""
        {"archiveMinutes":10,"baseURL":"https://example.test/v1","model":"existing-model","language":"ja",
         "hotKeyCode":49,"hotKeyModifiers":2048,"translationShortcut":"commandT","translationKeyCode":17,"translationModifiers":256}
        """.utf8)
        let value = try JSONDecoder().decode(AppConfiguration.self, from: json)
        #expect(value.baseURL == "https://example.test/v1")
        #expect(value.model == "existing-model")
        #expect(value.archiveMinutes == 10)
        #expect(value.language == "ja")
        #expect(value.archiveKeyCode == 34 && value.archiveModifiers == 2048)
        #expect(value.archiveFolderPath.isEmpty)
    }
    @Test func newArchivePreferencesRoundTrip() throws {
        var value = AppConfiguration()
        value.archiveFolderPath = "/tmp/Chosen Archive"
        value.archiveKeyCode = 7
        value.archiveModifiers = 4352
        #expect(try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func legacyBlurPreferenceIsIgnoredWithoutLosingConnectionSettings() throws {
        let json = Data("""
        {"backgroundBlurRadius":24,"baseURL":"https://example.test/v1","model":"existing-model","language":"ja"}
        """.utf8)
        let value = try JSONDecoder().decode(AppConfiguration.self, from: json)
        #expect(value.baseURL == "https://example.test/v1")
        #expect(value.model == "existing-model")
        #expect(value.language == "ja")
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        #expect(saved["backgroundBlurRadius"] == nil)
    }
    @Test func changingOutputFolderKeepsOneRecoverableConversation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original")
        let chosen = root.appendingPathComponent("chosen")
        let checkpoint = original.appendingPathComponent(".current.json")
        let first = try ConversationStore(directory: original, checkpointURL: checkpoint)
        var conversation = Conversation()
        var turn = Turn(question: "Question", mode: .chat)
        turn.answer = "Saved answer"
        turn.state = .complete
        conversation.turns = [turn]
        try first.save(conversation)
        let next = try ConversationStore(directory: chosen, checkpointURL: checkpoint)
        #expect(try next.recover()?.id == conversation.id)
        try next.archive(conversation)
        #expect(try first.recover() == nil)
        #expect(try next.recover() == nil)
        #expect(FileManager.default.fileExists(atPath: first.fileURL(conversation).path))
        #expect(try String(contentsOf: next.fileURL(conversation), encoding: .utf8).contains("Saved answer"))
    }
    @Test func invalidDestinationCannotRemoveTheCurrentConversation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ConversationStore(directory: root)
        var conversation = Conversation()
        conversation.turns = [Turn(question: "Keep this", mode: .chat)]
        try first.save(conversation)
        let file = root.appendingPathComponent("not-a-folder")
        try Data("occupied".utf8).write(to: file)
        #expect(throws: (any Error).self) { try ConversationStore(directory: file) }
        #expect(try first.recover()?.turns.first?.question == "Keep this")
    }
    @Test func growingShellDoesNotScrollAFittingAnswerUpward() {
        #expect(TextViewport.followingOrigin(contentHeight: 200, maximumViewportHeight: 450) == 0)
        #expect(TextViewport.followingOrigin(contentHeight: 450, maximumViewportHeight: 450) == 0)
        #expect(TextViewport.followingOrigin(contentHeight: 520, maximumViewportHeight: 450) == 70)
    }
    @Test func inputHeightChangesOnlyAtLineBoundaries() {
        #expect(TextViewport.inputHeight(lineCount: 0) == 68)
        #expect(TextViewport.inputHeight(lineCount: 1) == 68)
        #expect(TextViewport.inputHeight(lineCount: 2) == 96)
        #expect(TextViewport.inputHeight(lineCount: 3) == 124)
        #expect(TextViewport.inputHeight(lineCount: 30) == 124)
    }
    @Test func fractionalAnimationHeightsKeepTheTopOnAPixelBoundary() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for value: CGFloat in [68.01, 68.26, 102.12, 204.97] {
            let height = TextViewport.snappedHeight(value, scale: 2)
            let frame = PanelGeometry.frame(contentSize: CGSize(width: 680, height: height), screenFrame: screen, top: 700)
            #expect(frame.maxY - PanelGeometry.margin == 700)
            #expect((frame.minY * 2).rounded() == frame.minY * 2)
        }
    }
}
