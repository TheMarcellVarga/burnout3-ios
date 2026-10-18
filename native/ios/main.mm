// UIKit entry point for runtime checks and the optional native game host.
#import <UIKit/UIKit.h>

int RunRuntimeTests();
#ifdef BURNOUT_NATIVE_HOST
UIViewController* CreateNativeBootController(int runtime_status);
#endif

@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@end

@interface ProbeSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
@end

@implementation ProbeSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    const BOOL diagnostics = [NSProcessInfo.processInfo.arguments containsObject:@"--runtime-tests"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--native-boot"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--gpu-tests"];
    const int status = diagnostics ? RunRuntimeTests() : 0;
    fflush(stdout);
    // Persist the on-device result so the Mac can verify it without depending
    // on console attachment or asking the owner to read diagnostic output.
    if (diagnostics) {
    NSDictionary *report = @{
        @"passed": @(status == 0),
        @"exit_code": @(status),
        @"architecture": @"arm64",
        @"os_version": UIDevice.currentDevice.systemVersion,
        @"timestamp": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
        @"bundle_version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"],
        @"scope": @"Math runtime checks only; game startup has a separate report"
    };
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    NSError *writeError = nil;
    if (![data writeToURL:[documents URLByAppendingPathComponent:@"native-runtime-result.json"] options:NSDataWritingAtomic error:&writeError]) {
        NSLog(@"Could not save runtime-check result: %@", writeError);
    }
    }
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
#ifdef BURNOUT_NATIVE_HOST
    UIViewController *controller = CreateNativeBootController(status);
#else
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.text = status == 0
        ? @"Native runtime checks passed.\n\nThe PS2 math runtime ran as compiled ARM64 code.\n\nGame boot and rendering are still under development."
        : @"Native runtime checks failed.\n\nSee the Xcode console for the failing checks.";
    [controller.view addSubview:label];
    UILayoutGuide *safe = controller.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [label.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [label.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor]
    ]];
#endif
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class));
    }
}
