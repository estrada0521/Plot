#import "PlotData.h"
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <math.h>

static NSString *Text(const char *bytes) {
    NSData *data = [NSData dataWithBytes:bytes length:strlen(bytes)];
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s)
        s = [[NSString alloc] initWithData:data encoding:NSShiftJISStringEncoding];
    if (!s)
        s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}
static char *Trim(char *s) {
    while (isspace((unsigned char)*s))
        s++;
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1]))
        s[--n] = 0;
    return s;
}
// CSV quoting is supported for headers and numeric cells, including escaped quotes.
static NSArray<NSString *> *Headers(const char *line, BOOL comma) {
    NSString *s = Text(line);
    if (!comma) {
        NSArray *parts = [s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        return [parts
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *_) {
                return p.length > 0;
            }]];
    }
    NSMutableArray *result = [NSMutableArray new];
    NSMutableString *cell = [NSMutableString new];
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"') {
            if (quoted && i + 1 < s.length && [s characterAtIndex:i + 1] == '"') {
                [cell appendString:@"\""];
                i++;
            } else
                quoted = !quoted;
        } else if (c == ',' && !quoted) {
            [result addObject:[cell stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
            [cell setString:@""];
        } else
            [cell appendFormat:@"%C", c];
    }
    [result addObject:[cell stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    return result;
}
static double Number(char *s, BOOL *valid) {
    s = Trim(s);
    if (*s == '"') {
        s++;
        size_t n = strlen(s);
        if (n && s[n - 1] == '"')
            s[n - 1] = 0;
    }
    if (!*s) {
        *valid = NO;
        return NAN;
    }
    char *end;
    double value = strtod(s, &end);
    while (isspace((unsigned char)*end))
        end++;
    *valid = end != s && !*end;
    return *valid ? value : NAN;
}
static NSUInteger ParseRow(char *line, BOOL comma, double *out, NSUInteger capacity, BOOL *any,
                           BOOL *allNumeric) {
    NSUInteger i = 0;
    *any = NO;
    *allNumeric = YES;
    char *cursor = line;
    while (cursor && (comma || *cursor)) {
        if (!comma) {
            while (isspace((unsigned char)*cursor))
                cursor++;
            if (!*cursor)
                break;
        }
        char *start = cursor;
        if (comma) {
            BOOL quote = NO;
            while (*cursor && (*cursor != ',' || quote)) {
                if (*cursor == '"')
                    quote = !quote;
                cursor++;
            }
        } else
            while (*cursor && !isspace((unsigned char)*cursor))
                cursor++;
        BOOL more = *cursor != 0;
        if (more)
            *cursor++ = 0;
        BOOL valid;
        double v = Number(start, &valid);
        if (i < capacity)
            out[i] = v;
        *any |= !isnan(v);
        *allNumeric &= valid;
        i++;
        if (!more)
            break;
    }
    for (NSUInteger j = i; j < capacity; j++)
        out[j] = NAN;
    return i;
}
static NSError *DataError(NSString *message) {
    return [NSError errorWithDomain:@"PlotData" code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}
@implementation PLDataset
- (NSUInteger)rowCount {
    return self.columns.count ? self.values.length / sizeof(double) / self.columns.count : 0;
}
- (double)valueAtRow:(NSUInteger)row column:(NSUInteger)column {
    return ((const double *)self.values.bytes)[row * self.columns.count + column];
}
+ (instancetype)readPath:(NSString *)path error:(NSError **)error {
    FILE *file = fopen(path.fileSystemRepresentation, "rb");
    if (!file) {
        if (error)
            *error = DataError([NSString stringWithFormat:@"Cannot read %@: %s", path, strerror(errno)]);
        return nil;
    }
    char *line = NULL;
    size_t allocated = 0;
    NSUInteger index = 0, dataLine = NSNotFound, specLine = NSNotFound, rasColumns = 0;
    BOOL ras = [path.pathExtension.lowercaseString isEqual:@"ras"], inRAS = NO;
    NSString *specHeader = nil;
    // First pass discovers sectioned formats without retaining file-sized text or row objects.
    while (getline(&line, &allocated, file) >= 0) {
        char *t = Trim(line);
        if (!strcasecmp(t, "[data]") && dataLine == NSNotFound)
            dataLine = index;
        if (!strncmp(line, "#L", 2) && specLine == NSNotFound) {
            specLine = index;
            specHeader = Text(line + 2);
        }
        if (ras) {
            if (!strncmp(t, "*RAS_INT_START", 14))
                inRAS = YES;
            else if (!strncmp(t, "*RAS_INT_END", 12))
                inRAS = NO;
            else if (inRAS && *t && *t != '*') {
                BOOL any, all;
                rasColumns = MAX(rasColumns, ParseRow(t, NO, NULL, 0, &any, &all));
            }
        }
        index++;
    }
    rewind(file);
    index = 0;
    inRAS = NO;
    BOOL section = !ras && dataLine != NSNotFound, spec = !ras && !section && specLine != NSNotFound;
    BOOL comma = section || (!spec && [path.pathExtension.lowercaseString isEqual:@"csv"]);
    NSArray *columns = nil;
    if (ras && rasColumns) {
        if (rasColumns == 2)
            columns = @[ @"2theta", @"intensity" ];
        else if (rasColumns == 3)
            columns = @[ @"2theta", @"intensity", @"attenuation" ];
        else {
            NSMutableArray *names = [NSMutableArray new];
            for (NSUInteger i = 0; i < rasColumns; i++)
                [names addObject:[NSString stringWithFormat:@"col%lu", i + 1]];
            columns = names;
        }
    } else if (spec)
        columns = Headers(specHeader.UTF8String, NO);
    NSError *allocationError = nil;
    NSMutableData *values = [NSMutableData new];
    double *row = columns.count ? malloc(columns.count * sizeof(double)) : NULL;
    while (getline(&line, &allocated, file) >= 0) {
        @autoreleasepool {
            char *t = Trim(line);
            NSUInteger lineIndex = index++;
            if (!*t)
                continue;
            if (ras) {
                if (!strncmp(t, "*RAS_INT_START", 14)) {
                    inRAS = YES;
                    continue;
                }
                if (!strncmp(t, "*RAS_INT_END", 12)) {
                    inRAS = NO;
                    continue;
                }
                if (!inRAS || *t == '*' || !columns.count)
                    continue;
            } else if (section && lineIndex <= dataLine)
                continue;
            else if (spec && *t == '#')
                continue;
            if (!columns) {
                NSArray *header = Headers(t, comma);
                char *copy = strdup(t);
                BOOL any, numeric;
                NSUInteger count = ParseRow(copy, comma, NULL, 0, &any, &numeric);
                free(copy);
                if (!count)
                    continue;
                if (section || !numeric) {
                    columns = header;
                    row = malloc(columns.count * sizeof(double));
                    continue;
                }
                NSMutableArray *names = [NSMutableArray new];
                for (NSUInteger i = 0; i < count; i++)
                    [names addObject:[NSString stringWithFormat:@"col%lu", i + 1]];
                columns = names;
                row = malloc(count * sizeof(double));
            }
            if (!columns.count)
                continue;
            if (!row) {
                allocationError = DataError(@"Cannot allocate a data row");
                break;
            }
            BOOL any, numeric;
            ParseRow(t, comma, row, columns.count, &any, &numeric);
            // Match legacy behavior: extra cells do not rescue an otherwise empty retained row.
            BOOL keep = NO;
            for (NSUInteger i = 0; i < columns.count; i++)
                keep |= !isnan(row[i]);
            if (keep)
                [values appendBytes:row length:columns.count * sizeof(double)];
        }
    }
    BOOL readError = ferror(file);
    free(row);
    free(line);
    fclose(file);
    if (allocationError) {
        if (error)
            *error = allocationError;
        return nil;
    }
    if (readError || !columns.count || !values.length) {
        if (error)
            *error = DataError(readError ? @"Read failed" : @"No numeric data found");
        return nil;
    }
    NSData *metaData = [NSData dataWithContentsOfFile:[path.stringByDeletingLastPathComponent
                                                          stringByAppendingPathComponent:@"metadata.json"]];
    id metadata = metaData ? [NSJSONSerialization JSONObjectWithData:metaData options:0 error:nil] : nil;
    NSDictionary *meta = [metadata isKindOfClass:NSDictionary.class] ? metadata : @{};
    NSString * (^field)(NSString *) = ^NSString *(NSString *key) {
        id value = meta[key];
        return [value isKindOfClass:NSString.class]
                   ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                   : nil;
    };
    PLDataset *result = [PLDataset new];
    result.path = path;
    result.columns = columns;
    result.values = values;
    NSString *display = field(@"display_name");
    result.name = display.length ? display : path.lastPathComponent;
    NSString *x = field(@"default_x"), *y = field(@"default_y");
    result.defaultX = [columns containsObject:x ?: @""] ? x : columns[0];
    result.defaultY = [columns containsObject:y ?: @""] ? y : columns[MIN(1ul, columns.count - 1)];
    return result;
}
@end
@implementation PLGroup
@end
NSArray<PLGroup *> *PLReadGroups(NSArray<NSString *> *paths, NSMutableArray<NSString *> *errors) {
    NSMutableArray<PLGroup *> *groups = [NSMutableArray new];
    NSMutableSet *seen = [NSMutableSet new];
    for (NSString *input in paths) {
        @autoreleasepool {
            NSString *path = input.stringByStandardizingPath;
            if ([seen containsObject:path])
                continue;
            [seen addObject:path];
            NSError *error;
            PLDataset *d = [PLDataset readPath:path error:&error];
            if (!d) {
                [errors addObject:[NSString stringWithFormat:@"%@: %@", path, error.localizedDescription]];
                continue;
            }
            PLGroup *match = nil;
            for (PLGroup *g in groups)
                if ([g.x isEqual:d.defaultX] && [g.y isEqual:d.defaultY]) {
                    match = g;
                    break;
                }
            if (!match) {
                match = [PLGroup new];
                match.x = d.defaultX;
                match.y = d.defaultY;
                match.items = @[];
                match.columns = d.columns;
                [groups addObject:match];
            }
            match.items = [match.items arrayByAddingObject:d];
            match.columns = [match.columns
                filteredArrayUsingPredicate:[NSPredicate
                                                predicateWithBlock:^BOOL(NSString *name, NSDictionary *_) {
                                                    return [d.columns containsObject:name];
                                                }]];
        }
    }
    // Unshared columns cannot be selected or exported. Release them rather than retaining
    // wide instrument tables when a group only shares a small number of columns.
    for (PLGroup *group in groups) {
        @autoreleasepool {
            NSMutableArray *items = [NSMutableArray new];
            for (PLDataset *source in group.items) {
                if (source.columns.count == group.columns.count) {
                    [items addObject:source];
                    continue;
                }
                NSUInteger count = group.columns.count, stride = source.columns.count, rows = source.rowCount;
                NSMutableData *mapping = [NSMutableData dataWithLength:count * sizeof(NSUInteger)];
                NSUInteger *indices = mapping.mutableBytes;
                for (NSUInteger c = 0; c < count; c++)
                    indices[c] = [source.columns indexOfObject:group.columns[c]];
                NSMutableData *projected = [NSMutableData dataWithLength:rows * count * sizeof(double)];
                double *out = projected.mutableBytes;
                const double *in = source.values.bytes;
                for (NSUInteger r = 0; r < rows; r++)
                    for (NSUInteger c = 0; c < count; c++)
                        out[r * count + c] = in[r * stride + indices[c]];
                PLDataset *d = [PLDataset new];
                d.path = source.path;
                d.name = source.name;
                d.defaultX = source.defaultX;
                d.defaultY = source.defaultY;
                d.columns = group.columns;
                d.values = projected;
                [items addObject:d];
            }
            group.items = items;
        }
    }
    return groups;
}
NSIndexSet *PLFilteredRows(PLDataset *d, NSArray<NSDictionary *> *rules) {
    if (!rules.count)
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, d.rowCount)];
    typedef struct {
        NSUInteger column;
        double min, max;
    } Rule;
    NSMutableData *compiled = [NSMutableData dataWithLength:rules.count * sizeof(Rule)];
    Rule *limits = compiled.mutableBytes;
    NSUInteger count = 0;
    for (NSDictionary *rule in rules) {
        NSUInteger column = [d.columns indexOfObject:rule[@"column"]];
        if (column == NSNotFound)
            continue;
        limits[count++] = (Rule){column, rule[@"min"] ? [rule[@"min"] doubleValue] : -INFINITY,
                                 rule[@"max"] ? [rule[@"max"] doubleValue] : INFINITY};
    }
    const double *values = d.values.bytes;
    NSUInteger stride = d.columns.count, n = d.rowCount, start = NSNotFound;
    NSMutableIndexSet *rows = [NSMutableIndexSet new];
    for (NSUInteger r = 0; r < n; r++) {
        BOOL keep = YES;
        for (NSUInteger i = 0; i < count; i++) {
            double v = values[r * stride + limits[i].column];
            if (!isfinite(v) || v < limits[i].min || v > limits[i].max) {
                keep = NO;
                break;
            }
        }
        if (keep && start == NSNotFound)
            start = r;
        if (!keep && start != NSNotFound) {
            [rows addIndexesInRange:NSMakeRange(start, r - start)];
            start = NSNotFound;
        }
    }
    if (start != NSNotFound)
        [rows addIndexesInRange:NSMakeRange(start, n - start)];
    return rows;
}

static int CompareDouble(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static double Median(double *v, NSUInteger n) {
    qsort(v, n, sizeof(double), CompareDouble);
    return n % 2 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) * .5;
}
NSIndexSet *PLRemoveOutliers(PLDataset *d, NSIndexSet *rows, NSUInteger x, NSArray<NSNumber *> *ys) {
    const double *values = d.values.bytes;
    NSUInteger stride = d.columns.count;
    NSMutableIndexSet *result = [rows mutableCopy];
    NSMutableData *sortedData = [NSMutableData dataWithLength:rows.count * sizeof(NSUInteger)];
    NSUInteger *indices = sortedData.mutableBytes;
    __block NSUInteger count = 0;
    [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        if (isfinite(values[r * stride + x]))
            indices[count++] = r;
    }];
    if (count < 5)
        return result;
    qsort_b(indices, count, sizeof(NSUInteger), ^int(const void *a, const void *b) {
        double aa = values[*(const NSUInteger *)a * stride + x],
               bb = values[*(const NSUInteger *)b * stride + x];
        return aa == bb ? (*(const NSUInteger *)a > *(const NSUInteger *)b) -
                              (*(const NSUInteger *)a < *(const NSUInteger *)b)
                        : (aa > bb) - (aa < bb);
    });
    NSUInteger half = MIN(5ul, (count - 1) / 2);
    for (NSUInteger i = 0; i < count; i++)
        for (NSNumber *column in ys) {
            double y = values[indices[i] * stride + column.unsignedIntegerValue];
            if (!isfinite(y))
                continue;
            double neighborhood[11], deviation[11];
            NSUInteger n = 0;
            for (NSUInteger j = i > half ? i - half : 0; j < MIN(count, i + half + 1); j++) {
                double v = values[indices[j] * stride + column.unsignedIntegerValue];
                if (isfinite(v))
                    neighborhood[n++] = v;
            }
            if (n < 5)
                continue;
            double center = Median(neighborhood, n);
            NSUInteger distinct = 1;
            for (NSUInteger j = 0; j < n; j++) {
                deviation[j] = fabs(neighborhood[j] - center);
                if (j && neighborhood[j] != neighborhood[j - 1])
                    distinct++;
            }
            double mad = Median(deviation, n);
            if ((mad > 0 && fabs(y - center) > 4.5 * 1.4826 * mad) ||
                (mad == 0 && distinct <= 2 && y != center)) {
                [result removeIndex:indices[i]];
                break;
            }
        }
    return result;
}
static NSString *Quote(NSString *s) {
    return [NSString stringWithFormat:@"\"%@\"", [s stringByReplacingOccurrencesOfString:@"\""
                                                                              withString:@"\"\""]];
}
BOOL PLWriteCSV(PLGroup *group, NSArray<NSDictionary *> *rules, NSURL *url, NSError **error) {
    NSString *temp = [url.path.stringByDeletingLastPathComponent
        stringByAppendingPathComponent:[@".plot-export-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    FILE *f = fopen(temp.fileSystemRepresentation, "wb");
    if (!f) {
        if (error)
            *error = DataError(@"Cannot create export file");
        return NO;
    }
    BOOL multiple = group.items.count > 1;
    if (multiple)
        fputs("Dataset,", f);
    for (NSUInteger i = 0; i < group.columns.count; i++)
        fprintf(f, "%s%s", i ? "," : "", Quote(group.columns[i]).UTF8String);
    fputc('\n', f);
    for (PLDataset *d in group.items) {
        NSIndexSet *rows = PLFilteredRows(d, rules);
        for (NSUInteger r = rows.firstIndex; r != NSNotFound; r = [rows indexGreaterThanIndex:r]) {
            if (multiple)
                fprintf(f, "%s,", Quote(d.name).UTF8String);
            for (NSUInteger i = 0; i < group.columns.count; i++) {
                if (i)
                    fputc(',', f);
                double v = [d valueAtRow:r column:[d.columns indexOfObject:group.columns[i]]];
                if (isfinite(v))
                    fprintf(f, "%.17g", v);
            }
            fputc('\n', f);
        }
    }
    BOOL ok = !ferror(f);
    if (fclose(f))
        ok = NO;
    if (ok && rename(temp.fileSystemRepresentation, url.path.fileSystemRepresentation))
        ok = NO;
    if (!ok) {
        unlink(temp.fileSystemRepresentation);
        if (error)
            *error = DataError(@"Could not write CSV");
    }
    return ok;
}
