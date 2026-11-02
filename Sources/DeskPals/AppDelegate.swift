import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let world = World()
    private let settings = SettingsModel()
    private lazy var props = Props(world: world)
    private var needs: Needs!
    private var settingsWindow: SettingsWindow?
    private var pet: Pet!
    private var window: PetWindow!
    private var senses: Senses!
    private var status: NSStatusItem!
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var worldClock = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        needs = Needs(petID: settings.petID)
        props.scale = CGFloat(settings.scale)
        world.extraPlatforms = { [weak self] in self?.props.platforms() ?? [] }
        world.refresh()
        pet = Pet(kind: settings.kind, scale: CGFloat(settings.scale), name: settings.displayName,
                  world: world, needs: needs, props: props)
        pet.accessory = settings.accessory
        pet.dropIn(atX: NSEvent.mouseLocation.x)
        window = PetWindow(pet: pet)
        senses = Senses(pet: pet, world: world)
        senses.start()
        wireSettings()
        props.onGiftOpened = { [weak self] gift in
            self?.props.remove(gift)
            self?.pet.giftOpened()
        }
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

        // Testing aid: `DESKPALS_DEBUG=1 DeskPals` then
        // `osascript -e 'tell application "System Events"…'` isn't needed; post a distributed notification instead.
        if ProcessInfo.processInfo.environment["DESKPALS_DEBUG"] == "1" {
            DistributedNotificationCenter.default().addObserver(forName: .init("tech.rennko.deskpals.debug"), object: nil, queue: .main) { [weak self] n in
                guard let self else { return }
                switch n.object as? String ?? "" {
                case "feed": self.feed(self.settings.kind.favorite)
                case "ball": self.throwBall()
                case "bed": self.toggleBed()
                case "jump": self.pet.superJump()
                case "sleep": self.pet.fallAsleep()
                case "settings": self.showSettings()
                default: break
                }
            }
        }

        if !UserDefaults.standard.bool(forKey: Keys.launchedBefore) {
            UserDefaults.standard.set(true, forKey: Keys.launchedBefore)
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        needs.save()
    }

    /// Opening the app again while it runs (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func wireSettings() {
        settings.needs = needs
        settings.onPet = { [weak self] k in
            guard let self else { return }
            self.needs.switchTo(k.id)
            self.pet.setKind(k, name: self.settings.displayName)
            self.pet.accessory = self.settings.accessory
            self.updateIcon()
        }
        settings.onScale = { [weak self] s in self?.pet.scale = s; self?.props.scale = s }
        settings.onName = { [weak self] n in self?.pet.name = n }
        settings.onAccessory = { [weak self] a in self?.pet.accessory = a }
        settings.onCall = { [weak self] in self?.callHere() }
        settings.onReactionsChanged = { [weak self] in self?.senses.refreshDock() }
        settings.onFeed = { [weak self] f in self?.feed(f) }
        settings.onBall = { [weak self] in self?.throwBall() }
        settings.onBed = { [weak self] in self?.toggleBed() }
        settings.hasBed = { [weak self] in self?.props.bed != nil }
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
        pet.trackCursor(NSEvent.mouseLocation, dt, pressed: NSEvent.pressedMouseButtons != 0)
        pet.tick(dt)
        props.tick(dt)
        window.sync()
    }

    // MARK: - Care

    /// Drops food from the top of the screen, a little way from the pet.
    private func feed(_ f: Food) {
        let x = pet.pos.x + (Bool.random() ? 1 : -1) * .random(in: 140...280)
        props.add(.food(f), at: CGPoint(x: x, y: world.screenTop(at: x) - 60))
    }

    private func throwBall() {
        if let old = props.ball { props.remove(old) }
        let x = pet.pos.x + (Bool.random() ? 1 : -1) * 120
        props.add(.ball, at: CGPoint(x: x, y: pet.pos.y + pet.size * 2), vel: CGVector(dx: .random(in: -500...500), dy: 600))
    }

    private func toggleBed() {
        if let bed = props.bed {
            props.remove(bed)
        } else {
            let x = pet.pos.x + (pet.pos.x > world.bounds.midX ? -1 : 1) * 220
            props.add(.bed, at: CGPoint(x: x, y: world.screenTop(at: x) - 80))
        }
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

    private func item(_ title: String, _ action: Selector?, key: String = "", tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = item("\(settings.displayName) · Level \(needs.level) · Full \(Int(needs.fullness * 100))% · Happy \(Int(needs.happiness * 100))%", nil)
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        for (i, k) in PetKind.all.enumerated() {
            let name = UserDefaults.standard.string(forKey: Keys.name(k.id)) ?? k.name
            let it = item("\(name) the \(k.species)", #selector(choosePet(_:)), tag: i)
            it.image = SpriteSheet.icon(for: k, points: 18)
            it.state = k.id == settings.petID ? .on : .off
            menu.addItem(it)
        }
        menu.addItem(.separator())

        let feedMenu = NSMenu()
        for (i, f) in Food.allCases.enumerated() {
            let it = item(f == settings.kind.favorite ? "\(f.title) ★" : f.title, #selector(feedItem(_:)), tag: i)
            it.image = SpriteSheet.icon(f.image, points: 18)
            feedMenu.addItem(it)
        }
        let feedItem = item("Feed", nil)
        feedItem.submenu = feedMenu
        menu.addItem(feedItem)
        menu.addItem(item("Throw a ball", #selector(ballItem)))
        menu.addItem(item(props.bed == nil ? "Place a bed" : "Remove the bed", #selector(bedItem)))
        menu.addItem(item("Call \(settings.displayName) here", #selector(callHere)))

        let sizeMenu = NSMenu()
        for (i, size) in SettingsModel.sizes.enumerated() {
            let it = item(size.name, #selector(chooseSize(_:)), tag: i)
            it.state = size.scale == settings.scale ? .on : .off
            sizeMenu.addItem(it)
        }
        let sizeItem = item("Size", nil)
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let reactMenu = NSMenu()
        for (i, r) in SettingsModel.reactions.enumerated() {
            let it = item(r.name, #selector(toggleReaction(_:)), tag: i)
            it.state = settings.reacts[r.key] ?? true ? .on : .off
            reactMenu.addItem(it)
        }
        let reactItem = item("Reacts to", nil)
        reactItem.submenu = reactMenu
        menu.addItem(reactItem)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(NSMenuItem(title: "Quit DeskPals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func updateIcon() {
        status.button?.image = SpriteSheet.icon(for: pet.kind, points: 18)
        status.button?.toolTip = "\(settings.displayName) the \(pet.kind.species)"
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(model: settings) }
        settingsWindow?.show()
    }

    @objc private func choosePet(_ sender: NSMenuItem) { settings.petID = PetKind.all[sender.tag].id }
    @objc private func feedItem(_ sender: NSMenuItem) { feed(Food.allCases[sender.tag]) }
    @objc private func ballItem() { throwBall() }
    @objc private func bedItem() { toggleBed() }
    @objc private func callHere() { pet.dropIn(atX: NSEvent.mouseLocation.x) }
    @objc private func chooseSize(_ sender: NSMenuItem) { settings.scale = SettingsModel.sizes[sender.tag].scale }

    @objc private func toggleReaction(_ sender: NSMenuItem) {
        let key = SettingsModel.reactions[sender.tag].key
        settings.reacts[key] = !(settings.reacts[key] ?? true)
    }
}
