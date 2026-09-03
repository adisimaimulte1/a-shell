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

Download and run `A-Shell-Setup.exe`. The branded terminal installer lets you choose Full or Core, verifies its bundled files, places A-Shell in `%LOCALAPPDATA%\Programs\A-Shell`, and runs setup. No manual ZIP extraction or folder placement is needed. Approve the Windows administrator prompt when setup asks, then reopen your terminal and run `ashell help`.

The installer will not overwrite an existing installation or its backups. Existing users can reapply their current copy with `ashell setup`; this launcher does not perform in-place upgrades. The ZIP remains available for portable/manual placement. Lively is not required. This preview installer is unsigned.

Setup saves your previous appearance and desktop layout, switches both Windows and apps to dark mode, archives personal desktop contents in `Documents/original_desktop`, and applies the supported features. Shared and virtual desktop icons are hidden. `Setup Core.cmd` installs the common Windows features only.

## Make it yours

Use $\color{#D65A00}{\textsf{one accent}}$ for Windows and the live rain:

```text
ashell color 00AAFF
ashell color default
```

Colors accept six RGB hex digits. `default` restores A-Shell orange, `D65A00`. Color changes preserve the running animation.

Use $\color{#D65A00}{\textsf{your own wallpaper}}$: one PNG, JPEG or BMP for desktop, lock and sign-in:

```text
ashell background "C:\Pictures\wallpaper.png"
ashell background original
ashell background default
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

Every run checks detected apps against the PNGs already in assets/icons. Matching compares exact names, aliases and publisher/product identities, handling release years and version labels on either side. For example, Excel matches microsoft-excel, and Illustrator 2024 matches adobe-illustrator. Known conflicting publishers and ambiguous candidates are rejected rather than guessed. Exact names take priority over aliases; existing choices are preserved and ambiguous matches are left alone. Task Manager uses the bar-chart icon; Windows Terminal and Command Prompt use the terminal icon. PowerShell and ISE variants use the PowerShell icon, and 32/64-bit labels are recognized. Notepad++ stays distinct from Notepad. Only changed taskbar settings and image files are refreshed.

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

## Undo and maintenance

$\color{#D65A00}{\textsf{Restore your saved setup}}$, rather than factory defaults:

```text
ashell restore
```

Keep `state/` and `Documents/original_desktop`. Reapplying setup preserves the first backup. File collisions are reported without overwriting either version; resolve them and retry. Desktop icon coordinates, visibility and arrangement preferences are saved before setup; restore verifies the positions and retries while Explorer loads the returned files. Missing items or a changed monitor layout can prevent an exact match. Saved taskbar alignment is restored too; A-Shell does not rearrange your pinned apps. Windhawk remains installed for other mods.

Setup also saves your Windows accent and light/dark preferences before changing them. Full restore stops generating new rain, waits for the existing drops and trails to finish naturally, then restores wallpapers and colors. The rain keeps its current color throughout the fade. `background original` only restores wallpapers and keeps the rain running. If Windows protects its optional Widgets toggle, A-Shell leaves that toggle unchanged and reports a warning while completing the other changes.

`ashell setup [core]` reapplies appearance, `ashell check` verifies the package, and `ashell help` lists commands. `Undo A-Shell.cmd` and `Restore Previous Settings.cmd` also undo setup.

`Remove Sign-in Shading.cmd` / `Restore Sign-in Shading.cmd` control the screen fixes. `Use Original Profile PNG.cmd` / `Restore Profile Picture.cmd` separately control the optional account photo. Legacy command aliases and restore launchers remain available.

## Included and compatible

Matrix rain, shared backgrounds/accent, dark cursors and desktop archiving. Full mode adds the $\color{#D65A00}{\textsf{transparent taskbar}}$, monochrome taskbar icons and clear lock/sign-in screens.

Tested on Windows 11 Home 25H2, build `26200.9168 x64`. Full screen fixes require verified `Windows.UI.Logon.dll 10.0.26100.8972`. Setup downloads and verifies Windhawk `1.7.3` when missing.

Core mode targets Windows 10 22H2 and unverified Windows 11 builds, x64. Real Windows 10, ARM64, multiple/mixed-DPI monitors and clean-machine installation remain unverified. [Tests and measurements](docs/Verification.md).

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
