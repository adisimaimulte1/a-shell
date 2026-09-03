# Clear sign-in background

Windows can apply separate dimming/backdrop layers even when acrylic blur is disabled. A-Shell first uses named XAML visual-tree styling in LockApp.exe and LogonUI.exe to collapse known dimming overlays without changing Windows DLLs on disk. A legacy exact-build brush hook remains only as a fallback on the one Windows.UI.Logon.dll build where it was validated.

The lock/sign-in visual tree is handled by a narrowly configured fork of the Windows 11 Start Menu Styler, restricted to LockApp.exe and LogonUI.exe. Its A-Shell rules hide the known password/no-password dimmers, additional named dim/scrim/tint overlays, conservative 40–45% opacity Rectangle/Border overlays, and force common background-image elements to full opacity. v1.9 genuinely initializes in both LockApp.exe and LogonUI.exe and adds a native brush-level pass that clears near-black translucent background filters even when Windows stores the 40–45% dimming on the SolidColorBrush rather than the element Opacity property. The upstream XAML styling machinery restores original properties when the mod is disabled. This fork retains its GPL-3.0 license; full source is included under assets\windhawk, alongside LICENSE.txt. Upstream: https://github.com/ramensoftware/windhawk-mods/blob/main/mods/windows-11-start-menu-styler.wh.cpp .

- **Remove Sign-in Shading.cmd** installs/enables both screen fixes.
- **Restore Sign-in Shading.cmd** restores previous screen-mod settings and removes process inclusions added by the installer. Legacy backups disable both mods. Lock and unlock to refresh the views.
- **Setup.cmd** always applies the documented clear-logon policy and the Windows 11 LockApp/LogonUI visual-tree fix; it enables the private brush hook only as a legacy fallback on its verified binary.
- **Restore Previous Settings.cmd** includes that restore step.

This is a custom appearance modification, not a Microsoft-supported setting. Windhawk must be running. The visual-tree mod explicitly targets only LockApp.exe and LogonUI.exe; the legacy fallback targets only LogonUI.exe. The option allowing all critical system processes remains unchanged.

The private sign-in mod verifies the entire Windows.UI.Logon.dll SHA256 before installing its hook. It supports file version 10.0.26100.8972, SHA256 51b3aa2b50944111f039c0de035f9c8951a3fd7a65eda7380ad30ece5c2565bf. It refuses other versions instead of applying old addresses after an update. That refusal no longer disables the unrelated taskbar/icon or LockApp styling; unknown Windows 11 builds use the documented clear-logon policy plus the general LockApp/LogonUI visual-tree fix. Only the verified non-acrylic member, containing an opaque-black SolidColorBrush at 0.45 opacity, is altered. PIN entry and authentication functions are not hooked.

The COM brush-handling test covers clearing the correct brush, repeated calls, preserving different colors and opacities, null input, accepting the verified binary and rejecting a different binary. The screen mod records targeted overlay hits in Windhawk local storage for diagnostics. Because Windows builds can change XAML names, physical visual verification is still required after Windows updates.

Source: src\signin-clear-background.wh.cpp. Build: scripts\Build-SignIn-Backdrop.ps1. Installer backup/log: state\signin-backdrop-before.clixml and state\signin-backdrop.log. Restore retains source and package files.

If a future Windows update restores the darkening, the binary guard may have intentionally disabled the mod. Reinspect the new Windows component before updating the guard. Do not simply replace the hash.

## Sign-in picture preference

A-Shell does **not** write `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\<SID>\AnyoneRead\LockScreen\HideLogonBackgroundImage`. Despite the `AnyoneRead` name, current Windows 11 builds can deny writes to that broker-owned preference even to elevated administrators. A-Shell treats it as read-only diagnostics, uses the supported lock-screen image API, and keeps `DisableLogonBackgroundImage=0`. If Windows reports that the per-user **Show the lock screen background picture on the sign-in screen** switch is Off, setup finishes and tells the user to enable that switch in Settings rather than taking ownership of protected registry data.


## Local lock-screen policy handoff

A-Shell detects existing policies that can lock the **Personalize your lock screen** picker or pin another image. With explicit setup consent, it snapshots the exact original existence, type and value, temporarily releases only the active lock/sign-in personalization blockers while A-Shell is enabled, broadcasts the policy change, and restores those exact values on `ashell stop`/recovery. It does not delete the whole Personalization policy key.

Handled blockers include active `NoChangingLockScreen`, `NoLockScreen`, `NoLockScreenSlideshow`, forced `LockScreenImage`, existing Personalization CSP `LockScreenImagePath` / `LockScreenImageUrl` inputs, and an existing `DisableLogonBackgroundImage=1`. `LockScreenImageStatus` is treated as status/output and is never edited. If Windows reports Active Directory, Microsoft Entra, enterprise join or MDM enrollment, A-Shell clearly warns the user and still overrides only these personalization blockers **when the user explicitly consents**. It never removes enrollment, disables MDM services, or changes unrelated organization policy; management software can reapply a policy later.
