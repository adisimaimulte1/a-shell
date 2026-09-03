# Clear sign-in background

Windows applies a separate 45% black backdrop even when acrylic blur is disabled. A-Shell includes a small Windhawk mod that changes only that backdrop brush to zero opacity. Your wallpaper, profile picture and Windows DLL on disk are unchanged.

The clock lock screen is handled separately by a narrowly configured fork of the Windows 11 Start Menu Styler, targeting only LockApp.exe. Its only styling rules hide DimmingOverlayPassword and DimmingOverlayNoPassword. The upstream XAML styling machinery restores original properties when the mod is disabled. This fork retains its GPL-3.0 license; full source is included under assets\windhawk, alongside LICENSE.txt. Upstream: https://github.com/ramensoftware/windhawk-mods/blob/main/mods/windows-11-start-menu-styler.wh.cpp .

- **Remove Sign-in Shading.cmd** installs/enables both screen fixes.
- **Restore Sign-in Shading.cmd** restores previous screen-mod settings and removes process inclusions added by the installer. Legacy backups disable both mods. Lock and unlock to refresh the views.
- **Setup.cmd** includes this step on the supported Windows binary.
- **Restore Previous Settings.cmd** includes that restore step.

This is a custom appearance modification, not a Microsoft-supported setting. Windhawk must be running. The two mods explicitly target LogonUI.exe and LockApp.exe respectively; the option allowing all critical system processes remains unchanged.

The mod verifies the entire Windows.UI.Logon.dll SHA256 before installing its hook. It supports file version 10.0.26100.8972, SHA256 51b3aa2b50944111f039c0de035f9c8951a3fd7a65eda7380ad30ece5c2565bf. It refuses other versions instead of applying old addresses after an update. Only the verified non-acrylic member, containing an opaque-black SolidColorBrush at 0.45 opacity, is altered. PIN entry and authentication functions are not hooked.

The COM brush-handling test covers clearing the correct brush, repeated calls, preserving different colors and opacities, null input, accepting the verified binary and rejecting a different binary. Both the clock lock screen and sign-in screen were confirmed visually on the development machine; mod telemetry also confirmed the targeted overlays were found.

Source: src\signin-clear-background.wh.cpp. Build: scripts\Build-SignIn-Backdrop.ps1. Installer backup/log: state\signin-backdrop-before.clixml and state\signin-backdrop.log. Restore retains source and package files.

If a future Windows update restores the darkening, the binary guard may have intentionally disabled the mod. Reinspect the new Windows component before updating the guard. Do not simply replace the hash.
