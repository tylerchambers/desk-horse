import AppKit

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let horseScene = HorseScene()
    private let inputController = InputController()
    private var horseController = HorseController()

    private var overlayWindow: HorseOverlayWindow?
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var previousFrameTime: TimeInterval?
    private var selectedDisplayID: NSNumber?
    private var isHorseVisible = true

    private weak var visibilityMenuItem: NSMenuItem?
    private weak var pixelatedMenuItem: NSMenuItem?
    private weak var alwaysOnTopMenuItem: NSMenuItem?
    private weak var displayMenuItem: NSMenuItem?

    func start() {
        guard let initialScreen = NSScreen.main ?? NSScreen.screens.first else {
            fatalError("Horse requires an attached display")
        }

        selectedDisplayID = displayID(for: initialScreen)
        createOverlay(on: initialScreen)
        createStatusItem()

        inputController.onInputActivityChanged = { [weak self] in
            self?.updateClockActivity()
        }
        inputController.onEscape = { [weak self] in
            self?.overlayWindow?.makeKey()
        }
        inputController.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        NSApp.activate(ignoringOtherApps: true)
        overlayWindow?.makeKeyAndOrderFront(nil)
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        inputController.stop()
        NotificationCenter.default.removeObserver(self)
        overlayWindow?.orderOut(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard isHorseVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow?.makeKeyAndOrderFront(nil)
    }

    private func createOverlay(on screen: NSScreen) {
        let window = HorseOverlayWindow(screen: screen)
        window.contentView = HorseOverlayView(scene: horseScene)
        window.orderFrontRegardless()
        overlayWindow = window
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "HORSE"
        item.button?.toolTip = "Horse"

        let menu = NSMenu(title: "Horse")
        menu.delegate = self

        let visibilityItem = menu.addItem(
            withTitle: "Hide Horse",
            action: #selector(toggleHorseVisibility),
            keyEquivalent: "h"
        )
        visibilityItem.keyEquivalentModifierMask = [.command, .shift]
        visibilityItem.target = self
        visibilityMenuItem = visibilityItem

        let resetItem = menu.addItem(
            withTitle: "Reset Horse",
            action: #selector(resetHorse),
            keyEquivalent: "r"
        )
        resetItem.keyEquivalentModifierMask = [.command, .shift]
        resetItem.target = self

        menu.addItem(.separator())

        let displayItem = NSMenuItem(title: "Select Display", action: nil, keyEquivalent: "")
        menu.addItem(displayItem)
        displayMenuItem = displayItem
        rebuildDisplayMenu()

        let pixelatedItem = menu.addItem(
            withTitle: "1997 Graphics",
            action: #selector(togglePixelatedRendering),
            keyEquivalent: ""
        )
        pixelatedItem.target = self
        pixelatedItem.state = horseScene.pixelatedRendering ? .on : .off
        pixelatedMenuItem = pixelatedItem

        let topItem = menu.addItem(
            withTitle: "Always on Top",
            action: #selector(toggleAlwaysOnTop),
            keyEquivalent: ""
        )
        topItem.target = self
        topItem.state = .on
        alwaysOnTopMenuItem = topItem

        menu.addItem(.separator())

        let controlsItem = NSMenuItem(
            title: "WASD / arrows move · hold Control+Option for mouse",
            action: nil,
            keyEquivalent: ""
        )
        controlsItem.isEnabled = false
        menu.addItem(controlsItem)

        menu.addItem(.separator())

        let quitItem = menu.addItem(
            withTitle: "Quit Horse",
            action: #selector(quitHorse),
            keyEquivalent: "q"
        )
        quitItem.target = self

        item.menu = menu
        statusItem = item
    }

    private func rebuildDisplayMenu() {
        let displayMenu = NSMenu(title: "Select Display")

        for (index, screen) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(
                title: screen.localizedName,
                action: #selector(selectDisplay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = index
            item.state = displayID(for: screen) == selectedDisplayID ? .on : .off
            displayMenu.addItem(item)
        }

        displayMenuItem?.submenu = displayMenu
    }

    @objc private func toggleHorseVisibility() {
        isHorseVisible.toggle()
        visibilityMenuItem?.title = isHorseVisible ? "Hide Horse" : "Show Horse"

        if isHorseVisible {
            overlayWindow?.orderFrontRegardless()
        } else {
            inputController.releaseAllInput()
            overlayWindow?.orderOut(nil)
        }
        updateClockActivity()
    }

    @objc private func resetHorse() {
        horseController.reset()
        horseScene.apply(horseController.state)
    }

    @objc private func togglePixelatedRendering() {
        horseScene.pixelatedRendering.toggle()
        pixelatedMenuItem?.state = horseScene.pixelatedRendering ? .on : .off
    }

    @objc private func toggleAlwaysOnTop() {
        let enabled = alwaysOnTopMenuItem?.state != .on
        alwaysOnTopMenuItem?.state = enabled ? .on : .off
        overlayWindow?.level = enabled ? .floating : .normal
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard
            let index = sender.representedObject as? Int,
            NSScreen.screens.indices.contains(index)
        else { return }

        let screen = NSScreen.screens[index]
        selectedDisplayID = displayID(for: screen)
        overlayWindow?.setFrame(screen.frame, display: true)
        rebuildDisplayMenu()
    }

    @objc private func quitHorse() {
        NSApp.terminate(nil)
    }

    @objc private func updateFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        defer { previousFrameTime = now }
        guard let previousFrameTime else { return }

        let input = inputController.currentState()
        horseController.update(input: input, deltaTime: Float(now - previousFrameTime))
        horseScene.apply(horseController.state)

        if !inputController.hasContinuousInput {
            updateClockActivity()
        }
    }

    private func updateClockActivity() {
        let shouldRun = isHorseVisible && inputController.hasContinuousInput

        if shouldRun, updateTimer == nil {
            previousFrameTime = ProcessInfo.processInfo.systemUptime
            let timer = Timer(
                timeInterval: 1.0 / 60.0,
                target: self,
                selector: #selector(updateFrame),
                userInfo: nil,
                repeats: true
            )
            RunLoop.main.add(timer, forMode: .common)
            updateTimer = timer
        } else if !shouldRun {
            updateTimer?.invalidate()
            updateTimer = nil
            previousFrameTime = nil
        }
    }

    @objc private func screenConfigurationChanged() {
        let screens = NSScreen.screens
        let selectedScreen = screens.first { displayID(for: $0) == selectedDisplayID }
            ?? NSScreen.main
            ?? screens.first

        guard let selectedScreen else { return }
        selectedDisplayID = displayID(for: selectedScreen)
        overlayWindow?.setFrame(selectedScreen.frame, display: true)
        rebuildDisplayMenu()
    }

    @objc private func applicationDidResignActive() {
        inputController.releaseAllInput()
    }

    private func displayID(for screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
}
