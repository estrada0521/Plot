#import "PlotRenderer.h"
#include <float.h>
static void Require(BOOL ok, NSString *message) {
    if (!ok)
        @throw [NSException exceptionWithName:@"PlotRenderer" reason:message userInfo:nil];
}
@implementation Series
- (instancetype)initWithData:(NSData *)data name:(NSString *)name device:(id<MTLDevice>)device {
    if (!(self = [super init]))
        return nil;
    self.raw = data;
    self.name = name;
    self.xName = @"X";
    self.yName = @"Y";
    const XY *xy = data.bytes;
    NSUInteger n = data.length / sizeof(XY);
    double xMin = DBL_MAX, yMin = DBL_MAX, xMax = -DBL_MAX, yMax = -DBL_MAX;
    for (NSUInteger i = 0; i < n; i++)
        if (isfinite(xy[i].x) && isfinite(xy[i].y)) {
            xMin = fmin(xMin, xy[i].x);
            xMax = fmax(xMax, xy[i].x);
            yMin = fmin(yMin, xy[i].y);
            yMax = fmax(yMax, xy[i].y);
        }
    if (xMin == DBL_MAX) {
        xMin = yMin = -1;
        xMax = yMax = 1;
    }
    self.xMin = xMin;
    self.xMax = xMax;
    self.yMin = yMin;
    self.yMax = yMax;
    if (self.xMax == self.xMin) {
        double pad = fmax(fabs(self.xMin) * 1e-6, 1);
        self.xMin -= pad;
        self.xMax += pad;
    }
    if (self.yMax == self.yMin) {
        double pad = fmax(fabs(self.yMin) * 1e-6, 1);
        self.yMin -= pad;
        self.yMax += pad;
    }
    self.buffer = [device newBufferWithLength:MAX(sizeof(vector_float2), n * sizeof(vector_float2))
                                      options:MTLResourceStorageModeShared];
    Require(self.buffer != nil, @"Cannot allocate vertex buffer");
    [self rebaseToBounds:(Bounds){self.xMin, self.yMin, self.xMax - self.xMin, self.yMax - self.yMin}];
    return self;
}
- (void)rebaseToBounds:(Bounds)b {
    // Replace instead of mutating a buffer that an earlier GPU command may still read.
    id<MTLBuffer> buffer = [self.buffer.device newBufferWithLength:self.buffer.length
                                                           options:MTLResourceStorageModeShared];
    if (!buffer)
        @throw [NSException exceptionWithName:@"PlotRenderer"
                                       reason:@"Cannot allocate rebased vertex buffer"
                                     userInfo:nil];
    const XY *xy = self.raw.bytes;
    vector_float2 *out = buffer.contents;
    NSUInteger count = self.raw.length / sizeof(XY);
    for (NSUInteger i = 0; i < count; i++)
        out[i] = (vector_float2){(xy[i].x - b.x) / b.width, (xy[i].y - b.y) / b.height};
    self.buffer = buffer;
    self.bufferBounds = b;
}
@end

@implementation Renderer
- (instancetype)init {
    if (!(self = [super init]))
        return nil;
    self.device = MTLCreateSystemDefaultDevice();
    Require(self.device != nil, @"Metal is unavailable");
    self.queue = [self.device newCommandQueue];
    NSString *shader = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"plot.metal"];
#ifdef PLOT_TESTING
    if (![NSFileManager.defaultManager fileExistsAtPath:shader])
        shader = [NSFileManager.defaultManager.currentDirectoryPath
            stringByAppendingPathComponent:@"src/plot.metal"];
#endif
    NSString *source = [NSString stringWithContentsOfFile:shader encoding:NSUTF8StringEncoding error:nil];
    Require(source != nil, @"Cannot load plot shaders.");
    NSError *error;
    MTLCompileOptions *options = [MTLCompileOptions new];
    // NaN checks preserve missing-data gaps; fast math may assume all values are finite.
    options.fastMathEnabled = NO;
    id<MTLLibrary> library = [self.device newLibraryWithSource:source options:options error:&error];
    Require(library != nil, error.localizedDescription ?: @"Shader compilation failed");
    for (NSNumber *points in @[ @NO, @YES ]) {
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [library newFunctionWithName:points.boolValue ? @"plot_point" : @"plot_line"];
        desc.fragmentFunction = [library newFunctionWithName:points.boolValue ? @"plot_dot" : @"plot_color"];
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.rasterSampleCount = 4;
        id<MTLRenderPipelineState> pipeline = [self.device newRenderPipelineStateWithDescriptor:desc
                                                                                          error:&error];
        Require(pipeline != nil, error.localizedDescription ?: @"Pipeline creation failed");
        if (points.boolValue)
            self.points = pipeline;
        else
            self.lines = pipeline;
    }
    return self;
}
- (id<MTLCommandBuffer>)encode:(MTLRenderPassDescriptor *)pass
                        series:(NSArray<Series *> *)series
                      selected:(NSUInteger)selected
                        bounds:(Bounds)bounds
                      viewport:(Viewport)view
                        points:(BOOL)points
                      drawable:(id<CAMetalDrawable>)drawable {
    id<MTLCommandBuffer> command = [self.queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:points ? self.points : self.lines];
    // Draw the selection last. Buffer contents remain unchanged when selection changes.
    for (NSUInteger step = 0; step <= series.count; step++) {
        NSUInteger index = step == series.count ? selected : step;
        if (index >= series.count || (step != series.count && index == selected))
            continue;
        Series *s = series[index];
        Bounds base = s.bufferBounds;
        if (bounds.width < base.width * .001 || bounds.height < base.height * .001 ||
            bounds.width > base.width * 1000 || bounds.height > base.height * 1000 ||
            fabs(bounds.x - base.x) > base.width * 10 || fabs(bounds.y - base.y) > base.height * 10) {
            [s rebaseToBounds:bounds];
            base = bounds;
        }
        Viewport uniforms = view;
        // All buffers use their own local origin; remap to the shared group's axes.
        uniforms.minimum =
            (vector_float2){(bounds.x - base.x) / base.width, (bounds.y - base.y) / base.height};
        uniforms.span = (vector_float2){bounds.width / base.width, bounds.height / base.height};
        uniforms.points = (uint32_t)(s.raw.length / sizeof(XY));
        PlotPalette palette = PLPlotPalette(view.dark);
        float gray = index == selected ? palette.selected : palette.context;
        uniforms.color = (vector_float4){gray, gray, gray, 1};
        uniforms.width =
            (points ? (index == selected ? 4 : 3) : (index == selected ? 2.5 : 1.5)) * view.width;
        [encoder setVertexBuffer:s.buffer offset:0 atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        NSUInteger count = points ? uniforms.points : (uniforms.points > 1 ? (uniforms.points - 1) * 6ul : 0);
        if (count)
            [encoder drawPrimitives:points ? MTLPrimitiveTypePoint : MTLPrimitiveTypeTriangle
                        vertexStart:0
                        vertexCount:count];
    }
    [encoder endEncoding];
    if (drawable)
        [command presentDrawable:drawable];
    return command;
}
@end
