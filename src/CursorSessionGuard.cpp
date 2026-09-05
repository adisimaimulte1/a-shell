#define _WIN32_WINNT 0x0A00
#define WINVER 0x0A00
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>
#include <cstdint>
#include <cwchar>

struct CursorRole {
    const wchar_t* file;
    DWORD id;
};

static const CursorRole kRoles[] = {
    {L"pointer.cur", 32512},      // Arrow
    {L"beam.cur", 32513},         // IBeam
    {L"busy.ani", 32514},         // Wait
    {L"precision.cur", 32515},    // Crosshair
    {L"alternate.cur", 32516},    // UpArrow
    {L"handwriting.cur", 32631},  // NWPen (optional on newer Windows)
    {L"dgn1.cur", 32642},         // SizeNWSE
    {L"dgn2.cur", 32643},         // SizeNESW
    {L"horz.cur", 32644},         // SizeWE
    {L"vert.cur", 32645},         // SizeNS
    {L"move.cur", 32646},         // SizeAll
    {L"unavailable.cur", 32648},  // No
    {L"link.cur", 32649},         // Hand
    {L"working.ani", 32650},      // AppStarting
    {L"help.cur", 32651},         // Help
    {L"pin.cur", 32671},          // Pin (optional)
    {L"person.cur", 32672},       // Person (optional)
};

static std::wstring AShellRootPath() {
    wchar_t path[32768]{};
    DWORD count = GetModuleFileNameW(nullptr, path, static_cast<DWORD>(_countof(path)));
    if (!count || count >= _countof(path)) return L"";
    std::wstring value(path, count);
    auto binSlash = value.find_last_of(L"\\/");
    if (binSlash == std::wstring::npos) return L"";
    value.resize(binSlash); // ...\\A-Shell\\bin
    auto rootSlash = value.find_last_of(L"\\/");
    if (rootSlash == std::wstring::npos) return L"";
    value.resize(rootSlash); // ...\\A-Shell
    return value;
}

static bool FileExists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

static std::string ReadSmallFile(const std::wstring& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || size.QuadPart > 1024 * 1024) {
        CloseHandle(file);
        return {};
    }
    std::string bytes(static_cast<size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    if (!bytes.empty() &&
        !ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr)) {
        CloseHandle(file);
        return {};
    }
    CloseHandle(file);
    bytes.resize(read);
    return bytes;
}

static bool ReadJsonBool(const std::string& json, const char* key, bool fallback) {
    std::string token = "\"" + std::string(key) + "\"";
    auto pos = json.find(token);
    if (pos == std::string::npos) return fallback;
    pos = json.find(':', pos + token.size());
    if (pos == std::string::npos) return fallback;
    ++pos;
    while (pos < json.size() &&
           (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\r' || json[pos] == '\n')) {
        ++pos;
    }
    if (json.compare(pos, 4, "true") == 0) return true;
    if (json.compare(pos, 5, "false") == 0) return false;
    return fallback;
}

static bool AShellIsActive(const std::wstring& root) {
    const auto runtime = root + L"\\state\\runtime-state.json";
    if (FileExists(runtime)) return ReadJsonBool(ReadSmallFile(runtime), "active", false);
    return FileExists(root + L"\\state\\applied.txt"); // legacy installs
}

static std::wstring CursorFolder() {
    const wchar_t* programData = _wgetenv(L"ProgramData");
    if (!programData || !*programData) return L"";
    return std::wstring(programData) + L"\\A-Shell\\Cursors\\MaterialPureDarkV2";
}

static bool ApplyAllCursors() {
    const auto folder = CursorFolder();
    if (folder.empty()) return false;

    // The guard's detector is the normal-select arrow only. Apply every role as
    // best effort, but report success based on the arrow itself. A single exotic
    // optional/animated role rejected by a Windows build must not put the guard
    // into a permanent 500 ms full-scheme retry loop (another source of flicker).
    bool arrowOkay = false;
    for (size_t i = 0; i < _countof(kRoles); ++i) {
        const auto path = folder + L"\\" + kRoles[i].file;
        if (!FileExists(path)) continue;
        HCURSOR cursor = LoadCursorFromFileW(path.c_str());
        if (!cursor) continue;

        // SetSystemCursor copies the cursor and destroys the supplied handle on
        // success. Only destroy it ourselves when the call fails.
        if (!SetSystemCursor(cursor, kRoles[i].id)) {
            DestroyCursor(cursor);
        } else if (kRoles[i].id == 32512) {
            arrowOkay = true;
        }
    }
    return arrowOkay;
}

static uint64_t HashBytes(uint64_t hash, const void* data, size_t length) {
    const auto* bytes = static_cast<const unsigned char*>(data);
    for (size_t i = 0; i < length; ++i) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static uint64_t HashBitmap(uint64_t hash, HBITMAP bitmap) {
    if (!bitmap) return HashBytes(hash, "none", 4);
    BITMAP info{};
    if (!GetObjectW(bitmap, sizeof(info), &info)) return HashBytes(hash, "bad", 3);
    hash = HashBytes(hash, &info.bmWidth, sizeof(info.bmWidth));
    hash = HashBytes(hash, &info.bmHeight, sizeof(info.bmHeight));
    hash = HashBytes(hash, &info.bmBitsPixel, sizeof(info.bmBitsPixel));
    const size_t byteCount = static_cast<size_t>(info.bmWidthBytes) *
                             static_cast<size_t>(info.bmHeight < 0 ? -info.bmHeight : info.bmHeight);
    if (!byteCount || byteCount > 16 * 1024 * 1024) return hash;
    std::vector<unsigned char> bytes(byteCount);
    LONG got = GetBitmapBits(bitmap, static_cast<LONG>(byteCount), bytes.data());
    if (got > 0) hash = HashBytes(hash, bytes.data(), static_cast<size_t>(got));
    return hash;
}

static uint64_t FingerprintSystemCursor(DWORD id) {
    HCURSOR cursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(id));
    if (!cursor) return 0;
    ICONINFO info{};
    if (!GetIconInfo(cursor, &info)) return 0;
    uint64_t hash = 1469598103934665603ULL;
    hash = HashBytes(hash, &info.xHotspot, sizeof(info.xHotspot));
    hash = HashBytes(hash, &info.yHotspot, sizeof(info.yHotspot));
    hash = HashBitmap(hash, info.hbmMask);
    hash = HashBitmap(hash, info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    if (info.hbmColor) DeleteObject(info.hbmColor);
    return hash;
}

static uint64_t FingerprintArrowCursor() {
    // Only fingerprint the static normal-select cursor. Animated Wait/AppStarting
    // cursors can expose different frames through GetIconInfo, which made the old
    // guard mistake animation for a Windows reset and continuously re-apply the
    // entire scheme (the visible hard flicker reported at logon).
    return FingerprintSystemCursor(32512);
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR args, int) {
    const auto root = AShellRootPath();
    if (root.empty() || !AShellIsActive(root)) return 0;

    HANDLE mutex = CreateMutexW(nullptr, TRUE, L"Local\\A-Shell-CursorSessionGuard-v2");
    if (!mutex) return 1;
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(mutex);
        return 0;
    }

    // KB5120998-era Windows 11 builds can leave the custom scheme correctly
    // stored in HKCU yet still load the stock live cursor table at sign-in.
    // SetSystemCursor remains effective, so establish the exact A-Shell table
    // before Explorer/startup apps get a chance to paint their first desktop UI.
    bool applied = ApplyAllCursors();
    uint64_t expectedArrow = applied ? FingerprintArrowCursor() : 0;

    if (args && wcsstr(args, L"--once")) {
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        return applied ? 0 : 2;
    }

    // Keep one tiny windowless guard for the whole active A-Shell session. During
    // the first minute poll quickly enough to catch ThemeService/Explorer/startup
    // resets before they become a visible flash; afterwards use a low-frequency
    // safety check. Crucially, expectedArrow NEVER gets replaced by a mismatching
    // cursor. The previous guard accepted whatever was present immediately after
    // a race, so it could permanently bless the Windows default cursor.
    const ULONGLONG fastUntil = GetTickCount64() + 60000;
    ULONGLONG lastFallback = 0;
    while (AShellIsActive(root)) {
        Sleep(GetTickCount64() < fastUntil ? 8 : 250);

        const uint64_t current = FingerprintArrowCursor();
        if (expectedArrow && current) {
            if (current == expectedArrow) continue;

            if (ApplyAllCursors()) {
                // Keep the original known-good fingerprint. Do not learn a cursor
                // that Windows/startup software may have swapped in during this race.
                const uint64_t repaired = FingerprintArrowCursor();
                if (repaired == expectedArrow) continue;
            }
        } else {
            // If fingerprinting is temporarily unavailable, retry conservatively
            // rather than hammering animated cursor roles.
            const ULONGLONG now = GetTickCount64();
            if (now - lastFallback < 500) continue;
            if (ApplyAllCursors()) {
                const uint64_t repaired = FingerprintArrowCursor();
                if (!expectedArrow && repaired) expectedArrow = repaired;
            }
            lastFallback = now;
        }
    }

    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 0;
}
