import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let world = World()
    private let settings = SettingsModel()
    private var settingsWindow: SettingsWindow?
    private var pet: Pet!
    private var window: PetWindow!
    private var senses: Senses!
    private var status: NSStatusItem!
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var worldClock = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        world.refresh()
        pet = Pet(kind: settings.kind, scale: CGFloat(settings.scale), world: world)
        pet.dropIn(atX: NSEvent.mouseLocation.x)
        window = PetWindow(pet: pet)
        senses = Senses(pet: pet)
        senses.start()

        settings.onPet = { [weak self] k in self?.pet.setKind(k); self?.updateIcon() }
        settings.onScale = { [weak self] s in self?.pet.scale = s }
        settings.onCall = { [weak self] in self?.callHere() }
        buildMenu()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.world.refresh()
            if !self.world.bounds.contains(self.pet.pos) { self.pet.dropIn(atX: self.world.bounds.midX) }
        }

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if !UserDefaults.standard.bool(forKey: Keys.launchedBefore) {
            UserDefaults.standard.set(true, forKey: Keys.launchedBefore)
            showSettings()
        }
    }

    /// Opening the app again while it runs (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 1.0 / 20)
        last = now
        worldClock += dt
        if worldClock >= 1.0 / 30 {
            worldClock = 0
            senses.newWindows(world.refresh())
        }
        senses.tick(dt)
        pet.tick(dt)
        window.sync()
    }

    // MARK: - Menu bar

    private func buildMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        status.menu = menu
        updateIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (i, k) in PetKind.all.enumerated() {
            let item = NSMenuItem(title: "\(k.name) the \(k.species)", action: #selector(choosePet(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.image = SpriteSheet.icon(for: k, points: 18)
            item.state = k.id == settings.petID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let call = NSMenuItem(title: "Call \(pet.kind.name) here", action: #selector(callHere), keyEquivalent: "")
        call.target = self
        menu.addItem(call)

        let sizeMenu = NSMenu()
        for (i, size) in SettingsModel.sizes.enumerated() {
            let item = NSMenuItem(title: size.name, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.state = size.scale == settings.scale ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let reactMenu = NSMenu()
        for (i, r) in SettingsModel.reactions.enumerated() {
            let item = NSMenuItem(title: r.name, action: #selector(toggleReaction(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.state = settings.reacts[r.key] ?? true ? .on : .off
            reactMenu.addItem(item)
        }
        let reactItem = NSMenuItem(title: "Reacts to", action: nil, keyEquivalent: "")
        reactItem.submenu = reactMenu
        menu.addItem(reactItem)

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(NSMenuItem(title: "Quit DeskPals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func updateIcon() {
        status.button?.image = SpriteSheet.icon(for: pet.kind, points: 18)
        status.button?.toolTip = "\(pet.kind.name) the \(pet.kind.species)"
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(model: settings) }
        settingsWindow?.show()
    }

    @objc private func choosePet(_ sender: NSMenuItem) {
        settings.petID = PetKind.all[sender.tag].id
    }

    @objc private func callHere() {
        pet.dropIn(atX: NSEvent.mouseLocation.x)
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        settings.scale = SettingsModel.sizes[sender.tag].scale
    }

    @objc private func toggleReaction(_ sender: NSMenuItem) {
        let key = SettingsModel.reactions[sender.tag].key
        settings.reacts[key] = !(settings.reacts[key] ?? true)
    }
}
