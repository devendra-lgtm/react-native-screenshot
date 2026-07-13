import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

/**
 * Codegen spec for the new architecture (TurboModules).
 *
 * NOTE: TurboModule codegen only supports a constrained set of types. Event
 * emitting is handled via the classic `RCTEventEmitter`/`NativeEventEmitter`
 * pathway (see `src/index.tsx`), which works on both architectures, so the
 * event methods here are only the bookkeeping `addListener`/`removeListeners`
 * required by codegen when a module emits events.
 */
export interface Spec extends TurboModule {
  /**
   * Enable OS-level screenshot & screen-recording protection.
   * Android: sets `WINDOW_SECURE` (FLAG_SECURE) on the current Activity.
   * iOS: installs a safe-area-preserving secure overlay so captured frames
   *      render blank. Pass a hex background color (e.g. "#000000") to control
   *      what appears in the captured/blanked frame.
   */
  enableSecureView(backgroundColor: string): void;

  /**
   * Disable the protection installed by `enableSecureView`.
   */
  disableSecureView(): void;

  /**
   * Resolves `true` while the screen is being captured / recorded / mirrored.
   * iOS: backed by `UIScreen.isCaptured`.
   * Android: best-effort; resolves `false` on OS versions without an API.
   */
  isBeingCaptured(): Promise<boolean>;

  /**
   * Resolves `true` if OS-level secure protection is currently enabled.
   */
  isSecureViewEnabled(): Promise<boolean>;

  // --- Required by codegen for event-emitting modules ---
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.get<Spec>('ScreenshotShield');
