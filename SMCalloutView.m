#import "SMCalloutView.h"
#import <QuartzCore/QuartzCore.h>

//
// UIView frame helpers - we do a lot of UIView frame fiddling in this class; these functions help keep things readable.
//

@interface UIView (SMFrameAdditions)
@property (nonatomic, assign) CGPoint $origin;
@property (nonatomic, assign) CGSize $size;
@property (nonatomic, assign) CGFloat $x, $y, $width, $height; // normal rect properties
@property (nonatomic, assign) CGFloat $left, $top, $right, $bottom; // these will stretch/shrink the rect
@end

//
// Callout View.
//

NSTimeInterval kSMCalloutViewRepositionDelayForUIScrollView = 1.0/3.0;

#define CALLOUT_DEFAULT_MIN_WIDTH 75 // our image-based background graphics limit us to this minimum width...
#define CALLOUT_DEFAULT_HEIGHT 54 // ...and allow only for this exact height.
#define CALLOUT_DEFAULT_WIDTH 153 // default "I give up" width when we are asked to present in a space less than our min width
#define TITLE_MARGIN 5 // the title view's normal horizontal margin from the edges of our callout view
#define TITLE_TOP 9.5 // the top of the title view when no subtitle is present
#define TITLE_SUB_TOP 3 // the top of the title view when a subtitle IS present
#define TITLE_HEIGHT 22 // title height, fixed
#define SUBTITLE_TOP 25 // the top of the subtitle, when present
#define SUBTITLE_HEIGHT 16 // subtitle height, fixed
#define TITLE_ACCESSORY_MARGIN 0 // the margin between the title and an accessory if one is present (on either side)
#define ACCESSORY_MARGIN 4.5 // the accessory's margin from the edges of our callout view
#define ACCESSORY_TOP 1.5 // the top of the accessory "area" in which accessory views are placed
#define ACCESSORY_HEIGHT 40 // the "suggested" maximum height of an accessory view. shorter accessories will be vertically centered
#define BETWEEN_ACCESSORIES_MARGIN 7 // if we have no title or subtitle, but have two accessory views, then this is the space between them
#define ANCHOR_MARGIN 37 // the smallest possible distance from the edge of our control to the "tip" of the anchor, from either left or right
#define TOP_ANCHOR_MARGIN 13 // all the above measurements assume a bottom anchor! if we're pointing "up" we'll need to add this top margin to everything.
#define BOTTOM_ANCHOR_MARGIN 6 // if using a bottom anchor, we'll need to account for the shadow below the "tip"
#define REPOSITION_MARGIN 10 // when we try to reposition content to be visible, we'll consider this margin around your target rect

#define TOP_SHADOW_BUFFER 2 // height offset buffer to account for top shadow
#define BOTTOM_SHADOW_BUFFER 5 // height offset buffer to account for bottom shadow
#define OFFSET_FROM_ORIGIN 5 // distance to offset vertically from the rect origin of the callout
#define ANCHOR_HEIGHT 5 // height to use for the anchor
#define ANCHOR_MARGIN_MIN 24 // the smallest possible distance from the edge of our control to the edge of the anchor, from either left or right

@implementation SMCalloutView {
    UILabel *titleLabel, *subtitleLabel;
    UIImageView *leftCap, *rightCap, *topAnchor, *bottomAnchor, *leftBackground, *rightBackground;
    SMCalloutArrowDirection arrowDirection;
    BOOL popupCancelled;
}

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _presentAnimation = SMCalloutAnimationBounce;
        _dismissAnimation = SMCalloutAnimationFade;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (UIView *)titleViewOrDefault {
    if (self.titleView)
        // if you have a custom title view defined, return that.
        return self.titleView;
    else {
        if (!titleLabel) {
            // create a default titleView
            titleLabel = [UILabel new];
            titleLabel.$height = TITLE_HEIGHT;
            titleLabel.opaque = NO;
            titleLabel.backgroundColor = [UIColor clearColor];
            titleLabel.font = [UIFont boldSystemFontOfSize:17];
            titleLabel.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1];
//            titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
//            titleLabel.shadowOffset = CGSizeMake(0, -1);
        }
        return titleLabel;
    }
}

- (UIView *)subtitleViewOrDefault {
    if (self.subtitleView)
        // if you have a custom subtitle view defined, return that.
        return self.subtitleView;
    else {
        if (!subtitleLabel) {
            // create a default subtitleView
            subtitleLabel = [UILabel new];
            subtitleLabel.$height = SUBTITLE_HEIGHT;
            subtitleLabel.opaque = NO;
            subtitleLabel.backgroundColor = [UIColor clearColor];
            subtitleLabel.font = [UIFont systemFontOfSize:12];
            subtitleLabel.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1];
//            subtitleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
//            subtitleLabel.shadowOffset = CGSizeMake(0, -1);
        }
        return subtitleLabel;
    }
}

- (SMCalloutBackgroundView *)backgroundView {
    // create our default background on first access only if it's nil, since you might have set your own background anyway.
    return _backgroundView ?: (_backgroundView = [SMCalloutDrawnBackgroundView new]);
}

- (void)rebuildSubviews {
    // remove and re-add our appropriate subviews in the appropriate order
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self setNeedsDisplay];
    
    [self addSubview:self.backgroundView];
    
    if (self.contentView) {
        [self addSubview:self.contentView];
    }
    else {
        if (self.titleViewOrDefault) [self addSubview:self.titleViewOrDefault];
        if (self.subtitleViewOrDefault) [self addSubview:self.subtitleViewOrDefault];
    }
    if (self.leftAccessoryView) [self addSubview:self.leftAccessoryView];
    if (self.rightAccessoryView) [self addSubview:self.rightAccessoryView];
}

- (CGFloat)innerContentMarginLeft {
    if (self.leftAccessoryView)
        return ACCESSORY_MARGIN + self.leftAccessoryView.$width + TITLE_ACCESSORY_MARGIN;
    else
        return TITLE_MARGIN + 9;
}

- (CGFloat)innerContentMarginRight {
    if (self.rightAccessoryView)
        return ACCESSORY_MARGIN + self.rightAccessoryView.$width + TITLE_ACCESSORY_MARGIN;
    else
        return TITLE_MARGIN;
}

- (CGFloat)calloutHeight {
    if (self.contentView)
        return self.contentView.$height + TITLE_TOP*2 + ANCHOR_HEIGHT + BOTTOM_ANCHOR_MARGIN;
    else
        return CALLOUT_DEFAULT_HEIGHT;
}

- (CGSize)sizeThatFits:(CGSize)size {
    
    // odd behavior, but mimicking the system callout view
    if (size.width < CALLOUT_DEFAULT_MIN_WIDTH)
        return CGSizeMake(CALLOUT_DEFAULT_WIDTH, self.calloutHeight);
    
    // calculate how much non-negotiable space we need to reserve for margin and accessories
    CGFloat margin = self.innerContentMarginLeft + self.innerContentMarginRight;
    
    // how much room is left for text?
    CGFloat availableWidthForText = size.width - margin;

    // no room for text? then we'll have to squeeze into the given size somehow.
    if (availableWidthForText < 0)
        availableWidthForText = 0;

    CGSize preferredTitleSize = [self.titleViewOrDefault sizeThatFits:CGSizeMake(availableWidthForText, TITLE_HEIGHT)];
    CGSize preferredSubtitleSize = [self.subtitleViewOrDefault sizeThatFits:CGSizeMake(availableWidthForText, SUBTITLE_HEIGHT)];
    
    // total width we'd like
    CGFloat preferredWidth;
    
    if (self.contentView) {
        
        // if we have a content view, then take our preferred size directly from that
        preferredWidth = self.contentView.$width + margin;
    }
    else if (preferredTitleSize.width >= 0.000001 || preferredSubtitleSize.width >= 0.000001) {
        
        // if we have a title or subtitle, then our assumed margins are valid, and we can apply them
        preferredWidth = fmaxf(preferredTitleSize.width, preferredSubtitleSize.width) + margin;
    }
    else {
        // ok we have no title or subtitle to speak of. In this case, the system callout would actually not display
        // at all! But we can handle it.
        preferredWidth = self.leftAccessoryView.$width + self.rightAccessoryView.$width + ACCESSORY_MARGIN*2;
        
        if (self.leftAccessoryView && self.rightAccessoryView)
            preferredWidth += BETWEEN_ACCESSORIES_MARGIN;
    }
    
    // ensure we're big enough to fit our graphics!
    preferredWidth = fmaxf(preferredWidth, CALLOUT_DEFAULT_MIN_WIDTH);
    
    // ask to be smaller if we have space, otherwise we'll fit into what we have by truncating the title/subtitle.
    return CGSizeMake(fminf(preferredWidth, size.width), self.calloutHeight);
}

- (CGSize)offsetToContainRect:(CGRect)innerRect inRect:(CGRect)outerRect {
    CGFloat nudgeRight = fmaxf(0, CGRectGetMinX(outerRect) - CGRectGetMinX(innerRect));
    CGFloat nudgeLeft = fminf(0, CGRectGetMaxX(outerRect) - CGRectGetMaxX(innerRect));
    CGFloat nudgeTop = fmaxf(0, CGRectGetMinY(outerRect) - CGRectGetMinY(innerRect));
    CGFloat nudgeBottom = fminf(0, CGRectGetMaxY(outerRect) - CGRectGetMaxY(innerRect));
    return CGSizeMake(nudgeLeft ?: nudgeRight, nudgeTop ?: nudgeBottom);
}

- (void)presentCalloutFromRect:(CGRect)rect inView:(UIView *)view constrainedToView:(UIView *)constrainedView permittedArrowDirections:(SMCalloutArrowDirection)arrowDirections animated:(BOOL)animated {
    [self presentCalloutFromRect:rect inLayer:view.layer ofView:view constrainedToLayer:constrainedView.layer permittedArrowDirections:arrowDirections animated:animated];
}

- (void)presentCalloutFromRect:(CGRect)rect inLayer:(CALayer *)layer constrainedToLayer:(CALayer *)constrainedLayer permittedArrowDirections:(SMCalloutArrowDirection)arrowDirections animated:(BOOL)animated {
    [self presentCalloutFromRect:rect inLayer:layer ofView:nil constrainedToLayer:constrainedLayer permittedArrowDirections:arrowDirections animated:animated];
}

// this private method handles both CALayer and UIView parents depending on what's passed.
- (void)presentCalloutFromRect:(CGRect)rect inLayer:(CALayer *)layer ofView:(UIView *)view constrainedToLayer:(CALayer *)constrainedLayer permittedArrowDirections:(SMCalloutArrowDirection)arrowDirections animated:(BOOL)animated {
    
    // Sanity check: dismiss this callout immediately if it's displayed somewhere
    if (self.layer.superlayer) [self dismissCalloutAnimated:NO];
    
    // figure out the constrained view's rect in our popup view's coordinate system
    CGRect constrainedRect = [constrainedLayer convertRect:constrainedLayer.bounds toLayer:layer];
    
    // form our subviews based on our content set so far
    [self rebuildSubviews];
    
    // apply title/subtitle (if present
    titleLabel.text = self.title;
    subtitleLabel.text = self.subtitle;
    
    // size the callout to fit the width constraint as best as possible
    self.$size = [self sizeThatFits:CGSizeMake(constrainedRect.size.width, self.calloutHeight)];
    
    // how much room do we have in the constraint box, both above and below our target rect?
    CGFloat topSpace = CGRectGetMinY(rect) - CGRectGetMinY(constrainedRect);
    CGFloat bottomSpace = CGRectGetMaxY(constrainedRect) - CGRectGetMaxY(rect);
    
    // we prefer to point our arrow down.
    SMCalloutArrowDirection bestDirection = SMCalloutArrowDirectionDown;
    
    // we'll point it up though if that's the only option you gave us.
    if (arrowDirections == SMCalloutArrowDirectionUp)
        bestDirection = SMCalloutArrowDirectionUp;
    
    // or, if we don't have enough space on the top and have more space on the bottom, and you
    // gave us a choice, then pointing up is the better option.
    if (arrowDirections == SMCalloutArrowDirectionAny && topSpace < self.calloutHeight && bottomSpace > topSpace)
        bestDirection = SMCalloutArrowDirectionUp;
    
    // show the correct anchor based on our decision
    topAnchor.hidden = (bestDirection == SMCalloutArrowDirectionDown);
    bottomAnchor.hidden = (bestDirection == SMCalloutArrowDirectionUp);
    arrowDirection = bestDirection;
    
    // we want to point directly at the horizontal center of the given rect. calculate our "anchor point" in terms of our
    // target view's coordinate system. make sure to offset the anchor point as requested if necessary.
    CGFloat anchorX = self.calloutOffset.x + CGRectGetMidX(rect);
    CGFloat anchorY = self.calloutOffset.y + (bestDirection == SMCalloutArrowDirectionDown ? CGRectGetMinY(rect) : CGRectGetMaxY(rect));
    
    // we prefer to sit in the exact center of our constrained view, so we have visually pleasing equal left/right margins.
    CGFloat calloutX = roundf(CGRectGetMidX(constrainedRect) - self.$width / 2);
    
    // what's the farthest to the left and right that we could point to, given our background image constraints?
    CGFloat minPointX = calloutX + ANCHOR_MARGIN;
    CGFloat maxPointX = calloutX + self.$width - ANCHOR_MARGIN;
    
    // we may need to scoot over to the left or right to point at the correct spot
    CGFloat adjustX = 0;
    if (anchorX < minPointX) adjustX = anchorX - minPointX;
    if (anchorX > maxPointX) adjustX = anchorX - maxPointX;
    
    // add the callout to the given layer (or view if possible, to receive touch events)
    if (view)
        [view addSubview:self];
    else
        [layer addSublayer:self.layer];
    
    CGPoint calloutOrigin = {
        .x = calloutX + adjustX,
        .y = bestDirection == SMCalloutArrowDirectionDown ? (anchorY - self.calloutHeight + BOTTOM_ANCHOR_MARGIN) : anchorY
    };
    
    _currentArrowDirection = bestDirection;
    
    self.$origin = calloutOrigin;
    
    // now set the *actual* anchor point for our layer so that our "popup" animation starts from this point.
    CGPoint anchorPoint = [layer convertPoint:CGPointMake(anchorX, anchorY) toLayer:self.layer];
    
    // pass on the anchor point to our background view so it knows where to draw the arrow
    self.backgroundView.arrowPoint = anchorPoint;

    // adjust it to unit coordinates for the actual layer.anchorPoint property
    anchorPoint.x /= self.$width;
    anchorPoint.y /= self.$height;
    self.layer.anchorPoint = anchorPoint;
    
    // setting the anchor point moves the view a bit, so we need to reset
    self.$origin = calloutOrigin;
    
    // make sure our frame is not on half-pixels or else we may be blurry!
    self.frame = CGRectIntegral(self.frame);

    // layout now so we can immediately start animating to the final position if needed
    [self setNeedsLayout];
    [self layoutIfNeeded];
    
    // if we're outside the bounds of our constraint rect, we'll give our delegate an opportunity to shift us into position.
    // consider both our size and the size of our target rect (which we'll assume to be the size of the content you want to scroll into view.
    CGRect contentRect = CGRectUnion(self.frame, CGRectInset(rect, -REPOSITION_MARGIN, -REPOSITION_MARGIN));
    CGSize offset = [self offsetToContainRect:contentRect inRect:constrainedRect];
    
    NSTimeInterval delay = 0;
    popupCancelled = NO; // reset this before calling our delegate below
    
    if ([self.delegate respondsToSelector:@selector(calloutView:delayForRepositionWithSize:)] && !CGSizeEqualToSize(offset, CGSizeZero))
        delay = [self.delegate calloutView:self delayForRepositionWithSize:offset];
    
    // there's a chance that user code in the delegate method may have called -dismissCalloutAnimated to cancel things; if that
    // happened then we need to bail!
    if (popupCancelled) return;
    
    // if we need to delay, we don't want to be visible while we're delaying, so hide us in preparation for our popup
    self.hidden = YES;
    
    // create the appropriate animation, even if we're not animated
    CAAnimation *animation = [self animationWithType:self.presentAnimation presenting:YES];
    
    // nuke the duration if no animation requested - we'll still need to "run" the animation to get delays and callbacks
    if (!animated)
        animation.duration = 0.0000001; // can't be zero or the animation won't "run"
    
    animation.beginTime = CACurrentMediaTime() + delay;
    animation.delegate = self;
    
    [self.layer addAnimation:animation forKey:@"present"];
}

- (void)animationDidStart:(CAAnimation *)anim {
    BOOL presenting = [[anim valueForKey:@"presenting"] boolValue];

    if (presenting) {
        if ([_delegate respondsToSelector:@selector(calloutViewWillAppear:)])
            [_delegate calloutViewWillAppear:self];
        
        // ok, animation is on, let's make ourselves visible!
        self.hidden = NO;
    }
    else if (!presenting) {
        if ([_delegate respondsToSelector:@selector(calloutViewWillDisappear:)])
            [_delegate calloutViewWillDisappear:self];
    }
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)finished {
    BOOL presenting = [[anim valueForKey:@"presenting"] boolValue];
    
    if (presenting) {
        if ([_delegate respondsToSelector:@selector(calloutViewDidAppear:)])
            [_delegate calloutViewDidAppear:self];
    }
    else if (!presenting) {
        
        [self removeFromParent];
        [self.layer removeAnimationForKey:@"dismiss"];

        if ([_delegate respondsToSelector:@selector(calloutViewDidDisappear:)])
            [_delegate calloutViewDidDisappear:self];
    }
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // we want to match the system callout view, which doesn't "capture" touches outside the accessory areas. This way you can click on other pins and things *behind* a translucent callout.
    return
        [self.leftAccessoryView pointInside:[self.leftAccessoryView convertPoint:point fromView:self] withEvent:nil] ||
        [self.rightAccessoryView pointInside:[self.rightAccessoryView convertPoint:point fromView:self] withEvent:nil] ||
        [self.contentView pointInside:[self.contentView convertPoint:point fromView:self] withEvent:nil] ||
        (!self.contentView && [self.titleView pointInside:[self.titleView convertPoint:point fromView:self] withEvent:nil]) ||
        (!self.contentView && [self.subtitleView pointInside:[self.subtitleView convertPoint:point fromView:self] withEvent:nil]);
}

- (void)dismissCalloutAnimated:(BOOL)animated {
    [self.layer removeAnimationForKey:@"present"];
    
    popupCancelled = YES;
    
    if (animated) {
        CAAnimation *animation = [self animationWithType:self.dismissAnimation presenting:NO];
        animation.delegate = self;
        [self.layer addAnimation:animation forKey:@"dismiss"];
    }
    else [self removeFromParent];
}

- (void)removeFromParent {
    if (self.superview)
        [self removeFromSuperview];
    else {
        // removing a layer from a superlayer causes an implicit fade-out animation that we wish to disable.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self.layer removeFromSuperlayer];
        [CATransaction commit];
    }
}

- (CAAnimation *)animationWithType:(SMCalloutAnimation)type presenting:(BOOL)presenting {
    CAAnimation *animation = nil;
    
    if (type == SMCalloutAnimationBounce) {
        CAKeyframeAnimation *bounceAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        CAMediaTimingFunction *easeInOut = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        
        bounceAnimation.values = @[@0.05, @1.11245, @0.951807, @1.0];
        bounceAnimation.keyTimes = @[@0, @(4.0/9.0), @(4.0/9.0+5.0/18.0), @1.0];
        bounceAnimation.duration = 1.0/3.0; // the official bounce animation duration adds up to 0.3 seconds; but there is a bit of delay introduced by Apple using a sequence of callback-based CABasicAnimations rather than a single CAKeyframeAnimation. So we bump it up to 0.33333 to make it feel identical on the device
        bounceAnimation.timingFunctions = @[easeInOut, easeInOut, easeInOut, easeInOut];
        
        if (!presenting)
            bounceAnimation.values = [[bounceAnimation.values reverseObjectEnumerator] allObjects]; // reverse values
        
        animation = bounceAnimation;
    }
    else if (type == SMCalloutAnimationFade) {
        CABasicAnimation *fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeAnimation.duration = 1.0/3.0;
        fadeAnimation.fromValue = presenting ? @0.0 : @1.0;
        fadeAnimation.toValue = presenting ? @1.0 : @0.0;
        animation = fadeAnimation;
    }
    else if (type == SMCalloutAnimationStretch) {
        CABasicAnimation *stretchAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        stretchAnimation.duration = 0.1;
        stretchAnimation.fromValue = presenting ? @0.0 : @1.0;
        stretchAnimation.toValue = presenting ? @1.0 : @0.0;
        animation = stretchAnimation;
    }
    
    // CAAnimation is KVC compliant, so we can store whether we're presenting for lookup in our delegate methods
    [animation setValue:@(presenting) forKey:@"presenting"];
    
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    return animation;
}

- (CGFloat)centeredPositionOfView:(UIView *)view ifSmallerThan:(CGFloat)height {
    return view.$height < height ? floorf(height/2 - view.$height/2) : 0;
}

- (CGFloat)centeredPositionOfView:(UIView *)view relativeToView:(UIView *)parentView {
    return roundf((parentView.$height - view.$height) / 2);
}

- (void)layoutSubviews {
    
    self.backgroundView.frame = self.bounds;
    
    // if we're pointing up, we'll need to push almost everything down a bit
    CGFloat dy = arrowDirection == SMCalloutArrowDirectionUp ? TOP_ANCHOR_MARGIN : 0;
    
    self.titleViewOrDefault.$x = self.innerContentMarginLeft;
    self.titleViewOrDefault.$y = (self.subtitleView || self.subtitle.length ? TITLE_SUB_TOP : TITLE_TOP) + dy;
    self.titleViewOrDefault.$width = self.$width - self.innerContentMarginLeft - self.innerContentMarginRight;
    
    self.subtitleViewOrDefault.$x = self.titleViewOrDefault.$x;
    self.subtitleViewOrDefault.$y = SUBTITLE_TOP + dy;
    self.subtitleViewOrDefault.$width = self.titleViewOrDefault.$width;
    
    self.leftAccessoryView.$x = ACCESSORY_MARGIN;
    if (self.contentView)
        self.leftAccessoryView.$y = TITLE_TOP + [self centeredPositionOfView:self.leftAccessoryView relativeToView:self.contentView] + dy;
    else
        self.leftAccessoryView.$y = ACCESSORY_TOP + [self centeredPositionOfView:self.leftAccessoryView ifSmallerThan:ACCESSORY_HEIGHT] + dy;
    
    self.rightAccessoryView.$x = self.$width-ACCESSORY_MARGIN-self.rightAccessoryView.$width;
    if (self.contentView)
        self.rightAccessoryView.$y = TITLE_TOP + [self centeredPositionOfView:self.rightAccessoryView relativeToView:self.contentView] + dy;
    else
        self.rightAccessoryView.$y = ACCESSORY_TOP + [self centeredPositionOfView:self.rightAccessoryView ifSmallerThan:ACCESSORY_HEIGHT] + dy;
    
    
    if (self.contentView) {
        self.contentView.$x = self.innerContentMarginLeft;
        self.contentView.$y = TITLE_TOP + dy;
    }
}

@end

//
// Callout background base class, includes graphics for +systemBackgroundView
//
@implementation SMCalloutBackgroundView

+ (SMCalloutBackgroundView *)systemBackgroundView {
    SMCalloutImageBackgroundView *background = [SMCalloutImageBackgroundView new];
    background.leftCapImage = [[self embeddedImageNamed:@"SMCalloutViewLeftCap"] resizableImageWithCapInsets:UIEdgeInsetsMake(10, 8, 15, 0)];
    background.rightCapImage = [[self embeddedImageNamed:@"SMCalloutViewRightCap"] resizableImageWithCapInsets:UIEdgeInsetsMake(10, 0, 15, 8)];
    background.topAnchorImage = [[self embeddedImageNamed:@"SMCalloutViewTopAnchor"] stretchableImageWithLeftCapWidth:0 topCapHeight:33];
    background.bottomAnchorImage = [[self embeddedImageNamed:@"SMCalloutViewBottomAnchor"] resizableImageWithCapInsets:UIEdgeInsetsMake(10, 0, 15, 12)];
    background.backgroundImage = [[self embeddedImageNamed:@"SMCalloutViewBackground"] resizableImageWithCapInsets:UIEdgeInsetsMake(10, 0, 15, 0)];
    return background;
}

+ (NSData *)dataWithBase64EncodedString:(NSString *)string {
    //
    //  NSData+Base64.m
    //
    //  Version 1.0.2
    //
    //  Created by Nick Lockwood on 12/01/2012.
    //  Copyright (C) 2012 Charcoal Design
    //
    //  Distributed under the permissive zlib License
    //  Get the latest version from here:
    //
    //  https://github.com/nicklockwood/Base64
    //
    //  This software is provided 'as-is', without any express or implied
    //  warranty.  In no event will the authors be held liable for any damages
    //  arising from the use of this software.
    //
    //  Permission is granted to anyone to use this software for any purpose,
    //  including commercial applications, and to alter it and redistribute it
    //  freely, subject to the following restrictions:
    //
    //  1. The origin of this software must not be misrepresented; you must not
    //  claim that you wrote the original software. If you use this software
    //  in a product, an acknowledgment in the product documentation would be
    //  appreciated but is not required.
    //
    //  2. Altered source versions must be plainly marked as such, and must not be
    //  misrepresented as being the original software.
    //
    //  3. This notice may not be removed or altered from any source distribution.
    //
    const char lookup[] = {
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 62, 99, 99, 99, 63,
        52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 99, 99, 99, 99, 99, 99,
        99,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
        15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 99, 99, 99, 99, 99,
        99, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 99, 99, 99, 99, 99
    };
    
    NSData *inputData = [string dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    long long inputLength = [inputData length];
    const unsigned char *inputBytes = [inputData bytes];
    
    long long maxOutputLength = (inputLength / 4 + 1) * 3;
    NSMutableData *outputData = [NSMutableData dataWithLength:maxOutputLength];
    unsigned char *outputBytes = (unsigned char *)[outputData mutableBytes];
    
    int accumulator = 0;
    long long outputLength = 0;
    unsigned char accumulated[] = {0, 0, 0, 0};
    for (long long i = 0; i < inputLength; i++) {
        unsigned char decoded = lookup[inputBytes[i] & 0x7F];
        if (decoded != 99) {
            accumulated[accumulator] = decoded;
            if (accumulator == 3) {
                outputBytes[outputLength++] = (accumulated[0] << 2) | (accumulated[1] >> 4);
                outputBytes[outputLength++] = (accumulated[1] << 4) | (accumulated[2] >> 2);
                outputBytes[outputLength++] = (accumulated[2] << 6) | accumulated[3];
            }
            accumulator = (accumulator + 1) % 4;
        }
    }
    
    //handle left-over data
    if (accumulator > 0) outputBytes[outputLength] = (accumulated[0] << 2) | (accumulated[1] >> 4);
    if (accumulator > 1) outputBytes[++outputLength] = (accumulated[1] << 4) | (accumulated[2] >> 2);
    if (accumulator > 2) outputLength++;
    
    //truncate data to match actual output length
    outputData.length = outputLength;
    return outputLength? outputData: nil;
}

+ (UIImage *)embeddedImageNamed:(NSString *)name {
    if ([UIScreen mainScreen].scale == 2)
        name = [name stringByAppendingString:@"$2x"];
    
    SEL selector = NSSelectorFromString(name);
    
    if (![(id)self respondsToSelector:selector]) {
        NSLog(@"Could not find an embedded image. Ensure that you've added a category method to UIImage named +%@", name);
        return nil;
    }
    
    // We need to hush the compiler here - but we know what we're doing!
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *base64String = [(id)self performSelector:selector];
    #pragma clang diagnostic pop
    
    UIImage *rawImage = [UIImage imageWithData:[self dataWithBase64EncodedString:base64String]];
    return [UIImage imageWithCGImage:rawImage.CGImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
}

//
// I didn't want this class to require adding any images to your Xcode project. So instead the images needed are embedded below.
//

+ (NSString *)SMCalloutViewBackground { return @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAAxCAYAAAAbb8MkAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAD5JREFUeNpi+P//PwPz/3+/mxmArP9Mf35/YWBiAIIhRoBdD/KHAYhjCRLjZQYSAiCCDUQwgYj/IFlGgAADAKibFkBrntlWAAAAAElFTkSuQmCC"; }
+ (NSString *)SMCalloutViewBackground$2x { return @"iVBORw0KGgoAAAANSUhEUgAAAAIAAABiCAYAAAB6QgJ+AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAFFJREFUeNpiZGBgYARiBhYgZoIxmEEMxt+/Pv9ngAmPMkYZQ5sBSuYxsBT+C4PxE8b4AWN8hzG+YTB+YOgCm8MMxf+YofaBGSDwnxGW0QACDAD4whHYe6Ke0QAAAABJRU5ErkJggg=="; }
+ (NSString *)SMCalloutViewBottomAnchor { return @"iVBORw0KGgoAAAANSUhEUgAAAA0AAAA3CAYAAADXCsC3AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAdZJREFUeNrsls8vA0EUx2e7W6y2SIWQtjhIpAkHEQcHd0G5O3EkqX+A8A84cKt/QHroH+CEkwStg+WCA0mXRFTSH1R3Z3e8x6tslUOdd5JPZvfN9ztv3uwkO5IQgjXalM2NtXXomxvwVCTxj1QKN0tF6AMNeIoe9o/mmlyTa3JNrsk1uaaGW83f3TQKTJLq5xHCZt6mtu93Wdjm0NHhgRbwq2qkbzAohFE7qwRXAG+AZdLHt7uJxD5oLzE+AYyFQqFFmJELYQmjUhCmUfzs8R3j4XBoCXWo99AdYkDX9aud7a0UlinL8tcyPnsPw3g2q2OGAdRDcjZOxoqqtvgfH+732ju6gxzqU6COQv7ppae3f6Fcfi/RdaiIU6mAhRNzzh+fczlrbm5+EouRJJnF46vbJ6dnRzDeAhSAPK6iC+gHosAoMKJdZDTc1UvtXMN3ikdJh3rWCnQCEWAYB2Znppax+lhseoWEwzSOulZcnnCAzXd9c/ukZ+/SyWQqjbsOlIh3wJAoqFCRmNUHeLFg2iATeAXecLMALle/IYHZbALH8EuXSWzShtkKmVDEHSZO59Ki5yo2o2Uxh7j6bDkyW47sorqs306989TaP/o601+xmnvuhwADAMVMwKuVKRm4AAAAAElFTkSuQmCC"; }
+ (NSString *)SMCalloutViewBottomAnchor$2x { return @"iVBORw0KGgoAAAANSUhEUgAAABoAAABuCAYAAAA5+QMZAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAypJREFUeNrsms9rE0EUx3eySRRTBC9NK7YeVGzUKEiv6kGP3jx48h8QFVOo3sSboGm1FwsiUgp6SNJ6FIRSoRYP9qDxBzWKaHuoiSfRrMnuZseZMBNfn7NN20MO8gYeszM7+z7zffN2dg7LLMtiVgdKVFikUyC7EyDmuT95J0AdCRuBCEQgAhGIQAQiEIEIRCACEYhABCIQgQhEIAIRiEAEIhCBCEQgAhGIQAT6H0DyN5Bz1t/fQVh/X9/WYnHhRiKxbcdmHDqO8yOdHry6tLxcE039rwSXijxlvjQxoJrPT+U3O/NcbionfWh/2r9UckYpYiqUzBbl65fS9WSye+9GIJXK98/9u/dda4ii1ASqbiqqC3OBeWKclx25Mwmkr6fwW9nbE/JZpQT6rEsVp5QSaTa04uuXF1KpgRProSwufniePjw4Ji4byKSqQDqvIdMKvczQlYe+79faQcSY+uXM8KRaD1f5qEO/EuQI+22CzczMlufm5qfbgebnXzyWYwGkBnzK2pGhS4Fwyf+EYsDivb09iffvXt3t6kp0myDVqlNJHThyfmXlW1VHAmVyM4QRgxIYPlc6yOUKD8LUFArTEwDiIh8t31LRTqQojmyLVLe89OlmT08yDSHlcuXtrr49w2r2OHtdrMhFg+qmlBepO845D1q5LK5HRsfGQQKEPd+8loq2q9SOgjXSSmAde1NcyAwM7D8tQaXSxycHDx3NokyDtQd2hyACOjxkLp7txUtD90Uq/5Imru9h1YZkaPlmarbwZY0ZVMVVn/1s9ulZuUUdO37ykYq/KXQa0nppmXIeMaQ4BMR1aMX+F1OJ4KGNE6vzMSgCNlTbsFZaYRRMylJbSwOFHa+N3oK4jb5NptoCO3GAAD5aY92vx3BtUeRMO2TqAXivoRQx1BcAqA8mw+HuH0WfAg2yDH22csxQfyNkx+ZrKQpM3xlwD58xcDgDZKsUaWfM4Bi2I+BLjMcFYSHT18xwWFn1WQ9pYxBfo71KkRWyLhDEDRPjIWY8blkhqsJSHiuyQmreDhT2LrE11FshwFax2xwu13X6adPekDO2Qdg/5Y8AAwDhf72/OMoBXQAAAABJRU5ErkJggg=="; }
+ (NSString *)SMCalloutViewLeftCap { return @"iVBORw0KGgoAAAANSUhEUgAAAAkAAAAxCAYAAAAIuIPQAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAQFJREFUeNrslU0KwjAQhSdtrVq1KugpBC+g4M6lLsRDCEXoAb1CPUyh1f4kTnRGYrCI+wZeGZpv3iRdvDpKKfglTwgBxhK+76soOq3DcLKVdak37ybg6EccnzfKWp4BuCg5n8/2+kVVpOj7nJI6ttMtv6nXYPGxIUgunwusxU6uAXWaILvhKySsutEJ/oGghVqohVoIg9b5CQWDwH9VshEKkuR60YXXCVFDrRHnpY7APirUwPF42C0Wy5WU9x4oyE2oixqhxqiCYnGKqjnHa5JO/5wcA9SQIUWqySGjxoKa3n8Evk5J49k1MyG+L7tWxrnAdgJj9Du2Pes7yW9R/RBgALRiZvBSF/6TAAAAAElFTkSuQmCC"; }
+ (NSString *)SMCalloutViewLeftCap$2x { return @"iVBORw0KGgoAAAANSUhEUgAAABIAAABiCAYAAABd7IOWAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAbZJREFUeNrsmTtOAzEQhj22EyAIqPK4AELALbgAt+ICoJyBe6AoBSUVUEEbJKQQoNkHWWRHjpnxenddUMxKo304/jz/780WMyCaHxD9kBiH0DjUAHwQ9ZxcBfzr15fn49FoeKWUuljfHvqTdAREPj0+nEwm4zsAOIr1wN5LF/T99X6rtb4MmSkD0sCMKyNHxIAAiV9IFWtJB7EgNxvpQhAfG0mTDqQRCJMl22bkQxqDgICprhlhsNZm+7BGZmMQIBaLkoYZ31kaRHyzSFDTj180SKQAQVcQpM6IQQxiEIMYxCAGMYhBDGIQgxjEIAb9G1CZOqMyqbQ8zz9TgMrF4u2+Daj04/pmOs2ybBUCVfUzrKa2VfWbzear5fJjfnZ+Ot4fDIZSyp4PciF2Ys9Efx27JvbMecdE3/xGm0WlrpFWVF6byJzFbFmosAp8aX5lFAvAFlSIRCnwEiIEst4CCYFX/PzqHypdBcynug6Yf7kiANQGFD7AboRGJhSB/52FKN8/qqALAZAL3GQXeo+Ek13pbH+BeQmE2aLmdfizGdEtn8Bukr0jIRI1oSjTW7XFYuGb40eAAQDM12Mzzq2kawAAAABJRU5ErkJggg=="; }
+ (NSString *)SMCalloutViewRightCap { return @"iVBORw0KGgoAAAANSUhEUgAAAAkAAAAxCAYAAAAIuIPQAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAR1JREFUeNrslMFqwkAQhmc3iaKtJ/VNeu8r+CSCV6v2JQTfoBfpCxQED+1VQfAxRI2lxo1mnElnZTVq6T0Lf7LMfPtP2MCvERH+kup12x0AKGovwDBcffT7g09jjKIagl14sVqt5rO0tGX0Pv7ekGBvNmmhXq81pOdZ8ESDUukr2kZJxgmySzlOvFfXoMCBvFtO3n/Gabu/B8E9J8ihHMqhHFIqm1lO4TcFyw/lwiXk+8FjxS1MJtMRs2fQa+/ljRKppHUxms9nX8Ph+5jqVVJos5wD60kicEk6kHjcmsSZvSPFPj0qTtL+iMNODhzSceLAwJZjXEAjAI9DhhYCxdKMRcnpw2U2OPZWiQV9GWMvCh2dORnnSvDabzkKMAC7e38ndgWhVgAAAABJRU5ErkJggg=="; }
+ (NSString *)SMCalloutViewRightCap$2x { return @"iVBORw0KGgoAAAANSUhEUgAAABIAAABiCAYAAABd7IOWAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAd9JREFUeNrsmTtOw0AQhndtQ4MQFyAtiIIj0HELjsMBUhiFY3AOCg6AkFBCQ6RQEIFwYq93iGE3jDeztjdxQTEjjZTHzud/HnYxlkIIKWgDEWAVJG4Jhi7wBIGoAOistsg/gPD5Inu/e5k8nZmL2QtGxjfKIatAn1wAmI/Hk4uT0/PH1VdtlGC169iosYBSHg0Gx9dISYRiJFaWtHUjjuNLVEeNIOAWW7SoOnA6q4kaQdJxTKhzGqvaBgRU+0NAYFREKD2bIkQBoNjpXK1roaCYglSfu4IoyFaKKEjNuoIshILJUFBEAIJTk77abANqldyLhYBk34rkv0mNQQxiEIMYxCAGMYhBDGIQgxjEIAb1DYJdQbCTorIss15Sm83e7kWH3XYjSCn1md6MRuJv94i9ZokHkL1Opw/DYXqbpqNn8bt3bNweJ3v7h1fooFp5sfJ85UvjGKIJVWAVFeZAabwwQOv2d92WWu6AVACstvRdOqlZzx0gBVvPWAVaIFCJAgvkCkGowv8oypwDFMwFbaRXgb5QR9xaKaJW2lfszGkthmFoSaiqgRZIogtzVWrflNuuUX9qwlvnyB17ICa5+RYxXRGeQ75AoGqkiAeXL8D7cqq312LkbrrLo9W1bwEGAFvzKdul23CXAAAAAElFTkSuQmCC"; }
+ (NSString *)SMCalloutViewTopAnchor { return @"iVBORw0KGgoAAAANSUhEUgAAACkAAABGCAYAAABRwr15AAAAHGlET1QAAAACAAAAAAAAACMAAAAoAAAAIwAAACMAAAQYDCloiwAAA+RJREFUaAXMVslKHFEUfSaaaPIFunDaulJj2/QQBxxwVtCFC9GFCxVRUHHAARVx1pWf9QKVNCGb5FvMPUWf5vazqu0qFVwc7nTuvaeedr0yj4+P5qUwxlQoVCq/4qWz0R9boBLyQXwfzc3N31paWn7CMpe3/kPEFRxLZF4gxX2UuLKpqSkxOTn56/T09DcsYuQFqJMb62Qji5SFOBUs9cWJ/dTY2JiEsPv7e+/s7OwHLGLkURdosZGFRhIpyygQS6sE1Q0NDampqakchMkpWgIx8qiDl+ejDw8YSWjZIjE4vwCLcDrV9fX1aQi5u7vzBZ6cnBREQiyFggd+vi+y0LJEynBXYI0szsif1BcIccfHx0+APB4APPBlTk0coc+KDBM4MTGRu7299SDk6OgoFKiDB35coSVFhgkcGxvLXV1deRB3eHhoDw4OiixyGjjlm5sbD31xhIaKDBM4Ojqau7y89AXu7+/bvb09C/sc8EDoQ39UoYEiwwQODw/nLi4uPJzc7u5uZKAP/SMjI5GEPhEZJnBoaCh3fn7uQdzW1pbd3t72resjZg4cgnn0Yw7mlXuiRSKDBNbV1WUwUF4p3s7Ojt3Y2CjC5uamH8NqHzzmXIs5mIe5mC97S/7qpV64svQt8lnyX2pra7MDAwO+QCxaW1vzsb6+bgk3FxSTqy3myS/fw3zswT4B9uI9qq9S6PJvDtweeEGDhKf6Ko3f+/v7c/LL9DB8dXX11YG5mI892Ie9+f3QAT3QVWV6enr+uejt7f07PT39R14j3srKil1aWirC8vJyUezW3bgUH/OxB/uw19WC2Dw8PNggXF9f+0IWFxftWwMPhX1BOpAzCwsL1sX8/LwFmKdPyzxsGJecoB7Wwix7aM3c3Jx97zCzs7P2vcPMzMxY+ae1sHERpd/lunGQBiOfUVa+CS2si7C85mlOmB+2o1y+GR8ft4Bc/EXWzSOWz60iDnuCuMwFWfbBBvnoYR6+kY8GqyGXvx/D0medsVuT660wgxy3h7Fr2cs+WvJQN3It2cHBQR/wCZ2DX4rHGnvd2J3lztN13Uue6evrs4C87X0bFjP/mtbdGTYb16Iluru7C36pHGvavqRXz6Gv55lsNmuJrq4uq4E8YteSwz7WycUCnWMeljW3l3zWdY/JZDL2vcOkUikbhGQyWcin0+mCH8SNmtPz6Ot97jzT2dlpCRDpw7qxrr2l7+41iUTCamA5Y/raUhw5sMyR59Y0R9eYD8txXpHIjo4OXyCtbg7K6Tr953il6m6NsWlvb7floq2trWyunhm3jzMMBgShtbXVAlFq5MfpxR7dz73I/QcAAP//R6Pt0AAAASZJREFU7VK7asNAEBwCblKltISkImrUWEhl+tQuU+WT7xfyL94TjNksdzIkZ7yGMwyzj9m9YWWs6xpuYVmWm5rcjhKzmOc55BAfYE/HrO2x1ut4b4Y9rY8x+r4PFl3XhQjWGVtmX/M9ZsGlnnkz2bbtdjkaZU5mPcVWY/PUDGvUWmafjCjQIuY5joO2l6pZTcxTulTNzl5NNk0TiCjKxXaB1sYZndv4r7PQi/VSmiTzAeZkzpBZ1/zf2c0kF+49RE2O7zn7y2TOwKPr1WSpL1AvWS9Z6gKl9tT/ZL1kqQuU2oNhGIJ3YJqm4B0Yx/HHOyC/7ycAvsSkd+AsJr0Dn2LSO/AhJr0DJzHpHXgXk96Bo5j0DryJSe/Aq5j0DhzEpHfgRUy6xgX1iUkAQX47jAAAAABJRU5ErkJggg=="; }
+ (NSString *)SMCalloutViewTopAnchor$2x { return @"iVBORw0KGgoAAAANSUhEUgAAAFIAAACMCAYAAADvGP7EAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyRpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMy1jMDExIDY2LjE0NTY2MSwgMjAxMi8wMi8wNi0xNDo1NjoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENTNiAoTWFjaW50b3NoKSIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo5QUY0RkNERjZENDMxMUUyQTAzNEREMUIxRjIzOEVCNSIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo5QUY0RkNFMDZENDMxMUUyQTAzNEREMUIxRjIzOEVCNSI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOjdFQUM5NTk0NkJGQjExRTJBMDM0REQxQjFGMjM4RUI1IiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOjlBRjRGQ0RFNkQ0MzExRTJBMDM0REQxQjFGMjM4RUI1Ii8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+zk9a9AAABhtJREFUeNrsnclO41gUhm3HDGEo5jGAQLwDsxjFICR2JVFVza4fAVFdD9H1ALxA9yPAhg0S6170mnmeCVMSyNDnt3LT7jSIQJzEgf9IVkJw7OuP/5zz3+sAeiwW0xjph0EEHwTkzMzMl+np6W8EmSZEKT2/GYax4HaYhtsh1tfXa9jcDtOVICcnJ78qiCMjIxVNTU12mL+4ccy6G7q2LqGeT0xMfCkoKPgOcH19faUyPl0AahsbG7eHh4faycmJFo1Gf19aWvpDvSfmgovIKUg7QHwpEGcBsaamRuvq6vIGAoHow8ND1OPx6GVlZZ69vb3AwcGBdn5+rmD+CY5uAJozkDaIuk2JCwri/f195Pb2NhIOh2PYtbS01PPp0yfTDjMSifxcXl5WyozlEqbhFoiiuoXq6moL4t3dXeTm5iYSCoWi2ESVMUD1+/1hn8/nRc3EvnKY+ampqW/2YyWp/P2CTIKoK4i1tbVad3e3BRHQkNJQIwQmaRx7fHyM4XvX19fhlpYWb3Nzs4b32GDquYSZ1dR+AuIsICKdFURswWAwKmkbE4D//sSl4cimS/rrJSUlnsrKSnN3dzeABnR2doaURpqrmpn1NM8ayKcgyuMCurNdiYAIJT53HDQe0zSt5qNgomaim6Nmrqys5ASmkU8QEVAq9sH+V1dX4dbWVivNcSyBPD82NvY1F2mecUUmQxSDPSuKWqirq9N6e3u9AKIgAlIq48EhlTLRze1pfnx8jJqadWUa+QYxDiWhTKhZKRPdvKGhAbU068rMmCKTIY6Pj3+Wxx+A2NPT44134ER3tjeWlFUgDciuzKqqKnN7e9tS5unpaVaVmRGQyRCHh4c/ywX/gF2BEmG2FUTYmnTGgFOhmxcWFloNqKKiwtzZ2QkcHR1ZaS7H/7m6uppxmEY+Q1RpDp9pN+1tbW3exsZGK83FLs0PDg5mPM0dVeRzEOET+/r6EjMWzKGTfWLaioj7zKKiIkuZmE6qNIfPzLQyHQP5HESpW1p/f/9/IL5kcdIJ1EzALC8vT8BUc/NMwnQE5FMQ5SVLiYCourOk9au6czo1U8FEzdza2grs7+8nFjoyAdN4TxDtNTMUCsWQAaiZ7e3tXp/Pp2FMMO2ZqJl6mh3zRYi4mGxBfM60S4pb1mhjY8OqmZlQ5ptBJkMUcFZNhE+0Q1Q1UQae9aUtGU9iocMOE9ZIzc3X1tYcgfkmkE9BlAFbFmdgYCDRWOTREYvjhDLhMxXM9fX1ADxm/LaFIzCN9wzRPp2Ez4R/vby8DHd2dnrhMeM31OblGtKuma9S5HMQYXGGhoasdMZgAVEtyrollDJVN6+urraUqXxmuso0nYIIFdohai4LMFFzenluFWwoUx4CeC4woUwtDtN6C645VZh6istW/4OIBQhAHB0d9YrFgM2wIMJ6ODljcXxObFtpr6ysTChT+UyJNykTUP56y4A6OjoM3KiSkz/mC8TnYEp9NzFusUOBOMzXl465ubm/X9oJJ5ST4YQFXq/XIy/BF4YvLi7CqrHkyuKkY41QM3FtUjMN8b6mdPUCfAu+F2ucku5huTaI42VFLi4urqc6WxBQUXWLVLpfojOjI+bj5yztDai4uFiX6aSnpKTEgFhg5BFQbkrNZnNz8z7FYm3BwtQrGAxalgLPFeh8DCUQZJNciw5hCEQLLNL/NVYIn1wIax88ABSZJZsmM7E3qcLkR58damBE4EyY+WBXqMiPpEjWSKY2FckayWBqM7XzBWQ+rdhQkWw2DCqSXZuKJEgGU5sgaX8YrJEEybk2Fclgs6H9IUgGayRrJBXJGsmgIgmSIAmSQftDRdL+MJjaBOnW1MZv0TOoSIIkSAZBEiRBEiSDIAmSIBkESZAESZAMgiRIgiRIBkESJEEyCJIgCZIgGQRJkARJkAyCJEiCZBAkQRIkQTJSD7OwsJAUqEgXKdLv95MCFemewL9h+pUYHEhtLf6//xgE6RqQ/HN9BOkukGFicAbkIzE4A/KBGJwBGSIGgnQVyCAxOAMyQAxUJGskQTLoIzmz4Vz7Y4Hk6o8DgVsNvG/jQHiIwCFF8i+aOhNMa4J0V/wjwADkbTd31/iGkwAAAABJRU5ErkJggg=="; }
@end

//
// Callout background assembled from predrawn stretched images.
//
@implementation SMCalloutImageBackgroundView {
    UIImageView *leftCap, *rightCap, *topAnchor, *bottomAnchor, *leftBackground, *rightBackground;
}

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        leftCap = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 17, 49)];
        rightCap = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 17, 49)];
        topAnchor = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 41, 55)];
        bottomAnchor = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 41, 55)];
        leftBackground = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 1, 49)];
        rightBackground = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 1, 49)];
        [self addSubview:leftCap];
        [self addSubview:rightCap];
        [self addSubview:topAnchor];
        [self addSubview:bottomAnchor];
        [self addSubview:leftBackground];
        [self addSubview:rightBackground];
    }
    return self;
}

// Make sure we relayout our images when our arrow point changes!
- (void)setArrowPoint:(CGPoint)arrowPoint {
    [super setArrowPoint:arrowPoint];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    
    // apply our background graphics
    leftCap.image = self.leftCapImage;
    rightCap.image = self.rightCapImage;
    topAnchor.image = self.topAnchorImage;
    bottomAnchor.image = self.bottomAnchorImage;
    leftBackground.image = self.backgroundImage;
    rightBackground.image = self.backgroundImage;
    
    // stretch the images to fill our vertical space. The system background images aren't really stretchable,
    // but that's OK because you'll probably be using title/subtitle rather than contentView if you're using the
    // system images, and in that case the height will match the system background heights exactly and no stretching
    // will occur. However, if you wish to define your own custom background using prerendered images, you could
    // define stretchable images using -stretchableImageWithLeftCapWidth:TopCapHeight and they'd get stretched
    // properly here if necessary.
    leftCap.$height = rightCap.$height = leftBackground.$height = rightBackground.$height = self.$height - 6;
    topAnchor.$height = bottomAnchor.$height = self.$height;

    BOOL pointingUp = self.arrowPoint.y < self.$height/2;

    // show the correct anchor based on our direction
    topAnchor.hidden = !pointingUp;
    bottomAnchor.hidden = pointingUp;

    // if we're pointing up, we'll need to push almost everything down a bit
    CGFloat dy = pointingUp ? TOP_ANCHOR_MARGIN : 0;
    leftCap.$y = rightCap.$y = leftBackground.$y = rightBackground.$y = dy;
    
    leftCap.$x = 0;
    rightCap.$x = self.$width - rightCap.$width;
    
    // move both anchors, only one will have been made visible in our -popup method
    CGFloat anchorX = roundf(self.arrowPoint.x - bottomAnchor.$width / 2);
    topAnchor.$origin = CGPointMake(anchorX, 0);
    
    // make sure the anchor graphic isn't overlapping with an endcap
    if (topAnchor.$left < leftCap.$right) topAnchor.$x = leftCap.$right;
    if (topAnchor.$right > rightCap.$left) topAnchor.$x = rightCap.$left - topAnchor.$width; // don't stretch it
    
    bottomAnchor.$origin = topAnchor.$origin; // match
    
    leftBackground.$left = leftCap.$right;
    leftBackground.$right = topAnchor.$left;
    rightBackground.$left = topAnchor.$right;
    rightBackground.$right = rightCap.$left;
}

@end

//
// Custom-drawn flexible-height background implementation.
// Contributed by Nicholas Shipes: https://github.com/u10int
//
@implementation SMCalloutDrawnBackgroundView

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
    return self;
}

// Make sure we redraw our graphics when the arrow point changes!
- (void)setArrowPoint:(CGPoint)arrowPoint {
    [super setArrowPoint:arrowPoint];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {

    BOOL pointingUp = self.arrowPoint.y < self.$height/2;
    CGSize anchorSize = CGSizeMake(27, ANCHOR_HEIGHT);
    CGFloat anchorX = roundf(self.arrowPoint.x - anchorSize.width / 2);
    CGRect anchorRect = CGRectMake(anchorX, 0, anchorSize.width, anchorSize.height);
    
    // make sure the anchor is not too close to the end caps
    if (anchorRect.origin.x < ANCHOR_MARGIN_MIN)
        anchorRect.origin.x = ANCHOR_MARGIN_MIN;
    
    else if (anchorRect.origin.x + anchorRect.size.width > self.$width - ANCHOR_MARGIN_MIN)
        anchorRect.origin.x = self.$width - anchorRect.size.width - ANCHOR_MARGIN_MIN;
    
    // determine size
    CGFloat stroke = 1.0;
    CGFloat radius = [UIScreen mainScreen].scale == 1 ? 4.5 : 6.0;
    
    rect = CGRectMake(self.bounds.origin.x, self.bounds.origin.y + TOP_SHADOW_BUFFER, self.bounds.size.width, self.bounds.size.height - ANCHOR_HEIGHT);
    rect.size.width -= stroke + 14;
    rect.size.height -= stroke * 2 + TOP_SHADOW_BUFFER + BOTTOM_SHADOW_BUFFER + OFFSET_FROM_ORIGIN;
    rect.origin.x += stroke / 2.0 + 7;
    rect.origin.y += pointingUp ? ANCHOR_HEIGHT - stroke / 2.0 : stroke / 2.0;
    
    
    // General Declarations
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Color Declarations
    UIColor* fillBlack = [UIColor colorWithRed: 0.11 green: 0.11 blue: 0.11 alpha: 1];
    UIColor* shadowBlack = [UIColor colorWithRed: 0 green: 0 blue: 0 alpha: 0.47];
    UIColor* glossBottom = [UIColor colorWithRed: 1 green: 1 blue: 1 alpha: 0.2];
    UIColor* glossTop = [UIColor colorWithRed: 1 green: 1 blue: 1 alpha: 0.85];
    UIColor* strokeColor = [UIColor colorWithRed: 0.199 green: 0.199 blue: 0.199 alpha: 1];
    UIColor* innerShadowColor = [UIColor colorWithRed: 1 green: 1 blue: 1 alpha: 0.4];
    UIColor* innerStrokeColor = [UIColor colorWithRed: 0.821 green: 0.821 blue: 0.821 alpha: 0.04];
    UIColor* outerStrokeColor = [UIColor colorWithRed: 0 green: 0 blue: 0 alpha: 0.35];
    
    // Gradient Declarations
    NSArray* glossFillColors = [NSArray arrayWithObjects:
                                (id)glossBottom.CGColor,
                                (id)glossTop.CGColor, nil];
    CGFloat glossFillLocations[] = {0, 1};
    CGGradientRef glossFill = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)glossFillColors, glossFillLocations);
    
    // Shadow Declarations
    UIColor* baseShadow = shadowBlack;
    CGSize baseShadowOffset = CGSizeMake(0.1, 6.1);
    CGFloat baseShadowBlurRadius = 6;
    UIColor* innerShadow = innerShadowColor;
    CGSize innerShadowOffset = CGSizeMake(0.1, 1.1);
    CGFloat innerShadowBlurRadius = 1;
    
    CGFloat backgroundStrokeWidth = 1;
    CGFloat outerStrokeStrokeWidth = 1;
    
    // Frames
    CGRect frame = rect;
    CGRect innerFrame = CGRectMake(frame.origin.x + backgroundStrokeWidth, frame.origin.y + backgroundStrokeWidth, frame.size.width - backgroundStrokeWidth * 2, frame.size.height - backgroundStrokeWidth * 2);
    CGRect glossFrame = CGRectMake(frame.origin.x - backgroundStrokeWidth / 2, frame.origin.y - backgroundStrokeWidth / 2, frame.size.width + backgroundStrokeWidth, frame.size.height / 2 + backgroundStrokeWidth + 0.5);
    
    //// CoreGroup ////
    {
        CGContextSaveGState(context);
        CGContextSetAlpha(context, 0.83);
        CGContextBeginTransparencyLayer(context, NULL);
        
        // Background Drawing
        UIBezierPath* backgroundPath = [UIBezierPath bezierPath];
        [backgroundPath moveToPoint:CGPointMake(CGRectGetMinX(frame), CGRectGetMinY(frame) + radius)];
        [backgroundPath addLineToPoint:CGPointMake(CGRectGetMinX(frame), CGRectGetMaxY(frame) - radius)]; // left
        [backgroundPath addArcWithCenter:CGPointMake(CGRectGetMinX(frame) + radius, CGRectGetMaxY(frame) - radius) radius:radius startAngle:M_PI endAngle:M_PI / 2 clockwise:NO]; // bottom-left corner
        
        // pointer down
        if (!pointingUp) {
            [backgroundPath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect), CGRectGetMaxY(frame))];
            [backgroundPath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect) + anchorRect.size.width / 2, CGRectGetMaxY(frame) + anchorRect.size.height)];
            [backgroundPath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorRect), CGRectGetMaxY(frame))];
        }
        
        [backgroundPath addLineToPoint:CGPointMake(CGRectGetMaxX(frame) - radius, CGRectGetMaxY(frame))]; // bottom
        [backgroundPath addArcWithCenter:CGPointMake(CGRectGetMaxX(frame) - radius, CGRectGetMaxY(frame) - radius) radius:radius startAngle:M_PI / 2 endAngle:0.0f clockwise:NO]; // bottom-right corner
        [backgroundPath addLineToPoint: CGPointMake(CGRectGetMaxX(frame), CGRectGetMinY(frame) + radius)]; // right
        [backgroundPath addArcWithCenter:CGPointMake(CGRectGetMaxX(frame) - radius, CGRectGetMinY(frame) + radius) radius:radius startAngle:0.0f endAngle:-M_PI / 2 clockwise:NO]; // top-right corner
        
        // pointer up
        if (pointingUp) {
            [backgroundPath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorRect), CGRectGetMinY(frame))];
            [backgroundPath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect) + anchorRect.size.width / 2, CGRectGetMinY(frame) - anchorRect.size.height)];
            [backgroundPath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect), CGRectGetMinY(frame))];
        }
        
        [backgroundPath addLineToPoint:CGPointMake(CGRectGetMinX(frame) + radius, CGRectGetMinY(frame))]; // top
        [backgroundPath addArcWithCenter:CGPointMake(CGRectGetMinX(frame) + radius, CGRectGetMinY(frame) + radius) radius:radius startAngle:-M_PI / 2 endAngle:M_PI clockwise:NO]; // top-left corner
        [backgroundPath closePath];
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, baseShadowOffset, baseShadowBlurRadius, baseShadow.CGColor);
        [fillBlack setFill];
        [backgroundPath fill];
        
        // Background Inner Shadow
        CGRect backgroundBorderRect = CGRectInset([backgroundPath bounds], -innerShadowBlurRadius, -innerShadowBlurRadius);
        backgroundBorderRect = CGRectOffset(backgroundBorderRect, -innerShadowOffset.width, -innerShadowOffset.height);
        backgroundBorderRect = CGRectInset(CGRectUnion(backgroundBorderRect, [backgroundPath bounds]), -1, -1);
        
        UIBezierPath* backgroundNegativePath = [UIBezierPath bezierPathWithRect: backgroundBorderRect];
        [backgroundNegativePath appendPath: backgroundPath];
        backgroundNegativePath.usesEvenOddFillRule = YES;
        
        CGContextSaveGState(context);
        {
            CGFloat xOffset = innerShadowOffset.width + round(backgroundBorderRect.size.width);
            CGFloat yOffset = innerShadowOffset.height;
            CGContextSetShadowWithColor(context,
                                        CGSizeMake(xOffset + copysign(0.1, xOffset), yOffset + copysign(0.1, yOffset)),
                                        innerShadowBlurRadius,
                                        innerShadow.CGColor);
            
            [backgroundPath addClip];
            CGAffineTransform transform = CGAffineTransformMakeTranslation(-round(backgroundBorderRect.size.width), 0);
            [backgroundNegativePath applyTransform: transform];
            [[UIColor grayColor] setFill];
            [backgroundNegativePath fill];
        }
        CGContextRestoreGState(context);
        
        CGContextRestoreGState(context);
        
        [strokeColor setStroke];
        backgroundPath.lineWidth = backgroundStrokeWidth;
        [backgroundPath stroke];
        
        
        // Inner Stroke Drawing
        CGFloat innerRadius = radius - 1.0;
        CGRect anchorInnerRect = anchorRect;
        anchorInnerRect.origin.x += backgroundStrokeWidth / 2;
        anchorInnerRect.origin.y -= backgroundStrokeWidth / 2;
        anchorInnerRect.size.width -= backgroundStrokeWidth;
        anchorInnerRect.size.height -= backgroundStrokeWidth / 2;
        
        UIBezierPath* innerStrokePath = [UIBezierPath bezierPath];
        [innerStrokePath moveToPoint:CGPointMake(CGRectGetMinX(innerFrame), CGRectGetMinY(innerFrame) + innerRadius)];
        [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(innerFrame), CGRectGetMaxY(innerFrame) - innerRadius)]; // left
        [innerStrokePath addArcWithCenter:CGPointMake(CGRectGetMinX(innerFrame) + innerRadius, CGRectGetMaxY(innerFrame) - innerRadius) radius:innerRadius startAngle:M_PI endAngle:M_PI / 2 clockwise:NO]; // bottom-left corner
        
        // pointer down
        if (!pointingUp) {
            [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorInnerRect), CGRectGetMaxY(innerFrame))];
            [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorInnerRect) + anchorInnerRect.size.width / 2, CGRectGetMaxY(innerFrame) + anchorInnerRect.size.height)];
            [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorInnerRect), CGRectGetMaxY(innerFrame))];
        }
        
        [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMaxX(innerFrame) - innerRadius, CGRectGetMaxY(innerFrame))]; // bottom
        [innerStrokePath addArcWithCenter:CGPointMake(CGRectGetMaxX(innerFrame) - innerRadius, CGRectGetMaxY(innerFrame) - innerRadius) radius:innerRadius startAngle:M_PI / 2 endAngle:0.0f clockwise:NO]; // bottom-right corner
        [innerStrokePath addLineToPoint: CGPointMake(CGRectGetMaxX(innerFrame), CGRectGetMinY(innerFrame) + innerRadius)]; // right
        [innerStrokePath addArcWithCenter:CGPointMake(CGRectGetMaxX(innerFrame) - innerRadius, CGRectGetMinY(innerFrame) + innerRadius) radius:innerRadius startAngle:0.0f endAngle:-M_PI / 2 clockwise:NO]; // top-right corner
        
        // pointer up
        if (pointingUp) {
            [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorInnerRect), CGRectGetMinY(innerFrame))];
            [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorInnerRect) + anchorRect.size.width / 2, CGRectGetMinY(innerFrame) - anchorInnerRect.size.height)];
            [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorInnerRect), CGRectGetMinY(innerFrame))];
        }
        
        [innerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(innerFrame) + innerRadius, CGRectGetMinY(innerFrame))]; // top
        [innerStrokePath addArcWithCenter:CGPointMake(CGRectGetMinX(innerFrame) + innerRadius, CGRectGetMinY(innerFrame) + innerRadius) radius:innerRadius startAngle:-M_PI / 2 endAngle:M_PI clockwise:NO]; // top-left corner
        [innerStrokePath closePath];
        
        [innerStrokeColor setStroke];
        innerStrokePath.lineWidth = backgroundStrokeWidth;
        [innerStrokePath stroke];
        
        
        //// GlossGroup ////
        {
            CGContextSaveGState(context);
            CGContextSetAlpha(context, 0.45);
            CGContextBeginTransparencyLayer(context, NULL);
            
            CGFloat glossRadius = radius + 0.5;
            
            // Gloss Drawing
            UIBezierPath* glossPath = [UIBezierPath bezierPath];
            [glossPath moveToPoint:CGPointMake(CGRectGetMinX(glossFrame), CGRectGetMinY(glossFrame))];
            [glossPath addLineToPoint:CGPointMake(CGRectGetMinX(glossFrame), CGRectGetMaxY(glossFrame) - glossRadius)]; // left
            [glossPath addArcWithCenter:CGPointMake(CGRectGetMinX(glossFrame) + glossRadius, CGRectGetMaxY(glossFrame) - glossRadius) radius:glossRadius startAngle:M_PI endAngle:M_PI / 2 clockwise:NO]; // bottom-left corner
            [glossPath addLineToPoint:CGPointMake(CGRectGetMaxX(glossFrame) - glossRadius, CGRectGetMaxY(glossFrame))]; // bottom
            [glossPath addArcWithCenter:CGPointMake(CGRectGetMaxX(glossFrame) - glossRadius, CGRectGetMaxY(glossFrame) - glossRadius) radius:glossRadius startAngle:M_PI / 2 endAngle:0.0f clockwise:NO]; // bottom-right corner
            [glossPath addLineToPoint: CGPointMake(CGRectGetMaxX(glossFrame), CGRectGetMinY(glossFrame) - glossRadius)]; // right
            [glossPath addArcWithCenter:CGPointMake(CGRectGetMaxX(glossFrame) - glossRadius, CGRectGetMinY(glossFrame) + glossRadius) radius:glossRadius startAngle:0.0f endAngle:-M_PI / 2 clockwise:NO]; // top-right corner
            
            // pointer up
            if (pointingUp) {
                [glossPath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorRect), CGRectGetMinY(glossFrame))];
                [glossPath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect) + roundf(anchorRect.size.width / 2), CGRectGetMinY(glossFrame) - anchorRect.size.height)];
                [glossPath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect), CGRectGetMinY(glossFrame))];
            }
            
            [glossPath addLineToPoint:CGPointMake(CGRectGetMinX(glossFrame) + glossRadius, CGRectGetMinY(glossFrame))]; // top
            [glossPath addArcWithCenter:CGPointMake(CGRectGetMinX(glossFrame) + glossRadius, CGRectGetMinY(glossFrame) + glossRadius) radius:glossRadius startAngle:-M_PI / 2 endAngle:M_PI clockwise:NO]; // top-left corner
            [glossPath closePath];
            
            CGContextSaveGState(context);
            [glossPath addClip];
            CGRect glossBounds = glossPath.bounds;
            CGContextDrawLinearGradient(context, glossFill,
                                        CGPointMake(CGRectGetMidX(glossBounds), CGRectGetMaxY(glossBounds)),
                                        CGPointMake(CGRectGetMidX(glossBounds), CGRectGetMinY(glossBounds)),
                                        0);
            CGContextRestoreGState(context);
            
            CGContextEndTransparencyLayer(context);
            CGContextRestoreGState(context);
        }
        
        CGContextEndTransparencyLayer(context);
        CGContextRestoreGState(context);
    }
    
    // Outer Stroke Drawing
    UIBezierPath* outerStrokePath = [UIBezierPath bezierPath];
    [outerStrokePath moveToPoint:CGPointMake(CGRectGetMinX(frame), CGRectGetMinY(frame) + radius)];
    [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(frame), CGRectGetMaxY(frame) - radius)]; // left
    [outerStrokePath addArcWithCenter:CGPointMake(CGRectGetMinX(frame) + radius, CGRectGetMaxY(frame) - radius) radius:radius startAngle:M_PI endAngle:M_PI / 2 clockwise:NO]; // bottom-left corner
    
    // pointer down
    if (!pointingUp) {
        [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect), CGRectGetMaxY(frame))];
        [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect) + anchorRect.size.width / 2, CGRectGetMaxY(frame) + anchorRect.size.height)];
        [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorRect), CGRectGetMaxY(frame))];
    }
    
    [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMaxX(frame) - radius, CGRectGetMaxY(frame))]; // bottom
    [outerStrokePath addArcWithCenter:CGPointMake(CGRectGetMaxX(frame) - radius, CGRectGetMaxY(frame) - radius) radius:radius startAngle:M_PI / 2 endAngle:0.0f clockwise:NO]; // bottom-right corner
    [outerStrokePath addLineToPoint: CGPointMake(CGRectGetMaxX(frame), CGRectGetMinY(frame) + radius)]; // right
    [outerStrokePath addArcWithCenter:CGPointMake(CGRectGetMaxX(frame) - radius, CGRectGetMinY(frame) + radius) radius:radius startAngle:0.0f endAngle:-M_PI / 2 clockwise:NO]; // top-right corner
    
    // pointer up
    if (pointingUp) {
        [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMaxX(anchorRect), CGRectGetMinY(frame))];
        [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect) + anchorRect.size.width / 2, CGRectGetMinY(frame) - anchorRect.size.height)];
        [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(anchorRect), CGRectGetMinY(frame))];
    }
    
    [outerStrokePath addLineToPoint:CGPointMake(CGRectGetMinX(frame) + radius, CGRectGetMinY(frame))]; // top
    [outerStrokePath addArcWithCenter:CGPointMake(CGRectGetMinX(frame) + radius, CGRectGetMinY(frame) + radius) radius:radius startAngle:-M_PI / 2 endAngle:M_PI clockwise:NO]; // top-left corner
    [outerStrokePath closePath];
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, baseShadowOffset, baseShadowBlurRadius, baseShadow.CGColor);
    CGContextRestoreGState(context);
    
    [outerStrokeColor setStroke];
    outerStrokePath.lineWidth = outerStrokeStrokeWidth;
    [outerStrokePath stroke];
    
    //// Cleanup
    CGGradientRelease(glossFill);
    CGColorSpaceRelease(colorSpace);
}

@end

//
// Our UIView frame helpers implementation
//

@implementation UIView (SMFrameAdditions)

- (CGPoint)$origin { return self.frame.origin; }
- (void)set$origin:(CGPoint)origin { self.frame = (CGRect){ .origin=origin, .size=self.frame.size }; }

- (CGFloat)$x { return self.frame.origin.x; }
- (void)set$x:(CGFloat)x { self.frame = (CGRect){ .origin.x=x, .origin.y=self.frame.origin.y, .size=self.frame.size }; }

- (CGFloat)$y { return self.frame.origin.y; }
- (void)set$y:(CGFloat)y { self.frame = (CGRect){ .origin.x=self.frame.origin.x, .origin.y=y, .size=self.frame.size }; }

- (CGSize)$size { return self.frame.size; }
- (void)set$size:(CGSize)size { self.frame = (CGRect){ .origin=self.frame.origin, .size=size }; }

- (CGFloat)$width { return self.frame.size.width; }
- (void)set$width:(CGFloat)width { self.frame = (CGRect){ .origin=self.frame.origin, .size.width=width, .size.height=self.frame.size.height }; }

- (CGFloat)$height { return self.frame.size.height; }
- (void)set$height:(CGFloat)height { self.frame = (CGRect){ .origin=self.frame.origin, .size.width=self.frame.size.width, .size.height=height }; }

- (CGFloat)$left { return self.frame.origin.x; }
- (void)set$left:(CGFloat)left { self.frame = (CGRect){ .origin.x=left, .origin.y=self.frame.origin.y, .size.width=fmaxf(self.frame.origin.x+self.frame.size.width-left,0), .size.height=self.frame.size.height }; }

- (CGFloat)$top { return self.frame.origin.y; }
- (void)set$top:(CGFloat)top { self.frame = (CGRect){ .origin.x=self.frame.origin.x, .origin.y=top, .size.width=self.frame.size.width, .size.height=fmaxf(self.frame.origin.y+self.frame.size.height-top,0) }; }

- (CGFloat)$right { return self.frame.origin.x + self.frame.size.width; }
- (void)set$right:(CGFloat)right { self.frame = (CGRect){ .origin=self.frame.origin, .size.width=fmaxf(right-self.frame.origin.x,0), .size.height=self.frame.size.height }; }

- (CGFloat)$bottom { return self.frame.origin.y + self.frame.size.height; }
- (void)set$bottom:(CGFloat)bottom { self.frame = (CGRect){ .origin=self.frame.origin, .size.width=self.frame.size.width, .size.height=fmaxf(bottom-self.frame.origin.y,0) }; }

@end
