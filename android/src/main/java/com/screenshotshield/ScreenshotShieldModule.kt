package com.screenshotshield

import android.app.Activity
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.WindowManager
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.Arguments
import com.facebook.react.modules.core.DeviceEventManagerModule
import java.util.concurrent.Executor

class ScreenshotShieldModule(private val reactContext: ReactApplicationContext) :
  ScreenshotShieldSpec(reactContext), LifecycleEventListener {

  private var secureEnabled = false
  private var listenerCount = 0

  private var screenshotObserver: ContentObserver? = null

  // Android 14 (API 34) native screen-capture callback.
  private var screenCaptureCallback: Any? = null

  init {
    reactContext.addLifecycleEventListener(this)
  }

  override fun getName(): String = NAME

  // --- Secure view ---------------------------------------------------------

  @ReactMethod
  override fun enableSecureView(backgroundColor: String?) {
    // On Android FLAG_SECURE blocks BOTH screenshots and screen recording at
    // the OS level, and it does not alter the view hierarchy — so there is no
    // safe-area / bottom-bar side effect to work around here (that is
    // iOS-specific). backgroundColor is accepted for API parity but unused.
    val activity: Activity = currentActivity ?: return
    activity.runOnUiThread {
      activity.window.setFlags(
        WindowManager.LayoutParams.FLAG_SECURE,
        WindowManager.LayoutParams.FLAG_SECURE
      )
      secureEnabled = true
    }
  }

  @ReactMethod
  override fun disableSecureView() {
    val activity: Activity = currentActivity ?: return
    activity.runOnUiThread {
      activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
      secureEnabled = false
    }
  }

  @ReactMethod
  override fun isSecureViewEnabled(promise: Promise) {
    promise.resolve(secureEnabled)
  }

  @ReactMethod
  override fun isBeingCaptured(promise: Promise) {
    // Android has no synchronous "am I being recorded" API pre-34. We rely on
    // the registered callback (API 34+) for events; this resolves false when
    // unsupported.
    promise.resolve(false)
  }

  // --- Screenshot detection (ContentObserver on MediaStore) ----------------

  private fun startScreenshotObserver() {
    if (screenshotObserver != null) return
    val handler = Handler(Looper.getMainLooper())
    val observer = object : ContentObserver(handler) {
      override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        if (uri == null) return
        try {
          val path = resolvePath(uri)
          if (path != null && path.lowercase().contains("screenshot")) {
            emit("screenshotTaken", Arguments.createMap())
          }
        } catch (_: Exception) {
          // Ignore transient query failures.
        }
      }
    }
    reactContext.contentResolver.registerContentObserver(
      MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
      true,
      observer
    )
    screenshotObserver = observer
  }

  private fun stopScreenshotObserver() {
    screenshotObserver?.let { reactContext.contentResolver.unregisterContentObserver(it) }
    screenshotObserver = null
  }

  private fun resolvePath(uri: Uri): String? {
    val projection = arrayOf(MediaStore.Images.Media.DISPLAY_NAME, MediaStore.Images.Media.DATA)
    reactContext.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
      if (cursor.moveToFirst()) {
        val nameIndex = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
        if (nameIndex >= 0) return cursor.getString(nameIndex)
      }
    }
    return null
  }

  // --- Screen-capture detection (API 34+) ----------------------------------

  private fun registerScreenCaptureCallback() {
    if (Build.VERSION.SDK_INT < 34) return
    val activity = currentActivity ?: return
    if (screenCaptureCallback != null) return
    val executor: Executor = Executor { command -> activity.runOnUiThread(command) }
    val callback = Activity.ScreenCaptureCallback {
      val map: WritableMap = Arguments.createMap()
      map.putBoolean("isCaptured", true)
      emit("screenCaptureChanged", map)
    }
    activity.registerScreenCaptureCallback(executor, callback)
    screenCaptureCallback = callback
  }

  private fun unregisterScreenCaptureCallback() {
    if (Build.VERSION.SDK_INT < 34) return
    val activity = currentActivity ?: return
    (screenCaptureCallback as? Activity.ScreenCaptureCallback)?.let {
      try {
        activity.unregisterScreenCaptureCallback(it)
      } catch (_: Exception) {
      }
    }
    screenCaptureCallback = null
  }

  // --- Event plumbing ------------------------------------------------------

  private fun emit(eventName: String, params: WritableMap) {
    if (listenerCount == 0) return
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(eventName, params)
  }

  @ReactMethod
  override fun addListener(eventName: String?) {
    if (listenerCount == 0) {
      startScreenshotObserver()
      registerScreenCaptureCallback()
    }
    listenerCount += 1
  }

  @ReactMethod
  override fun removeListeners(count: Double) {
    listenerCount = (listenerCount - count.toInt()).coerceAtLeast(0)
    if (listenerCount == 0) {
      stopScreenshotObserver()
      unregisterScreenCaptureCallback()
    }
  }

  // --- Lifecycle -----------------------------------------------------------

  override fun onHostResume() {
    if (listenerCount > 0) registerScreenCaptureCallback()
  }

  override fun onHostPause() {
    unregisterScreenCaptureCallback()
  }

  override fun onHostDestroy() {
    stopScreenshotObserver()
    unregisterScreenCaptureCallback()
  }

  companion object {
    const val NAME = "ScreenshotShield"
  }
}
