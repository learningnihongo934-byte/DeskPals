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
    private var env: Environment!
    private var games: MiniGames!
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
        Pet.chaos = settings.chaos
        settings.slots.forEach { spawn($0, isNew: false) }
        props.restorePlaces()
        env = Environment(world: world, pets: { [weak self] in self?.pets ?? [] })
        FX.shared.rebuild()
        props.frozen = { FX.shared.isFrozen(point: $0) }
        games = MiniGames(world: world, props: props, selected: { [weak self] in self?.selected?.pet })
        Economy.shared.onToast = { [weak self] msg in
            Sound.shared.play(.coin)
            self?.selected?.pet.say(msg, 2.4)
        }
        Economy.shared.atLeast(.adopted, slots.count)
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
            self.env.rebuildOverlays()
            FX.shared.rebuild()
            for p in self.pets where !self.world.bounds.contains(p.pos) { p.dropIn(atX: self.world.bounds.midX) }
        }

        if WatchParty.shared.enabled {
            WatchParty.shared.checkOllama()
            if !WatchParty.shared.hasScreenAccess { WatchParty.shared.requestScreenAccess() }
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
                case "coins": Economy.shared.earn(1000, "test coins")
                case let cmd where cmd.hasPrefix("buy:"):
                    if let it = ShopItem.find(String(cmd.dropFirst(4))) { Economy.shared.buy(it) }
                case let cmd where cmd.hasPrefix("place:"):
                    if let p = Place(rawValue: String(cmd.dropFirst(6))) { self.togglePlace(p) }
                case let cmd where cmd.hasPrefix("weather:"):
                    self.env.override = WeatherKind(rawValue: String(cmd.dropFirst(8)))
                case let cmd where cmd.hasPrefix("theme:"):
                    self.env.theme = Theme(rawValue: String(cmd.dropFirst(6))) ?? .none
                case let cmd where cmd.hasPrefix("game:"):
                    if let g = MiniGames.Kind(rawValue: String(cmd.dropFirst(5))) { self.games.start(g) }
                case "stopgame": self.games.stop("stopped")
                case "status":
                    for s in self.slots { NSLog("DeskPals pet \(s.uid) \(s.pet.state) pos=\(Int(s.pet.pos.x)),\(Int(s.pet.pos.y)) target=\(s.pet.gameTarget.map { Int($0) } ?? -1) mouse=\(Int(NSEvent.mouseLocation.x)) selected=\(s.uid == self.selected?.uid)") }
                case "power": self.selected?.pet.powerMove()
                case let cmd where cmd.hasPrefix("power:"):
                    self.slots.first { $0.uid == String(cmd.dropFirst(6)) }?.pet.powerMove()
                case let cmd where cmd.hasPrefix("bestie:"):
                    let ps = self.pets
                    if let a = ps.first(where: { $0.kind.bestie != nil }), let b = ps.first(where: { $0.kind.id == a.kind.bestie }) {
                        switch cmd.dropFirst(7) {
                        case "hug": Rivalry.hangOut(a, b, hug: true)
                        case "sit": Rivalry.hangOut(a, b, hug: false)
                        case "dance": Rivalry.danceTogether(a, b)
                        case "food": Rivalry.shareFood(a, b)
                        default: Rivalry.piggyback(a, b)
                        }
                    }
                case let cmd where cmd.hasPrefix("progress:"):
                    let parts = cmd.split(separator: ":")
                    if parts.count == 3, let s = self.slots.first(where: { $0.uid == String(parts[1]) }), let n = Int(parts[2]) {
                        s.pet.progressStep = n
                        s.pet.progressClock = s.pet.kind.progressInterval - 1
                    }
                case "noworld": self.env.clearWorld()
                case "noplaces": self.noPlaces()
                case "chase":
                    let ps = self.pets
                    if let prey = ps.first(where: { $0.kind.power == .vanish }), let hunter = ps.first(where: { $0.kind.id == prey.kind.rival }) {
                        Rivalry.chase(hunter, prey)
                    }
                case let cmd where cmd.hasPrefix("rival:"):
                    let ps = self.pets
                    if let a = ps.first(where: { $0.kind.rival != nil && $0.kind.dropArt != nil }) ?? ps.first(where: { $0.kind.rival != nil }), let b = ps.first(where: { $0.kind.id == a.kind.rival }) {
                        switch cmd.dropFirst(6) {
                        case "clash": Rivalry.faceOff(a, b) { Rivalry.clash(a, b) }
                        case "duel": Rivalry.faceOff(a, b) { Rivalry.timeStopDuel(a, b) }
                        case "drop": Rivalry.faceOff(a, b) { Rivalry.dropOn(a, b) }
                        case "pose": Rivalry.faceOff(a, b) { Rivalry.strikePoses(a, b) }
                        case "chase": Rivalry.chase(a.kind.power == .vanish ? b : a, a.kind.power == .vanish ? a : b)
                        default: Rivalry.truce(a, b)
                        }
                    }
                case let cmd where cmd.hasPrefix("remove:"):
                    self.settings.remove(String(cmd.dropFirst(7)))
                case "peek": _ = self.selected?.pet.peekFromCorner()
                case "visit": _ = self.selected?.pet.visitPlace()
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
        props.savePlaces()
    }

    /// Opening the app again while it runs (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Pets

    private func spawn(_ info: PetSlotInfo, isNew: Bool) {
        let needs = Needs(petID: info.uid)
        if isNew, needs.bond < 1, !SettingsModel.kind(of: info).startsGrown {   // a brand-new pet starts as a baby
            needs.stage = 0
            needs.save()
        }
        let pet = Pet(kind: SettingsModel.kind(of: info), scale: CGFloat(settings.scale), name: SettingsModel.name(of: info),
                      world: world, needs: needs, props: props)
        pet.accessory = SettingsModel.accessory(of: info)
        pet.headID = nextHeadID
        nextHeadID += 1
        pet.friends = { [weak self] in self?.pets ?? [] }
        pet.growth = [0.6, 0.8, 1][min(needs.stage, 2)]
        needs.onGrow = { [weak pet] stage in pet?.grewUp(to: stage) }
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
        settings.onAdd = { [weak self] info in
            guard let self else { return }
            self.spawn(info, isNew: true)
            self.updateIcon()
            Economy.shared.atLeast(.adopted, self.slots.count)
        }
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
        settings.env = env
        settings.onPlace = { [weak self] p in self?.togglePlace(p) }
        settings.hasPlace = { [weak self] p in self?.props.place(p) != nil }
        settings.onGame = { [weak self] g in self?.games.start(g) }
        settings.onPower = { [weak self] in self?.selected?.pet.powerMove() }
        settings.onNoPlaces = { [weak self] in self?.noPlaces() }
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
        WatchParty.shared.tick(pets: pets, video: senses.currentVideo, clock: now)
        env.tick(dt)
        games.tick(dt)
        let mouse = NSEvent.mouseLocation, pressed = NSEvent.pressedMouseButtons != 0
        for s in slots where !FX.shared.isFrozen(s.pet) {   // time stop: frozen pets skip their turn
            s.pet.trackCursor(mouse, dt, pressed: pressed)
            s.pet.tick(dt)
        }
        FX.shared.tick(dt)
        props.tick(dt)
        Bubble.stack(pets)
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
        Rivalry.tick(pets, clock: clock)
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

    private func togglePlace(_ place: Place) {
        if let p = props.place(place) {
            props.remove(p)
        } else if Economy.shared.owned.contains(place.shopID), let pet = selected?.pet {
            // an open spot near the pet, not on top of another place
            let taken = props.places.map(\.rect)
            let tries = (0..<40).map { _ in clamp(pet.pos.x + .random(in: -900...900), world.bounds.minX + 140, world.bounds.maxX - 140) }
            let x = tries.first { x in !taken.contains { abs($0.midX - x) < $0.width / 2 + 150 } } ?? tries[0]
            props.add(.place(place), at: CGPoint(x: x, y: world.screenTop(at: x) - 120))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.props.savePlaces() }
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
        let coins = item("🪙 \(Economy.shared.coins) coins · \(Economy.shared.quests.filter(\.done).count)/\(Economy.shared.quests.count) quests done", nil)
        coins.isEnabled = false
        menu.addItem(coins)
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
        menu.addItem(item("Power up! ⚡ (\(name))", #selector(powerUp)))

        let gameMenu = NSMenu()
        for (i, g) in MiniGames.Kind.allCases.enumerated() { gameMenu.addItem(item(g.title, #selector(playGame(_:)), tag: i)) }
        if games.isRunning { gameMenu.addItem(.separator()); gameMenu.addItem(item("Stop game", #selector(stopGame))) }
        let gameItem = item("Play", nil)
        gameItem.submenu = gameMenu
        menu.addItem(gameItem)

        let placeMenu = NSMenu()
        for (i, p) in Place.allCases.enumerated() {
            let owned = Economy.shared.owned.contains(p.shopID)
            let it = item(owned ? p.title : "\(p.title) (in the Shop)", owned ? #selector(placeItem(_:)) : nil, tag: i)
            it.isEnabled = owned
            it.state = props.place(p) != nil ? .on : .off
            it.image = SpriteSheet.icon(p.image(), points: 18)
            placeMenu.addItem(it)
        }
        placeMenu.insertItem(.separator(), at: 0)
        placeMenu.insertItem(item("None (put all away)", #selector(noPlaces)), at: 0)
        let placeItem = item("Places", nil)
        placeItem.submenu = placeMenu
        menu.addItem(placeItem)

        let worldMenu = NSMenu()
        for (i, th) in Theme.allCases.enumerated() {
            let owned = th.shopID.map { Economy.shared.owned.contains($0) } ?? true
            let it = item(th.title + (owned ? "" : " (in the Shop)"), owned ? #selector(themeItem(_:)) : nil, tag: i)
            it.isEnabled = owned
            it.state = env.theme == th ? .on : .off
            worldMenu.addItem(it)
        }
        worldMenu.addItem(.separator())
        let off = item("Weather: off", #selector(weatherOff))
        off.state = env.mode == .off && env.override == nil ? .on : .off
        worldMenu.addItem(off)
        let auto = item("Weather: automatic", #selector(weatherItem(_:)), tag: -1)
        auto.state = env.override == nil ? .on : .off
        worldMenu.addItem(auto)
        for (i, w) in WeatherKind.allCases.enumerated() {
            let it = item("Weather: \(w.title)", #selector(weatherItem(_:)), tag: i)
            it.state = env.override == w ? .on : .off
            worldMenu.addItem(it)
        }
        let worldItem = item("World", nil)
        worldItem.submenu = worldMenu
        menu.addItem(worldItem)

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
        let party = item("Watch party (AI reactions)", #selector(toggleParty))
        party.state = WatchParty.shared.enabled ? .on : .off
        menu.addItem(party)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(NSMenuItem(title: "Quit DeskPals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func updateIcon() {
        guard let pet = selected?.pet else { return }
        status.button?.image = SpriteSheet.icon(for: pet.kind, points: 18)
        status.button?.toolTip = slots.count == 1 ? "\(settings.displayName) the \(pet.kind.species)" : "\(slots.count) pets"
    }

    @objc private func toggleParty() {
        WatchParty.shared.enabled.toggle()
        if WatchParty.shared.enabled, !WatchParty.shared.hasScreenAccess { WatchParty.shared.requestScreenAccess() }
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

    @objc private func playGame(_ sender: NSMenuItem) { games.start(MiniGames.Kind.allCases[sender.tag]) }
    @objc private func stopGame() { games.stop("stopped") }
    @objc private func powerUp() { selected?.pet.powerMove() }
    @objc private func placeItem(_ sender: NSMenuItem) { togglePlace(Place.allCases[sender.tag]) }
    @objc private func themeItem(_ sender: NSMenuItem) {
        let th = Theme.allCases[sender.tag]
        if th == .none { env.clearWorld() } else { env.theme = th }
    }
    @objc private func weatherOff() { env.mode = .off; env.override = nil }
    @objc private func noPlaces() {
        props.places.forEach(props.remove)
        props.savePlaces()
    }
    @objc private func weatherItem(_ sender: NSMenuItem) {
        env.override = sender.tag < 0 ? nil : WeatherKind.allCases[sender.tag]
    }

    @objc private func callEveryone() {
        let x = NSEvent.mouseLocation.x
        for (i, p) in pets.enumerated() { p.dropIn(atX: x + CGFloat(i - pets.count / 2) * p.size * 1.2) }
    }

    @objc private func toggleReaction(_ sender: NSMenuItem) {
        let key = SettingsModel.reactions[sender.tag].key
        settings.reacts[key] = !(settings.reacts[key] ?? true)
    }
}
