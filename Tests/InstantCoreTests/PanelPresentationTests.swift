import Foundation
import CoreGraphics
import Testing
@testable import InstantCore

struct PanelPresentationTests {
    @Test func invocationSelectsTheDisplayUnderThePointerInEveryArrangement() throws {
        let main = PanelDisplay(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 835), scale: 2)
        for frame in [CGRect(x: -1920, y: -120, width: 1920, height: 1080),
                      CGRect(x: 1440, y: 200, width: 2560, height: 1440),
                      CGRect(x: 0, y: 900, width: 1920, height: 1080),
                      CGRect(x: 0, y: -1080, width: 1920, height: 1080)] {
            let secondary = PanelDisplay(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 24), scale: 1)
            let selected = try #require(PanelDisplay.select(at: CGPoint(x: frame.midX, y: frame.midY),
                                                           from: [main, secondary], fallback: main))
            #expect(selected.frame == frame && selected.scale == 1)
            #expect(!selected.shouldDismiss(isVisible: true, isDismissing: false, isOnActiveSpace: true,
                                           currentFrame: main.frame))
            #expect(selected.shouldDismiss(isVisible: true, isDismissing: false, isOnActiveSpace: true,
                                          currentFrame: frame))
            #expect(!selected.shouldDismiss(isVisible: true, isDismissing: false, isOnActiveSpace: false,
                                           currentFrame: frame))
            #expect(!selected.shouldDismiss(isVisible: true, isDismissing: true, isOnActiveSpace: true,
                                           currentFrame: frame))
            #expect(!selected.shouldDismiss(isVisible: false, isDismissing: false, isOnActiveSpace: true,
                                           currentFrame: frame))
        }
        #expect(PanelDisplay.select(at: CGPoint(x: 10000, y: 10000), from: [main], fallback: main)?.frame == main.frame)
        #expect(PanelDisplay.select(at: .zero, from: [], fallback: nil) == nil)
    }

    @Test func panelIsHorizontallyCenteredOnEachDisplay() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: -120, width: 1920, height: 1080),
                       CGRect(x: 1440, y: 200, width: 2560, height: 1440)] {
            let frame = PanelGeometry.frame(contentSize: CGSize(width: 680, height: 68), screenFrame: screen, top: 700)
            #expect(frame.midX == screen.midX)
        }
    }
    @Test func expandingAnswerPreservesTheOriginalInputHeightPosition() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let originalTop: CGFloat = 680
        for height: CGFloat in [68, 180, 400, 600] {
            let frame = PanelGeometry.frame(contentSize: CGSize(width: 680, height: height), screenFrame: screen, top: originalTop)
            #expect(frame.maxY - PanelGeometry.margin == originalTop)
            #expect(frame.midX == screen.midX)
        }
    }
    @Test func revealHasVisibleShapeChangeAndOneRestrainedSettle() {
        let frames = (0...100).map { step in
            PanelVisualState.interpolate(from: .entering, to: .visible,
                                         geometry: PanelMotionCurve.reveal(CGFloat(step) / 100),
                                         opacity: PanelMotionCurve.easeOut(min(1, CGFloat(step) / 50)))
        }
        #expect(abs(frames[0].scaleX - 0.90) < 0.000001)
        #expect(abs(frames[0].scaleY - 0.80) < 0.000001)
        #expect(frames.last == .visible)
        #expect(frames.contains { $0.scaleX > 1 && $0.scaleY > 1 })
        #expect(frames.allSatisfy { $0.scaleX <= 1.01 && $0.scaleY <= 1.02 && (0...1).contains($0.opacity) })
    }
    @Test func interruptedAnimationStartsAtTheCurrentVisibleShape() {
        let middle = PanelVisualState.interpolate(from: .entering, to: .visible, geometry: 0.6, opacity: 0.7)
        let reversed = PanelVisualState.interpolate(from: middle, to: .exiting, geometry: 0, opacity: 0)
        #expect(reversed == middle)
        #expect(PanelVisualState.interpolate(from: reversed, to: .visible, geometry: 1, opacity: 1) == .visible)
    }
    @Test func dismissIncludesShapeChangeBeforeTheFinalInvisibleFrame() {
        let middle = PanelVisualState.interpolate(from: .visible, to: .exiting,
                                                 geometry: PanelMotionCurve.smooth(0.5), opacity: PanelMotionCurve.smooth(0.5))
        #expect(middle.scaleX < 1)
        #expect(middle.scaleY < 1)
        #expect(middle.opacity == 0.5)
        #expect(PanelMotionCurve.smooth(0) == 0)
        #expect(PanelMotionCurve.smooth(1) == 1)
    }
}
