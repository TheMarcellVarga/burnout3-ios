#import "mobile_preferences.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if(!(condition)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#condition); return 1; } } while(0)
int main(int argc,char **argv) {
    @autoreleasepool {
        /* Optional full-disc validation uses the exact same mobile code. */
        if(argc==3) {
            NSError *error=nil;
            BOOL valid=BO3ValidateGameFolder([NSURL fileURLWithPath:@(argv[1]) isDirectory:YES],
                [NSURL fileURLWithPath:@(argv[2])],nil,&error);
            if(!valid) fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
            return valid ? 0 : 1;
        }
        NSString *suite=[@"dev.burnout3.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *prefs=[[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
        for(NSUInteger i=0;i<BO3MobileSettings().count;i++) CHECK(BO3MobileChoice(prefs,i)==0);
        BO3MobileSetChoice(prefs,0,1); CHECK(BO3MobileChoice(prefs,0)==1);
        [prefs synchronize];
        NSUserDefaults *reloaded=[[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
        CHECK(BO3MobileChoice(reloaded,0)==1);
        [prefs setInteger:99 forKey:@"ios.touch_visibility"]; CHECK(BO3MobileChoice(prefs,3)==0);
        [prefs setObject:@"1" forKey:@"ios.aspect"]; CHECK(BO3MobileChoice(prefs,1)==0);
        BO3MobileSetChoice(prefs,0,-1); BO3MobileSetChoice(prefs,0,99); CHECK(BO3MobileChoice(prefs,0)==1);
        BO3MobileSetChoice(prefs,99,0); CHECK(BO3MobileChoice(prefs,99)==0);
        unsetenv("RECOMP_RENDER_SCALE"); unsetenv("RECOMP_DISPLAY_WIDESCREEN");
        BO3MobileApplyLaunchEnvironment(prefs); CHECK(!strcmp(getenv("RECOMP_RENDER_SCALE"),"2"));
        setenv("RECOMP_RENDER_SCALE","3",1); BO3MobileApplyLaunchEnvironment(prefs);
        CHECK(!strcmp(getenv("RECOMP_RENDER_SCALE"),"3")); /* Explicit diagnostics win. */
        [prefs setObject:@"keep" forKey:@"other.preference"];
        BO3MobileReset(prefs); CHECK(BO3MobileChoice(prefs,0)==0);
        CHECK([[prefs stringForKey:@"other.preference"] isEqualToString:@"keep"]);
        [prefs removePersistentDomainForName:suite];

        NSFileManager *fm=NSFileManager.defaultManager;
        NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        CHECK([fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSURL *game=[root URLByAppendingPathComponent:@"Game"];
        CHECK([fm createDirectoryAtURL:game withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSURL *file=[game URLByAppendingPathComponent:@"Mixed Case.bin"];
        NSURL *manifest=[root URLByAppendingPathComponent:@"test.manifest"];
        CHECK([@"abc" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        CHECK([@"# fixture, contains no game data\nba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad 3 mixed case.bin\n" writeToURL:manifest atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        __block NSUInteger progress=0;
        NSError *error=nil;
        CHECK(!BO3ValidateGameFolder(game,nil,nil,&error));
        BOOL fixtureValid=BO3ValidateGameFolder(game,manifest,^(NSUInteger done,NSUInteger total){progress=done;},&error);
        if(!fixtureValid) fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
        CHECK(fixtureValid);
        CHECK(progress==1);
        NSURL *installed=[root URLByAppendingPathComponent:@"Installed"];
        CHECK(BO3InstallGameFolder(game,installed,manifest,nil,&error));
        CHECK([fm fileExistsAtPath:[installed URLByAppendingPathComponent:@"Mixed Case.bin"].path]);
        CHECK(!BO3InstallGameFolder(game,installed,manifest,nil,&error)); /* Preserve an existing installation. */
        CHECK([[NSString stringWithContentsOfURL:[installed URLByAppendingPathComponent:@"Mixed Case.bin"] encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"abc"]);
        CHECK([@"abd" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        CHECK(!BO3ValidateGameFolder(game,manifest,nil,&error)); CHECK(error!=nil); /* Equal-size corruption. */
        CHECK(!BO3InstallGameFolder(game,[root URLByAppendingPathComponent:@"Rejected"],manifest,nil,&error));
        CHECK(![fm fileExistsAtPath:[root URLByAppendingPathComponent:@"Rejected"].path]);
        for(NSString *name in [fm contentsOfDirectoryAtPath:root.path error:NULL]) CHECK(![name hasPrefix:@".import-"]);
        CHECK([@"ab" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        CHECK(!BO3ValidateGameFolder(game,manifest,nil,&error)); /* Truncated file. */
        CHECK([fm removeItemAtURL:file error:NULL]);
        CHECK(!BO3ValidateGameFolder(game,manifest,nil,&error)); /* Missing file. */
        CHECK([fm createSymbolicLinkAtPath:file.path withDestinationPath:manifest.path error:NULL]);
        CHECK(!BO3ValidateGameFolder(game,manifest,nil,&error)); /* Reject escapes. */
        CHECK([fm removeItemAtURL:file error:NULL]);
        CHECK([@"# empty manifest\n" writeToURL:manifest atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        CHECK(!BO3ValidateGameFolder(game,manifest,nil,&error));
        CHECK([fm removeItemAtURL:root error:NULL]);
        puts("Native preferences and game validation checks passed.");
        return 0;
    }
}
