// ==WindhawkMod==
// @id              ashell-signin-clear-background
// @name            A-Shell clear sign-in background
// @description     Removes the separate 45% black sign-in backdrop on the verified Windows build.
// @version         1.0
// @author          A-Shell
// @include         LogonUI.exe
// @architecture    x86-64
// @compilerOptions -lruntimeobject -ladvapi32 -lole32 -loleaut32
// ==/WindhawkMod==

#include <windows.h>
#include <wincrypt.h>
#undef GetCurrentTime
#include <winrt/Windows.UI.Xaml.Media.h>
#include <winrt/Windows.UI.h>
#include <cmath>
#include <cstring>
#include <cstdio>
#ifndef ASHELL_TEST
#include <windhawk_api.h>
#endif

// Only this exact, inspected binary is supported. Updates fail closed.
static constexpr char kHash[] = "51b3aa2b50944111f039c0de035f9c8951a3fd7a65eda7380ad30ece5c2565bf";
static bool VerifiedFile(PCWSTR path) {
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE,
                          nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    HCRYPTPROV provider = 0; HCRYPTHASH hash = 0;
    bool ok = CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT)
        && CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash);
    BYTE buffer[32768]; DWORD count = 0;
    while (ok) {
        if (!ReadFile(f, buffer, sizeof(buffer), &count, nullptr)) { ok = false; break; }
        if (!count) break;
        ok = !!CryptHashData(hash, buffer, count, 0);
    }
    BYTE digest[32]; DWORD size = sizeof(digest); char hex[65]{};
    if (ok) ok = !!CryptGetHashParam(hash, HP_HASHVAL, digest, &size, 0);
    if (ok) for (unsigned i = 0; i < 32; ++i) sprintf_s(hex + i * 2, 3, "%02x", digest[i]);
    if (hash) CryptDestroyHash(hash);
    if (provider) CryptReleaseContext(provider, 0);
    CloseHandle(f);
    return ok && !strcmp(hex, kHash);
}

// QI avoids relying on the C++/CX class pointer's default interface layout.
static bool ClearVerifiedBrush(void* raw) noexcept {
    if (!raw) return false;
    try {
        winrt::Windows::UI::Xaml::Media::SolidColorBrush brush{nullptr};
        if (FAILED(static_cast<IUnknown*>(raw)->QueryInterface(
                winrt::guid_of<decltype(brush)>(), winrt::put_abi(brush)))) return false;
        auto c = brush.Color();
        if (c.A != 255 || c.R || c.G || c.B) return false;
        double opacity = brush.Opacity();
        if (opacity == 0.0) return true;
        if (std::abs(opacity - 0.45) > 0.000001) return false;
        brush.Opacity(0.0);
        return brush.Opacity() == 0.0;
    } catch (winrt::hresult_error const& e) {
#ifdef ASHELL_TEST
        printf("Brush operation failed: %08x\n", unsigned(e.code().value));
#endif
        return false;
    } catch (...) { return false; }
}

#ifndef ASHELL_TEST
using Getter = void* (*)(void*);
static Getter originalGetter;
static HMODULE logonModule;
static volatile LONG reported;

static void* BackgroundGetter(void* self) {
    void* result = originalGetter(self);
    // Only the known non-acrylic member, never another returned brush.
    if (result && result == *reinterpret_cast<void**>(static_cast<BYTE*>(self) + 0x170)
        && ClearVerifiedBrush(result) && InterlockedCompareExchange(&reported, 1, 0) == 0) {
        Wh_SetIntValue(L"OverlayRemoved", 1);
        Wh_SetIntValue(L"LastAppliedPid", GetCurrentProcessId());
    }
    return result;
}

BOOL Wh_ModInit() {
    Wh_SetIntValue(L"OverlayRemoved", 0);
    Wh_SetIntValue(L"HookInstalled", 0);
    wchar_t path[MAX_PATH];
    if (!GetSystemDirectoryW(path, MAX_PATH)) return FALSE;
    wcscat_s(path, L"\\Windows.UI.Logon.dll");
    if (!VerifiedFile(path)) { Wh_Log(L"Unsupported Windows binary; no changes made"); return FALSE; }
    DWORD disabled = 0, size = sizeof(disabled);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        L"DisableAcrylicBackgroundOnLogon", RRF_RT_REG_DWORD, nullptr, &disabled, &size) != ERROR_SUCCESS
        || disabled != 1) return FALSE;
    logonModule = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!logonModule) return FALSE;
    BYTE* target = reinterpret_cast<BYTE*>(logonModule) + 0x94140;
    const BYTE prologue[] = {0x48,0x89,0x5c,0x24,0x08,0x55,0x56,0x57,0x41,0x56,0x41,0x57};
    if (memcmp(target, prologue, sizeof(prologue)) ||
        !Wh_SetFunctionHook(target, reinterpret_cast<void*>(BackgroundGetter),
                          reinterpret_cast<void**>(&originalGetter))) {
        FreeLibrary(logonModule); logonModule = nullptr; return FALSE;
    }
    Wh_SetIntValue(L"HookInstalled", 1);
    return TRUE;
}

void Wh_ModUninit() {
    // Windhawk removes the hook. Existing brushes expire with the sign-in view.
    if (logonModule) FreeLibrary(logonModule);
}
#else
// Test the COM interface boundary without loading the secure sign-in UI.
struct TestBrush : winrt::implements<TestBrush,
    winrt::Windows::UI::Xaml::Media::ISolidColorBrush,
    winrt::Windows::UI::Xaml::Media::IBrush> {
    winrt::Windows::UI::Color color;
    double opacity;
    TestBrush(winrt::Windows::UI::Color c, double o) : color(c), opacity(o) {}
    auto Color() { return color; }
    void Color(winrt::Windows::UI::Color const& c) { color = c; }
    double Opacity() { return opacity; }
    void Opacity(double o) { opacity = o; }
    winrt::Windows::UI::Xaml::Media::Transform Transform() { return nullptr; }
    void Transform(winrt::Windows::UI::Xaml::Media::Transform const&) {}
    winrt::Windows::UI::Xaml::Media::Transform RelativeTransform() { return nullptr; }
    void RelativeTransform(winrt::Windows::UI::Xaml::Media::Transform const&) {}
};
int main() {
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    try {
        using namespace winrt::Windows::UI::Xaml::Media;
        auto black = winrt::make<TestBrush>(winrt::Windows::UI::Color{255,0,0,0}, 0.45).as<SolidColorBrush>();
        auto white = winrt::make<TestBrush>(winrt::Windows::UI::Color{255,255,255,255}, 0.45).as<SolidColorBrush>();
        auto different = winrt::make<TestBrush>(winrt::Windows::UI::Color{255,0,0,0}, 0.6).as<SolidColorBrush>();
        auto color = black.Color();
        printf("Before: ARGB=%u,%u,%u,%u opacity=%.9f\n", color.A,color.R,color.G,color.B,black.Opacity());
        bool cleared = ClearVerifiedBrush(winrt::get_abi(black));
        printf("After: cleared=%d opacity=%.9f\n",cleared,black.Opacity());
        if (!cleared || black.Opacity() != 0) return 1;
        if (!ClearVerifiedBrush(winrt::get_abi(black))) return 2;
        if (ClearVerifiedBrush(winrt::get_abi(white)) || white.Opacity() != 0.45) return 3;
        if (ClearVerifiedBrush(winrt::get_abi(different)) || different.Opacity() != 0.6) return 4;
        if (ClearVerifiedBrush(nullptr)) return 5;
        if (!VerifiedFile(L"C:\\Windows\\System32\\Windows.UI.Logon.dll")) return 6;
        if (VerifiedFile(L"C:\\Windows\\System32\\kernel32.dll")) return 7;
        puts("PASS: correct brush cleared; unrelated brushes unchanged; binary guard passed.");
        return 0;
    } catch (winrt::hresult_error const& e) { printf("XAML test failed: %08x\n", unsigned(e.code().value)); return 8; }
}
#endif
