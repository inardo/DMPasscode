//
//  DMPasscode.m
//  DMPasscode
//
//  Created by Dylan Marriott on 20/09/14.
//  Copyright (c) 2014 Dylan Marriott. All rights reserved.
//

#import "DMPasscode.h"
#import "DMPasscodeInternalNavigationController.h"
#import "DMPasscodeInternalViewController.h"
#import "DMKeychain.h"
#ifdef __IPHONE_8_0
#import <LocalAuthentication/LocalAuthentication.h>
#endif

#undef NSLocalizedString
#define NSLocalizedString(key, comment) \
[bundle localizedStringForKey:(key) value:@"" table:@"DMPasscodeLocalisation"]

static DMPasscode* instance;
static const NSString* KEYCHAIN_NAME = @"passcode";
static NSBundle* bundle;

@interface DMPasscode () <DMPasscodeInternalViewControllerDelegate>
@end

@implementation DMPasscode {
    PasscodeCompletionBlock _completion;
    DMPasscodeInternalViewController* _passcodeViewController;
    int _mode; // 0 = setup, 1 = input
    int _count;
    NSString* _prevCode;
}

+ (void)initialize {
    [super initialize];
    instance = [[DMPasscode alloc] init];
    bundle = [DMPasscode bundleWithName:@"DMPasscode.bundle"];
}

+ (NSBundle*)bundleWithName:(NSString*)name {
    NSString* mainBundlePath = [[NSBundle mainBundle] resourcePath];
    NSString* frameworkBundlePath = [mainBundlePath stringByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] fileExistsAtPath:frameworkBundlePath]){
        return [NSBundle bundleWithPath:frameworkBundlePath];
    }
    return nil;
}

#pragma mark - Public
+ (void)setupPasscodeInViewController:(UIViewController *)viewController completion:(PasscodeCompletionBlock)completion {
    [instance setupPasscodeInViewController:viewController completion:completion];
}

+ (void)showPasscodeInViewController:(UIViewController *)viewController completion:(PasscodeCompletionBlock)completion {
    [instance showPasscodeInViewController:viewController completion:completion];
}

+ (void)removePasscode {
    [instance removePasscode];
}

+ (BOOL)isPasscodeSet {
    return [instance isPasscodeSet];
}

#pragma mark - Instance methods
- (void)setupPasscodeInViewController:(UIViewController *)viewController completion:(PasscodeCompletionBlock)completion {
    _completion = completion;
    [self openPasscodeWithMode:0 viewController:viewController];
}

- (void)showPasscodeInViewController:(UIViewController *)viewController completion:(PasscodeCompletionBlock)completion {
    NSAssert([self isPasscodeSet], @"No passcode set");
    _completion = completion;
#ifdef __IPHONE_8_0
    LAContext* context = [[LAContext alloc] init];
    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil]) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:NSLocalizedString(@"", nil) reply:^(BOOL success, NSError* error) {
            if (error) {
                if (error.code == LAErrorUserFallback) {
                    // user fallback, show passcode
                    [self openPasscodeWithMode:1 viewController:viewController];
                } else {
                    // some error, show passcode
                    [self openPasscodeWithMode:1 viewController:viewController];
                }
            } else {
                _completion(success);
            }
        }];
    } else {
        // no touch id available
        [self openPasscodeWithMode:1 viewController:viewController];
    }
#else
    [self openPasscodeWithMode:1 viewController:viewController];
#endif
}

- (void)removePasscode {
    [[DMKeychain defaultKeychain] removeObjectForKey:KEYCHAIN_NAME];
}

- (BOOL)isPasscodeSet {
    BOOL ret = [[DMKeychain defaultKeychain] objectForKey:KEYCHAIN_NAME] != nil;
    return ret;
}

#pragma mark - Private
- (void)openPasscodeWithMode:(int)mode viewController:(UIViewController *)viewController {
    _mode = mode;
    _count = 0;
    _passcodeViewController = [[DMPasscodeInternalViewController alloc] initWithDelegate:self];
    DMPasscodeInternalNavigationController* nc = [[DMPasscodeInternalNavigationController alloc] initWithRootViewController:_passcodeViewController];
    [viewController presentViewController:nc animated:YES completion:nil];
    if (_mode == 0) {
        [_passcodeViewController setInstructions:NSLocalizedString(@"dmpasscode_enter_new_code", nil)];
    } else if (_mode == 1) {
        [_passcodeViewController setInstructions:NSLocalizedString(@"dmpasscode_enter_to_unlock", nil)];
    }
}

#pragma mark - DMPasscodeInternalViewControllerDelegate
- (void)enteredCode:(NSString *)code {
    if (_mode == 0) {
        if (_count == 0) {
            _prevCode = code;
            [_passcodeViewController setInstructions:NSLocalizedString(@"dmpasscode_repeat", nil)];
            [_passcodeViewController reset];
        } else if (_count == 1) {
            if ([code isEqualToString:_prevCode]) {
                [[DMKeychain defaultKeychain] setObject:code forKey:KEYCHAIN_NAME];
                [_passcodeViewController dismissViewControllerAnimated:YES completion:nil];
                _completion(YES);
            } else {
                UIAlertView* errorAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"dmpasscode_not_match", nil) message:nil delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"dmpasscode_okay", nil), nil];
                [errorAlert show];
                [_passcodeViewController dismissViewControllerAnimated:YES completion:nil];
                _completion(NO);
            }
        }
    } else if (_mode == 1) {
        if ([code isEqualToString:[[DMKeychain defaultKeychain] objectForKey:KEYCHAIN_NAME]]) {
            [_passcodeViewController dismissViewControllerAnimated:YES completion:nil];
            _completion(YES);
        } else {
            [_passcodeViewController setErrorMessage:[NSString stringWithFormat:NSLocalizedString(@"dmpasscode_n_left", nil), 2 - _count]];
            [_passcodeViewController reset];
            if (_count >= 2) { // max 3 attempts
                [_passcodeViewController dismissViewControllerAnimated:YES completion:nil];
                _completion(NO);
            }
        }
    }
    _count++;
}

- (void)canceled {
    _completion(NO);
}

@end
