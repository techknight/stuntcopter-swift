#include "CStuntCopterWin.h"
#include <dwmapi.h>
#include <mmsystem.h>
#include <stdlib.h>
#include <string.h>

BOOL sc_wait_for_vblank(void) {
    return SUCCEEDED(DwmFlush());
}

void sc_begin_fine_timer(void) { timeBeginPeriod(1); }
void sc_end_fine_timer(void) { timeEndPeriod(1); }

// MARK: Icon

HICON sc_icon_from_rgba(const uint8_t *rgba, int size) {
    BITMAPV5HEADER bi;
    memset(&bi, 0, sizeof bi);
    bi.bV5Size = sizeof bi;
    bi.bV5Width = size;
    bi.bV5Height = -size;   // top-down
    bi.bV5Planes = 1;
    bi.bV5BitCount = 32;
    bi.bV5Compression = BI_BITFIELDS;
    bi.bV5RedMask = 0x00FF0000;
    bi.bV5GreenMask = 0x0000FF00;
    bi.bV5BlueMask = 0x000000FF;
    bi.bV5AlphaMask = 0xFF000000;

    HDC dc = GetDC(NULL);
    void *bits = NULL;
    HBITMAP color = CreateDIBSection(dc, (BITMAPINFO *)&bi, DIB_RGB_COLORS, &bits, NULL, 0);
    ReleaseDC(NULL, dc);
    if (!color || !bits) return NULL;
    uint8_t *dst = bits;
    for (int i = 0; i < size * size; i++) {   // premultiplied RGBA → straight BGRA, as icons want
        int a = rgba[i * 4 + 3];
        for (int c = 0; c < 3; c++) {
            int v = rgba[i * 4 + 2 - c];
            dst[i * 4 + c] = (uint8_t)(a ? (v * 255 + a / 2) / a : 0);
        }
        dst[i * 4 + 3] = (uint8_t)a;
    }
    HBITMAP mask = CreateBitmap(size, size, 1, 1, NULL);
    ICONINFO ii;
    memset(&ii, 0, sizeof ii);
    ii.fIcon = TRUE;
    ii.hbmMask = mask;
    ii.hbmColor = color;
    HICON icon = CreateIconIndirect(&ii);
    DeleteObject(color);
    DeleteObject(mask);
    return icon;
}

HICON sc_resource_icon(BOOL small_icon) {
    int size = GetSystemMetrics(small_icon ? SM_CXSMICON : SM_CXICON);
    return (HICON)LoadImageW(GetModuleHandleW(NULL), MAKEINTRESOURCEW(1), IMAGE_ICON, size, size, LR_DEFAULTCOLOR);
}

// MARK: Audio (waveOut, fed from a thread)

#define SC_AUDIO_RATE 44100
#define SC_AUDIO_BUFFERS 4
#define SC_AUDIO_FRAMES 441   // 10 ms each

struct sc_audio {
    HWAVEOUT device;
    HANDLE event;
    HANDLE thread;
    volatile LONG stopping;
    sc_audio_render render;
    void *context;
    WAVEHDR headers[SC_AUDIO_BUFFERS];
    short samples[SC_AUDIO_BUFFERS][SC_AUDIO_FRAMES];
    float scratch[SC_AUDIO_FRAMES];
};

static void sc_audio_fill(sc_audio *a, int i) {
    a->render(a->context, a->scratch, SC_AUDIO_FRAMES);
    for (int n = 0; n < SC_AUDIO_FRAMES; n++) {
        float v = a->scratch[n];
        if (v > 1.0f) v = 1.0f;
        if (v < -1.0f) v = -1.0f;
        a->samples[i][n] = (short)(v * 32767.0f);
    }
    waveOutWrite(a->device, &a->headers[i], sizeof(WAVEHDR));
}

static DWORD WINAPI sc_audio_thread(LPVOID param) {
    sc_audio *a = param;
    while (!a->stopping) {
        for (int i = 0; i < SC_AUDIO_BUFFERS; i++) {
            if (a->headers[i].dwFlags & WHDR_DONE) sc_audio_fill(a, i);
        }
        WaitForSingleObject(a->event, 20);
    }
    return 0;
}

sc_audio *sc_audio_start(sc_audio_render render, void *context) {
    sc_audio *a = calloc(1, sizeof *a);
    if (!a) return NULL;
    a->render = render;
    a->context = context;
    a->event = CreateEventW(NULL, FALSE, FALSE, NULL);

    WAVEFORMATEX fmt;
    memset(&fmt, 0, sizeof fmt);
    fmt.wFormatTag = WAVE_FORMAT_PCM;
    fmt.nChannels = 1;
    fmt.nSamplesPerSec = SC_AUDIO_RATE;
    fmt.wBitsPerSample = 16;
    fmt.nBlockAlign = 2;
    fmt.nAvgBytesPerSec = SC_AUDIO_RATE * 2;
    if (waveOutOpen(&a->device, WAVE_MAPPER, &fmt, (DWORD_PTR)a->event, 0, CALLBACK_EVENT) != MMSYSERR_NOERROR) {
        CloseHandle(a->event);
        free(a);
        return NULL;
    }
    for (int i = 0; i < SC_AUDIO_BUFFERS; i++) {
        a->headers[i].lpData = (LPSTR)a->samples[i];
        a->headers[i].dwBufferLength = SC_AUDIO_FRAMES * sizeof(short);
        waveOutPrepareHeader(a->device, &a->headers[i], sizeof(WAVEHDR));
        sc_audio_fill(a, i);
    }
    a->thread = CreateThread(NULL, 0, sc_audio_thread, a, 0, NULL);
    if (a->thread) SetThreadPriority(a->thread, THREAD_PRIORITY_HIGHEST);
    return a;
}

double sc_audio_rate(const sc_audio *a) { (void)a; return SC_AUDIO_RATE; }

void sc_audio_stop(sc_audio *a) {
    if (!a) return;
    InterlockedExchange(&a->stopping, 1);
    SetEvent(a->event);
    if (a->thread) {
        WaitForSingleObject(a->thread, 1000);
        CloseHandle(a->thread);
    }
    waveOutReset(a->device);
    for (int i = 0; i < SC_AUDIO_BUFFERS; i++) waveOutUnprepareHeader(a->device, &a->headers[i], sizeof(WAVEHDR));
    waveOutClose(a->device);
    CloseHandle(a->event);
    free(a);
}
