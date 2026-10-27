#import "mobile_shell.h"
#import "mobile_preferences.h"
#include "session_guard.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdlib.h>
#include <string.h>
#define BOOL XBOX_BOOL
#include "input/touch_pad.h"
#include "input/input_backend.h"
#include "kernel/kernel_pause.h"
#undef BOOL

static bo3_session_guard session;
NSString *const BO3SessionDidChangeNotification=@"BO3SessionDidChange";
BOOL BO3SessionHeld(void) { return session.reasons!=0; }
static void SessionActions(unsigned actions) {
    if(actions&BO3_SESSION_BLOCK) { xbox_InputTouchReleaseAll(); xbox_InputSetBlocked(1); }
    if(actions&BO3_SESSION_PAUSE) xbox_HostPause(1);
    if(actions&BO3_SESSION_UNBLOCK) xbox_InputSetBlocked(0);
    if(actions&BO3_SESSION_RESUME) xbox_HostPause(0);
    if(actions) [NSNotificationCenter.defaultCenter postNotificationName:BO3SessionDidChangeNotification object:nil];
}
static void SessionHold(unsigned reason) { SessionActions(bo3_session_hold(&session,reason,xbox_HostPaused())); }
static void SessionRelease(unsigned reason) { SessionActions(bo3_session_release(&session,reason)); }
void BO3SessionBackground(BOOL background) {
    if(background) SessionHold(BO3_HOLD_BACKGROUND); else SessionRelease(BO3_HOLD_BACKGROUND);
}
static void ShowSessionLauncher(UIViewController *host);
void bo3_ios_request_settings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if([scene isKindOfClass:UIWindowScene.class])
                for(UIWindow *window in ((UIWindowScene *)scene).windows)
                    if(window.isKeyWindow) { BO3ShowSettings(window.rootViewController,YES); return; }
    });
}

void BO3ApplyTouchPreferences(void) {
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    xbox_InputTouchSetMode(XBOX_TOUCH_AUTO);
    xbox_InputTouchSetScale(BO3MobileChoice(d,2) ? 1.2f : 1.0f);
    const float alpha[]={0.24f,0.5f,0.8f};
    xbox_InputTouchSetOpacity(alpha[BO3MobileChoice(d,3)]);
    xbox_InputTouchSetAutoGas((int)BO3MobileChoice(d,4));
    xbox_InputTouchSetHybrid(BO3MobileChoice(d,5)==0);
    xbox_InputTouchSetSteeringResponse((int)BO3MobileChoice(d,6));
}
static UITableViewCell *Cell(UITableView *table, NSString *title, NSString *detail) {
    UITableViewCell *cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease];
    UIListContentConfiguration *content=cell.defaultContentConfiguration;
    content.text=title; content.secondaryText=detail;
    content.textProperties.numberOfLines=0; content.secondaryTextProperties.numberOfLines=0;
    content.textProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.adjustsFontForContentSizeCategory=YES;
    content.secondaryTextProperties.adjustsFontForContentSizeCategory=YES;
    cell.contentConfiguration=content;
    return cell;
}
@interface BO3ChoicesController : UITableViewController
@property(nonatomic) NSUInteger setting;
@property(nonatomic) BOOL inGame;
@end
@implementation BO3ChoicesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=BO3MobileSettings()[self.setting][@"title"];
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=56;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [BO3MobileSettings()[self.setting][@"choices"] count]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return BO3MobileSettings()[self.setting][@"help"]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=Cell(t,BO3MobileSettings()[self.setting][@"choices"][p.row],nil);
    BOOL selected=BO3MobileChoice(NSUserDefaults.standardUserDefaults,self.setting)==p.row;
    cell.accessoryType=selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits|=selected ? UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    BO3MobileSetChoice(NSUserDefaults.standardUserDefaults,self.setting,p.row);
    if(self.inGame) BO3ApplyTouchPreferences();
    [t reloadData];
}
@end

@interface BO3SettingsController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic) BOOL inGame;
@property(nonatomic) BOOL canReturnToLauncher;
@end
@implementation BO3SettingsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"iOS Settings";
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=56;
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)] autorelease];
    if(self.canReturnToLauncher) {
        self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"Launcher" style:UIBarButtonItemStylePlain target:self action:@selector(returnToLauncher)] autorelease];
        self.navigationItem.leftBarButtonItem.accessibilityLabel=@"Return to iOS launcher";
        self.navigationItem.leftBarButtonItem.accessibilityIdentifier=@"ios.launcherButton";
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self.tableView reloadData];
    self.navigationController.presentationController.delegate=self;
}
- (void)done { [self dismissViewControllerAnimated:YES completion:^{ if(self.inGame) SessionRelease(BO3_HOLD_SETTINGS); }]; }
- (void)returnToLauncher {
    if(!self.canReturnToLauncher) return;
    UIViewController *host=self.navigationController.presentingViewController;
    SessionHold(BO3_HOLD_LAUNCHER);
    [self dismissViewControllerAnimated:YES completion:^{ SessionRelease(BO3_HOLD_SETTINGS); ShowSessionLauncher(host); }];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)p { if(self.inGame) SessionRelease(BO3_HOLD_SETTINGS); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return self.canReturnToLauncher ? 4 : 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0 ? 2 : s==1 ? (NSInteger)BO3MobileSettings().count-2 : s==2 ? 2 : 1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return @[@"Display",@"Touch controls",@"Preferences",@"Session"][s]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==3) return @"Your current game stays paused. Choose Resume game on the launcher to return. Permanent progress uses the game’s Save Profile.";
    return s==0 ? @"Display changes apply the next time you launch the app. Restart between races so your progress can save."
        : s==1 ? @"In races: steer on the left; GAS accelerates, BRAKE slows down and BOOST also holds the accelerator. Menu navigation uses the D-pad, A to select and B to go back."
        : @"Resetting iOS settings keeps your game files and saved profiles. Built on Takedawn and xboxrecomp; their license notices are included with this app.";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    if(p.section==3) { UITableViewCell *c=Cell(t,@"Return to iOS launcher",nil); c.accessibilityTraits|=UIAccessibilityTraitButton; c.accessibilityIdentifier=@"ios.returnToLauncher"; return c; }
    if(p.section==2) { UITableViewCell *c=Cell(t,p.row==0 ? @"Credits & licenses" : @"Reset iOS settings",nil); c.accessibilityTraits|=UIAccessibilityTraitButton; return c; }
    NSUInteger i=p.section==0 ? p.row : p.row+2;
    NSDictionary *item=BO3MobileSettings()[i];
    UITableViewCell *cell=Cell(t,item[@"title"],item[@"choices"][BO3MobileChoice(NSUserDefaults.standardUserDefaults,i)]);
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier=[@"ios.setting." stringByAppendingString:item[@"key"]];
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES];
    if(p.section==3 && self.canReturnToLauncher) {
        [self returnToLauncher];
        return;
    }
    if(p.section==2) {
        if(p.row==0) {
            UIViewController *credits=[[[UIViewController alloc] init] autorelease];
            credits.title=@"Credits & licenses";
            UITextView *text=[[[UITextView alloc] initWithFrame:CGRectZero] autorelease];
            text.editable=NO; text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            text.adjustsFontForContentSizeCategory=YES;
            text.backgroundColor=UIColor.systemBackgroundColor; text.textColor=UIColor.labelColor;
            text.textContainerInset=UIEdgeInsetsMake(20,20,20,20);
            NSMutableString *notices=[NSMutableString stringWithString:@"Burnout 3 iOS · Xbox edition\n\nAn iOS adaptation of Takedawn and xboxrecomp, carrying forward the native app work from our PS2 port. Game content and trademarks belong to their respective owners. No game data is included.\n\n"];
            NSArray *paths=@[@"LICENSE",@"THIRD_PARTY_NOTICES.md",@"licenses/NOTICE",@"licenses/LGPL-2.1.txt",@"licenses/SDL2-Zlib.txt",@"licenses/ADPCM-XQ-BSD-3-Clause.txt"];
            for(NSString *path in paths) {
                NSString *content=[NSString stringWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:path] encoding:NSUTF8StringEncoding error:NULL];
                if(content) [notices appendFormat:@"%@\n\n%@\n\n",path,content];
            }
            text.text=notices; credits.view=text;
            [self.navigationController pushViewController:credits animated:YES]; return;
        }
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Reset iOS settings?" message:@"Your game files and saved profiles will stay on this device." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reset settings" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){ BO3MobileReset(NSUserDefaults.standardUserDefaults); if(self.inGame) BO3ApplyTouchPreferences(); [t reloadData]; }]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    BO3ChoicesController *choices=[[[BO3ChoicesController alloc] initWithStyle:UITableViewStyleInsetGrouped] autorelease];
    choices.setting=p.section==0 ? p.row : p.row+2; choices.inGame=self.inGame;
    [self.navigationController pushViewController:choices animated:YES];
}
@end
void BO3ShowSettings(UIViewController *host, BOOL inGame) {
    if(host.presentedViewController) return;
    if(inGame) SessionHold(BO3_HOLD_SETTINGS);
    BO3SettingsController *settings=[[[BO3SettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] autorelease];
    settings.inGame=inGame;
    settings.canReturnToLauncher=inGame && ![host isKindOfClass:NSClassFromString(@"BO3LauncherController")];
    UINavigationController *nav=[[[UINavigationController alloc] initWithRootViewController:settings] autorelease];
    nav.view.tintColor=UIColor.systemOrangeColor;
    nav.modalPresentationStyle=UIModalPresentationFormSheet;
    [host presentViewController:nav animated:YES completion:nil];
    if(settings.canReturnToLauncher && getenv("RECOMP_IOS_UI_TEST"))
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(settings.navigationController.presentingViewController) [settings tableView:settings.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
        });
    if(inGame) XR_NOTICE("[IOS SESSION] native settings opened, paused=%d\n",xbox_HostPaused());
}

@interface BO3LauncherController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic,copy) NSString *documents;
@property(nonatomic) BOOL play;
@property(nonatomic) BOOL resumeSession;
@property(nonatomic) BOOL importing;
@property(nonatomic,copy) NSString *status;
@end
@implementation BO3LauncherController
- (BOOL)hasGame { return [NSFileManager.defaultManager fileExistsAtPath:[self.documents stringByAppendingPathComponent:@"Burnout 3 Takedown/default.xbe"]]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Burnout 3";
    self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=64;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s==1 ? @"On this iPhone or iPad" : nil; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return self.resumeSession ? @"Your current game is paused. Resume to pick up where you left off." : [self hasGame] ? @"Xbox edition · iOS development build" : @"Import the supported USA Xbox game folder to play.";
    if(s==1) return self.status ?: ([self hasGame] ? @"Your game files are available. Saved profiles are stored separately and kept when this app is updated."
        : @"Choose an extracted game folder from Files. The app checks every file before installing it. Archives and PS2 files are not supported. Allow about 3 GB of free space for installation.");
    return @"An unofficial Burnout 3 iOS port built on Takedawn and xboxrecomp. Game files are supplied separately. Saved profiles stay on this device.";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    NSString *title=p.section==0 ? (self.resumeSession ? @"Resume game" : @"Play") : p.section==1 ? ([self hasGame] ? @"Xbox game files" : @"Import Xbox game folder") : @"iOS Settings";
    UITableViewCell *cell=Cell(t,title,p.section==1 && [self hasGame] ? @"Available" : nil);
    cell.accessibilityIdentifier=@[@"ios.play",@"ios.import",@"ios.settings"][p.section];
    BOOL action=p.section!=1 || ![self hasGame];
    cell.userInteractionEnabled=!self.importing && (p.section!=0 || [self hasGame]);
    cell.selectionStyle=action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if(cell.userInteractionEnabled && action) { cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.accessibilityTraits|=UIAccessibilityTraitButton; }
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES];
    if(self.importing) return;
    if(p.section==0 && [self hasGame]) {
        if(self.resumeSession) [self dismissViewControllerAnimated:YES completion:^{ UIApplication.sharedApplication.idleTimerDisabled=YES; SessionRelease(BO3_HOLD_LAUNCHER); XR_NOTICE("[IOS SESSION] resumed, paused=%d\n",xbox_HostPaused()); }];
        else self.play=YES;
    }
    else if(p.section==2) BO3ShowSettings(self,self.resumeSession);
    else if(p.section==1 && ![self hasGame]) {
        UIDocumentPickerViewController *picker=[[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO] autorelease];
        picker.delegate=self; picker.allowsMultipleSelection=NO;
        [self presentViewController:picker animated:YES completion:nil];
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source=urls.firstObject; if(!source) return;
    BOOL access=[source startAccessingSecurityScopedResource];
    self.importing=YES; self.status=@"Copying game files… Keep the app open."; [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSURL *destination=[NSURL fileURLWithPath:[self.documents stringByAppendingPathComponent:@"Burnout 3 Takedown"] isDirectory:YES];
            NSError *error=nil;
            NSFileCoordinator *coordinator=[[[NSFileCoordinator alloc] initWithFilePresenter:nil] autorelease];
            __block NSError *installError=nil;
            __block BOOL valid=NO;
            [coordinator coordinateReadingItemAtURL:source options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *readURL) {
                valid=BO3InstallGameFolder(readURL,destination,[NSBundle.mainBundle URLForResource:@"ntsc-u-retail" withExtension:@"manifest"],^(NSUInteger done,NSUInteger total){
                    if(done%20 && done!=total) return;
                    dispatch_async(dispatch_get_main_queue(),^{ self.status=[NSString stringWithFormat:@"Checking game files… %lu of %lu",(unsigned long)done,(unsigned long)total]; [self.tableView reloadData]; });
                },&installError);
                [installError retain];
            }];
            if(!error) error=[installError autorelease]; else { [installError release]; valid=NO; }
            if(access) [source stopAccessingSecurityScopedResource];
            NSString *message=valid ? @"All 716 game files verified. Ready to play." : (error.localizedDescription ?: @"The folder could not be imported. Choose the extracted USA Xbox game folder and try again.");
            dispatch_async(dispatch_get_main_queue(),^{ self.importing=NO; self.status=message; [self.tableView reloadData];
                if(!valid) {
                    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Couldn’t import game" message:message preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                }
            });
        }
    });
}
- (void)dealloc { [_documents release]; [_status release]; [super dealloc]; }
@end

static void ShowSessionLauncher(UIViewController *host) {
    if(!host || host.presentedViewController) return;
    SessionHold(BO3_HOLD_LAUNCHER);
    BO3LauncherController *launcher=[[[BO3LauncherController alloc] initWithStyle:UITableViewStyleInsetGrouped] autorelease];
    launcher.documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    launcher.resumeSession=YES;
    UINavigationController *nav=[[[UINavigationController alloc] initWithRootViewController:launcher] autorelease];
    nav.view.tintColor=UIColor.systemOrangeColor; nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
    UIApplication.sharedApplication.idleTimerDisabled=NO;
    XR_NOTICE("[IOS SESSION] returned to launcher, paused=%d\n",xbox_HostPaused());
    if(getenv("RECOMP_IOS_UI_TEST"))
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(launcher.navigationController.presentingViewController && !launcher.presentedViewController)
                [launcher tableView:launcher.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        });
}

BOOL BO3ShowLauncher(NSString *documents) {
    /* Test scripts select Play through the same launcher path as a user. */
    UIWindowScene *windowScene=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class]) { windowScene=(UIWindowScene *)scene; break; }
    if(!windowScene) return NO;
    UIApplication.sharedApplication.idleTimerDisabled=NO;
    UIWindow *window=[[UIWindow alloc] initWithWindowScene:windowScene];
    BO3LauncherController *launcher=[[BO3LauncherController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    launcher.documents=documents;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:launcher];
    nav.view.tintColor=UIColor.systemOrangeColor;
    window.rootViewController=nav;
    [window makeKeyAndVisible];
    if(getenv("RECOMP_IOS_SETTINGS_PREVIEW"))
        dispatch_async(dispatch_get_main_queue(), ^{ BO3ShowSettings(launcher,NO); });
    if(getenv("RECOMP_IOS_AUTOPLAY") && !strcmp(getenv("RECOMP_IOS_AUTOPLAY"),"1"))
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [launcher tableView:launcher.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        });
    while(!launcher.play) @autoreleasepool {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    window.hidden=YES; window.rootViewController=nil;
    UIApplication.sharedApplication.idleTimerDisabled=YES;
    [nav release]; [launcher release]; [window release];
    return YES;
}
