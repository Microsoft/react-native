/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // TODO(macOS ISS#2323203)

@interface RCTAlertController : UIAlertController

#if !TARGET_OS_OSX // [TODO(macOS ISS#2323203)
- (void)show:(BOOL)animated completion:(void (^)(void))completion;
#endif // ]TODO(macOS ISS#2323203)

@end
