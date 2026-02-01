#import <Foundation/Foundation.h>

@interface TestService : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *items;

- (instancetype)initWithName:(NSString *)name;
- (NSString *)fetchDataForIdentifier:(NSNumber *)identifier;
- (void)processItems:(NSArray *)items completion:(void (^)(BOOL success))completion;

@end
