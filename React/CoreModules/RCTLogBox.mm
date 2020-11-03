/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RCTLogBox.h"

#import <FBReactNativeSpec/FBReactNativeSpec.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTDefines.h>
#import <React/RCTErrorInfo.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTJSStackFrame.h>
#import <React/RCTRedBoxSetEnabled.h>
#import <React/RCTReloadCommand.h>
#import <React/RCTRootView.h>
#import <React/RCTSurface.h>
#import <React/RCTUtils.h>

#import <objc/runtime.h>

#import "CoreModulesPlugins.h"

#if RCT_DEV_MENU

#if !TARGET_OS_OSX // TODO(macOS ISS#2323203)
@interface RCTLogBoxWindow : UIWindow // TODO(OSS Candidate ISS#2710739) Renamed from RCTLogBoxView to RCTLogBoxWindow
@end

@implementation RCTLogBoxWindow {
  RCTSurface *_surface;
}

- (instancetype)initWithBridge:(RCTBridge *)bridge // TODO(OSS Candidate ISS#2710739) Dropped `frame` parameter to make it compatible with NSWindow based version
{
  CGRect frame = [UIScreen mainScreen].bounds;
  if ((self = [super initWithFrame:frame])) {
    self.windowLevel = UIWindowLevelStatusBar - 1;
    self.backgroundColor = [UIColor clearColor];

    _surface = [[RCTSurface alloc] initWithBridge:bridge moduleName:@"LogBox" initialProperties:@{}];

    [_surface start];
    [_surface setSize:frame.size];

    if (![_surface synchronouslyWaitForStage:RCTSurfaceStageSurfaceDidInitialMounting timeout:1]) {
      RCTLogInfo(@"Failed to mount LogBox within 1s");
    }

    UIViewController *_rootViewController = [UIViewController new];
    _rootViewController.view = (UIView *)_surface.view;
    _rootViewController.view.backgroundColor = [UIColor clearColor];
    _rootViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    self.rootViewController = _rootViewController;
  }
  return self;
}

- (void)hide
{
  [RCTSharedApplication().delegate.window makeKeyWindow];
}

- (void)show
{
  [self becomeFirstResponder];
  [self makeKeyAndVisible];
}

@end

#else // [TODO(macOS ISS#2323203)

@interface _RCTLogBoxView : NSView
@end

@implementation _RCTLogBoxView
- (BOOL)isFlipped
{
  return YES;
}
- (NSView *)hitTest:(NSPoint)point
{
  return self.subviews[0];
}
@end

@interface RCTLogBoxWindow : NSWindow
@end

@implementation RCTLogBoxWindow {
  RCTSurface *_surface;
}

- (instancetype)initWithBridge:(RCTBridge *)bridge
{
//  NSRect minimumFrame = NSMakeRect(0, 0, 500, 500);
//  // TODO: Figure out why we actually need to specify a max size.
//  NSRect maximumFrame = NSMakeRect(0, 0, CGFLOAT_MAX, CGFLOAT_MAX);
//  for (NSScreen *screen in [NSScreen screens]) {
//    maximumFrame = NSIntersectionRect(maximumFrame, (NSRect){ NSZeroPoint, screen.visibleFrame.size });
//  }

  NSRect minimumFrame = NSMakeRect(0, 0, 600, 800);
  NSRect maximumFrame = minimumFrame;

  if ((self = [self initWithContentRect:minimumFrame
                              styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable
                                backing:NSBackingStoreBuffered
                                  defer:YES])) {
    // The instance already gets released when we `nil` it from the `-[RCTLogBox hide]` method.
    self.releasedWhenClosed = NO;

    _surface = [[RCTSurface alloc] initWithBridge:bridge moduleName:@"LogBox" initialProperties:@{}];

    [_surface start];
    [_surface setMinimumSize:minimumFrame.size maximumSize:maximumFrame.size];

    if (![_surface synchronouslyWaitForStage:RCTSurfaceStageSurfaceDidInitialMounting timeout:1]) {
      RCTLogInfo(@"Failed to mount LogBox within 1s");
    }

    self.contentView = (NSView *)_surface.view;
    self.contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  return self;
}

- (void)hide
{
  [self close];
}

- (void)show
{
  [NSApp activateIgnoringOtherApps:YES];
  [self makeKeyAndOrderFront:nil];
}

@end

#endif // ]TODO(macOS ISS#2323203)

@interface RCTLogBox () <NativeLogBoxSpec>
@end

@implementation RCTLogBox {
  RCTLogBoxWindow *_window; // TODO(OSS Candidate ISS#2710739) Renamed from _view to _window
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

RCT_EXPORT_METHOD(show)
{
  if (RCTRedBoxGetEnabled()) {
    __weak RCTLogBox *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong RCTLogBox *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      if (!strongSelf->_window) {
        strongSelf->_window = [[RCTLogBoxWindow alloc] initWithBridge:self->_bridge];
      }
      [strongSelf->_window show];
    });
  }
}

RCT_EXPORT_METHOD(hide)
{
  if (RCTRedBoxGetEnabled()) {
    __weak RCTLogBox *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong RCTLogBox *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      [strongSelf->_window hide];
      strongSelf->_window = nil;
    });
  }
}

- (std::shared_ptr<facebook::react::TurboModule>)
    getTurboModuleWithJsInvoker:(std::shared_ptr<facebook::react::CallInvoker>)jsInvoker
                  nativeInvoker:(std::shared_ptr<facebook::react::CallInvoker>)nativeInvoker
                     perfLogger:(id<RCTTurboModulePerformanceLogger>)perfLogger
{
  return std::make_shared<facebook::react::NativeLogBoxSpecJSI>(self, jsInvoker, nativeInvoker, perfLogger);
}

@end

#else // Disabled

@interface RCTLogBox () <NativeLogBoxSpec>
@end

@implementation RCTLogBox

+ (NSString *)moduleName
{
  return nil;
}

- (void)show
{
  // noop
}

- (void)hide
{
  // noop
}

- (std::shared_ptr<facebook::react::TurboModule>)
    getTurboModuleWithJsInvoker:(std::shared_ptr<facebook::react::CallInvoker>)jsInvoker
                  nativeInvoker:(std::shared_ptr<facebook::react::CallInvoker>)nativeInvoker
                     perfLogger:(id<RCTTurboModulePerformanceLogger>)perfLogger
{
  return std::make_shared<facebook::react::NativeLogBoxSpecJSI>(self, jsInvoker, nativeInvoker, perfLogger);
}
@end

#endif

Class RCTLogBoxCls(void)
{
  return RCTLogBox.class;
}
