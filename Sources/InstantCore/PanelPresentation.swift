import Foundation
import CoreGraphics

public enum PanelGeometry {
    /// Transparent room for the spring and the glass edge, equal on every side.
    public static let margin: CGFloat = 24

    public static func frame(contentSize: CGSize, screenFrame: CGRect, top: CGFloat) -> CGRect {
        let size = CGSize(width: contentSize.width + margin * 2, height: contentSize.height + margin * 2)
        let x: CGFloat = screenFrame.midX - size.width * 0.5
        let y: CGFloat = top - contentSize.height - margin
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

public struct PanelVisualState: Equatable {
    public var scaleX: CGFloat
    public var scaleY: CGFloat
    public var offsetY: CGFloat
    public var opacity: CGFloat

    public static let visible = PanelVisualState(scaleX: 1, scaleY: 1, offsetY: 0, opacity: 1)
    public static let entering = PanelVisualState(scaleX: 0.90, scaleY: 0.80, offsetY: 9, opacity: 0)
    public static let exiting = PanelVisualState(scaleX: 0.94, scaleY: 0.86, offsetY: 6, opacity: 0)

    public static func interpolate(from: Self, to: Self, geometry: CGFloat, opacity: CGFloat) -> Self {
        Self(scaleX: from.scaleX + (to.scaleX - from.scaleX) * geometry,
             scaleY: from.scaleY + (to.scaleY - from.scaleY) * geometry,
             offsetY: from.offsetY + (to.offsetY - from.offsetY) * geometry,
             opacity: min(1, max(0, from.opacity + (to.opacity - from.opacity) * opacity)))
    }
}

public enum PanelMotionCurve {
    /// One soft settle, rather than a repeating spring or an abrupt final snap.
    public static func reveal(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress)) - 1
        return 1 + 2.1 * t * t * t + 1.1 * t * t
    }
    public static func easeOut(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress))
        return 1 - pow(1 - t, 3)
    }
    public static func smooth(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress))
        return t * t * (3 - 2 * t)
    }
}
