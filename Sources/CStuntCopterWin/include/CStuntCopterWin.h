// Win32 pieces the Swift shell can't express directly: the waveOut audio pump,
// icon construction, and the macros Swift doesn't import (casts and LOWORD-style
// field extraction). Everything else comes straight from WinSDK.
#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <stdint.h>

// MARK: Macros as functions

static inline int sc_loword(uintptr_t v) { return (int)(v & 0xFFFF); }
static inline int sc_hiword(uintptr_t v) { return (int)((v >> 16) & 0xFFFF); }
/// GET_X_LPARAM / GET_Y_LPARAM: signed client coordinates from a mouse message.
static inline int sc_x_lparam(intptr_t l) { return (int)(short)(l & 0xFFFF); }
static inline int sc_y_lparam(intptr_t l) { return (int)(short)((l >> 16) & 0xFFFF); }

static inline int sc_cw_usedefault(void) { return CW_USEDEFAULT; }
static inline DWORD sc_srccopy(void) { return SRCCOPY; }
static inline DWORD sc_blackness(void) { return BLACKNESS; }
static inline HCURSOR sc_arrow_cursor(void) { return LoadCursorW(NULL, MAKEINTRESOURCEW(32512) /* IDC_ARROW */); }
static inline HBRUSH sc_black_brush(void) { return (HBRUSH)GetStockObject(BLACK_BRUSH); }
static inline UINT_PTR sc_menu_as_id(HMENU m) { return (UINT_PTR)m; }
static inline LPARAM sc_icon_as_lparam(HICON i) { return (LPARAM)i; }

/// Per-monitor DPI awareness (v2), so the window is sized in real pixels.
static inline BOOL sc_set_dpi_aware(void) {
    return SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
}

/// DwmFlush: wait for the next display refresh. Returns FALSE if the DWM isn't running.
BOOL sc_wait_for_vblank(void);

/// 1 ms scheduler resolution for Sleep.
void sc_begin_fine_timer(void);
void sc_end_fine_timer(void);

// MARK: Icon

/// A 32-bit icon with alpha from premultiplied RGBA pixels (see appIconPixels).
HICON sc_icon_from_rgba(const uint8_t *rgba, int size);
/// Icon resource 1 (Support/Windows/StuntCopter.rc) at the system's large or small
/// icon size, or NULL if the exe was built without it.
HICON sc_resource_icon(BOOL small);

// MARK: Audio

/// Called on the audio thread to fill `frames` mono Float samples.
typedef void (*sc_audio_render)(void *context, float *out, int frames);

typedef struct sc_audio sc_audio;

/// Opens the default waveOut device (16-bit mono, 44.1 kHz) and starts a thread that
/// keeps it fed from `render`. Returns NULL if no device could be opened.
sc_audio *sc_audio_start(sc_audio_render render, void *context);
/// Sample rate the renderer is asked for.
double sc_audio_rate(const sc_audio *a);
void sc_audio_stop(sc_audio *a);
