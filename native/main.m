#import "PlotData.h"
#import "PlotIcons.h"
#import "PlotView.h"
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Native drawing matching the original CSS chrome; no blur or glass layers.
static BOOL DarkChrome(void) {
    return [[NSAppearance.currentDrawingAppearance
        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
        isEqual:NSAppearanceNameDarkAqua];
}
static NSColor *RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:r / 255 green:g / 255 blue:b / 255 alpha:alpha];
}
static void DrawHeader(NSRect r, BOOL separator) {
    BOOL dark = DarkChrome();
    NSGradient *gradient = [[NSGradient alloc]
        initWithColors:dark ? @[ RGB(17, 17, 16, 1), RGB(14, 14, 13, 1), RGB(10, 10, 9, 1) ]
                            : @[ RGB(251, 251, 249, 1), RGB(249, 249, 247, 1), RGB(244, 244, 242, 1) ]];
    [gradient drawInRect:r angle:270];
    [[NSColor.whiteColor colorWithAlphaComponent:dark ? .06 : .9] setFill];
    NSRectFill(NSMakeRect(r.origin.x, NSMaxY(r) - 1, r.size.width, 1));
    if (separator) {
        [(dark ? RGB(13, 13, 12, 1) : [NSColor.blackColor colorWithAlphaComponent:.15]) setFill];
        NSRectFillUsingOperation(NSMakeRect(r.origin.x, r.origin.y, r.size.width, 1),
                                 NSCompositingOperationSourceOver);
    }
}
static NSBezierPath *ToolbarOutline(NSRect r, BOOL joinsAbove, BOOL joinsBelow) {
    CGFloat left = NSMinX(r), right = NSMaxX(r), bottom = NSMinY(r), top = NSMaxY(r);
    CGFloat bl = 6, br = joinsBelow ? 0 : 6, tl = joinsAbove ? 0 : 6, tr = joinsAbove ? 0 : 6, k = .55228475;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(left + bl, bottom)];
    [p lineToPoint:NSMakePoint(right - br, bottom)];
    [p curveToPoint:NSMakePoint(right, bottom + br)
        controlPoint1:NSMakePoint(right - br + k * br, bottom)
        controlPoint2:NSMakePoint(right, bottom + br - k * br)];
    [p lineToPoint:NSMakePoint(right, top - tr)];
    [p curveToPoint:NSMakePoint(right - tr, top)
        controlPoint1:NSMakePoint(right, top - tr + k * tr)
        controlPoint2:NSMakePoint(right - tr + k * tr, top)];
    [p lineToPoint:NSMakePoint(left + tl, top)];
    [p curveToPoint:NSMakePoint(left, top - tl)
        controlPoint1:NSMakePoint(left + tl - k * tl, top)
        controlPoint2:NSMakePoint(left, top - tl + k * tl)];
    [p lineToPoint:NSMakePoint(left, bottom + bl)];
    [p curveToPoint:NSMakePoint(left + bl, bottom)
        controlPoint1:NSMakePoint(left, bottom + bl - k * bl)
        controlPoint2:NSMakePoint(left + bl - k * bl, bottom)];
    [p closePath];
    return p;
}

@interface ToolbarSurface : NSView
@property(nonatomic) BOOL joinsBelow, joinsAbove;
@property(nonatomic) CGFloat joinX;
@end
@implementation ToolbarSurface
- (NSBezierPath *)outlineInRect:(NSRect)r {
    return ToolbarOutline(r, self.joinsAbove, self.joinsBelow);
}
- (void)drawRect:(NSRect)dirty {
    BOOL dark = DarkChrome();
    NSBezierPath *fill = [self outlineInRect:self.bounds];
    [(dark ? RGB(18, 18, 17, .88) : RGB(235, 235, 233, .88)) setFill];
    [fill fill];
    NSRect r = NSInsetRect(self.bounds, .5, .5);
    NSBezierPath *border = [self outlineInRect:r];
    if (self.joinsAbove) {
        // The top belongs to the toolbar; only the two sides and bottom have an edge.
        border = [NSBezierPath bezierPath];
        [border moveToPoint:NSMakePoint(NSMinX(r), NSMaxY(self.bounds))];
        [border lineToPoint:NSMakePoint(NSMinX(r), NSMinY(r) + 6)];
        [border appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(r), NSMinY(r))
                                         toPoint:NSMakePoint(NSMinX(r) + 6, NSMinY(r))
                                          radius:6];
        [border lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMinY(r))];
        [border appendBezierPathWithArcFromPoint:NSMakePoint(NSMaxX(r), NSMinY(r))
                                         toPoint:NSMakePoint(NSMaxX(r), NSMinY(r) + 6)
                                          radius:6];
        [border lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(self.bounds))];
    } else if (self.joinsBelow) {
        border = [NSBezierPath bezierPath];
        [border moveToPoint:NSMakePoint(self.joinX + .5, NSMinY(r))];
        [border lineToPoint:NSMakePoint(NSMinX(r) + 6, NSMinY(r))];
        [border appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(r), NSMinY(r))
                                         toPoint:NSMakePoint(NSMinX(r), NSMinY(r) + 6)
                                          radius:6];
        [border lineToPoint:NSMakePoint(NSMinX(r), NSMaxY(r) - 6)];
        [border appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(r), NSMaxY(r))
                                         toPoint:NSMakePoint(NSMinX(r) + 6, NSMaxY(r))
                                          radius:6];
        [border lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMaxY(r))];
        [border appendBezierPathWithArcFromPoint:NSMakePoint(NSMaxX(r), NSMaxY(r))
                                         toPoint:NSMakePoint(NSMaxX(r), NSMaxY(r) - 6)
                                          radius:6];
        [border lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(self.bounds))];
    }
    [[NSColor.whiteColor colorWithAlphaComponent:dark ? .10 : .62] setStroke];
    border.lineWidth = 1;
    [border stroke];
    if (!self.joinsAbove) {
        [NSGraphicsContext saveGraphicsState];
        [fill addClip];
        [[NSColor.whiteColor colorWithAlphaComponent:dark ? .06 : .9] setFill];
        NSRectFillUsingOperation(NSMakeRect(0, self.bounds.size.height - 1.5, self.bounds.size.width, 1),
                                 NSCompositingOperationSourceOver);
        [NSGraphicsContext restoreGraphicsState];
    }
}
@end
static const CGFloat ToolbarShadowMargin = 20;
@interface ToolbarShadowView : NSView
@property(nonatomic) NSRect mainRect, stackRect;
@property(nonatomic) BOOL hasStack;
@property(nonatomic) NSBezierPath *silhouette;
- (void)configureMain:(NSRect)main stack:(NSRect)stack hasStack:(BOOL)hasStack;
@end
@implementation ToolbarShadowView
- (void)configureMain:(NSRect)main stack:(NSRect)stack hasStack:(BOOL)hasStack {
    if (self.silhouette && NSEqualRects(self.mainRect, main) && NSEqualRects(self.stackRect, stack) &&
        self.hasStack == hasStack)
        return;
    self.mainRect = main;
    self.stackRect = stack;
    self.hasStack = hasStack;
    NSBezierPath *outline = ToolbarOutline(main, NO, hasStack);
    if (hasStack)
        [outline appendBezierPath:ToolbarOutline(stack, YES, NO)];
    self.silhouette = outline;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirty {
    if (!self.silhouette)
        return;
    [NSGraphicsContext saveGraphicsState];
    // Mask out the whole joined surface, so no shadow shows through the translucent controls or seam.
    NSBezierPath *outside = [NSBezierPath bezierPathWithRect:self.bounds];
    [outside appendBezierPath:self.silhouette];
    outside.windingRule = NSWindingRuleEvenOdd;
    [outside addClip];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:.28];
    shadow.shadowBlurRadius = 9;
    shadow.shadowOffset = NSMakeSize(0, -3);
    [shadow set];
    [NSColor.blackColor setFill];
    [self.silhouette fill];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface IconButton : NSButton
@property(nonatomic) BOOL hovered;
@property(nonatomic) NSTrackingArea *hoverTracking;
@property(nonatomic) CGFloat iconSize;
@property(nonatomic) BOOL headerButton;
@property(nonatomic) NSImage *selectedImage;
@end
@implementation IconButton
- (void)drawRect:(NSRect)dirty {
    BOOL pressed = self.cell.isHighlighted, selected = self.state == NSControlStateValueOn;
    BOOL dark = DarkChrome();
    if (self.enabled && (pressed || self.hovered || (selected && !self.headerButton))) {
        CGFloat alpha = self.headerButton ? (dark ? .075 : .055)
                        : pressed         ? .24
                        : selected        ? (dark ? .22 : .15)
                                          : (dark ? .16 : .12);
        [[(dark ? NSColor.whiteColor : NSColor.blackColor) colorWithAlphaComponent:alpha] setFill];
        CGFloat radius = self.headerButton ? self.bounds.size.height / 2 : 6;
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
    }
    CGFloat size = self.iconSize ?: 16;
    NSRect r = NSMakeRect(NSMidX(self.bounds) - size / 2, NSMidY(self.bounds) - size / 2, size, size);
    CGContextRef c = NSGraphicsContext.currentContext.CGContext;
    CGContextBeginTransparencyLayer(c, NULL);
    [(selected && self.selectedImage ? self.selectedImage : self.image)
            drawInRect:r
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1
        respectFlipped:YES
                 hints:nil];
    [(self.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor) setFill];
    NSRectFillUsingOperation(r, NSCompositingOperationSourceIn);
    CGContextEndTransparencyLayer(c);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTracking)
        [self removeTrackingArea:self.hoverTracking];
    self.hoverTracking = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:self.hoverTracking];
}
- (void)mouseEntered:(NSEvent *)event {
    self.hovered = YES;
    self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
    self.needsDisplay = YES;
}
@end
static NSButton *Icon(NSString *symbol, NSString *help, id target, SEL action, NSRect frame) {
    IconButton *b = [[IconButton alloc] initWithFrame:frame];
    b.image = PlotIcon(symbol, NO);
    b.headerButton = [@[ @"close", @"minimize", @"pin" ] containsObject:symbol];
    if ([symbol isEqual:@"pin"])
        b.selectedImage = PlotIcon(symbol, YES);
    b.iconSize = [@[ @"close", @"minimize", @"pin" ] containsObject:symbol] ? 13 : 16;
    b.imagePosition = NSImageOnly;
    b.target = target;
    b.action = action;
    b.bordered = NO;
    b.toolTip = help;
    b.accessibilityLabel = help;
    b.refusesFirstResponder = YES;
    b.focusRingType = NSFocusRingTypeNone;
    return b;
}
@interface PanelChrome : NSView
@end
@implementation PanelChrome
- (void)drawRect:(NSRect)dirty {
    [NSColor.controlBackgroundColor setFill];
    NSRectFill(self.bounds);
    DrawHeader(NSMakeRect(0, self.bounds.size.height - 28, self.bounds.size.width, 28), YES);
    [NSColor.separatorColor setFill];
    NSFrameRect(self.bounds);
}
@end
@interface SquarePanel : NSPanel
@end
@implementation SquarePanel
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.locationInWindow.y > self.frame.size.height - 28 &&
        event.locationInWindow.x > 30) {
        [self makeKeyAndOrderFront:nil];
        [self performWindowDragWithEvent:event];
        return;
    }
    [super sendEvent:event];
}
@end
static NSPanel *MakePanel(NSString *title, NSSize size) {
    NSPanel *panel = [[SquarePanel alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height + 28)
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    panel.title = title;
    panel.releasedWhenClosed = NO;
    panel.opaque = YES;
    panel.hasShadow = YES;
    panel.backgroundColor = NSColor.controlBackgroundColor;
    panel.contentView = [[PanelChrome alloc] initWithFrame:panel.contentView.bounds];
    NSButton *close =
        Icon(@"close", @"Close Window", panel, @selector(close), NSMakeRect(7, size.height + 5, 18, 18));
    close.autoresizingMask = NSViewMinYMargin;
    [panel.contentView addSubview:close];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:12];
    label.alignment = NSTextAlignmentCenter;
    label.textColor = NSColor.secondaryLabelColor;
    label.frame = NSMakeRect(34, size.height + 6, size.width - 68, 16);
    label.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    [panel.contentView addSubview:label];
    return panel;
}

@class PlotApp, PlotController;
static NSTextField *Label(NSString *text, NSRect frame) {
    NSTextField *v = [NSTextField labelWithString:text ?: @""];
    v.frame = frame;
    v.font = [NSFont systemFontOfSize:11];
    v.lineBreakMode = NSLineBreakByTruncatingMiddle;
    v.toolTip = text;
    return v;
}
static NSTextField *Input(NSString *text, NSRect frame) {
    NSTextField *v = [[NSTextField alloc] initWithFrame:frame];
    v.stringValue = text ?: @"";
    v.font = [NSFont systemFontOfSize:11];
    return v;
}
static NSValue *Box(Bounds b) {
    return [NSValue valueWithBytes:&b objCType:@encode(Bounds)];
}
static Bounds Unbox(NSValue *v) {
    Bounds b;
    [v getValue:&b];
    return b;
}
static void Alert(NSString *title, NSString *message) {
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    a.informativeText = message ?: @"";
    [a runModal];
}
typedef NS_OPTIONS(NSUInteger, PlotResizeEdge) {
    PlotResizeLeft = 1 << 0,
    PlotResizeRight = 1 << 1,
    PlotResizeBottom = 1 << 2,
    PlotResizeTop = 1 << 3,
};
static const CGFloat PlotResizeBorder = 6, PlotResizeCorner = 12;
static const CGFloat ToolbarYInset = 26, ToolbarYWidth = 158;

static PlotResizeEdge PlotResizeHit(NSPoint p, NSSize size) {
    if (p.x < 0 || p.y < 0 || p.x > size.width || p.y > size.height)
        return 0;
    PlotResizeEdge horizontal = p.x < PlotResizeCorner                 ? PlotResizeLeft
                                : p.x >= size.width - PlotResizeCorner ? PlotResizeRight
                                                                       : 0;
    PlotResizeEdge vertical = p.y < PlotResizeCorner                  ? PlotResizeBottom
                              : p.y >= size.height - PlotResizeCorner ? PlotResizeTop
                                                                      : 0;
    if (horizontal && vertical)
        return horizontal | vertical;
    if (p.x < PlotResizeBorder)
        return PlotResizeLeft;
    if (p.x >= size.width - PlotResizeBorder)
        return PlotResizeRight;
    if (p.y < PlotResizeBorder)
        return PlotResizeBottom;
    if (p.y >= size.height - PlotResizeBorder)
        return PlotResizeTop;
    return 0;
}
static NSRect PlotResizeFrame(NSRect original, NSPoint delta, PlotResizeEdge edges, NSSize minimum,
                              NSSize maximum) {
    NSRect r = original;
    if (edges & (PlotResizeLeft | PlotResizeRight)) {
        CGFloat width = original.size.width + (edges & PlotResizeLeft ? -delta.x : delta.x);
        r.size.width = fmin(fmax(width, minimum.width), fmax(minimum.width, maximum.width));
        if (edges & PlotResizeLeft)
            r.origin.x = NSMaxX(original) - r.size.width;
    }
    if (edges & (PlotResizeTop | PlotResizeBottom)) {
        CGFloat height = original.size.height + (edges & PlotResizeBottom ? -delta.y : delta.y);
        r.size.height = fmin(fmax(height, minimum.height), fmax(minimum.height, maximum.height));
        if (edges & PlotResizeBottom)
            r.origin.y = NSMaxY(original) - r.size.height;
    }
    return r;
}
static NSCursor *PlotResizeCursor(PlotResizeEdge edges) {
    BOOL horizontal = edges & (PlotResizeLeft | PlotResizeRight);
    BOOL vertical = edges & (PlotResizeTop | PlotResizeBottom);
    if (!vertical)
        return NSCursor.resizeLeftRightCursor;
    if (!horizontal)
        return NSCursor.resizeUpDownCursor;
    static NSCursor *diagonals[2];
    BOOL rising = edges == (PlotResizeLeft | PlotResizeBottom) || edges == (PlotResizeRight | PlotResizeTop);
    if (!diagonals[rising]) {
        NSImage *image = [NSImage imageWithSize:NSMakeSize(24, 24)
                                        flipped:NO
                                 drawingHandler:^BOOL(NSRect rect) {
                                     NSBezierPath *path = [NSBezierPath bezierPath];
                                     CGFloat a = rising ? 5 : 19, b = rising ? 19 : 5, step = rising ? 5 : -5;
                                     [path moveToPoint:NSMakePoint(5, a)];
                                     [path lineToPoint:NSMakePoint(19, b)];
                                     [path moveToPoint:NSMakePoint(5, a + step)];
                                     [path lineToPoint:NSMakePoint(5, a)];
                                     [path lineToPoint:NSMakePoint(10, a)];
                                     [path moveToPoint:NSMakePoint(14, b)];
                                     [path lineToPoint:NSMakePoint(19, b)];
                                     [path lineToPoint:NSMakePoint(19, b - step)];
                                     path.lineCapStyle = NSLineCapStyleRound;
                                     path.lineJoinStyle = NSLineJoinStyleRound;
                                     [NSColor.whiteColor setStroke];
                                     path.lineWidth = 3.5;
                                     [path stroke];
                                     [NSColor.blackColor setStroke];
                                     path.lineWidth = 1.5;
                                     [path stroke];
                                     return YES;
                                 }];
        diagonals[rising] = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(12, 12)];
    }
    return diagonals[rising];
}

@interface PlotWindow : NSWindow
@end
@implementation PlotWindow
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (BOOL)canBecomeMainWindow {
    return YES;
}
- (void)sendEvent:(NSEvent *)e {
    if (e.type != NSEventTypeLeftMouseDown) {
        [super sendEvent:e];
        return;
    }
    NSPoint p = e.locationInWindow;
    PlotResizeEdge edges = PlotResizeHit(p, self.frame.size);
    // Edges take precedence over header dragging, including the top edge and corners.
    if (edges) {
        [self makeKeyAndOrderFront:nil];
        NSRect original = self.frame;
        NSPoint start = [self convertPointToScreen:p];
        [PlotResizeCursor(edges) push];
        @try {
            while (YES) {
                NSEvent *next =
                    [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
                                       untilDate:NSDate.distantFuture
                                          inMode:NSEventTrackingRunLoopMode
                                         dequeue:YES];
                if (!next)
                    break;
                NSPoint now = NSEvent.mouseLocation;
                NSRect frame = PlotResizeFrame(original, NSMakePoint(now.x - start.x, now.y - start.y), edges,
                                               self.minSize, self.maxSize);
                if (!NSEqualRects(frame, self.frame))
                    [self setFrame:frame display:YES];
                if (next.type == NSEventTypeLeftMouseUp)
                    break;
            }
        } @finally {
            [NSCursor pop];
            [self invalidateCursorRectsForView:self.contentView];
        }
        return;
    }
    if (p.x > 82 && p.y > self.frame.size.height - 28) {
        [self makeKeyAndOrderFront:nil];
        [self performWindowDragWithEvent:e];
        return;
    }
    [super sendEvent:e];
}
@end
@interface ToolbarPanel : NSPanel
@end
@implementation ToolbarPanel
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (BOOL)canBecomeMainWindow {
    return NO;
}
@end
@interface PlotRoot : NSView
@property(nonatomic, weak) PlotController *controller;
@end
@interface PlotApp : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic) Renderer *renderer;
@property(nonatomic) NSMutableArray<PlotController *> *controllers;
@property(nonatomic) ToolbarPanel *toolbar, *yStack;
@property(nonatomic) NSWindow *toolbarShadow;
@property(nonatomic, weak) PlotController *target;
@property(nonatomic) NSPopUpButton *xSelect, *ySelect;
@property(nonatomic) NSMutableArray<NSPopUpButton *> *ySelects;
@property(nonatomic) NSMutableArray<NSButton *> *yRemoves;
@property(nonatomic) NSMutableArray<NSTextField *> *yLabels;
@property(nonatomic) NSButton *yAdd;
@property(nonatomic) CGFloat yColumnX;
@property(nonatomic) NSMutableDictionary<NSString *, NSButton *> *tools;
@property(nonatomic) NSWindowController *settings;
@property(nonatomic) dispatch_queue_t loader;
@property(nonatomic) NSArray<NSString *> *initialPaths;
@property(nonatomic) NSUInteger syntheticCount, syntheticWindows;
- (void)syncFocus;
- (void)updateToolbar;
- (void)placeToolbar;
- (void)syncYStack;
- (void)layoutToolbarShadow;
- (void)syncToolbarShadow;
- (PlotController *)newPlot:(PLGroup *)group;
- (void)openPaths:(NSArray<NSString *> *)paths reply:(BOOL)reply;
- (void)action:(id)sender;
- (void)applyAppearance;
@end
@interface PlotController : NSObject <NSWindowDelegate>
@property(nonatomic, weak) PlotApp *app;
@property(nonatomic) PlotWindow *window;
@property(nonatomic) PlotRoot *root;
@property(nonatomic) NSTextField *title, *positionLabel;
@property(nonatomic) NSButton *pin;
@property(nonatomic) PLGroup *group;
@property(nonatomic) NSMutableArray<PLChart *> *charts;
@property(nonatomic) NSUInteger selected;
@property(nonatomic) NSString *x;
@property(nonatomic) NSArray<NSString *> *ys;
@property(nonatomic) NSArray<NSDictionary *> *rules;
@property(nonatomic) BOOL points, pan, outliers;
@property(nonatomic) NSMutableArray<NSArray<NSValue *> *> *history;
@property(nonatomic) NSInteger historyIndex;
@property(nonatomic) NSPanel *filterPanel;
@property(nonatomic) NSMutableArray<NSDictionary *> *filterFields;
- (instancetype)initWithApp:(PlotApp *)app group:(PLGroup *)group;
- (void)layout;
- (void)updateHeader;
- (void)rebuild;
- (void)perform:(NSString *)action;
- (void)cycle:(BOOL)x backwards:(BOOL)backwards;
- (void)choose:(NSInteger)delta;
- (NSArray<NSValue *> *)ranges;
- (void)applyRanges:(NSArray<NSValue *> *)ranges;
- (void)record;
- (void)addY;
- (void)removeY:(NSUInteger)index;
- (void)setYColumns:(NSArray<NSString *> *)columns keeping:(NSArray<NSNumber *> *)indexes;
@end
@implementation PlotRoot
- (BOOL)isOpaque {
    return YES;
}
- (void)drawRect:(NSRect)dirty {
    [NSColor.whiteColor setFill];
    NSRectFill(self.bounds);
    DrawHeader(NSMakeRect(0, self.bounds.size.height - 28, self.bounds.size.width, 28), NO);

    [NSColor.grayColor setStroke];
    NSBezierPath *grip = [NSBezierPath bezierPath];
    [grip moveToPoint:NSMakePoint(self.bounds.size.width - 8, 2)];
    [grip lineToPoint:NSMakePoint(self.bounds.size.width - 2, 8)];
    [grip stroke];
}
- (void)resetCursorRects {
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat edge = PlotResizeBorder, corner = PlotResizeCorner;
    [self addCursorRect:NSMakeRect(0, corner, edge, MAX(0, h - 2 * corner))
                 cursor:NSCursor.resizeLeftRightCursor];
    [self addCursorRect:NSMakeRect(w - edge, corner, edge, MAX(0, h - 2 * corner))
                 cursor:NSCursor.resizeLeftRightCursor];
    [self addCursorRect:NSMakeRect(corner, 0, MAX(0, w - 2 * corner), edge)
                 cursor:NSCursor.resizeUpDownCursor];
    [self addCursorRect:NSMakeRect(corner, h - edge, MAX(0, w - 2 * corner), edge)
                 cursor:NSCursor.resizeUpDownCursor];
    [self addCursorRect:NSMakeRect(0, 0, corner, corner)
                 cursor:PlotResizeCursor(PlotResizeLeft | PlotResizeBottom)];
    [self addCursorRect:NSMakeRect(w - corner, 0, corner, corner)
                 cursor:PlotResizeCursor(PlotResizeRight | PlotResizeBottom)];
    [self addCursorRect:NSMakeRect(0, h - corner, corner, corner)
                 cursor:PlotResizeCursor(PlotResizeLeft | PlotResizeTop)];
    [self addCursorRect:NSMakeRect(w - corner, h - corner, corner, corner)
                 cursor:PlotResizeCursor(PlotResizeRight | PlotResizeTop)];
}
- (void)layout {
    [super layout];
    [self.controller layout];
    [self.window invalidateCursorRectsForView:self];
}
@end

@implementation PlotController
- (instancetype)initWithApp:(PlotApp *)app group:(PLGroup *)group {
    if (!(self = [super init]))
        return nil;
    self.app = app;
    self.group = group;
    self.rules = @[];
    self.charts = [NSMutableArray new];
    self.history = [NSMutableArray new];
    self.historyIndex = -1;
    self.x = group.x;
    self.ys = group ? @[ group.y ] : @[];
    self.window =
        [[PlotWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 310)
                                      styleMask:NSWindowStyleMaskBorderless |
                                                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                        backing:NSBackingStoreBuffered
                                          defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    self.window.title = @"Plot";
    self.window.minSize = NSMakeSize(240, 170);
    self.window.opaque = YES;
    self.window.backgroundColor = NSColor.whiteColor;
    self.window.hasShadow = YES;
    self.root = [[PlotRoot alloc] initWithFrame:self.window.contentView.bounds];
    self.root.controller = self;
    self.window.contentView = self.root;
    [self.root addSubview:Icon(@"close", @"Close Window (⌘W)", self, @selector(close:), NSZeroRect)];
    [self.root addSubview:Icon(@"minimize", @"Minimize (⌘M)", self, @selector(minimize:), NSZeroRect)];
    self.pin = Icon(@"pin", @"Always on Top (⌥⌘T)", self, @selector(togglePin:), NSZeroRect);
    self.pin.buttonType = NSButtonTypeToggle;
    [self.root addSubview:self.pin];
    self.title = Label(@"Plot", NSZeroRect);
    self.title.font = [NSFont systemFontOfSize:12];
    self.title.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.root addSubview:self.title];
    self.positionLabel = Label(@"", NSZeroRect);
    self.positionLabel.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.positionLabel.lineBreakMode = NSLineBreakByClipping;
    self.positionLabel.cell.usesSingleLineMode = YES;
    self.positionLabel.textColor = NSColor.secondaryLabelColor;
    [self.root addSubview:self.positionLabel];
    if (!group) {
        NSButton *open =
            Icon(@"open", @"Open files (⌘O)", app, @selector(action:), NSMakeRect(194, 139, 32, 32));
        open.identifier = @"open";
        open.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
        [self.root addSubview:open];
    } else
        [self rebuild];
    [self layout];
    [self updateHeader];
    return self;
}
- (void)layout {
    CGFloat w = self.root.bounds.size.width, h = self.root.bounds.size.height;
    for (NSUInteger i = 0; i < 3; i++)
        self.root.subviews[i].frame = NSMakeRect(7 + i * 25, h - 23, 18, 18);
    CGFloat right = w - 7;
    self.positionLabel.hidden = self.group.items.count < 2;
    if (!self.positionLabel.hidden) {
        // NSTextField's cell includes horizontal padding absent from string measurement.
        NSSize fitting = self.positionLabel.cell.cellSize;
        CGFloat width = ceil(fitting.width) + 2;
        CGFloat height = MAX(14, ceil(fitting.height));
        self.positionLabel.frame = NSMakeRect(right - width, h - 14 - height / 2, width, height);
        right -= width + 8;
    }
    self.title.frame = NSMakeRect(83, h - 22, MAX(1, right - 83), 16);
    NSUInteger count = self.charts.count;
    CGFloat plotHeight = MAX(1, (h - 30 - count * 26 - 26) / MAX(1ul, count));
    CGFloat top = h - 29;
    for (NSUInteger i = 0; i < count; i++) {
        BOOL last = i + 1 == count;
        self.charts[i].showsXLabels = last;
        CGFloat height = plotHeight + (last ? 52 : 26);
        self.charts[i].frame = NSMakeRect(0, top - height, w, height);
        self.charts[i].needsLayout = YES;
        top -= height;
    }
}
- (void)close:(id)sender {
    [self.window close];
}
- (void)minimize:(id)sender {
    [self.window miniaturize:nil];
}
- (void)togglePin:(id)sender {
    self.window.level =
        self.window.level == NSFloatingWindowLevel ? NSNormalWindowLevel : NSFloatingWindowLevel;
    self.pin.state =
        self.window.level == NSFloatingWindowLevel ? NSControlStateValueOn : NSControlStateValueOff;
    BOOL pinned = self.window.level == NSFloatingWindowLevel;
    self.pin.toolTip = pinned ? @"Disable Always on Top (⌥⌘T)" : @"Always on Top (⌥⌘T)";
    self.pin.accessibilityLabel = self.pin.toolTip;
    self.pin.needsDisplay = YES;
    if (self.app.target == self)
        [self.app placeToolbar];
}
- (NSString *)displayName:(NSUInteger)index {
    PLDataset *d = self.group.items[index];
    NSUInteger count = 0;
    for (PLDataset *other in self.group.items)
        if ([other.name isEqual:d.name])
            count++;
    return count > 1 ? [NSString stringWithFormat:@"%@ [%@]", d.name,
                                                  d.path.stringByDeletingLastPathComponent.lastPathComponent]
                     : d.name;
}
- (void)updateHeader {
    NSString *text = self.group ? [self displayName:self.selected] : @"Plot";
    self.positionLabel.stringValue =
        self.group.items.count > 1
            ? [NSString stringWithFormat:@"%lu / %lu", self.selected + 1, self.group.items.count]
            : @"";
    self.title.stringValue = text;
    self.title.toolTip = self.group.items.count ? self.group.items[self.selected].path : nil;
    self.window.title = text;
    self.title.textColor = NSApp.isActive && (NSApp.keyWindow == self.window || self.app.target == self)
                               ? NSColor.labelColor
                               : NSColor.secondaryLabelColor;
    [self layout];
    [self.root setNeedsDisplay:YES];
    [self.app updateToolbar];
}
- (void)choose:(NSInteger)delta {
    if (!self.group.items.count)
        return;
    self.selected = (self.selected + self.group.items.count + delta) % self.group.items.count;
    for (PLChart *chart in self.charts) {
        chart.selected = self.selected;
        [chart refresh];
    }
    [self updateHeader];
}
- (NSArray<NSValue *> *)ranges {
    NSMutableArray *a = [NSMutableArray new];
    for (PLChart *c in self.charts)
        [a addObject:Box(c.range)];
    return a;
}
- (void)applyRanges:(NSArray<NSValue *> *)ranges {
    for (NSUInteger i = 0; i < MIN(self.charts.count, ranges.count); i++) {
        self.charts[i].range = Unbox(ranges[i]);
        [self.charts[i] refresh];
    }
    [self.app updateToolbar];
}
- (void)record {
    NSArray *ranges = [self ranges];
    if (!ranges.count)
        return;
    if (self.historyIndex >= 0 && [self.history[self.historyIndex] isEqual:ranges])
        return;
    if (self.historyIndex + 1 < (NSInteger)self.history.count)
        [self.history removeObjectsInRange:NSMakeRange(self.historyIndex + 1,
                                                       self.history.count - self.historyIndex - 1)];
    [self.history addObject:ranges];
    self.historyIndex = self.history.count - 1;
    [self.app updateToolbar];
}
- (void)rebuild {
    if (!self.group)
        return;
    for (PLChart *chart in self.charts)
        [chart removeFromSuperview];
    [self.charts removeAllObjects];
    NSMutableArray<NSIndexSet *> *rowSets = [NSMutableArray new];
    for (PLDataset *d in self.group.items) {
        NSIndexSet *rows = PLFilteredRows(d, self.rules);
        if (self.outliers) {
            NSMutableArray *ys = [NSMutableArray new];
            for (NSString *y in self.ys)
                [ys addObject:@([d.columns indexOfObject:y])];
            rows = PLRemoveOutliers(d, rows, [d.columns indexOfObject:self.x], ys);
        }
        [rowSets addObject:rows];
    }
    __weak PlotController *weak = self;
    for (NSString *y in self.ys) {
        NSMutableArray *series = [NSMutableArray new];
        for (NSUInteger j = 0; j < self.group.items.count; j++) {
            PLDataset *d = self.group.items[j];
            NSIndexSet *rows = rowSets[j];
            NSUInteger xi = [d.columns indexOfObject:self.x], yi = [d.columns indexOfObject:y];
            NSMutableData *data = [NSMutableData dataWithLength:rows.count * sizeof(XY)];
            XY *xy = data.mutableBytes;
            __block NSUInteger index = 0;
            const double *source = d.values.bytes;
            NSUInteger stride = d.columns.count;
            [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
                xy[index++] = (XY){source[r * stride + xi], source[r * stride + yi]};
            }];
            Series *s = [[Series alloc] initWithData:data
                                                name:[self displayName:j]
                                              device:self.app.renderer.device];
            s.xName = self.x;
            s.yName = y;
            [series addObject:s];
        }
        PLChart *chart = [[PLChart alloc] initWithRenderer:self.app.renderer];
        chart.series = series;
        chart.xName = self.x;
        chart.yName = y;
        chart.selected = self.selected;
        chart.points = self.points;
        chart.pan = self.pan;
        chart.range = PLSeriesExtent(series);
        chart.selectDataset = ^(NSInteger delta) {
            [weak choose:delta];
        };
        chart.navigate = ^(BOOL forward) {
            [weak perform:forward ? @"redo-view" : @"undo-view"];
        };
        chart.changed = ^(PLChart *changed, BOOL finished) {
            PlotController *s = weak;
            for (PLChart *other in s.charts)
                if (other != changed) {
                    Bounds b = other.range;
                    b.x = changed.range.x;
                    b.width = changed.range.width;
                    other.range = b;
                    [other refresh];
                }
            if (finished)
                [s record];
        };
        [self.charts addObject:chart];
        [self.root addSubview:chart];
    }
    double min = INFINITY, max = -INFINITY;
    for (PLChart *c in self.charts) {
        min = fmin(min, c.range.x);
        max = fmax(max, c.range.x + c.range.width);
    }
    for (PLChart *c in self.charts) {
        Bounds b = c.range;
        b.x = min;
        b.width = max - min;
        c.range = b;
    }
    [self.history removeAllObjects];
    self.historyIndex = -1;
    [self record];
    [self layout];
    [self updateHeader];
}
- (void)cycle:(BOOL)x backwards:(BOOL)backwards {
    NSArray *columns = self.group.columns;
    if (!columns.count)
        return;
    NSString *old = x ? self.x : self.ys.lastObject;
    NSUInteger index = [columns indexOfObject:old];
    index = (index + columns.count + (backwards ? -1 : 1)) % columns.count;
    NSArray *before = [self ranges];
    if (x)
        self.x = columns[index];
    else {
        NSMutableArray *ys = [self.ys mutableCopy];
        ys[ys.count - 1] = columns[index];
        self.ys = ys;
    }
    [self rebuild];
    for (NSUInteger i = 0; i < MIN(before.count, self.charts.count); i++) {
        Bounds old = Unbox(before[i]), b = self.charts[i].range;
        if (x) {
            b.y = old.y;
            b.height = old.height;
        } else {
            b.x = old.x;
            b.width = old.width;
        }
        self.charts[i].range = b;
        [self.charts[i] refresh];
    }
    [self.history removeAllObjects];
    self.historyIndex = -1;
    [self record];
}
- (NSPanel *)panel:(NSString *)title size:(NSSize)size {
    NSPanel *panel = MakePanel(title, size);
    panel.delegate = self;
    [panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(self.window.frame) + 8, NSMaxY(self.window.frame))];
    return panel;
}
- (void)showFilter {
    if (self.filterPanel) {
        [self.filterPanel makeKeyAndOrderFront:nil];
        return;
    }
    self.filterPanel = [self panel:@"Filter" size:NSMakeSize(400, 330)];
    NSView *v = self.filterPanel.contentView;
    self.filterFields = [NSMutableArray new];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 48, 384, 274)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    NSView *doc =
        [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 365, MAX(274, self.group.columns.count * 30))];
    scroll.documentView = doc;
    [v addSubview:scroll];
    for (NSUInteger i = 0; i < self.group.columns.count; i++) {
        CGFloat y = doc.frame.size.height - (i + 1) * 30;
        NSString *column = self.group.columns[i];
        NSTextField *lo = Input(@"", NSMakeRect(210, y, 70, 24)),
                    *hi = Input(@"", NSMakeRect(285, y, 70, 24));
        lo.placeholderString = @"min";
        hi.placeholderString = @"max";
        lo.accessibilityLabel = [column stringByAppendingString:@" minimum"];
        hi.accessibilityLabel = [column stringByAppendingString:@" maximum"];
        for (NSDictionary *rule in self.rules)
            if ([rule[@"column"] isEqual:column]) {
                lo.stringValue = rule[@"min"] ? [rule[@"min"] stringValue] : @"";
                hi.stringValue = rule[@"max"] ? [rule[@"max"] stringValue] : @"";
            }
        [doc addSubview:Label(column, NSMakeRect(2, y + 4, 200, 20))];
        [doc addSubview:lo];
        [doc addSubview:hi];
        [self.filterFields addObject:@{@"column" : column, @"min" : lo, @"max" : hi}];
    }
    [v addSubview:Icon(@"apply", @"Apply Filter", self, @selector(applyFilter:), NSMakeRect(8, 10, 28, 28))];
    [v addSubview:Icon(@"home", @"Reset Filter", self, @selector(resetFilter:), NSMakeRect(44, 10, 28, 28))];
    [v addSubview:Icon(@"save-image", @"Save Filtered CSV", self, @selector(saveCSV:),
                       NSMakeRect(362, 10, 28, 28))];
    [self.window addChildWindow:self.filterPanel ordered:NSWindowAbove];
    [self.filterPanel makeKeyAndOrderFront:nil];
}
- (void)applyFilter:(id)sender {
    @try {
        NSMutableArray *rules = [NSMutableArray new];
        for (NSDictionary *field in self.filterFields) {
            NSTextField *lo = field[@"min"], *hi = field[@"max"];
            if (!lo.stringValue.length && !hi.stringValue.length)
                continue;
            NSMutableDictionary *rule = [@{@"column" : field[@"column"]} mutableCopy];
            for (NSString *key in @[ @"min", @"max" ]) {
                NSTextField *input = field[key];
                if (!input.stringValue.length)
                    continue;
                NSScanner *scan = [NSScanner scannerWithString:input.stringValue];
                double number;
                if (![scan scanDouble:&number] || !scan.isAtEnd || !isfinite(number))
                    @throw [NSException exceptionWithName:@"Filter"
                                                   reason:@"Filter limits must be finite numbers."
                                                 userInfo:nil];
                rule[key] = @(number);
            }
            if (rule[@"min"] && rule[@"max"] && [rule[@"min"] doubleValue] > [rule[@"max"] doubleValue])
                @throw [NSException exceptionWithName:@"Filter"
                                               reason:@"Minimum must not exceed maximum."
                                             userInfo:nil];
            [rules addObject:rule];
        }
        self.rules = rules;
        [self rebuild];
    } @catch (NSException *e) {
        Alert(@"Invalid filter", e.reason);
    }
}
- (void)resetFilter:(id)sender {
    for (NSDictionary *f in self.filterFields) {
        [f[@"min"] setStringValue:@""];
        [f[@"max"] setStringValue:@""];
    }
    self.rules = @[];
    [self rebuild];
}
- (void)saveCSV:(id)sender {
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@"csv"] ];
    panel.nameFieldStringValue =
        [NSString stringWithFormat:@"%@-filtered.csv",
                                   self.group.items[self.selected].name.stringByDeletingPathExtension];
    [panel beginSheetModalForWindow:self.filterPanel
                  completionHandler:^(NSModalResponse result) {
                      if (result != NSModalResponseOK)
                          return;
                      NSError *error;
                      if (!PLWriteCSV(self.group, self.rules, panel.URL, &error))
                          Alert(@"Export failed", error.localizedDescription);
                  }];
}
- (void)setYColumns:(NSArray<NSString *> *)columns keeping:(NSArray<NSNumber *> *)indexes {
    if (!columns.count || !self.group)
        return;
    NSArray *before = [self ranges];
    Bounds shared = before.count ? Unbox(before[0]) : (Bounds){0, 0, 1, 1};
    self.ys = columns;
    [self rebuild];
    for (NSUInteger i = 0; i < self.charts.count; i++) {
        NSInteger oldIndex = indexes[i].integerValue;
        Bounds b = oldIndex >= 0 && oldIndex < (NSInteger)before.count ? Unbox(before[oldIndex])
                                                                       : self.charts[i].range;
        b.x = shared.x;
        b.width = shared.width;
        self.charts[i].range = b;
        [self.charts[i] refresh];
    }
    [self.history removeAllObjects];
    self.historyIndex = -1;
    [self record];
}
- (void)addY {
    if (!self.group)
        return;
    NSString *column = self.ys.lastObject ?: self.group.y;
    for (NSString *candidate in self.group.columns)
        if (![self.ys containsObject:candidate] && ![candidate isEqual:self.x]) {
            BOOL numeric = NO;
            for (PLDataset *dataset in self.group.items) {
                NSUInteger yi = [dataset.columns indexOfObject:candidate];
                NSUInteger xi = [dataset.columns indexOfObject:self.x];
                if (yi == NSNotFound || xi == NSNotFound)
                    continue;
                for (NSUInteger row = 0; row < dataset.rowCount; row++)
                    if (isfinite([dataset valueAtRow:row column:yi]) && isfinite([dataset valueAtRow:row
                                                                                              column:xi])) {
                        numeric = YES;
                        break;
                    }
                if (numeric)
                    break;
            }
            if (numeric) {
                column = candidate;
                break;
            }
        }
    NSMutableArray *columns = [self.ys mutableCopy], *indexes = [NSMutableArray new];
    for (NSUInteger i = 0; i < columns.count; i++)
        [indexes addObject:@(i)];
    [columns addObject:column];
    [indexes addObject:@(-1)];
    [self setYColumns:columns keeping:indexes];
}
- (void)removeY:(NSUInteger)index {
    if (self.ys.count <= 1 || index >= self.ys.count)
        return;
    NSMutableArray *columns = [self.ys mutableCopy], *indexes = [NSMutableArray new];
    for (NSUInteger i = 0; i < columns.count; i++)
        if (i != index)
            [indexes addObject:@(i)];
    [columns removeObjectAtIndex:index];
    [self setYColumns:columns keeping:indexes];
}
- (NSData *)renderPanelPNG {
    CGFloat scale = self.window.backingScaleFactor;
    NSSize size = self.root.bounds.size;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:size.width * scale
                                                                       pixelsHigh:size.height * scale
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    if (!bitmap)
        return nil;
    bitmap.size = size;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [self.root drawRect:self.root.bounds];
    // Header text and each GPU plot are composited explicitly; layer-backed views are not captured by
    // cacheDisplay.
    for (NSUInteger i = 0; i < 3; i++) {
        NSButton *button = (NSButton *)self.root.subviews[i];
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, button.frame.origin.x, button.frame.origin.y);
        [button drawRect:button.bounds];
        CGContextRestoreGState(context);
    }
    for (NSTextField *label in @[ self.title, self.positionLabel ]) {
        if (label.hidden)
            continue;
        [label.stringValue drawInRect:label.frame
                       withAttributes:@{
                           NSFontAttributeName : label.font,
                           NSForegroundColorAttributeName : label.textColor
                       }];
    }
    for (PLChart *chart in self.charts) {
        NSImage *image = [chart plotImageAtScale:scale];
        if (!image) {
            [NSGraphicsContext restoreGraphicsState];
            return nil;
        }
        CGContextRef c = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, chart.frame.origin.x, chart.frame.origin.y);
        [image drawInRect:chart.plotRect];
        [chart drawAnnotationsForExport];
        CGContextRestoreGState(c);
    }
    [NSGraphicsContext restoreGraphicsState];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
- (NSData *)panelPNG {
    [self.root layoutSubtreeIfNeeded];
    __block NSData *png;
    [self.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        png = [self renderPanelPNG];
    }];
    return png;
}
- (void)saveImage {
    NSData *png = [self panelPNG];
    if (!png) {
        Alert(@"Save failed", @"Metal image rendering failed.");
        return;
    }
    NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory
                                                            inDomains:NSUserDomainMask]
                           .firstObject;
    NSString *name = [self.group.items[self.selected].name.stringByDeletingPathExtension
        stringByReplacingOccurrencesOfString:@"/"
                                  withString:@"_"];
    name = [name stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    NSURL *url =
        [downloads URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%.0f.png", name,
                                                                          NSDate.date.timeIntervalSince1970]];
    NSError *error;
    if (![png writeToURL:url options:NSDataWritingAtomic error:&error])
        Alert(@"Save failed", error.localizedDescription);
}
- (void)perform:(NSString *)action {
    if ([action isEqual:@"pin"]) {
        [self togglePin:nil];
        return;
    }
    if (!self.group)
        return;
    PLDataset *selected = self.group.items[self.selected];
    if ([action isEqual:@"copy"]) {
        if (selected.path.length) {
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard writeObjects:@[ [NSURL fileURLWithPath:selected.path] ]];
        }
    } else if ([action isEqual:@"copy-path"]) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:selected.path ?: @"" forType:NSPasteboardTypeString];
    } else if ([action isEqual:@"reveal"] && selected.path.length)
        [NSWorkspace.sharedWorkspace
            activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:selected.path] ]];
    else if ([action isEqual:@"editor"] && selected.path.length) {
        NSString *editor = [NSUserDefaults.standardUserDefaults stringForKey:@"editor"];
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
        task.arguments = editor.length ? @[ @"-a", editor, selected.path ] : @[ @"-t", selected.path ];
        NSError *error;
        if (![task launchAndReturnError:&error])
            Alert(@"Cannot open editor", error.localizedDescription);
    } else if ([action isEqual:@"filter"])
        [self showFilter];
    else if ([action isEqual:@"save-image"])
        [self saveImage];
    else if ([action isEqual:@"home"]) {
        double min = INFINITY, max = -INFINITY;
        for (PLChart *chart in self.charts) {
            chart.range = PLSeriesExtent(chart.series);
            min = fmin(min, chart.range.x);
            max = fmax(max, chart.range.x + chart.range.width);
        }
        for (PLChart *chart in self.charts) {
            Bounds b = chart.range;
            b.x = min;
            b.width = max - min;
            chart.range = b;
            [chart refresh];
        }
        [self record];
    } else if ([action isEqual:@"undo-view"] || [action isEqual:@"redo-view"]) {
        NSInteger next = self.historyIndex + ([action isEqual:@"undo-view"] ? -1 : 1);
        if (next >= 0 && next < (NSInteger)self.history.count) {
            self.historyIndex = next;
            [self applyRanges:self.history[next]];
        }
    } else if ([action isEqual:@"outliers"]) {
        NSArray *old = [self ranges];
        self.outliers = !self.outliers;
        [self rebuild];
        for (NSUInteger i = 0; i < self.charts.count; i++) {
            Bounds b = self.charts[i].range, oldB = Unbox(old[i]);
            b.x = oldB.x;
            b.width = oldB.width;
            self.charts[i].range = b;
            [self.charts[i] refresh];
        }
        [self.history removeAllObjects];
        self.historyIndex = -1;
        [self record];
    } else if ([action isEqual:@"line"] || [action isEqual:@"points"]) {
        self.points = [action isEqual:@"points"];
        for (PLChart *c in self.charts) {
            c.points = self.points;
            [c refresh];
        }
    } else if ([action isEqual:@"pan"] || [action isEqual:@"zoom"]) {
        self.pan = [action isEqual:@"pan"];
        for (PLChart *c in self.charts)
            c.pan = self.pan;
    } else if ([action isEqual:@"duplicate"]) {
        PlotController *copy = [self.app newPlot:self.group];
        copy.x = self.x;
        copy.ys = self.ys;
        copy.rules = self.rules;
        copy.points = self.points;
        copy.pan = self.pan;
        copy.outliers = self.outliers;
        copy.selected = self.selected;
        [copy rebuild];
        [copy applyRanges:[self ranges]];
        [copy.history removeAllObjects];
        copy.historyIndex = -1;
        [copy record];
        [copy.window setFrame:NSOffsetRect(self.window.frame, 28, -28) display:YES];
    }
    [self.app updateToolbar];
}
- (void)windowDidBecomeKey:(NSNotification *)n {
    if (n.object == self.window) {
        if (self.charts.count)
            [self.window makeFirstResponder:self.charts.firstObject];
        [self.app syncFocus];
        [self updateHeader];
    }
}
- (void)windowDidResignKey:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.app syncFocus];
        [self updateHeader];
    });
}
- (void)windowDidMove:(NSNotification *)n {
    // AppKit moves the attached toolbar together with its parent.
}
- (void)windowDidResize:(NSNotification *)n {
    if (n.object != self.window)
        return;
    [self layout];
    [self.root setNeedsDisplay:YES];
    if (self.app.target == self)
        [self.app placeToolbar];
}
- (void)windowWillMiniaturize:(NSNotification *)n {
    if (n.object == self.window && self.app.target == self) {
        [self.window removeChildWindow:self.app.toolbar];
        [self.app.toolbar orderOut:nil];
        self.app.target = nil;
        [self.app syncYStack];
    }
}
- (void)windowWillClose:(NSNotification *)n {
    if (n.object == self.filterPanel) {
        [self.window removeChildWindow:self.filterPanel];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.app.controllers containsObject:self] && self.window.visible &&
                !self.window.miniaturized && !NSApp.keyWindow)
                [self.window makeKeyAndOrderFront:nil];
        });
        self.filterPanel = nil;
        self.filterFields = nil;
        self.rules = @[];
        [self rebuild];
        return;
    }
    if (n.object != self.window)
        return;
    self.filterPanel.delegate = nil;
    [self.filterPanel close];
    if (self.app.target == self) {
        [self.window removeChildWindow:self.app.toolbar];
        self.app.target = nil;
        [self.app.toolbar orderOut:nil];
        [self.app syncYStack];
    }
    for (PLChart *c in self.charts)
        [c removeFromSuperview];
    [self.charts removeAllObjects];
    self.window.contentView = nil;
    [self.app.controllers removeObject:self];
}
@end

@implementation PlotApp
- (instancetype)init {
    if ((self = [super init])) {
        self.controllers = [NSMutableArray new];
        self.tools = [NSMutableDictionary new];
        self.loader = dispatch_queue_create("com.okadaharuto.plot.read", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (void)applyAppearance {
    NSString *theme = [NSUserDefaults.standardUserDefaults stringForKey:@"theme"];
    NSApp.appearance = [theme isEqual:@"dark"]    ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
                       : [theme isEqual:@"light"] ? [NSAppearance appearanceNamed:NSAppearanceNameAqua]
                                                  : nil;
    for (PlotController *c in self.controllers) {
        [c layout];
        [c.root setNeedsDisplay:YES];
        for (NSView *view in c.root.subviews)
            view.needsDisplay = YES;
        c.filterPanel.contentView.needsDisplay = YES;
    }
    self.toolbar.contentView.needsDisplay = YES;
    self.yStack.contentView.needsDisplay = YES;
    self.settings.window.contentView.needsDisplay = YES;
}
- (NSMenuItem *)menu:(NSMenu *)menu
               title:(NSString *)title
             command:(NSString *)command
                 key:(NSString *)key
           modifiers:(NSEventModifierFlags)mods {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(action:) keyEquivalent:key];
    item.target = self;
    item.representedObject = command;
    item.keyEquivalentModifierMask = mods;
    [menu addItem:item];
    return item;
}
- (void)makeMenus {
    NSEventModifierFlags cmd = NSEventModifierFlagCommand, alt = cmd | NSEventModifierFlagOption,
                         shift = cmd | NSEventModifierFlagShift;
    NSArray *definitions = @[
        @[
            @"Plot", @[ @"Settings…", @"settings", @",", @(cmd) ], @[ @"Hide Plot", @"hide", @"h", @(cmd) ],
            @[ @"Quit Plot", @"quit", @"q", @(cmd) ]
        ],
        @[
            @"File", @[ @"New Window", @"new", @"n", @(cmd) ], @[ @"Open…", @"open", @"o", @(cmd) ],
            @[ @"Duplicate Window", @"duplicate", @"d", @(shift) ],
            @[ @"Reveal in Finder", @"reveal", @"r", @(alt) ],
            @[ @"Open in Editor", @"editor", @"e", @(cmd) ],
            @[ @"Copy Absolute Path", @"copy-path", @"c", @(alt) ],
            @[ @"Save Image to Downloads", @"save-image", @"s", @(cmd) ]
        ],
        @[
            @"Edit", @[ @"Undo", @"undo-view", @"z", @(cmd) ], @[ @"Redo", @"redo-view", @"z", @(shift) ],
            @[ @"Cut", @"cut:", @"x", @(cmd) ], @[ @"Copy", @"copy", @"c", @(cmd) ],
            @[ @"Paste", @"paste:", @"v", @(cmd) ], @[ @"Select All", @"selectAll:", @"a", @(cmd) ]
        ],
        @[
            @"Tools", @[ @"Filter…", @"filter", @"f", @(alt) ],
            @[ @"Exclude Outliers", @"outliers", @"r", @(alt | NSEventModifierFlagShift) ],
            @[ @"Next X Column", @"next-x", @"x", @(cmd) ],
            @[ @"Previous X Column", @"previous-x", @"x", @(shift) ],
            @[ @"Next Y Column", @"next-y", @"y", @(cmd) ],
            @[ @"Previous Y Column", @"previous-y", @"y", @(shift) ]
        ],
        @[
            @"Window", @[ @"Close Window", @"close", @"w", @(cmd) ],
            @[ @"Minimize", @"minimize", @"m", @(cmd) ], @[ @"Always on Top", @"pin", @"t", @(alt) ],
            @[ @"Next Window", @"next", @"`", @(cmd) ], @[ @"Previous Window", @"previous", @"`", @(shift) ],
            @[ @"Tile Windows", @"arrange", @"a", @(alt) ],
            @[ @"Cascade Windows", @"cascade", @"a", @(alt | NSEventModifierFlagShift) ]
        ]
    ];
    NSMenu *bar = [NSMenu new];
    for (NSArray *definition in definitions) {
        NSMenuItem *root = [NSMenuItem new];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:definition[0]];
        for (NSUInteger i = 1; i < definition.count; i++) {
            NSArray *entry = definition[i];
            if ([entry[1] hasSuffix:@":"]) {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0]
                                                              action:NSSelectorFromString(entry[1])
                                                       keyEquivalent:entry[2]];
                item.keyEquivalentModifierMask = [entry[3] unsignedIntegerValue];
                [menu addItem:item];
            } else
                [self menu:menu
                        title:entry[0]
                      command:entry[1]
                          key:entry[2]
                    modifiers:[entry[3] unsignedIntegerValue]];
        }
        root.submenu = menu;
        [bar addItem:root];
    }
    NSApp.mainMenu = bar;
}
- (void)makeToolbar {
    self.toolbar = [[ToolbarPanel alloc] initWithContentRect:NSMakeRect(0, 0, 790, 34)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self.toolbar.delegate = self;
    self.toolbar.title = @"Plot Controls";
    self.toolbar.opaque = NO;
    self.toolbar.backgroundColor = NSColor.clearColor;
    self.toolbar.contentView = [[ToolbarSurface alloc] initWithFrame:self.toolbar.contentView.bounds];
    self.toolbar.hasShadow = NO;
    self.toolbar.releasedWhenClosed = NO;
    self.toolbar.becomesKeyOnlyIfNeeded = YES;
    NSArray *commands = @[
        @[ @"Open", @"open", @"Open files (⌘O)" ], @[ @"⌂", @"home", @"Fit all data" ],
        @[ @"‹", @"undo-view", @"Previous view" ], @[ @"›", @"redo-view", @"Next view" ],
        @[ @"Pan", @"pan", @"Pan" ], @[ @"Zoom", @"zoom", @"Box zoom" ], @[ @"Line", @"line", @"Lines" ],
        @[ @"Dots", @"points", @"Points" ], @[ @"Clean", @"outliers", @"Exclude outliers (⇧⌥⌘R)" ]
    ];
    CGFloat x = 3;
    for (NSArray *entry in commands) {
        CGFloat w = 26;
        NSButton *button = Icon(entry[1], entry[2], self, @selector(action:), NSMakeRect(x, 4, w, w));
        button.identifier = entry[1];
        button.bordered = NO;
        if ([@[ @"pan", @"zoom", @"line", @"points", @"outliers" ] containsObject:entry[1]])
            button.buttonType = NSButtonTypeToggle;
        self.tools[entry[1]] = button;
        [self.toolbar.contentView addSubview:button];
        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(x + w + 2, 8, 1, 18)];
        separator.boxType = NSBoxSeparator;
        [self.toolbar.contentView addSubview:separator];
        x += w + 6;
    }
    [self.toolbar.contentView addSubview:Label(@"X", NSMakeRect(x + 2, 7, 12, 16))];
    x += 22;
    self.xSelect = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 5, 98, 24) pullsDown:NO];
    self.xSelect.target = self;
    self.xSelect.action = @selector(action:);
    self.xSelect.identifier = @"x-select";
    self.xSelect.accessibilityLabel = @"X column";
    [self.toolbar.contentView addSubview:self.xSelect];
    x += 104;
    x += 22;
    self.yColumnX = x;
    self.yStack = [[ToolbarPanel alloc] initWithContentRect:NSMakeRect(0, 0, ToolbarYWidth, 34)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.yStack.title = @"Y Plots";
    self.yStack.delegate = self;
    self.yStack.releasedWhenClosed = NO;
    self.yStack.opaque = NO;
    self.yStack.backgroundColor = NSColor.clearColor;
    self.yStack.hasShadow = NO;
    self.yStack.becomesKeyOnlyIfNeeded = YES;
    self.yStack.contentView = [[ToolbarSurface alloc] initWithFrame:self.yStack.contentView.bounds];
    ((ToolbarSurface *)self.yStack.contentView).joinsAbove = YES;
    self.ySelects = [NSMutableArray new];
    self.yRemoves = [NSMutableArray new];
    self.yLabels = [NSMutableArray new];
    self.yAdd = Icon(@"add", @"Add Y plot", self, @selector(action:), NSMakeRect(x + 102, 4, 26, 26));
    self.yAdd.identifier = @"add-y";
    [self.toolbar.contentView addSubview:self.yAdd];
    NSRect r = self.toolbar.frame;
    r.size.width = x + 132;
    [self.toolbar setFrame:r display:NO];
    self.toolbarShadow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    self.toolbarShadow.releasedWhenClosed = NO;
    self.toolbarShadow.opaque = NO;
    self.toolbarShadow.backgroundColor = NSColor.clearColor;
    self.toolbarShadow.hasShadow = NO;
    self.toolbarShadow.ignoresMouseEvents = YES;
    self.toolbarShadow.collectionBehavior =
        NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;
    self.toolbarShadow.contentView =
        [[ToolbarShadowView alloc] initWithFrame:self.toolbarShadow.contentView.bounds];
    self.toolbarShadow.contentView.accessibilityElement = NO;
}
- (PlotController *)newPlot:(PLGroup *)group {
    PlotController *previous = self.target;
    PlotController *c = [[PlotController alloc] initWithApp:self group:group];
    [self.controllers addObject:c];
    NSRect area = (previous.window.screen ?: NSScreen.mainScreen).visibleFrame;
    NSPoint p = previous ? NSMakePoint(NSMinX(previous.window.frame) + 28, NSMaxY(previous.window.frame) - 28)
                         : NSMakePoint(NSMinX(area) + 80, NSMaxY(area) - 70);
    [c.window setFrameTopLeftPoint:p];
    [c.window makeKeyAndOrderFront:nil];
    [self syncFocus];
    return c;
}
- (void)placeToolbar {
    PlotController *c = self.target;
    if (!c)
        return;
    NSRect r = self.toolbar.frame;
    r.origin = NSMakePoint(NSMinX(c.window.frame), NSMinY(c.window.frame) - r.size.height - 6);
    if (!NSEqualRects(r, self.toolbar.frame))
        [self.toolbar setFrame:r display:YES];
    self.toolbar.level = c.window.level;
    self.yStack.level = c.window.level;
    NSRect stack = self.yStack.frame;
    stack.origin = NSMakePoint(NSMinX(r) + self.yColumnX - ToolbarYInset, NSMinY(r) - stack.size.height);
    if (!NSEqualRects(stack, self.yStack.frame))
        [self.yStack setFrame:stack display:YES];
    [self layoutToolbarShadow];
}
- (void)layoutToolbarShadow {
    if (!self.target || !self.toolbarShadow)
        return;
    BOOL hasStack = self.ySelects.count > 1;
    NSRect main = self.toolbar.frame, stack = hasStack ? self.yStack.frame : NSZeroRect;
    NSRect frame =
        NSInsetRect(hasStack ? NSUnionRect(main, stack) : main, -ToolbarShadowMargin, -ToolbarShadowMargin);
    if (!NSEqualRects(frame, self.toolbarShadow.frame))
        [self.toolbarShadow setFrame:frame display:NO];
    self.toolbarShadow.level = self.toolbar.level;
    main = NSOffsetRect(main, -frame.origin.x, -frame.origin.y);
    if (hasStack)
        stack = NSOffsetRect(stack, -frame.origin.x, -frame.origin.y);
    [(ToolbarShadowView *)self.toolbarShadow.contentView configureMain:main stack:stack hasStack:hasStack];
}
- (void)syncToolbarShadow {
    if (self.target && NSApp.isActive && self.toolbar.visible &&
        self.toolbar.parentWindow == self.target.window) {
        if (self.toolbarShadow.parentWindow != self.toolbar)
            [self.toolbar addChildWindow:self.toolbarShadow ordered:NSWindowBelow];
        if (!self.toolbarShadow.visible)
            [self.toolbarShadow orderWindow:NSWindowBelow relativeTo:self.toolbar.windowNumber];
    } else {
        [self.toolbarShadow.parentWindow removeChildWindow:self.toolbarShadow];
        [self.toolbarShadow orderOut:nil];
    }
}
- (void)syncFocus {
    NSWindow *key = NSApp.keyWindow;
    PlotController *active = nil;
    if (NSApp.isActive) {
        if (key == self.toolbar || key == self.yStack)
            active = self.target;
        else
            for (PlotController *c in self.controllers)
                if (c.window == key && !c.window.miniaturized) {
                    active = c;
                    break;
                }
    }
    if (active != self.target) {
        [self.toolbar.parentWindow removeChildWindow:self.toolbar];
        [self.toolbar orderOut:nil];
        PlotController *previous = self.target;
        self.target = active;
        [previous updateHeader];
        [active updateHeader];
    }
    if (!active) {
        [self.toolbar.parentWindow removeChildWindow:self.toolbar];
        [self.toolbar orderOut:nil];
        [self syncToolbarShadow];
        return;
    }
    [self updateToolbar];
    if (self.toolbar.parentWindow != active.window) {
        [self placeToolbar];
        [active.window addChildWindow:self.toolbar ordered:NSWindowAbove];
        [self.toolbar orderFront:nil];
    }
    [self syncYStack];
}
- (void)syncYStack {
    if (self.ySelects.count > 1 && self.target && NSApp.isActive &&
        self.toolbar.parentWindow == self.target.window) {
        if (self.yStack.parentWindow != self.toolbar)
            [self.toolbar addChildWindow:self.yStack ordered:NSWindowAbove];
        if (!self.yStack.visible)
            [self.yStack orderFront:nil];
    } else {
        PlotController *owner = self.target;
        BOOL restoreFocus = self.ySelects.count <= 1 && self.yStack.keyWindow && owner && NSApp.isActive;
        [self.yStack.parentWindow removeChildWindow:self.yStack];
        [self.yStack orderOut:nil];
        if (restoreFocus && owner.window.visible)
            [owner.window makeKeyWindow];
    }
    [self layoutToolbarShadow];
    [self syncToolbarShadow];
}
- (void)updateToolbar {
    PlotController *c = self.target;
    BOOL loaded = c.group != nil;
    for (NSString *command in self.tools) {
        NSButton *b = self.tools[command];
        b.enabled = loaded || [command isEqual:@"open"];
    }
    self.tools[@"pan"].state = c.pan;
    self.tools[@"zoom"].state = !c.pan;
    self.tools[@"line"].state = !c.points;
    self.tools[@"points"].state = c.points;
    self.tools[@"outliers"].state = c.outliers;
    self.tools[@"undo-view"].enabled = loaded && c.historyIndex > 0;
    self.tools[@"redo-view"].enabled = loaded && c.historyIndex + 1 < (NSInteger)c.history.count;
    self.xSelect.enabled = self.yAdd.enabled = loaded;
    NSArray *titles = c.group.columns ?: @[];
    if (![self.xSelect.itemTitles isEqual:titles]) {
        [self.xSelect removeAllItems];
        [self.xSelect addItemsWithTitles:titles];
    }
    [self.xSelect selectItemWithTitle:c.x ?: @""];
    NSUInteger count = MAX(1ul, c.ys.count);
    while (self.ySelects.count > count) {
        [self.ySelects.lastObject removeFromSuperview];
        [self.yRemoves.lastObject removeFromSuperview];
        [self.yLabels.lastObject removeFromSuperview];
        [self.ySelects removeLastObject];
        [self.yRemoves removeLastObject];
        [self.yLabels removeLastObject];
    }
    while (self.ySelects.count < count) {
        NSPopUpButton *select = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        select.target = self;
        select.action = @selector(action:);
        select.identifier = @"y-select";
        [self.ySelects addObject:select];
        [(self.ySelects.count == 1 ? self.toolbar.contentView : self.yStack.contentView) addSubview:select];
        NSButton *remove = Icon(@"remove", @"Remove Y plot", self, @selector(action:), NSZeroRect);
        remove.identifier = @"remove-y";
        [self.yRemoves addObject:remove];
        [(self.yRemoves.count == 1 ? self.toolbar.contentView : self.yStack.contentView) addSubview:remove];
        NSTextField *label = Label(@"Y", NSZeroRect);
        [self.yLabels addObject:label];
        [(self.yLabels.count == 1 ? self.toolbar.contentView : self.yStack.contentView) addSubview:label];
    }
    ToolbarSurface *surface = (ToolbarSurface *)self.toolbar.contentView;
    surface.joinsBelow = count > 1;
    surface.joinX = self.yColumnX - ToolbarYInset;
    CGFloat height = MAX(32, (count - 1) * 32);
    if (self.yStack.frame.size.height != height)
        [self.yStack setContentSize:NSMakeSize(ToolbarYWidth, height)];
    for (NSUInteger i = 0; i < count; i++) {
        NSPopUpButton *select = self.ySelects[i];
        if (![select.itemTitles isEqual:titles]) {
            [select removeAllItems];
            [select addItemsWithTitles:titles];
        }
        select.tag = i;
        select.accessibilityLabel = [NSString stringWithFormat:@"Y column %lu", i + 1];
        select.enabled = loaded;
        [select selectItemWithTitle:loaded ? c.ys[i] : @""];
        CGFloat y = i == 0 ? 5 : height - 27 - (i - 1) * 32;
        CGFloat x = i == 0 ? self.yColumnX : ToolbarYInset;
        select.frame = NSMakeRect(x, y, 98, 24);
        self.yLabels[i].frame = NSMakeRect(x - 20, y + 2, 12, 16);
        NSButton *remove = self.yRemoves[i];
        remove.tag = i;
        remove.hidden = i == 0;
        remove.frame = NSMakeRect(x + 102, y - 1, 26, 26);
        remove.enabled = loaded;
    }
    self.ySelect = self.ySelects.firstObject;
    self.yAdd.frame = NSMakeRect(self.yColumnX + 102, 4, 26, 26);
    [self placeToolbar];
    self.toolbar.contentView.needsDisplay = YES;
    self.yStack.contentView.needsDisplay = YES;
    [self syncYStack];
}
- (void)openPaths:(NSArray<NSString *> *)paths reply:(BOOL)reply {
    dispatch_async(self.loader, ^{
        @autoreleasepool {
            NSMutableArray *errors = [NSMutableArray new];
            NSArray *groups = PLReadGroups(paths, errors);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *empty = [NSMutableArray new];
                for (PlotController *c in self.controllers)
                    if (!c.group)
                        [empty addObject:c];
                for (PLGroup *g in groups)
                    [self newPlot:g];
                if (groups.count)
                    for (PlotController *c in empty)
                        [c.window close];
                if (errors.count)
                    Alert(@"Some files could not be opened", [errors componentsJoinedByString:@"\n"]);
                if (reply)
                    [NSApp replyToOpenOrPrint:errors.count ? NSApplicationDelegateReplyFailure
                                                           : NSApplicationDelegateReplySuccess];
            });
        }
    });
}
- (void)showSettings {
    if (!self.settings) {
        NSWindow *window = MakePanel(@"Settings", NSMakeSize(360, 130));
        self.settings = [[NSWindowController alloc] initWithWindow:window];
        NSView *v = window.contentView;
        [v addSubview:Label(@"Theme", NSMakeRect(16, 88, 85, 16))];
        NSPopUpButton *theme = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 82, 230, 28)
                                                          pullsDown:NO];
        [theme addItemsWithTitles:@[ @"System", @"Light", @"Dark" ]];
        NSString *pref = [NSUserDefaults.standardUserDefaults stringForKey:@"theme"] ?: @"system";
        [theme selectItemAtIndex:[pref isEqual:@"dark"] ? 2 : [pref isEqual:@"light"] ? 1 : 0];
        theme.identifier = @"theme";
        theme.target = self;
        theme.action = @selector(settingChanged:);
        [v addSubview:theme];
        [v addSubview:Label(@"Editor", NSMakeRect(16, 45, 85, 16))];
        NSTextField *editor =
            Input([NSUserDefaults.standardUserDefaults stringForKey:@"editor"], NSMakeRect(110, 40, 230, 24));
        editor.placeholderString = @"Default text editor";
        editor.target = self;
        editor.action = @selector(settingChanged:);
        editor.identifier = @"editor";
        [v addSubview:editor];
        [v addSubview:Label(@"Enter an app name; press Return to save.", NSMakeRect(110, 13, 240, 20))];
        [window center];
    }
    [self.settings showWindow:nil];
    [self.settings.window makeKeyAndOrderFront:nil];
    [self syncFocus];
}
- (void)settingChanged:(id)sender {
    if ([[sender identifier] isEqual:@"theme"]) {
        [NSUserDefaults.standardUserDefaults
            setObject:@[ @"system", @"light", @"dark" ][[sender indexOfSelectedItem]]
               forKey:@"theme"];
        [self applyAppearance];
    } else
        [NSUserDefaults.standardUserDefaults setObject:[sender stringValue] forKey:@"editor"];
}
- (void)action:(id)sender {
    NSString *action =
        [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : [sender identifier];
    PlotController *c = self.target;
    for (PlotController *owner in self.controllers)
        if (NSApp.keyWindow == owner.window || NSApp.keyWindow == owner.filterPanel)
            c = owner;
    NSResponder *responder = NSApp.keyWindow.firstResponder;
    if ([responder isKindOfClass:NSTextView.class] &&
        [@[ @"copy", @"undo-view", @"redo-view" ] containsObject:action]) {
        SEL sel = NSSelectorFromString([action isEqual:@"copy"]        ? @"copy:"
                                       : [action isEqual:@"undo-view"] ? @"undo:"
                                                                       : @"redo:");
        [NSApp sendAction:sel to:responder from:sender];
        return;
    }
    if ([action isEqual:@"quit"])
        [NSApp terminate:nil];
    else if ([action isEqual:@"hide"])
        [NSApp hide:nil];
    else if ([action isEqual:@"new"])
        [self newPlot:nil];
    else if ([action isEqual:@"close"])
        [((NSApp.keyWindow == self.toolbar || NSApp.keyWindow == self.yStack) ? c.window : NSApp.keyWindow)
            close];
    else if ([action isEqual:@"minimize"])
        [((NSApp.keyWindow == self.toolbar || NSApp.keyWindow == self.yStack) ? c.window : NSApp.keyWindow)
            miniaturize:nil];
    else if ([action isEqual:@"settings"])
        [self showSettings];
    else if ([action isEqual:@"open"]) {
        NSOpenPanel *panel = NSOpenPanel.openPanel;
        panel.allowsMultipleSelection = YES;
        panel.canChooseDirectories = NO;
        panel.allowedContentTypes = @[
            [UTType typeWithFilenameExtension:@"csv"], [UTType typeWithFilenameExtension:@"dat"],
            [UTType typeWithFilenameExtension:@"txt"], [UTType typeWithFilenameExtension:@"ras"]
        ];
        [panel beginWithCompletionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK)
                [self openPaths:[panel.URLs valueForKey:@"path"] reply:NO];
        }];
    } else if ([@[ @"next-x", @"previous-x", @"next-y", @"previous-y" ] containsObject:action])
        [c cycle:[action hasSuffix:@"-x"] backwards:[action hasPrefix:@"previous"]];
    else if ([action isEqual:@"add-y"])
        [c addY];
    else if ([action isEqual:@"remove-y"])
        [c removeY:[sender tag]];
    else if ([action isEqual:@"y-select"]) {
        NSUInteger index = [sender tag];
        if (index >= c.ys.count)
            return;
        NSMutableArray *columns = [c.ys mutableCopy], *indexes = [NSMutableArray new];
        for (NSUInteger i = 0; i < columns.count; i++)
            [indexes addObject:i == index ? @(-1) : @(i)];
        columns[index] = [sender titleOfSelectedItem];
        [c setYColumns:columns keeping:indexes];
    } else if ([action isEqual:@"x-select"]) {
        NSArray *before = [c ranges];
        c.x = self.xSelect.titleOfSelectedItem;
        [c rebuild];
        for (NSUInteger i = 0; i < c.charts.count; i++) {
            Bounds b = c.charts[i].range, old = Unbox(before[i]);
            b.y = old.y;
            b.height = old.height;
            c.charts[i].range = b;
            [c.charts[i] refresh];
        }
        [c.history removeAllObjects];
        c.historyIndex = -1;
        [c record];
    } else if ([action isEqual:@"next"] || [action isEqual:@"previous"]) {
        if (!self.controllers.count)
            return;
        NSUInteger i = [self.controllers indexOfObject:c];
        if (i == NSNotFound)
            i = 0;
        i = (i + self.controllers.count + ([action isEqual:@"next"] ? 1 : -1)) % self.controllers.count;
        [self.controllers[i].window makeKeyAndOrderFront:nil];
    } else if ([action isEqual:@"arrange"] || [action isEqual:@"cascade"]) {
        NSRect area = (c.window.screen ?: NSScreen.mainScreen).visibleFrame;
        CGFloat x = area.origin.x + 12, y = NSMaxY(area) - 12, row = 0;
        for (PlotController *p in self.controllers) {
            NSSize size = p.window.frame.size;
            if ([action isEqual:@"arrange"] && x + size.width > NSMaxX(area) && x > area.origin.x + 12) {
                x = area.origin.x + 12;
                y -= row + 12;
                row = 0;
            }
            [p.window setFrameTopLeftPoint:NSMakePoint(x, y)];
            if ([action isEqual:@"cascade"]) {
                x += 28;
                y -= 28;
            } else {
                x += size.width + 12;
                row = MAX(row, size.height);
            }
        }
    } else if ([action isEqual:@"save-image"] && NSApp.keyWindow == c.filterPanel)
        [c saveCSV:nil];
    else
        [c perform:action];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    NSString *a = item.representedObject;
    if (!a)
        return YES;
    if ([@[ @"quit", @"hide", @"settings", @"open", @"new" ] containsObject:a])
        return YES;
    PlotController *c = self.target;
    BOOL loaded = c.group != nil;
    if ([a isEqual:@"copy"] && [NSApp.keyWindow.firstResponder isKindOfClass:NSTextView.class])
        return YES;
    if ([a isEqual:@"close"] || [a isEqual:@"minimize"])
        return NSApp.keyWindow != nil;
    if ([a isEqual:@"undo-view"])
        return [NSApp.keyWindow.firstResponder isKindOfClass:NSTextView.class] || c.historyIndex > 0;
    if ([a isEqual:@"redo-view"])
        return [NSApp.keyWindow.firstResponder isKindOfClass:NSTextView.class] ||
               c.historyIndex + 1 < (NSInteger)c.history.count;
    if ([a isEqual:@"pin"])
        item.state = c.window.level == NSFloatingWindowLevel;
    if ([a isEqual:@"outliers"])
        item.state = c.outliers;
    return loaded || [@[ @"pin", @"next", @"previous", @"arrange", @"cascade" ] containsObject:a];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try {
        self.renderer = [Renderer new];
    } @catch (NSException *e) {
        Alert(@"Metal could not start", e.reason);
        [NSApp terminate:nil];
        return;
    }
    [self applyAppearance];
    [self makeMenus];
    [self makeToolbar];
    if (!self.controllers.count)
        [self newPlot:nil];
    if (self.initialPaths.count)
        [self openPaths:self.initialPaths reply:NO];
    if (self.syntheticCount) {
        dispatch_async(self.loader, ^{
            @autoreleasepool {
                NSMutableArray *groups = [NSMutableArray new];
                for (NSUInteger j = 0; j < self.syntheticWindows; j++) {
                    NSMutableData *values =
                        [NSMutableData dataWithLength:self.syntheticCount * 2 * sizeof(double)];
                    double *v = values.mutableBytes;
                    for (NSUInteger i = 0; i < self.syntheticCount; i++) {
                        double x = (double)i / MAX(1ul, self.syntheticCount - 1) * 100;
                        v[i * 2] = x;
                        v[i * 2 + 1] = sin(x * .25 + j * .1) + .05 * sin(x * 11);
                    }
                    PLDataset *d = [PLDataset new];
                    d.columns = @[ @"X", @"Y" ];
                    d.defaultX = @"X";
                    d.defaultY = @"Y";
                    d.name =
                        [NSString stringWithFormat:@"Synthetic %lu (%lu points)", j + 1, self.syntheticCount];
                    d.values = values;
                    PLGroup *g = [PLGroup new];
                    g.columns = d.columns;
                    g.x = @"X";
                    g.y = @"Y";
                    g.items = @[ d ];
                    [groups addObject:g];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    for (PLGroup *g in groups)
                        [self newPlot:g];
                    for (PlotController *c in [self.controllers copy])
                        if (!c.group)
                            [c.window close];
                });
            }
        });
    }
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames {
    // Finder may deliver files before applicationDidFinishLaunching; defer native window creation until Metal
    // is ready.
    if (!self.renderer) {
        self.initialPaths = [(self.initialPaths ?: @[]) arrayByAddingObjectsFromArray:filenames];
        [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    } else
        [self openPaths:filenames reply:YES];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (!visible)
        [self newPlot:nil];
    return YES;
}
- (void)applicationDidBecomeActive:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncFocus];
    });
}
- (void)applicationDidResignActive:(NSNotification *)n {
    [self syncFocus];
    for (PlotController *c in self.controllers)
        [c updateHeader];
}
- (void)windowDidBecomeKey:(NSNotification *)n {
    [self syncFocus];
}
- (void)windowDidResignKey:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncFocus];
    });
}
@end

#ifndef PLOT_TESTING
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        PlotApp *app = [PlotApp new];
        NSMutableArray *paths = [NSMutableArray new];
        app.syntheticWindows = 1;
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqual:@"--synthetic"] && i + 1 < argc)
                app.syntheticCount = MAX(1, [@(argv[++i]) integerValue]);
            else if ([arg isEqual:@"--windows"] && i + 1 < argc)
                app.syntheticWindows = MAX(1, [@(argv[++i]) integerValue]);
            else if (![arg hasPrefix:@"-"])
                [paths addObject:arg];
        }
        if (app.syntheticCount > 10000000 || app.syntheticWindows > 32) {
            fprintf(stderr, "Synthetic preview limits: 10 million points, 32 windows\n");
            return 1;
        }
        app.initialPaths = paths;
        NSApp.delegate = app;
        [NSApp run];
    }
    return 0;
}

#endif
