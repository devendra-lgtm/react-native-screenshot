package com.screenshotshield

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule

/**
 * Old-architecture base class. On the legacy bridge there is no generated spec,
 * so we extend [ReactContextBaseJavaModule] directly and declare the surface
 * that [ScreenshotShieldModule] implements.
 */
abstract class ScreenshotShieldSpec(context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {

  abstract fun enableSecureView(backgroundColor: String?)
  abstract fun disableSecureView()
  abstract fun isBeingCaptured(promise: Promise)
  abstract fun isSecureViewEnabled(promise: Promise)
  abstract fun addListener(eventName: String?)
  abstract fun removeListeners(count: Double)
}
