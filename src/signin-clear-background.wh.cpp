// ==WindhawkMod==
// @id              ashell-signin-clear-background
// @name            A-Shell clear sign-in background
// @description     Removes the sign-in dimmer using matching Microsoft symbols across Windows updates.
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
#ifndef WH_MOD_ID
#define WH_MOD_ID L"ashell-signin-clear-background"
#endif
#include <windhawk_utils.h>
#endif

// QI avoids relying on the C++/CX class pointer's default interface layout.
static bool ClearVerifiedBrush(void* raw, bool verifiedMember = false) noexcept {
    if (!raw) return false;
    try {
        winrt::Windows::UI::Xaml::Media::SolidColorBrush brush{nullptr};
        if (FAILED(static_cast<IUnknown*>(raw)->QueryInterface(
                winrt::guid_of<decltype(brush)>(), winrt::put_abi(brush)))) return false;
        auto c = brush.Color();
        // Color alpha remains zero even if the handoff storyboard animates
        // Brush.Opacity after the getter returns. Opacity alone can flash back.
        if (c.R || c.G || c.B) return false;
        if (c.A == 0) { brush.Opacity(0.0); return true; }
        if (c.A != 255) return false;
        double opacity = brush.Opacity();
        if (opacity == 0.0) { brush.Color({0, 0, 0, 0}); return true; }
        // The exact getter/member identity also permits intermediate fade values.
        // Keep the original narrow check for brushes without that identity proof.
        if (!std::isfinite(opacity) || opacity < 0 || opacity > 1) return false;
        if (!verifiedMember && std::abs(opacity - 0.45) > 0.000001) return false;
        brush.Color({0, 0, 0, 0});
        brush.Opacity(0.0);
        return brush.Opacity() == 0.0 && brush.Color().A == 0;
    } catch (winrt::hresult_error const& e) {
#ifdef ASHELL_TEST
        printf("Brush operation failed: %08x\n", unsigned(e.code().value));
#endif
        return false;
    } catch (...) { return false; }
}

#ifndef ASHELL_TEST
using Getter = void* (*)(void*);
using ZoomPolicy = bool (*)(void*);
using ZoomGetter = bool (*)(void*);
using ZoomSetter = void (*)(void*, bool);
static Getter originalGetter;
static ZoomPolicy originalZoomPolicy;
static ZoomGetter originalZoomGetter;
static ZoomSetter setZoomDisabled;
static HMODULE logonModule;
static volatile LONG reported, zoomReported;

static void* BackgroundGetter(void* self) {
    if (setZoomDisabled) setZoomDisabled(self, true);
    void* result = originalGetter(self);
    // The symbol-identified background property owns this brush. Validate its
    // COM type and black color; never read private object member offsets.
    if (result && ClearVerifiedBrush(result, true) && InterlockedCompareExchange(&reported, 1, 0) == 0) {
        Wh_SetIntValue(L"OverlayRemoved", 1);
        Wh_SetIntValue(L"LastAppliedPid", GetCurrentProcessId());
    }
    return result;
}

static bool ZoomPolicyHook(void* self) {
    // Microsoft PDB: this is ShouldPanLockLogonImage, NOT IsZoomDisabled.
    // Returning true enables image panning and its oversized image surface.
    originalZoomPolicy(self);
    if (setZoomDisabled) setZoomDisabled(self, true);
    Wh_SetIntValue(L"PanDisabled", 1);
    return false;
}

static bool ZoomGetterHook(void* self) {
    // Native property getter: generated XAML bindings bypass the ABI wrapper.
    if (setZoomDisabled) setZoomDisabled(self, true);
    if (InterlockedCompareExchange(&zoomReported, 1, 0) == 0) {
        Wh_SetIntValue(L"ZoomDisabled", 1);
        Wh_SetIntValue(L"LastAppliedPid", GetCurrentProcessId());
    }
    return true;
}

BOOL Wh_ModInit() {
    Wh_SetIntValue(L"SymbolResolved", 0);
    Wh_SetIntValue(L"OverlayRemoved", 0);
    Wh_SetIntValue(L"HookInstalled", 0);
    Wh_SetIntValue(L"ZoomHookInstalled", 0);
    Wh_SetIntValue(L"ZoomDisabled", 0);
    Wh_SetIntValue(L"PanDisabled", 0);
    wchar_t path[MAX_PATH];
    if (!GetSystemDirectoryW(path, MAX_PATH)) return FALSE;
    wcscat_s(path, L"\\Windows.UI.Logon.dll");
    DWORD disabled = 0, size = sizeof(disabled);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        L"DisableAcrylicBackgroundOnLogon", RRF_RT_REG_DWORD, nullptr, &disabled, &size) != ERROR_SUCCESS
        || disabled != 1) return FALSE;
    logonModule = LoadLibraryExW(path, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!logonModule) return FALSE;
    Wh_SetStringValue(L"CompatibilityError", L"");
    WindhawkUtils::SYMBOL_HOOK hooks[] = {
        {{L"?get@?QLogonBackgroundBrush@__IRequestCredentialEntryViewModelPublicNonVirtuals@LogonUX@@1RequestCredentialEntryViewModel@3@UE$AAAPE$AAVBrush@Media@Xaml@UI@Windows@@XZ"}, &originalGetter, BackgroundGetter},
        {{L"?get@?QShouldPanLockLogonImage@__IRequestCredentialEntryViewModelPublicNonVirtuals@LogonUX@@1RequestCredentialEntryViewModel@3@UE$AAA_NXZ"}, &originalZoomPolicy, ZoomPolicyHook, true},
        {{L"?get@?QIsZoomDisabled@__IRequestCredentialEntryViewModelPublicNonVirtuals@LogonUX@@1RequestCredentialEntryViewModel@3@UE$AAA_NXZ"}, &originalZoomGetter, ZoomGetterHook, true},
        {{L"?set@?QIsZoomDisabled@__IRequestCredentialEntryViewModelPublicNonVirtuals@LogonUX@@1RequestCredentialEntryViewModel@3@UE$AAAX_N@Z"}, &setZoomDisabled, nullptr, true},
    };
    // Windhawk validates PDB identity against this module and caches addresses
    // per binary version. No fixed hashes, RVAs or object-layout offsets.
    WH_HOOK_SYMBOLS_OPTIONS options{sizeof(options)};
    options.noUndecoratedSymbols = TRUE;
    if (!WindhawkUtils::HookSymbols(logonModule, hooks, ARRAYSIZE(hooks), &options)) {
        Wh_SetStringValue(L"CompatibilityError", L"Matching Microsoft background symbols unavailable; reconnect and refresh A-Shell screens.");
        Wh_Log(L"Matching Microsoft background symbols unavailable");
        return FALSE;
    }
    Wh_SetIntValue(L"HookInstalled", 1);
    Wh_SetIntValue(L"SymbolResolved", 1);
    Wh_SetIntValue(L"ResolvedForPid", GetCurrentProcessId());
    Wh_SetIntValue(L"ZoomHookInstalled", originalZoomGetter && originalZoomPolicy);
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
        // A late transition opacity animation must not make this brush visible.
        black.Opacity(0.45);
        if (black.Color().A != 0) return 12;
        if (!ClearVerifiedBrush(winrt::get_abi(black)) || black.Opacity() != 0) return 13;
        if (ClearVerifiedBrush(winrt::get_abi(white)) || white.Opacity() != 0.45) return 3;
        if (ClearVerifiedBrush(winrt::get_abi(different)) || different.Opacity() != 0.6) return 4;
        for (double opacity : {0.01, 0.12, 0.3, 0.6, 1.0}) {
            auto fading = winrt::make<TestBrush>(winrt::Windows::UI::Color{255,0,0,0}, opacity).as<SolidColorBrush>();
            if (!ClearVerifiedBrush(winrt::get_abi(fading), true) || fading.Color().A != 0) return 14;
        }
        if (ClearVerifiedBrush(winrt::get_abi(white), true)) return 15;
        if (ClearVerifiedBrush(nullptr)) return 5;
        puts("PASS: exact brush type/color validation, fade values, and unrelated brushes preserved.");
        return 0;
    } catch (winrt::hresult_error const& e) { printf("XAML test failed: %08x\n", unsigned(e.code().value)); return 8; }
}
#endif
