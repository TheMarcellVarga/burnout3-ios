#import <UIKit/UIKit.h>
@interface AnalogStick : UIControl
@property(nonatomic) NSUInteger stickIndex;
@property(nonatomic, readonly) CGPoint position;
- (void)setPosition:(CGPoint)position;
- (void)refreshVisibility;
@end
