/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RCTSurfacePresenter.h"

#import <mutex>

#import <React/RCTAssert.h>
#import <React/RCTComponentViewFactory.h>
#import <React/RCTComponentViewRegistry.h>
#import <React/RCTFabricSurface.h>
#import <React/RCTFollyConvert.h>
#import <React/RCTI18nUtil.h>
#import <React/RCTMountingManager.h>
#import <React/RCTMountingManagerDelegate.h>
#import <React/RCTScheduler.h>
#import <React/RCTSurfaceRegistry.h>
#import <React/RCTSurfaceView+Internal.h>
#import <React/RCTSurfaceView.h>
#import <React/RCTUtils.h>

#import <react/componentregistry/ComponentDescriptorFactory.h>
#import <react/components/root/RootShadowNode.h>
#import <react/config/ReactNativeConfig.h>
#import <react/core/LayoutConstraints.h>
#import <react/core/LayoutContext.h>
#import <react/scheduler/SchedulerToolbox.h>
#import <react/utils/ContextContainer.h>
#import <react/utils/ManagedObjectWrapper.h>

#import "MainRunLoopEventBeat.h"
#import "RCTConversions.h"
#import "RuntimeEventBeat.h"

using namespace facebook::react;

static inline LayoutConstraints RCTGetLayoutConstraintsForSize(CGSize minimumSize, CGSize maximumSize)
{
  return {
      .minimumSize = RCTSizeFromCGSize(minimumSize),
      .maximumSize = RCTSizeFromCGSize(maximumSize),
      .layoutDirection = RCTLayoutDirection([[RCTI18nUtil sharedInstance] isRTL]),
  };
}

static inline LayoutContext RCTGetLayoutContext()
{
  return {.pointScaleFactor = RCTScreenScale(),
          .swapLeftAndRightInRTL =
              [[RCTI18nUtil sharedInstance] isRTL] && [[RCTI18nUtil sharedInstance] doLeftAndRightSwapInRTL]};
}

@interface RCTSurfacePresenter () <RCTSchedulerDelegate, RCTMountingManagerDelegate>
@end

@implementation RCTSurfacePresenter {
  RCTMountingManager *_mountingManager; // Thread-safe.
  RCTSurfaceRegistry *_surfaceRegistry; // Thread-safe.

  std::mutex _schedulerAccessMutex;
  std::mutex _schedulerLifeCycleMutex;
  RCTScheduler *_Nullable _scheduler; // Thread-safe. Pointer is protected by `_schedulerAccessMutex`.
  ContextContainer::Shared _contextContainer; // Protected by `_schedulerLifeCycleMutex`.
  RuntimeExecutor _runtimeExecutor; // Protected by `_schedulerLifeCycleMutex`.

  better::shared_mutex _observerListMutex;
  NSMutableArray<id<RCTSurfacePresenterObserver>> *_observers;
  RCTImageLoader *_imageLoader;
  RuntimeExecutor _runtimeExecutor;
}

- (instancetype)initWithContextContainer:(ContextContainer::Shared)contextContainer
                         runtimeExecutor:(RuntimeExecutor)runtimeExecutor
{
  if (self = [super init]) {
    assert(contextContainer && "RuntimeExecutor must be not null.");

    _runtimeExecutor = runtimeExecutor;
    _contextContainer = contextContainer;

    _surfaceRegistry = [[RCTSurfaceRegistry alloc] init];
    _mountingManager = [[RCTMountingManager alloc] init];
    _mountingManager.delegate = self;

    _observers = [NSMutableArray array];

    _scheduler = [self _createScheduler];
  }

  return self;
}

- (RCTScheduler *_Nullable)_scheduler
{
  std::lock_guard<std::mutex> lock(_schedulerAccessMutex);
  return _scheduler;
}

- (ContextContainer::Shared)contextContainer
{
  std::lock_guard<std::mutex> lock(_schedulerLifeCycleMutex);
  return _contextContainer;
}

- (void)setContextContainer:(ContextContainer::Shared)contextContainer
{
  std::lock_guard<std::mutex> lock(_schedulerLifeCycleMutex);
  _contextContainer = contextContainer;
}

- (RuntimeExecutor)runtimeExecutor
{
  std::lock_guard<std::mutex> lock(_schedulerLifeCycleMutex);
  return _runtimeExecutor;
}

- (void)setRuntimeExecutor:(RuntimeExecutor)runtimeExecutor
{
  std::lock_guard<std::mutex> lock(_schedulerLifeCycleMutex);
  _runtimeExecutor = runtimeExecutor;
}

#pragma mark - Internal Surface-dedicated Interface

- (void)registerSurface:(RCTFabricSurface *)surface
{
  RCTScheduler *scheduler = [self _scheduler];
  [_surfaceRegistry registerSurface:surface];
  if (scheduler) {
    [self _startSurface:surface scheduler:scheduler];
  }
}

- (void)unregisterSurface:(RCTFabricSurface *)surface
{
  RCTScheduler *scheduler = [self _scheduler];
  if (scheduler) {
    [self _stopSurface:surface scheduler:scheduler];
  }
  [_surfaceRegistry unregisterSurface:surface];
}

- (void)setProps:(NSDictionary *)props surface:(RCTFabricSurface *)surface
{
  RCTScheduler *scheduler = [self _scheduler];
  if (scheduler) {
    [self _stopSurface:surface scheduler:scheduler];
    [self _startSurface:surface scheduler:scheduler];
  }
}

- (RCTFabricSurface *)surfaceForRootTag:(ReactTag)rootTag
{
  return [_surfaceRegistry surfaceForRootTag:rootTag];
}

- (CGSize)sizeThatFitsMinimumSize:(CGSize)minimumSize
                      maximumSize:(CGSize)maximumSize
                          surface:(RCTFabricSurface *)surface
{
  RCTScheduler *scheduler = [self _scheduler];
  if (!scheduler) {
    return minimumSize;
  }
  LayoutContext layoutContext = RCTGetLayoutContext();
  LayoutConstraints layoutConstraints = RCTGetLayoutConstraintsForSize(minimumSize, maximumSize);
  return [scheduler measureSurfaceWithLayoutConstraints:layoutConstraints
                                          layoutContext:layoutContext
                                              surfaceId:surface.rootTag];
}

- (void)setMinimumSize:(CGSize)minimumSize maximumSize:(CGSize)maximumSize surface:(RCTFabricSurface *)surface
{
  RCTScheduler *scheduler = [self _scheduler];
  if (!scheduler) {
    return;
  }

  LayoutContext layoutContext = RCTGetLayoutContext();
  LayoutConstraints layoutConstraints = RCTGetLayoutConstraintsForSize(minimumSize, maximumSize);
  [scheduler constraintSurfaceLayoutWithLayoutConstraints:layoutConstraints
                                            layoutContext:layoutContext
                                                surfaceId:surface.rootTag];
}

- (BOOL)synchronouslyUpdateViewOnUIThread:(NSNumber *)reactTag props:(NSDictionary *)props
{
  RCTScheduler *scheduler = [self _scheduler];
  if (!scheduler) {
    return NO;
  }

  ReactTag tag = [reactTag integerValue];
  UIView<RCTComponentViewProtocol> *componentView =
      [_mountingManager.componentViewRegistry findComponentViewWithTag:tag];
  if (componentView == nil) {
    return NO; // This view probably isn't managed by Fabric
  }
  ComponentHandle handle = [[componentView class] componentDescriptorProvider].handle;
  auto *componentDescriptor = [scheduler findComponentDescriptorByHandle_DO_NOT_USE_THIS_IS_BROKEN:handle];

  if (!componentDescriptor) {
    return YES;
  }

  [_mountingManager synchronouslyUpdateViewOnUIThread:tag changedProps:props componentDescriptor:*componentDescriptor];
  return YES;
}

- (BOOL)synchronouslyWaitSurface:(RCTFabricSurface *)surface timeout:(NSTimeInterval)timeout
{
  RCTScheduler *scheduler = [self _scheduler];
  if (!scheduler) {
    return NO;
  }

  auto mountingCoordinator = [scheduler mountingCoordinatorWithSurfaceId:surface.rootTag];

  if (!mountingCoordinator->waitForTransaction(std::chrono::duration<NSTimeInterval>(timeout))) {
    return NO;
  }

  [_mountingManager scheduleTransaction:mountingCoordinator];

  return YES;
}

- (BOOL)suspend
{
  std::lock_guard<std::mutex> lock(_schedulerLifeCycleMutex);

  RCTScheduler *scheduler;
  {
    std::lock_guard<std::mutex> accessLock(_schedulerAccessMutex);

    if (!_scheduler) {
      return NO;
    }
    scheduler = _scheduler;
    _scheduler = nil;
  }

  [self _stopAllSurfacesWithScheduler:scheduler];

  return YES;
}

- (BOOL)resume
{
  std::lock_guard<std::mutex> lock(_schedulerLifeCycleMutex);

  RCTScheduler *scheduler;
  {
    std::lock_guard<std::mutex> accessLock(_schedulerAccessMutex);

    if (_scheduler) {
      return NO;
    }
    scheduler = [self _createScheduler];
  }

  [self _startAllSurfacesWithScheduler:scheduler];

  {
    std::lock_guard<std::mutex> accessLock(_schedulerAccessMutex);
    _scheduler = scheduler;
  }

  return YES;
}

#pragma mark - Private

- (RCTScheduler *)_createScheduler
{
  auto componentRegistryFactory =
      [factory = wrapManagedObject(_mountingManager.componentViewRegistry.componentViewFactory)](
          EventDispatcher::Weak const &eventDispatcher, ContextContainer::Shared const &contextContainer) {
        return [(RCTComponentViewFactory *)unwrapManagedObject(factory)
            createComponentDescriptorRegistryWithParameters:{eventDispatcher, contextContainer}];
      };

  auto runtimeExecutor = _runtimeExecutor;

  auto toolbox = SchedulerToolbox{};
  toolbox.contextContainer = _contextContainer;
  toolbox.componentRegistryFactory = componentRegistryFactory;
  toolbox.runtimeExecutor = runtimeExecutor;

  toolbox.synchronousEventBeatFactory = [runtimeExecutor](EventBeat::SharedOwnerBox const &ownerBox) {
    return std::make_unique<MainRunLoopEventBeat>(ownerBox, runtimeExecutor);
  };

  toolbox.asynchronousEventBeatFactory = [runtimeExecutor](EventBeat::SharedOwnerBox const &ownerBox) {
    return std::make_unique<RuntimeEventBeat>(ownerBox, runtimeExecutor);
  };

  RCTScheduler *scheduler = [[RCTScheduler alloc] initWithToolbox:toolbox];
  scheduler.delegate = self;

  auto reactNativeConfig = _contextContainer->at<std::shared_ptr<ReactNativeConfig const>>("ReactNativeConfig");
  if (reactNativeConfig) {
    _mountingManager.useModernDifferentiatorMode =
        reactNativeConfig->getBool("react_fabric:enabled_optimized_moves_differ_ios");
  }

  return scheduler;
}

- (void)_startSurface:(RCTFabricSurface *)surface scheduler:(RCTScheduler *)scheduler
{
  RCTMountingManager *mountingManager = _mountingManager;
  RCTExecuteOnMainQueue(^{
    [mountingManager.componentViewRegistry dequeueComponentViewWithComponentHandle:RootShadowNode::Handle()
                                                                               tag:surface.rootTag];
  });

  LayoutContext layoutContext = RCTGetLayoutContext();

  LayoutConstraints layoutConstraints = RCTGetLayoutConstraintsForSize(surface.minimumSize, surface.maximumSize);

  [scheduler startSurfaceWithSurfaceId:surface.rootTag
                            moduleName:surface.moduleName
                          initialProps:surface.properties
                     layoutConstraints:layoutConstraints
                         layoutContext:layoutContext];
}

- (void)_stopSurface:(RCTFabricSurface *)surface scheduler:(RCTScheduler *)scheduler
{
  [scheduler stopSurfaceWithSurfaceId:surface.rootTag];

  RCTMountingManager *mountingManager = _mountingManager;
  RCTExecuteOnMainQueue(^{
    RCTComponentViewDescriptor rootViewDescriptor =
        [mountingManager.componentViewRegistry componentViewDescriptorWithTag:surface.rootTag];
    [mountingManager.componentViewRegistry enqueueComponentViewWithComponentHandle:RootShadowNode::Handle()
                                                                               tag:surface.rootTag
                                                           componentViewDescriptor:rootViewDescriptor];
  });

  [surface _unsetStage:(RCTSurfaceStagePrepared | RCTSurfaceStageMounted)];
}

- (void)_startAllSurfacesWithScheduler:(RCTScheduler *)scheduler
{
  [_surfaceRegistry enumerateWithBlock:^(NSEnumerator<RCTFabricSurface *> *enumerator) {
    for (RCTFabricSurface *surface in enumerator) {
      [self _startSurface:surface scheduler:scheduler];
    }
  }];
}

- (void)_stopAllSurfacesWithScheduler:(RCTScheduler *)scheduler
{
  [_surfaceRegistry enumerateWithBlock:^(NSEnumerator<RCTFabricSurface *> *enumerator) {
    for (RCTFabricSurface *surface in enumerator) {
      [self _stopSurface:surface scheduler:scheduler];
    }
  }];
}

#pragma mark - RCTSchedulerDelegate

- (void)schedulerDidFinishTransaction:(MountingCoordinator::Shared const &)mountingCoordinator
{
  RCTFabricSurface *surface = [_surfaceRegistry surfaceForRootTag:mountingCoordinator->getSurfaceId()];

  [surface _setStage:RCTSurfaceStagePrepared];

  [_mountingManager scheduleTransaction:mountingCoordinator];
}

- (void)schedulerDidDispatchCommand:(ShadowView const &)shadowView
                        commandName:(std::string const &)commandName
                               args:(folly::dynamic const)args
{
  ReactTag tag = shadowView.tag;
  NSString *commandStr = [[NSString alloc] initWithUTF8String:commandName.c_str()];
  NSArray *argsArray = convertFollyDynamicToId(args);

  [self->_mountingManager dispatchCommand:tag commandName:commandStr args:argsArray];
}

- (void)addObserver:(id<RCTSurfacePresenterObserver>)observer
{
  std::unique_lock<better::shared_mutex> lock(_observerListMutex);
  [self->_observers addObject:observer];
}

- (void)removeObserver:(id<RCTSurfacePresenterObserver>)observer
{
  std::unique_lock<better::shared_mutex> lock(_observerListMutex);
  [self->_observers removeObject:observer];
}

#pragma mark - RCTMountingManagerDelegate

- (void)mountingManager:(RCTMountingManager *)mountingManager willMountComponentsWithRootTag:(ReactTag)rootTag
{
  RCTAssertMainQueue();

  std::shared_lock<better::shared_mutex> lock(_observerListMutex);
  for (id<RCTSurfacePresenterObserver> observer in _observers) {
    if ([observer respondsToSelector:@selector(willMountComponentsWithRootTag:)]) {
      [observer willMountComponentsWithRootTag:rootTag];
    }
  }
}

- (void)mountingManager:(RCTMountingManager *)mountingManager didMountComponentsWithRootTag:(ReactTag)rootTag
{
  RCTAssertMainQueue();

  RCTFabricSurface *surface = [_surfaceRegistry surfaceForRootTag:rootTag];
  RCTSurfaceStage stage = surface.stage;
  if (stage & RCTSurfaceStagePrepared) {
    // We have to progress the stage only if the preparing phase is done.
    if ([surface _setStage:RCTSurfaceStageMounted]) {
      auto rootComponentViewDescriptor =
          [_mountingManager.componentViewRegistry componentViewDescriptorWithTag:rootTag];
      surface.view.rootView = (RCTSurfaceRootView *)rootComponentViewDescriptor.view;
    }
  }

  std::shared_lock<better::shared_mutex> lock(_observerListMutex);
  for (id<RCTSurfacePresenterObserver> observer in _observers) {
    if ([observer respondsToSelector:@selector(didMountComponentsWithRootTag:)]) {
      [observer didMountComponentsWithRootTag:rootTag];
    }
  }
}

@end
