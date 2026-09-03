<div align="center">

<img src="assets/logo/A-Shell_Logo_Original_HQ.png" width="112" alt="A-Shell logo">

# A-SHELL
### A quieter Windows desktop. A little orange rain.

![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-D65A00?style=for-the-badge)
![Native](https://img.shields.io/badge/C++-Native-D65A00?style=for-the-badge)

A reversible Windows appearance setup with a standalone Matrix background.

</div>

---

## Setup

Download and run `A-Shell-Setup.exe`. The terminal installer offers **Complete experience** (recommended) or **Essentials only**, verifies every bundled file, places A-Shell in `%LOCALAPPDATA%\Programs\A-Shell`, and runs setup. Complete experience enables every supported feature for the detected Windows version; Essentials skips the Windhawk taskbar/LockApp visual mods. No manual ZIP extraction or folder placement is needed. Approve the Windows administrator prompt when setup asks, then reopen your terminal and run `ashell help`.

The installer can upgrade/repair an existing A-Shell installation in place. It replaces program files while preserving `state/`, `backup/`, the current `assets/icon-map.json`, and custom icon files, then reapplies setup against the preserved original recovery baseline. The ZIP remains available for portable/manual placement. Lively is not required. This preview installer is unsigned.

Setup saves your previous appearance, desktop icon visibility and icon layout, switches both Windows and apps to dark mode, and applies the supported features. **Desktop files are never moved on new installs.** A-Shell hides the Explorer desktop view instead, so local files, OneDrive Known Folder Move desktops and Files On-Demand items stay in their existing folders. Setup is installer-only: `Setup.cmd`, `Setup Essentials.cmd` and `Setup Core.cmd` now point users back to `A-Shell-Setup.exe` instead of re-running installation logic.

## Make it yours

Use $\color{#D65A00}{\textsf{one accent}}$ for Windows and the live rain:

```text
ashell color 00AAFF
ashell color default
```

Colors accept six RGB hex digits. `default` restores A-Shell orange, `D65A00`. Color changes preserve the running animation.

Use $\color{#D65A00}{\textsf{your own wallpaper}}$: one PNG, JPEG or BMP for desktop and lock screen; the sign-in screen reuses it when Windows' sign-in-picture switch is On:

```text
ashell bg "C:\Pictures\wallpaper.png"
ashell bg original
ashell bg default
```

`original` restores your saved pre-setup wallpapers; `default` uses A-Shell's near-black `#070706` (RGB 7, 7, 6). Windows may crop images to fit. Trails fade into your wallpaper rather than black.

### Rain and startup

| Command | Result |
| :--- | :--- |
| `ashell rain start` | Start or resume rain without clearing existing falling streams or trails. |
| `ashell rain stop` | Stop new streams; existing rain finishes falling and fades away. |
| `ashell rain status` | Show process, accent and startup details. |
| `ashell startup install` | Enable automatic sign-in startup. |
| `ashell startup remove` | Remove startup and stop the renderer. |

Task Manager calls it `A-Shell Matrix Rain` (`MatrixDesktop.exe`), with the project logo. Rain starts randomly at launch and after lock/unlock. Permission prompts, sleep and appearance changes preserve it. Stopping while the desktop is inaccessible closes it directly.

### Icons without editing JSON

Run $\color{#D65A00}{\textsf{automatic matching}}$ after installing more apps or adding icons:

```text
ashell icons
ashell icons list
```

Every run checks detected apps against the PNGs already in assets/icons. Matching compares exact names, aliases, publisher/product identities, generic trailing product words (such as Browser/Desktop/App) and safe AppID product tokens, while handling release years and version labels on either side. For example, Excel matches microsoft-excel, Illustrator 2024 matches adobe-illustrator, and Opera Browser / OperaStable matches the bundled Opera icon. Known conflicting publishers and ambiguous candidates are rejected rather than guessed. Exact names take priority over aliases; existing choices are preserved and ambiguous matches are left alone. Task Manager uses the bar-chart icon; Windows Terminal and Command Prompt use the terminal icon. PowerShell and ISE variants use the PowerShell icon, and 32/64-bit labels are recognized. Notepad++ stays distinct from Notepad. Only changed taskbar settings and image files are refreshed.

To choose your own, import a PNG from the terminal, then use the exact app name shown by `icons list`:

```text
ashell icons add "C:\Downloads\my-chrome.png"
ashell icons set "Google Chrome" "my-chrome.png"
ashell icons refresh
ashell icons check
```

`add` copies the original PNG into `assets/icons` without admin access. An optional filename renames the copy: `ashell icons add "C:\Downloads\icon.png" illustrator.png`. Existing different files are never overwritten. Run `ashell icons` afterward to auto-match a clearly named icon, or use `set` to choose the app yourself. `set` saves the assignment and applies it; `refresh` reapplies existing mappings; `check` validates files and reports pinned shortcuts whose executable no longer exists. If names repeat, use the listed AppID. Some classic apps have a different taskbar ID from their Start-menu ID; those may still need an explicit ID in `assets/icon-map.json`. [Mapping details](docs/Development.md#icon-mapping).

### Permissions and feedback

Commands use separate headings and colored progress, success and error labels. Color, rain, listing and validation run without admin access. An unchanged icon refresh needs no prompt. Changing protected taskbar settings, setup and other system settings can still require approval.

For $\color{#D65A00}{\textsf{one approval}}$ across several administrative changes, run `ashell admin`. It opens an elevated Command Prompt (CMD) in the A-Shell folder, with help ready. Approve once, use that window for your commands, then close it. Windows security settings are unchanged. Commands still use the bundled PowerShell scripts internally.

## Start, stop and component switches

After installation, normal use is intentionally lightweight:

```text
ashell start
ashell stop
ashell status
```

`start` activates the already-installed A-Shell runtime without rebuilding the package or replacing Windhawk DLLs. `stop` disables Matrix startup first, restores the saved pre-A-Shell appearance component-by-component, and **never rolls a failed stop back into the active A-Shell state**. Legacy `ashell restore` and `ashell undo` are compatibility aliases for `ashell stop`. Keep `state/`; it contains the original reversible baseline.

Individual runtime components can be saved independently:

```text
ashell screen on|off
ashell taskbar on|off
ashell icons on|off
```

Desktop files remain in their original Desktop/OneDrive location. While A-Shell is active the Explorer desktop surface is always icon-free; original icon visibility, layout and coordinates are captured before setup and restored by `ashell stop`. Older A-Shell v1 installations that already created `Documents/original_desktop` are still supported by legacy recovery logic.

Setup also saves your Windows accent and light/dark preferences before changing them. When lock-screen personalization policy blocks the picker or pins a different image, A-Shell asks for explicit consent in the Setup EXE to temporarily override only those lock/sign-in personalization values. The exact original values/types/existence are restored by `ashell stop`, although active management software can reapply policy while A-Shell is running. `bg original` changes the saved background choice without uninstalling A-Shell. `screen off` restores the pre-A-Shell lock/login picture and Windows effects while leaving the desktop background choice independent; `screen on` reapplies the A-Shell lock/login image and filter-removal rules. On Windows 11 Complete experience, A-Shell hides the Widgets entry visually through its Windhawk taskbar style instead of writing the UCPD-protected `TaskbarDa` preference. Essentials leaves the Windows Widgets preference untouched.

Installation, upgrade and repair are done only by `A-Shell-Setup.exe`. `ashell check` verifies the installed package, and `ashell help` lists commands. `Undo A-Shell.cmd` and `Restore Previous Settings.cmd` are compatibility launchers for `ashell stop`.

`Remove Sign-in Shading.cmd` / `Restore Sign-in Shading.cmd` control the screen fixes. `Use Original Profile PNG.cmd` / `Restore Profile Picture.cmd` separately control the optional account photo.

## Included and compatible

Matrix rain, shared desktop/lock backgrounds (and the same sign-in picture when Windows allows it), dark cursors and a reversible icon-free desktop that leaves Desktop/OneDrive files in place. On x64 Windows 11, normal setup also enables the $\color{#D65A00}{\textsf{transparent taskbar}}$, monochrome taskbar icons and named LockApp/LogonUI dimming-overlay removal through XAML visual-tree styling without tying those features to one LogonUI binary hash. Cursor activation includes a direct per-session fallback and a delayed sign-in repair task for Windows builds where `SPI_SETCURSORS` does not refresh the selected scheme.

The old private hook for one verified 45% LogonUI brush remains only as a legacy fallback on its validated `Windows.UI.Logon.dll 10.0.26100.8972` hash. Unknown/newer Windows 11 builds use version-tolerant XAML visual-tree styling for both LockApp and LogonUI, including known dim/scrim/tint surface names plus conservative Rectangle/Border selectors for the 40–45% opacity credential overlay. v1.9 keeps the process-gate fix and broadens raw-image cleanup so the visual-tree DLL actually initializes inside LogonUI.exe rather than only LockApp.exe, instead of guessing a byte offset. Setup downloads and verifies Windhawk `1.7.3` when missing.

Windows 10 22H2 x64 uses the compatibility profile for the common features and the documented clear-logon policy; the Windows 11 taskbar/LockApp mods are not installed there. ARM64 is not supported by the current native binaries. The original development machine was Windows 11 Home 25H2 build `26200.9168 x64`; additional Windows builds still require physical visual verification before claiming exhaustive coverage. [Tests and measurements](docs/Verification.md).

## Help improve the icon pack

Found or created a $\color{#D65A00}{\textsf{new monochrome icon}}$ for an app? Contributions are welcome for future official releases. Open an **Icon contribution** issue in this GitHub repository, or [message me on Instagram](https://www.instagram.com/adicontras353/).

Include the app name (from `ashell icons list`), the PNG or original link, its creator and license, and how you would like to be credited. A taskbar preview helps. Suggestions are reviewed before inclusion; please share icons that may be redistributed with the pack.

## Credits & license

- [Windhawk](https://github.com/ramensoftware/windhawk) — Michael Maltsev / Ramen Software; [styler mods](https://github.com/ramensoftware/windhawk-mods) by m417z.
- [Lively Wallpaper](https://github.com/rocksdanister/lively) — rocksdanister, the original wallpaper workflow.
- [Original Matrix](https://github.com/bad1dea/lively_matrix) — parambirs / khuong, the supplied generation reference.
- [Material Design Cursor V2 Dark HDPI](https://github.com/SullensCR/Windows-Material-Design-Cursor-V2-Dark-Hdpi-by-jepriCreations) — jepriCreations; repository by SullensCR.
- [Icons8](https://icons8.com/) — monochrome icons.

Code: [GPL-3.0](LICENSE). Icons and cursors retain their original terms. [Third-party notices](assets/THIRD-PARTY.md).

<div align="center">

Put together by [Adrian Contraș](https://github.com/adisimaimulte1).

</div>
Maintaining a release? See [Publishing on GitHub](docs/Publishing.md).


Windows stores the **Show the lock screen background picture on the sign-in screen** switch in a per-user `SystemProtectedUserData` location. Current Windows 11 builds can allow that value to be read while refusing writes from an elevated administrator. A-Shell therefore never takes ownership of that protected key and never launches a SYSTEM helper merely to change it. It sets the lock-screen picture with the supported `Windows.System.UserProfile.LockScreen` API and enables the normal logon-background policy; if the user's protected switch is explicitly Off, setup reports the exact Settings page to toggle once instead of rolling back the entire installation.


### Restore resilience

If Explorer still maps the taskbar-styler DLL after Windhawk is disabled, restore restarts Explorer once and retries before using the reboot-time fallback.

Before restoring older Windhawk files, A-Shell disables its own mods and asks Windhawk to unload them. It retries locked DLL replacements; if Windows still has an injected DLL mapped, the exact previous bytes are queued with `MoveFileEx(..., MOVEFILE_DELAY_UNTIL_REBOOT)` and restore continues instead of aborting. Other Windhawk mods are left installed.


### In-place upgrades

The single-file installer can replace an existing recognized A-Shell installation in `%LOCALAPPDATA%\Programs\A-Shell`. Updates replace code/program files only, preserve `state/`, `backup/`, mappings/custom icons and the current started/stopped state, and keep live Matrix rain running when its executable is unchanged. A non-A-Shell folder is never overwritten.


### Runtime shortcuts (v1.9)
`ashell screen on|off`, `ashell taskbar on|off`, `ashell icons on|off`, and `ashell bg ...` are the preferred short forms. A-Shell always hides the desktop icon surface while active. Screen `off` restores the pre-A-Shell lock/login image and Windows effects; screen `on` uses the saved A-Shell image and removes the targeted blur/dim/scrim/tint/content layers.


### Runtime command rules (1.9.3)

`ashell help` always shows the full command set. `start` and `stop` are idempotent: calling them in the state already requested is a no-op. Appearance, component, mapping-mutation and rain start/stop commands only change state while A-Shell is started; when it is stopped they return a `[SKIP]` message and save nothing. Running the Setup EXE over a recognized installation is a code-only update: program files are replaced while `state/`, `backup/`, icon mappings/custom icons and the current started/stopped runtime state are preserved.


### Administrator prompts (1.9.3)

Interactive Setup asks for administrator access immediately, before install/update choices are shown. Runtime commands only elevate when they actually need system-level access. Those commands open a visible **Administrator Command Prompt** and run the PowerShell worker inside it, so UAC work never disappears into a hidden PowerShell process while the original terminal appears frozen. If the current terminal is already elevated, no second prompt is shown.
