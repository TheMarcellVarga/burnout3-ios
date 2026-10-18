#import "game_launch.h"

@interface GameLaunchView ()
@property(nonatomic, strong, readwrite) UIButton *importButton;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) UILabel *message;
@property(nonatomic, strong) UIActivityIndicatorView *activity;
@end

@implementation GameLaunchView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.systemBackgroundColor;
        UIScrollView *scroll = [UIScrollView new];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:scroll];
        self.heading = [UILabel new];
        self.heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
        self.heading.adjustsFontForContentSizeCategory = YES;
        self.heading.textColor = UIColor.labelColor;
        self.heading.numberOfLines = 0;
        self.heading.accessibilityTraits = UIAccessibilityTraitHeader;
        self.message = [UILabel new];
        self.message.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.message.adjustsFontForContentSizeCategory = YES;
        self.message.textColor = UIColor.secondaryLabelColor;
        self.message.numberOfLines = 0;
        self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *button = [UIButtonConfiguration filledButtonConfiguration];
        button.title = @"Upload ISO file";
        button.image = [UIImage systemImageNamed:@"doc.badge.plus"];
        button.imagePadding = 10;
        button.contentInsets = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
        self.importButton.configuration = button;
        self.importButton.accessibilityHint = @"Choose your Burnout 3 disc image from Files. It stays on this device.";
        self.activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.activity.hidesWhenStopped = YES;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.heading, self.message, self.importButton, self.activity]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentLeading;
        stack.spacing = 16;
        [stack setCustomSpacing:24 afterView:self.message];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [scroll addSubview:stack];
        UILayoutGuide *safe = self.safeAreaLayoutGuide;
        NSLayoutConstraint *center = [stack.centerYAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerYAnchor];
        center.priority = UILayoutPriorityDefaultLow;
        [NSLayoutConstraint activateConstraints:@[
            [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],
            [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],
            [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
            [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
            [scroll.contentLayoutGuide.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
            [stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],
            [stack.widthAnchor constraintLessThanOrEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
            [stack.widthAnchor constraintLessThanOrEqualToConstant:560],
            [stack.topAnchor constraintGreaterThanOrEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
            [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
            [stack.heightAnchor constraintGreaterThanOrEqualToConstant:1],
            [self.importButton.heightAnchor constraintGreaterThanOrEqualToConstant:44], center
        ]];
        NSLayoutConstraint *measure = [stack.widthAnchor constraintEqualToConstant:560];
        measure.priority = UILayoutPriorityDefaultHigh;
        measure.active = YES;
        [self showLoadingMessage:@"Starting game…"];
    }
    return self;
}
- (void)showImportMessage:(NSString *)message {
    self.hidden = NO;
    self.heading.text = @"Add your game";
    self.message.text = message ?: @"Choose your Burnout 3: Takedown ISO (NTSC-U). Import it once to play. Future launches start the game automatically. The file stays on this device.";
    self.importButton.hidden = NO;
    self.importButton.enabled = YES;
    [self.activity stopAnimating];
}
- (void)showLoadingMessage:(NSString *)message {
    self.hidden = NO;
    self.heading.text = message;
    self.message.text = nil;
    self.importButton.hidden = YES;
    [self.activity startAnimating];
}
- (void)showMessage:(NSString *)message {
    self.hidden = NO;
    self.heading.text = @"Burnout 3";
    self.message.text = message;
    self.importButton.hidden = YES;
    [self.activity stopAnimating];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
}
@end
