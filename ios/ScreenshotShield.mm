#import "ScreenshotShield.h"
#import <UIKit/UIKit.h>

@interface ScreenshotShield ()

/// The secure text field whose `secureTextEntry` protection excludes its layer
/// subtree from screenshots and screen recordings.
@property (nonatomic, strong, nullable) UITextField *secureField;

/// The RN root view whose layer we move into the secure canvas. Kept so we can
/// put it back when protection is disabled.
@property (nonatomic, weak, nullable) UIView *protectedView;

/// The container layer the protected view's layer originally lived in, so we
/// can restore it exactly on disable.
@property (nonatomic, weak, nullable) CALayer *originalSuperlayer;

@property (nonatomic, assign) BOOL secureEnabled;
@property (nonatomic, assign) BOOL hasListeners;

/// The safe-area insets captured from the window *before* we reparent the RN
/// view. Re-applied as `additionalSafeAreaInsets` so the bottom tab bar keeps
/// its full height (see README → "iOS bottom bar fix").
@property (nonatomic, assign) UIEdgeInsets savedSafeAreaInsets;

@end

@implementation ScreenshotShield

RCT_EXPORT_MODULE(ScreenshotShield)

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

- (instancetype)init {
  if (self = [super init]) {
    _secureEnabled = NO;
    _savedSafeAreaInsets = UIEdgeInsetsZero;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // Screenshot detection.
    [nc addObserver:self
           selector:@selector(handleScreenshot)
               name:UIApplicationUserDidTakeScreenshotNotification
             object:nil];

    // Screen recording / mirroring detection.
    if (@available(iOS 11.0, *)) {
      [nc addObserver:self
             selector:@selector(handleCaptureChanged)
                 name:UIScreenCapturedDidChangeNotification
               object:nil];
    }

    // Re-apply the secure overlay + safe-area fix on orientation / layout
    // changes so it survives rotation and multitasking resizes.
    [nc addObserver:self
           selector:@selector(reapplyIfNeeded)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(reapplyIfNeeded)
               name:UIDeviceOrientationDidChangeNotification
             object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - RCTEventEmitter

- (NSArray<NSString *> *)supportedEvents {
  return @[ @"screenshotTaken", @"screenCaptureChanged" ];
}

- (void)startObserving {
  self.hasListeners = YES;
}

- (void)stopObserving {
  self.hasListeners = NO;
}

- (void)handleScreenshot {
  if (self.hasListeners) {
    [self sendEventWithName:@"screenshotTaken" body:@{}];
  }
}

- (void)handleCaptureChanged {
  BOOL captured = [self currentlyCaptured];
  if (self.hasListeners) {
    [self sendEventWithName:@"screenCaptureChanged" body:@{ @"isCaptured" : @(captured) }];
  }
}

- (BOOL)currentlyCaptured {
  if (@available(iOS 11.0, *)) {
    for (UIScreen *screen in [UIScreen screens]) {
      if (screen.isCaptured) {
        return YES;
      }
    }
  }
  return NO;
}

#pragma mark - Window helpers

- (nullable UIWindow *)keyWindow {
  UIWindow *keyWindow = nil;
  if (@available(iOS 13.0, *)) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if (scene.activationState == UISceneActivationStateForegroundActive &&
          [scene isKindOfClass:[UIWindowScene class]]) {
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
          if (window.isKeyWindow) {
            keyWindow = window;
            break;
          }
        }
      }
      if (keyWindow) break;
    }
  }
  if (keyWindow == nil) {
#if !TARGET_OS_MACCATALYST
    keyWindow = UIApplication.sharedApplication.keyWindow;
#endif
  }
  return keyWindow;
}

#pragma mark - Exported: secure view

RCT_EXPORT_METHOD(enableSecureView:(NSString *)backgroundColor) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self applySecureViewWithColor:backgroundColor];
  });
}

RCT_EXPORT_METHOD(disableSecureView) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self removeSecureView];
  });
}

RCT_EXPORT_METHOD(isBeingCaptured:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject) {
  resolve(@([self currentlyCaptured]));
}

RCT_EXPORT_METHOD(isSecureViewEnabled:(RCTPromiseResolveBlock)resolve
                             rejecter:(RCTPromiseRejectBlock)reject) {
  resolve(@(self.secureEnabled));
}

RCT_EXPORT_METHOD(addListener:(NSString *)eventName) {
  // Bookkeeping only — RCTEventEmitter manages the actual subscriptions.
}

RCT_EXPORT_METHOD(removeListeners:(double)count) {
  // Bookkeeping only.
}

#pragma mark - Secure view implementation (with bottom-bar / safe-area fix)

- (void)applySecureViewWithColor:(NSString *)hexColor {
  UIWindow *window = [self keyWindow];
  if (window == nil) {
    return;
  }

  // The RN root view — the first subview of the window.
  UIView *rootView = window.subviews.firstObject;
  if (rootView == nil) {
    return;
  }

  // If it's already installed, just re-sync the frame and bail.
  if (self.secureEnabled && self.secureField != nil) {
    self.secureField.frame = window.bounds;
    return;
  }

  // 1. Capture the window's safe-area insets BEFORE we touch the hierarchy.
  //    Reparenting the RN view's layer into the secure canvas detaches it from
  //    UIKit's view-based safe-area propagation, which is exactly what makes
  //    the React Navigation bottom tab bar collapse in other libraries. We
  //    remember the real insets here and re-apply them below.
  if (@available(iOS 11.0, *)) {
    self.savedSafeAreaInsets = window.safeAreaInsets;
  } else {
    self.savedSafeAreaInsets = UIEdgeInsetsZero;
  }

  // 2. Build the secure text field. `secureTextEntry` makes its whole layer
  //    subtree render blank in screenshots and screen recordings.
  UITextField *field = [[UITextField alloc] initWithFrame:window.bounds];
  field.secureTextEntry = YES;
  field.userInteractionEnabled = NO;
  field.backgroundColor = [self colorFromHex:hexColor];
  field.translatesAutoresizingMaskIntoConstraints = YES;
  field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  self.secureField = field;
  self.protectedView = rootView;
  self.originalSuperlayer = rootView.layer.superlayer;

  // 3. Attach the secure field to the window and move the RN view's layer into
  //    the secure canvas (the field's inner layout layer). The RN *view* stays
  //    a subview of the window, so touches and the responder chain keep
  //    working; only the layer is rendered through the secure canvas.
  [window addSubview:field];
  [window.layer addSublayer:field.layer];
  CALayer *secureCanvas = field.layer.sublayers.firstObject ?: field.layer;
  [secureCanvas addSublayer:rootView.layer];

  // 4. THE FIX: restore the safe-area insets that the layer move stripped away.
  //    Applying them as `additionalSafeAreaInsets` on the root view controller
  //    means react-native-safe-area-context reports the correct bottom inset
  //    again, so the bottom tab bar keeps its full height.
  [self applySafeAreaFix:window];

  self.secureEnabled = YES;
}

- (void)applySafeAreaFix:(UIWindow *)window {
  if (@available(iOS 11.0, *)) {
    UIViewController *rootVC = window.rootViewController;
    if (rootVC != nil) {
      // The reparented view now reports ~zero insets, so adding the saved
      // insets reconstitutes the correct total safe area.
      rootVC.additionalSafeAreaInsets = self.savedSafeAreaInsets;
      [rootVC.view setNeedsLayout];
      [rootVC.view layoutIfNeeded];
    }
  }
}

- (void)removeSecureView {
  if (!self.secureEnabled) {
    return;
  }

  UIWindow *window = [self keyWindow];

  // Move the RN view's layer back to where it started.
  if (self.protectedView != nil && self.originalSuperlayer != nil) {
    [self.originalSuperlayer addSublayer:self.protectedView.layer];
  }

  [self.secureField.layer removeFromSuperlayer];
  [self.secureField removeFromSuperview];
  self.secureField = nil;

  // Undo the safe-area compensation.
  if (@available(iOS 11.0, *)) {
    UIViewController *rootVC = window.rootViewController;
    if (rootVC != nil) {
      rootVC.additionalSafeAreaInsets = UIEdgeInsetsZero;
      [rootVC.view setNeedsLayout];
      [rootVC.view layoutIfNeeded];
    }
  }

  self.protectedView = nil;
  self.originalSuperlayer = nil;
  self.savedSafeAreaInsets = UIEdgeInsetsZero;
  self.secureEnabled = NO;
}

- (void)reapplyIfNeeded {
  if (!self.secureEnabled) {
    return;
  }
  UIWindow *window = [self keyWindow];
  if (window != nil && self.secureField != nil) {
    self.secureField.frame = window.bounds;
    // Keep the safe-area compensation in sync after rotation.
    if (@available(iOS 11.0, *)) {
      self.savedSafeAreaInsets = window.safeAreaInsets.bottom > self.savedSafeAreaInsets.bottom
                                     ? window.safeAreaInsets
                                     : self.savedSafeAreaInsets;
    }
    [self applySafeAreaFix:window];
  }
}

#pragma mark - Utils

- (UIColor *)colorFromHex:(NSString *)hex {
  if (hex == nil || hex.length == 0) {
    return [UIColor blackColor];
  }
  NSString *cleaned = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if (cleaned.length != 6 && cleaned.length != 8) {
    return [UIColor blackColor];
  }
  unsigned int rgb = 0;
  NSScanner *scanner = [NSScanner scannerWithString:cleaned];
  if (![scanner scanHexInt:&rgb]) {
    return [UIColor blackColor];
  }
  CGFloat r, g, b, a = 1.0;
  if (cleaned.length == 8) {
    a = ((rgb & 0xFF000000) >> 24) / 255.0;
    r = ((rgb & 0x00FF0000) >> 16) / 255.0;
    g = ((rgb & 0x0000FF00) >> 8) / 255.0;
    b = (rgb & 0x000000FF) / 255.0;
  } else {
    r = ((rgb & 0xFF0000) >> 16) / 255.0;
    g = ((rgb & 0x00FF00) >> 8) / 255.0;
    b = (rgb & 0x0000FF) / 255.0;
  }
  return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

#pragma mark - New architecture (TurboModule)

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeScreenshotShieldSpecJSI>(params);
}
#endif

@end
