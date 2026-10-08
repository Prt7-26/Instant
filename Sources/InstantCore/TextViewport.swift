import Foundation
import CoreGraphics

public enum TextViewport {
    /// Use the final viewport while its shell grows. Scrolling against each
    /// intermediate animation frame makes existing lines move up and back down.
    public static func followingOrigin(contentHeight: CGFloat, maximumViewportHeight: CGFloat) -> CGFloat {
        max(0, contentHeight - max(1, maximumViewportHeight))
    }
    public static func snappedHeight(_ height: CGFloat, scale: CGFloat) -> CGFloat {
        ceil(height * max(1, scale)) / max(1, scale)
    }
    public static func inputHeight(lineCount: Int) -> CGFloat {
        40 + CGFloat(min(3, max(1, lineCount))) * 28
    }
}
