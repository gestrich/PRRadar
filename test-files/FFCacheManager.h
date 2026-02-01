#import <Foundation/Foundation.h>

@interface FFCacheManager : NSObject

@property (nonatomic, strong) NSString *cacheDirectory;

- (instancetype)initWithDirectory:(NSString *)directory;
- (void)clearCache;

@end
