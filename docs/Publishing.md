# Publishing a release

Build releases on **x64 Windows** from the repository root with **64-bit Windows PowerShell 5.1**. `Build.ps1` expects the Windhawk LLVM-MinGW compiler at `C:\Program Files\Windhawk\Compiler\bin\clang++.exe` unless the script is changed to another compatible compiler.

```powershell
# Native A-Shell binaries
powershell -ExecutionPolicy Bypass -File .\scripts\Build.ps1

# Rebuild only when the corresponding Windhawk C++ payload/source changed
powershell -ExecutionPolicy Bypass -File .\scripts\Build-SignIn-Backdrop.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Taskbar-Styler.ps1

# Portable verified payload
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Package.ps1 -Output C:\Releases\A-Shell.zip

# Single-file installer. This rebuilds the package internally, embeds it,
# and writes A-Shell-Setup.exe.sha256 next to the executable.
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Installer.ps1 -Output C:\Releases\A-Shell-Setup.exe
```

`Build-Package.ps1` runs the full build by default, then regenerates `assets\package-manifest.json` before creating the ZIP. Use `-SkipBuild` only for diagnostics; do not publish a package made with stale generated binaries.

Before publishing, run the installer verification pass:

```powershell
C:\Releases\A-Shell-Setup.exe --verify-only
Get-FileHash C:\Releases\A-Shell-Setup.exe -Algorithm SHA256
```

Recommended GitHub release files:

- `A-Shell-Setup.exe`
- `A-Shell-Setup.exe.sha256`
- `A-Shell.zip` for portable/manual installation


`Build-Package.ps1` also validates/recreates generated Windhawk payload provenance. Because the lock/sign-in visual-tree source is compiled code, do not run Setup directly from an edited source checkout until `scripts\Build.ps1` has completed successfully.
