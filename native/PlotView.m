#import "PlotView.h"
#include <float.h>

Bounds PLSeriesExtent(NSArray<Series *> *series) {
    double x = DBL_MAX, y = DBL_MAX, xx = -DBL_MAX, yy = -DBL_MAX;
    for (Series *s in series) {
        x = fmin(x, s.xMin);
        y = fmin(y, s.yMin);
        xx = fmax(xx, s.xMax);
        yy = fmax(yy, s.yMax);
    }
    if (x == DBL_MAX)
        return (Bounds){-1, -1, 2, 2};
    return (Bounds){x - (xx - x) * .02, y - (yy - y) * .05, (xx - x) * 1.04, (yy - y) * 1.1};
}
@class PLChart;
@interface PLAnnotation : NSView
@property(nonatomic, weak) PLChart *chart;
@end
@implementation PLAnnotation
- (BOOL)isOpaque {
    return NO;
}
- (NSView *)hitTest:(NSPoint)p {
    return nil;
}
- (void)drawRect:(NSRect)dirty {
    [self.chart drawAnnotations];
}
@end
@interface PLChart ()
@property(nonatomic) MTKView *metal;
@property(nonatomic) PLAnnotation *annotation;
@property(nonatomic) NSPoint dragStart, dragCurrent;
@property(nonatomic) Bounds dragRange;
@property(nonatomic) BOOL dragging;
@property(nonatomic) NSTimer *wheelTimer, *hoverTimer;
@property(nonatomic) NSTrackingArea *tracking;
@property(nonatomic) NSString *hoverText;
@property(nonatomic) NSPoint hoverPoint;
@property(nonatomic) NSUInteger hoverGeneration;
@end
@implementation PLChart
- (instancetype)initWithRenderer:(Renderer *)renderer {
    if (!(self = [super initWithFrame:NSZeroRect]))
        return nil;
    self.renderer = renderer;
    self.series = @[];
    self.xName = @"X";
    self.yName = @"Y";
    self.range = (Bounds){-1, -1, 2, 2};
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.whiteColor.CGColor;
    self.metal = [[MTKView alloc] initWithFrame:NSZeroRect device:renderer.device];
    self.metal.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metal.sampleCount = 4;
    self.metal.clearColor = MTLClearColorMake(1, 1, 1, 1);
    self.metal.paused = YES;
    self.metal.enableSetNeedsDisplay = YES;
    self.metal.delegate = self;
    [self addSubview:self.metal];
    self.annotation = [PLAnnotation new];
    self.annotation.chart = self;
    [self addSubview:self.annotation];
    return self;
}
- (void)dealloc {
    [self.wheelTimer invalidate];
    [self.hoverTimer invalidate];
    self.metal.delegate = nil;
}
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (NSRect)plotRect {
    return NSMakeRect(58, 38, MAX(1, self.bounds.size.width - 76), MAX(1, self.bounds.size.height - 52));
}
- (void)layout {
    [super layout];
    self.metal.frame = self.plotRect;
    self.annotation.frame = self.bounds;
    [self refresh];
}
- (void)refresh {
    self.hoverGeneration++;
    self.hoverText = nil;
    [self.hoverTimer invalidate];
    [self.metal setNeedsDisplay:YES];
    [self.annotation setNeedsDisplay:YES];
    self.annotation.accessibilityElement = YES;
    self.annotation.accessibilityRole = NSAccessibilityImageRole;
    self.annotation.accessibilityLabel =
        [NSString stringWithFormat:@"%@ vs %@, %lu datasets, %@", self.yName, self.xName, self.series.count,
                                   self.points ? @"points" : @"lines"];
}
static double TickStep(double span, NSUInteger count) {
    double raw = span / MAX(2ul, count);
    double power = pow(10, floor(log10(raw))), t = raw / power;
    return (t <= 1 ? 1 : t <= 2 ? 2 : t <= 2.5 ? 2.5 : t <= 5 ? 5 : 10) * power;
}
static NSString *TickLabel(double value, double step, double origin) {
    double v = value - origin;
    if (fabs(v) < fabs(step) * 1e-7)
        v = 0;
    return [NSString stringWithFormat:@"%.6g", v];
}
- (void)drawAnnotations {
    NSRect r = self.plotRect;
    Bounds b = self.range;
    CGContextRef c = NSGraphicsContext.currentContext.CGContext;
    NSDictionary *font = @{
        NSFontAttributeName : [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName : NSColor.blackColor
    };
    CGContextSetRGBStrokeColor(c, .08, .08, .08, 1);
    CGContextSetLineWidth(c, .7);
    CGContextStrokeRect(c, NSRectToCGRect(r));
    double sx = TickStep(b.width, (NSUInteger)(r.size.width / 65)),
           sy = TickStep(b.height, (NSUInteger)(r.size.height / 40));
    double ox = fabs(b.x) > fabs(b.width) * 10000 ? b.x : 0,
           oy = fabs(b.y) > fabs(b.height) * 10000 ? b.y : 0;
    if (isfinite(sx) && sx > 0)
        for (double v = ceil(b.x / sx) * sx, prev = -INFINITY; v <= b.x + b.width + sx * 1e-8 && v > prev;
             prev = v, v += sx) {
            CGFloat x = r.origin.x + (v - b.x) / b.width * r.size.width;
            CGContextMoveToPoint(c, x, r.origin.y);
            CGContextAddLineToPoint(c, x, r.origin.y + 4);
            CGContextMoveToPoint(c, x, NSMaxY(r));
            CGContextAddLineToPoint(c, x, NSMaxY(r) - 4);
            NSString *s = TickLabel(v, sx, ox);
            NSSize size = [s sizeWithAttributes:font];
            [s drawAtPoint:NSMakePoint(x - size.width / 2, r.origin.y - 15) withAttributes:font];
        }
    if (isfinite(sy) && sy > 0)
        for (double v = ceil(b.y / sy) * sy, prev = -INFINITY; v <= b.y + b.height + sy * 1e-8 && v > prev;
             prev = v, v += sy) {
            CGFloat y = r.origin.y + (v - b.y) / b.height * r.size.height;
            CGContextMoveToPoint(c, r.origin.x, y);
            CGContextAddLineToPoint(c, r.origin.x + 4, y);
            CGContextMoveToPoint(c, NSMaxX(r), y);
            CGContextAddLineToPoint(c, NSMaxX(r) - 4, y);
            NSString *s = TickLabel(v, sy, oy);
            NSSize size = [s sizeWithAttributes:font];
            [s drawAtPoint:NSMakePoint(r.origin.x - size.width - 5, y - 6) withAttributes:font];
        }
    CGContextStrokePath(c);
    NSString *x = ox ? [NSString stringWithFormat:@"%@ (offset %.12g)", self.xName, ox] : self.xName;
    NSSize xs = [x sizeWithAttributes:font];
    [x drawAtPoint:NSMakePoint(r.origin.x + (r.size.width - xs.width) / 2, 3) withAttributes:font];
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 12, r.origin.y + r.size.height / 2);
    CGContextRotateCTM(c, M_PI_2);
    NSString *y = oy ? [NSString stringWithFormat:@"%@ (offset %.12g)", self.yName, oy] : self.yName;
    NSSize ys = [y sizeWithAttributes:font];
    [y drawAtPoint:NSMakePoint(-ys.width / 2, 0) withAttributes:font];
    CGContextRestoreGState(c);
    if (self.hoverText.length) {
        NSSize size = [self.hoverText sizeWithAttributes:font];
        NSRect box =
            NSMakeRect(fmax(2, fmin(self.bounds.size.width - size.width - 10, self.hoverPoint.x + 10)),
                       fmax(2, fmin(self.bounds.size.height - size.height - 10, self.hoverPoint.y + 10)),
                       size.width + 8, size.height + 6);
        [[NSColor.whiteColor colorWithAlphaComponent:.95] setFill];
        NSRectFill(box);
        [NSColor.grayColor setFill];
        NSFrameRect(box);
        [self.hoverText drawAtPoint:NSMakePoint(box.origin.x + 4, box.origin.y + 3) withAttributes:font];
    }
    if (self.dragging && !self.pan) {
        NSRect box = NSMakeRect(
            fmin(self.dragStart.x, self.dragCurrent.x), fmin(self.dragStart.y, self.dragCurrent.y),
            fabs(self.dragStart.x - self.dragCurrent.x), fabs(self.dragStart.y - self.dragCurrent.y));
        [[NSColor.selectedControlColor colorWithAlphaComponent:.15] setFill];
        NSRectFillUsingOperation(NSIntersectionRect(box, r), NSCompositingOperationSourceOver);
    }
}
- (void)drawInMTKView:(MTKView *)view {
    if (!view.currentRenderPassDescriptor || !view.currentDrawable)
        return;
    Viewport v = {.pixels = {view.drawableSize.width, view.drawableSize.height},
                  .width = self.window.backingScaleFactor ?: 1};
    id<MTLCommandBuffer> command = [self.renderer encode:view.currentRenderPassDescriptor
                                                  series:self.series
                                                selected:self.selected
                                                  bounds:self.range
                                                viewport:v
                                                  points:self.points
                                                drawable:view.currentDrawable];
    [command addCompletedHandler:^(id<MTLCommandBuffer> done) {
        if (done.error)
            NSLog(@"Metal: %@", done.error);
    }];
    [command commit];
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}
- (void)viewDidMoveToWindow {
    [self.window setAcceptsMouseMovedEvents:YES];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.tracking)
        [self removeTrackingArea:self.tracking];
    self.tracking =
        [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                     options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                             NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                       owner:self
                                    userInfo:nil];
    [self addTrackingArea:self.tracking];
}
- (void)mouseExited:(NSEvent *)event {
    self.hoverGeneration++;
    [self.hoverTimer invalidate];
    self.hoverText = nil;
    [self.annotation setNeedsDisplay:YES];
}
- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect r = self.plotRect;
    if (!NSPointInRect(point, r)) {
        [self mouseExited:event];
        return;
    }
    [self.hoverTimer invalidate];
    NSUInteger generation = ++self.hoverGeneration;
    self.hoverPoint = point;
    __weak PLChart *weak = self;
    self.hoverTimer = [NSTimer
        scheduledTimerWithTimeInterval:.08
                               repeats:NO
                                 block:^(NSTimer *timer) {
                                     PLChart *chart = weak;
                                     if (!chart)
                                         return;
                                     NSArray<Series *> *series = chart.series;
                                     Bounds b = chart.range;
                                     NSUInteger selected = chart.selected;
                                     double targetX = b.x + (point.x - r.origin.x) / r.size.width * b.width,
                                            targetY = b.y + (point.y - r.origin.y) / r.size.height * b.height;
                                     dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                                         double best = 100, bestX = 0, bestY = 0;
                                         NSString *name = nil;
                                         for (NSUInteger j = 0; j < series.count; j++) {
                                             Series *s = series[(selected + j) % series.count];
                                             const XY *xy = s.raw.bytes;
                                             NSUInteger count = s.raw.length / sizeof(XY);
                                             for (NSUInteger i = 0; i < count; i++) {
                                                 double dx = (xy[i].x - targetX) / b.width * r.size.width;
                                                 if (!isfinite(dx) || fabs(dx) > 10)
                                                     continue;
                                                 double dy = (xy[i].y - targetY) / b.height * r.size.height,
                                                        dist = dx * dx + dy * dy;
                                                 if (isfinite(dist) && dist < best) {
                                                     best = dist;
                                                     bestX = xy[i].x;
                                                     bestY = xy[i].y;
                                                     name = s.name;
                                                 }
                                             }
                                         }
                                         NSString *text =
                                             name ? [NSString stringWithFormat:@"%.12g, %.12g — %@", bestX,
                                                                               bestY, name]
                                                  : nil;
                                         dispatch_async(dispatch_get_main_queue(), ^{
                                             PLChart *current = weak;
                                             if (current && current.hoverGeneration == generation) {
                                                 current.hoverText = text;
                                                 [current.annotation setNeedsDisplay:YES];
                                             }
                                         });
                                     });
                                 }];
}
- (void)keyDown:(NSEvent *)e {
    if (!(e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                             NSEventModifierFlagOption | NSEventModifierFlagShift))) {
        if (e.keyCode == 123 || e.keyCode == 126) {
            if (self.selectDataset)
                self.selectDataset(-1);
            return;
        }
        if (e.keyCode == 124 || e.keyCode == 125) {
            if (self.selectDataset)
                self.selectDataset(1);
            return;
        }
    }
    [super keyDown:e];
}
- (void)otherMouseDown:(NSEvent *)e {
    if ((e.buttonNumber == 3 || e.buttonNumber == 4) && self.navigate)
        self.navigate(e.buttonNumber == 4);
    else
        [super otherMouseDown:e];
}
- (void)mouseDown:(NSEvent *)e {
    [self.window makeFirstResponder:self];
    self.dragStart = [self convertPoint:e.locationInWindow fromView:nil];
    self.dragCurrent = self.dragStart;
    self.dragRange = self.range;
    self.dragging = NSPointInRect(self.dragStart, self.plotRect);
}
- (void)mouseDragged:(NSEvent *)e {
    if (!self.dragging)
        return;
    self.dragCurrent = [self convertPoint:e.locationInWindow fromView:nil];
    if (self.pan) {
        Bounds b = self.dragRange;
        NSRect r = self.plotRect;
        b.x -= (self.dragCurrent.x - self.dragStart.x) / r.size.width * b.width;
        b.y -= (self.dragCurrent.y - self.dragStart.y) / r.size.height * b.height;
        self.range = b;
        if (self.changed)
            self.changed(self, NO);
    }
    [self refresh];
}
- (void)mouseUp:(NSEvent *)e {
    if (!self.dragging)
        return;
    self.dragging = NO;
    if (!self.pan) {
        NSRect r = self.plotRect;
        NSPoint a = self.dragStart, z = self.dragCurrent;
        a.x = fmax(NSMinX(r), fmin(NSMaxX(r), a.x));
        z.x = fmax(NSMinX(r), fmin(NSMaxX(r), z.x));
        a.y = fmax(NSMinY(r), fmin(NSMaxY(r), a.y));
        z.y = fmax(NSMinY(r), fmin(NSMaxY(r), z.y));
        if (fabs(a.x - z.x) > 4 && fabs(a.y - z.y) > 4) {
            Bounds b = self.dragRange;
            b.x += (fmin(a.x, z.x) - r.origin.x) / r.size.width * b.width;
            b.y += (fmin(a.y, z.y) - r.origin.y) / r.size.height * b.height;
            b.width *= fabs(a.x - z.x) / r.size.width;
            b.height *= fabs(a.y - z.y) / r.size.height;
            self.range = b;
        }
    }
    if (self.changed)
        self.changed(self, YES);
    [self refresh];
}
- (void)scrollWheel:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSRect r = self.plotRect;
    if (!NSPointInRect(p, r))
        return;
    Bounds b = self.range;
    double factor = exp(fmax(-.7, fmin(.7, e.scrollingDeltaY * .01)));
    double tx = (p.x - r.origin.x) / r.size.width, ty = (p.y - r.origin.y) / r.size.height;
    double w = b.width * factor, h = b.height * factor;
    if (!isfinite(w) || !isfinite(h) || w <= fabs(b.x) * DBL_EPSILON * 8 || h <= fabs(b.y) * DBL_EPSILON * 8)
        return;
    b.x += tx * b.width * (1 - factor);
    b.y += ty * b.height * (1 - factor);
    b.width = w;
    b.height = h;
    self.range = b;
    if (self.changed)
        self.changed(self, NO);
    [self refresh];
    [self.wheelTimer invalidate];
    __weak PLChart *weak = self;
    self.wheelTimer = [NSTimer scheduledTimerWithTimeInterval:.25
                                                      repeats:NO
                                                        block:^(NSTimer *timer) {
                                                            PLChart *chart = weak;
                                                            if (chart.changed)
                                                                chart.changed(chart, YES);
                                                        }];
}
- (NSImage *)plotImageAtScale:(CGFloat)scale {
    NSRect r = self.plotRect;
    NSUInteger w = MAX(1, (NSUInteger)(r.size.width * scale)),
               h = MAX(1, (NSUInteger)(r.size.height * scale));
    MTLTextureDescriptor *d =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:w
                                                          height:h
                                                       mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget;
    d.storageMode = MTLStorageModePrivate;
    id<MTLTexture> output = [self.renderer.device newTextureWithDescriptor:d];
    d.textureType = MTLTextureType2DMultisample;
    d.sampleCount = 4;
    id<MTLTexture> msaa = [self.renderer.device newTextureWithDescriptor:d];
    if (!output || !msaa)
        return nil;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = msaa;
    pass.colorAttachments[0].resolveTexture = output;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1);
    Viewport v = {.pixels = {w, h}, .width = scale};
    id<MTLCommandBuffer> cmd = [self.renderer encode:pass
                                              series:self.series
                                            selected:self.selected
                                              bounds:self.range
                                            viewport:v
                                              points:self.points
                                            drawable:nil];
    NSUInteger row = ((w * 4 + 255) / 256) * 256;
    id<MTLBuffer> read = [self.renderer.device newBufferWithLength:row * h
                                                           options:MTLResourceStorageModeShared];
    if (!read)
        return nil;
    id<MTLBlitCommandEncoder> blit = [cmd blitCommandEncoder];
    [blit copyFromTexture:output
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(w, h, 1)
                        toBuffer:read
               destinationOffset:0
          destinationBytesPerRow:row
        destinationBytesPerImage:row * h];
    [blit endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    if (cmd.error)
        return nil;
    NSData *pixels = [NSData dataWithBytes:read.contents length:row * h];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image =
        CGImageCreate(w, h, 8, 32, row, space, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                      provider, NULL, NO, kCGRenderingIntentDefault);
    if (!image) {
        CGColorSpaceRelease(space);
        CGDataProviderRelease(provider);
        return nil;
    }
    NSImage *result = [[NSImage alloc] initWithCGImage:image size:r.size];
    CGImageRelease(image);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return result;
}
@end
