<div align="center">

<img src="assets/logo/A-Shell_Logo_Original_HQ.png" width="116" alt="A-Shell logo">

![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-D65A00?style=for-the-badge\&logo=windows\&logoColor=white)
![Native](https://img.shields.io/badge/C%2B%2B-Native-D65A00?style=for-the-badge\&logo=cplusplus\&logoColor=white)
![Reversible](https://img.shields.io/badge/Reversible-Yes-D65A00?style=for-the-badge)

# A-SHELL

### A quieter Windows desktop. A little orange rain.

**Minimal desktop · Matrix rain · monochrome UI · reversible Windows styling**

</div>

---

## What A-Shell does

A-Shell turns Windows into a $\color{#D65A00}{\textsf{cleaner, darker workspace}}$ while keeping your original setup recoverable.

|                                              |                                                                                       |
| -------------------------------------------- | ------------------------------------------------------------------------------------- |
| $\color{#D65A00}{\textsf{Empty desktop}}$    | Hides desktop icons without moving your files.                                        |
| $\color{#D65A00}{\textsf{Matrix rain}}$      | Native animated rain runs over your wallpaper.                                        |
| $\color{#D65A00}{\textsf{Shared accent}}$    | Windows styling and rain use the same color.                                          |
| $\color{#D65A00}{\textsf{Monochrome icons}}$ | Automatically matches supported apps to the icon pack.                                |
| $\color{#D65A00}{\textsf{Windows styling}}$  | Transparent taskbar, dark cursors and cleaner lock / sign-in visuals where supported. |
| $\color{#D65A00}{\textsf{Reversible}}$       | `ashell stop` restores your saved Windows appearance.                                 |

Your Desktop and OneDrive files are $\color{#D65A00}{\textsf{never moved}}$ as part of the normal A-Shell workflow.

---

## Install

Download and run:

```text
A-Shell-Setup.exe
```

The installer verifies the package, saves your current Windows appearance and installs A-Shell to:

```text
%LOCALAPPDATA%\Programs\A-Shell
```

Choose $\color{#D65A00}{\textsf{Complete experience}}$ for all supported features or **Essentials only** to skip the Windhawk taskbar and LockApp modifications.

After installation:

```text
ashell help
```

### Updating

Run the new Setup EXE normally.

Updates replace program files while preserving $\color{#D65A00}{\textsf{state, backups, icon mappings, custom icons}}$ and your current started / stopped state.

---

## Commands

### Main

| Command            | What it does                           |
| ------------------ | -------------------------------------- |
| `ashell start`     | Start A-Shell.                         |
| `ashell stop`      | Restore your saved Windows appearance. |
| `ashell status`    | Show the current state.                |
| `ashell help`      | Show all commands.                     |
| `ashell version`   | Show the installed version.            |
| `ashell uninstall` | Restore Windows and remove A-Shell.    |

`start` and `stop` are $\color{#D65A00}{\textsf{idempotent}}$ — calling them when already in that state changes nothing.

### Appearance

| Command                 | What it does                           |
| ----------------------- | -------------------------------------- |
| `ashell screen on/off`  | Toggle A-Shell lock + sign-in styling. |
| `ashell taskbar on/off` | Toggle taskbar styling.                |
| `ashell icons on/off`   | Toggle monochrome app icons.           |
| `ashell color D65A00`   | Change the shared accent color.        |
| `ashell color default`  | Restore A-Shell orange.                |

Appearance commands only modify settings while A-Shell is running. Otherwise they return $\color{#D65A00}{\textsf{[SKIP]}}$ and change nothing.

---

## Make it yours

Use any six-digit RGB color:

```text
ashell color 00AAFF
```

Return to the default $\color{#D65A00}{\textsf{A-Shell orange}}$:

```text
ashell color default
```

The selected accent is shared between Windows styling and Matrix rain.

Use your own wallpaper:

```text
ashell bg "C:\Pictures\wallpaper.png"
```

Or switch between:

```text
ashell bg default
ashell bg original
```

A-Shell supports $\color{#D65A00}{\textsf{PNG, JPEG and BMP}}$. When screen styling is enabled, the desktop, lock screen and sign-in screen share the selected background where Windows allows it.

---

## Matrix rain

```text
ashell rain start
ashell rain stop
ashell rain status
```

Rain starts without clearing existing trails, while stopping it lets the remaining streams $\color{#D65A00}{\textsf{fade naturally}}$.

Automatic startup can be controlled with:

```text
ashell startup install
ashell startup remove
```

In Task Manager, the renderer appears as `A-Shell Matrix Rain`.

---

## Monochrome icons

Automatically match installed apps:

```text
ashell icons
```

See detected apps:

```text
ashell icons list
```

A-Shell understands names, aliases, publishers, version labels and AppIDs. $\color{#D65A00}{\textsf{Clear matches are applied automatically; ambiguous ones are left alone.}}$

Add your own icon:

```text
ashell icons add "C:\Downloads\icon.png"
ashell icons set "Google Chrome" "icon.png"
```

Then use:

```text
ashell icons refresh
ashell icons check
```

See [icon mapping](docs/Development.md#icon-mapping) for the detailed matching rules.

---

## Admin access

Most everyday commands run without elevation.

Protected Windows changes request administrator access $\color{#D65A00}{\textsf{only when required}}$.

For several protected commands under one approval:

```text
ashell admin
```

This opens an elevated Command Prompt directly in the A-Shell directory.

---

## Restore & uninstall

Restore your original Windows appearance:

```text
ashell stop
```

This keeps A-Shell installed while restoring the saved pre-A-Shell state.

Remove everything:

```text
ashell uninstall
```

A-Shell restores Windows first, then removes its startup entries and program files.

The original recovery baseline stays in $\color{#D65A00}{\textsf{state/}}$ while A-Shell is installed.

---

## Compatibility

| Platform                                        | Support                                          |
| ----------------------------------------------- | ------------------------------------------------ |
| $\color{#D65A00}{\textsf{Windows 11 x64}}$      | Full supported experience.                       |
| $\color{#D65A00}{\textsf{Windows 10 22H2 x64}}$ | Core features; Windows 11-only mods are skipped. |
| $\color{#D65A00}{\textsf{ARM64}}$               | Not currently supported.                         |

A-Shell prefers $\color{#D65A00}{\textsf{version-tolerant XAML / Windhawk styling}}$ instead of unsafe hooks on unknown Windows binaries.

The main development environment is Windows 11 Home 25H2 x64. See [tests and measurements](docs/Verification.md) for more detail.

---

## Build the installer

From **64-bit Windows PowerShell 5.1**:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Installer.ps1
```

The script verifies the package, builds the native components and creates the $\color{#D65A00}{\textsf{versioned Setup EXE}}$.

---

## Credits

* [Windhawk](https://github.com/ramensoftware/windhawk) — Michael Maltsev / Ramen Software
* [Original Matrix](https://github.com/bad1dea/lively_matrix) — original rain reference
* [Material Design Cursor V2 Dark HDPI](https://github.com/SullensCR/Windows-Material-Design-Cursor-V2-Dark-Hdpi-by-jepriCreations)
* [Icons8](https://icons8.com/) — monochrome icon assets

Code is released under the [GPL-3.0 License](LICENSE). Third-party assets retain their original licenses.

---

<div align="center">

Built with $\color{#D65A00}{\textsf{a little orange rain}}$ by [Adrian Contraș](https://github.com/adisimaimulte1).

</div>
