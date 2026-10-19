#import <UIKit/UIKit.h>
#import "analog_stick.h"
#import "game_launch.h"
#if PS2HOST_VULKAN
#import "gpu_display.h"
#include "ps2gpu/gs_renderer.h"
#include "pipeline_hints.h"
#endif
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <cstring>
#include "ps2host/host.h"
#include "ps2host/run.h"
#include "ps2host/gs.h"
#include "ps2host/profile.h"
#include "ps2host/vu.h"
#include "apple_frame_sink.h"
#include "apple_touch_input.h"
#include <chrono>
#include <atomic>
#include <memory>
#include <cstdio>
#include <thread>

extern const ps2host::FunctionEntry kGuestFunctions[];
extern const std::size_t kGuestFunctionCount;
extern const ps2host::OverlayEntry kGuestOverlays[];
extern const std::size_t kGuestOverlayCount;
void RegisterGameOverrides();
void RegisterMobileQuality();
void RegisterSixtyFps();
void RegisterNativeRaceMetrics();
void RegisterMobileAuxRefresh(unsigned);
unsigned long long NativeRaceDrawCalls();
unsigned long long RaceWorldCalls();
NSDictionary *RunAnalogTrackingChecks(AnalogStick *, AnalogStick *, UIView *);
#if PS2HOST_VULKAN
int RunGpuRendererTests();
#endif
namespace applehost { void InstallIosAudio(); }

// Read only ISO metadata, never map a multi-gigabyte image into memory.
static BOOL SupportedDisc(NSURL *url) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue] != 2867822592ull) return NO;
    FILE *file = fopen(url.path.fileSystemRepresentation, "rb");
    if (!file) return NO;
    unsigned char pvd[2048];
    BOOL valid = fseeko(file, 16 * 2048, SEEK_SET) == 0 && fread(pvd, 1, sizeof(pvd), file) == sizeof(pvd);
    auto le32 = [](const unsigned char *p) -> uint32_t {
        return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
    };
    valid = valid && memcmp(pvd, "\1CD001\1", 7) == 0 && pvd[128] == 0 && pvd[129] == 8;
    BOOL found = NO;
    if (valid) {
        uint64_t offset = uint64_t(le32(pvd + 158)) * 2048;
        uint32_t size = le32(pvd + 166);
        if (size <= 1024 * 1024 && offset + size <= 2867822592ull) {
            NSMutableData *root = [NSMutableData dataWithLength:size];
            if (fseeko(file, offset, SEEK_SET) == 0 && fread(root.mutableBytes, 1, size, file) == size) {
                const unsigned char *bytes = (const unsigned char *)root.bytes;
                for (uint32_t pos = 0; pos < size;) {
                    unsigned length = bytes[pos];
                    if (!length) { pos = (pos / 2048 + 1) * 2048; continue; }
                    if (length < 34 || pos + length > size || bytes[pos + 32] > length - 33) break;
                    if (!(bytes[pos + 25] & 2) && bytes[pos + 32] == 13 &&
                        memcmp(bytes + pos + 33, "SLUS_210.50;1", 13) == 0) found = YES;
                    pos += length;
                }
            }
        }
    }
    fclose(file);
    return found;
}

@interface NativeBootController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIImageView *frame;
@property(nonatomic, strong) UIView *gpuView;
@property(nonatomic, strong) GameLaunchView *launcher;
@property(nonatomic) BOOL startupAttempted;
@property(nonatomic) BOOL importing;
@property(nonatomic) BOOL showingGame;
@property(nonatomic) BOOL started;
@property(nonatomic, strong) AnalogStick *leftStick;
@property(nonatomic, strong) AnalogStick *rightStick;
@property(nonatomic, strong) NSMutableArray<UIButton *> *padButtons;
- (void)recordLaunchState:(NSString *)state;
- (void)saveLaunchScreenshot:(NSString *)state;
@end

@implementation NativeBootController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIButton *)padButton:(NSString *)title symbol:(NSString *)symbol input:(NSInteger)input {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.baseBackgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.12];
    config.baseForegroundColor = UIColor.labelColor;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    if (symbol) config.image = [UIImage systemImageNamed:symbol];
    else config.title = title;
    button.configuration = config;
    button.alpha = 0.24;
    button.configurationUpdateHandler = ^(UIButton *control) {
        control.alpha = control.highlighted ? 0.6 : 0.24;
    };
    button.accessibilityLabel = title;
    button.tag = input;
    button.exclusiveTouch = NO;
    [button addTarget:self action:@selector(padDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:self action:@selector(padUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self.view addSubview:button];
    [self.padButtons addObject:button];
    return button;
}
- (void)padDown:(UIButton *)button { applehost::SetTouchButton((unsigned)button.tag, true); std::fprintf(stderr, "[touch] down %ld\n", (long)button.tag); }
- (void)padUp:(UIButton *)button { applehost::SetTouchButton((unsigned)button.tag, false); std::fprintf(stderr, "[touch] up %ld\n", (long)button.tag); }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.blackColor;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--launcher-accessibility"])
        self.view.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
    self.view.multipleTouchEnabled = YES;
    self.frame = [UIImageView new];
    self.frame.contentMode = UIViewContentModeScaleAspectFit;
    self.frame.accessibilityLabel = @"Game output";
    [self.view addSubview:self.frame];
    self.padButtons = [NSMutableArray new];
    [self padButton:@"Up" symbol:@"arrow.up" input:4];
    [self padButton:@"Left / steer left" symbol:@"arrow.left" input:7];
    [self padButton:@"Right / steer right" symbol:@"arrow.right" input:5];
    [self padButton:@"Down" symbol:@"arrow.down" input:6];
    [self padButton:@"Triangle" symbol:@"triangle" input:12];
    [self padButton:@"Square" symbol:@"square" input:15];
    [self padButton:@"Circle / back" symbol:@"circle" input:13];
    [self padButton:@"Cross / confirm / boost" symbol:@"xmark" input:14];
    [self padButton:@"R2" symbol:nil input:9];
    [self padButton:@"L2" symbol:nil input:8];
    [self padButton:@"L1" symbol:nil input:10];
    [self padButton:@"R1" symbol:nil input:11];
    [self padButton:@"Select" symbol:nil input:0];
    [self padButton:@"Start" symbol:nil input:3];
    self.leftStick = [AnalogStick new];
    self.leftStick.stickIndex = 0;
    self.leftStick.accessibilityLabel = @"Left analog stick / steering";
    self.rightStick = [AnalogStick new];
    self.rightStick.stickIndex = 1;
    self.rightStick.accessibilityLabel = @"Right analog stick";
    [self.view addSubview:self.leftStick];
    [self.view addSubview:self.rightStick];
    self.launcher = [[GameLaunchView alloc] initWithFrame:self.view.bounds];
    [self.launcher.importButton addTarget:self action:@selector(importDisc) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.launcher];
    applehost::EnableTouchController(true);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopBoot)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect area = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat x = CGRectGetMinX(area), y = CGRectGetMinY(area), w = area.size.width, h = area.size.height;
    const CGFloat side = MIN(44, (h - 160) / 3), gap = 4, pad = side * 3 + gap * 2;
    const CGFloat top = y + 68, right = x + w - pad;
    self.frame.frame = area;
    // Match the existing image view's aspect-fit presentation.
    const CGFloat gameAspect = 640.0 / 448.0;
    CGSize gameSize = CGSizeMake(MIN(w, h * gameAspect), MIN(h, w / gameAspect));
    self.gpuView.frame = CGRectMake(CGRectGetMidX(area) - gameSize.width / 2,
        CGRectGetMidY(area) - gameSize.height / 2, gameSize.width, gameSize.height);
    self.launcher.frame = self.view.bounds;
    const CGPoint cells[] = {{1,0},{0,1},{2,1},{1,2},{1,0},{0,1},{2,1},{1,2}};
    for (NSUInteger i = 0; i < 8; ++i) {
        const CGFloat origin = i < 4 ? x : right;
        self.padButtons[i].frame = CGRectMake(origin + cells[i].x * (side + gap), top + cells[i].y * (side + gap), side, side);
    }
    self.padButtons[8].frame = CGRectMake(x + w - 164, y + 20, 104, 44);
    self.padButtons[9].frame = CGRectMake(x, y + 20, 104, 44);
    self.padButtons[10].frame = CGRectMake(x + 108, y + 20, 56, 44);
    self.padButtons[11].frame = CGRectMake(x + w - 224, y + 20, 56, 44);
    self.leftStick.frame = CGRectMake(x + 14, y + h - 128, 112, 112);
    self.rightStick.frame = CGRectMake(x + w - 126, y + h - 128, 112, 112);
    self.padButtons[12].frame = CGRectMake(CGRectGetMidX(area) - 86, y + h - 44, 80, 44);
    self.padButtons[13].frame = CGRectMake(CGRectGetMidX(area) + 6, y + h - 44, 80, 44);
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSDictionary *layout = @{@"width": @(self.view.bounds.size.width), @"height": @(self.view.bounds.size.height),
        @"landscape": @(self.view.bounds.size.width > self.view.bounds.size.height), @"touch_buttons": @(self.padButtons.count), @"analog_sticks": @2, @"idle_opacity": @0.24};
    [[NSJSONSerialization dataWithJSONObject:layout options:0 error:nil]
        writeToURL:[documents URLByAppendingPathComponent:@"native-layout.json"] atomically:YES];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    if (!self.started && ([arguments containsObject:@"--controller-tests"] || [arguments containsObject:@"--stick-smoke"])) {
        // The launcher covers controls during startup; test the gameplay hit areas.
        self.launcher.hidden = YES;
        NSDictionary *tracking = RunAnalogTrackingChecks(self.leftStick, self.rightStick, self.view);
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [[NSJSONSerialization dataWithJSONObject:tracking options:NSJSONWritingPrettyPrinted error:nil]
            writeToURL:[documents URLByAppendingPathComponent:@"native-stick-tracking.json"] atomically:YES];
        self.launcher.hidden = NO;
    }
    if (!self.startupAttempted) {
        self.startupAttempted = YES;
        [self beginBoot];
        if ([arguments containsObject:@"--launch-smoke"]) [self saveLaunchScreenshot:@"starting"];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--stick-smoke"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 24 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.leftStick setPosition:CGPointMake(-0.5, 0.25)];
            [self.rightStick setPosition:CGPointMake(0.5, -0.5)];
            [self.padButtons[8] sendActionsForControlEvents:UIControlEventTouchDown];
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.view.bounds];
            UIImage *screen = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
            }];
            NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
            [UIImagePNGRepresentation(screen) writeToURL:[documents URLByAppendingPathComponent:@"native-controls.png"] atomically:YES];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self.leftStick cancelTrackingWithEvent:nil];
                [self.rightStick cancelTrackingWithEvent:nil];
                [self.padButtons[8] sendActionsForControlEvents:UIControlEventTouchUpInside];
            });
        });
    }
    // Developer-only input smoke run traverses the same UIControl handlers as a touch.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--input-smoke"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 24 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.padButtons[0] sendActionsForControlEvents:UIControlEventTouchDown];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [self.padButtons[0] sendActionsForControlEvents:UIControlEventTouchUpInside];
                [self.padButtons[7] sendActionsForControlEvents:UIControlEventTouchDown];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    [self.padButtons[7] sendActionsForControlEvents:UIControlEventTouchUpInside];
                });
            });
        });
    }
}
- (void)stopBoot {
    [self.leftStick cancelTrackingWithEvent:nil];
    [self.rightStick cancelTrackingWithEvent:nil];
    applehost::ReleaseTouchButtons();
    if (self.started) ps2host::StopRequested() = true;
}
- (void)importDisc {
    if (self.started || self.importing || self.presentedViewController) return;
    // Providers may classify .iso as generic data; validation checks its contents.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source || self.importing || self.started) return;
    self.importing = YES;
    [self.launcher showLoadingMessage:@"Importing your game…"];
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [self recordLaunchState:@"importing"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [source startAccessingSecurityScopedResource];
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *destination = [documents URLByAppendingPathComponent:@"burnout3.iso"];
        NSURL *staging = [documents URLByAppendingPathComponent:@"burnout3-import.partial"];
        NSFileManager *files = NSFileManager.defaultManager;
        [files removeItemAtURL:staging error:nil];
        __block NSError *importError = nil;
        __block BOOL imported = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError *coordinationError = nil;
        [coordinator coordinateReadingItemAtURL:source options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
            if (!SupportedDisc(readURL)) {
                importError = [NSError errorWithDomain:@"BurnoutImport" code:1 userInfo:@{
                    NSLocalizedDescriptionKey: @"Choose a complete Burnout 3: Takedown NTSC-U ISO (SLUS-21050). This file isn’t supported."}];
                return;
            }
            if (![files copyItemAtURL:readURL toURL:staging error:&importError]) return;
            if (!SupportedDisc(staging)) {
                importError = [NSError errorWithDomain:@"BurnoutImport" code:2 userInfo:@{
                    NSLocalizedDescriptionKey: @"The copied ISO is incomplete. Try importing it again."}];
                return;
            }
            if ([files fileExistsAtPath:destination.path]) {
                imported = [files replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil options:0 resultingItemURL:nil error:&importError];
            } else {
                imported = [files moveItemAtURL:staging toURL:destination error:&importError];
            }
            if (imported) [destination setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }];
        [files removeItemAtURL:staging error:nil];
        if (scoped) [source stopAccessingSecurityScopedResource];
        NSError *error = importError ?: coordinationError;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.importing = NO;
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            if (imported) [self beginBoot];
            else {
                NSString *message = [NSString stringWithFormat:@"Import failed. %@ Try choosing the ISO again.",
                    error.localizedDescription ?: @"Check available device storage and file access."];
                [self.launcher showImportMessage:message];
                [self recordLaunchState:@"import-failed"];
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
            }
        });
    });
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)recordLaunchState:(NSString *)state {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSDictionary *report = @{@"state": state, @"display_name": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"],
        @"bundle_version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"],
        @"timestamp": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date]};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
        writeToURL:[documents URLByAppendingPathComponent:@"game-launch.json"] atomically:YES];
}
- (void)saveLaunchScreenshot:(NSString *)state {
    [self.view layoutIfNeeded];
    UIView *surface = self.view.window ?: self.view;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:surface.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [surface drawViewHierarchyInRect:surface.bounds afterScreenUpdates:YES];
    }];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [UIImagePNGRepresentation(image) writeToURL:[documents URLByAppendingPathComponent:[NSString stringWithFormat:@"game-launch-%@.png", state]] atomically:YES];
}
- (void)beginBoot {
    if (self.started) return;
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *disc = [documents URLByAppendingPathComponent:@"burnout3.iso"];
    if (!SupportedDisc(disc)) {
        [self.launcher showImportMessage:nil];
        [self recordLaunchState:@"awaiting-iso"];
        return;
    }
    // Keep slot 1 in Documents so profiles survive closing the app and updates.
    NSURL *card = [documents URLByAppendingPathComponent:@"memcard" isDirectory:YES];
    NSError *cardError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:card withIntermediateDirectories:YES attributes:nil error:&cardError] ||
        ![NSFileManager.defaultManager isWritableFileAtPath:card.path]) {
        [self.launcher showMessage:@"Saved profiles couldn’t be opened. Free some device storage, then close and reopen Burnout 3."];
        [self recordLaunchState:@"memory-card-unavailable"];
        return;
    }
    self.started = YES;
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [self.launcher showLoadingMessage:@"Starting game…"];
    [self recordLaunchState:@"starting"];
    NSURL *output = [documents URLByAppendingPathComponent:@"native-boot" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:output withIntermediateDirectories:YES attributes:nil error:nil];
    // Capture only this app's diagnostics, inside its own sandbox.
    std::freopen([[output URLByAppendingPathComponent:@"run.log"].path fileSystemRepresentation], "w", stderr);
    NativeBootController *owner = self;
    std::string disc_path = disc.path.UTF8String, output_path = output.path.UTF8String;
    std::string card_path = card.path.UTF8String;
    const bool bounded = [NSProcessInfo.processInfo.arguments containsObject:@"--native-boot"];
    const bool smoke = [NSProcessInfo.processInfo.arguments containsObject:@"--input-smoke"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--stick-smoke"];
    const bool title_test = [NSProcessInfo.processInfo.arguments containsObject:@"--gpu-title-test"];
    #if PS2HOST_VULKAN
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--copy-blend"])
        setenv("PS2HOST_GPU_COPY_BLEND", "1", 1);
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--race-profile"]) {
        setenv("PS2HOST_GPU_PROFILE", "1", 1);
        setenv("PS2HOST_GPU_COUNT", "1", 1);
    }
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--software-renderer"] &&
        ![NSProcessInfo.processInfo.arguments containsObject:@"--cpu-display"]) {
        self.gpuView = applehost::InstallGpuDisplay(self.view, [owner] {
            dispatch_async(dispatch_get_main_queue(), ^{
                owner.showingGame = YES;
                owner.launcher.hidden = YES;
                owner.frame.hidden = YES;
                [owner recordLaunchState:@"playing"];
            });
        });
        // Keep the controls above the game's surface.
        if (self.gpuView) [self.view insertSubview:self.gpuView aboveSubview:self.frame];
        [self.view setNeedsLayout];
    }
#endif
    const bool race_soak = [NSProcessInfo.processInfo.arguments containsObject:@"--race-soak"];
    const bool race_test = race_soak || [NSProcessInfo.processInfo.arguments containsObject:@"--race-test"];
    const bool geometry_test = race_test || [NSProcessInfo.processInfo.arguments containsObject:@"--geometry-test"];
    const u64 target_frame = race_soak ? 12000 : race_test ? 8400 : geometry_test ? 6000 : title_test ? 4000 : bounded ? 1200 : smoke ? 2400 : 0;
    std::thread([owner, output, disc_path, output_path, card_path, bounded, smoke, title_test, geometry_test, race_test, target_frame] {
        @autoreleasepool {
            auto pending_frame = std::make_shared<std::atomic<bool>>(false);
            auto frame_sink = [owner, output, pending_frame, bounded, smoke, title_test](const std::vector<u32>& pixels, u32 width, u32 height) {
                @autoreleasepool {
                    NSData *bytes = [NSData dataWithBytes:pixels.data() length:pixels.size() * sizeof(u32)];
                    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)bytes);
                    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
                    CGImageRef cg = CGImageCreate(width, height, 8, 32, width * 4, color,
                        CGBitmapInfo(kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst),
                        provider, nullptr, false, kCGRenderingIntentDefault);
                    UIImage *image = cg ? [UIImage imageWithCGImage:cg] : nil;
                    if (cg) CGImageRelease(cg);
                    CGColorSpaceRelease(color); CGDataProviderRelease(provider);
                    if (image) {
                        bool visible = false;
                        for (size_t i = 0; i < pixels.size(); i += 64) {
                            if ((pixels[i] & 0x00ffffffu) != 0) { visible = true; break; }
                        }
                        // Saving diagnostics must not encode a PNG for every live frame.
                        static auto last_save = std::chrono::steady_clock::time_point{};
                        const auto now = std::chrono::steady_clock::now();
                        if ((bounded || smoke || title_test) && now - last_save > std::chrono::seconds(2)) {
                        last_save = now;
                        [UIImagePNGRepresentation(image) writeToURL:[output URLByAppendingPathComponent:@"last-frame.png"] atomically:YES];
                        }
                        // Never build a backlog of frames in front of touch events.
                        if (!pending_frame->exchange(true)) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                owner.frame.image = image;
                                if (visible && !owner.showingGame) {
                                    owner.showingGame = YES;
                                    owner.launcher.hidden = YES;
                                    [owner recordLaunchState:@"playing"];
                                    if ([NSProcessInfo.processInfo.arguments containsObject:@"--launch-smoke"])
                                        [owner saveLaunchScreenshot:@"playing"];
                                }
                                pending_frame->store(false);
                            });
                        }
                    }
                }
            };
            applehost::SetFrameSink(frame_sink);
            applehost::InstallIosAudio();
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--two-draw-threads"])
                setenv("PS2HOST_GS_THREADS", "2", 1);
            const auto run_start = std::chrono::steady_clock::now();
            int code = 3;
            NSString *failure = nil;
            const bool mobile_quality = ![NSProcessInfo.processInfo.arguments containsObject:@"--original-quality"];
#if PS2HOST_VULKAN
            // POC prioritizes 50–60 FPS. Keep original meshes/textures and
            // camera distances; restore dynamic maps with --live-reflections.
            const bool flat_reflections = mobile_quality &&
                ![NSProcessInfo.processInfo.arguments containsObject:@"--software-renderer"] &&
                ![NSProcessInfo.processInfo.arguments containsObject:@"--live-reflections"];
#else
            const bool flat_reflections = false;
#endif
            const unsigned auxiliary_interval = flat_reflections ? 0 : 1;
            try {
#if PS2HOST_VULKAN
                if ([NSProcessInfo.processInfo.arguments containsObject:@"--gpu-tests"]) {
                    const int gpu_tests = RunGpuRendererTests();
                    NSDictionary *test_report = @{@"exit_code": @(gpu_tests), @"passed": @(gpu_tests == 0),
                        @"timestamp": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date]};
                    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
                    [[NSJSONSerialization dataWithJSONObject:test_report options:NSJSONWritingPrettyPrinted error:nil]
                        writeToURL:[documents URLByAppendingPathComponent:@"native-gpu-tests.json"] atomically:YES];
                    if (gpu_tests != 0) throw std::runtime_error("GPU compatibility checks failed");
                }
#endif
                ps2host::RegisterFunctions(kGuestFunctions, kGuestFunctionCount);
                ps2host::RegisterOverlays(kGuestOverlays, kGuestOverlayCount);
                RegisterGameOverrides();
                RegisterSixtyFps();
                RegisterNativeRaceMetrics();
#if PS2HOST_VULKAN
                ps2gpu::SetPipelineCacheDir(output_path);
                ps2gpu::SetPipelineHints(kGpuPipelineHints, std::size(kGpuPipelineHints));
#endif
                if (mobile_quality) RegisterMobileQuality();
                RegisterMobileAuxRefresh(auxiliary_interval);
                if (flat_reflections) setenv("BURNOUT3_FLAT_REFLECTIONS", "1", 1);
                ps2host::Options options;
                options.disc_path = disc_path;
                options.memcard = card_path;
                options.audio = true;
                options.vu_fast = mobile_quality;
                if (mobile_quality || [NSProcessInfo.processInfo.arguments containsObject:@"--race-no-blur"])
                    options.settings.push_back("blur=off");
#if PS2HOST_VULKAN
                options.gpu = ![NSProcessInfo.processInfo.arguments containsObject:@"--software-renderer"];
                options.gpu_show = options.gpu;
#endif
                // Normal play uses the real-time scheduler and VIF1 worker.
                // Bounded diagnostics retain repeatable boot/menu timings;
                // the race replay switches before race rendering starts.
                options.virtual_time = target_frame != 0;
                if (race_test && ![NSProcessInfo.processInfo.arguments containsObject:@"--race-virtual-clock"]) {
                    options.real_time_from = 6000;
                    ps2host::SetRealTimeFrom(options.real_time_from);
                }
                options.until_frame = target_frame;
                options.paced = !bounded && !title_test;
                options.timeout_seconds = target_frame ? 120 : 0;
                options.discover_path = output_path + "/discovered.txt";
                if (target_frame) options.record_input = output_path + "/input.txt";
                options.frame_times = 120;
                if (target_frame) { options.frames_dir = output_path; options.frames_every = title_test ? 1000 : 600; }
                if (title_test) options.presses = {{"up", 800, 806}, {"cross", 830, 836},
                    {"cross", 2100, 2106}, {"start", 2200, 2206}};
                if (geometry_test) {
                    // Replay uses a disposable card so profiling cannot change
                    // the player's profiles. Game-derived captures stay local.
                    options.memcard = output_path + "/geometry-test-card";
                    options.replay_input = output_path + "/../geometry-input.txt";
                    if (race_test) options.replay_input = output_path + "/../race-input.txt";
                    // Capturing traverses microcode on each invocation and
                    // must be off when measuring normal gameplay throughput.
                    if ([NSProcessInfo.processInfo.arguments containsObject:@"--geometry-capture"]) {
                        options.vu_record = output_path + "/vu-programs.txt";
                        options.vu_snapshot = output_path + "/vu-snapshots.bin";
                        options.vu_snapshot_from = race_test ? 6200 : 5400;
                        options.vu_snapshot_count = 256;
                    }
                    if ([NSProcessInfo.processInfo.arguments containsObject:@"--race-state-capture"]) {
                        options.vu_snapshot = output_path + "/vu-snapshots.bin";
                        options.vu_snapshot_from = 7800;
                        options.vu_snapshot_count = 256;
                    }
                    options.vu_interpret = [NSProcessInfo.processInfo.arguments containsObject:@"--geometry-interpreter"];
                    options.paced = [NSProcessInfo.processInfo.arguments containsObject:@"--geometry-paced"];
                    options.timeout_seconds = 360;
                    options.frames_every = 300;
                    if ([NSProcessInfo.processInfo.arguments containsObject:@"--race-profile"]) {
                        setenv("PS2HOST_GPU_PROFILE", "1", 1);
                        setenv("PS2HOST_GPU_COUNT", "1", 1);
                        setenv("PS2HOST_CAPTURE_FRAME", "7800", 1);
                        setenv("PS2HOST_CAPTURE_STREAM_ONLY", "1", 1);
                    }
                }
                code = ps2host::Run(options);
            } catch (const std::exception& error) {
                failure = [NSString stringWithUTF8String:error.what()];
            } catch (...) { failure = @"Native host stopped with an unexpected exception."; }
            const double run_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - run_start).count();
            std::fflush(stdout);
            // Preserve the final frame even when the live sink was throttled.
            std::vector<u32> final_pixels;
            u32 final_width = 0, final_height = 0;
            if (ps2host::gs::TheGs().Picture(&final_pixels, &final_width, &final_height))
                frame_sink(final_pixels, final_width, final_height);
            applehost::ReleaseTouchButtons();
            applehost::SetFrameSink({});
            ps2host::CloseAudio();
            std::fflush(stderr);
            const bool reached = ps2host::UntilFrameReached();
            NSDictionary *report = @{@"target_reached": @(reached), @"target_frame": @(target_frame),
                @"quality_preset": mobile_quality ? @"mobile performance" : @"original",
                @"vu_fast": @(mobile_quality),
                @"presentation": owner.gpuView ? @"direct Metal" : @"CPU image",
                @"renderer": ps2host::GpuPrimary() ? @"GPU (MoltenVK/Metal)" : @"software",
                @"gpu_summary": [NSString stringWithUTF8String:ps2host::GpuShadowSummary().c_str()],
                @"vu1_pairs": @(ps2host::Vu1().pairs()),
                @"vu1_compiled_pairs": @(ps2host::Vu1().compiled_pairs()),
                @"race_world_calls": @(RaceWorldCalls()),
                @"world_render_submissions": @(NativeRaceDrawCalls()),
                @"auxiliary_refresh_interval": @(auxiliary_interval),
                @"flat_reflections": @(flat_reflections),
                @"car_materials": flat_reflections ? @"POC diffuse materials" : @"original live reflections",
                @"world_far_clip_override": @0,
                @"world_draw_distance": @"original game cameras",
                @"host_exit_code": @(code), @"run_seconds": @(run_seconds),
                @"profile": [NSString stringWithUTF8String:ps2host::ProfileSummary().c_str()],
                @"thermal_state": @(NSProcessInfo.processInfo.thermalState),
                @"low_power_mode": @(NSProcessInfo.processInfo.lowPowerModeEnabled),
                @"bundle_version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"], @"failure": failure ?: NSNull.null,
                @"architecture": @"arm64", @"os_version": UIDevice.currentDevice.systemVersion,
                @"timestamp": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
                @"scope": @"Native game with touch controls and audio; active renderer reported separately"};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
                writeToURL:[output URLByAppendingPathComponent:@"result.json"] atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIApplication.sharedApplication.idleTimerDisabled = NO;
                [owner.launcher showMessage:failure ? @"The game couldn’t start. Close and reopen Burnout 3 to try again." :
                    @"Game session ended. Close and reopen Burnout 3 to play again."];
                [owner recordLaunchState:failure ? @"failed" : @"stopped"];
            });
        }
    }).detach();
}
@end

UIViewController* CreateNativeBootController(int runtime_status) {
    if (runtime_status != 0) {
        UIViewController *controller = [UIViewController new];
        UILabel *label = [UILabel new]; label.text = @"Runtime checks failed; native boot is disabled.";
        label.frame = CGRectMake(20, 100, 340, 100); label.numberOfLines = 0;
        [controller.view addSubview:label]; return controller;
    }
    return [NativeBootController new];
}
