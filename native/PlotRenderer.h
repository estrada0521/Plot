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
    uint32_t points;
    vector_float4 color;
} Viewport;

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
