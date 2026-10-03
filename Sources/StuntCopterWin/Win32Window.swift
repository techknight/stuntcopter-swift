import CStuntCopterWin
import ClassicToolbox
import StuntCopterCore
import WinSDK

// Window styles as DWORDs (the headers' `L` literals import as mixed types).
let wsCaption: DWORD = 0x00C0_0000
let wsSysMenu: DWORD = 0x0008_0000
let wsThickFrame: DWORD = 0x0004_0000
let wsMinimizeBox: DWORD = 0x0002_0000
let wsPopup: DWORD = 0x8000_0000

/// Windows that receive messages, by handle.
@MainActor var windowHandlers: [HWND: Win32Window] = [:]

/// The one window procedure: hands the message to the Win32Window it belongs to.
func windowProc(_ hwnd: HWND?, _ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    guard let hwnd else { return DefWindowProcW(hwnd, msg, wParam, lParam) }
    let bits = UInt(bitPattern: hwnd)   // the pointer itself isn't Sendable
    return MainActor.assumeIsolated {
        let hwnd = HWND(bitPattern: bits)!
        if let w = windowHandlers[hwnd], let r = w.handle(Int32(msg), wParam, lParam) { return r }
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
}

/// Registers a window class that paints through Win32Window.
@MainActor
func registerWindowClass(_ name: String, icon: HICON?, dropShadow: Bool) {
    var wc = WNDCLASSEXW()
    wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wc.style = UINT(CS_HREDRAW | CS_VREDRAW) | (dropShadow ? UINT(CS_DROPSHADOW) : 0)
    wc.lpfnWndProc = windowProc
    wc.hInstance = GetModuleHandleW(nil)
    wc.hCursor = sc_arrow_cursor()
    wc.hbrBackground = sc_black_brush()
    wc.hIcon = icon
    wc.hIconSm = icon
    name.withCString(encodedAs: UTF16.self) { cls in
        wc.lpszClassName = cls
        _ = RegisterClassExW(&wc)
    }
}

/// Shows a 1-bit bitmap at an integer scale, centered on black, and reports input in
/// bitmap coordinates: the Win32 counterpart of the Mac app's PixelView.
@MainActor
final class Win32Window {
    let hwnd: HWND
    var bitmap: BitMap {
        didSet { lastGeneration = -1 }
    }
    /// Integer magnification of the bitmap in pixels.
    var scale = 1
    private var lastGeneration = -1
    private var bgra: [UInt8] = []

    var onMouseDown: ((Point) -> Void)?
    var onMouseDragged: ((Point) -> Void)?
    var onMouseUp: ((Point) -> Void)?
    /// Raw client-area pointer position on every move, for the virtual pointer.
    var onMouseMoved: ((Int, Int) -> Void)?
    var onKey: ((HostKey) -> Bool)?
    /// Everything else; return nil for DefWindowProc.
    var onMessage: ((Int32, WPARAM, LPARAM) -> LRESULT?)?

    init(className: String, title: String, style: DWORD, exStyle: DWORD = 0, owner: HWND? = nil,
         bitmap: BitMap) {
        self.bitmap = bitmap
        let h = className.withCString(encodedAs: UTF16.self) { cls in
            title.withCString(encodedAs: UTF16.self) { t in
                CreateWindowExW(exStyle, cls, t, style, sc_cw_usedefault(), sc_cw_usedefault(),
                                Int32(bitmap.width), Int32(bitmap.height), owner, nil, GetModuleHandleW(nil), nil)
            }
        }
        guard let h else { fatalError("CreateWindowExW failed") }
        hwnd = h
        windowHandlers[h] = self
    }

    // MARK: Geometry

    var clientSize: (width: Int, height: Int) {
        var r = RECT()
        _ = GetClientRect(hwnd, &r)
        return (Int(r.right - r.left), Int(r.bottom - r.top))
    }

    /// Window size minus client size: title bar, borders and menu bar, measured.
    var chromeSize: (width: Int, height: Int) {
        var r = RECT()
        _ = GetWindowRect(hwnd, &r)
        let c = clientSize
        return (Int(r.right - r.left) - c.width, Int(r.bottom - r.top) - c.height)
    }

    /// Where the bitmap is drawn, in client coordinates.
    var imageRect: (x: Int, y: Int, width: Int, height: Int) {
        let c = clientSize
        let w = bitmap.width * scale, h = bitmap.height * scale
        return ((c.width - w) / 2, (c.height - h) / 2, w, h)
    }

    func bitmapPoint(clientX: Int, clientY: Int) -> Point {
        let r = imageRect
        return Point(h: Int((Double(clientX - r.x) / Double(scale)).rounded(.down)),
                     v: Int((Double(clientY - r.y) / Double(scale)).rounded(.down)))
    }

    /// The center of a bitmap pixel, in client coordinates.
    func clientPoint(_ p: Point) -> (x: Int, y: Int) {
        let r = imageRect
        return (r.x + p.h * scale + scale / 2, r.y + p.v * scale + scale / 2)
    }

    func screenPoint(_ p: Point) -> POINT {
        let c = clientPoint(p)
        var pt = POINT(x: Int32(c.x), y: Int32(c.y))
        _ = ClientToScreen(hwnd, &pt)
        return pt
    }

    /// The client area in screen coordinates.
    var clientScreenRect: RECT {
        var r = RECT()
        _ = GetClientRect(hwnd, &r)
        var tl = POINT(x: r.left, y: r.top), br = POINT(x: r.right, y: r.bottom)
        _ = ClientToScreen(hwnd, &tl)
        _ = ClientToScreen(hwnd, &br)
        return RECT(left: tl.x, top: tl.y, right: br.x, bottom: br.y)
    }

    /// The pointer's current position as a bitmap point.
    var mousePosition: Point {
        var p = POINT()
        _ = GetCursorPos(&p)
        _ = ScreenToClient(hwnd, &p)
        return bitmapPoint(clientX: Int(p.x), clientY: Int(p.y))
    }

    var isVisible: Bool { IsWindowVisible(hwnd).boolValue }

    // MARK: Painting

    /// Pushes the bitmap to the screen if it changed.
    func refresh() {
        guard bitmap.generation != lastGeneration else { return }
        lastGeneration = bitmap.generation
        let gray = bitmap.grayscaleBytes()
        if bgra.count != gray.count * 4 { bgra = [UInt8](repeating: 255, count: gray.count * 4) }
        for i in 0..<gray.count {
            let g = gray[i]
            bgra[i * 4] = g
            bgra[i * 4 + 1] = g
            bgra[i * 4 + 2] = g
        }
        _ = InvalidateRect(hwnd, nil, false)
        _ = UpdateWindow(hwnd)
    }

    private func paint() {
        var ps = PAINTSTRUCT()
        guard let hdc = BeginPaint(hwnd, &ps) else { return }
        defer { _ = EndPaint(hwnd, &ps) }
        let c = clientSize, r = imageRect
        // Letterbox strips (only in the moments a resize is between integer sizes).
        if r.x > 0 { _ = PatBlt(hdc, 0, 0, Int32(r.x), Int32(c.height), sc_blackness()) }
        if r.y > 0 { _ = PatBlt(hdc, 0, 0, Int32(c.width), Int32(r.y), sc_blackness()) }
        if r.x + r.width < c.width {
            _ = PatBlt(hdc, Int32(r.x + r.width), 0, Int32(c.width - r.x - r.width), Int32(c.height), sc_blackness())
        }
        if r.y + r.height < c.height {
            _ = PatBlt(hdc, 0, Int32(r.y + r.height), Int32(c.width), Int32(c.height - r.y - r.height), sc_blackness())
        }
        if bgra.isEmpty { refreshPixels() }
        guard !bgra.isEmpty else { return }
        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = Int32(bitmap.width)
        bmi.bmiHeader.biHeight = -Int32(bitmap.height)   // top-down
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = DWORD(BI_RGB)
        _ = SetStretchBltMode(hdc, COLORONCOLOR)   // nearest neighbour
        bgra.withUnsafeBytes { bytes in
            _ = StretchDIBits(hdc, Int32(r.x), Int32(r.y), Int32(r.width), Int32(r.height),
                              0, 0, Int32(bitmap.width), Int32(bitmap.height),
                              bytes.baseAddress, &bmi, UINT(DIB_RGB_COLORS), sc_srccopy())
        }
    }

    /// Rebuilds the pixel buffer without presenting (for the first expose).
    private func refreshPixels() {
        lastGeneration = -1
        let gray = bitmap.grayscaleBytes()
        bgra = [UInt8](repeating: 255, count: gray.count * 4)
        for i in 0..<gray.count {
            bgra[i * 4] = gray[i]
            bgra[i * 4 + 1] = gray[i]
            bgra[i * 4 + 2] = gray[i]
        }
        lastGeneration = bitmap.generation
    }

    // MARK: Messages

    func handle(_ msg: Int32, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch msg {
        case WM_PAINT:
            paint()
            return 0
        case WM_ERASEBKGND:
            return 1
        case WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
            _ = SetCapture(hwnd)
            onMouseDown?(mousePoint(lParam))
            return 0
        case WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP:
            _ = ReleaseCapture()
            onMouseUp?(mousePoint(lParam))
            return 0
        case WM_MOUSEMOVE:
            let x = Int(sc_x_lparam(Int(lParam))), y = Int(sc_y_lparam(Int(lParam)))
            onMouseMoved?(x, y)
            if Int32(truncatingIfNeeded: wParam) & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON) != 0 {
                onMouseDragged?(bitmapPoint(clientX: x, clientY: y))
            }
            return 0
        case WM_CHAR:
            guard GetKeyState(VK_CONTROL) >= 0, let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: wParam)) else {
                return nil
            }
            let key: HostKey
            switch scalar.value {
            case 0x08: key = .backspace
            case 0x1B: key = .escape
            case 0x0D: key = .character("\r")
            case 0..<0x20: return nil
            default: key = .character(Character(scalar))
            }
            return onKey?(key) == true ? 0 : nil
        default:
            return onMessage?(msg, wParam, lParam)
        }
    }

    private func mousePoint(_ lParam: LPARAM) -> Point {
        bitmapPoint(clientX: Int(sc_x_lparam(Int(lParam))), clientY: Int(sc_y_lparam(Int(lParam))))
    }
}
