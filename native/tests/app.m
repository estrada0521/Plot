#define PLOT_TESTING
#import "../main.m"
static NSUInteger checks = 0;
static void Check(BOOL value, NSString *message) {
    if (!value) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
    checks++;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        PlotApp *app = [PlotApp new];
        app.renderer = [Renderer new];
        [app makeToolbar];
        PLDataset *a = [PLDataset new], *b = [PLDataset new];
        NSMutableData *values = [NSMutableData dataWithLength:100 * 3 * sizeof(double)];
        double *v = values.mutableBytes;
        for (NSUInteger i = 0; i < 100; i++) {
            v[i * 3] = i;
            v[i * 3 + 1] = sin(i * .1);
            v[i * 3 + 2] = cos(i * .1);
        }
        a.columns = b.columns = @[ @"X", @"Y", @"Z" ];
        a.values = b.values = values;
        a.name = @"A";
        b.name = @"B";
        a.defaultX = b.defaultX = @"X";
        a.defaultY = b.defaultY = @"Y";
        PLGroup *g = [PLGroup new];
        g.columns = a.columns;
        g.x = @"X";
        g.y = @"Y";
        g.items = @[ a, b ];
        PlotController *c = [[PlotController alloc] initWithApp:app group:g];
        [app.controllers addObject:c];
        app.target = c;
        [c.root layoutSubtreeIfNeeded];
        Check(c.charts.count == 1 && c.charts[0].series.count == 2, @"native grouped charts");
        id<MTLBuffer> buffer = c.charts[0].series[0].buffer;
        Bounds range = c.charts[0].range;
        [c choose:1];
        Check(c.selected == 1 && [c.title.stringValue containsString:@"B"] &&
                  c.charts[0].series[0].buffer == buffer,
              @"selection updates header without rebuilding buffers");
        [c.window setContentSize:NSMakeSize(1276, 882)];
        [c windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification
                                                         object:c.window]];
        Check(c.charts[0].plotRect.size.width == 1200 && c.charts[0].plotRect.size.height == 800,
              @"window resize updates plot geometry");
        [c.window setContentSize:NSMakeSize(420, 310)];
        [c layout];
        [c perform:@"points"];
        Bounds afterMode = c.charts[0].range;
        Check(c.charts[0].points && memcmp(&range, &afterMode, sizeof(Bounds)) == 0,
              @"mode switch preserves viewport");
        Bounds zoom = range;
        zoom.width *= .5;
        c.charts[0].range = zoom;
        [c record];
        [c perform:@"home"];
        Check(c.historyIndex == 2, @"home records navigation history");
        [c perform:@"undo-view"];
        Check(c.charts[0].range.width == zoom.width, @"undo restores zoom");
        [c perform:@"redo-view"];
        Check(c.charts[0].range.width == range.width, @"redo restores home");
        [c cycle:NO backwards:NO];
        Check([c.ys.lastObject isEqual:@"Z"] && c.charts[0].range.x == range.x &&
                  c.charts[0].range.width == range.width,
              @"Y column cycle preserves X range");
        [c showAxes];
        [c.axesPanel orderOut:nil];
        c.axesXMin.stringValue = @"10";
        c.axesXMax.stringValue = @"50";
        [c addAxis:nil];
        [c applyAxes:nil];
        Check(c.charts.count == 2 && c.charts[0].range.x == 10 && c.charts[1].range.width == 40,
              @"stacked Y plots with shared manual X range");
        [c showFilter];
        [c.filterPanel orderOut:nil];
        for (NSDictionary *f in c.filterFields)
            if ([f[@"column"] isEqual:@"X"])
                [f[@"min"] setStringValue:@"90"];
        [c applyFilter:nil];
        Check(c.charts[0].series[0].raw.length == 10 * sizeof(XY) && a.rowCount == 100,
              @"native filter preserves original data");
        [c.filterPanel close];
        Check(!c.filterPanel && !c.rules.count && c.charts[0].series[0].raw.length == 100 * sizeof(XY),
              @"closing filter resets rows");
        [c.axesPanel close];
        Check(!c.axesPanel, @"axes panel lifecycle");
        [c perform:@"duplicate"];
        PlotController *duplicate = app.controllers.lastObject;
        Check(duplicate != c && duplicate.group == c.group && duplicate.selected == c.selected &&
                  [duplicate ranges].count == c.charts.count,
              @"duplicate shares immutable originals and copies plot state");
        [duplicate.window close];
        app.target = c;
        [c.root layoutSubtreeIfNeeded];
        for (PLChart *chart in c.charts)
            [chart layout];
        NSData *png = [c panelPNG];
        Check(png.length > 1000, @"GPU-backed PNG export");
        NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:png];
        Check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, @"PNG dimensions");
        NSUInteger dark = 0;
        for (NSInteger y = 30; y < bitmap.pixelsHigh - 50; y++)
            for (NSInteger x = 50; x < bitmap.pixelsWide - 30; x++) {
                NSColor *pixel = [[bitmap colorAtX:x
                                                 y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
                if (pixel.redComponent < .4 && pixel.greenComponent < .4 && pixel.blueComponent < .4)
                    dark++;
            }
        Check(dark > 500, @"PNG contains GPU traces and axes, not a blank Metal layer");
        [png writeToFile:@"build/native-export.png" atomically:YES];
        // Exercise real AppKit key-window and child-window transitions.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        [c.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!NSApp.isActive && deadline.timeIntervalSinceNow > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:[NSDate dateWithTimeIntervalSinceNow:.02]
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (event)
                [NSApp sendEvent:event];
        }
        Check(NSApp.isActive, @"integration app becomes active");
        [c.window makeKeyAndOrderFront:nil];
        [app syncFocus];
        Check(app.toolbar.parentWindow == c.window, @"focused plot owns toolbar");
        NSRect beforeMove = app.toolbar.frame;
        [c.window setFrameOrigin:NSMakePoint(c.window.frame.origin.x + 53, c.window.frame.origin.y - 27)];
        Check(fabs(app.toolbar.frame.origin.x - beforeMove.origin.x - 53) < 1 &&
                  fabs(app.toolbar.frame.origin.y - beforeMove.origin.y + 27) < 1,
              @"AppKit moves toolbar with plot by the same displacement");
        [c.window setContentSize:NSMakeSize(460, 350)];
        Check(fabs(NSMinY(c.window.frame) - NSMaxY(app.toolbar.frame) - 6) < 1, @"resize keeps toolbar gap");
        PlotController *other = [app newPlot:g];
        Check(app.toolbar.parentWindow == other.window && app.target == other,
              @"focus transfers toolbar ownership");
        NSRect attached = app.toolbar.frame;
        [c.window setFrameOrigin:NSMakePoint(110, 230)];
        Check(NSEqualRects(attached, app.toolbar.frame), @"inactive plot cannot move toolbar");
        [app.toolbar makeKeyWindow];
        [app syncFocus];
        Check(app.target == other && app.toolbar.parentWindow == other.window,
              @"toolbar interaction retains owner");
        [other.window close];
        Check(app.toolbar.parentWindow == nil, @"closing owner detaches toolbar");
        [c.window makeKeyAndOrderFront:nil];
        [app syncFocus];
        Check(app.toolbar.parentWindow == c.window, @"remaining plot reclaims toolbar");
        [c.window miniaturize:nil];
        NSDate *miniDeadline = [NSDate dateWithTimeIntervalSinceNow:1];
        while (miniDeadline.timeIntervalSinceNow > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:[NSDate dateWithTimeIntervalSinceNow:.02]
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (event)
                [NSApp sendEvent:event];
        }
        Check(app.toolbar.parentWindow == nil && !app.toolbar.visible,
              @"minimizing focused plot hides and detaches toolbar");
        [c.window deminiaturize:nil];
        [c.window makeKeyAndOrderFront:nil];
        [app syncFocus];
        Check(app.toolbar.parentWindow == c.window, @"restored plot reattaches toolbar");
        [app showSettings];
        Check(app.settings.window != nil && app.settings.window.contentView.subviews.count >= 4,
              @"native settings UI");
        [app.settings.window close];
        [c.window close];
        Check(app.controllers.count == 0 && c.charts.count == 0, @"closing plot releases chart views");
        printf("PASS: %lu native UI/model checks\n", checks);
    }
    return 0;
}
