#import <Foundation/Foundation.h>

@interface FFLogger : NSObject

@property (nonatomic, strong) NSString *logLevel;

- (instancetype)initWithLevel:(NSString *)level;
- (void)log:(NSString *)message;

@end
