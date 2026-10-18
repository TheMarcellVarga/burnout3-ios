#import <UIKit/UIKit.h>

// First-run import and transient startup/error surface. Gameplay hides it.
@interface GameLaunchView : UIView
@property(nonatomic, strong, readonly) UIButton *importButton;
- (void)showImportMessage:(NSString *)message;
- (void)showLoadingMessage:(NSString *)message;
- (void)showMessage:(NSString *)message;
@end
