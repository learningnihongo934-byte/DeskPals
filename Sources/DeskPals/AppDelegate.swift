import AppKit

/// One pet on screen with its window and needs.
final class PetSlot {
    let uid: String
    let pet: Pet
    let window: PetWindow
    let needs: Needs

    init(uid: String, pet: Pet, window: PetWindow, needs: Needs) {
        self.uid = uid
        self.pet = pet
        self.window = window
        self.needs = needs
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let world = World()
    private let settings = SettingsModel()
    private lazy var props = Props(world: world)
    private var slots: [PetSlot] = []
    private var nextHeadID = 4_000_000
    private var settingsWindow: SettingsWindow?
    private var senses: Senses!
    private var status: NSStatusItem!
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var worldClock = 0.0
    private var socialClock = 0.0
    private var clock = 0.0
    private var lastMeet: [String: Double] = [:]

    private var pets: [Pet] { slots.map(\.pet) }
    /// The pet the menu and Settings are about right now.
    private var selected: PetSlot? { slots.first { $0.uid == settings.selectedUID } ?? slots.first }

    func applicationDidFinishLaunching(_ notification: Notification) {
        props.scale = CGFloat(settings.scale)
        world.extraPlatforms = { [weak self] in
            guard let self else { return [] }
            return self.props.platforms() + self.slots.compactMap { $0.pet.headPlatform }
        }
        world.refresh()
        settings.slots.forEach(spawn)
        senses = Senses(pets: { [weak self] in self?.pets ?? [] }, world: world)
        senses.start()
        wireSettings()
        props.onGiftOpened = { [weak self] gift in
            guard let self else { return }
            self.props.remove(gift)
            self.pets.min { abs($0.pos.x - gift.pos.x) < abs($1.pos.x - gift.pos.x) }?.giftOpened()
        }
        buildMenu()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.world.refresh()
            for p in self.pets where !self.world.bounds.contains(p.pos) { p.dropIn(atX: self.world.bounds.midX) }
        }

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Testing aid: launch with DESKPALS_DEBUG=1, then post a distributed notification.
        if ProcessInfo.processInfo.environment["DESKPALS_DEBUG"] == "1" {
            DistributedNotificationCenter.default().addObserver(forName: .init("tech.rennko.deskpals.debug"), object: nil, queue: .main) { [weak self] n in
                guard let self else { return }
                switch n.object as? String ?? "" {
                case "feed": self.feed(self.settings.kind.favorite)
                case "ball": self.throwBall()
                case "bed": self.toggleBed()
                case "jump": self.selected?.pet.superJump()
                case "sleep": self.pets.forEach { $0.fallAsleep() }
                case "settings": self.showSettings()
                case let cmd where cmd.hasPrefix("add:"):
                    if let k = PetKind.all.first(where: { $0.id == cmd.dropFirst(4) }) { self.settings.add(k) }
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
        slots.forEach { $0.needs.save() }
    }

    /// Opening the app again while it runs (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Pets

    private func spawn(_ info: PetSlotInfo) {
        let needs = Needs(petID: info.uid)
        let pet = Pet(kind: SettingsModel.kind(of: info), scale: CGFloat(settings.scale), name: SettingsModel.name(of: info),
                      world: world, needs: needs, props: props)
        pet.accessory = SettingsModel.accessory(of: info)
        pet.headID = nextHeadID
        nextHeadID += 1
        pet.friends = { [weak self] in self?.pets ?? [] }
        pet.dropIn(atX: NSEvent.mouseLocation.x + .random(in: -300...300))
        slots.append(PetSlot(uid: info.uid, pet: pet, window: PetWindow(pet: pet), needs: needs))
    }

    private func despawn(_ uid: String) {
        guard let i = slots.firstIndex(where: { $0.uid == uid }) else { return }
        slots[i].needs.save()
        slots[i].window.orderOut(nil)
        slots.remove(at: i)
    }

    private func wireSettings() {
        settings.needsFor = { [weak self] uid in self?.slots.first { $0.uid == uid }?.needs }
        settings.onAdd = { [weak self] info in self?.spawn(info); self?.updateIcon() }
        settings.onRemove = { [weak self] uid in self?.despawn(uid); self?.updateIcon() }
        settings.onSelect = { [weak self] in self?.updateIcon() }
        settings.onScale = { [weak self] s in
            self?.pets.forEach { $0.scale = s }
            self?.props.scale = s
        }
        settings.onName = { [weak self] uid, n in self?.slots.first { $0.uid == uid }?.pet.name = n }
        settings.onAccessory = { [weak self] uid, a in self?.slots.first { $0.uid == uid }?.pet.accessory = a }
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
        clock += dt
        worldClock += dt
        if worldClock >= 1.0 / 30 {
            worldClock = 0
            senses.newWindows(world.refresh())
        }
        senses.tick(dt)
        let mouse = NSEvent.mouseLocation, pressed = NSEvent.pressedMouseButtons != 0
        for s in slots {
            s.pet.trackCursor(mouse, dt, pressed: pressed)
            s.pet.tick(dt)
        }
        props.tick(dt)
        slots.forEach { $0.window.sync() }
        socialClock += dt
        if socialClock > 0.5 {
            socialClock = 0
            socialize()
        }
    }

    /// Pets that bump into each other say hi, or start a game of tag.
    private func socialize() {
        let pets = self.pets
        guard pets.count > 1 else { return }
        for i in 0..<pets.count {
            for j in (i + 1)..<pets.count {
                let a = pets[i], b = pets[j]
                guard a.isCalm, b.isCalm, abs(a.pos.y - b.pos.y) < 6,
                      abs(a.pos.x - b.pos.x) < max(a.size, b.size) * 1.1 else { continue }
                let key = "\(a.headID)-\(b.headID)"
                guard clock - (lastMeet[key] ?? -1e9) > 90 else { continue }
                lastMeet[key] = clock
                if Double.random(in: 0..<1) < 0.35 {
                    a.runFrom(b)
                    b.chase(a)
                } else {
                    a.greet(b)
                    b.greet(a)
                }
            }
        }
    }

    // MARK: - Care

    /// Drops food from the top of the screen, a little way from the selected pet.
    private func feed(_ f: Food) {
        guard let pet = selected?.pet else { return }
        let x = pet.pos.x + (Bool.random() ? 1 : -1) * .random(in: 140...280)
        props.add(.food(f), at: CGPoint(x: x, y: world.screenTop(at: x) - 60))
    }

    private func throwBall() {
        guard let pet = selected?.pet else { return }
        if let old = props.ball { props.remove(old) }
        let x = pet.pos.x + (Bool.random() ? 1 : -1) * 120
        props.add(.ball, at: CGPoint(x: x, y: pet.pos.y + pet.size * 2), vel: CGVector(dx: .random(in: -500...500), dy: 600))
    }

    private func toggleBed() {
        if let bed = props.bed {
            props.remove(bed)
        } else if let pet = selected?.pet {
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
        let header = item("Your pets", nil)
        header.isEnabled = false
        menu.addItem(header)
        for (i, s) in slots.enumerated() {
            let info = PetSlotInfo(uid: s.uid, kindID: s.pet.kind.id)
            let it = item("\(SettingsModel.name(of: info)) · Lv \(s.needs.level) · Full \(Int(s.needs.fullness * 100))%",
                          #selector(selectPet(_:)), tag: i)
            it.image = SpriteSheet.icon(for: s.pet.kind, points: 18)
            it.state = s.uid == selected?.uid ? .on : .off
            menu.addItem(it)
        }

        let addMenu = NSMenu()
        for (i, k) in PetKind.all.enumerated() {
            let it = item("\(k.name) the \(k.species)", #selector(addPet(_:)), tag: i)
            it.image = SpriteSheet.icon(for: k, points: 18)
            addMenu.addItem(it)
        }
        let addItem = item("Add a pet", nil)
        addItem.submenu = addMenu
        menu.addItem(addItem)
        if slots.count > 1, let s = selected {
            menu.addItem(item("Remove \(s.pet.name)", #selector(removeSelected)))
        }
        menu.addItem(.separator())

        let name = settings.displayName
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
        menu.addItem(item("Call \(name) here", #selector(callHere)))
        menu.addItem(item("Call everyone here", #selector(callEveryone)))

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
        guard let pet = selected?.pet else { return }
        status.button?.image = SpriteSheet.icon(for: pet.kind, points: 18)
        status.button?.toolTip = slots.count == 1 ? "\(settings.displayName) the \(pet.kind.species)" : "\(slots.count) pets"
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(model: settings) }
        settingsWindow?.show()
    }

    @objc private func selectPet(_ sender: NSMenuItem) { settings.selectedUID = slots[sender.tag].uid }
    @objc private func addPet(_ sender: NSMenuItem) { settings.add(PetKind.all[sender.tag]) }
    @objc private func removeSelected() { if let s = selected { settings.remove(s.uid) } }
    @objc private func feedItem(_ sender: NSMenuItem) { feed(Food.allCases[sender.tag]) }
    @objc private func ballItem() { throwBall() }
    @objc private func bedItem() { toggleBed() }
    @objc private func callHere() { selected?.pet.dropIn(atX: NSEvent.mouseLocation.x) }
    @objc private func chooseSize(_ sender: NSMenuItem) { settings.scale = SettingsModel.sizes[sender.tag].scale }

    @objc private func callEveryone() {
        let x = NSEvent.mouseLocation.x
        for (i, p) in pets.enumerated() { p.dropIn(atX: x + CGFloat(i - pets.count / 2) * p.size * 1.2) }
    }

    @objc private func toggleReaction(_ sender: NSMenuItem) {
        let key = SettingsModel.reactions[sender.tag].key
        settings.reacts[key] = !(settings.reacts[key] ?? true)
    }
}
