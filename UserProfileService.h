#import <Foundation/Foundation.h>

@interface UserProfileService : NSObject

@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) NSString *email;
@property (nonatomic, strong) NSArray *preferences;

- (instancetype)initWithUsername:(NSString *)username;
- (NSString *)displayNameForUser:(NSString *)userId;
- (void)updatePreferences:(NSDictionary *)preferences completion:(void (^)(BOOL success, NSError *error))completion;
- (NSArray *)fetchFriendsForUser:(NSString *)userId;

@end
