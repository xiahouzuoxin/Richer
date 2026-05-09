import AppKit
import CoreGraphics

enum ScreenshotCapture {
    /// Capture a CGImage of the given screen rectangle (in global screen coordinates,
    /// AppKit/Cocoa convention: origin bottom-left, points). Returns nil if the system
    /// declined to provide pixels (typically: Screen Recording permission missing or
    /// the rect lies outside any active display).
    ///
    /// Coordinate note: `CGWindowListCreateImage` expects rects in CoreGraphics
    /// coordinates (origin top-left). We convert from AppKit (origin bottom-left)
    /// using the primary display height per Apple's documented convention.
    static func capture(rect: CGRect) -> CGImage? {
        let cgRect = convertToCGCoordinates(rect)
        return CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution, .boundsIgnoreFraming]
        )
    }

    private static func convertToCGCoordinates(_ appKitRect: CGRect) -> CGRect {
        // AppKit's global coordinate space has origin at the bottom-left of the
        // primary screen. CG/Cocoa screenshots want top-left origin.
        // Total visible vertical span: max y of any screen.
        guard let primary = NSScreen.screens.first else { return appKitRect }
        let primaryHeight = primary.frame.height
        // In multi-display setups, all screens share AppKit's coordinate space,
        // so converting against the primary screen's height is correct as long as
        // we use the primary's frame.height (not visibleFrame).
        let flippedY = primaryHeight - appKitRect.origin.y - appKitRect.height
        return CGRect(
            x: appKitRect.origin.x,
            y: flippedY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }
}
