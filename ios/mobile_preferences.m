#import "mobile_preferences.h"
#import <CommonCrypto/CommonDigest.h>
#include <stdlib.h>

NSArray<NSDictionary *> *BO3MobileSettings(void) {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = [@[
            @{@"key":@"resolution", @"title":@"Render resolution", @"choices":@[@"Original · 640 × 480", @"Sharper · 1280 × 960"],
              @"help":@"Sharper increases detail and GPU load. Original is the tested baseline. Applies when you next start the game.", @"env":@"RECOMP_RENDER_SCALE", @"values":@[@"1",@"2"]},
            @{@"key":@"aspect", @"title":@"Picture shape", @"choices":@[@"Original · 4:3", @"Widescreen · 16:9"],
              @"help":@"Widescreen adjusts the game camera and keeps the HUD in proportion. The full picture fits without cropping its sides. Applies when you next start the game.", @"env":@"RECOMP_DISPLAY_WIDESCREEN", @"values":@[@"0",@"1"]},
            @{@"key":@"touch_size", @"title":@"Control size", @"choices":@[@"Standard", @"Large"],
              @"help":@"Enlarge the buttons and steering area. Changes apply immediately."},
            @{@"key":@"touch_visibility", @"title":@"Control visibility", @"choices":@[@"Subtle", @"Medium", @"High"],
              @"help":@"Controls brighten when pressed. Changes apply immediately."},
            @{@"key":@"auto_gas", @"title":@"Automatic acceleration", @"choices":@[@"Off", @"On"],
              @"help":@"Hold the accelerator automatically during races. Brake overrides it. Changes apply immediately."},
            @{@"key":@"touch_layout", @"title":@"Control layout", @"choices":@[@"Hybrid", @"Xbox prototype"],
              @"help":@"Hybrid combines a stable analog stick with a compact driving cluster. Touch farther from the stick to float its base. Xbox prototype restores the first layout. Changes apply immediately."},
            @{@"key":@"steering_response", @"title":@"Steering response", @"choices":@[@"Standard", @"Gentle", @"Quick"],
              @"help":@"Gentle gives finer steering near the center. Quick turns sooner. Every setting reaches full steering and releases immediately; the D-pad and physical controllers stay unchanged."}
        ] retain];
    });
    return items;
}
static NSString *PreferenceKey(NSUInteger setting) {
    return [@"ios." stringByAppendingString:BO3MobileSettings()[setting][@"key"]];
}
NSInteger BO3MobileChoice(NSUserDefaults *defaults, NSUInteger setting) {
    if (setting >= BO3MobileSettings().count) return 0;
    id value = [defaults objectForKey:PreferenceKey(setting)];
    if (![value isKindOfClass:NSNumber.class]) return 0;
    NSInteger choice = [value integerValue];
    return choice >= 0 && choice < (NSInteger)[BO3MobileSettings()[setting][@"choices"] count] ? choice : 0;
}
void BO3MobileSetChoice(NSUserDefaults *defaults, NSUInteger setting, NSInteger choice) {
    if (setting >= BO3MobileSettings().count || choice < 0 ||
        choice >= (NSInteger)[BO3MobileSettings()[setting][@"choices"] count]) return;
    [defaults setInteger:choice forKey:PreferenceKey(setting)];
}
void BO3MobileReset(NSUserDefaults *defaults) {
    for (NSUInteger i=0; i<BO3MobileSettings().count; ++i) [defaults removeObjectForKey:PreferenceKey(i)];
}
void BO3MobileApplyLaunchEnvironment(NSUserDefaults *defaults) {
    for (NSUInteger i=0; i<BO3MobileSettings().count; ++i) {
        NSDictionary *item = BO3MobileSettings()[i];
        if (item[@"env"]) setenv([item[@"env"] UTF8String], [item[@"values"][BO3MobileChoice(defaults,i)] UTF8String], 0);
    }
    setenv("RECOMP_GFX_HUD_FIX", "1", 0);
    setenv("RECOMP_PRESENT_FIT", "letterbox", 0);
}
static BOOL ValidationError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"Burnout3Import" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
BOOL BO3ValidateGameFolder(NSURL *folder, NSURL *manifest,
    void (^progress)(NSUInteger, NSUInteger), NSError **error) {
    if(!folder || !manifest) return ValidationError(error,@"The game folder or app manifest is missing. Choose a game folder or reinstall the app.");
    NSString *text = [NSString stringWithContentsOfURL:manifest encoding:NSUTF8StringEncoding error:error];
    if (!text) return NO;
    folder=[folder URLByResolvingSymlinksInPath];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    NSDirectoryEnumerator *walk = [fm enumeratorAtPath:folder.path];
    for (NSString *relative in walk) {
        NSURL *url=[folder URLByAppendingPathComponent:relative];
        NSDictionary *attrs=[fm attributesOfItemAtPath:url.path error:error];
        if(!attrs) return NO;
        if([attrs[NSFileType] isEqual:NSFileTypeSymbolicLink])
            return ValidationError(error,@"The folder contains a symbolic link. Choose an extracted game folder with regular files.");
        NSString *key=relative.lowercaseString;
        if (files[key]) return ValidationError(error,@"Two files differ only by letter case. Choose a clean extraction of the USA Xbox game.");
        files[key] = url;
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
        if (line.length && ![line hasPrefix:@"#"]) [entries addObject:line];
    if (!entries.count) return ValidationError(error,@"The app's game manifest is missing or empty. Reinstall the app.");
    NSUInteger done=0;
    for (NSString *line in entries) {
        NSRange first=[line rangeOfString:@" "], second;
        if (first.location==NSNotFound) return ValidationError(error,@"Invalid game manifest.");
        second=[line rangeOfString:@" " options:0 range:NSMakeRange(first.location+1,line.length-first.location-1)];
        if (second.location==NSNotFound) return ValidationError(error,@"Invalid game manifest.");
        NSString *hash=[line substringToIndex:first.location];
        unsigned long long size=[[line substringWithRange:NSMakeRange(first.location+1,second.location-first.location-1)] longLongValue];
        NSString *name=[line substringFromIndex:second.location+1];
        NSURL *url=files[name.lowercaseString];
        NSDictionary *attrs=url ? [fm attributesOfItemAtPath:url.path error:error] : nil;
        if (!attrs || ![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs fileSize]!=size)
            return ValidationError(error,[NSString stringWithFormat:@"Missing or incomplete file: %@. Choose the extracted USA Xbox folder, not an archive or the PS2 edition.",name]);
        NSInputStream *stream=[NSInputStream inputStreamWithURL:url];
        [stream open];
        CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
        uint8_t buffer[65536]; NSInteger n;
        while ((n=[stream read:buffer maxLength:sizeof buffer])>0) CC_SHA256_Update(&ctx,buffer,(CC_LONG)n);
        NSError *readError=n<0 ? [[stream.streamError retain] autorelease] : nil;
        [stream close];
        if (n<0) { if(error) *error=readError; return NO; }
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&ctx);
        NSMutableString *actual=[NSMutableString string];
        for (unsigned i=0;i<sizeof digest;i++) [actual appendFormat:@"%02x",digest[i]];
        if (![actual isEqualToString:hash]) return ValidationError(error,[NSString stringWithFormat:@"File does not match the supported USA Xbox release: %@. Try a clean extraction.",name]);
        if(progress) progress(++done,entries.count);
    }
    return YES;
}

BOOL BO3InstallGameFolder(NSURL *source, NSURL *destination, NSURL *manifest,
    void (^progress)(NSUInteger, NSUInteger), NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *stage=[[destination URLByDeletingLastPathComponent] URLByAppendingPathComponent:
        [@".import-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    BOOL valid=[fm copyItemAtURL:source toURL:stage error:error];
    if(valid) valid=BO3ValidateGameFolder(stage,manifest,progress,error);
    if(valid) {
        /* The runtime folds Xbox paths; the launcher's direct check needs this
         * root executable to have the canonical spelling. */
        NSArray *names=[fm contentsOfDirectoryAtPath:stage.path error:error];
        if(!names) valid=NO;
        for(NSString *name in names) {
            if([name caseInsensitiveCompare:@"default.xbe"]==NSOrderedSame && ![name isEqualToString:@"default.xbe"])
                valid=[fm moveItemAtURL:[stage URLByAppendingPathComponent:name]
                    toURL:[stage URLByAppendingPathComponent:@"default.xbe"] error:error];
        }
    }
    if(valid && [fm fileExistsAtPath:destination.path]) {
        NSArray *names=[fm contentsOfDirectoryAtPath:destination.path error:error];
        if(!names) valid=NO;
        else if(names.count) valid=ValidationError(error,@"A game folder already exists. Its files have been kept. Move it elsewhere in Files before importing another copy.");
        else valid=[fm removeItemAtURL:destination error:error];
    }
    if(valid) valid=[fm moveItemAtURL:stage toURL:destination error:error];
    [fm removeItemAtURL:stage error:NULL];
    return valid;
}
