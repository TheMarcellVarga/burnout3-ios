#import <UIKit/UIKit.h>
#include <SDL.h>
#include "SDL_uikitappdelegate.h"

/* SDL2 exposes this delegate subclass hook. Delay SDL_main until the iOS scene
 * has connected, instead of launching it from the legacy app lifecycle. */
@interface SDLUIKitDelegate (TakedawnStartup)
- (void)postFinishLaunch;
@end
@interface TakedawnAppDelegate : SDLUIKitDelegate
@end
@interface TakedawnSceneDelegate : UIResponder <UIWindowSceneDelegate>
@end

@implementation SDLUIKitDelegate (TakedawnDelegateClass)
+ (NSString *)getAppDelegateClassName { return @"TakedawnAppDelegate"; }
@end

@implementation TakedawnAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)options;
    SDL_SetMainReady();
    app.idleTimerDisabled = YES;
    return YES;
}
@end

@implementation TakedawnSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    static BOOL started;
    if (![scene isKindOfClass:UIWindowScene.class] || started) return;
    started = YES;
    SDLUIKitDelegate *delegate = (SDLUIKitDelegate *)UIApplication.sharedApplication.delegate;
    [delegate performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0];
}
@end
