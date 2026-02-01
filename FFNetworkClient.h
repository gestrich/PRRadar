//
//  FFNetworkClient.h
//  Network client for API requests
//

#import <Foundation/Foundation.h>

@class FFNetworkResponse;

@interface FFNetworkClient : NSObject

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, strong) NSDictionary *defaultHeaders;

- (instancetype)initWithBaseURL:(NSString *)baseURL;

- (void)GET:(NSString *)endpoint
 completion:(void (^)(FFNetworkResponse *response, NSError *error))completion;

- (void)POST:(NSString *)endpoint
        body:(NSDictionary *)body
  completion:(void (^)(FFNetworkResponse *response, NSError *error))completion;

- (NSArray *)pendingRequests;

- (void)cancelAllRequests;

@end
