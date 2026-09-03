# Third-party notices

A-Shell code and original modifications: Copyright (C) 2026 Adrian Contraș, GPL-3.0. See ../LICENSE. Separately licensed artwork is excluded from that code license.

## Windhawk and mods

Windhawk by Michael Maltsev / Ramen Software: https://github.com/ramensoftware/windhawk — GPL-3.0. Setup retrieves official version 1.7.3; URL and published SHA256 are pinned in dependencies.json. Windhawk itself is not bundled. Its installer downloads its components. Corresponding source: https://github.com/ramensoftware/windhawk/tree/v1.7.3 .

Windows 11 Taskbar Styler 1.9 by m417z: https://github.com/ramensoftware/windhawk-mods . Full working source and binary are under windhawk/, with GPL-3.0 in windhawk/LICENSE.txt. A-Shell supplies configuration and Icons8 mappings.

A-Shell clear lock-screen background is a modified Windows 11 Start Menu Styler 1.7 by m417z: https://github.com/ramensoftware/windhawk-mods/blob/main/mods/windows-11-start-menu-styler.wh.cpp . Modified 2026-09-02 for LockApp-only targeting, removal of irrelevant Start-menu statistics, and dimming-element status reporting. Full source: windhawk/ashell-lockscreen-clear-background.wh.cpp. GPL-3.0.

The original sign-in brush mod is under ../src/signin-clear-background.wh.cpp. Windows binaries and Microsoft debugging symbols are not distributed or modified on disk.

## Lively Wallpaper

Lively Wallpaper by rocksdanister: https://github.com/rocksdanister/lively — GPL-3.0. Credited for the original wallpaper workflow; Lively is neither installed nor bundled. A-Shell’s renderer runs independently.

## Cursor artwork

Material Design Pure Dark v2 / Windows Material Design Cursor V2 Dark HDPI by jepriCreations: https://www.deviantart.com/jepricreations/art/Windows-Material-Design-Cursor-V2-Dark-Hdpi-911776406 . Supplied repository by SullensCR: https://github.com/SullensCR/Windows-Material-Design-Cursor-V2-Dark-Hdpi-by-jepriCreations .

Original terms are preserved in cursors/Original-Agreement.txt, alongside the original Install.inf for provenance. Setup uses explicit mappings rather than executing that INF. This artwork is not open source or covered by A-Shell’s GPL. The maintainer confirmed permission to bundle it; this does not grant recipients unrestricted redistribution rights. The original agreement also credits https://www.deviantart.com/rosea92 ; that link is retained without asserting a verified relationship between the creator accounts.

## Icons8 artwork

Icons by Icons8: https://icons8.com/ . The PNGs retain Icons8’s terms and trademarks; they are not GPL assets or an independently licensed icon pack. Keep visible attribution. Terms: https://icons8.com/license and https://intercom.help/icons8-7fb7577e8170/en/articles/5534926-universal-multimedia-license-agreement-for-icons8 . Public redistribution of downloadable assets/customization skins requires the applicable permission; attribution does not replace it.

## Original artwork and toolchain

LockScreenPicture.png is the selected solid RGB (7,7,6) background; profile/personal-icon.png is maintainer-supplied arrow artwork. Account-photo installation is optional and outside the main setup.

Native builds use LLVM-MinGW. Compiler/runtime notices are retained in ../licenses/. Build commands and upstream source notices are included.
A-Shell modifies the bundled Windows 11 Taskbar Styler by m417z to re-evaluate icon rules when recycled taskbar buttons change AutomationId. The modified source is included in assets/windhawk/windows-11-taskbar-styler.wh.cpp and remains GPL-3.0.
