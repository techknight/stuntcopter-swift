import AppKit
import ClassicToolbox
import StuntCopterCore

/// The AppKit shell: owns the game, its window, menus, frame pacing, mouse
/// capture, dialogs and preferences, and implements the Toolbox calls the game
/// makes outside QuickDraw (GameHost).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, GameHost {
    private var game: StuntCopterGame!
    private var window: NSWindow!
    private var view: PixelView!
    private var audio: AudioOutput?
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var accumulator = 0.0
    private var dialogPanels: [Int: DialogPanel] = [:]
    private var modalDepth = 0

    // Menu state mirrored from the game (InsertMenu/DisableItem/CheckItem).
    private var messageMenuItem: NSMenuItem?
    private var menusEnabled = true
    private var soundItem: NSMenuItem?

    // Virtual pointer while the cursor is hidden for play.
    private var captured = false
    private var virtualX = 256.0, virtualY = 170.0

    private let defaults = UserDefaults.standard

    /// In-game loops per second at NORMAL speed: the original on a Mac Plus, measured in
    /// an emulator (StuntCopterGame.loopRateFactor scales it for attract mode etc.).
    /// Override with `defaults write com.techknight.StuntCopter LoopsPerSecond -float N`.
    private var loopsPerSecond: Double {
        let v = defaults.double(forKey: "LoopsPerSecond")
        return v > 0 ? v : 30
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            game = try StuntCopterGame(host: self)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        if Bundle.main.bundleIdentifier == nil, let icn = try? game.resources.iconList(129) {
            NSApp.applicationIconImage = makeIconImage(icon: icn.icon)
        }
        NSWindow.allowsAutomaticWindowTabbing = false   // no "Show Tab Bar" in the View menu
        buildMenus()
        buildWindow()
        do {
            try game.start()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        game.tick()   // the first update event draws the window
        view.refresh()

        let audio = AudioOutput(driver: game.soundDriver)
        audio.start()
        self.audio = audio

        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .default)   // like the original, menus and dialogs pause the loop
        displayLink = link

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.game.pauseIfPlaying() }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        releaseCapture()
        audio?.stop()
    }

    // MARK: Window

    private func defaultScale() -> Int {
        guard let screen = NSScreen.main?.visibleFrame else { return 2 }
        let s = min(Int(screen.width) / game.windowRect.width, Int(screen.height - 40) / game.windowRect.height)
        return max(1, min(4, s))
    }

    private func contentSize(scale: Int) -> NSSize {
        NSSize(width: game.windowRect.width * scale, height: game.windowRect.height * scale)
    }

    private func buildWindow() {
        let saved = defaults.integer(forKey: "Scale")
        let scale = (1...4).contains(saved) ? saved : defaultScale()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize(scale: scale)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "StuntCopter"
        window.collectionBehavior = [.fullScreenPrimary]
        // One game window: no tabs. (A tab bar would eat into the content area and
        // knock the picture off its integer scale.)
        window.tabbingMode = .disallowed
        window.contentMinSize = contentSize(scale: 1)
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        view = PixelView(bitmap: game.myWindow.portBits)
        window.contentView = view
        window.center()
        window.makeFirstResponder(view)

        view.onMouseDown = { [weak self] p, _ in self?.game.post(.mouseDown(self?.captured == true ? .zero : p)) }
        view.onMouseDragged = { [weak self] p, _ in
            guard let self, !self.captured else { return }
            self.game.post(.mouseDragged(p))
        }
        view.onMouseUp = { [weak self] p, _ in
            guard let self, !self.captured else { return }
            self.game.post(.mouseUp(p))
        }
        view.onMouseMoved = { [weak self] event in self?.mouseMoved(event) }
        view.onKeyDown = { [weak self] event in self?.keyDown(event) ?? false }
    }

    /// Window chrome around the game view (title bar, plus anything else AppKit adds),
    /// measured rather than assumed.
    private var chromeSize: NSSize {
        NSSize(width: window.frame.width - view.bounds.width, height: window.frame.height - view.bounds.height)
    }

    /// Snap user resizes to integer magnifications.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !sender.styleMask.contains(.fullScreen) else { return frameSize }
        let chrome = chromeSize
        let s = max(1, min(Int(frameSize.width - chrome.width) / game.windowRect.width,
                           Int(frameSize.height - chrome.height) / game.windowRect.height))
        let content = contentSize(scale: s)
        return NSSize(width: content.width + chrome.width, height: content.height + chrome.height)
    }

    func windowDidResize(_ notification: Notification) {
        guard !window.styleMask.contains(.fullScreen), !window.inLiveResize else { return }
        snapToIntegerScale()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        snapToIntegerScale()
    }

    func windowDidExitFullScreen(_ notification: Notification) { snapToIntegerScale() }

    /// If anything changed the content area behind our back, resize the window so the
    /// game view is exactly 503×310 × an integer again (no letterboxing in a window).
    private func snapToIntegerScale() {
        let s = view.scale
        if view.bounds.size != contentSize(scale: s) {
            setGameScale(s)
        } else {
            defaults.set(s, forKey: "Scale")
        }
    }

    /// Sizes the window so the game view is exactly `s`× the original, keeping the
    /// window's top-left corner where it is.
    private func setGameScale(_ s: Int) {
        let top = window.frame.maxY
        window.setContentSize(contentSize(scale: s))
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        defaults.set(s, forKey: "Scale")
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        setGameScale(sender.tag)
    }

    // MARK: Frame pacing

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTime = now }
        guard lastTime > 0, modalDepth == 0 else { return }
        accumulator += min(now - lastTime, 0.25) * loopsPerSecond * game.loopRateFactor
        var steps = 0
        while accumulator >= 1 && steps < 8 {
            game.tick()
            accumulator -= 1
            steps += 1
        }
        if steps == 8 { accumulator = 0 }
        view.refresh()
    }

    // MARK: Input

    private func mouseMoved(_ event: NSEvent) {
        guard captured else { return }
        let s = Double(view.scale)
        let origin = game.windowGlobalOrigin
        // Clamp to the 512×342 Mac Plus screen, expressed in window coordinates.
        virtualX = min(max(virtualX + event.deltaX / s, Double(-origin.h)), Double(512 - origin.h))
        virtualY = min(max(virtualY + event.deltaY / s, Double(-origin.v)), Double(342 - origin.v))
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        switch event.keyCode {
        case 51: game.post(.keyDown("\u{8}"))    // delete = backspace
        case 53: game.post(.keyDown("\u{1B}"))   // esc
        default:
            guard let ch = event.characters?.first else { return false }
            game.post(.keyDown(ch))
        }
        return true
    }

    private func releaseCapture() {
        guard captured else { return }
        captured = false
        CGAssociateMouseAndMouseCursorPosition(1)
        if let p = view.screenPoint(Point(h: Int(virtualX), v: Int(virtualY))),
           let screenHeight = NSScreen.screens.first?.frame.height {
            CGWarpMouseCursorPosition(CGPoint(x: p.x, y: screenHeight - p.y))
        }
        NSCursor.unhide()
    }

    // MARK: GameHost

    func getMouse() -> Point {
        if captured { return Point(h: Int(virtualX.rounded(.down)), v: Int(virtualY.rounded(.down))) }
        let p = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return view.bitmapPoint(p)
    }

    func hideCursor() {
        guard !captured else { return }
        let p = getMouse()
        virtualX = Double(p.h)
        virtualY = Double(p.v)
        captured = true
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    func showCursor() { releaseCapture() }

    func drawMenuBar(messageMenuShown: Bool, menusEnabled: Bool) {
        self.menusEnabled = menusEnabled
        guard let item = messageMenuItem, let main = NSApp.mainMenu else { return }
        let present = main.items.contains(item)
        if messageMenuShown && !present { main.addItem(item) }
        if !messageMenuShown && present { main.removeItem(item) }
    }

    func checkSoundItem(_ on: Bool) { soundItem?.state = on ? .on : .off }

    private func panel(for d: ClassicDialog) -> DialogPanel {
        if let p = dialogPanels[d.id] { return p }
        let p = DialogPanel(dialog: d, game: game)
        dialogPanels[d.id] = p
        return p
    }

    func showDialogWindow(_ d: ClassicDialog) {
        modalDepth += 1
        releaseCapture()
        let p = panel(for: d)
        p.position(over: view, windowOrigin: game.windowGlobalOrigin)
        p.refresh()
        p.makeKeyAndOrderFront(nil)
    }

    func hideDialogWindow(_ d: ClassicDialog) {
        panel(for: d).orderOut(nil)
        modalDepth = max(0, modalDepth - 1)
        lastTime = 0
        window.makeKeyAndOrderFront(nil)
    }

    func modalDialog(_ d: ClassicDialog) -> Int {
        let p = panel(for: d)
        p.refresh()   // pick up anything drawn since ShowWindow
        let response = NSApp.runModal(for: p)
        p.refresh()
        return response.rawValue
    }

    func pause(ticks: Int) {
        let end = Date().addingTimeInterval(Double(ticks) / 60)
        for p in dialogPanels.values where p.isVisible { p.refresh() }
        CATransaction.flush()
        let remaining = end.timeIntervalSinceNow
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
    }

    func savedHiScore() -> Int { defaults.integer(forKey: "HiScore") }

    func hiScoreChanged(_ hiScore: Int) { defaults.set(hiScore, forKey: "HiScore") }

    func quit() { NSApp.terminate(nil) }

    // MARK: Menus

    private func buildMenus() {
        let main = NSMenu()
        let res = game.resources

        // Apple menu → app menu.
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "StuntCopter")
        let aboutTitle = (try? res.menu(1).items.first?.text) ?? "About Stunt..."
        appMenu.addItem(withTitle: aboutTitle, action: #selector(menuCommand(_:)), keyEquivalent: "").tag =
            StuntCopterGame.appleMenu * 1000 + 1
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide StuntCopter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        // File ▸ Quit /Q lives in the app menu on macOS.
        appMenu.addItem(withTitle: "Quit StuntCopter", action: #selector(menuCommand(_:)), keyEquivalent: "q").tag =
            StuntCopterGame.fileMenu * 1000 + 1
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Options, from MENU 257.
        if let options = try? res.menu(StuntCopterGame.optionMenu) {
            let item = NSMenuItem()
            let menu = NSMenu(title: options.title)
            for (i, it) in options.items.enumerated() {
                let mi = menu.addItem(withTitle: it.text, action: #selector(menuCommand(_:)), keyEquivalent: "")
                mi.tag = StuntCopterGame.optionMenu * 1000 + i + 1
                if i == 0 { soundItem = mi }
            }
            item.submenu = menu
            main.addItem(item)
        }

        // View (new): magnification and full screen.
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        for s in 1...4 {
            let mi = viewMenu.addItem(withTitle: "\(s)× Size", action: #selector(setScale(_:)), keyEquivalent: "\(s)")
            mi.tag = s
        }
        viewMenu.addItem(.separator())
        let fs = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)),
                                  keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        // The "(Backspace to Exit)" message menu, inserted during play.
        if let msg = try? res.menu(StuntCopterGame.messageMenu) {
            let item = NSMenuItem()
            let menu = NSMenu(title: msg.title)
            for it in msg.items { menu.addItem(withTitle: it.text, action: nil, keyEquivalent: "").isEnabled = false }
            menu.autoenablesItems = false
            item.submenu = menu
            messageMenuItem = item
        }

        NSApp.mainMenu = main
    }

    @objc private func menuCommand(_ sender: NSMenuItem) {
        game.DoMenuCommand(sender.tag / 1000, sender.tag % 1000)
        view.refresh()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(menuCommand(_:)) {
            // Quit stays available (a macOS expectation); the rest follow DisableItem.
            return item.tag / 1000 == StuntCopterGame.fileMenu || (menusEnabled && modalDepth == 0)
        }
        if item.action == #selector(setScale(_:)) {
            item.state = (view?.scale == item.tag && !window.styleMask.contains(.fullScreen)) ? .on : .off
            return !window.styleMask.contains(.fullScreen)
        }
        return true
    }
}
