# Verification

A-Shell combines supported Windows APIs/settings with a small number of explicitly version-sensitive visual hooks. Package verification proves file integrity and script syntax; live visual behavior must still be tested on Windows hardware before a release is labeled for that build.

## Release checks

Run from **64-bit Windows PowerShell 5.1** after rebuilding the native binaries:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Package.ps1 -Output C:\Releases\A-Shell.zip
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Installer.ps1 -Output C:\Releases\A-Shell-Setup.exe
C:\Releases\A-Shell-Setup.exe --verify-only
```

Then run the isolated tests and the live tests listed in `docs/Development.md` on a disposable/test account.

## Desktop / OneDrive regression

`tests\Test-DesktopLive.ps1` is the regression test for the desktop behavior introduced after the OneDrive/Known Folder Move failure. It verifies that:

- Explorer enters `FWF_NOICONS` mode and the persistent `HideIcons` preference is set.
- Test files and folders remain at the same Desktop known-folder path while hidden.
- Nested file contents are unchanged.
- Exact icon coordinates can be restored.
- The account's previous desktop visibility/layout is restored during cleanup.

Run this test at least once with **OneDrive Desktop backup / Known Folder Move enabled**. New A-Shell installs must not create `Documents\original_desktop`, move cloud placeholders, or require OneDrive files to be hydrated. The legacy archive functions remain only to undo older A-Shell v1 installations that already moved files.


## Protected sign-in preference regression

`tests\Test-OptionalWidget.ps1` now also guards the Windows 11 failure where `SystemProtectedUserData\<SID>\AnyoneRead\LockScreen\HideLogonBackgroundImage` can be readable but not writable by an elevated administrator. A-Shell must never attempt to take ownership of or write that path. The per-user switch is diagnostic only. If it is Off, setup reports **Settings > Personalization > Lock screen > Show the lock screen background picture on the sign-in screen** and continues.

The same test injects access-denied errors for optional Windows shell controls and confirms they do not roll back unrelated A-Shell features, while installer-owned Windhawk settings still fail closed. On Windows 11 build 26200, verify a Complete install with the protected sign-in preference both On and Off.

## Lock-screen policy handoff regression

`tests\Test-LockScreenPolicyHandoff.ps1` covers the registry-policy layer that can make **Personalize your lock screen** and **Browse photos** appear disabled with the Windows message that settings are managed. On a personal/unmanaged test PC, verify with `NoChangingLockScreen=1` and/or a temporary forced `LockScreenImage` present before setup:

- setup discovers the blocker before creating the run checkpoint;
- only the existing blocking value is temporarily released;
- the A-Shell lock image becomes active and the picture picker is usable again after reopening Settings;
- `LockScreenImageStatus` is never edited;
- rollback and Undo recreate the exact original value, registry type and existence state;
- Active Directory joined, Microsoft Entra device joined and MDM-enrolled devices report the blocker but do not override it.


## Windows matrix

Minimum release coverage for x64 builds:

- Windows 11: Complete experience, Essentials only, reapply, restore, lock/unlock, sign-out/sign-in and restart.
- Windows 11 + OneDrive Desktop backup: same, plus `Test-DesktopLive.ps1`.
- Windows 10 22H2: compatibility feature profile and restore.
