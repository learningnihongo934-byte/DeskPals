import AppKit

/// Three quick games with your pets: catch falling treats, keep the ball in the air, and hide & seek.
final class MiniGames {
    enum Kind: String, CaseIterable {
        case treatRain, keepyUppy, hideAndSeek
        var title: String { ["treatRain": "Treat Rain", "keepyUppy": "Keepy-Uppy", "hideAndSeek": "Hide & Seek"][rawValue]! }
        var how: String {
            switch self {
            case .treatRain: return "Move your mouse left and right to steer your pet under the falling treats. 30 seconds."
            case .keepyUppy: return "Click the ball to bounce it up. Don't let it touch the ground!"
            case .hideAndSeek: return "Your pet hides behind one of your windows. Find it and click it within a minute."
            }
        }
    }

    private struct Treat {
        var pos: CGPoint
        var vy: CGFloat
        let food: Food
    }

    private let world: World
    private let props: Props
    private let selected: () -> Pet?
    private(set) var active: Kind?
    private var pet: Pet?
    private var score = 0
    private var timeLeft = 0.0
    private var spawnClock = 0.0
    private var treats: [Treat] = []
    private var ball: Prop?
    private var ballLanded = 0.0
    private var hud: GameHUD?
    private var overlay: GameOverlay?

    init(world: World, props: Props, selected: @escaping () -> Pet?) {
        self.world = world
        self.props = props
        self.selected = selected
    }

    var isRunning: Bool { active != nil }

    func start(_ kind: Kind) {
        stop(nil)
        guard let pet = selected() else { return }
        self.pet = pet
        active = kind
        score = 0
        hud = GameHUD(screen: NSScreen.screens.first { $0.frame.contains(pet.pos) } ?? NSScreen.main) { [weak self] in self?.stop("stopped") }
        Sound.shared.play(.ding)
        switch kind {
        case .treatRain:
            timeLeft = 30
            treats = []
            pet.enterGame(at: NSEvent.mouseLocation.x)
            pet.say("feed me!", 1.5)
            overlay = GameOverlay(screen: NSScreen.screens.first { $0.frame.contains(pet.pos) } ?? NSScreen.main!) { [weak self] in
                guard let self, let pet = self.pet else { return [] }
                return self.treats.map { ($0.food.image, $0.pos, pet.px) }
            }
        case .keepyUppy:
            timeLeft = 0
            ballLanded = 0
            let b = props.add(.ball, at: CGPoint(x: pet.pos.x, y: pet.pos.y + pet.size * 3), vel: CGVector(dx: 0, dy: 300))
            ball = b
            props.onClick = { [weak self] p in
                guard let self, p === self.ball else { return false }
                p.groundID = nil
                p.vel = CGVector(dx: .random(in: -260...260), dy: 1150)
                self.score += 1
                Sound.shared.play(.pop, pitch: 1 + Double(min(self.score, 20)) * 0.03)
                if self.score % 5 == 0 { self.pet?.say(["nice!", "\(self.score)!", "keep going!"].randomElement()!, 1) }
                return true
            }
            pet.say("click the ball!", 2)
        case .hideAndSeek:
            let candidates = world.windows.filter { w in
                w.frame.width > 300 && w.frame.height > 200 && !NSScreen.screens.contains { $0.frame == w.frame }
            }.prefix(8)
            guard let w = candidates.randomElement() else {
                pet.say("no windows to hide behind!", 2)
                active = nil
                hud?.close()
                hud = nil
                return
            }
            timeLeft = 60
            pet.say("count to three!", 2)
            pet.onClicked = { [weak self] in
                guard let self, let pet = self.pet else { return }
                self.score = Int(self.timeLeft)
                pet.found()
                self.stop("found")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.active == .hideAndSeek, let pet = self.pet,
                      let fresh = self.world.windowInfo(w.id) else { return }
                pet.startHiding(behind: fresh, seconds: 60)
            }
        }
        updateHUD()
    }

    func tick(_ dt: Double) {
        guard let kind = active, let pet else { return }
        switch kind {
        case .treatRain:
            timeLeft -= dt
            pet.gameTarget = NSEvent.mouseLocation.x
            spawnClock += dt
            let screen = world.screenFrame(at: pet.pos.x)
            if spawnClock > max(0.35, 0.8 - (30 - timeLeft) * 0.015) {
                spawnClock = 0
                treats.append(Treat(pos: CGPoint(x: .random(in: (screen.minX + 60)...(screen.maxX - 60)), y: screen.maxY - 40),
                                    vy: -.random(in: 220...380), food: Food.allCases.randomElement()!))
            }
            for i in treats.indices {
                treats[i].vy -= 500 * CGFloat(dt)
                treats[i].pos.y += treats[i].vy * CGFloat(dt)
            }
            let caught = treats.filter { abs($0.pos.x - pet.pos.x) < pet.size * 0.6 && $0.pos.y < pet.pos.y + pet.size && $0.pos.y > pet.pos.y - 10 }
            if !caught.isEmpty {
                score += caught.count
                Sound.shared.play(.munch)
                pet.emit(.heart, at: pet.head, count: 1, vy: 60...100, gravity: 0, life: 0.6...0.9)
                if caught.contains(where: { $0.food == pet.kind.favorite }) { pet.say("my favorite!", 1) }
            }
            treats.removeAll { t in caught.contains { $0.pos == t.pos } || t.pos.y < pet.pos.y - 60 }
            overlay?.refresh()
            if timeLeft <= 0 { stop("time") }
        case .keepyUppy:
            guard let ball, !ball.dead else { stop("lost"); return }
            if ball.grounded, score > 0 {
                ballLanded += dt
                if ballLanded > 0.4 { stop("dropped") }
            } else {
                ballLanded = 0
            }
        case .hideAndSeek:
            timeLeft -= dt
            if case .hiding = pet.state {} else if timeLeft < 58 { stop("lost") }
        }
        updateHUD()
    }

    func stop(_ reason: String?) {
        guard let kind = active else { return }
        active = nil
        overlay?.close()
        overlay = nil
        hud?.close()
        hud = nil
        props.onClick = nil
        if let ball, !ball.dead, kind == .keepyUppy { props.remove(ball) }
        ball = nil
        treats = []
        if let pet {
            pet.leaveGame()
            pet.onClicked = nil
            pet.hidingWindowID = nil
            if case .hiding = pet.state { pet.reappear() }
            let coins: Int
            switch kind {
            case .treatRain: coins = score; pet.say("\(score) treats! yum", 2.5)
            case .keepyUppy: coins = score * 2; if reason != "stopped" { pet.say("\(score) bounces!", 2.5) }
            case .hideAndSeek: coins = reason == "found" ? 10 + score / 3 : 2
            }
            if reason != "stopped" {
                Economy.shared.record(.gamePlayed)
                Economy.shared.earn(coins, kind.title)
                let best = UserDefaults.standard.integer(forKey: "best.\(kind.rawValue)")
                if score > best { UserDefaults.standard.set(score, forKey: "best.\(kind.rawValue)") }
            }
        }
        pet = nil
    }

    static func best(_ k: Kind) -> Int { UserDefaults.standard.integer(forKey: "best.\(k.rawValue)") }

    private func updateHUD() {
        guard let kind = active, let pet else { return }
        let text: String
        switch kind {
        case .treatRain: text = "🍪 Treat Rain   \(score)   0:\(String(format: "%02d", max(0, Int(timeLeft))))"
        case .keepyUppy: text = "⚽️ Keepy-Uppy   \(score)"
        case .hideAndSeek: text = "🙈 Find \(pet.name)!   0:\(String(format: "%02d", max(0, Int(timeLeft))))"
        }
        hud?.show(text)
    }
}

/// A little score bar at the top of the screen. Click it to stop the game.
final class GameHUD: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let onStop: () -> Void

    init(screen: NSScreen?, onStop: @escaping () -> Void) {
        self.onStop = onStop
        let s = screen?.visibleFrame ?? .zero
        super.init(contentRect: CGRect(x: s.midX - 160, y: s.maxY - 54, width: 320, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
        let box = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 20
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.alignment = .center
        label.frame = CGRect(x: 10, y: 10, width: 300, height: 20)
        label.toolTip = "Click to stop the game"
        box.addSubview(label)
        contentView = box
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) { onStop() }

    func show(_ text: String) {
        if label.stringValue != text { label.stringValue = text + "   ✕" }
    }
}

/// Draws falling treats across one screen; clicks pass through.
final class GameOverlay: NSPanel {
    private let view: View

    final class View: NSView {
        var items: () -> [(CGImage, CGPoint, CGFloat)] = { [] }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext, let window else { return }
            ctx.interpolationQuality = .none
            let o = window.frame.origin
            for (img, p, px) in items() {
                let w = CGFloat(img.width) * px, h = CGFloat(img.height) * px
                ctx.draw(img, in: CGRect(x: p.x - o.x - w / 2, y: p.y - o.y, width: w, height: h))
            }
        }
    }

    init(screen: NSScreen, items: @escaping () -> [(CGImage, CGPoint, CGFloat)]) {
        view = View()
        view.items = items
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    func refresh() { view.needsDisplay = true }
}
