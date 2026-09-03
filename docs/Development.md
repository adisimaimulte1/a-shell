# Development

## Build and package

Use 64-bit Windows PowerShell and LLVM-MinGW (the Windhawk compiler is the default):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Build-SignIn-Backdrop.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Package.ps1 -Output C:\path\A-Shell.zip
```

Stop this copy of Matrix before rebuilding it. Build.ps1 compiles MatrixDesktop and DesktopLayout, embeds the Windows compatibility manifest, then adds icon/version resources. Branding uses assets/logo/A-Shell_Logo_Original.png and produces a seven-size A-Shell.ico. System hosts such as PowerShell retain their own Windows icons; A-Shell's own executables carry the project branding.

## Icon mapping

Add PNG files to assets/icons/ and entries to assets/icon-map.json:

```json
{"name":"My application","icon":"my-application.png","appIds":["Vendor.ExactAppID"]}
```

Use `ashell icons list` for Start-menu IDs. For classic applications whose runtime ID differs, inspect Taskbar.TaskListButton AutomationProperties.AutomationId with Windhawk UWPSpy and copy the value after `Appid: `. Do not infer identity from executable/display names. The existing Android Studio and Godot entries are path/version-specific. Multiple exact IDs may share an image; duplicate IDs and wildcards are rejected.

Run `ashell icons check`, then `ashell icons`. No rebuild is required for user PNG/map edits. Full-mode Windows 11 taskbar styling is required. The command hashes referenced images, preserves existing rule slots even when entries are reordered, and writes only changed values. Content-addressed images under state/icons avoid stale XAML caches. Removed slots are reused; old cache images remain available for rollback. A pending marker retries an interrupted notification. No Explorer restart or global icon-cache deletion is used. taskbar-base.json holds the transparent theme; taskbar-settings.json is a legacy reference.

## Renderer

The Win32 child is attached behind desktop icons. Its proven GDI presentation path displays an opaque frame composed from the current wallpaper and premultiplied rain. This avoids the UpdateLayeredWindow/Explorer visibility regression. IDesktopWallpaper supplies each monitor's image, bounds and display mode; GDI+ decodes/render-caches it. Solid wallpapers use one background color instead of a full pixel cache. Images are decoded on change, not every frame. Windows can render image scaling/color management differently; mixed-DPI and multi-monitor displays need physical validation.

Glyph masks are cached. Only active/previously active pixels are faded and recomposited. Movement uses elapsed time and skips overdue rows instead of drawing a catch-up backlog. Very long gaps redistribute stream phases. The normal 50 ms timer does not request a high-resolution system timer. Secure desktop, sleep, disconnects and a covering full-screen window pause drawing; WTS lock/unlock alone requests a fresh stream. Explicit stop/start also starts a new process. Surface/window recreation preserves rain. Wallpaper changes are detected through settings messages and a two-second path/timestamp check.

The live accent preference is six ASCII hex digits in state/accent-color.txt, atomically replaced and reloaded through a registered window message. Existing trails recolor without restarting. A single-instance mutex prevents duplicate launchers. Logs record PID, frame gaps, attachments and resets and rotate at 256 KiB. CPU measurements exclude the compositor; see Verification.md.

API references: [IDesktopWallpaper](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-idesktopwallpaper), [desktop positioning](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifolderview-selectandpositionitems).

## State and recovery

Fresh setup captures its original baseline before mutations, including images, registry values, cursor/mod trees, existing mod files and startup tasks. Per-run checkpoints support rollback. Legacy first backups are preserved. Original image paths are reused only when bytes still match the saved copy; otherwise restore uses the copy. Windows may recompress a cached lock image when no original source was available.

Background changes validate PNG/JPEG/BMP first, keep immutable source copies, checkpoint each operation and preserve the accent. `background original` restores pre-setup wallpapers without undoing the rest of A-Shell. Setup, color, icon and background changes share a short-lived operation mutex.

Desktop positions use documented shell interfaces. A journal records intent before moving personal desktop entries and completion afterward. Restore never overwrites conflicts. Shared/virtual icons are hidden without moving public files. Desktop.ini remains in place. Linked roots, top-level junctions/cloud placeholders and a project inside Desktop/original_desktop are rejected before moving files. Cross-volume directory moves may fail safely; there is no unsafe copy/delete fallback. Reapply handles journaled original items, not newly created desktop files. Changed screen layouts can affect restored positions.

Keep state/ and Documents/original_desktop. Undo restores saved state, not factory defaults. Windhawk stays installed for unrelated mods. PATH undo removes only the entry A-Shell added. Optional account-photo backups are under ProgramData/A-Shell/AccountPictures and are managed separately.

## Tests

Isolated: Test-Matrix.ps1, Test-Background.ps1, Test-Enhancements.ps1, Test-IconRefresh.ps1. Test-MatrixPerformance.ps1 measures simulation only.

Live tests change real settings: Test-SetupLifecycle.ps1, Test-FirstSetup.ps1, Test-LiveCommands.ps1, Test-DesktopLive.ps1, Test-OptionalControls.ps1, Test-Colors.ps1, Test-TerminalCLI.ps1 and Test-MatrixRuntime.ps1. Use a test account when possible. DesktopLive uses unique temporary items and restores visibility; the setup tests intentionally leave A-Shell applied. Never run multiple live mutation tests concurrently. Backups, test logs and outputs are excluded from releases.

Do not change the sign-in patch's allowed DLL hash without investigating the new Windows binary. Full styling is version-gated; unverified builds use Core mode. A successful package check is not proof of visual behavior on every Windows version.
### Rain timing

The frame loop directly follows the supplied script.js: 50 ms interval, 5% fade, transparent cell clearing, random glyph selection, drawing, one-row increment and a fresh off-screen random restart check above 0.975. Random opening positions are preserved by explicit user request. Elapsed time does not alter advancement or rearrange streams. The native renderer retains cached masks and wallpaper composition; the original dark rectangles become transparent.
### Single-file installer

Build with Windows PowerShell 5.1: `scripts\Build-Installer.ps1 -Output C:\Releases\A-Shell-Setup.exe`. It rebuilds the package, embeds the ZIP and its SHA-256 into a branded .NET Framework console executable, and writes a checksum sidecar. No extra build tools beyond Windows' .NET Framework compiler are needed for this launcher.

The installer verifies the resource hash, each manifest file, duplicate paths and path containment before extracting to a new staging directory and moving it to the permanent location. It rejects existing destinations and linked parent directories. Failed extractions are retained for inspection; setup failures retain logs and provide retry/undo instructions. It does not merge upgrades or overwrite personal state. Full/Core application delegates to the existing Setup.ps1 and its backup/rollback logic.

`A-Shell-Setup.exe --verify-only` validates without installation. `--extract-only "C:\new-folder"` verifies and extracts without changing Windows settings. Normal launch shows an interactive menu and install summary. The executable is unsigned until a release publisher signs it.

### Recycled taskbar buttons

The bundled GPL Taskbar Styler includes an A-Shell AutomationId observer. Its existing repeater hooks alone did not handle every app-identity transition. The observer tears down and rematches the entire button subtree; the cleanup and uninitialize paths unregister it. Build with scripts/Build-Taskbar-Styler.ps1. Keep source and DLL together when publishing.

`ashell icons refresh` upgrades to the library selected by assets/windhawk/mod.json. For troubleshooting, scripts/Repair-TaskbarEngine.ps1 -Restore from an administrator terminal returns to the previous library selection (and restores the former source). This rollback reintroduces the older behavior and is not the normal fix.
