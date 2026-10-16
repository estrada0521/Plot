#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
typedef struct {
    double x, y;
} XY;
typedef struct {
    double x, y, width, height;
} Bounds;
typedef struct {
    vector_float2 minimum, span, pixels;
    float width;
    uint32_t points, dark;
    vector_float4 color;
} Viewport;

typedef struct {
    double background, ink, axis, selected, context;
} PlotPalette;
static inline PlotPalette PLPlotPalette(BOOL dark) {
    return dark ? (PlotPalette){.07, .88, .68, .92, .42} : (PlotPalette){1, 0, .08, .08, .72};
}
static inline BOOL PLPlotIsDark(NSAppearance *appearance) {
    return [[(appearance ?: NSAppearance.currentDrawingAppearance) bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
    ]] isEqual:NSAppearanceNameDarkAqua];
}
static inline NSColor *PLPlotGray(double value, double alpha) {
    return [NSColor colorWithSRGBRed:value green:value blue:value alpha:alpha];
}

@interface Series : NSObject
@property(nonatomic) NSString *name;
@property(nonatomic) NSString *xName;
@property(nonatomic) NSString *yName;
@property(nonatomic) NSData *raw;
@property(nonatomic) id<MTLBuffer> buffer;
@property(nonatomic) double xMin, xMax, yMin, yMax;
@property(nonatomic) double prepareMS;
@property(nonatomic) Bounds bufferBounds;
- (instancetype)initWithData:(NSData *)data name:(NSString *)name device:(id<MTLDevice>)device;
@end
@interface Renderer : NSObject
@property(nonatomic) id<MTLDevice> device;
@property(nonatomic) id<MTLCommandQueue> queue;
@property(nonatomic) id<MTLRenderPipelineState> lines, points;
@property(nonatomic) double setupMS;
- (id<MTLCommandBuffer>)encode:(MTLRenderPassDescriptor *)pass
                        series:(NSArray<Series *> *)series
                      selected:(NSUInteger)selected
                        bounds:(Bounds)bounds
                      viewport:(Viewport)view
                        points:(BOOL)points
                      drawable:(id<CAMetalDrawable>)drawable;
@end

@interface Series (Rebase)
- (void)rebaseToBounds:(Bounds)bounds;
@end
