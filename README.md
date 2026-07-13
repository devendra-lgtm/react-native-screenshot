# react-native-screenshot-shield

Prevent **screenshots** and **screen recording** in React Native, on **iOS and Android**, with support for **both** the old bridge and the new architecture (Fabric / TurboModules).

It works like `react-native-screenshot-prevent`, and additionally **fixes the well-known iOS bug where enabling the secure view shrinks the React Navigation bottom tab bar** (the home-indicator safe-area inset collapses to `0`).

## Features

- 🔒 Block screenshots & screen recording (`FLAG_SECURE` on Android, secure-overlay on iOS)
- 🧯 **iOS bottom-bar fix** — secure view no longer collapses the bottom safe-area inset
- 📸 Screenshot detection events (iOS + Android)
- 🎥 Screen recording / mirroring detection (`UIScreen.isCaptured` on iOS, `ScreenCaptureCallback` on Android 14+)
- 🏛️ Works on old **and** new architecture
- 🧩 TypeScript types included

## Installation

```sh
npm install react-native-screenshot-shield
# or
yarn add react-native-screenshot-shield
```

### iOS

```sh
cd ios && pod install
```

### Android

Autolinking handles everything. No manual steps.

> This library ships native code, so it does **not** work in Expo Go. Use a development build (`expo prebuild` / EAS) or a bare React Native app.

## Usage

```ts
import ScreenshotShield, {
  enableSecureView,
  disableSecureView,
  isBeingCaptured,
  addScreenshotListener,
  addScreenCaptureListener,
} from 'react-native-screenshot-shield';

// Turn protection on (blocks screenshots + screen recording)
enableSecureView({ backgroundColor: '#000000' });

// Turn it off
disableSecureView();

// Detect screenshots
const sub = addScreenshotListener(() => {
  console.log('User took a screenshot!');
});

// Detect screen recording / mirroring
const capSub = addScreenCaptureListener(({ isCaptured }) => {
  console.log('Screen capture active:', isCaptured);
});

// One-shot query (iOS: UIScreen.isCaptured)
const captured = await isBeingCaptured();

// Clean up
sub.remove();
capSub.remove();
```

### Protect only certain screens

```tsx
import { useFocusEffect } from '@react-navigation/native';
import { useCallback } from 'react';
import { enableSecureView, disableSecureView } from 'react-native-screenshot-shield';

function SecretScreen() {
  useFocusEffect(
    useCallback(() => {
      enableSecureView();
      return () => disableSecureView();
    }, [])
  );
  // ...
}
```

## API

| Function | Description |
| --- | --- |
| `enableSecureView(options?)` | Enable OS-level screenshot + recording protection. `options.backgroundColor` (iOS) sets the color shown in the blanked frame. Defaults to `#000000`. |
| `disableSecureView()` | Disable protection. |
| `isBeingCaptured(): Promise<boolean>` | `true` while the screen is recorded/mirrored (iOS `UIScreen.isCaptured`; Android best-effort). |
| `isSecureViewEnabled(): Promise<boolean>` | Whether protection is currently on. |
| `addScreenshotListener(cb): EmitterSubscription` | Fires when the user takes a screenshot. |
| `addScreenCaptureListener(cb): EmitterSubscription` | Fires when capture/recording state changes. Payload: `{ isCaptured: boolean }`. |

## The iOS bottom-bar fix

**The problem.** The usual iOS screenshot-prevention trick puts the app content inside a `secureTextEntry` `UITextField` by moving the React Native root view's **layer** into the text field's secure canvas. UIKit propagates `safeAreaInsets` through the **view** hierarchy, not the layer hierarchy — so once the RN view's layer is reparented, the view stops receiving the bottom safe-area inset. `safeAreaInsets.bottom` drops to `0`, and libraries that read it (like `react-native-safe-area-context`, which powers React Navigation) compute a **shorter bottom tab bar** (missing the ~34pt home-indicator inset).

**The fix.** This library captures the window's real `safeAreaInsets` **before** reparenting, and then re-applies them as `additionalSafeAreaInsets` on the root view controller. The secure canvas still blanks captured frames, but `react-native-safe-area-context` reports the correct bottom inset again — so the tab bar keeps its full height. The insets are re-synced on rotation and app-activation, and cleanly reset when you call `disableSecureView()`.

See `ios/ScreenshotShield.mm` (`applySecureViewWithColor:` and `applySafeAreaFix:`) for the implementation.

## Platform notes

- **Android** uses `WindowManager.LayoutParams.FLAG_SECURE`, which blocks screenshots *and* screen recording at the OS level. It doesn't alter the view hierarchy, so there's no safe-area side effect to fix on Android.
- **Screen-recording detection on Android** requires **API 34+** (`Activity.ScreenCaptureCallback`). On older versions, recording is still blocked by `FLAG_SECURE`, but the change event won't fire.
- **Screenshot detection on Android** observes `MediaStore` for new images whose name contains `screenshot`. Behavior varies by OEM.
- iOS **cannot block a screenshot from being taken** (the OS doesn't allow it); the secure view instead makes the captured image blank. Recording/mirroring *is* blanked live.

## License

MIT © Devendra Sharma
