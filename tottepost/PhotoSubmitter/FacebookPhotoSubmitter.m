//
//  FacebookPhotoSubmitter.m
//  tottepost
//
//  Created by ISHITOYA Kentaro on 11/12/13.
//  Copyright (c) 2011 cocotomo. All rights reserved.
//

#import "PhotoSubmitterAPIKey.h"
#import "FacebookPhotoSubmitter.h"
#import "UIImage+Digest.h"
#import "RegexKitLite.h"

#define PS_FACEBOOK_ENABLED @"PSFacebookEnabled"
#define PS_FACEBOOK_AUTH_TOKEN @"FBAccessTokenKey"
#define PS_FACEBOOK_AUTH_EXPIRATION_DATE @"FBExpirationDateKey"
#define PS_FACEBOOK_SETTING_USERNAME @"FBUsername"

//-----------------------------------------------------------------------------
//Private Implementations
//-----------------------------------------------------------------------------
@interface FacebookPhotoSubmitter(PrivateImplementation)
- (void) setupInitialState;
- (void) clearCredentials;
- (void) getUserInfomation;
@end

@implementation FacebookPhotoSubmitter(PrivateImplementation)
#pragma mark -
#pragma mark private implementations
/*!
 * initializer
 */
-(void)setupInitialState{
    facebook_ = [[Facebook alloc] initWithAppId:PHOTO_SUBMITTER_FACEBOOK_API_ID andDelegate:self];
    if ([self settingExistsForKey:PS_FACEBOOK_AUTH_TOKEN] 
        && [self settingExistsForKey:PS_FACEBOOK_AUTH_EXPIRATION_DATE]) {
        facebook_.accessToken = [self settingForKey:PS_FACEBOOK_AUTH_TOKEN];
        facebook_.expirationDate = [self settingForKey:PS_FACEBOOK_AUTH_EXPIRATION_DATE];
    }
}

/*!
 * clear facebook access token key
 */
- (void)clearCredentials{
    if ([self settingExistsForKey:PS_FACEBOOK_AUTH_TOKEN]) {
        [self removeSettingForKey:PS_FACEBOOK_AUTH_TOKEN];
        [self removeSettingForKey:PS_FACEBOOK_AUTH_EXPIRATION_DATE];
    } 
    [self disable];
}

/*!
 * get user information
 */
- (void)getUserInfomation{
    [facebook_ requestWithGraphPath:@"me" andDelegate:self];
}

#pragma mark -
#pragma mark facebook delegates
/*!
 * facebook delegate, did login suceeded
 */
- (void)fbDidLogin {
    [self setSetting:[facebook_ accessToken] forKey:PS_FACEBOOK_AUTH_TOKEN];
    [self setSetting:[facebook_ expirationDate] forKey:PS_FACEBOOK_AUTH_EXPIRATION_DATE];
    [self setSetting:@"enabled" forKey:PS_FACEBOOK_ENABLED];
    [self.authDelegate photoSubmitter:self didLogin:self.type];
    
    [self getUserInfomation];
}

/*!
 * facebook delegate, if not login
 */
-(void)fbDidNotLogin:(BOOL)cancelled {
    [self clearCredentials];
    [self.authDelegate photoSubmitter:self didLogout:self.type];
}

/*!
 * facebook delegate, if logout
 */
- (void) fbDidLogout {
    [self clearCredentials];
    [self.authDelegate photoSubmitter:self didLogout:self.type];
}

/*!
 * facebook request delegate, did receive response
 */
- (void)request:(FBRequest *)request didReceiveResponse:(NSURLResponse *)response {
};

/*!
 * facebook request delegate, did load
 */
- (void)request:(FBRequest *)request didLoad:(id)result {
	if ([result isKindOfClass:[NSArray class]]) {
		result = [result objectAtIndex:0];
	}
    if([request.url isMatchedByRegex:@"me$"]){
        self.username = [[result objectForKey:@"name"] stringByReplacingOccurrencesOfRegex:@" +" withString:@" "];
        NSLog(@"%@", self.username);
    }else if([request.url isMatchedByRegex:@"photos$"]){
        NSString *hash = [self photoForRequest:request];
        if ([result objectForKey:@"owner"]) {
            [self photoSubmitter:self didSubmitted:hash suceeded:YES message:@"Photo upload succeeded"];
        } else {
            [self photoSubmitter:self didSubmitted:hash suceeded:NO message:[result objectForKey:@"name"]];
        }
    
        id<PhotoSubmitterOperationDelegate> operationDelegate = [self operationDelegateForRequest:request];
        [operationDelegate photoSubmitterDidOperationFinished];
        [self clearRequest:request];
    }
};

/*!
 * facebook request delegate, did fail
 */
- (void)request:(FBRequest *)request didFailWithError:(NSError *)error {
    NSString *hash = [self photoForRequest:request];
    [self photoSubmitter:self didSubmitted:hash suceeded:NO message:[error localizedDescription]];
    id<PhotoSubmitterOperationDelegate> operationDelegate = [self operationDelegateForRequest:request];
    [operationDelegate photoSubmitterDidOperationFinished];
    [self clearRequest:request];
};

/*!
 * facebook request delegate, upload progress
 */
- (void)request:(FBRequest *)request didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite{
    CGFloat progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    NSString *hash = [self photoForRequest:request];
    [self photoSubmitter:self didProgressChanged:hash progress:progress];
}
@end

//-----------------------------------------------------------------------------
//Public Implementations
//-----------------------------------------------------------------------------
@implementation FacebookPhotoSubmitter
@synthesize authDelegate;
#pragma mark -
#pragma mark public PhotoSubmitter Protocol implementations
/*!
 * initialize
 */
- (id)init{
    self = [super init];
    if (self) {
        [self setupInitialState];
    }
    return self;
}

/*!
 * submit photo with comment
 */
- (void)submitPhoto:(UIImage *)photo comment:(NSString *)comment andDelegate:(id<PhotoSubmitterOperationDelegate>)delegate{
    NSMutableDictionary *params = 
      [NSMutableDictionary dictionaryWithObjectsAndKeys: 
       photo, @"source", 
       comment, @"name",
       nil];
    FBRequest *request = [facebook_ requestWithGraphPath:@"me/photos" andParams:params andHttpMethod:@"POST" andDelegate:self];
    /*FBRequest *request =
      [facebook_ requestWithMethodName:@"photos.upload"
                             andParams:params
                         andHttpMethod:@"POST"
                           andDelegate:self];*/
    NSString *hash = photo.MD5DigestString;
    [self setPhotoHash:hash forRequest:request];
    [self setOperationDelegate:delegate forRequest:request];
    [self photoSubmitter:self willStartUpload:hash];
}

/*!
 * login to facebook
 */
-(void)login{
    if (![facebook_ isSessionValid]) {
        NSArray *permissions = 
        [NSArray arrayWithObjects:@"publish_stream", @"user_photos", @"offline_access", nil];
        [facebook_ authorize:permissions];
    }else{
        [self setSetting:@"enabled" forKey:PS_FACEBOOK_ENABLED];
        [self.authDelegate photoSubmitter:self didLogin:self.type];
    }
}

/*!
 * logoff from facebook
 */
- (void)logout{
    [facebook_ logout:self];   
    [self clearCredentials];
}

/*!
 * disable
 */
- (void)disable{
    [self removeSettingForKey:PS_FACEBOOK_ENABLED];
    [self.authDelegate photoSubmitter:self didLogout:self.type];
}

/*!
 * check is logined
 */
- (BOOL)isLogined{
    if(self.isEnabled == false){
        return NO;
    }
    if ([self settingExistsForKey:PS_FACEBOOK_AUTH_TOKEN]) {
        return YES;
    }
    return NO;
}

/*!
 * check is enabled
 */
- (BOOL) isEnabled{
    return [FacebookPhotoSubmitter isEnabled];
}

/*!
 * return type
 */
- (PhotoSubmitterType) type{
    return PhotoSubmitterTypeFacebook;
}

/*!
 * check url is processoble
 */
- (BOOL)isProcessableURL:(NSURL *)url{
    if([url.absoluteString isMatchedByRegex:@"^fb[0-9]+"]){
        return YES;
    }
    return NO;
}

/*!
 * on open url finished
 */
- (BOOL)didOpenURL:(NSURL *)url{
    return [facebook_ handleOpenURL:url];
}

/*!
 * name
 */
- (NSString *)name{
    return @"Facebook";
}

/*!
 * icon image
 */
- (UIImage *)icon{
    return [UIImage imageNamed:@"facebook_32.png"];
}

/*!
 * small icon image
 */
- (UIImage *)smallIcon{
    return [UIImage imageNamed:@"facebook_16.png"];
}

/*!
 * get username
 */
- (NSString *)username{
    return [self settingForKey:PS_FACEBOOK_SETTING_USERNAME];
}

/*!
 * save username
 */
- (void)setUsername:(NSString *)username{
    [self setSetting:username forKey:PS_FACEBOOK_SETTING_USERNAME];
}


/*!
 * isEnabled
 */
+ (BOOL)isEnabled{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:PS_FACEBOOK_ENABLED]) {
        return YES;
    }
    return NO;
}

#pragma mark -
#pragma mark Facebook information methods
@end
