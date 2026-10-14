#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern char *plots_read_dataset(const char *path);
extern void plots_free_string(char *value);

static NSString *JSON(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value ?: NSNull.null options:NSJSONWritingFragmentsAllowed error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@interface PlotWindow : NSWindow
@end
@implementation PlotWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return self.parentWindow == nil; }
- (void)sendEvent:(NSEvent *)event {
    NSPoint point = event.locationInWindow;
    if (!self.parentWindow && event.type == NSEventTypeLeftMouseDown &&
        point.x > 78 && point.x < self.frame.size.width - 10 &&
        point.y > self.frame.size.height - 28 && point.y < self.frame.size.height - 10) {
        [self makeKeyAndOrderFront:nil];
        [self performWindowDragWithEvent:event];
        return;
    }
    [super sendEvent:event];
}
@end

@class PlotsApp;
@interface PlotController : NSObject <NSWindowDelegate, WKScriptMessageHandlerWithReply, WKNavigationDelegate>
@property(nonatomic, weak) PlotsApp *app;
@property(nonatomic, strong) PlotWindow *window;
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSString *pendingPath;
@property(nonatomic, strong) NSDictionary *initial;
@property(nonatomic) BOOL loaded;
@property(nonatomic) BOOL isPlot;
- (instancetype)initWithApp:(PlotsApp *)app label:(NSString *)label page:(NSString *)page size:(NSSize)size;
- (void)event:(NSString *)event payload:(id)payload;
@end

@interface PlotsApp : NSObject <NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandlerWithReply, WKNavigationDelegate>
@property(nonatomic, strong) NSMutableDictionary<NSString *, PlotController *> *controllers;
@property(nonatomic, strong) WKWebsiteDataStore *dataStore;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic, strong) PlotWindow *toolbar;
@property(nonatomic, strong) WKWebView *toolbarWeb;
@property(nonatomic, weak) PlotController *toolbarTarget;
@property(nonatomic) CGFloat toolbarGap;
- (PlotController *)newPlot:(NSString *)path initial:(NSDictionary *)initial;
- (PlotController *)active;
- (void)menu:(NSMenuItem *)sender;
- (void)selectPlot:(PlotController *)plot;
- (void)syncFocus;
- (void)placeToolbar;
- (void)updateToolbar:(NSDictionary *)state;
@end

@interface ToolbarWindow : PlotWindow
@end
@implementation ToolbarWindow
- (BOOL)canBecomeMainWindow { return NO; }
@end

@implementation PlotController
- (WKWebView *)makeWeb {
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.websiteDataStore = self.app.dataStore;
    [config.userContentController addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.pageWorld name:@"plots"];
    NSString *script = [NSString stringWithFormat:@"window.plotsLabel=%@;", JSON(self.label)];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    web.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    web.navigationDelegate = self;
    [web setValue:@NO forKey:@"drawsBackground"];
    return web;
}
- (PlotWindow *)makeWindow:(NSSize)size {
    PlotWindow *window = [[PlotWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = NO;
    window.releasedWhenClosed = NO;
    window.delegate = self;
    window.title = @"Plots";
    return window;
}
- (instancetype)initWithApp:(PlotsApp *)app label:(NSString *)label page:(NSString *)page size:(NSSize)size {
    self = [super init];
    if (!self) return nil;
    self.app = app;
    self.label = label;
    self.window = [self makeWindow:size];
    self.web = [self makeWeb];
    self.window.contentView = self.web;
    NSURL *root = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"web"];
    [self.web loadFileURL:[root URLByAppendingPathComponent:page] allowingReadAccessToURL:root];
    self.isPlot = [page isEqual:@"index.html"];
    if (!self.isPlot) {
        self.window.styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
        self.window.minSize = NSMakeSize(220, 150);
    }
    return self;
}
- (void)event:(NSString *)event payload:(id)payload {
    NSString *script = [NSString stringWithFormat:@"window.plotsEvent?.(%@,%@)", JSON(event), JSON(payload)];
    [self.web evaluateJavaScript:script completionHandler:nil];
}
- (void)windowDidMove:(NSNotification *)notification {
    if (self.app.toolbarTarget == self) [self.app placeToolbar];
}
- (void)windowDidResize:(NSNotification *)notification {
    if (self.app.toolbarTarget == self) [self.app placeToolbar];
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self.app selectPlot:self.isPlot ? self : nil];
    [self event:@"focus" payload:@YES];
}
- (void)windowDidResignKey:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.app syncFocus];
        [self event:@"focus" payload:@(NSApp.isActive && (NSApp.keyWindow == self.window || self.app.toolbarTarget == self))];
    });
}
- (void)windowWillMiniaturize:(NSNotification *)notification {
    if (self.app.toolbarTarget == self) [self.app selectPlot:nil];
}
- (void)windowWillClose:(NSNotification *)notification {
    if (self.app.toolbarTarget == self) [self.app selectPlot:nil];
    if ([self.label hasPrefix:@"filter-"]) {
        NSString *source = self.initial[@"source_label"];
        [self.app.controllers[source] event:@"filter-reset" payload:NSNull.null];
    }
    for (NSString *prefix in @[@"filter-", @"axes-"]) {
        [self.app.controllers[[prefix stringByAppendingString:self.label]].window close];
    }
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"plots" contentWorld:WKContentWorld.pageWorld];
    [self.app.controllers removeObjectForKey:self.label];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    handler(action.request.URL.isFileURL ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message replyHandler:(void (^)(id, NSString *))reply {
    NSDictionary *body = message.body;
    NSString *command = body[@"command"];
    NSDictionary *args = body[@"args"];
    id result = NSNull.null;
    NSString *error = nil;
    if ([command isEqual:@"read_dataset"]) {
        char *raw = plots_read_dataset([args[@"path"] UTF8String]);
        NSData *data = [[NSString stringWithUTF8String:raw] dataUsingEncoding:NSUTF8StringEncoding];
        plots_free_string(raw);
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        result = parsed[@"data"];
        error = parsed[@"error"];
    } else if ([command isEqual:@"take_pending_file"]) {
        result = self.pendingPath; self.pendingPath = nil;
    } else if ([command isEqual:@"take_duplicate_init"]) {
        result = self.initial; self.initial = nil;
    } else if ([command isEqual:@"take_filter_init"] || [command isEqual:@"take_axes_init"]) {
        result = self.initial;
    } else if ([command isEqual:@"mark_window_loaded"]) {
        self.loaded = YES;
    } else if ([command isEqual:@"close"]) {
        [self.window close];
    } else if ([command isEqual:@"minimize"]) {
        [self.window miniaturize:nil];
    } else if ([command isEqual:@"is_pinned"]) {
        result = @(self.window.level == NSFloatingWindowLevel);
    } else if ([command isEqual:@"pin"]) {
        self.window.level = [args[@"value"] boolValue] ? NSFloatingWindowLevel : NSNormalWindowLevel;
        if (self.app.toolbarTarget == self) self.app.toolbar.level = self.window.level;
    } else if ([command isEqual:@"resize"]) {
        NSRect frame = self.window.frame;
        CGFloat top = NSMaxY(frame);
        frame.size = NSMakeSize([args[@"width"] doubleValue], [args[@"height"] doubleValue]);
        frame.origin.y = top - frame.size.height;
        [self.window setFrame:frame display:YES];
        if (self.app.toolbarTarget == self) [self.app placeToolbar];
    } else if ([command isEqual:@"scale_factor"]) {
        result = @(self.window.backingScaleFactor);
    } else if ([command isEqual:@"outer_position"]) {
        CGFloat scale = self.window.backingScaleFactor;
        result = @{@"x": @(NSMinX(self.window.frame) * scale), @"y": @((NSMaxY(NSScreen.screens.firstObject.frame) - NSMaxY(self.window.frame)) * scale)};
    } else if ([command isEqual:@"outer_size"]) {
        CGFloat scale = self.window.backingScaleFactor;
        result = @{@"width": @(self.window.frame.size.width * scale), @"height": @(self.window.frame.size.height * scale)};
    } else if ([command isEqual:@"position"]) {
        CGFloat scale = self.window.backingScaleFactor;
        [self.window setFrameTopLeftPoint:NSMakePoint([args[@"x"] doubleValue] / scale, NSMaxY(NSScreen.screens.firstObject.frame) - [args[@"y"] doubleValue] / scale)];
        if (self.app.toolbarTarget == self) [self.app placeToolbar];
    } else if ([command isEqual:@"emit"]) {
        NSString *target = args[@"target"];
        NSArray *receivers = target ? (self.app.controllers[target] ? @[self.app.controllers[target]] : @[]) : self.app.controllers.allValues;
        for (PlotController *receiver in receivers) [receiver event:args[@"event"] payload:args[@"payload"]];
    } else if ([command isEqual:@"open_file"] || [command isEqual:@"save_file"]) {
        NSSavePanel *panel = [command isEqual:@"open_file"] ? NSOpenPanel.openPanel : NSSavePanel.savePanel;
        NSMutableArray *types = [NSMutableArray new];
        for (NSDictionary *filter in args[@"filters"]) for (NSString *ext in filter[@"extensions"]) {
            UTType *type = [UTType typeWithFilenameExtension:ext]; if (type) [types addObject:type];
        }
        panel.allowedContentTypes = types;
        if ([panel isKindOfClass:NSOpenPanel.class]) {
            ((NSOpenPanel *)panel).canChooseDirectories = NO;
            ((NSOpenPanel *)panel).allowsMultipleSelection = NO;
        } else panel.nameFieldStringValue = [args[@"defaultPath"] lastPathComponent] ?: @"data.csv";
        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            reply(response == NSModalResponseOK ? panel.URL.path : NSNull.null, nil);
        }];
        return;
    } else if ([command isEqual:@"write_text_file"]) {
        NSError *err;
        [args[@"content"] writeToFile:args[@"path"] atomically:YES encoding:NSUTF8StringEncoding error:&err];
        error = err.localizedDescription;
    } else if ([command isEqual:@"reveal_in_finder"]) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:args[@"path"]]]];
    } else if ([command isEqual:@"open_with_editor"]) {
        NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
        NSString *editor = args[@"editor"];
        task.arguments = editor.length ? @[@"-a", editor, args[@"path"]] : @[@"-t", args[@"path"]];
        NSError *err; [task launchAndReturnError:&err]; error = err.localizedDescription;
    } else if ([command isEqual:@"copy_path"]) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:args[@"text"] forType:NSPasteboardTypeString];
    } else if ([command isEqual:@"save_panel_image"]) {
        NSString *name = [[args[@"name"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"_"];
        NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *destination = [downloads URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%.0f.png", name, NSDate.date.timeIntervalSince1970]];
        [self.web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *err) {
            if (err) { reply(nil, err.localizedDescription); return; }
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSError *writeError;
            if (![png writeToURL:destination options:NSDataWritingAtomic error:&writeError]) reply(nil, writeError.localizedDescription);
            else reply(destination.path, nil);
        }];
        return;
    } else if ([command isEqual:@"duplicate_plot_window"]) {
        [self.app newPlot:args[@"path"] initial:args];
    } else if ([command isEqual:@"open_filter_window"] || [command isEqual:@"open_axes_window"]) {
        BOOL filter = [command isEqual:@"open_filter_window"];
        NSString *label = [(filter ? @"filter-" : @"axes-") stringByAppendingString:args[@"sourceLabel"]];
        PlotController *popup = self.app.controllers[label];
        if (!popup) {
            popup = [[PlotController alloc] initWithApp:self.app label:label page:filter ? @"filter.html" : @"axes.html" size:filter ? NSMakeSize(300, 360) : NSMakeSize(420, 300)];
            NSMutableDictionary *initial = [args mutableCopy];
            NSDictionary *keys = @{@"sourceLabel": @"source_label", @"xIndex": @"x_index", @"yIndices": @"y_indices", @"xRange": @"x_range", @"yRanges": @"y_ranges", @"twinYName": @"twin_y_name", @"twinYRange": @"twin_y_range"};
            for (NSString *key in keys) if (args[key]) initial[keys[key]] = args[key];
            popup.initial = initial;
            self.app.controllers[label] = popup;
            [popup.window setFrameTopLeftPoint:NSMakePoint(NSMaxX(self.window.frame) + 8, NSMaxY(self.window.frame))];
        }
        [popup.window makeKeyAndOrderFront:nil];
    } else if ([command isEqual:@"update_toolbar"]) {
        if (self.app.toolbarTarget == self) [self.app updateToolbar:args];
    } else error = [@"Unknown native command: " stringByAppendingString:command];
    reply(result ?: NSNull.null, error);
}
@end

@implementation PlotsApp
- (void)makeToolbar {
    self.toolbarGap = 6;
    self.toolbar = [[ToolbarWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 34) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    self.toolbar.delegate = self;
    self.toolbar.title = @"Plot Controls";
    self.toolbar.opaque = NO;
    self.toolbar.backgroundColor = NSColor.clearColor;
    self.toolbar.hasShadow = NO;
    self.toolbar.releasedWhenClosed = NO;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.websiteDataStore = self.dataStore;
    [config.userContentController addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.pageWorld name:@"plots"];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:@"window.plotsLabel='toolbar';" injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    self.toolbarWeb = [[WKWebView alloc] initWithFrame:self.toolbar.contentView.bounds configuration:config];
    self.toolbarWeb.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.toolbarWeb.navigationDelegate = self;
    [self.toolbarWeb setValue:@NO forKey:@"drawsBackground"];
    self.toolbar.contentView = self.toolbarWeb;
    NSURL *root = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"web"];
    [self.toolbarWeb loadFileURL:[root URLByAppendingPathComponent:@"toolbar.html"] allowingReadAccessToURL:root];
}
- (void)selectPlot:(PlotController *)plot {
    if (!NSApp.isActive) plot = nil;
    if (plot == self.toolbarTarget) return;
    PlotController *previous = self.toolbarTarget;
    [previous.window removeChildWindow:self.toolbar];
    [self.toolbar orderOut:nil];
    self.toolbarTarget = plot;
    [previous event:@"focus" payload:@NO];
    if (plot) {
        self.toolbar.level = plot.window.level;
        [plot event:@"focus" payload:@YES];
        [plot event:@"toolbar-refresh" payload:NSNull.null];
    }
}
- (void)syncFocus {
    if (!NSApp.isActive) { [self selectPlot:nil]; return; }
    if (NSApp.keyWindow == self.toolbar) return;
    PlotController *active = [self active];
    [self selectPlot:active.isPlot && !active.window.isMiniaturized ? active : nil];
}
- (void)applicationDidBecomeActive:(NSNotification *)notification { [self syncFocus]; }
- (void)applicationDidResignActive:(NSNotification *)notification { [self selectPlot:nil]; }
- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self.toolbarTarget event:@"focus" payload:@YES];
}
- (void)windowDidResignKey:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self syncFocus]; });
}
- (void)placeToolbar {
    PlotController *plot = self.toolbarTarget;
    if (!plot) return;
    NSRect frame = self.toolbar.frame;
    frame.origin = NSMakePoint(NSMinX(plot.window.frame), NSMinY(plot.window.frame) - self.toolbarGap - frame.size.height);
    [self.toolbar setFrame:frame display:YES];
}
- (void)updateToolbar:(NSDictionary *)state {
    if (!self.toolbarTarget || !NSApp.isActive) return;
    self.toolbarGap = [state[@"gap"] doubleValue];
    [self.toolbar setContentSize:NSMakeSize([state[@"width"] doubleValue], [state[@"height"] doubleValue])];
    [self placeToolbar];
    PlotController *target = self.toolbarTarget;
    [self.toolbarWeb evaluateJavaScript:[NSString stringWithFormat:@"window.plotsToolbar?.(%@)", JSON(state)] completionHandler:^(id result, NSError *error) {
        if (!error && NSApp.isActive && self.toolbarTarget == target) {
            if (self.toolbar.parentWindow != target.window) [target.window addChildWindow:self.toolbar ordered:NSWindowAbove];
            [self.toolbar orderFront:nil];
        }
    }];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    handler(action.request.URL.isFileURL ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message replyHandler:(void (^)(id, NSString *))reply {
    NSString *command = message.body[@"command"];
    NSDictionary *args = message.body[@"args"];
    if ([command isEqual:@"toolbar_ready"]) [self.toolbarTarget event:@"toolbar-refresh" payload:NSNull.null];
    else if ([command isEqual:@"toolbar_action"]) [self.toolbarTarget event:@"toolbar-action" payload:args];
    else if ([command isEqual:@"toolbar_key"]) [self.toolbarTarget event:@"toolbar-key" payload:args];
    else { reply(nil, [@"Unknown toolbar command: " stringByAppendingString:command]); return; }
    reply(NSNull.null, nil);
}
- (PlotController *)active {
    if (NSApp.keyWindow == self.toolbar) return self.toolbarTarget;
    for (PlotController *controller in self.controllers.allValues) {
        if (NSApp.keyWindow == controller.window) return controller;
    }
    return nil;
}
- (PlotController *)newPlot:(NSString *)path initial:(NSDictionary *)initial {
    PlotController *active = [self active];
    PlotController *controller = [[PlotController alloc] initWithApp:self label:[NSString stringWithFormat:@"plot-%lu", (unsigned long)self.sequence++] page:@"index.html" size:NSMakeSize(360, 280)];
    controller.pendingPath = path;
    controller.initial = initial;
    self.controllers[controller.label] = controller;
    NSPoint top = active ? NSMakePoint(NSMinX(active.window.frame) + 28, NSMaxY(active.window.frame) - 28) : NSMakePoint(100, NSMaxY(NSScreen.screens.firstObject.visibleFrame) - 60);
    [controller.window setFrameTopLeftPoint:top];
    [controller.window makeKeyAndOrderFront:nil];
    return controller;
}
- (void)addMenu:(NSMenu *)menu title:(NSString *)title action:(NSString *)action key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(menu:) keyEquivalent:key];
    item.target = self; item.representedObject = action; item.keyEquivalentModifierMask = modifiers;
    [menu addItem:item];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSMenu *bar = [NSMenu new];
    NSEventModifierFlags cmd = NSEventModifierFlagCommand, alt = cmd | NSEventModifierFlagOption, shift = cmd | NSEventModifierFlagShift;
    NSArray *definitions = @[
        @[@"Plots", @[@"Settings…", @"settings", @",", @(cmd)], @[@"Hide Plots", @"hide", @"h", @(cmd)], @[@"Quit Plots", @"quit", @"q", @(cmd)]],
        @[@"File", @[@"New Window", @"new", @"n", @(cmd)], @[@"Duplicate Window", @"duplicate-window", @"", @(cmd)], @[@"Open…", @"open", @"o", @(cmd)], @[@"Reveal in Finder", @"reveal", @"f", @(cmd)], @[@"Open in Editor", @"editor", @"e", @(cmd)], @[@"Copy Path", @"copy-path", @"p", @(cmd)]],
        @[@"Edit", @[@"Undo", @"undo:", @"z", @(cmd)], @[@"Redo", @"redo:", @"z", @(shift)], @[@"Copy", @"copy:", @"c", @(cmd)], @[@"Paste", @"paste:", @"v", @(cmd)], @[@"Select All", @"selectAll:", @"a", @(cmd)]],
        @[@"Tools", @[@"Filter…", @"filter", @"f", @(alt)], @[@"Axes…", @"axes", @"g", @(alt | NSEventModifierFlagShift)], @[@"Add Twin Data…", @"add-twin-data", @"d", @(alt | NSEventModifierFlagShift)], @[@"Exclude Outliers", @"toggle-outliers", @"r", @(alt)]],
        @[@"Window", @[@"Minimize", @"minimize", @"m", @(cmd)], @[@"Next Window", @"next", @"`", @(cmd)], @[@"Previous Window", @"previous", @"`", @(shift)], @[@"Arrange Windows", @"arrange", @"a", @(alt)], @[@"Cascade Windows", @"cascade", @"a", @(alt | NSEventModifierFlagShift)]]
    ];
    for (NSArray *definition in definitions) {
        NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:definition[0] action:nil keyEquivalent:@""];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:definition[0]];
        for (NSArray *entry in [definition subarrayWithRange:NSMakeRange(1, definition.count - 1)]) {
            NSString *action = entry[1];
            if ([action hasSuffix:@":"]) {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(action) keyEquivalent:entry[2]];
                item.keyEquivalentModifierMask = [entry[3] unsignedIntegerValue]; [menu addItem:item];
            } else [self addMenu:menu title:entry[0] action:action key:entry[2] modifiers:[entry[3] unsignedIntegerValue]];
        }
        root.submenu = menu; [bar addItem:root];
    }
    NSApp.mainMenu = bar;
    [self makeToolbar];
    if (!self.controllers.count) [self newPlot:nil initial:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)menu:(NSMenuItem *)sender {
    NSString *action = sender.representedObject;
    PlotController *active = [self active];
    if ([action isEqual:@"quit"]) [NSApp terminate:nil];
    else if ([action isEqual:@"hide"]) [NSApp hide:nil];
    else if ([action isEqual:@"new"]) [self newPlot:nil initial:nil];
    else if ([action isEqual:@"minimize"]) [active.window miniaturize:nil];
    else if ([action isEqual:@"settings"]) {
        PlotController *settings = self.controllers[@"settings"];
        if (!settings) {
            settings = [[PlotController alloc] initWithApp:self label:@"settings" page:@"settings.html" size:NSMakeSize(360, 156)];
            self.controllers[@"settings"] = settings; [settings.window center];
        }
        [settings.window makeKeyAndOrderFront:nil];
    } else if ([action isEqual:@"next"] || [action isEqual:@"previous"]) {
        NSArray *labels = [self.controllers.allKeys sortedArrayUsingSelector:@selector(compare:)];
        if (!labels.count) return;
        NSUInteger index = [labels indexOfObject:active.label];
        if (index == NSNotFound) index = 0;
        index = (index + labels.count + ([action isEqual:@"next"] ? 1 : -1)) % labels.count;
        [self.controllers[labels[index]].window makeKeyAndOrderFront:nil];
    } else if ([action isEqual:@"arrange"] || [action isEqual:@"cascade"]) {
        NSRect area = NSScreen.screens.firstObject.visibleFrame;
        CGFloat x = NSMinX(area) + 12, y = NSMaxY(area) - 12, rowHeight = 0;
        for (NSString *label in [self.controllers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            PlotController *controller = self.controllers[label];
            CGFloat width = controller.window.frame.size.width;
            CGFloat height = controller.window.frame.size.height;
            if ([action isEqual:@"arrange"] && x + width > NSMaxX(area) && x > NSMinX(area) + 12) { x = NSMinX(area) + 12; y -= rowHeight + 12; rowHeight = 0; }
            [controller.window setFrameTopLeftPoint:NSMakePoint(x, y)];
            if ([action isEqual:@"cascade"]) { x += 28; y -= 28; }
            else { x += width + 12; rowHeight = MAX(rowHeight, height); }
        }
    } else [active event:@"menu-action" payload:action];
}
- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames {
    NSArray *empty = [self.controllers.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PlotController *controller, NSDictionary *bindings) { return controller.isPlot && !controller.loaded && !controller.pendingPath; }]];
    for (NSString *path in filenames) [self newPlot:path initial:nil];
    for (PlotController *controller in empty) [controller.window close];
    [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (!visible) [self newPlot:nil initial:nil];
    return YES;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        PlotsApp *delegate = [PlotsApp new];
        delegate.controllers = [NSMutableDictionary new];
        delegate.dataStore = WKWebsiteDataStore.defaultDataStore;
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
