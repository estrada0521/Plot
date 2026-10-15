#import <Foundation/Foundation.h>

@interface PLDataset : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSArray<NSString *> *columns;
@property(nonatomic, copy) NSString *defaultX;
@property(nonatomic, copy) NSString *defaultY;
@property(nonatomic, strong) NSData *values; // row-major doubles, NaN for missing cells
@property(nonatomic, readonly) NSUInteger rowCount;
- (double)valueAtRow:(NSUInteger)row column:(NSUInteger)column;
+ (instancetype)readPath:(NSString *)path error:(NSError **)error;
@end

@interface PLGroup : NSObject
@property(nonatomic, copy) NSArray<PLDataset *> *items;
@property(nonatomic, copy) NSArray<NSString *> *columns;
@property(nonatomic, copy) NSString *x;
@property(nonatomic, copy) NSString *y;
@end
NSArray<PLGroup *> *PLReadGroups(NSArray<NSString *> *paths, NSMutableArray<NSString *> *errors);
NSIndexSet *PLFilteredRows(PLDataset *dataset, NSArray<NSDictionary *> *rules);
NSIndexSet *PLRemoveOutliers(PLDataset *dataset, NSIndexSet *rows, NSUInteger x, NSArray<NSNumber *> *ys);
BOOL PLWriteCSV(PLGroup *group, NSArray<NSDictionary *> *rules, NSURL *url, NSError **error);
