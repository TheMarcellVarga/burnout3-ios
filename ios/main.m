#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#import "mobile_shell.h"
#import "mobile_preferences.h"

int bo3_game_main(int argc, char **argv);
void bo3_ios_attach_touch(void);

/* SDL2's iOS entry point owns UIApplication and calls this on its main thread.
 * Keep the Xbox runtime's window/event loop there, and the title on its worker.
 * Game data is supplied separately in Documents/Burnout 3 Takedown for the prototype. */
int SDL_main(int argc, char **argv)
{
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *data = [docs stringByAppendingPathComponent:@"Burnout 3 Takedown"];
        NSString *saves = [docs stringByAppendingPathComponent:@"Saves"];
        NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *path in @[data, saves, cache])
            [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
        setenv("RECOMP_SAVE_DIR", saves.fileSystemRepresentation, 1);
        setenv("RECOMP_CACHE_DIR", cache.fileSystemRepresentation, 1);
        setenv("RECOMP_STDIO_LOG", [[docs stringByAppendingPathComponent:@"takedawn.log"] fileSystemRepresentation], 1);
        /* Keep normal phone sessions quiet. Explicit diagnostic switches
         * still enable logs for a bounded device test. */
        if (!getenv("RECOMP_LOG_DIAG") && !getenv("RECOMP_TRACE") && !getenv("RECOMP_DEBUG"))
            setenv("RECOMP_LOG_DIAG", "0", 1);
        setenv("RECOMP_PB_BACKEND", "metal", 1);
        setenv("RECOMP_PRESENT_VSYNC", "1", 1);
        /* Short phone comparison: 4 ms retained ~16.8 ms p95 guest flips
         * while reducing menu CPU work versus the inherited 8 ms lead.
         * Explicit diagnostic overrides still win. */
        setenv("RECOMP_PRESENT_SPIN_LEAD", "4", 0);
        setenv("RECOMP_WINDOW_SCALE", "1", 1);
        setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1);
        SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
        SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
        if (!BO3ShowLauncher(docs)) return 3;
        BO3MobileApplyLaunchEnvironment(NSUserDefaults.standardUserDefaults);
        if (![fm fileExistsAtPath:[data stringByAppendingPathComponent:@"default.xbe"]]) {
            SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION, "Burnout 3 iOS",
                "Game data is missing. Supply the supported USA Xbox files in Documents/Burnout 3 Takedown using Files or Finder.", NULL);
            return 3;
        }
        char **args = calloc((size_t)argc + 5, sizeof(char *));
        args[0] = argv[0];
        if (chdir(docs.fileSystemRepresentation) != 0) return 4;
        args[1] = "--no-setup";
        for (int i = 1; i < argc; ++i) args[i + 1] = argv[i];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ bo3_ios_attach_touch(); });
        int rc = bo3_game_main(argc + 1, args);
        free(args);
        return rc;
    }
}
