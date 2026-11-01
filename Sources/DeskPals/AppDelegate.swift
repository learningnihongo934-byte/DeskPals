import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let world = World()
    private var pet: Pet!
    private var window: PetWindow!
    private var senses: Senses!
    private var status: NSStatusItem!
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var worldClock = 0.0

    private let sizes: [(String, CGFloat)] = [("Small", 3), ("Medium", 4), ("Large", 6)]
    private let reactions: [(String, String)] = [("New windows & apps", Keys.windows), ("Mouse clicks", Keys.clicks),
                                                 ("Typing", Keys.typing), ("Idle & time of day", Keys.idle)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let d = UserDefaults.standard
        let kind = PetKind.all.first { $0.id == d.string(forKey: Keys.pet) } ?? PetKind.all[0]
        let scale = d.double(forKey: Keys.scale)

        world.refresh()
        pet = Pet(kind: kind, scale: scale > 0 ? scale : 4, world: world)
        pet.dropIn(atX: NSEvent.mouseLocation.x)
        window = PetWindow(pet: pet)
        senses = Senses(pet: pet)
        senses.start()
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
            item.state = k.id == pet.kind.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let call = NSMenuItem(title: "Call \(pet.kind.name) here", action: #selector(callHere), keyEquivalent: "")
        call.target = self
        menu.addItem(call)

        let sizeMenu = NSMenu()
        for (i, (name, s)) in sizes.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.state = s == pet.scale ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let reactMenu = NSMenu()
        for (i, (name, key)) in reactions.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(toggleReaction(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.state = Senses.on(key) ? .on : .off
            reactMenu.addItem(item)
        }
        let reactItem = NSMenuItem(title: "Reacts to", action: nil, keyEquivalent: "")
        reactItem.submenu = reactMenu
        menu.addItem(reactItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DeskPals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func updateIcon() {
        status.button?.image = SpriteSheet.icon(for: pet.kind, points: 18)
        status.button?.toolTip = "\(pet.kind.name) the \(pet.kind.species)"
    }

    @objc private func choosePet(_ sender: NSMenuItem) {
        let k = PetKind.all[sender.tag]
        UserDefaults.standard.set(k.id, forKey: Keys.pet)
        pet.setKind(k)
        updateIcon()
    }

    @objc private func callHere() {
        pet.dropIn(atX: NSEvent.mouseLocation.x)
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        let s = sizes[sender.tag].1
        UserDefaults.standard.set(Double(s), forKey: Keys.scale)
        pet.scale = s
    }

    @objc private func toggleReaction(_ sender: NSMenuItem) {
        let key = reactions[sender.tag].1
        UserDefaults.standard.set(!Senses.on(key), forKey: key)
    }
}
