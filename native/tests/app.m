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
        for (NSButton *button in app.tools.allValues)
            Check(button.image != nil && button.toolTip.length > 0, @"toolbar symbol and help available");
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
        [app updateToolbar];
        [c.root layoutSubtreeIfNeeded];
        Check(c.charts.count == 1 && c.charts[0].series.count == 2, @"native grouped charts");
        for (NSString *position in @[ @"1 / 2", @"10 / 10", @"100 / 100", @"1000 / 1000" ]) {
            c.positionLabel.stringValue = position;
            [c.window setContentSize:NSMakeSize(240, 170)];
            [c layout];
            NSSize needed = c.positionLabel.cell.cellSize;
            Check(c.positionLabel.frame.size.width >= needed.width &&
                      c.positionLabel.frame.size.height >= needed.height &&
                      NSMaxX(c.positionLabel.frame) <= c.root.bounds.size.width - 7 &&
                      NSMaxX(c.title.frame) < NSMinX(c.positionLabel.frame),
                  @"dataset counter fits its text cell at minimum window size");
        }
        [c.window setContentSize:NSMakeSize(420, 310)];
        [c updateHeader];
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
        Bounds shared = c.charts[0].range;
        shared.x = 10;
        shared.width = 40;
        c.charts[0].range = shared;
        [app.yAdd performClick:nil];
        Check(c.charts.count == 2 && app.ySelects.count == 2 && c.charts[0].range.x == 10 &&
                  c.charts[1].range.width == 40 && [c.charts[0].yName isEqual:c.ys[0]] &&
                  [c.charts[1].yName isEqual:c.ys[1]] &&
                  NSMaxY(app.yStack.frame) < NSMaxY(app.toolbar.frame) &&
                  app.ySelects[1].superview == app.yStack.contentView &&
                  c.charts[1].frame.origin.y < c.charts[0].frame.origin.y,
              @"plus adds ordered Y selector and corresponding plot, preserving shared X");
        Check(NSMaxY(app.yStack.frame) == NSMinY(app.toolbar.frame) &&
                  NSMaxX(app.yStack.frame) == NSMaxX(app.toolbar.frame),
              @"Y extension meets toolbar edge without overlap");
        Check(!c.charts[0].showsXLabels && c.charts[1].showsXLabels &&
                  fabs(c.charts[0].plotRect.size.height - c.charts[1].plotRect.size.height) < 1 &&
                  app.ySelects[1].frame.origin.x >= 16 && app.yLabels[1].frame.origin.x >= 6,
              @"only bottom plot labels shared X and added Y rows have label padding");
        Bounds unchanged = c.charts[1].range;
        [app.ySelects[0] selectItemWithTitle:@"X"];
        [app action:app.ySelects[0]];
        Bounds after = c.charts[1].range;
        Check([c.ys[0] isEqual:@"X"] && [c.charts[0].yName isEqual:@"X"] &&
                  memcmp(&unchanged, &after, sizeof(Bounds)) == 0,
              @"each selector edits its own plot and preserves other ranges");
        [app.yRemoves[1] performClick:nil];
        Check(c.charts.count == 1 && app.ySelects.count == 1 && app.toolbar.frame.size.height == 34,
              @"minus removes plot and collapses toolbar");
        Check(c.charts[0].showsXLabels, @"remaining single plot restores X labels");
        [app.yAdd performClick:nil];
        for (NSView *view in app.toolbar.contentView.subviews)
            if ([view isKindOfClass:IconButton.class])
                Check(view.frame.size.width == view.frame.size.height, @"toolbar hit areas are square");
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
        [c perform:@"duplicate"];
        PlotController *duplicate = app.controllers.lastObject;
        Check(duplicate != c && duplicate.group == c.group && duplicate.selected == c.selected &&
                  [duplicate ranges].count == c.charts.count,
              @"duplicate shares immutable originals and copies plot state");
        [duplicate.window close];
        app.target = c;
        [app updateToolbar];
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
        [c.pin performClick:nil];
        Check(c.window.level == NSFloatingWindowLevel && app.toolbar.level == c.window.level &&
                  c.pin.state == NSControlStateValueOn && [c.pin.toolTip containsString:@"Disable"],
              @"pin click updates floating level, toolbar and release hint");
        [c.pin performClick:nil];
        Check(c.window.level == NSNormalWindowLevel && c.pin.state == NSControlStateValueOff,
              @"second pin click restores normal level");
        NSRect beforeMove = app.toolbar.frame;
        [c.window setFrameOrigin:NSMakePoint(c.window.frame.origin.x + 53, c.window.frame.origin.y - 27)];
        Check(fabs(app.toolbar.frame.origin.x - beforeMove.origin.x - 53) < 1 &&
                  fabs(app.toolbar.frame.origin.y - beforeMove.origin.y + 27) < 1,
              @"AppKit moves toolbar with plot by the same displacement");
        [c.window setContentSize:NSMakeSize(460, 350)];
        Check(fabs(NSMinY(c.window.frame) - NSMaxY(app.toolbar.frame) - 6) < 1, @"resize keeps toolbar gap");
        PlotController *other = [app newPlot:g];
        [other addY];
        Check(app.toolbar.parentWindow == other.window && app.target == other,
              @"focus transfers toolbar ownership");
        NSRect attached = app.toolbar.frame;
        [c.window setFrameOrigin:NSMakePoint(110, 230)];
        Check(NSEqualRects(attached, app.toolbar.frame), @"inactive plot cannot move toolbar");
        Check(app.yStack.parentWindow == app.toolbar, @"extra Y controls attach to toolbar");
        [app.yStack makeKeyWindow];
        [app syncFocus];
        Check(app.target == other && app.yStack.parentWindow == app.toolbar,
              @"extra Y interaction retains plot owner");
        [app.yRemoves[1] performClick:nil];
        [app syncFocus];
        Check(app.target == other && NSApp.keyWindow == other.window && !app.yStack.visible,
              @"removing last extra row restores plot focus");
        [other addY];
        [app.toolbar makeKeyWindow];
        [app syncFocus];
        Check(app.target == other && app.toolbar.parentWindow == other.window,
              @"toolbar interaction retains owner");
        [other.window close];
        Check(app.toolbar.parentWindow == nil && app.yStack.parentWindow == nil,
              @"closing owner detaches toolbar and Y controls");
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
        [NSApp activateIgnoringOtherApps:YES];
        [c.window makeKeyAndOrderFront:nil];
        NSDate *restoreDeadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while ((c.window.miniaturized || !NSApp.isActive || NSApp.keyWindow != c.window) &&
               restoreDeadline.timeIntervalSinceNow > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:[NSDate dateWithTimeIntervalSinceNow:.02]
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (event)
                [NSApp sendEvent:event];
        }
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
