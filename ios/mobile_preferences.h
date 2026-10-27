#import <Foundation/Foundation.h>

/* Native preferences stay separate from the PS2 port and desktop settings. */
NSArray<NSDictionary *> *BO3MobileSettings(void);
NSInteger BO3MobileChoice(NSUserDefaults *defaults, NSUInteger setting);
void BO3MobileSetChoice(NSUserDefaults *defaults, NSUInteger setting, NSInteger choice);
void BO3MobileReset(NSUserDefaults *defaults);
void BO3MobileApplyLaunchEnvironment(NSUserDefaults *defaults);

/* Verifies every manifest entry, including size and SHA-256. No game data here. */
BOOL BO3ValidateGameFolder(NSURL *folder, NSURL *manifest,
    void (^progress)(NSUInteger done, NSUInteger total), NSError **error);
BOOL BO3InstallGameFolder(NSURL *source, NSURL *destination, NSURL *manifest,
    void (^progress)(NSUInteger done, NSUInteger total), NSError **error);
