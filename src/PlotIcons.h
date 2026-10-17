#import <Cocoa/Cocoa.h>

// Original toolbar SVG geometry (24 × 24), drawn with the original 1.6 stroke.
static NSImage *PlotIcon(NSString *name, BOOL filled) {
    return [NSImage
         imageWithSize:NSMakeSize(24, 24)
               flipped:YES
        drawingHandler:^BOOL(NSRect rect) {
            CGContextRef c = NSGraphicsContext.currentContext.CGContext;
            CGContextScaleCTM(c, rect.size.width / 24, rect.size.height / 24);
            CGContextSetRGBStrokeColor(c, 0, 0, 0, 1);
            CGContextSetLineWidth(c, [@[ @"close", @"minimize", @"pin" ] containsObject:name] ? 1.7 : 1.6);
            CGContextSetLineCap(c, kCGLineCapRound);
            CGContextSetLineJoin(c, kCGLineJoinRound);
#define M(x, y) CGContextMoveToPoint(c, x, y)
#define L(x, y) CGContextAddLineToPoint(c, x, y)
#define C(a, b, d, e, f, g) CGContextAddCurveToPoint(c, a, b, d, e, f, g)
#define O(x, y, r) CGContextAddEllipseInRect(c, CGRectMake((x) - (r), (y) - (r), 2 * (r), 2 * (r)))
#define Z() CGContextClosePath(c)
            if ([name isEqual:@"add"]) {
                M(5, 12);
                L(19, 12);
                M(12, 5);
                L(12, 19);
            } else if ([name isEqual:@"remove"]) {
                M(5, 12);
                L(19, 12);
            } else if ([name isEqual:@"close"]) {
                M(7, 7);
                L(17, 17);
                M(17, 7);
                L(7, 17);
            } else if ([name isEqual:@"minimize"]) {
                M(7, 15.5);
                L(17, 15.5);
            } else if ([name isEqual:@"pin"]) {
                M(12, 22);
                L(12, 17);
                M(9, 8);
                L(9, 4);
                C(9, 3.448, 9.448, 3, 10, 3);
                L(14, 3);
                C(14.552, 3, 15, 3.448, 15, 4);
                L(15, 8);
                M(6, 16);
                L(9, 13);
                L(9, 8);
                L(15, 8);
                L(15, 13);
                L(18, 16);
                Z();
            } else if ([name isEqual:@"open"]) {
                M(3, 6);
                L(9, 6);
                L(11, 8);
                L(21, 8);
                L(21, 18);
                L(3, 18);
                Z();
            } else if ([name isEqual:@"home"]) {
                M(3, 11);
                L(12, 4);
                L(21, 11);
                M(5, 10);
                L(5, 19);
                L(19, 19);
                L(19, 10);
            } else if ([name isEqual:@"undo-view"]) {
                M(9, 7);
                L(4, 12);
                L(9, 17);
                M(4, 12);
                L(14, 12);
                C(17.314, 12, 20, 14.686, 20, 18);
            } else if ([name isEqual:@"redo-view"]) {
                M(15, 7);
                L(20, 12);
                L(15, 17);
                M(20, 12);
                L(10, 12);
                C(6.686, 12, 4, 14.686, 4, 18);
            } else if ([name isEqual:@"pan"]) {
                M(12, 3);
                L(12, 21);
                M(3, 12);
                L(21, 12);
                M(12, 3);
                L(9, 6);
                M(12, 3);
                L(15, 6);
                M(12, 21);
                L(9, 18);
                M(12, 21);
                L(15, 18);
                M(3, 12);
                L(6, 9);
                M(3, 12);
                L(6, 15);
                M(21, 12);
                L(18, 9);
                M(21, 12);
                L(18, 15);
            } else if ([name isEqual:@"zoom"]) {
                O(11, 11, 7);
                M(21, 21);
                L(16.7, 16.7);
            } else if ([name isEqual:@"line"]) {
                M(5, 18);
                L(19, 6);
            } else if ([name isEqual:@"points"]) {
                O(5, 18, 1.8);
                O(12, 12, 1.8);
                O(19, 6, 1.8);
                CGContextSetRGBFillColor(c, 0, 0, 0, 1);
                CGContextFillPath(c);
            } else if ([name isEqual:@"outliers"]) {
                M(4, 5);
                L(20, 5);
                L(14, 12);
                L(14, 19);
                L(10, 19);
                L(10, 12);
                Z();
            } else if ([name isEqual:@"save-image"]) {
                M(12, 4);
                L(12, 14);
                M(8, 11);
                L(12, 15);
                L(16, 11);
                M(5, 19);
                L(19, 19);
            }
            if (filled && [name isEqual:@"pin"]) {
                CGContextSetRGBFillColor(c, 0, 0, 0, 1);
                CGContextDrawPath(c, kCGPathFillStroke);
            } else
                CGContextStrokePath(c);
#undef M
#undef L
#undef C
#undef O
#undef Z
            return YES;
        }];
}
