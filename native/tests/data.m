#import "../PlotData.h"
#include <math.h>
static NSUInteger checks = 0;
static void Check(BOOL ok, NSString *message) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
    checks++;
}
static NSString *Write(NSString *root, NSString *relative, NSString *text) {
    NSString *path = [root stringByAppendingPathComponent:relative];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}
static PLDataset *Read(NSString *path) {
    NSError *error;
    PLDataset *d = [PLDataset readPath:path error:&error];
    Check(d != nil, error.localizedDescription ?: @"read");
    return d;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[@"plot-data-test-"
                                               stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *csv = Write(root, @"a/data.csv", @"Field,Moment,Extra\n1,10,99\n2,,88\n3,30,77\n");
        Write(root, @"a/metadata.json",
              @"{\"default_x\":\"Field\",\"default_y\":\"Moment\",\"display_name\":\"A\"}");
        PLDataset *d = Read(csv);
        Check(d.rowCount == 3 && d.columns.count == 3 && isnan([d valueAtRow:1 column:1]),
              @"CSV missing cell preserved");
        Check([d.name isEqual:@"A"] && [d.defaultX isEqual:@"Field"] && [d.defaultY isEqual:@"Moment"],
              @"metadata defaults");
        PLDataset *table = Read(Write(root, @"plain.dat", @"1 2\n3\n4 5 6\n\n"));
        Check([table.columns isEqual:@[ @"col1", @"col2" ]] && table.rowCount == 3 &&
                  isnan([table valueAtRow:1 column:1]),
              @"headerless table, short/long rows");
        PLDataset *section = Read(Write(root, @"mpms.dat", @"MPMS header\n[Data]\nField,Moment\n1,2\n2,3\n"));
        Check([section.columns isEqual:@[ @"Field", @"Moment" ]] && section.rowCount == 2, @"MPMS [Data]");
        PLDataset *spec =
            Read(Write(root, @"scan.txt", @"#F test\n#L Theta Intensity\n1 10\n# comment\n2 20\n"));
        Check([spec.columns isEqual:@[ @"Theta", @"Intensity" ]] && spec.rowCount == 2, @"SPEC #L");
        PLDataset *ras =
            Read(Write(root, @"scan.ras", @"*RAS_HEADER_START\n*RAS_INT_START\n1 2\n2 3 4\n*RAS_INT_END\n"));
        Check([ras.columns isEqual:@[ @"2theta", @"intensity", @"attenuation" ]] && ras.rowCount == 2 &&
                  isnan([ras valueAtRow:0 column:2]),
              @"RAS variable width");
        PLDataset *quoted = Read(Write(root, @"quoted.csv", @"\"X, field\",\"Y\"\n1,\"2\"\n"));
        Check([quoted.columns[0] isEqual:@"X, field"] && [quoted valueAtRow:0 column:1] == 2,
              @"quoted CSV headers/cells");
        PLDataset *nanFirst = Read(Write(root, @"nan-first.csv", @"NaN,1\n2,3\n"));
        Check(nanFirst.rowCount == 2 && [nanFirst.columns[0] isEqual:@"col1"] &&
                  isnan([nanFirst valueAtRow:0 column:0]),
              @"headerless NaN first row");
        PLDataset *precision = Read(Write(root, @"precision.csv", @"X,Y\n1.0000000000000002,2\n"));
        Check([precision valueAtRow:0 column:0] == nextafter(1., 2.), @"64-bit numeric precision");
        NSError *error;
        Check([PLDataset readPath:Write(root, @"empty.csv", @"X,Y\n,\na,b\n") error:&error] == nil,
              @"empty/non-numeric files rejected");
        Write(root, @"bad/metadata.json", @"[1,2]");
        PLDataset *bad = Read(Write(root, @"bad/data.csv", @"X,Y\n1,2\n"));
        Check([bad.defaultX isEqual:@"X"], @"malformed metadata ignored");
        Write(root, @"b/metadata.json", @"{\"default_x\":\"Field\",\"default_y\":\"Moment\"}");
        NSString *b = Write(root, @"b/data.csv", @"Moment,Field\n20,2\n");
        NSMutableArray *errors = [NSMutableArray new];
        NSArray<PLGroup *> *groups =
            PLReadGroups(@[ csv, b, csv, [root stringByAppendingPathComponent:@"missing.csv"] ], errors);
        Check(groups.count == 1 && groups[0].items.count == 2 && errors.count == 1,
              @"grouping, deduplication and partial errors");
        Check([groups[0].columns isEqual:@[ @"Field", @"Moment" ]],
              @"shared columns retain first-file order");
        Check(groups[0].items[0].columns.count == 2 &&
                  groups[0].items[0].values.length == 3 * 2 * sizeof(double),
              @"unshared columns released without losing rows");
        PLDataset *second = groups[0].items[1];
        Check([second valueAtRow:0 column:[second.columns indexOfObject:@"Moment"]] == 20,
              @"column alignment without data copies");
        Write(root, @"c/metadata.json", @"{\"default_x\":\"Moment\",\"default_y\":\"Field\"}");
        NSString *c = Write(root, @"c/data.csv", @"Field,Moment\n1,2\n");
        Check(PLReadGroups(@[ csv, c ], [NSMutableArray new]).count == 2,
              @"different defaults remain separate");
        NSArray *rules = @[ @{@"column" : @"Moment", @"min" : @15} ];
        NSIndexSet *rows = PLFilteredRows(d, rules);
        Check(rows.count == 1 && rows.firstIndex == 2 && d.rowCount == 3,
              @"filter missing cells without mutating data");
        PLDataset *out = Read(Write(root, @"outlier.csv", @"X,Y\n0,1\n1,1\n2,1\n3,100\n4,1\n5,1\n6,1\n"));
        NSIndexSet *kept = PLRemoveOutliers(out, PLFilteredRows(out, @[]), 0, @[ @1 ]);
        Check(kept.count == 6 && ![kept containsIndex:3], @"Hampel zero-MAD isolated spike");
        PLGroup *g = groups[0];
        NSURL *export = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"export.csv"]];
        Check(PLWriteCSV(g, @[], export, &error), @"CSV export");
        PLDataset *roundtrip = Read(export.path);
        Check(roundtrip.rowCount == 4 && roundtrip.columns.count == 3 &&
                  [roundtrip.columns[0] isEqual:@"Dataset"],
              @"combined CSV labels and row count");
        Check([d valueAtRow:0 column:1] == 10, @"export leaves original values unchanged");
        // Optional real fixtures also exercise non-UTF8 scientific headers.
        for (int i = 1; i < argc; i++) {
            PLDataset *real = Read(@(argv[i]));
            Check(real.rowCount > 0 && real.columns.count >= 2, @"real scientific file");
            printf("REAL: %s: %lu rows, %lu columns\n", real.name.UTF8String, real.rowCount,
                   real.columns.count);
        }
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        printf("PASS: %lu data checks\n", checks);
    }
    return 0;
}
