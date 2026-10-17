#import "PlotRenderer.h"

@interface PLChart : NSView <MTKViewDelegate>
@property(nonatomic) Renderer *renderer;
@property(nonatomic) NSArray<Series *> *series;
@property(nonatomic) NSString *xName, *yName;
@property(nonatomic) Bounds range;
@property(nonatomic) NSUInteger selected;
@property(nonatomic) BOOL points, pan, showsXLabels;
@property(nonatomic, copy) void (^changed)(PLChart *chart, BOOL finished);
@property(nonatomic, copy) void (^activate)(void);
@property(nonatomic, copy) void (^selectDataset)(NSInteger delta);
@property(nonatomic, copy) void (^navigate)(BOOL forward);
@property(nonatomic, readonly) NSRect plotRect;
- (instancetype)initWithRenderer:(Renderer *)renderer;
- (void)refresh;
- (void)refreshAppearance;
- (void)drawAnnotations;
- (void)drawAnnotationsForExport;
- (NSImage *)plotImageAtScale:(CGFloat)scale;
@end
Bounds PLSeriesExtent(NSArray<Series *> *series);
