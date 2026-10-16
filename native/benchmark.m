#import "PlotRenderer.h"
#include <float.h>
#import <mach/mach.h>
#include <time.h>
static double Now(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
}
static void Require(BOOL ok, NSString *message) {
    if (!ok)
        @throw [NSException exceptionWithName:@"PlotTest" reason:message userInfo:nil];
}
static Bounds Extent(NSArray<Series *> *series) {
    double x = DBL_MAX, y = DBL_MAX, xx = -DBL_MAX, yy = -DBL_MAX;
    for (Series *s in series) {
        x = fmin(x, s.xMin);
        y = fmin(y, s.yMin);
        xx = fmax(xx, s.xMax);
        yy = fmax(yy, s.yMax);
    }
    return (Bounds){x - (xx - x) * .02, y - (yy - y) * .05, (xx - x) * 1.04, (yy - y) * 1.1};
}
static void DrawCG(CGContextRef context, NSArray<Series *> *series, NSUInteger selected, Bounds b,
                   CGSize pixels, BOOL points) {
    CGContextSaveGState(context);
    CGContextClipToRect(context, (CGRect){CGPointZero, pixels});
    for (NSUInteger step = 0; step <= series.count; step++) {
        NSUInteger index = step == series.count ? selected : step;
        if (index >= series.count || (step != series.count && index == selected))
            continue;
        Series *s = series[index];
        const XY *xy = s.raw.bytes;
        NSUInteger n = s.raw.length / sizeof(XY);
        CGFloat gray = index == selected ? .08 : .72;
        CGContextSetRGBStrokeColor(context, gray, gray, gray, 1);
        CGContextSetRGBFillColor(context, gray, gray, gray, 1);
        CGContextSetLineWidth(context, index == selected ? 2.5 : 1.5);
        CGContextSetLineJoin(context, kCGLineJoinBevel);
        BOOL connected = NO;
        CGContextBeginPath(context);
        for (NSUInteger i = 0; i < n; i++) {
            if (!isfinite(xy[i].x) || !isfinite(xy[i].y)) {
                connected = NO;
                continue;
            }
            CGPoint p = CGPointMake((xy[i].x - b.x) / b.width * pixels.width,
                                    (xy[i].y - b.y) / b.height * pixels.height);
            if (points)
                CGContextFillEllipseInRect(context, CGRectMake(p.x - 2, p.y - 2, 4, 4));
            else if (!connected) {
                CGContextMoveToPoint(context, p.x, p.y);
                connected = YES;
            } else
                CGContextAddLineToPoint(context, p.x, p.y);
        }
        if (!points)
            CGContextStrokePath(context);
    }
    CGContextRestoreGState(context);
}

static Series *Synthetic(NSUInteger count, NSUInteger phase, Renderer *renderer) {
    NSMutableData *data = [NSMutableData dataWithLength:count * sizeof(XY)];
    XY *xy = data.mutableBytes;
    for (NSUInteger i = 0; i < count; i++) {
        double x = (double)i / MAX(1ul, count - 1) * 100;
        xy[i] = (XY){x, sin(x * .25 + phase * .1) + .05 * sin(x * 11)};
    }
    return [[Series alloc]
        initWithData:data
                name:[NSString stringWithFormat:@"Synthetic %lu (%lu points)", phase + 1, count]
              device:renderer.device];
}
static double Median(NSArray<NSNumber *> *values) {
    NSArray *sorted = [values sortedArrayUsingSelector:@selector(compare:)];
    return [sorted[sorted.count / 2] doubleValue];
}
static void Benchmark(Renderer *renderer, NSUInteger count, NSUInteger windows, BOOL points) {
    @autoreleasepool {
        NSMutableArray<Series *> *series = [NSMutableArray new];
        double prep = 0;
        for (NSUInteger i = 0; i < windows; i++) {
            Series *s = Synthetic(count, i, renderer);
            [series addObject:s];
            prep += s.prepareMS;
        }
        const NSUInteger width = 1200, height = 800;
        MTLTextureDescriptor *texture =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:width
                                                              height:height
                                                           mipmapped:NO];
        texture.usage = MTLTextureUsageRenderTarget;
        texture.storageMode = MTLStorageModePrivate;
        id<MTLTexture> resolve = [renderer.device newTextureWithDescriptor:texture];
        texture.textureType = MTLTextureType2DMultisample;
        texture.sampleCount = 4;
        id<MTLTexture> multisample = [renderer.device newTextureWithDescriptor:texture];
        Require(resolve && multisample, @"Cannot allocate benchmark target");
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = multisample;
        pass.colorAttachments[0].resolveTexture = resolve;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1);
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        CGContextRef cg = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color,
                                                (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(color);
        Require(cg != NULL, @"Cannot allocate bitmap");
        NSMutableArray *gpuTimes = [NSMutableArray new], *wallTimes = [NSMutableArray new],
                       *cgTimes = [NSMutableArray new];
        // One warm-up, then five measured batches. Each batch redraws every logical window once.
        for (NSUInteger frame = 0; frame < 6; frame++) {
            @autoreleasepool {
                double gpu = 0, start = Now();
                for (Series *s in series) {
                    Bounds b = Extent(@[ s ]);
                    b.x += frame * .001 * b.width;
                    Viewport v = {.pixels = {width, height}, .width = 1};
                    id<MTLCommandBuffer> command = [renderer encode:pass
                                                             series:@[ s ]
                                                           selected:0
                                                             bounds:b
                                                           viewport:v
                                                             points:points
                                                           drawable:nil];
                    [command commit];
                    [command waitUntilCompleted];
                    Require(command.status == MTLCommandBufferStatusCompleted,
                            command.error.localizedDescription ?: @"GPU failed");
                    gpu += (command.GPUEndTime - command.GPUStartTime) * 1000;
                }
                double wall = (Now() - start) * 1000;
                start = Now();
                for (Series *s in series) {
                    Bounds b = Extent(@[ s ]);
                    b.x += frame * .001 * b.width;
                    CGContextSetRGBFillColor(cg, 1, 1, 1, 1);
                    CGContextFillRect(cg, CGRectMake(0, 0, width, height));
                    DrawCG(cg, @[ s ], 0, b, CGSizeMake(width, height), points);
                    CGContextFlush(cg);
                }
                double cpu = (Now() - start) * 1000;
                if (frame) {
                    [gpuTimes addObject:@(gpu)];
                    [wallTimes addObject:@(wall)];
                    [cgTimes addObject:@(cpu)];
                }
            }
        }
        struct task_vm_info memory = {0};
        mach_msg_type_number_t size = TASK_VM_INFO_COUNT;
        task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&memory, &size);
        printf("%lu,%lu,%s,%.2f,%.2f,%.2f,%.2f,%.1f\n", count, windows, points ? "points" : "lines", prep,
               Median(gpuTimes), Median(wallTimes), Median(cgTimes), memory.phys_footprint / 1048576.0);
        fflush(stdout);
        CGContextRelease(cg);
    }
}

static NSData *ReadMetalTheme(Renderer *renderer, NSArray<Series *> *series, NSUInteger selected,
                              Bounds bounds, BOOL points, BOOL dark) {
    const NSUInteger w = 256, h = 128;
    MTLTextureDescriptor *d =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:w
                                                          height:h
                                                       mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget;
    d.storageMode = MTLStorageModePrivate;
    id<MTLTexture> output = [renderer.device newTextureWithDescriptor:d];
    d.textureType = MTLTextureType2DMultisample;
    d.sampleCount = 4;
    id<MTLTexture> msaa = [renderer.device newTextureWithDescriptor:d];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = msaa;
    pass.colorAttachments[0].resolveTexture = output;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
    PlotPalette palette = PLPlotPalette(dark);
    pass.colorAttachments[0].clearColor =
        MTLClearColorMake(palette.background, palette.background, palette.background, 1);
    Viewport v = {.pixels = {w, h}, .width = 1, .dark = dark};
    id<MTLCommandBuffer> command = [renderer encode:pass
                                             series:series
                                           selected:selected
                                             bounds:bounds
                                           viewport:v
                                             points:points
                                           drawable:nil];
    id<MTLBuffer> readback = [renderer.device newBufferWithLength:w * h * 4
                                                          options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    [blit copyFromTexture:output
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(w, h, 1)
                        toBuffer:readback
               destinationOffset:0
          destinationBytesPerRow:w * 4
        destinationBytesPerImage:w * h * 4];
    [blit endEncoding];
    [command commit];
    [command waitUntilCompleted];
    Require(command.status == MTLCommandBufferStatusCompleted,
            command.error.localizedDescription ?: @"Readback failed");
    return [NSData dataWithBytes:readback.contents length:w * h * 4];
}
static NSData *ReadMetal(Renderer *renderer, NSArray<Series *> *series, NSUInteger selected, Bounds bounds,
                         BOOL points) {
    return ReadMetalTheme(renderer, series, selected, bounds, points, NO);
}
static unsigned Pixel(NSData *image, int x, int y) {
    return ((const unsigned char *)image.bytes)[(y * 256 + x) * 4];
}
static BOOL DarkNear(NSData *image, int x, int y) {
    for (int dy = -2; dy <= 2; dy++)
        for (int dx = -2; dx <= 2; dx++)
            if (Pixel(image, x + dx, y + dy) < 80)
                return YES;
    return NO;
}
static void Verify(Renderer *renderer) {
    // Large absolute coordinates expose accidental float conversion before origin subtraction.
    const double x = 1e12, y = 1e9;
    XY raw[] = {{x, y}, {x + 4, y + 4}, {NAN, NAN}, {x + 6, y + 4}, {x + 10, y}};
    Series *s = [[Series alloc] initWithData:[NSData dataWithBytes:raw length:sizeof(raw)]
                                        name:@"Precision and gaps"
                                      device:renderer.device];
    Bounds b = {x - 1, y - 1, 12, 6};
    NSData *image = ReadMetal(renderer, @[ s ], 0, b, NO);
    Require(DarkNear(image, 64, 64) && DarkNear(image, 192, 64),
            @"FAIL: large-offset coordinates lost precision or lines are absent");
    Require(Pixel(image, 128, 21) > 245, @"FAIL: line bridged a missing-data gap");
    puts("PASS: large-offset coordinates and missing-data gaps");
    XY a[] = {{x, y + 1}, {x + 10, y + 1}}, c[] = {{x, y + 3}, {x + 10, y + 3}};
    Series *sa = [[Series alloc] initWithData:[NSData dataWithBytes:a length:sizeof(a)]
                                         name:@"A"
                                       device:renderer.device];
    Series *sc = [[Series alloc] initWithData:[NSData dataWithBytes:c length:sizeof(c)]
                                         name:@"B"
                                       device:renderer.device];
    Bounds group = {x, y, 10, 4};
    image = ReadMetal(renderer, @[ sa, sc ], 0, group, NO);
    Require(DarkNear(image, 128, 96) && Pixel(image, 128, 32) > 140 && Pixel(image, 128, 32) < 245,
            @"FAIL: shared axes or selected/gray colors");
    id<MTLBuffer> before = sa.buffer;
    image = ReadMetal(renderer, @[ sa, sc ], 1, group, NO);
    Require(DarkNear(image, 128, 32) && Pixel(image, 128, 96) > 140 && Pixel(image, 128, 96) < 245 &&
                sa.buffer == before,
            @"FAIL: selection switch or buffer reuse");
    puts("PASS: shared axes, selection colors and buffer reuse");
    XY point[] = {{NAN, NAN}, {x + 5, y + 2}};
    Series *sp = [[Series alloc] initWithData:[NSData dataWithBytes:point length:sizeof(point)]
                                         name:@"Single point"
                                       device:renderer.device];
    image = ReadMetal(renderer, @[ sp ], 0, group, YES);
    Require(DarkNear(image, 128, 64) && Pixel(image, 16, 16) > 245,
            @"FAIL: isolated marker or missing marker");
    puts("PASS: isolated marker and non-finite marker rejection");
    image = ReadMetalTheme(renderer, @[ sa, sc ], 0, group, NO, YES);
    Require(Pixel(image, 128, 96) > 210 && Pixel(image, 128, 32) > 70 && Pixel(image, 128, 32) < 150 &&
                Pixel(image, 16, 64) < 35 && sa.buffer == before,
            @"FAIL: dark palette must render white selection and gray context without replacing buffers");
    image = ReadMetalTheme(renderer, @[ sp ], 0, group, YES, YES);
    Require(Pixel(image, 128, 64) > 210 && Pixel(image, 16, 16) < 35,
            @"FAIL: dark points must remain visible on the dark background");
    puts("PASS: dark background, selected and context colors for lines and points");
    XY zoom[] = {{0, 0}, {1e8 - 1, 1}, {1e8, 1}, {1e8 + 1, 1}};
    Series *detail = [[Series alloc] initWithData:[NSData dataWithBytes:zoom length:sizeof(zoom)]
                                             name:@"Deep zoom"
                                           device:renderer.device];
    id<MTLBuffer> original = detail.buffer;
    image = ReadMetal(renderer, @ [detail], 0, (Bounds) { 1e8 - 2, 0, 4, 2 }, YES);
    Require(DarkNear(image, 64, 64) && DarkNear(image, 128, 64) && DarkNear(image, 192, 64) &&
                original != detail.buffer,
            @"FAIL: deep zoom must rebase from double precision values");
    puts("PASS: deep-zoom rebasing preserves nearby points");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        @try {
            NSUInteger count = 3000000, windows = 1;
            BOOL points = NO, verify = NO;
            for (int i = 1; i < argc; i++) {
                NSString *arg = @(argv[i]);
                if ([arg isEqual:@"--verify"])
                    verify = YES;
                else if ([arg isEqual:@"--markers"])
                    points = YES;
                else if ([arg isEqual:@"--benchmark"]) {
                } else if (([arg isEqual:@"--points"] || [arg isEqual:@"--windows"]) && i + 1 < argc) {
                    NSInteger value = [@(argv[++i]) integerValue];
                    Require(value > 0, @"Counts must be positive");
                    if ([arg isEqual:@"--points"])
                        count = value;
                    else
                        windows = value;
                } else {
                    fprintf(stderr,
                            "Usage: bin/benchmark-metal [--verify] [--points N] [--windows N] [--markers]\n");
                    return 1;
                }
            }
            Require(count <= 10000000 && windows <= 32, @"Benchmark limits: 10 million points, 32 batches");
            Renderer *renderer = [Renderer new];
            fprintf(stderr, "GPU: %s; setup %.2f ms\n", renderer.device.name.UTF8String, renderer.setupMS);
            if (verify)
                Verify(renderer);
            else {
                puts("points_per_window,windows,mode,prepare_ms,metal_gpu_ms,metal_wall_ms,cg_wall_ms,"
                     "combined_footprint_mib");
                Benchmark(renderer, count, windows, points);
            }
        } @catch (NSException *e) {
            fprintf(stderr, "%s\n", e.reason.UTF8String);
            return 1;
        }
    }
    return 0;
}
