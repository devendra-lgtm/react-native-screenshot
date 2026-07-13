import {
  NativeEventEmitter,
  NativeModules,
  Platform,
  type EmitterSubscription,
} from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-screenshot-shield' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go (this library requires custom native code)\n';

// Resolve the native module for BOTH architectures.
// On the new architecture the TurboModule is registered under the same name,
// and `NativeModules` proxies to it transparently, so this single lookup works
// for old bridge + Fabric/TurboModules.
const ScreenshotShieldModule = NativeModules.ScreenshotShield
  ? NativeModules.ScreenshotShield
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

const emitter = new NativeEventEmitter(ScreenshotShieldModule);

export type ScreenshotShieldEvent =
  /** User captured a screenshot (iOS + Android). */
  | 'screenshotTaken'
  /** Screen capture / recording / mirroring state changed (iOS; Android 34+). */
  | 'screenCaptureChanged';

export interface ScreenCaptureChangedPayload {
  isCaptured: boolean;
}

export interface SecureViewOptions {
  /**
   * The solid color shown in the captured/blanked frame on iOS.
   * Defaults to black. Ignored on Android (FLAG_SECURE blanks natively).
   */
  backgroundColor?: string;
}

/**
 * Enable OS-level protection against screenshots AND screen recording.
 *
 * - **Android:** applies `WindowManager.LayoutParams.FLAG_SECURE` to the current
 *   Activity. Screenshots and screen recordings are blocked by the OS.
 * - **iOS:** installs a `secureTextEntry`-backed overlay so any captured frame
 *   renders as a solid color. Unlike the naive implementation used by other
 *   libraries, this keeps the React Native root view inside the live view
 *   hierarchy, so `safeAreaInsets` stay correct and the React Navigation bottom
 *   tab bar keeps its full height. See README → "iOS bottom bar fix".
 */
export function enableSecureView(options: SecureViewOptions = {}): void {
  const backgroundColor = options.backgroundColor ?? '#000000';
  ScreenshotShieldModule.enableSecureView(backgroundColor);
}

/**
 * Remove the protection installed by {@link enableSecureView}.
 */
export function disableSecureView(): void {
  ScreenshotShieldModule.disableSecureView();
}

/**
 * Whether the screen is currently being captured/recorded/mirrored.
 * iOS: backed by `UIScreen.isCaptured`. Android: best-effort (false on
 * versions without a supported API).
 */
export function isBeingCaptured(): Promise<boolean> {
  return ScreenshotShieldModule.isBeingCaptured();
}

/**
 * Whether secure protection is currently enabled.
 */
export function isSecureViewEnabled(): Promise<boolean> {
  return ScreenshotShieldModule.isSecureViewEnabled();
}

/**
 * Subscribe to screenshot events. The callback fires whenever the user takes a
 * screenshot. Remember to call `.remove()` on the returned subscription.
 */
export function addScreenshotListener(
  callback: () => void
): EmitterSubscription {
  return emitter.addListener('screenshotTaken', callback);
}

/**
 * Subscribe to screen-capture (recording/mirroring) state changes.
 * Remember to call `.remove()` on the returned subscription.
 */
export function addScreenCaptureListener(
  callback: (payload: ScreenCaptureChangedPayload) => void
): EmitterSubscription {
  return emitter.addListener('screenCaptureChanged', callback);
}

const ScreenshotShield = {
  enableSecureView,
  disableSecureView,
  isBeingCaptured,
  isSecureViewEnabled,
  addScreenshotListener,
  addScreenCaptureListener,
};

export default ScreenshotShield;
