#import <UIKit/UIKit.h>
#import "mobile_shell.h"
#include <string.h>
/* Win32 BOOL is a 32-bit int; keep it separate from Objective-C BOOL. */
#define BOOL XBOX_BOOL
#include "input/touch_pad.h"
#undef BOOL

/* Reuse xboxrecomp's tested touch-to-pad mapping with a native iOS view.
 * Coordinates stay in UIKit points for both the layout and finger events. */
@interface TakedawnTouchView : UIView {
    xbox_touch_draw _lastControls[XBOX_TOUCH_MAX_CONTROLS];
    int _lastCount;
    float _lastOpacity;
    BOOL _hasDrawState;
}
@property(nonatomic, retain) CADisplayLink *clock;
@property(nonatomic, retain) UIButton *settingsButton;
@property(nonatomic, retain) UIView *stickKnob;
@property(nonatomic) BOOL stickWasPressed;
@property(nonatomic) CGPoint stickBase;
@end
@implementation TakedawnTouchView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.multipleTouchEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.settingsButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
        self.settingsButton.tintColor = UIColor.whiteColor;
        self.settingsButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.65];
        self.settingsButton.layer.cornerRadius = 22;
        self.settingsButton.accessibilityLabel = @"iOS Settings";
        [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.settingsButton];
        self.stickKnob=[[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        self.stickKnob.userInteractionEnabled=NO;
        self.stickKnob.backgroundColor=[UIColor colorWithWhite:1 alpha:0.35];
        self.stickKnob.layer.borderWidth=1;
        [self addSubview:self.stickKnob];
        self.clock = [CADisplayLink displayLinkWithTarget:self selector:@selector(redraw:)];
        self.clock.preferredFramesPerSecond = 60;
        [self.clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suspend:)
            name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resume:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged:)
            name:BO3SessionDidChangeNotification object:nil];
    }
    return self;
}
- (void)suspend:(NSNotification *)note {
    (void)note; xbox_InputTouchReleaseAll(); BO3SessionBackground(YES); self.clock.paused=YES;
}
- (void)resume:(NSNotification *)note {
    (void)note; BO3SessionBackground(NO); self.clock.paused=BO3SessionHeld(); _hasDrawState=NO;
}
- (void)sessionChanged:(NSNotification *)note {
    (void)note; _hasDrawState=NO; [self redraw:self.clock];
    self.clock.paused=BO3SessionHeld() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
}
- (void)showSettings {
    xbox_InputTouchReleaseAll();
    BO3ShowSettings(self.window.rootViewController, YES);
}
- (void)redraw:(CADisplayLink *)clock {
    (void)clock;
    xbox_touch_draw controls[XBOX_TOUCH_MAX_CONTROLS];
    int count=xbox_InputTouchDrawList(controls,XBOX_TOUCH_MAX_CONTROLS);
    BO3ProfileTick(NO);
    float opacity=xbox_InputTouchOpacity();
    /* Poll context at 60 Hz; repaint only when fingers/layout/visibility
     * change. Core Animation runs the release spring independently. */
    if(_hasDrawState && count==_lastCount && opacity==_lastOpacity &&
        !memcmp(controls,_lastControls,(size_t)count*sizeof(*controls))) return;
    CGRect dirty=self.bounds;
    if(_hasDrawState && count==_lastCount && opacity==_lastOpacity) {
        dirty=CGRectNull;
        for(int i=0;i<count;i++) if(memcmp(&controls[i],&_lastControls[i],sizeof(*controls))) {
            xbox_touch_draw a=controls[i], b=_lastControls[i];
            dirty=CGRectUnion(dirty,CGRectMake(a.x-a.r-3,a.y-a.r-3,2*a.r+6,2*a.r+6));
            dirty=CGRectUnion(dirty,CGRectMake(b.x-b.r-3,b.y-b.r-3,2*b.r+6,2*b.r+6));
        }
    }
    memcpy(_lastControls,controls,(size_t)count*sizeof(*controls));
    _lastCount=count; _lastOpacity=opacity; _hasDrawState=YES;
    BOOL driving=NO;
    for(int i=0;i<count;i++) if(controls[i].kind==XBOX_TOUCH_KIND_STICK) {
        xbox_touch_draw stick=controls[i];
        driving=YES;
        CGFloat radius=stick.r*0.35;
        self.stickKnob.bounds=CGRectMake(0,0,2*radius,2*radius);
        self.stickKnob.layer.cornerRadius=radius;
        self.stickKnob.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.6].CGColor;
        self.stickKnob.alpha=stick.pressed ? MAX(0.6,opacity) : opacity;
        CGPoint from=self.stickKnob.layer.presentationLayer ? self.stickKnob.layer.presentationLayer.position : self.stickKnob.center;
        CGPoint to=CGPointMake(stick.kx,stick.ky);
        BOOL returning=self.stickWasPressed && !stick.pressed;
        if(stick.pressed || returning) [self.stickKnob.layer removeAnimationForKey:@"recenter"];
        self.stickKnob.center=to;
        /* Neutral has already reached the game. Only this visible knob springs.
         * A floated base returns quietly rather than flying across the screen. */
        if(returning && !UIAccessibilityIsReduceMotionEnabled() && hypot(self.stickBase.x-stick.x,self.stickBase.y-stick.y)<stick.r*0.25) {
            CASpringAnimation *spring=[CASpringAnimation animationWithKeyPath:@"position"];
            spring.mass=1; spring.stiffness=800; spring.damping=30;
            spring.fromValue=[NSValue valueWithCGPoint:from]; spring.toValue=[NSValue valueWithCGPoint:to];
            spring.duration=spring.settlingDuration;
            [self.stickKnob.layer addAnimation:spring forKey:@"recenter"];
        }
        self.stickWasPressed=stick.pressed;
        self.stickBase=CGPointMake(stick.x,stick.y);
    }
    self.stickKnob.hidden=!driving;
    if(!driving) { self.stickWasPressed=NO; [self.stickKnob.layer removeAllAnimations]; }
    /* Settings are available in menus and after pausing. Never leave a live
     * race running behind a sheet with its controls blocked. */
    self.settingsButton.hidden=driving || count==0;
    for(int i=0;i<count;i++) if(controls[i].icon==XBOX_TOUCH_ICON_MENU)
        self.settingsButton.frame=CGRectMake(controls[i].x-22,controls[i].y-22,44,44);
    if(!CGRectIsNull(dirty)) [self setNeedsDisplayInRect:dirty];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets insets = self.safeAreaInsets;
    xbox_InputTouchSetScreen(self.bounds.size.width, self.bounds.size.height);
    xbox_InputTouchSetInsets(insets.left, insets.top, insets.right, insets.bottom);
    /* UIKit points, not physical pixels: cap tablet control size at a
     * comfortable thumb reach while leaving phone-sized layouts unchanged. */
    xbox_InputTouchSetDpi(UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad ? 132 : 163);
    self.settingsButton.frame=CGRectMake(insets.left+130,insets.top+12,44,44);
}
- (void)drawRect:(CGRect)rect {
    BO3ProfileTick(YES);
    CGFloat alpha = _lastOpacity;
    for (int i = 0; i < _lastCount; ++i) {
        xbox_touch_draw c = _lastControls[i];
        if (c.icon == XBOX_TOUCH_ICON_MENU) continue; /* accessible UIKit button above */
        CGFloat r = c.r;
        CGRect bounds = CGRectMake(c.x-r, c.y-r, 2*r, 2*r);
        if(!CGRectIntersectsRect(rect,CGRectInset(bounds,-3,-3))) continue;
        /* Match the PS2 overlay: faint at rest, clear while held. The
         * visibility preference applies to labels as well as the rings. */
        CGFloat visibility=c.pressed ? MAX(0.6,alpha) : alpha;
        [[UIColor colorWithWhite:0.08 alpha:visibility*0.2] setFill];
        [[UIColor colorWithWhite:1 alpha:visibility*0.6] setStroke];
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:bounds];
        circle.lineWidth = c.pressed ? 2.5 : 1.5;
        [circle fill]; [circle stroke];
        NSString *label = c.label ? [NSString stringWithUTF8String:c.label] : @"";
        if (c.icon == XBOX_TOUCH_ICON_PAUSE) {
            UIImage *icon=[[UIImage systemImageNamed:@"pause.fill"] imageWithTintColor:[UIColor colorWithWhite:1 alpha:visibility] renderingMode:UIImageRenderingModeAlwaysOriginal];
            [icon drawInRect:CGRectMake(c.x-8,c.y-9,16,18)];
            continue;
        }
        if (c.kind == XBOX_TOUCH_KIND_DPAD) label = @"✛";
        if (c.kind == XBOX_TOUCH_KIND_STICK) {
            const CGPoint directions[]={{0,-1},{1,0},{0,1},{-1,0}};
            for(int k=0;k<4;k++) {
                CGPoint d=directions[k];
                CGFloat strength=MAX(0,d.x*(c.kx-c.x)+d.y*(c.ky-c.y))/MAX(1,r*0.65);
                [[UIColor colorWithWhite:1 alpha:visibility*(0.25+0.75*MIN(1,strength))] setStroke];
                CGPoint tip=CGPointMake(c.x+d.x*r*0.84,c.y+d.y*r*0.84);
                UIBezierPath *tick=[UIBezierPath bezierPath];
                [tick moveToPoint:CGPointMake(tip.x-d.x*4-d.y*3,tip.y-d.y*4+d.x*3)];
                [tick addLineToPoint:tip];
                [tick addLineToPoint:CGPointMake(tip.x-d.x*4+d.y*3,tip.y-d.y*4-d.x*3)];
                tick.lineWidth=1.5; tick.lineCapStyle=kCGLineCapRound; [tick stroke];
            }
        } else {
            if([label isEqualToString:@"BREAKER"]) label=@"CRASH";
            NSDictionary *attributes = @{
                NSFontAttributeName:[UIFont systemFontOfSize:MAX(11,MIN(16,r*0.36)) weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:visibility]
            };
            CGSize size = [label sizeWithAttributes:attributes];
            [label drawAtPoint:CGPointMake(c.x-size.width/2,c.y-size.height/2) withAttributes:attributes];

        }
    }
}
- (void)sendTouches:(NSSet<UITouch *> *)touches kind:(int)kind {
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        xbox_InputTouchFinger(kind, (int64_t)(uintptr_t)touch, p.x, p.y);
    }
    [self redraw:self.clock];
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { (void)event; [self sendTouches:touches kind:XBOX_TOUCH_DOWN]; }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { (void)event; [self sendTouches:touches kind:XBOX_TOUCH_MOVE]; }
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { (void)event; [self sendTouches:touches kind:XBOX_TOUCH_UP]; }
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { (void)event; [self sendTouches:touches kind:XBOX_TOUCH_CANCEL]; }
@end

void bo3_ios_attach_touch(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
                if (candidate.isKeyWindow) window = candidate;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!window) window = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    UIView *host = window.rootViewController.view;
    if (!host || host.bounds.size.width <= 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/2), dispatch_get_main_queue(), ^{ bo3_ios_attach_touch(); });
        return;
    }
    BO3ApplyTouchPreferences();
    BO3ProfileStart();
    TakedawnTouchView *view = [[TakedawnTouchView alloc] initWithFrame:host.bounds];
    [host addSubview:view];
    [view release];
}
