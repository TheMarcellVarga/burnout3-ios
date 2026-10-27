#import <UIKit/UIKit.h>
BOOL BO3ShowLauncher(NSString *documents);
void BO3ShowSettings(UIViewController *host, BOOL inGame);
void BO3ApplyTouchPreferences(void);
void BO3SessionBackground(BOOL background);
void BO3ProfileTick(BOOL drew);
void BO3ProfileStart(void);
BOOL BO3SessionHeld(void);
extern NSString *const BO3SessionDidChangeNotification;
