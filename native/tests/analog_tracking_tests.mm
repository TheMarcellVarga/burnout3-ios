// Exercise the Objective-C selectors UIKit actually dispatches. These checks
// intentionally avoid setPosition:, which would bypass a broken touch handler.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "analog_stick.h"
#include "apple_touch_input.h"
#include "ps2host/run.h"

@interface BurnoutTrackingTestTouch : NSObject
@property(nonatomic) CGPoint location;
- (CGPoint)locationInView:(UIView *)view;
@end
@implementation BurnoutTrackingTestTouch
- (CGPoint)locationInView:(UIView *)view { return self.location; }
@end

NSDictionary *RunAnalogTrackingChecks(AnalogStick *left, AnalogStick *right, UIView *root) {
    NSMutableArray<NSString *> *failures = [NSMutableArray new];
    NSMutableDictionary *samples = [NSMutableDictionary new];
    unsigned checks = 0;
    auto check = [&](bool passed, NSString *name) { ++checks; if (!passed) [failures addObject:name]; };
    auto pad = [&] {
        ps2host::HostPadState result;
        check(ps2host::HostPad(&result), @"controller connected");
        return result;
    };
    auto remember = [&](NSString *name, const ps2host::HostPadState& state) {
        samples[name] = @{@"left_x": @(state.sticks[2]), @"left_y": @(state.sticks[3]),
            @"right_x": @(state.sticks[0]), @"right_y": @(state.sticks[1]), @"gas": @(state.r2)};
    };
    for (NSString *name in @[@"beginTrackingWithTouch:withEvent:", @"continueTrackingWithTouch:withEvent:", @"endTrackingWithTouch:withEvent:"]) {
        SEL selector = NSSelectorFromString(name);
        check(class_getMethodImplementation(AnalogStick.class, selector) != class_getMethodImplementation(UIControl.class, selector),
            [@"UIKit override: " stringByAppendingString:name]);
    }
    for (AnalogStick *stick in @[left, right]) {
        CGPoint center = [stick convertPoint:CGPointMake(CGRectGetMidX(stick.bounds), CGRectGetMidY(stick.bounds)) toView:root];
        check([root hitTest:center withEvent:nil] == stick, @"stick touch area is reachable");
    }
    BurnoutTrackingTestTouch *sample = [BurnoutTrackingTestTouch new];
    UITouch *touch = (UITouch *)(id)sample;
    UIControl *leftControl = left, *rightControl = right;
    sample.location = CGPointMake(56, 56);
    check([leftControl beginTrackingWithTouch:touch withEvent:nil], @"left accepts touch");
    sample.location = CGPointMake(72, 40);
    check([leftControl continueTrackingWithTouch:touch withEvent:nil], @"left continues drag");
    applehost::SetTouchButton(9, true);
    auto state = pad(); remember(@"left_drag_with_gas", state);
    check(state.sticks[2] > 180 && state.sticks[2] < 210 && state.sticks[3] > 45 && state.sticks[3] < 85,
        @"left drag produces proportional axes");
    check(state.sticks[0] == 128 && state.sticks[1] == 128 && state.r2 == 255, @"left drag keeps right centered and gas held");
    check(left.position.x > 0.4 && left.position.y < -0.4, @"thumb follows drag");
    sample.location = CGPointMake(56, 56);
    check([rightControl beginTrackingWithTouch:touch withEvent:nil], @"right accepts simultaneous touch");
    sample.location = CGPointMake(24, 88);
    check([rightControl continueTrackingWithTouch:touch withEvent:nil], @"right continues drag");
    state = pad(); remember(@"both_sticks_with_gas", state);
    check(state.sticks[0] < 100 && state.sticks[1] > 150 && state.sticks[2] > 180 && state.r2 == 255,
        @"both sticks and accelerator remain independent");
    [leftControl endTrackingWithTouch:touch withEvent:nil];
    state = pad(); remember(@"left_released", state);
    check(state.sticks[2] == 128 && state.sticks[3] == 128 && state.sticks[0] < 100 && state.r2 == 255,
        @"left release centers only the left stick");
    UIView *thumb = left.subviews.firstObject;
    check(CGPointEqualToPoint(left.position, CGPointZero), @"spring release publishes neutral immediately");
    check(UIAccessibilityIsReduceMotionEnabled() || [thumb.layer animationForKey:@"returnToCenter"] != nil,
        @"release animates visually unless Reduce Motion is enabled");
    sample.location = CGPointMake(40, 56);
    [leftControl beginTrackingWithTouch:touch withEvent:nil];
    state = pad();
    check(state.sticks[2] < 100 && [thumb.layer animationForKey:@"returnToCenter"] == nil,
        @"regrab interrupts spring and updates steering immediately");
    [leftControl cancelTrackingWithEvent:nil];
    check(CGPointEqualToPoint(left.position, CGPointZero) && [thumb.layer animationForKey:@"returnToCenter"] == nil,
        @"cancel clears input without bounce");
    [rightControl cancelTrackingWithEvent:nil];
    state = pad(); remember(@"right_cancelled", state);
    check(state.sticks[0] == 128 && state.sticks[1] == 128 && state.r2 == 255, @"cancel centers right without releasing gas");
    applehost::ReleaseTouchButtons();
    return @{@"passed": @(failures.count == 0), @"checks": @(checks), @"failures": failures, @"samples": samples,
        @"scope": @"UIKit tracking-selector dispatch and hit tests; physical finger input still requires owner verification",
        @"bundle_version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"],
        @"timestamp": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date]};
}
