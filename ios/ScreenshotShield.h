#import <React/RCTEventEmitter.h>
#import <React/RCTBridgeModule.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RNScreenshotShieldSpec/RNScreenshotShieldSpec.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface ScreenshotShield : RCTEventEmitter <RCTBridgeModule>
@end

NS_ASSUME_NONNULL_END
