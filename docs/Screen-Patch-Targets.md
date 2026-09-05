# Screen patch targets

Windows.UI.Logon.dll SHA-256:
`51B3AA2B50944111F039C0DE035F9C8951A3FD7A65EDA7380AD30ECE5C2565BF`

Microsoft public symbols: Windows.UI.Logon.pdb,
`A9C4EE12C6265928F84582038A5BF6F41`.

* RVA 0x64970 is RequestCredentialEntryViewModel.ShouldPanLockLogonImage.get.
  Return **false**. It is not the IsZoomDisabled getter. Returning true enables
  the oversized surface used for background panning, even when the static-image
  policy is enabled.
* RVA 0xbb260 is the native RequestCredentialEntryViewModel.IsZoomDisabled getter
  used by the layout routine through its vtable. Its ABI wrapper at 0x10f850 is
  bypassed by that path. Set the property through the verified native setter at
  0xb75d0 before reading it; both access the boolean at member offset 0x158.
* RVA 0x94140 is the existing narrow background-brush getter. Continue clearing
  only its verified non-acrylic black brush at member offset 0x170.

The exact file hash and all entry-point byte signatures must match before hooks
are installed. Test-SignInHookTargets.ps1 exercises the actual native brush
operation and these guards against the local file without opening authentication.

Hook telemetry confirms a code path ran; it does not prove visible framing.
Validate the clock screen, sign-in screen, and return to the desktop manually.

LockApp visual-tree Add events may precede layout. The background cleanup revisits
the laid-out tree on its UI dispatcher and includes element opacity in the
effective alpha calculation. BackgroundTree diagnostics contain structural names,
dimensions, and brush values only, never user text or credential contents.
The composition scan also checks full-screen dark translucent color layers.
BackgroundTreeHistory0 through BackgroundTreeHistory7 retain structural changes
across unlocking so a collapsed post-unlock tree cannot erase all earlier samples.

The clock page paints an opaque ImageBrush from LockScreen.GetImageStream on
LockRootGrid and the outer Frame, using UniformToFill without tint or effects. The
Frame retains the image while MainPage leaves during the transition. This covers the shared
system background underneath the clock page, whose dimming is outside the XAML
dimmers. The original image URI is checked for changes; the previous panel brush
is restored when unloading. Errors leave Windows' background available.

Known LockApp background/backplate brush resources are cleared in place. Panel,
control and content-presenter borders are removed independently of backgrounds;
text, icon strokes and media artwork are preserved. These changes run only in
LockApp. The LogonUI brush guard clears color alpha as well as opacity, so the handoff
storyboard cannot make the verified black dimmer visible again.

Visual-state paint is cleared on CompositionTarget.Rendering before XAML frames,
with the rendering subscription revoked on teardown. The timer retains resource
discovery and diagnostics. Widget ContentPresenter backgrounds (including media
button hover/pressed plates) are included; ImageBrush artwork is preserved. Dark
translucent background cleanup includes alpha below 12%, covering faint fades.

The supplied 2026-09-05 video shows a brief brightness pulse around 1.1 seconds.
The native regression simulates opacity returning after clearing the brush.
End-to-end clock/sign-in and Spotify hover still need visual verification after
installing this build on the interactive lock screen.

1.9.17 uses the packaged 1.9.14 LockApp cleanup rules and frame wallpaper.
When the native media overlay is actually visible, LockRootGrid also receives
the image, reconstructing the 1.9.13 media appearance. Hiding media restores
that panel's previous brush. Teardown retains the frame image after style
cleanup to preserve the fixed handoff. Live visual verification is required.

Rain no longer detects or pauses for fullscreen/foreground windows. It retains
lock, disconnect and suspend handling. Accent/fade and solid wallpaper tables
are cached, transparent glyph pixels use cached ink, and redundant restoration
of surviving pixels is removed. A 1920x1080, 1200-frame update/composition
benchmark took 4670.81 ms before and 3597.55 ms after (about 23% less time),
with matching sampled full-frame hashes and RNG state. This is a local
microbenchmark, not a measurement of whole-app CPU or battery life.
