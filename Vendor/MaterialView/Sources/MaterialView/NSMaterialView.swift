//
//  NSMaterialView.swift
//  MaterialView
//
//  Created by Oskar Groth on 2021-02-05.
//  Copyright © 2020-2024 Oskar Groth. All rights reserved.
//

import Cocoa
import CoreGraphics
import MaterialViewPrivate

// Retained from the upstream SwiftUI wrapper for the AppKit-only distribution.
public extension CACornerMask {
    static var all: CACornerMask { [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner] }
}

// MARK: - Public Filter Constants

/// Darken blend mode filter for use with MaterialView effects
public let kCAFilterDarkenBlendMode = "darkenBlendMode"
/// Lighten blend mode filter for use with MaterialView effects
public let kCAFilterLightenBlendMode = "lightenBlendMode"
/// Dest over compositing filter for use with MaterialView effects
public let kCAFilterDestOver = "destOver"

// MARK: - CALayer Extension

extension CALayer {
    /// Disable implicit animations for common properties
    func disableActions() {
        actions = [
            "position": NSNull(),
            "onOrderIn": NSNull(),
            "onOrderOut": NSNull(),
            "sublayers": NSNull(),
            "contents": NSNull(),
            "bounds": NSNull()
        ]
    }
}

public extension NSColor {
    static func rgbGray(gray: CGFloat, alpha: CGFloat) -> NSColor {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let color = CGColor(colorSpace: space, components: [gray, gray, gray, alpha]) else {
            return NSColor(white: gray, alpha: alpha)
        }
        return NSColor(cgColor: color) ?? NSColor(white: gray, alpha: alpha)
    }
}

/// A view that adds translucency and vibrancy effects to the views in your interface.
///
/// When you want views to be more prominent in your interface, place them in a
/// backdrop view. The backdrop view is partially transparent, allowing some of
/// the underlying content to show through. Typically, you use a backdrop view
/// to blur background content, instead of obscuring it completely. It can also
/// make its contained content more vibrant to ensure that it remains prominent.
///
/// A suggested use in designing visual containers is the use of "cards"; apply
/// a `.light` or `.dark` effect to the backdrop view, set its `cornerRadius = 4.5`,
/// `rimOpacity = 0.25`, and add a `NSView.shadow` (visually similar to `NSWindow`).
///
/// Note: if set as the containing `window`'s `contentView`, the window's
/// `isOpaque` value will be changed. If the window's `contentView` is changed,
/// the original settings are restored.
///
/// Based on: https://github.com/avaidyam/BackdropView/
public class NSMaterialView: NSVisualEffectView {

    /// Enable to print debug logging for layer updates
    public static var debugLogging = false

    private func debugLog(_ message: String) {
        if Self.debugLogging {
            print("[MaterialView] \(message)")
        }
    }
    
    /// The `Effect` structure describes the parameters used by the `MaterialView`
    /// to produce its effects.
    ///
    /// Effects support multiple states similar to how CoreUI provides materials:
    /// - **Active state**: When the window is key/main
    /// - **Inactive state**: When the window loses focus (optional, auto-derived if not provided)
    /// - **Accessibility fallbacks**: For reduced transparency and increased contrast settings
    ///
    /// Colors are provided as autoclosures to support dynamic appearance changes (light/dark mode).
    public struct Effect {

        // MARK: - Material Style

        /// Style configuration for a material state (active, inactive, emphasized, or accessibility fallback).
        public struct MaterialStyle {
            /// The background color blended with content behind the MaterialView.
            public let backgroundColor: () -> NSColor

            /// The tint color overlaid on the backdrop.
            public let tintColor: () -> NSColor

            /// The compositing filter for the tint layer (e.g., "darkenBlendMode", "lightenBlendMode").
            public let tintFilter: Any?

            /// The saturation factor for the backdrop (1.0 = normal, >1 = more saturated).
            public let saturationFactor: CGFloat?

            /// The brightness adjustment for the backdrop.
            public let brightnessFactor: CGFloat?

            /// The gaussian blur radius.
            public let blurRadius: CGFloat?

            /// How much the effect extends beyond layer bounds.
            public let bleedAmount: CGFloat?

            /// Creates a state configuration with the specified parameters.
            public init(
                backgroundColor: @autoclosure @escaping () -> NSColor,
                tintColor: @autoclosure @escaping () -> NSColor = .clear,
                tintFilter: Any? = nil,
                saturationFactor: CGFloat? = nil,
                brightnessFactor: CGFloat? = nil,
                blurRadius: CGFloat? = nil,
                bleedAmount: CGFloat? = nil
            ) {
                self.backgroundColor = backgroundColor
                self.tintColor = tintColor
                self.tintFilter = tintFilter
                self.saturationFactor = saturationFactor
                self.brightnessFactor = brightnessFactor
                self.blurRadius = blurRadius
                self.bleedAmount = bleedAmount
            }
        }

        // MARK: - Properties

        /// Configuration for the active (window is key) state.
        public let active: MaterialStyle

        /// Configuration for the inactive (window not key) state.
        /// If nil, automatically derives from active state with reduced opacity.
        public let inactive: MaterialStyle?

        /// Configuration for the emphasized state (e.g., selected rows, focused elements).
        /// If nil, auto-derives from active with boosted saturation.
        public let emphasized: MaterialStyle?

        /// Configuration for reduced transparency accessibility setting.
        /// When set, replaces backdrop+tint with a solid color.
        public let reducedTransparency: MaterialStyle?

        /// Configuration for increased contrast accessibility setting.
        /// When set, provides higher contrast colors.
        public let increasedContrast: MaterialStyle?

        /// The rim colors (inner and outer) for edge highlighting.
        public let rimColor: (inner: NSColor, outer: NSColor)

        /// The rim widths (inner and outer) for edge highlighting.
        public let rimWidth: (inner: CGFloat, outer: CGFloat)

        // MARK: - Initializers

        /// Creates an Effect with full state configuration support.
        ///
        /// - Parameters:
        ///   - active: Configuration for the active window state.
        ///   - inactive: Configuration for the inactive window state. If nil, auto-derived from active.
        ///   - emphasized: Configuration for the emphasized state. If nil, auto-derived from active with boosted saturation.
        ///   - reducedTransparency: Accessibility fallback for reduced transparency setting.
        ///   - increasedContrast: Accessibility fallback for increased contrast setting.
        ///   - rimColor: Inner and outer rim colors for edge highlighting.
        ///   - rimWidth: Inner and outer rim widths.
        public init(
            active: MaterialStyle,
            inactive: MaterialStyle? = nil,
            emphasized: MaterialStyle? = nil,
            reducedTransparency: MaterialStyle? = nil,
            increasedContrast: MaterialStyle? = nil,
            rimColor: (inner: NSColor, outer: NSColor) = (.clear, .clear),
            rimWidth: (inner: CGFloat, outer: CGFloat) = (0, 0)
        ) {
            self.active = active
            self.inactive = inactive
            self.emphasized = emphasized
            self.reducedTransparency = reducedTransparency
            self.increasedContrast = increasedContrast
            self.rimColor = rimColor
            self.rimWidth = rimWidth
        }

        // MARK: - State Resolution

        /// Returns the appropriate state configuration based on current conditions.
        ///
        /// Priority order:
        /// 1. Increased contrast (if accessibility setting enabled)
        /// 2. Reduced transparency (if accessibility setting enabled)
        /// 3. Emphasized + Inactive (if both conditions apply)
        /// 4. Emphasized (if active and emphasized)
        /// 5. Inactive state (if window not active)
        /// 6. Active state (default)
        ///
        /// - Parameters:
        ///   - isWindowActive: Whether the window is currently active/key.
        ///   - isEmphasized: Whether the view is in an emphasized state (e.g., selected).
        ///   - reduceTransparency: Whether the reduce transparency accessibility setting is enabled.
        ///   - increaseContrast: Whether the increase contrast accessibility setting is enabled.
        /// - Returns: The appropriate MaterialStyle for the current conditions.
        public func resolvedConfig(
            isWindowActive: Bool,
            isEmphasized: Bool = false,
            reduceTransparency: Bool = false,
            increaseContrast: Bool = false
        ) -> MaterialStyle {
            // Priority 1: Increased contrast accessibility
            if increaseContrast {
                if let config = increasedContrast {
                    return config
                }
                // Auto-derive: opaque version of active background
                return autoOpaqueConfig(from: active)
            }

            // Priority 2: Reduced transparency accessibility
            if reduceTransparency {
                if let config = reducedTransparency {
                    return config
                }
                // Auto-derive: opaque version of active background
                return autoOpaqueConfig(from: active)
            }

            // Priority 3: Emphasized state (works for both active and inactive)
            if isEmphasized {
                if let config = emphasized {
                    return config
                }
                // Auto-derive emphasized from active: boost saturation by ~20%
                return autoEmphasizedConfig(from: active)
            }

            // Priority 4: Inactive state
            if !isWindowActive, let config = inactive {
                return config
            }

            // Priority 5: Active state (or auto-derived inactive)
            if !isWindowActive {
                // Auto-derive inactive from active: same colors but backdrop disabled
                return active
            }

            return active
        }

        /// Auto-derives an emphasized configuration from a base config by boosting saturation.
        private func autoEmphasizedConfig(from base: MaterialStyle) -> MaterialStyle {
            let saturationBoost: CGFloat = 1.2
            return MaterialStyle(
                backgroundColor: base.backgroundColor(),
                tintColor: base.tintColor(),
                tintFilter: base.tintFilter,
                saturationFactor: (base.saturationFactor ?? 1.0) * saturationBoost,
                brightnessFactor: base.brightnessFactor,
                blurRadius: base.blurRadius,
                bleedAmount: base.bleedAmount
            )
        }

        /// Auto-derives an opaque configuration for accessibility (reduce transparency / increase contrast).
        private func autoOpaqueConfig(from base: MaterialStyle) -> MaterialStyle {
            return MaterialStyle(
                backgroundColor: base.backgroundColor().withAlphaComponent(1.0)
            )
        }
        
        // MARK: - Preset Effects

        /// A clear effect (only applies blur and saturation); when inactive,
        /// appears transparent. Not suggested for typical use.
        public static var clear = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 1.00, alpha: 0.05),
                tintColor: NSColor(calibratedWhite: 1.00, alpha: 0.00)
            )
        )

        /// A medium light effect.
        public static var mediumLight = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 1.00, alpha: 0.30),
                tintColor: NSColor(calibratedWhite: 0.94, alpha: 1.00),
                tintFilter: kCAFilterDarkenBlendMode
            )
        )

        /// A panel light effect matching system panels.
        /// Includes active, inactive, emphasized, and accessibility fallback configurations.
        public static var panelLight = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.9647, alpha: 0.45),
                tintColor: NSColor.rgbGray(gray: 0.9333, alpha: 0.5),
                tintFilter: kCAFilterDarkenBlendMode,
                saturationFactor: 1.8,
                blurRadius: 30.0
            ),
            inactive: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.92, alpha: 0.6),
                tintColor: NSColor.rgbGray(gray: 0.9333, alpha: 0.7),
                tintFilter: kCAFilterDarkenBlendMode,
                saturationFactor: 1.2,
                blurRadius: 30.0
            ),
            emphasized: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.95, alpha: 0.55),
                tintColor: NSColor.rgbGray(gray: 0.9, alpha: 0.6),
                tintFilter: kCAFilterDarkenBlendMode,
                saturationFactor: 2.2,
                blurRadius: 30.0
            ),
            reducedTransparency: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.8784, alpha: 1.0)
            ),
            increasedContrast: MaterialStyle(
                backgroundColor: NSColor(calibratedRed: 0.8235, green: 0.8235, blue: 0.8235, alpha: 1.0)
            ),
            rimColor: (.clear, NSColor.white.withAlphaComponent(0.5))
        )

        /// A panel dark effect matching system panels.
        /// Includes active, inactive, emphasized, and accessibility fallback configurations.
        public static var panelDark = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.2157, alpha: 0.45),
                tintColor: NSColor.rgbGray(gray: 0.08627, alpha: 0.5),
                tintFilter: kCAFilterLightenBlendMode,
                saturationFactor: 1.6,
                blurRadius: 30.0
            ),
            inactive: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.18, alpha: 0.6),
                tintColor: NSColor.rgbGray(gray: 0.08627, alpha: 0.7),
                tintFilter: kCAFilterLightenBlendMode,
                saturationFactor: 1.2,
                blurRadius: 30.0
            ),
            emphasized: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.24, alpha: 0.55),
                tintColor: NSColor.rgbGray(gray: 0.1, alpha: 0.6),
                tintFilter: kCAFilterLightenBlendMode,
                saturationFactor: 2.0,
                blurRadius: 30.0
            ),
            reducedTransparency: MaterialStyle(
                backgroundColor: NSColor.rgbGray(gray: 0.12, alpha: 1.0)
            ),
            increasedContrast: MaterialStyle(
                backgroundColor: NSColor(calibratedRed: 0.09804, green: 0.09804, blue: 0.09804, alpha: 1.0)
            ),
            rimColor: (NSColor.white.withAlphaComponent(0.2), NSColor.black.withAlphaComponent(0.8))
        )

        /// A light effect.
        public static var light = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 0.97, alpha: 0.70),
                tintColor: NSColor(calibratedWhite: 0.94, alpha: 1.00),
                tintFilter: kCAFilterDarkenBlendMode
            )
        )

        /// An ultra light effect.
        public static var ultraLight = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 0.97, alpha: 0.85),
                tintColor: NSColor(calibratedWhite: 0.94, alpha: 1.00),
                tintFilter: kCAFilterDarkenBlendMode
            )
        )

        /// A medium dark effect.
        public static var mediumDark = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 1.00, alpha: 0.40),
                tintColor: NSColor(calibratedWhite: 0.84, alpha: 1.00),
                tintFilter: kCAFilterDarkenBlendMode
            )
        )

        /// A dark effect.
        public static var dark = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.45),
                tintColor: NSColor(calibratedWhite: 0.16, alpha: 1.00),
                tintFilter: kCAFilterLightenBlendMode
            )
        )

        /// An ultra dark effect.
        public static var ultraDark = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.80),
                tintColor: NSColor(calibratedWhite: 0.01, alpha: 1.00),
                tintFilter: kCAFilterLightenBlendMode
            )
        )

        /// A selection effect that matches the user's current aqua color preference.
        public static var selection = Effect(
            active: MaterialStyle(
                backgroundColor: NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.7),
                tintColor: NSColor.keyboardFocusIndicatorColor,
                tintFilter: kCAFilterDestOver
            )
        )
    }
    
    /// If multiple `MaterialView`s within the same layer tree (that is, window)
    /// share the same `BlendGroup`, they will be composited and blended
    /// together as a single continuous backdrop.
    public final class BlendGroup {
        
        fileprivate static let removedNotification = Notification.Name("MaterialView.BlendGroup.deinit")
        
        fileprivate let value = UUID().uuidString
        
        public init() {}
        
        deinit {
            NotificationCenter.default.post(name: BlendGroup.removedNotification,
                                            object: nil, userInfo: ["value": self.value])
        }
        
        /// The `global` BlendGroup, if it is desired that all backdrops share
        /// the same blending group through the layer tree (window).
        public static let global = BlendGroup()
        
        fileprivate static func `default`() -> String {
            return UUID().uuidString
        }
    }
    
    /// If `state` is set to `.followsWindowActiveState` or `NSWorkspace`'s
    /// `accessibilityDisplayShouldReduceTransparency` is true, the visual change
    /// between active and inactive states may be animated.
    public var animatesImplicitStateChanges: Bool = false

    /// When `true`, the material view appears emphasized (e.g., for selection states).
    /// This affects how the tint color is applied and can be used for highlighting.
    public override var isEmphasized: Bool {
        didSet {
            debugLog("isEmphasized changed to: \(isEmphasized)")
            self.transaction(self.animatesImplicitStateChanges) {
                self.updateAppearanceState()
            }
        }
    }
    
    /// The visual effect to present within the `MaterialView`. See `Effect`.
    public var effect: Effect = .clear {
        didSet {
            self.transaction {
                // Apply rim configuration (doesn't depend on state)
                self.rim?.innerColor = effect.rimColor.inner
                self.rim?.outerColor = effect.rimColor.outer
                self.rim?.borderWidth = effect.rimWidth.outer
                self.rim?.inner.borderWidth = effect.rimWidth.inner
                self.rim?.setupCornerRadius()

                // Always apply active config's filter values directly
                // This ensures sliders always have immediate effect
                let config = effect.active
                if let saturation = config.saturationFactor {
                    self.backdrop?.setValue(saturation, forKeyPath: "filters.colorSaturate.inputAmount")
                }
                if let brightness = config.brightnessFactor {
                    self.backdrop?.setValue(brightness, forKeyPath: "filters.colorBrightness.inputAmount")
                }
                if let blur = config.blurRadius {
                    self.backdrop?.setValue(blur, forKeyPath: "filters.gaussianBlur.inputRadius")
                }
                if let bleed = config.bleedAmount {
                    self.backdrop?.bleedAmount = bleed
                }
                self.backdrop?.backgroundColor = config.backgroundColor().cgColor
                self.tint?.backgroundColor = config.tintColor().cgColor
                self.tint?.compositingFilter = config.tintFilter
            }
            // Update appearance state for state-dependent changes (active/inactive, accessibility)
            self.updateAppearanceState()
        }
    }
    
    /// If multiple `MaterialView`s within the same layer tree share the same
    /// `BlendGroup`, they will be composited and blended together as a single
    /// continuous backdrop.
    public weak var blendingGroup: BlendGroup? = nil {
        didSet {
            self.transaction {
                self.backdrop?.groupName = self.blendingGroup?.value ?? BlendGroup.default()
            }
        }
    }
    
    /// The gaussian blur radius of the visual effect. Animatable.
    public var blurRadius: CGFloat {
        get { return self.backdrop?.value(forKeyPath: "filters.gaussianBlur.inputRadius") as? CGFloat ?? 0 }
        set {
            self.transaction {
                self.backdrop?.setValue(newValue, forKeyPath: "filters.gaussianBlur.inputRadius")
            }
        }
    }
    
    /// The background color saturation factor of the visual effect. Animatable.
    public var saturationFactor: CGFloat {
        get { return self.backdrop?.value(forKeyPath: "filters.colorSaturate.inputAmount") as? CGFloat ?? 0 }
        set {
            self.transaction {
                self.backdrop?.setValue(newValue, forKeyPath: "filters.colorSaturate.inputAmount")
            }
        }
    }
    
    /// The background color brightness factor of the visual effect. Animatable.
    public var brightnessFactor: CGFloat {
        get { return self.backdrop?.value(forKeyPath: "filters.colorBrightness.inputAmount") as? CGFloat ?? 0 }
        set {
            self.transaction {
                self.backdrop?.setValue(newValue, forKeyPath: "filters.colorBrightness.inputAmount")
            }
        }
    }
    
    /// The bleed amount for the backdrop layer. Controls how much the effect extends beyond the layer bounds.
    public var bleedAmount: CGFloat {
        get { return self.backdrop?.bleedAmount ?? 0 }
        set {
            self.transaction {
                self.backdrop?.bleedAmount = newValue
            }
        }
    }
    
    /// The corner radius of the view.
    public var cornerRadius: CGFloat = 0.0 {
        didSet {
            self.transaction {
                self.container?.cornerRadius = self.cornerRadius
                self.colorFillLayer?.cornerRadius = self.cornerRadius
                self.rim?._cornerRadius = self.cornerRadius
                self.updateMaskImage()
            }
        }
    }
    
    /// The corner mask of the view.
    public var cornerMask: CACornerMask = .all {
        didSet {
            self.transaction {
                self.container?.maskedCorners = cornerMask
                self.colorFillLayer?.maskedCorners = cornerMask
                self.rim?.maskedCorners = cornerMask
                self.layer?.maskedCorners = cornerMask
            }
        }
    }
    
    /// The `MaterialView`'s rim serves to provide a visual contrast at its edges.
    /// If `rimOpacity > 0.0`, a slight hairline border is rendered around the view.
    public var rimOpacity: CGFloat = 1.0 {
        didSet {
            self.transaction {
                self.rim!.opacity = Float(rimOpacity)
            }
        }
    }
    
    /// Automatically `.behindWindow` if set as the contentView of the window.
    /// Otherwise, the view is ALWAYS `.withinWindow` blended.
    public override var blendingMode: NSVisualEffectView.BlendingMode {
        get { return (self.window?.contentView == self || isContentView) ? .behindWindow : .withinWindow }
        set { }
    }
    
    /// Always `.headerView`; use `effect` instead.
    public override var material: NSVisualEffectView.Material {
        get { return .headerView }
        set { }
    }
    
    /// Specify how the `effect` should reflect window activity or accessibility state.
    public override var state: NSVisualEffectView.State {
        get { return self._state }
        set { self._state = newValue }
    }
    
    /// The scale factor for the backdrop layer (affects performance vs quality).
    public var scale: CGFloat = 0.25 {
        didSet {
            backdrop?.scale = scale
        }
    }

    /// When true, forces the view to behave as if it's the window's contentView,
    /// enabling behindWindow blending even when not actually the contentView.
    public var isContentView: Bool = false

    /// Override the system reduce transparency setting. When nil, uses system setting.
    public var reduceTransparencyOverride: Bool? = nil {
        didSet {
            reduceTransparencyChanged(nil)
        }
    }

    /// Override the system increase contrast setting. When nil, uses system setting.
    public var increaseContrastOverride: Bool? = nil {
        didSet {
            reduceTransparencyChanged(nil)
        }
    }

    /// A mask image that defines the shape of the material effect.
    /// When set, the material effect is clipped to the non-transparent parts of the image.
    /// If nil and cornerRadius > 0, a rounded rect mask is auto-generated.
    public override var maskImage: NSImage? {
        didSet {
            self.transaction {
                self.updateMaskImage()
            }
        }
    }

    /// When true, uses continuous (smooth) corner curves matching Apple's design language.
    /// This applies to both the container layer and auto-generated mask images.
    public var usesContinuousCorners: Bool = true {
        didSet {
            self.transaction {
                self.container?.cornerCurve = usesContinuousCorners ? .continuous : .circular
                self.updateMaskImage()
            }
        }
    }

    private var _state: NSVisualEffectView.State = .followsWindowActiveState {
        didSet {
            debugLog("_state changed to: \(_state.rawValue)")
            guard let _ = self.backdrop else { return }
            self.reduceTransparencyChanged(nil)
        }
    }
    
    override public var debugDescription: String {
        return "<NSMaterialView: \(Unmanaged.passUnretained(self).toOpaque()) blur=\(blurRadius) sat=\(saturationFactor) corner=\(cornerRadius)>"
    }
    
    private var backdrop: CABackdropLayer? = nil
    private var tint: CALayer? = nil
    private var container: CALayer? = nil
    private var rim: RimLayer? = nil
    private var colorFillLayer: CALayer? = nil
    private var maskLayer: CALayer? = nil
    private var isRegisteredWithWindow: Bool = false
    
    public convenience init() {
        self.init(frame: .zero)
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }
    
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.commonInit()
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    private func commonInit() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.masksToBounds = false
        self.layer?.name = "view"

        // Tell the `NSVisualEffectView` to not do its job:
        super.state = .active
        super.blendingMode = .withinWindow
        super.material = .appearanceBased
        self.setValue(true, forKey: "clear")
        
        // Set up our backdrop view:
        self.backdrop = CABackdropLayer()
        self.backdrop!.name = "backdrop"
        self.backdrop!.allowsGroupBlending = true
        self.backdrop!.allowsGroupOpacity = true
        self.backdrop!.allowsEdgeAntialiasing = false
        self.backdrop!.disablesOccludedBackdropBlurs = true
        self.backdrop!.ignoresOffscreenGroups = true
        self.backdrop!.allowsInPlaceFiltering = false
        self.backdrop!.bleedAmount = 0.0
        self.backdrop!.scale = scale
        // Note: allowsSubstituteColor is set dynamically in viewDidMoveToWindow
        // based on blending mode. It should only be YES for behindWindow mode.
        
        // Set up the backdrop filters:
        let blur = CAFilter(type: kCAFilterGaussianBlur)!
        let saturate = CAFilter(type: kCAFilterColorSaturate)!
        let brightness = CAFilter(type: kCAFilterColorBrightness)!
        blur.setValue(true, forKey: "inputNormalizeEdges")
        self.backdrop!.filters = [saturate, blur, brightness]
        
        // Set up the tint and container view:
        self.tint = CALayer()
        self.tint!.name = "tint"
        self.container = CALayer()
        self.container!.name = "container"
        self.container!.masksToBounds = true
        self.container!.allowsGroupBlending = true
        self.container!.allowsEdgeAntialiasing = false
        self.container!.sublayers = [self.backdrop!, self.tint!]
        self.container?.cornerCurve = .continuous
        self.layer?.insertSublayer(self.container!, at: 0)
        
        // Set up color fill layer for accessibility fallback (reduced transparency / increased contrast)
        // This layer replaces backdrop+tint when accessibility modes require solid colors
        self.colorFillLayer = CALayer()
        self.colorFillLayer!.name = "colorFill"
        self.colorFillLayer!.isHidden = true
        self.colorFillLayer!.cornerCurve = .continuous
        // Insert in container as sibling to backdrop/tint - shown instead of them for accessibility
        self.container!.addSublayer(self.colorFillLayer!)

        // Set up rim:
        self.rim = RimLayer()
        self.layer?.addSublayer(self.rim!)

        // Set our effect-related properties:
        self.blendingGroup = nil
        self.blurRadius = 30.0
        self.saturationFactor = 2.5
        self.effect = .clear
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.reduceTransparencyChanged(_:)),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: NSWorkspace.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(self.colorVariantsChanged(_:)),
                                               name: NSColor.systemColorsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.blendGroupsChanged(_:)),
                                               name: BlendGroup.removedNotification, object: nil)
    }
    
    public override func layout() {
        debugLog("layout")
        super.layout()
        self.transaction(false) {
            let bounds = self.layer?.bounds ?? .zero
            self.container!.frame = bounds
            self.backdrop!.frame = bounds
            self.tint!.frame = bounds
            self.colorFillLayer?.frame = bounds
            self.rim!.frame = bounds.insetBy(dx: -rim!.borderWidth, dy: -rim!.borderWidth)
            self.updateMaskImage()
        }
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = self.window?.backingScaleFactor ?? 1.0
        self.transaction {
            self.layer?.contentsScale = scale
            self.container!.contentsScale = scale
            self.backdrop!.contentsScale = scale
            self.tint!.contentsScale = scale
            self.colorFillLayer?.contentsScale = scale
            self.maskLayer?.contentsScale = scale
            self.rim!.contentsScale = scale
            self.rim!.inner.contentsScale = scale
        }
    }
    
    @objc private func blendGroupsChanged(_ note: NSNotification!) {
        guard let removed = note.userInfo?["value"] as? String else { return }
        guard let backdrop = self.backdrop, backdrop.groupName == removed else { return }
        
        self.transaction(self.animatesImplicitStateChanges) {
            backdrop.groupName = BlendGroup.default()
        }
    }
    
    @objc private func colorVariantsChanged(_ note: NSNotification!) {
        guard let _ = self.backdrop else { return }

        DispatchQueue.main.async {
            // Re-evaluate colors since system colors may have changed
            self.updateAppearanceState()
        }
    }
    
    @objc private func reduceTransparencyChanged(_ note: NSNotification!) {
        debugLog("reduceTransparencyChanged: \(note?.name.rawValue ?? "nil")")
        updateAppearanceState()
    }
    
    /// Updates the appearance state based on accessibility settings and window state.
    private func updateAppearanceState() {
        guard let backdrop = self.backdrop,
              let tint = self.tint,
              let container = self.container else { return }

        let shouldAnimate = self.animatesImplicitStateChanges
        let reduceTransparency = reduceTransparencyOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let increaseContrast = increaseContrastOverride ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        // Determine window active state
        let isWindowActive = self.window?.isMainWindow ?? false
        let shouldFollowWindowState = self._state == .followsWindowActiveState
        let isEffectivelyActive = (
            self._state == .active ||
            (shouldFollowWindowState && isWindowActive)
        )

        // Resolve the appropriate state configuration
        let config = self.effect.resolvedConfig(
            isWindowActive: isEffectivelyActive,
            isEmphasized: self.isEmphasized,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )

        // Use solid color fallback for accessibility modes (when config has no blur)
        let useColorFill = reduceTransparency || increaseContrast

        self.transaction(shouldAnimate) {
            // Show/hide color fill layer for accessibility (replaces backdrop+tint)
            if let colorFill = self.colorFillLayer {
                colorFill.isHidden = !useColorFill
                if useColorFill {
                    // Use the resolved background color as the solid fill
                    colorFill.backgroundColor = config.backgroundColor().cgColor
                    colorFill.cornerRadius = self.cornerRadius
                }
            }

            // When using color fill, hide backdrop+tint; otherwise show them based on state
            if useColorFill {
                backdrop.isHidden = true
                tint.isHidden = true
            } else {
                backdrop.isHidden = false
                tint.isHidden = false

                // Apply resolved configuration
                backdrop.backgroundColor = config.backgroundColor().cgColor
                tint.backgroundColor = config.tintColor().cgColor
                tint.compositingFilter = config.tintFilter

                // Apply optional parameters from config (fall back to current values if nil)
                if let saturation = config.saturationFactor {
                    backdrop.setValue(saturation, forKeyPath: "filters.colorSaturate.inputAmount")
                }
                if let brightness = config.brightnessFactor {
                    backdrop.setValue(brightness, forKeyPath: "filters.colorBrightness.inputAmount")
                }
                if let blur = config.blurRadius {
                    backdrop.setValue(blur, forKeyPath: "filters.gaussianBlur.inputRadius")
                }
                if let bleed = config.bleedAmount {
                    backdrop.bleedAmount = bleed
                }

                // Enable/disable backdrop based on state (for inactive without explicit config)
                let shouldDisableBackdrop = !isEffectivelyActive && self.effect.inactive == nil
                backdrop.isEnabled = !shouldDisableBackdrop
                backdrop.opacity = shouldDisableBackdrop ? 0 : 1
            }

            // Ensure backdrop is in layer hierarchy
            if backdrop.superlayer == nil {
                container.insertSublayer(backdrop, at: 0)
            }

            // Increase contrast: force rims to full opacity and 1px width (if effect has rims)
            if let rim = self.rim {
                if increaseContrast {
                    let hasInnerRim = self.effect.rimWidth.inner > 0 || self.effect.rimColor.inner.alphaComponent > 0
                    let hasOuterRim = self.effect.rimWidth.outer > 0 || self.effect.rimColor.outer.alphaComponent > 0
                    if hasInnerRim || hasOuterRim {
                        rim.opacity = 1.0
                        if hasInnerRim {
                            rim.inner.borderWidth = 1.0
                            rim.innerColor = self.effect.rimColor.inner.withAlphaComponent(1.0)
                        }
                        if hasOuterRim {
                            rim.borderWidth = 1.0
                            rim.outerColor = self.effect.rimColor.outer.withAlphaComponent(1.0)
                        }
                        rim.setupCornerRadius()
                    }
                } else {
                    // Reset to original effect values
                    rim.opacity = 1.0
                    rim.innerColor = self.effect.rimColor.inner
                    rim.outerColor = self.effect.rimColor.outer
                    rim.inner.borderWidth = self.effect.rimWidth.inner
                    rim.borderWidth = self.effect.rimWidth.outer
                    rim.setupCornerRadius()
                }
            }
        }
    }

    /// Updates the mask image on the container layer.
    /// If maskImage is set, uses that. Otherwise auto-generates a rounded rect if cornerRadius > 0.
    private func updateMaskImage() {
        guard let container = self.container else { return }
        let bounds = container.bounds
        debugLog("updateMaskImage - bounds: \(bounds), maskImage: \(maskImage != nil), cornerRadius: \(cornerRadius), usesContinuous: \(usesContinuousCorners)")

        // If we have a custom mask image, apply it
        if let image = self.maskImage {
            debugLog("  -> setting custom mask image")
            if self.maskLayer == nil {
                self.maskLayer = CALayer()
                self.maskLayer!.name = "mask"
            }
            self.maskLayer!.frame = bounds
            self.maskLayer!.contentsScale = self.window?.backingScaleFactor ?? 1.0
            self.maskLayer!.contents = image.layerContents(forContentsScale: self.maskLayer!.contentsScale)
            container.mask = self.maskLayer
        }
        // If cornerRadius > 0 and we're not using continuous corners (which the layer handles natively),
        // we could generate a mask. But since we use cornerRadius on the container with masksToBounds,
        // we don't need an explicit mask for simple rounded rects.
        else if cornerRadius > 0 && !usesContinuousCorners {
            debugLog("  -> setting cornerRadius mask (non-continuous)")
            // For non-continuous corners, generate a rounded rect mask
            if self.maskLayer == nil {
                self.maskLayer = CALayer()
                self.maskLayer!.name = "mask"
            }
            self.maskLayer!.frame = bounds
            self.maskLayer!.cornerRadius = cornerRadius
            self.maskLayer!.backgroundColor = NSColor.black.cgColor
            container.mask = self.maskLayer
        }
        else {
            debugLog("  -> clearing mask (using container's built-in corners)")
            // Use the container's built-in corner radius handling
            container.mask = nil
            self.maskLayer = nil
        }
    }

    /// Returns whether the view or its appearance wants Solarium (glass) styling (macOS 14+).
    /// Note: Solarium detection requires private API calls that return primitive BOOL values,
    /// which don't work reliably with perform(Selector). For now, this returns false.
    /// In the future, this could be implemented via NSInvocation or other means.
    private var hasSolariumAppearance: Bool {
        // Solarium is a macOS 14+ glass appearance style.
        // Detection would require calling private _hasSolariumAppearance or _wantsSolarium methods,
        // but these return BOOL primitives which don't work with perform(Selector).
        // For custom materials, we don't need to match Solarium styling anyway.
        return false
    }

    private func transaction(_ animate: Bool? = nil, _ handler: () -> ()) {
        // If animate is nil, don't create a new transaction - just run handler
        // This allows outer transactions (e.g., from SwiftUI wrapper) to control animation
        let saved = NSAppearance.current
        NSAppearance.current = self.effectiveAppearance
        
        if let animate = animate {
            CATransaction.begin()
            CATransaction.setDisableActions(!animate)
            handler()
            CATransaction.commit()
        } else {
            handler()
        }
        
        NSAppearance.current = saved
    }
    
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        debugLog("viewWillMove(toWindow: \(newWindow != nil ? "window" : "nil"))")
        super.viewWillMove(toWindow: newWindow)

        // Unregister from current window
        if let oldWindow = self.window {
            if oldWindow.contentView == self || isContentView {
                self.configurator.unapply(from: oldWindow)
            }
            // Unregister backdrop view
            if isRegisteredWithWindow {
                unregisterFromWindow(oldWindow)
            }
        }

        guard let _ = self.window else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification,
                                                  object: self.window!)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignMainNotification,
                                                  object: self.window!)
    }

    public override func viewDidMoveToWindow() {
        debugLog("viewDidMoveToWindow")
        super.viewDidMoveToWindow()

        // behindWindow blending requires windowServerAware and allowsSubstituteColor
        // withinWindow blending should NOT use allowsSubstituteColor (causes flickering)
        let isBehindWindow = (self.window?.contentView == self || isContentView)
        self.backdrop?.windowServerAware = isBehindWindow
        self.backdrop?.allowsSubstituteColor = isBehindWindow

        if let newWindow = self.window {
            if newWindow.contentView == self || isContentView {
                self.configurator.apply(to: newWindow)
            }
            // Register backdrop view with window
            registerWithWindow(newWindow)
        }

        guard let _ = self.window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(self.reduceTransparencyChanged(_:)),
                                               name: NSWindow.didBecomeMainNotification, object: self.window!)
        NotificationCenter.default.addObserver(self, selector: #selector(self.reduceTransparencyChanged(_:)),
                                               name: NSWindow.didResignMainNotification, object: self.window!)
        self.reduceTransparencyChanged(NSNotification(name: NSWindow.didBecomeMainNotification, object: nil))
    }

    /// Registers this view with the window for backdrop coordination.
    /// This allows the window to coordinate corner masks and other backdrop-related features.
    private func registerWithWindow(_ window: NSWindow) {
        guard !isRegisteredWithWindow else { return }
        let selector = Selector(("_registerBackdropView:"))
        if window.responds(to: selector) {
            window.perform(selector, with: self)
            isRegisteredWithWindow = true
        }
    }

    /// Unregisters this view from the window.
    private func unregisterFromWindow(_ window: NSWindow) {
        guard isRegisteredWithWindow else { return }
        let selector = Selector(("_unregisterBackdropView:"))
        if window.responds(to: selector) {
            window.perform(selector, with: self)
        }
        isRegisteredWithWindow = false
    }

    public override func updateLayer() {
        debugLog("updateLayer called - NOT calling super to prevent NSVisualEffectView layer manipulation")
        // Do NOT call super.updateLayer() - NSVisualEffectView would recreate its material layers
        // and potentially cause flickering
    }

    public override func viewDidChangeEffectiveAppearance() {
        debugLog("viewDidChangeEffectiveAppearance")
        super.viewDidChangeEffectiveAppearance()
        // Update appearance when system appearance changes (light/dark mode, Solarium, etc.)
        // This re-evaluates colors since they may be appearance-dependent via autoclosures
        self.updateAppearanceState()
    }

    // MARK: - Private SPI

    private var configurator = WindowConfigurator()

    /// Declared for NSVisualEffectView; affects non-contentView backdrops.
    @objc private func _shouldAutoFlattenLayerTree() -> Bool {
        return false
    }

    /// Controls key `NSWindow` operations if the `MaterialView` is its `contentView`.
    private struct WindowConfigurator {
        private var observer: Any? = nil

        private var shouldAutoFlattenLayerTree = true
        private var canHostLayersInWindowServer = true
        private var isOpaque = false
        private var backgroundColor: NSColor? = nil

        /// Call upon migration to a new window.
        mutating func apply(to newWindow: NSWindow) {
            let cid = NSApp.value(forKey: "contextID") as! Int32
            self.shouldAutoFlattenLayerTree = newWindow.value(forKey: "shouldAutoFlattenLayerTree") as? Bool ?? true
            self.canHostLayersInWindowServer = newWindow.value(forKey: "canHostLayersInWindowServer") as? Bool ?? true
            self.isOpaque = newWindow.isOpaque
            self.backgroundColor = newWindow.backgroundColor

            // The WindowServer automatically flattens the render layer tree on its
            // end after a delayed duration (currently 1.05s). This is likely to
            // allow higher performance in windows that don't require effects.
            newWindow.setValue(false, forKey: "shouldAutoFlattenLayerTree")

            // `CGSSetSurfaceLayerBackingOptions` needs to be set to prevent layer
            // tree flattening, and `NSWindow` doesn't inform its `NSViewLayerSurface`s
            // to do this, EXCEPT upon initial surface creation, which happens
            // during the first call to `-[NSWindow displayIfNeeded]`, where the layer
            // tree is set up to match the `NSView` tree.
            //
            // A possible fix would be to grab "borderView.layerSurface.surface.surfaceID"
            // and call `CGSSetSurfaceLayerBackingOptions` ourselves, but we don't
            // consider currently set AppKit defaults.
            //
            // Instead, a simple workaround is to toggle `canHostLayersInWindowServer`
            // off and back on again, as this recreates the layer tree immediately
            // in both cases. This is, however, an "expensive" operation, but we
            // don't expect to be swapping `contentView` in and out rapidly anyway.
            newWindow.setValue(false, forKey: "canHostLayersInWindowServer")
            newWindow.setValue(true, forKey: "canHostLayersInWindowServer")

            // If the window is not opaque, the `CABackdropLayer` cannot sample behind it.
            newWindow.isOpaque = false

            // If the window's `backgroundColor` is `.clear`, the theme frame/`borderView`
            // will unfortunately turn off corner masking, which then causes terrible
            // window resize lag. This is likely because without a mask, WindowServer
            // recomputes the "real shape" for any non-opaque windows.
            newWindow.backgroundColor = NSColor.white.withAlphaComponent(0.001)

            // The kCGSNeverFlattenSurfacesDuringSwipesTagBit tells WindowServer to
            // not flatten the layer tree on its end, during Spaces swipes.
            let fixSurfaces: () -> () = { [weak newWindow] in
                guard let newWindow = newWindow else { return }
                // Fixed: bit is 16 on Big Sur
                var x: [Int32] = [0x0, (1 << 16)/*kCGSNeverFlattenSurfacesDuringSwipesTagBit?*/]
                _ = CGSSetWindowTags(cid,
                                     Int32(newWindow.windowNumber),
                                     &x, 0x40/*kCGSRealMaximumTagSize*/)
            }

            // Since `_startLiveResize` and the balanced `_endLiveResize` calls made
            // to `NSWindow` add and then reset this tag, respectively, we want to
            // make sure we restore it ourselves upon `_endLiveResize` using this note.
            DispatchQueue.main.async(execute: fixSurfaces)
            self.observer = NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: newWindow, queue: nil) { _ in
                DispatchQueue.main.async(execute: fixSurfaces)
            }
        }

        /// Call upon migration away from an existing window.
        mutating func unapply(from oldWindow: NSWindow) {
            // See the above notes for the particular order of operations.
            oldWindow.setValue(self.shouldAutoFlattenLayerTree, forKey: "shouldAutoFlattenLayerTree")
            oldWindow.setValue(false, forKey: "canHostLayersInWindowServer")
            oldWindow.setValue(self.canHostLayersInWindowServer, forKey: "canHostLayersInWindowServer")
            oldWindow.isOpaque = self.isOpaque
            oldWindow.backgroundColor = self.backgroundColor

            // There's no need to clear the kCGSNeverFlattenSurfacesDuringSwipesTagBit
            // window tag, as the window will manage that itself upon resize.
            if let observer = self.observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
    }
    
    class RimLayer: CALayer {
        
        var innerColor = NSColor.clear {
            didSet {
                inner.borderColor = innerColor.cgColor
            }
        }
        var outerColor = NSColor.clear {
            didSet {
                borderColor = outerColor.cgColor
            }
        }
        
        var _cornerRadius: CGFloat = 0 {
            didSet {
                setupCornerRadius()
            }
        }
        
        let inner = CALayer()
        
        override init() {
            super.init()
            inner.disableActions()
            name = "rim"
            borderWidth = 0.5
            cornerCurve = .continuous
            inner.cornerCurve = .continuous
            inner.borderWidth = 1
            addSublayer(inner)
            setupCornerRadius()
        }
        
        override init(layer: Any) {
            super.init()
            inner.disableActions()
            let other = layer as! RimLayer
            name = other.name
            innerColor = other.innerColor
            outerColor = other.outerColor
            opacity = other.opacity
            borderWidth = other.borderWidth
            cornerCurve = other.cornerCurve
            inner.cornerCurve = other.inner.cornerCurve
            inner.borderWidth = other.inner.borderWidth
            _cornerRadius = other._cornerRadius
            addSublayer(inner)
            inner.frame = other.inner.frame
            frame = other.frame
            setupCornerRadius()
        }
        
        func setupCornerRadius() {
            inner.cornerRadius = _cornerRadius
            cornerRadius = _cornerRadius + borderWidth
        }
        
        override func layoutSublayers() {
            super.layoutSublayers()
            self.inner.frame = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
