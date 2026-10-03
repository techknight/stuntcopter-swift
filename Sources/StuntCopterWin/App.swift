import CStuntCopterWin
import ClassicToolbox
import StuntCopterCore
import WinSDK

/// The Win32 shell: owns the game, its window, menus, frame pacing, pointer lock,
/// dialogs and preferences, and implements the Toolbox calls the game makes
/// outside QuickDraw (GameHost). The AppKit counterpart is StuntCopterMac/AppDelegate.
@MainActor
final class App: GameHost {
    static let className = "StuntCopterWindow"

    private var game: StuntCopterGame!
    private var window: Win32Window!
    private var audio: AudioOutput?
    private var pacer = FramePacer()
    private var dialogs: [Int: DialogWindow] = [:]
    private var modalDepth = 0
    private var inSizeMove = false
    private var settingScale = false
    /// Set once the window is sized and shown; before that, WM_SIZE from building it
    /// (SetMenu shrinks the client area) must not snap and overwrite the saved scale.
    private var ready = false
    private let prefs = Preferences()

    // Menus. Command ids: menu index × 100 + item (Win32 ids are 16-bit).
    private var menuBar: HMENU!
    private var messageMenu: HMENU?
    private var messageMenuTitle = ""
    private var messageMenuShown = false
    private var commands: [Int: (menu: Int, item: Int)] = [:]
    private let soundCommand = 301
    private static let viewCommandBase = 400
    private static let quitCommand = 201

    /// Set while the cursor is hidden for play.
    private var pointer: VirtualPointer?
    private var lockCenter = (x: 0, y: 0)

    private var performanceFrequency = 1.0

    // MARK: Launch

    init() throws {
        game = try StuntCopterGame(host: self)
        // Override by adding `LoopsPerSecond=N` to Preferences.txt, for calibration.
        pacer = FramePacer(loopsPerSecond: prefs.double(forKey: PreferenceKey.loopsPerSecond))
        var freq = LARGE_INTEGER()
        _ = QueryPerformanceFrequency(&freq)
        performanceFrequency = Double(freq.QuadPart)

        // The exe's icon resource, drawn for each size; a plain `swift build` has none,
        // so fall back to rendering the ICN# here.
        let large = sc_resource_icon(false), small = sc_resource_icon(true)
        let fallback = large == nil ? makeIcon() : nil
        registerWindowClass(App.className, icon: large ?? fallback, smallIcon: small ?? fallback, dropShadow: false)
        registerWindowClass(DialogWindow.className, icon: nil, smallIcon: nil, dropShadow: true)
        buildWindow()
        buildMenus()

        try game.start()
        game.tick()   // the first update event draws the window
        setScale(initialScale())
        center()
        _ = ShowWindow(window.hwnd, SW_SHOW)
        ready = true
        window.refresh()

        audio = AudioOutput(driver: game.soundDriver)
    }

    private func makeIcon() -> HICON? {
        guard let icn = try? game.resources.iconList(129) else { return nil }
        let rgba = appIconPixels(icon: icn.icon, size: 256)
        return rgba.withUnsafeBufferPointer { sc_icon_from_rgba($0.baseAddress, 256) }
    }

    /// The message loop and frame pacing: one frame per display refresh.
    func run() {
        var msg = MSG()
        loop: while true {
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) { break loop }
                _ = TranslateMessage(&msg)
                _ = DispatchMessageW(&msg)
            }
            frame()
            if !sc_wait_for_vblank() { Sleep(16) }
        }
        releasePointerLock()
        audio?.stop()
    }

    private var now: Double {
        var t = LARGE_INTEGER()
        _ = QueryPerformanceCounter(&t)
        return Double(t.QuadPart) / performanceFrequency
    }

    private func frame() {
        guard modalDepth == 0 else { return }   // hideDialogWindow resets the pacer
        for _ in 0..<pacer.steps(at: now, rateFactor: game.loopRateFactor) { game.tick() }
        window.refresh()
    }

    // MARK: Window

    private func buildWindow() {
        window = Win32Window(className: App.className, title: "StuntCopter",
                             style: wsCaption | wsSysMenu | wsThickFrame | wsMinimizeBox,
                             bitmap: game.myWindow.portBits)
        window.onMouseDown = { [weak self] p in
            guard let self else { return }
            game.post(.mouseDown(pointer != nil ? .zero : p))
        }
        window.onMouseDragged = { [weak self] p in
            guard let self, pointer == nil else { return }
            game.post(.mouseDragged(p))
        }
        window.onMouseUp = { [weak self] p in
            guard let self, pointer == nil else { return }
            game.post(.mouseUp(p))
        }
        window.onMouseMoved = { [weak self] x, y in self?.mouseMoved(x, y) }
        window.onKey = { [weak self] key in
            self?.game.post(.keyDown(key.character))
            return true
        }
        window.onMessage = { [weak self] msg, wParam, lParam in self?.message(msg, wParam, lParam) }
    }

    private func initialScale() -> Int {
        let saved = prefs.integer(forKey: PreferenceKey.scale)
        if WindowScale.range.contains(saved) { return saved }
        var work = RECT()
        guard SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &work, 0) else {
            return WindowScale.initial(game.windowRect, screenWidth: nil, screenHeight: nil)
        }
        let chrome = window.chromeSize
        return WindowScale.initial(game.windowRect, screenWidth: Int(work.right - work.left) - chrome.width,
                                   screenHeight: Int(work.bottom - work.top) - chrome.height)
    }

    /// Sizes the window so the game is exactly `s`× the original, keeping its
    /// top-left corner where it is. Chrome is measured, so a wrapped menu bar or a
    /// DPI change can't leave the picture off its integer scale.
    private func setScale(_ s: Int) {
        window.scale = s
        for d in dialogs.values { d.window.scale = s }
        let want = (width: game.windowRect.width * s, height: game.windowRect.height * s)
        settingScale = true
        defer { settingScale = false }
        for _ in 0..<2 where window.clientSize != want {
            let chrome = window.chromeSize
            _ = SetWindowPos(window.hwnd, nil, 0, 0, Int32(want.width + chrome.width), Int32(want.height + chrome.height),
                             UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        }
        prefs.set(s, forKey: PreferenceKey.scale)
        _ = CheckMenuRadioItem(menuBar, UINT(App.viewCommandBase + WindowScale.range.lowerBound),
                               UINT(App.viewCommandBase + WindowScale.range.upperBound),
                               UINT(App.viewCommandBase + s), UINT(MF_BYCOMMAND))
    }

    /// If anything changed the client area behind our back, resize the window so the
    /// game is exactly 503×310 × an integer again.
    private func snapToIntegerScale() {
        let c = window.clientSize
        let s = WindowScale.fitting(game.windowRect, width: c.width, height: c.height, limit: nil)
        setScale(s)
    }

    private func center() {
        var work = RECT(), r = RECT()
        guard SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &work, 0), GetWindowRect(window.hwnd, &r) else {
            return
        }
        let w = r.right - r.left, h = r.bottom - r.top
        let x = work.left + max(0, (work.right - work.left - w) / 2)
        let y = work.top + max(0, (work.bottom - work.top - h) / 2)
        _ = SetWindowPos(window.hwnd, nil, x, y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    private func message(_ msg: Int32, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch msg {
        case WM_COMMAND:
            guard sc_hiword(UInt(wParam)) <= 1 else { return nil }   // menu or accelerator
            command(Int(sc_loword(UInt(wParam))))
            return 0
        case WM_KEYDOWN:
            guard GetKeyState(VK_CONTROL) < 0 else { return nil }
            switch Int32(truncatingIfNeeded: wParam) {
            case 0x51: command(App.quitCommand)   // Ctrl+Q
            case 0x31...0x34: command(App.viewCommandBase + Int(wParam) - 0x30)   // Ctrl+1…4
            default: return nil
            }
            return 0
        case WM_ENTERSIZEMOVE:
            inSizeMove = true
            return nil
        case WM_EXITSIZEMOVE:
            inSizeMove = false
            if ready { snapToIntegerScale() }
            return nil
        case WM_SIZE:
            if ready, !inSizeMove, !settingScale, Int32(truncatingIfNeeded: wParam) != SIZE_MINIMIZED { snapToIntegerScale() }
            return nil
        case WM_GETMINMAXINFO:
            guard window != nil, let info = UnsafeMutablePointer<MINMAXINFO>(bitPattern: Int(lParam)) else { return nil }
            let chrome = window.chromeSize
            info.pointee.ptMinTrackSize = POINT(x: Int32(game.windowRect.width + chrome.width),
                                                y: Int32(game.windowRect.height + chrome.height))
            return 0
        case WM_ACTIVATEAPP:
            if wParam == 0 {   // like the original, losing the front pauses play
                game.pauseIfPlaying()
                window.refresh()
            }
            return nil
        case WM_CLOSE:
            _ = DestroyWindow(window.hwnd)
            return 0
        case WM_DESTROY:
            PostQuitMessage(0)
            return 0
        default:
            return nil
        }
    }

    // MARK: Input

    private func mouseMoved(_ x: Int, _ y: Int) {
        guard pointer != nil else { return }
        let dx = x - lockCenter.x, dy = y - lockCenter.y
        guard dx != 0 || dy != 0 else { return }   // our own warp back to the center
        pointer?.move(dx: Double(dx), dy: Double(dy), scale: window.scale, windowOrigin: game.windowGlobalOrigin)
        warpToLockCenter()
    }

    private func warpToLockCenter() {
        var p = POINT(x: Int32(lockCenter.x), y: Int32(lockCenter.y))
        _ = ClientToScreen(window.hwnd, &p)
        _ = SetCursorPos(p.x, p.y)
    }

    private func releasePointerLock() {
        guard let pointer else { return }
        self.pointer = nil
        _ = ClipCursor(nil)
        let p = window.screenPoint(pointer.point)
        _ = SetCursorPos(p.x, p.y)
        _ = ShowCursor(true)
    }

    // MARK: GameHost

    func getMouse() -> Point {
        if let pointer { return pointer.point }
        return window.mousePosition
    }

    func hideCursor() {
        guard pointer == nil else { return }
        pointer = VirtualPointer(at: getMouse())
        _ = ShowCursor(false)
        var clip = window.clientScreenRect
        _ = ClipCursor(&clip)
        let c = window.clientSize
        lockCenter = (c.width / 2, c.height / 2)
        warpToLockCenter()
    }

    func showCursor() { releasePointerLock() }

    func drawMenuBar(messageMenuShown: Bool, menusEnabled: Bool) {
        for (id, c) in commands where c.menu == StuntCopterGame.optionMenu || c.menu == StuntCopterGame.appleMenu {
            _ = EnableMenuItem(menuBar, UINT(id), UINT(MF_BYCOMMAND | (menusEnabled ? MF_ENABLED : MF_GRAYED)))
        }
        if let messageMenu, messageMenuShown != self.messageMenuShown {
            if messageMenuShown {
                messageMenuTitle.withCString(encodedAs: UTF16.self) { title in
                    _ = AppendMenuW(menuBar, UINT(MF_POPUP), sc_menu_as_id(messageMenu), title)
                }
            } else {
                _ = RemoveMenu(menuBar, UINT(GetMenuItemCount(menuBar) - 1), UINT(MF_BYPOSITION))
            }
            self.messageMenuShown = messageMenuShown
        }
        _ = DrawMenuBar(window.hwnd)
    }

    func checkSoundItem(_ on: Bool) {
        _ = CheckMenuItem(menuBar, UINT(soundCommand), UINT(MF_BYCOMMAND | (on ? MF_CHECKED : MF_UNCHECKED)))
    }

    private func dialogWindow(for d: ClassicDialog) -> DialogWindow {
        if let w = dialogs[d.id] { return w }
        let w = DialogWindow(dialog: d, game: game, owner: window)
        dialogs[d.id] = w
        return w
    }

    func showDialogWindow(_ d: ClassicDialog) {
        modalDepth += 1
        releasePointerLock()
        let w = dialogWindow(for: d)
        w.position(windowOrigin: game.windowGlobalOrigin)
        w.refresh()
        w.show()
    }

    func hideDialogWindow(_ d: ClassicDialog) {
        dialogWindow(for: d).hide()
        modalDepth = max(0, modalDepth - 1)
        pacer.reset()
        _ = SetForegroundWindow(window.hwnd)
        _ = SetFocus(window.hwnd)
    }

    func modalDialog(_ d: ClassicDialog) -> Int {
        let w = dialogWindow(for: d)
        w.refresh()   // pick up anything drawn since ShowWindow
        let item = w.runModal()
        w.refresh()
        return item
    }

    func pause(ticks: Int) {
        for w in dialogs.values where w.window.isVisible { w.refresh() }
        Sleep(DWORD(ticks * 1000 / 60))
    }

    func savedHiScore() -> Int { prefs.integer(forKey: PreferenceKey.hiScore) }

    func hiScoreChanged(_ hiScore: Int) { prefs.set(hiScore, forKey: PreferenceKey.hiScore) }

    func quit() { _ = DestroyWindow(window.hwnd) }

    // MARK: Menus

    private func addItem(_ menu: HMENU, _ text: String, id: Int, menuID: Int, item: Int) {
        commands[id] = (menuID, item)
        text.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(id), $0) }
    }

    private func addSubmenu(_ title: String) -> HMENU {
        let menu = CreatePopupMenu()!
        title.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menuBar, UINT(MF_POPUP), sc_menu_as_id(menu), $0) }
        return menu
    }

    private func buildMenus() {
        menuBar = CreateMenu()
        let res = game.resources

        // File: Quit (the original's File menu).
        let file = addSubmenu("&File")
        let quitTitle = (try? res.menu(StuntCopterGame.fileMenu).items.first?.text) ?? "Quit"
        addItem(file, quitTitle + "\tCtrl+Q", id: App.quitCommand, menuID: StuntCopterGame.fileMenu, item: 1)

        // Options, from MENU 257.
        if let options = try? res.menu(StuntCopterGame.optionMenu) {
            let menu = addSubmenu("&" + options.title)
            for (i, it) in options.items.enumerated() {
                addItem(menu, it.text, id: 300 + i + 1, menuID: StuntCopterGame.optionMenu, item: i + 1)
            }
        }

        // View (new): magnification.
        let view = addSubmenu("&View")
        for s in WindowScale.range {
            "\(s)× Size\tCtrl+\(s)".withCString(encodedAs: UTF16.self) {
                _ = AppendMenuW(view, UINT(MF_STRING), UINT_PTR(App.viewCommandBase + s), $0)
            }
        }

        // Help: the Apple menu's About item.
        let help = addSubmenu("&Help")
        let aboutTitle = (try? res.menu(StuntCopterGame.appleMenu).items.first?.text) ?? "About Stunt..."
        addItem(help, aboutTitle, id: 101, menuID: StuntCopterGame.appleMenu, item: 1)

        // The "(Backspace to Exit)" message menu, appended during play.
        if let msg = try? res.menu(StuntCopterGame.messageMenu) {
            let menu = CreatePopupMenu()!
            for it in msg.items {
                it.text.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, $0) }
            }
            messageMenu = menu
            messageMenuTitle = msg.title
        }

        _ = SetMenu(window.hwnd, menuBar)
    }

    private func command(_ id: Int) {
        if WindowScale.range.contains(id - App.viewCommandBase) {
            setScale(id - App.viewCommandBase)
        } else if let c = commands[id] {
            game.DoMenuCommand(c.menu, c.item)
            window.refresh()
        }
    }
}
