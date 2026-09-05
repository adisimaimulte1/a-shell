# A-Shell lock/sign-in background handling

A-Shell uses the normal per-user Windows lock-screen API. It does not force a second machine-policy/CSP lock image. Old A-Shell machine image pins are migrated away.

## Lock screen (clock screen)

Windows 11 LockApp uses `ashell-lockscreen-clear-background_1.7.dll`. A-Shell explicitly makes these stable LockApp layers transparent/collapsed while screen styling is enabled:

- `LockScreenOverlay`
- `DimmingOverlayPassword`
- `DimmingOverlayNoPassword`

Recent LockApp states can also create an unnamed dim surface. The LockApp-only fallback removes a brush only when it is a dark, partially transparent solid brush and belongs to a named background context or covers at least 90% of the XAML root. It never changes the image element or an opaque background, and it is not injected into `LogonUI.exe`.

## Sign-in blur

A-Shell sets and verifies:

`HKLM\SOFTWARE\Policies\Microsoft\Windows\System\DisableAcrylicBackgroundOnLogon = 1`

The original value is captured and restored when screen styling is restored.

## Separate 40-45% black sign-in backdrop

`LogonUI.exe` is handled only by the narrow `ashell-signin-clear-background_1.0.dll` hook. It is the previously verified implementation: on its verified `Windows.UI.Logon.dll` build it targets the known background getter/member and changes only the opaque black brush whose opacity is `0.45` to opacity `0`. On an unknown binary it fails closed rather than hooking a guessed address.

The old process-wide XAML/SolidColorBrush hook is not packaged. The general LockApp styling module is not injected into LogonUI.

## Image framing / transition

The lock image is set only through `Windows.System.UserProfile.LockScreen.SetImageFileAsync(...)`. A-Shell does not create `LockScreenImage`, `NoChangingLockScreen`, `PersonalizationCSP\LockScreenImagePath`, or `PersonalizationCSP\LockScreenImageUrl` values.

While screen styling is enabled, A-Shell also sets Windows' supported **Prevent lock screen background motion** policy:

`HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization\AnimateLockScreenBackground = 1`

This selects the static lock/logon image path and prevents the transition from panning or zooming the photo. The original value is backed up and restored when A-Shell screen styling is turned off.

The unrelated legacy `LogonUI\AnimationDisabled=1` experiment remains removed. During upgrade, A-Shell restores the value captured before that experiment (or removes the A-Shell-created value when there was no prior value), because suppressing all authentication animations could leave the background in an intermediate scaled or black state.
