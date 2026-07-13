package com.screenshotshield

import com.facebook.react.bridge.ReactApplicationContext

/**
 * New-architecture base class. Codegen generates `NativeScreenshotShieldSpec`
 * from `src/NativeScreenshotShield.ts`; we extend it so [ScreenshotShieldModule]
 * conforms to the TurboModule interface.
 */
abstract class ScreenshotShieldSpec(context: ReactApplicationContext) :
  NativeScreenshotShieldSpec(context)
