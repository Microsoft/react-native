/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTDevLoadingView.h>

#import <QuartzCore/QuartzCore.h>

#import <FBReactNativeSpec/FBReactNativeSpec.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTDefines.h>
#import <React/RCTDevSettings.h> // TODO(OSS Candidate ISS#2710739)
#import <React/RCTDevLoadingViewSetEnabled.h>
#if !TARGET_OS_OSX
#import <React/RCTModalHostViewController.h>
#endif // !TARGET_OS_OSX
#import <React/RCTUtils.h>
#import <React/RCTUIKit.h> // TODO(macOS ISS#2323203)

#import "CoreModulesPlugins.h"

using namespace facebook::react;

@interface RCTDevLoadingView () <NativeDevLoadingViewSpec>
@end

#if RCT_DEV | RCT_ENABLE_LOADING_VIEW

@implementation RCTDevLoadingView {
#if !TARGET_OS_OSX // TODO(macOS ISS#2323203)
  UIWindow *_window;
  UILabel *_label;
#else // [TODO(macOS ISS#2323203)
  NSWindow *_window;
  NSTextField *_label;
#endif // ]TODO(macOS ISS#2323203)
  NSDate *_showDate;
  BOOL _hiding;
  dispatch_block_t _initialMessageBlock;
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

+ (void)setEnabled:(BOOL)enabled
{
  RCTDevLoadingViewSetEnabled(enabled);
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(hide)
                                               name:RCTJavaScriptDidLoadNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(hide)
                                               name:RCTJavaScriptDidFailToLoadNotification
                                             object:nil];

  if ([[bridge devSettings] isDevModeEnabled] && bridge.loading) { // TODO(OSS Candidate ISS#2710739)
    [self showWithURL:bridge.bundleURL];
  }
}

- (void)clearInitialMessageDelay
{
  if (self->_initialMessageBlock != nil) {
    dispatch_block_cancel(self->_initialMessageBlock);
    self->_initialMessageBlock = nil;
  }
}

- (void)showInitialMessageDelayed:(void (^)())initialMessage
{
  self->_initialMessageBlock = dispatch_block_create(static_cast<dispatch_block_flags_t>(0), initialMessage);

  // We delay the initial loading message to prevent flashing it
  // when loading progress starts quickly. To do that, we
  // schedule the message to be shown in a block, and cancel
  // the block later when the progress starts coming in.
  // If the progress beats this timer, this message is not shown.
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), self->_initialMessageBlock);
}

- (RCTUIColor *)dimColor:(RCTUIColor *)c // TODO: (macOS ISS#2323203): UIColor -> RCTUIColor
{
  // Given a color, return a slightly lighter or darker color for dim effect.
  CGFloat h, s, b, a;
#if !TARGET_OS_OSX // TODO: (macOS ISS#2323203):  `getHue:saturation:brightness:alpha:` on macOS returns void but on iOS returns BOOL
  if ([c getHue:&h saturation:&s brightness:&b alpha:&a])
#else
  [c getHue:&h saturation:&s brightness:&b alpha:&a];
#endif // !TARGET_OS_OSX
    return [RCTUIColor colorWithHue:h saturation:s brightness:b < 0.5 ? b * 1.25 : b * 0.75 alpha:a]; // TODO: (macOS ISS#2323203): UIColor -> RCTUIColor
  return nil;
}

- (NSString *)getTextForHost
{
  if (self->_bridge.bundleURL == nil || self->_bridge.bundleURL.fileURL) {
    return @"React Native";
  }

  return [NSString stringWithFormat:@"%@:%@", self->_bridge.bundleURL.host, self->_bridge.bundleURL.port];
}

- (void)showMessage:(NSString *)message color:(RCTUIColor *)color backgroundColor:(RCTUIColor *)backgroundColor // TODO(OSS Candidate ISS#2710739)
{
  if (!RCTDevLoadingViewGetEnabled() || self->_hiding) {
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    self->_showDate = [NSDate date];
    if (!self->_window && !RCTRunningInTestEnvironment()) {
#if !TARGET_OS_OSX // TODO(macOS ISS#2323203)
      CGSize screenSize = [UIScreen mainScreen].bounds.size;

      if (@available(iOS 11.0, *)) {
        UIWindow *window = RCTSharedApplication().keyWindow;
        self->_window =
            [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenSize.width, window.safeAreaInsets.top + 10)];
        self->_label =
            [[UILabel alloc] initWithFrame:CGRectMake(0, window.safeAreaInsets.top - 10, screenSize.width, 20)];
      } else {
        self->_window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenSize.width, 20)];
        self->_label = [[UILabel alloc] initWithFrame:self->_window.bounds];
      }
      [self->_window addSubview:self->_label];

      self->_window.windowLevel = UIWindowLevelStatusBar + 1;
      // set a root VC so rotation is supported
      self->_window.rootViewController = [UIViewController new];

      self->_label.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
      self->_label.textAlignment = NSTextAlignmentCenter;
#elif TARGET_OS_OSX // [TODO(macOS ISS#2323203)
      NSRect screenFrame = [NSScreen mainScreen].visibleFrame;
      self->_window = [[NSPanel alloc] initWithContentRect:NSMakeRect(screenFrame.origin.x + round((screenFrame.size.width - 375) / 2), screenFrame.size.height - 20, 375, 19)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
      self->_window.releasedWhenClosed = NO;
      self->_window.backgroundColor = [NSColor clearColor];

      NSTextField *label = [[NSTextField alloc] initWithFrame:self->_window.contentView.bounds];
      label.alignment = NSTextAlignmentCenter;
      label.bezeled = NO;
      label.editable = NO;
      label.selectable = NO;
      label.wantsLayer = YES;
      label.layer.cornerRadius = label.frame.size.height / 3;
      self->_label = label;
      [[self->_window contentView] addSubview:label];
#endif // ]TODO(macOS ISS#2323203)
    }

#if !TARGET_OS_OSX // TODO(macOS ISS#2323203)
    self->_label.text = message;
    self->_label.textColor = color;

    self->_window.backgroundColor = backgroundColor;
    self->_window.hidden = NO;
#else // [TODO(macOS ISS#2323203)
    self->_label.stringValue = message;
    self->_label.textColor = color;
    self->_label.backgroundColor = backgroundColor;
    [self->_window orderFront:nil];
#endif // ]TODO(macOS ISS#2323203)

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && defined(__IPHONE_13_0) && \
    __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
    if (@available(iOS 13.0, *)) {
      UIWindowScene *scene = (UIWindowScene *)RCTSharedApplication().connectedScenes.anyObject;
      self->_window.windowScene = scene;
    }
#endif
  });
}

RCT_EXPORT_METHOD(showMessage
                  : (NSString *)message withColor
                  : (NSNumber *__nonnull)color withBackgroundColor
                  : (NSNumber *__nonnull)backgroundColor)
{
  [self showMessage:message color:[RCTConvert UIColor:color] backgroundColor:[RCTConvert UIColor:backgroundColor]];
}

RCT_EXPORT_METHOD(hide)
{
  if (!RCTDevLoadingViewGetEnabled()) {
    return;
  }

  // Cancel the initial message block so it doesn't display later and get stuck.
  [self clearInitialMessageDelay];

  dispatch_async(dispatch_get_main_queue(), ^{
    self->_hiding = true;
    const NSTimeInterval MIN_PRESENTED_TIME = 0.6;
    NSTimeInterval presentedTime = [[NSDate date] timeIntervalSinceDate:self->_showDate];
    NSTimeInterval delay = MAX(0, MIN_PRESENTED_TIME - presentedTime);
#if !TARGET_OS_OSX // TODO(macOS ISS#2323203)
    CGRect windowFrame = self->_window.frame;
    [UIView animateWithDuration:0.25
        delay:delay
        options:0
        animations:^{
          self->_window.frame = CGRectOffset(windowFrame, 0, -windowFrame.size.height);
        }
        completion:^(__unused BOOL finished) {
          self->_window.frame = windowFrame;
          self->_window.hidden = YES;
          self->_window = nil;
          self->_hiding = false;
        }];
#elif TARGET_OS_OSX // [TODO(macOS ISS#2323203)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [NSAnimationContext runAnimationGroup:^(__unused NSAnimationContext *context) {
        self->_window.animator.alphaValue = 0.0;
      } completionHandler:^{
        [self->_window orderFront:self];
        self->_window = nil;
      }];
    });
#endif // ]TODO(macOS ISS#2323203)
  });
}

- (void)showWithURL:(NSURL *)URL
{
  RCTUIColor *color; // TODO(macOS ISS#2323203)
  RCTUIColor *backgroundColor; // TODO(macOS ISS#2323203)
  NSString *message;
  if (URL.fileURL) {
    // If dev mode is not enabled, we don't want to show this kind of notification.
#if !RCT_DEV
    return;
#endif
    color = [RCTUIColor whiteColor]; //TODO(OSS Candidate ISS#2710739) UIColor -> RCTUIColor
    backgroundColor = [RCTUIColor blackColor]; // TODO(OSS Candidate ISS#2710739)
    message = [NSString stringWithFormat:@"Connect to %@ to develop JavaScript.", RCT_PACKAGER_NAME];
    [self showMessage:message color:color backgroundColor:backgroundColor];
  } else {
    color = [RCTUIColor whiteColor]; // TODO(OSS Candidate ISS#2710739)
    backgroundColor = [RCTUIColor colorWithHue:105 saturation:0 brightness:.25 alpha:1]; // TODO(OSS Candidate ISS#2710739)
    message = [NSString stringWithFormat:@"Loading from %@\u2026", RCT_PACKAGER_NAME];
  }

  [self showInitialMessageDelayed:^{
    [self showMessage:message color:color backgroundColor:backgroundColor];
  }];
}

- (void)updateProgress:(RCTLoadingProgress *)progress
{
  if (!progress) {
    return;
  }

  // Cancel the initial message block so it's not flashed before progress.
  [self clearInitialMessageDelay];

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_window == nil) {
      // If we didn't show the initial message, then there's no banner window.
      // We need to create it here so that the progress is actually displayed.
      RCTUIColor *color = [RCTUIColor whiteColor]; // TODO: (macOS ISS#2323203): UIColor -> RCTUIColor
      RCTUIColor *backgroundColor = [RCTUIColor colorWithHue:105 saturation:0 brightness:.25 alpha:1]; // TODO: (macOS ISS#2323203): UIColor -> RCTUIColor
      [self showMessage:[progress description] color:color backgroundColor:backgroundColor];
    } else {
      // This is an optimization. Since the progress can come in quickly,
      // we want to do the minimum amount of work to update the UI,
      // which is to only update the label text.
#if !TARGET_OS_OSX // TODO(macOS ISS#2323203)
      self->_label.text = [progress description];
#else // [TODO(macOS ISS#2323203)
      self->_label.stringValue = [progress description];
#endif // ]TODO(macOS ISS#2323203)
    }
  });
}

- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params
{
  return std::make_shared<NativeDevLoadingViewSpecJSI>(params);
}

@end

#else

@implementation RCTDevLoadingView

+ (NSString *)moduleName
{
  return nil;
}
+ (void)setEnabled:(BOOL)enabled
{
}
- (void)showMessage:(NSString *)message color:(UIColor *)color backgroundColor:(UIColor *)backgroundColor
{
}
- (void)showMessage:(NSString *)message withColor:(NSNumber *)color withBackgroundColor:(NSNumber *)backgroundColor
{
}
- (void)showWithURL:(NSURL *)URL
{
}
- (void)updateProgress:(RCTLoadingProgress *)progress
{
}
- (void)hide
{
}
- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params
{
  return std::make_shared<NativeDevLoadingViewSpecJSI>(params);
}

@end

#endif

Class RCTDevLoadingViewCls(void)
{
  return RCTDevLoadingView.class;
}
