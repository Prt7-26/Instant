// MaterialView
// Private CoreAnimation and CoreGraphics API declarations

#ifndef MaterialViewPrivate_h
#define MaterialViewPrivate_h

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - CALayer Private Extensions

@interface CALayer (MaterialViewPrivate)

@property (assign) BOOL allowsGroupBlending;
@property (assign) BOOL shadowPathIsBounds;

@end

// MARK: - CABackdropLayer

@class CABackdropLayer;

@protocol CABackdropLayerDelegate <CALayerDelegate>

@optional

- (void)backdropLayerStatisticsDidChange:(CABackdropLayer *)layer;

@end

@interface CABackdropLayer: CALayer

/// When YES, the backdrop ignores content from offscreen layer groups (e.g., off-screen windows).
/// Improves performance by not sampling content that isn't visible.
@property BOOL ignoresOffscreenGroups;

/// When YES, the backdrop layer coordinates with WindowServer for behind-window blending.
/// Required for sampling content behind the window (behindWindow blending mode).
@property BOOL windowServerAware;

/// The amount (in points) the backdrop effect extends beyond the layer bounds.
/// Useful for preventing edge artifacts with blur effects.
@property CGFloat bleedAmount;

/// Interval for backdrop statistics updates (used with statisticsType).
@property CGFloat statisticsInterval;

/// Type of statistics to gather from the backdrop (e.g., average color, luminance).
/// See kCABackdropStatistics* constants.
@property (copy) NSString *statisticsType;

/// When YES, disables blur effects when the backdrop is fully occluded.
/// Improves performance when backdrop content isn't visible.
@property BOOL disablesOccludedBackdropBlurs;

/// When YES, applies filters in-place without creating intermediate buffers.
/// Can improve performance but may affect quality.
@property BOOL allowsInPlaceFiltering;

/// When YES, the layer only captures content without displaying it.
/// Useful for getting backdrop statistics without visual output.
@property BOOL captureOnly;

/// Additional margin around the backdrop capture area.
@property CGFloat marginWidth;

/// Custom rectangle for backdrop capture (default uses layer bounds).
@property CGRect backdropRect;

/// Scale factor for the backdrop capture. Lower values (e.g., 0.25) improve performance
/// but reduce quality. Default is typically 0.5 or lower for blur effects.
@property CGFloat scale;

/// When YES, uses a global namespace for group names across all windows.
@property BOOL usesGlobalGroupNamespace;

/// Group name for coordinating multiple backdrop layers that should blend together.
/// Layers with the same groupName composite as a single continuous backdrop.
@property (copy) NSString *groupName;

/// Namespace for the group name. For behind-window blending, Apple uses a specific
/// WindowServer namespace.
@property (copy) NSString *groupNamespace;

/// When NO, disables the backdrop effect entirely (layer becomes transparent).
@property (getter=isEnabled) BOOL enabled;

/// When YES, allows WindowServer to substitute a solid color when the actual
/// backdrop content cannot be sampled (e.g., secure input, DRM content).
/// This prevents black rectangles in those scenarios.
@property BOOL allowsSubstituteColor;

@end

extern NSString * const kCABackdropStatisticsNone;
extern NSString * const kCABackdropStatisticsType1;
extern NSString * const kCABackdropStatisticsTime;
extern NSString * const kCABackdropStatisticsType;
extern NSString * const kCABackdropStatisticsRedAverage;
extern NSString * const kCABackdropStatisticsGreenAverage;
extern NSString * const kCABackdropStatisticsBlueAverage;
extern NSString * const kCABackdropStatisticsLuminanceStandardDeviation;

// MARK: - CAFilter

@interface CAFilter : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>

@property (copy) NSString *name;
@property (getter=isEnabled) BOOL enabled;
@property BOOL cachesInputImage;

+ (instancetype)filterWithType:(NSString *)type;
+ (instancetype)filterWithName:(NSString *)name;
+ (NSArray<NSString *> *)filterTypes;

- (instancetype)initWithType:(NSString *)type;
- (instancetype)initWithName:(NSString *)name;

@end

// Filter type constants
extern NSString * const kCAFilterGaussianBlur;
extern NSString * const kCAFilterColorSaturate;
extern NSString * const kCAFilterColorBrightness;
extern NSString * const kCAFilterColorContrast;
extern NSString * const kCAFilterColorMatrix;
extern NSString * const kCAFilterColorInvert;
extern NSString * const kCAFilterColorHueRotate;
extern NSString * const kCAFilterColorMonochrome;
extern NSString * const kCAFilterMultiplyColor;
extern NSString * const kCAFilterMultiplyGradient;

// Blend mode filter constants
extern NSString * const kCAFilterNormalBlendMode;
extern NSString * const kCAFilterMultiplyBlendMode;
extern NSString * const kCAFilterDarkenBlendMode;
extern NSString * const kCAFilterLightenBlendMode;
extern NSString * const kCAFilterColorBurnBlendMode;
extern NSString * const kCAFilterColorDodgeBlendMode;
extern NSString * const kCAFilterLinearBurnBlendMode;
extern NSString * const kCAFilterLinearDodgeBlendMode;
extern NSString * const kCAFilterOverlayBlendMode;
extern NSString * const kCAFilterSoftLightBlendMode;
extern NSString * const kCAFilterHardLightBlendMode;
extern NSString * const kCAFilterVividLightBlendMode;
extern NSString * const kCAFilterLinearLightBlendMode;
extern NSString * const kCAFilterPinLightBlendMode;
extern NSString * const kCAFilterHardMixBlendMode;
extern NSString * const kCAFilterDifferenceBlendMode;
extern NSString * const kCAFilterExclusionBlendMode;
extern NSString * const kCAFilterSubtractBlendMode;
extern NSString * const kCAFilterDivideBlendMode;
extern NSString * const kCAFilterScreenBlendMode;
extern NSString * const kCAFilterPlusD;
extern NSString * const kCAFilterPlusL;
extern NSString * const kCAFilterClear;
extern NSString * const kCAFilterCopy;
extern NSString * const kCAFilterSourceIn;
extern NSString * const kCAFilterSourceOut;
extern NSString * const kCAFilterSourceAtop;
extern NSString * const kCAFilterDestOver;
extern NSString * const kCAFilterDestIn;
extern NSString * const kCAFilterDestOut;
extern NSString * const kCAFilterDestAtop;
extern NSString * const kCAFilterXor;

// MARK: - NSWindow Private Extensions

@interface NSWindow (MaterialViewPrivate)

/// Registers a backdrop view with the window for coordination (corner masks, etc.).
/// Apple's NSVisualEffectView calls this in viewDidMoveToWindow.
- (void)_registerBackdropView:(NSView *)view;

/// Unregisters a backdrop view from the window.
- (void)_unregisterBackdropView:(NSView *)view;

/// Returns the array of registered backdrop views.
- (NSArray *)_registeredBackdropViews;

/// Whether the window should get corner mask from visual effect view.
- (BOOL)_shouldGetCornerMaskFromVisualEffectView;

/// Notifies the window that corner mask has changed.
- (void)_cornerMaskChanged;

/// Whether the window has an active appearance ignoring key focus.
- (BOOL)_hasActiveAppearanceIgnoringKeyFocus;

/// Whether visual effect views should always use WindowServer-aware backdrops.
- (BOOL)_visualEffectViewAlwaysUseWSAwareBackdrops;

@end

// MARK: - NSView Private Extensions

@interface NSView (MaterialViewPrivate)

/// Returns YES if the view has a Solarium (glass) appearance (macOS 14+).
- (BOOL)_hasSolariumAppearance;

@end

// MARK: - NSAppearance Private Extensions

@interface NSAppearance (MaterialViewPrivate)

/// Returns YES if this appearance wants Solarium (glass) styling (macOS 14+).
- (BOOL)_wantsSolarium;

/// Returns an appearance that prefers Solarium styling.
- (NSAppearance *)_appearancePreferringSolarium;

/// Returns an appearance that disables Solarium styling.
- (NSAppearance *)_appearanceDisablingSolarium;

@end

// MARK: - CGS Private Functions

typedef int32_t CGSConnectionID;

extern CGSConnectionID CGSMainConnectionID(void);

extern CGError CGSSetWindowTags(CGSConnectionID cid, int32_t wid, const int32_t *tags, int32_t maxTagSize);
extern CGError CGSClearWindowTags(CGSConnectionID cid, int32_t wid, const int32_t *tags, int32_t maxTagSize);
extern CGError CGSGetWindowTags(CGSConnectionID cid, int32_t wid, int32_t *tags, int32_t maxTagSize);

extern void CGSGetCatenatedWindowTransform(CGSConnectionID cid, int32_t wid, CGAffineTransform *transform);
extern CGError CGSFlushSurface(CGSConnectionID cid, int32_t wid, int32_t sid, int32_t param);

#ifdef __cplusplus
}
#endif

#endif /* MaterialViewPrivate_h */
