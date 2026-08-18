import AppKit
import Carbon.HIToolbox

private let takeControlHotKeySignature: OSType = 0x4852_5345
private let takeControlHotKeyIdentifier: UInt32 = 1

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let horseScene = HorseScene()
    private let inputController = InputController()
    private var horseController = HorseController()

    private var overlayWindow: HorseOverlayWindow?
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var previousFrameTime: TimeInterval?
    private var takeControlHotKey: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?
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
        registerTakeControlHotKey()

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

        takeControl()
    }

    func stop() {
        unregisterTakeControlHotKey()
        updateTimer?.invalidate()
        updateTimer = nil
        inputController.stop()
        NotificationCenter.default.removeObserver(self)
        overlayWindow?.orderOut(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        takeControl()
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

        let takeControlItem = menu.addItem(
            withTitle: "Take Control",
            action: #selector(takeControl),
            keyEquivalent: "h"
        )
        takeControlItem.keyEquivalentModifierMask = [.control, .shift]
        takeControlItem.target = self

        menu.addItem(.separator())

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
            title: "Control+Shift+H takes control · WASD / arrows move · hold Control+Option for mouse",
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

    @objc private func takeControl() {
        guard isHorseVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow?.makeKeyAndOrderFront(nil)
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

    private func registerTakeControlHotKey() {
        guard takeControlHotKey == nil, hotKeyEventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard
                    parameterStatus == noErr,
                    hotKeyID.signature == takeControlHotKeySignature,
                    hotKeyID.id == takeControlHotKeyIdentifier
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<AppController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.takeControl()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyEventHandler
        )
        guard handlerStatus == noErr else {
            NSLog("Horse could not install its take-control shortcut handler: %d", handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: takeControlHotKeySignature,
            id: takeControlHotKeyIdentifier
        )
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(controlKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &takeControlHotKey
        )
        guard hotKeyStatus == noErr else {
            if let hotKeyEventHandler {
                RemoveEventHandler(hotKeyEventHandler)
            }
            hotKeyEventHandler = nil
            NSLog("Horse could not register Control+Shift+H: %d", hotKeyStatus)
            return
        }
    }

    private func unregisterTakeControlHotKey() {
        if let takeControlHotKey {
            UnregisterEventHotKey(takeControlHotKey)
        }
        takeControlHotKey = nil

        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
        }
        hotKeyEventHandler = nil
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
