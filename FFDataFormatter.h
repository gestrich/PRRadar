#import <Foundation/Foundation.h>

@interface FFDataFormatter : NSObject

@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, copy) NSString *defaultFormat;

- (instancetype)initWithFormat:(NSString *)format;
- (NSString *)formatDate:(NSDate *)date;
- (NSDate *)parseString:(NSString *)dateString;
- (NSArray *)formatDates:(NSArray *)dates;

@end
