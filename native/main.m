#import "PlotData.h"
#import "PlotView.h"
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@class PlotApp, PlotController;
static NSTextField *Label(NSString *text, NSRect frame) {
    NSTextField *v = [NSTextField labelWithString:text ?: @""];
    v.frame = frame;
    v.font = [NSFont systemFontOfSize:11];
    v.lineBreakMode = NSLineBreakByTruncatingMiddle;
    v.toolTip = text;
    return v;
}
static NSButton *Button(NSString *title, NSString *help, id target, SEL action, NSRect frame) {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.frame = frame;
    b.bezelStyle = NSBezelStyleRounded;
    b.font = [NSFont systemFontOfSize:11];
    b.toolTip = help;
    b.accessibilityLabel = help;
    b.refusesFirstResponder = YES;
    b.focusRingType = NSFocusRingTypeNone;
    return b;
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
static BOOL ReadLimits(NSTextField *min, NSTextField *max, double *lo, double *hi) {
    if (!min.stringValue.length && !max.stringValue.length)
        return NO;
    NSScanner *a = [NSScanner scannerWithString:min.stringValue],
              *b = [NSScanner scannerWithString:max.stringValue];
    double x, y;
    if (![a scanDouble:&x] || !a.isAtEnd || ![b scanDouble:&y] || !b.isAtEnd || !isfinite(x) ||
        !isfinite(y) || !isfinite(y - x) || x >= y)
        @throw [NSException
            exceptionWithName:@"PlotInput"
                       reason:@"Enter two finite limits with minimum < maximum, or leave both empty."
                     userInfo:nil];
    *lo = x;
    *hi = y;
    return YES;
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
    NSPoint p = e.locationInWindow;
    if (e.type == NSEventTypeLeftMouseDown && p.x > 82 && p.y > self.frame.size.height - 28) {
        [self makeKeyAndOrderFront:nil];
        [self performWindowDragWithEvent:e];
        return;
    }
    if (e.type == NSEventTypeLeftMouseDown && p.x > self.frame.size.width - 12 && p.y < 12) {
        NSRect original = self.frame;
        NSPoint start = NSEvent.mouseLocation;
        while (YES) {
            NSEvent *next = [self nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
            if (next.type == NSEventTypeLeftMouseUp)
                break;
            NSPoint now = NSEvent.mouseLocation;
            NSRect r = original;
            r.size.width = MAX(self.minSize.width, original.size.width + now.x - start.x);
            r.size.height = MAX(self.minSize.height, original.size.height - now.y + start.y);
            r.origin.y = NSMaxY(original) - r.size.height;
            [self setFrame:r display:YES];
        }
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
@property(nonatomic) ToolbarPanel *toolbar;
@property(nonatomic, weak) PlotController *target;
@property(nonatomic) NSPopUpButton *xSelect, *ySelect;
@property(nonatomic) NSMutableDictionary<NSString *, NSButton *> *tools;
@property(nonatomic) NSWindowController *settings;
@property(nonatomic) dispatch_queue_t loader;
@property(nonatomic) NSArray<NSString *> *initialPaths;
@property(nonatomic) NSUInteger syntheticCount, syntheticWindows;
- (void)syncFocus;
- (void)updateToolbar;
- (void)placeToolbar;
- (PlotController *)newPlot:(PLGroup *)group;
- (void)openPaths:(NSArray<NSString *> *)paths reply:(BOOL)reply;
- (void)action:(id)sender;
- (void)applyAppearance;
@end
@interface PlotController : NSObject <NSWindowDelegate>
@property(nonatomic, weak) PlotApp *app;
@property(nonatomic) PlotWindow *window;
@property(nonatomic) PlotRoot *root;
@property(nonatomic) NSTextField *title;
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
@property(nonatomic) NSPanel *filterPanel, *axesPanel;
@property(nonatomic) NSMutableArray<NSDictionary *> *filterFields, *axisFields;
@property(nonatomic) NSPopUpButton *axesX;
@property(nonatomic) NSTextField *axesXMin, *axesXMax;
@property(nonatomic) NSView *axesDocument;
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
@end
@implementation PlotRoot
- (BOOL)isOpaque {
    return YES;
}
- (void)drawRect:(NSRect)dirty {
    [NSColor.whiteColor setFill];
    NSRectFill(self.bounds);
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 28, self.bounds.size.width, 28));
    [[NSColor.separatorColor colorWithAlphaComponent:.5] setFill];
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 29, self.bounds.size.width, 1));
    [NSColor.grayColor setStroke];
    NSBezierPath *grip = [NSBezierPath bezierPath];
    [grip moveToPoint:NSMakePoint(self.bounds.size.width - 8, 2)];
    [grip lineToPoint:NSMakePoint(self.bounds.size.width - 2, 8)];
    [grip stroke];
}
- (void)layout {
    [super layout];
    [self.controller layout];
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
    self.window.hasShadow = NO;
    self.root = [[PlotRoot alloc] initWithFrame:self.window.contentView.bounds];
    self.root.controller = self;
    self.window.contentView = self.root;
    [self.root addSubview:Button(@"×", @"Close Window (⌘W)", self, @selector(close:), NSZeroRect)];
    [self.root addSubview:Button(@"−", @"Minimize (⌘M)", self, @selector(minimize:), NSZeroRect)];
    self.pin = Button(@"↑", @"Always on Top (⌥⌘T)", self, @selector(togglePin:), NSZeroRect);
    self.pin.buttonType = NSButtonTypeToggle;
    [self.root addSubview:self.pin];
    self.title = Label(@"Plot", NSZeroRect);
    [self.root addSubview:self.title];
    if (!group) {
        NSButton *open =
            Button(@"Open Data…", @"Open files (⌘O)", app, @selector(action:), NSMakeRect(135, 120, 150, 30));
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
        self.root.subviews[i].frame = NSMakeRect(4 + i * 24, h - 25, 22, 22);
    self.title.frame = NSMakeRect(82, h - 22, MAX(1, w - 90), 18);
    CGFloat height = (h - 30) / MAX(1ul, self.charts.count);
    for (NSUInteger i = 0; i < self.charts.count; i++)
        self.charts[i].frame = NSMakeRect(0, h - 29 - (i + 1) * height, w, height);
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
    if (self.group.items.count > 1)
        text = [text stringByAppendingFormat:@"  %lu/%lu", self.selected + 1, self.group.items.count];
    self.title.stringValue = text;
    self.title.toolTip = self.group.items.count ? self.group.items[self.selected].path : nil;
    self.window.title = text;
    self.title.textColor = NSApp.isActive && (NSApp.keyWindow == self.window || self.app.target == self)
                               ? NSColor.labelColor
                               : NSColor.secondaryLabelColor;
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
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = title;
    panel.releasedWhenClosed = NO;
    panel.delegate = self;
    panel.minSize = size;
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
    [v addSubview:Button(@"Apply", @"Apply Filter", self, @selector(applyFilter:),
                         NSMakeRect(8, 10, 90, 28))];
    [v addSubview:Button(@"Reset", @"Reset Filter", self, @selector(resetFilter:),
                         NSMakeRect(105, 10, 90, 28))];
    [v addSubview:Button(@"Save CSV…", @"Save Filtered CSV", self, @selector(saveCSV:),
                         NSMakeRect(265, 10, 125, 28))];
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
- (void)addAxisField:(NSString *)column range:(NSValue *)range {
    NSPopUpButton *select = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [select addItemsWithTitles:self.group.columns];
    [select selectItemWithTitle:column];
    NSTextField *lo = Input(@"", NSZeroRect), *hi = Input(@"", NSZeroRect);
    lo.placeholderString = @"auto min";
    hi.placeholderString = @"auto max";
    lo.accessibilityLabel = @"Y minimum";
    hi.accessibilityLabel = @"Y maximum";
    if (range) {
        Bounds b = Unbox(range);
        lo.stringValue = [NSString stringWithFormat:@"%.17g", b.y];
        hi.stringValue = [NSString stringWithFormat:@"%.17g", b.y + b.height];
    }
    NSButton *remove = Button(@"−", @"Remove Y Axis", self, @selector(removeAxis:), NSZeroRect);
    NSDictionary *field = @{@"select" : select, @"min" : lo, @"max" : hi, @"remove" : remove};
    [self.axisFields addObject:field];
    for (NSView *control in field.allValues)
        [self.axesDocument addSubview:control];
    [self layoutAxes];
}
- (void)layoutAxes {
    self.axesDocument.frame = NSMakeRect(0, 0, 500, MAX(170, self.axisFields.count * 34));
    for (NSUInteger i = 0; i < self.axisFields.count; i++) {
        NSDictionary *f = self.axisFields[i];
        CGFloat y = self.axesDocument.frame.size.height - (i + 1) * 34;
        [f[@"select"] setFrame:NSMakeRect(4, y, 240, 28)];
        [f[@"min"] setFrame:NSMakeRect(250, y + 2, 100, 24)];
        [f[@"max"] setFrame:NSMakeRect(355, y + 2, 100, 24)];
        [f[@"remove"] setFrame:NSMakeRect(462, y, 32, 28)];
        [f[@"remove"] setEnabled:self.axisFields.count > 1];
    }
}
- (void)addAxis:(id)sender {
    NSString *column = self.group.columns[MIN(1ul, self.group.columns.count - 1)];
    for (NSString *c in self.group.columns) {
        BOOL used = NO;
        for (NSDictionary *field in self.axisFields)
            used |= [[field[@"select"] titleOfSelectedItem] isEqual:c];
        if (!used && ![c isEqual:self.x]) {
            column = c;
            break;
        }
    }
    [self addAxisField:column range:nil];
}
- (void)removeAxis:(id)sender {
    if (self.axisFields.count <= 1)
        return;
    for (NSDictionary *field in [self.axisFields copy])
        if (field[@"remove"] == sender) {
            for (NSView *v in field.allValues)
                [v removeFromSuperview];
            [self.axisFields removeObject:field];
            break;
        }
    [self layoutAxes];
}
- (void)showAxes {
    if (self.axesPanel) {
        [self.axesPanel makeKeyAndOrderFront:nil];
        return;
    }
    self.axesPanel = [self panel:@"Axes" size:NSMakeSize(530, 300)];
    NSView *v = self.axesPanel.contentView;
    self.axisFields = [NSMutableArray new];
    NSTextField *xLabel = Label(@"X", NSMakeRect(8, 260, 22, 22));
    xLabel.autoresizingMask = NSViewMinYMargin;
    [v addSubview:xLabel];
    self.axesX = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(30, 256, 230, 28)];
    self.axesX.autoresizingMask = NSViewMinYMargin;
    [self.axesX addItemsWithTitles:self.group.columns];
    [self.axesX selectItemWithTitle:self.x];
    [v addSubview:self.axesX];
    Bounds b = self.charts.firstObject.range;
    self.axesXMin = Input([NSString stringWithFormat:@"%.17g", b.x], NSMakeRect(265, 258, 115, 24));
    self.axesXMax = Input([NSString stringWithFormat:@"%.17g", b.x + b.width], NSMakeRect(385, 258, 130, 24));
    self.axesXMin.autoresizingMask = self.axesXMax.autoresizingMask = NSViewMinYMargin;
    self.axesXMin.accessibilityLabel = @"X minimum";
    self.axesXMax.accessibilityLabel = @"X maximum";
    [v addSubview:self.axesXMin];
    [v addSubview:self.axesXMax];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 55, 514, 195)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.axesDocument = [NSView new];
    scroll.documentView = self.axesDocument;
    [v addSubview:scroll];
    NSArray *ranges = [self ranges];
    for (NSUInteger i = 0; i < self.ys.count; i++)
        [self addAxisField:self.ys[i] range:ranges[i]];
    [v addSubview:Button(@"Add Y", @"Add Y Axis", self, @selector(addAxis:), NSMakeRect(8, 12, 90, 28))];
    NSButton *apply =
        Button(@"Apply", @"Apply Axes", self, @selector(applyAxes:), NSMakeRect(418, 12, 100, 28));
    apply.keyEquivalent = @"\r";
    apply.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [v addSubview:apply];
    [self.window addChildWindow:self.axesPanel ordered:NSWindowAbove];
    [self.axesPanel makeKeyAndOrderFront:nil];
}
- (void)applyAxes:(id)sender {
    @try {
        double x0 = 0, x1 = 0;
        BOOL hasX = ReadLimits(self.axesXMin, self.axesXMax, &x0, &x1);
        NSMutableArray *ys = [NSMutableArray new], *limits = [NSMutableArray new];
        for (NSDictionary *field in self.axisFields) {
            [ys addObject:[field[@"select"] titleOfSelectedItem]];
            double lo = 0, hi = 0;
            BOOL has = ReadLimits(field[@"min"], field[@"max"], &lo, &hi);
            [limits addObject:has ? @[ @(lo), @(hi) ] : NSNull.null];
        }
        self.x = self.axesX.titleOfSelectedItem;
        self.ys = ys;
        [self rebuild];
        for (NSUInteger i = 0; i < self.charts.count; i++) {
            Bounds b = self.charts[i].range;
            if (hasX) {
                b.x = x0;
                b.width = x1 - x0;
            }
            if (limits[i] != NSNull.null) {
                b.y = [limits[i][0] doubleValue];
                b.height = [limits[i][1] doubleValue] - b.y;
            }
            self.charts[i].range = b;
            [self.charts[i] refresh];
        }
        [self.history removeAllObjects];
        self.historyIndex = -1;
        [self record];
    } @catch (NSException *e) {
        Alert(@"Invalid axes", e.reason);
    }
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
        [button.cell drawWithFrame:button.frame inView:self.root];
    }
    [self.title.stringValue drawAtPoint:NSMakePoint(82, size.height - 22)
                         withAttributes:@{
                             NSFontAttributeName : [NSFont systemFontOfSize:11],
                             NSForegroundColorAttributeName : NSColor.labelColor
                         }];
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
        [chart drawAnnotations];
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
    } else if ([action isEqual:@"axes"])
        [self showAxes];
    else if ([action isEqual:@"filter"])
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
    if (n.object == self.axesPanel) {
        [self.window removeChildWindow:self.axesPanel];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.app.controllers containsObject:self] && self.window.visible &&
                !self.window.miniaturized && !NSApp.keyWindow)
                [self.window makeKeyAndOrderFront:nil];
        });
        self.axesPanel = nil;
        self.axisFields = nil;
        self.axesDocument = nil;
        return;
    }
    if (n.object != self.window)
        return;
    self.filterPanel.delegate = nil;
    [self.filterPanel close];
    self.axesPanel.delegate = nil;
    [self.axesPanel close];
    if (self.app.target == self) {
        [self.window removeChildWindow:self.app.toolbar];
        self.app.target = nil;
        [self.app.toolbar orderOut:nil];
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
    for (PlotController *c in self.controllers)
        [c.root setNeedsDisplay:YES];
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
            @[ @"Axes…", @"axes", @"g", @(alt | NSEventModifierFlagShift) ],
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
    self.toolbar.opaque = YES;
    self.toolbar.backgroundColor = NSColor.windowBackgroundColor;
    self.toolbar.hasShadow = NO;
    self.toolbar.releasedWhenClosed = NO;
    self.toolbar.becomesKeyOnlyIfNeeded = YES;
    NSArray *commands = @[
        @[ @"Open", @"open", @"Open files (⌘O)" ], @[ @"⌂", @"home", @"Fit all data" ],
        @[ @"‹", @"undo-view", @"Previous view" ], @[ @"›", @"redo-view", @"Next view" ],
        @[ @"Pan", @"pan", @"Pan" ], @[ @"Zoom", @"zoom", @"Box zoom" ], @[ @"Line", @"line", @"Lines" ],
        @[ @"Dots", @"points", @"Points" ], @[ @"Clean", @"outliers", @"Exclude outliers (⇧⌥⌘R)" ],
        @[ @"Axes", @"axes", @"Axes (⇧⌥⌘G)" ], @[ @"Filter", @"filter", @"Filter (⌥⌘F)" ],
        @[ @"PNG", @"save-image", @"Save image (⌘S)" ]
    ];
    CGFloat x = 3;
    for (NSArray *entry in commands) {
        CGFloat w = [entry[0] length] > 3 ? 46 : 30;
        NSButton *button = Button(entry[0], entry[2], self, @selector(action:), NSMakeRect(x, 3, w, 28));
        button.identifier = entry[1];
        button.bordered = NO;
        if ([@[ @"pan", @"zoom", @"line", @"points", @"outliers" ] containsObject:entry[1]])
            button.buttonType = NSButtonTypeToggle;
        self.tools[entry[1]] = button;
        [self.toolbar.contentView addSubview:button];
        x += w;
    }
    [self.toolbar.contentView addSubview:Label(@"X", NSMakeRect(x, 9, 12, 18))];
    x += 12;
    self.xSelect = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 4, 98, 26) pullsDown:NO];
    self.xSelect.target = self;
    self.xSelect.action = @selector(action:);
    self.xSelect.identifier = @"x-select";
    self.xSelect.accessibilityLabel = @"X column";
    [self.toolbar.contentView addSubview:self.xSelect];
    x += 100;
    [self.toolbar.contentView addSubview:Label(@"Y", NSMakeRect(x, 9, 12, 18))];
    x += 12;
    self.ySelect = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 4, 98, 26) pullsDown:NO];
    self.ySelect.target = self;
    self.ySelect.action = @selector(action:);
    self.ySelect.identifier = @"y-select";
    self.ySelect.accessibilityLabel = @"Y column";
    [self.toolbar.contentView addSubview:self.ySelect];
    NSRect r = self.toolbar.frame;
    r.size.width = x + 101;
    [self.toolbar setFrame:r display:NO];
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
}
- (void)syncFocus {
    NSWindow *key = NSApp.keyWindow;
    PlotController *active = nil;
    if (NSApp.isActive) {
        if (key == self.toolbar)
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
        return;
    }
    [self updateToolbar];
    if (self.toolbar.parentWindow != active.window) {
        [self placeToolbar];
        [active.window addChildWindow:self.toolbar ordered:NSWindowAbove];
        [self.toolbar orderFront:nil];
    }
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
    self.xSelect.enabled = self.ySelect.enabled = loaded;
    NSArray *titles = c.group.columns ?: @[];
    if (![self.xSelect.itemTitles isEqual:titles]) {
        [self.xSelect removeAllItems];
        [self.ySelect removeAllItems];
        [self.xSelect addItemsWithTitles:titles];
        [self.ySelect addItemsWithTitles:titles];
    }
    [self.xSelect selectItemWithTitle:c.x ?: @""];
    [self.ySelect selectItemWithTitle:c.ys.lastObject ?: @""];
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
        NSWindow *window =
            [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 130)
                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
        window.title = @"Settings";
        window.releasedWhenClosed = NO;
        self.settings = [[NSWindowController alloc] initWithWindow:window];
        NSView *v = window.contentView;
        [v addSubview:Label(@"Theme", NSMakeRect(16, 83, 85, 24))];
        NSPopUpButton *theme = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 82, 230, 28)
                                                          pullsDown:NO];
        [theme addItemsWithTitles:@[ @"System", @"Light", @"Dark" ]];
        NSString *pref = [NSUserDefaults.standardUserDefaults stringForKey:@"theme"] ?: @"system";
        [theme selectItemAtIndex:[pref isEqual:@"dark"] ? 2 : [pref isEqual:@"light"] ? 1 : 0];
        theme.identifier = @"theme";
        theme.target = self;
        theme.action = @selector(settingChanged:);
        [v addSubview:theme];
        [v addSubview:Label(@"Editor", NSMakeRect(16, 39, 85, 24))];
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
        if (NSApp.keyWindow == owner.window || NSApp.keyWindow == owner.axesPanel ||
            NSApp.keyWindow == owner.filterPanel)
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
        [(NSApp.keyWindow == self.toolbar ? c.window : NSApp.keyWindow) close];
    else if ([action isEqual:@"minimize"])
        [(NSApp.keyWindow == self.toolbar ? c.window : NSApp.keyWindow) miniaturize:nil];
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
    } else if ([action hasSuffix:@"-x"] || [action hasSuffix:@"-y"])
        [c cycle:[action hasSuffix:@"-x"] backwards:[action hasPrefix:@"previous"]];
    else if ([action isEqual:@"x-select"] || [action isEqual:@"y-select"]) {
        BOOL x = [action isEqual:@"x-select"];
        NSArray *before = [c ranges];
        if (x)
            c.x = self.xSelect.titleOfSelectedItem;
        else {
            NSMutableArray *ys = [c.ys mutableCopy];
            ys[ys.count - 1] = self.ySelect.titleOfSelectedItem;
            c.ys = ys;
        }
        [c rebuild];
        for (NSUInteger i = 0; i < c.charts.count; i++) {
            Bounds b = c.charts[i].range, old = Unbox(before[i]);
            if (x) {
                b.y = old.y;
                b.height = old.height;
            } else {
                b.x = old.x;
                b.width = old.width;
            }
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
