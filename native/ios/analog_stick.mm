#import "analog_stick.h"
#include "apple_touch_input.h"
#include <cmath>

@interface AnalogStick ()
@property(nonatomic, strong) UIView *thumb;
@property(nonatomic) CGPoint position;
- (void)returnToCenterAnimated:(BOOL)animated;
@end
@implementation AnalogStick
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.alpha = 0.24;
        self.exclusiveTouch = NO;
        self.thumb = [UIView new];
        self.thumb.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.35];
        self.thumb.layer.borderColor = UIColor.whiteColor.CGColor;
        self.thumb.layer.borderWidth = 1.5;
        self.thumb.userInteractionEnabled = NO;
        [self addSubview:self.thumb];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    [[UIColor.whiteColor colorWithAlphaComponent:0.6] setStroke];
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 2, 2)];
    circle.lineWidth = 1.5;
    [circle stroke];
    // Like the takehome controller: quiet direction cues brighten with pressure.
    CGFloat cx = CGRectGetMidX(self.bounds), cy = CGRectGetMidY(self.bounds);
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2 - 11;
    const CGPoint directions[] = {{0,-1}, {1,0}, {0,1}, {-1,0}};
    for (CGPoint direction : directions) {
        CGFloat strength = MAX(0, direction.x * self.position.x + direction.y * self.position.y);
        [[UIColor.whiteColor colorWithAlphaComponent:0.25 + 0.75 * strength] setStroke];
        CGPoint tip = CGPointMake(cx + radius * direction.x, cy + radius * direction.y);
        UIBezierPath *chevron = [UIBezierPath bezierPath];
        [chevron moveToPoint:CGPointMake(tip.x - 4 * direction.x - 3 * direction.y,
            tip.y - 4 * direction.y + 3 * direction.x)];
        [chevron addLineToPoint:tip];
        [chevron addLineToPoint:CGPointMake(tip.x - 4 * direction.x + 3 * direction.y,
            tip.y - 4 * direction.y - 3 * direction.x)];
        chevron.lineWidth = 1.5;
        chevron.lineCapStyle = kCGLineCapRound;
        [chevron stroke];
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat diameter = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat thumbSize = MAX(44, diameter * 0.4);
    self.thumb.bounds = CGRectMake(0, 0, thumbSize, thumbSize);
    self.thumb.layer.cornerRadius = thumbSize / 2;
    CGFloat travel = MAX(1, (diameter - thumbSize) / 2 - 2);
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds) + self.position.x * travel,
        CGRectGetMidY(self.bounds) + self.position.y * travel);
}
- (void)setPosition:(CGPoint)point {
    [self.thumb.layer removeAnimationForKey:@"returnToCenter"];
    CGFloat length = hypot(point.x, point.y);
    if (length > 1) { point.x /= length; point.y /= length; }
    _position = point;
    applehost::SetTouchStick((unsigned)self.stickIndex, float(point.x), float(point.y));
    self.accessibilityValue = [NSString stringWithFormat:@"Horizontal %.0f percent, vertical %.0f percent", point.x * 100, point.y * 100];
    [self setNeedsLayout];
    [self setNeedsDisplay];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)trackTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGFloat diameter = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat travel = MAX(1, (diameter - MAX(44, diameter * 0.4)) / 2 - 2);
    [self setPosition:CGPointMake((point.x - CGRectGetMidX(self.bounds)) / travel,
        (point.y - CGRectGetMidY(self.bounds)) / travel)];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.1
        delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{ self.alpha = 0.6; } completion:nil];
    [self trackTouch:touch];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self trackTouch:touch];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self returnToCenterAnimated:YES];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self returnToCenterAnimated:NO];
}
- (void)returnToCenterAnimated:(BOOL)animated {
    [self layoutIfNeeded];
    BOOL returning = [self.thumb.layer animationForKey:@"returnToCenter"] != nil;
    CGPoint from = returning && self.thumb.layer.presentationLayer ? self.thumb.layer.presentationLayer.position : self.thumb.center;
    // Neutral reaches the game immediately. Only the thumb has spring inertia.
    [self setPosition:CGPointZero];
    [self layoutIfNeeded];
    BOOL spring = animated && !UIAccessibilityIsReduceMotionEnabled();
    if (spring && hypot(from.x - self.thumb.center.x, from.y - self.thumb.center.y) > 0.5) {
        CASpringAnimation *bounce = [CASpringAnimation animationWithKeyPath:@"position"];
        bounce.mass = 1;
        bounce.stiffness = 800;
        bounce.damping = 30;
        bounce.fromValue = [NSValue valueWithCGPoint:from];
        bounce.toValue = [NSValue valueWithCGPoint:self.thumb.center];
        bounce.duration = bounce.settlingDuration;
        [self.thumb.layer addAnimation:bounce forKey:@"returnToCenter"];
    }
    [UIView animateWithDuration:spring ? 0.18 : 0 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{ self.alpha = 0.24; } completion:nil];
}
- (void)accessibilityIncrement { [self setPosition:CGPointMake(MIN(1, self.position.x + 0.25), self.position.y)]; }
- (void)accessibilityDecrement { [self setPosition:CGPointMake(MAX(-1, self.position.x - 0.25), self.position.y)]; }
@end
