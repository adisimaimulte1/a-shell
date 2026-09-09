# Sign-in background compatibility

The sign-in hook now resolves LogonBackgroundBrush, ShouldPanLockLogonImage and
IsZoomDisabled from Microsoft's PDB matching the installed Windows.UI.Logon.dll.
Windhawk caches the resolution per module version. There are no hard-coded
Windows hashes, RVAs or private member offsets in the runtime hook.

The background hook validates the returned COM brush and black color. Zoom
symbols are optional: their absence does not disable background cleanup.
If Microsoft symbols are unavailable or the background property changes, the
hook reports CompatibilityError in Windhawk LocalStorage, surfaced by the
screen status check, and leaves unsupported internals untouched.

Windows 25H2 build 26200.9445 changed the DLL hash to
A11BDE742BEAFB2964788F947FF2A475193CD3925A3D30990FDA1C420ABDCBDE.
Matching Microsoft PDB identity: 44A3092DE941F8C9B8DAC7D7E64F261A, age 1.
All four expected native property symbols were found in that PDB.

The old version-pinned hook rejected this update and left HookInstalled=0.
Routine updates that preserve these property symbols can now resolve without
an A-Shell rebuild. First resolution needs symbols from Microsoft's server;
cached resolutions work offline. A future Windows redesign can still require
an A-Shell compatibility update; no indefinite guarantee is possible.
