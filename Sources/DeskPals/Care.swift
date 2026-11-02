import AppKit

// MARK: - Needs

/// Hunger, happiness, energy and your bond with each pet. Saved per pet, and they keep
/// changing (a little) while DeskPals is closed.
final class Needs {
    private let d = UserDefaults.standard
    private(set) var petID: String
    var fullness = 0.8
    var happiness = 0.7
    var energy = 0.9
    var bond = 0.0
    /// 0 baby, 1 kid, 2 grown up. New pets start as babies.
    var stage = 2
    var onGrow: ((Int) -> Void)?
    private var saveClock = 0.0

    init(petID: String) {
        self.petID = petID
        load()
    }

    func switchTo(_ id: String) {
        save()
        petID = id
        load()
    }

    var level: Int { Int((bond / 5).squareRoot()) }
    /// 0...1 progress from this level to the next.
    var levelProgress: Double {
        let lo = Double(level * level) * 5, hi = Double((level + 1) * (level + 1)) * 5
        return (bond - lo) / (hi - lo)
    }

    func tick(_ dt: Double, asleep: Bool) {
        fullness -= dt / (6 * 3600)
        energy += asleep ? dt / 1200 : -dt / (5 * 3600)
        if fullness < 0.2 { happiness -= dt / 1800 }
        happiness += (0.5 - happiness) * dt / 7200
        if (stage == 0 && bond >= 8) || (stage == 1 && bond >= 30) {
            stage += 1
            save()
            onGrow?(stage)
        }
        clampAll()
        saveClock += dt
        if saveClock > 10 { saveClock = 0; save() }
    }

    func petted() { happiness += 0.04; bond += 0.3; clampAll() }
    func played() { happiness += 0.06; energy -= 0.02; bond += 1; clampAll() }
    func fed(favorite: Bool) { fullness += 0.35; happiness += favorite ? 0.2 : 0.08; bond += favorite ? 3 : 2; clampAll() }
    func thrown() { happiness -= 0.03; clampAll() }
    func watched(_ dt: Double) { bond += dt / 60; happiness += dt / 3600; clampAll() }

    private func clampAll() {
        fullness = clamp(fullness, 0, 1)
        happiness = clamp(happiness, 0, 1)
        energy = clamp(energy, 0, 1)
    }

    private func key(_ k: String) -> String { "needs.\(petID).\(k)" }

    private func load() {
        func get(_ k: String, _ def: Double) -> Double { d.object(forKey: key(k)) as? Double ?? def }
        fullness = get("fullness", 0.8)
        happiness = get("happiness", 0.7)
        energy = get("energy", 0.9)
        bond = get("bond", 0)
        stage = Int(get("stage", 2))
        if let saved = d.object(forKey: key("saved")) as? Date {
            let away = Date().timeIntervalSince(saved)
            fullness -= away / (10 * 3600)
            energy += away / 3600
            clampAll()
        }
    }

    func save() {
        d.set(fullness, forKey: key("fullness"))
        d.set(happiness, forKey: key("happiness"))
        d.set(energy, forKey: key("energy"))
        d.set(bond, forKey: key("bond"))
        d.set(Double(stage), forKey: key("stage"))
        d.set(Date(), forKey: key("saved"))
    }
}

// MARK: - Food and toys

enum Food: String, CaseIterable {
    case fish, berry, cookie, pepper, coffee, taiyaki, cherry

    var title: String { rawValue.capitalized }

    var image: CGImage {
        SpriteSheet.cached("food-\(rawValue)") {
            switch self {
            case .fish:
                return Pixels.image(["...ooo...o", ".oobbbo.ob", "obKbbbbobb", ".oobbbo.ob", "...ooo...o"],
                                    ["o": 0x24425E, "b": 0x7FB8E6, "K": 0x111111])
            case .berry:
                return Pixels.image(["..gg..", ".gggg.", "..rr..", ".rrrr.", "rrWrrr", "rrrrrr", ".rrrr."],
                                    ["r": 0xE0315B, "g": 0x4CAF50])
            case .cookie:
                return Pixels.image([".ooooo.", "obbkbbo", "obbbbko", "okbbbbo", "obbkbbo", ".ooooo."],
                                    ["o": 0x7A4A1E, "b": 0xD9A05B, "k": 0x4A2A10])
            case .pepper:
                return Pixels.image(["..g..", ".gg..", ".rrr.", "rrWrr", "rrrrr", ".rrr.", "..rr.", "...r."],
                                    ["r": 0xE53935, "g": 0x4CAF50])
            case .coffee:
                return Pixels.image(["..s.s..", "...s.s.", "ooooo..", "offfooo", "oWWWo.o", "oWWWooo", ".ooo..."],
                                    ["o": 0x5A5A66, "f": 0x6B3E1E, "s": 0xD8D8D8])
            case .taiyaki:
                return Pixels.image(["...ooo...o", ".oobbbo.ob", "obKbbbbobb", ".oobbbo.ob", "...ooo...o"],
                                    ["o": 0x7A4A1E, "b": 0xE0A44E, "K": 0x3A2410])
            case .cherry:
                return Pixels.image(["....gg.", "...g.g.", "..g..g.", ".rr.rr.", "rWrrWrr", "rrrrrrr", ".rr.rr."],
                                    ["r": 0xD6203A, "g": 0x3E8E41])
            }
        }
    }
}

enum PropKind: Equatable {
    case food(Food), ball, bed, gift, place(Place)

    var image: CGImage {
        switch self {
        case .food(let f): return f.image
        case .place(let p): return p.image()
        case .ball:
            return SpriteSheet.cached("ball") {
                Pixels.image([".oooo.", "orrWro", "orrrro", "oWrrro", "orrrro", ".oooo."], ["o": 0x7A1020, "r": 0xF0445A])
            }
        case .bed:
            return SpriteSheet.cached("bed") {
                Pixels.image(["..oooooooooooooo..", ".obbbbbbbbbbbbbbo.", "obhhhbbbbbbbbbbbbo",
                              "obbbbbbbbbbbbbbbbo", "osssssssssssssssso", ".oooooooooooooooo."],
                             ["o": 0x5B3A6E, "b": 0x9D7BD8, "h": 0xC9B3F0, "s": 0x7A5BB5])
            }
        case .gift:
            return SpriteSheet.cached("gift") {
                Pixels.image(["..y.y..", "...y...", "rrryrrr", "rrryrrr", "yyyyyyy", "rrryrrr", "rrryrrr"],
                             ["r": 0x3FA9F5, "y": 0xFFD54F])
            }
        }
    }

    var bounce: Double {
        switch self {
        case .ball: return 0.7
        case .food: return 0.25
        case .gift: return 0.3
        case .bed, .place: return 0.05
        }
    }
}

/// A thing on the desktop with its own physics: food, a ball, a bed or a gift.
final class Prop {
    let id: Int
    let kind: PropKind
    var pos: CGPoint             // bottom centre
    var vel = CGVector.zero
    var spin: CGFloat = 0
    var groundID: Int?
    var groundFrame: CGRect?
    var dead = false
    var dragged = false
    /// Places: whether a pet is inside (house lights on), the swing's angle, and the garden's growth.
    var occupied = false
    var swingAngle: CGFloat = 0
    var stage = 0
    fileprivate var dragOffset = CGVector.zero
    fileprivate var dragSamples: [(t: Double, p: CGPoint)] = []
    fileprivate var window: PropWindow!
    var scale: CGFloat

    init(id: Int, kind: PropKind, pos: CGPoint, scale: CGFloat) {
        self.id = id
        self.kind = kind
        self.pos = pos
        self.scale = scale
    }

    var size: CGSize { CGSize(width: CGFloat(kind.image.width) * scale, height: CGFloat(kind.image.height) * scale) }
    var rect: CGRect { CGRect(x: pos.x - size.width / 2, y: pos.y, width: size.width, height: size.height) }
    var grounded: Bool { groundID != nil }
}

final class Props {
    static let bedBase = 2_000_000
    static let placeBase = 2_500_000
    private(set) var items: [Prop] = []
    private var nextID = 1
    var scale: CGFloat = 4
    let world: World
    var onGiftOpened: ((Prop) -> Void)?
    var onClick: ((Prop) -> Bool)?
    /// Time stop: frozen things don't move.
    var frozen: (CGPoint) -> Bool = { _ in false }

    init(world: World) { self.world = world }

    @discardableResult
    func add(_ kind: PropKind, at p: CGPoint, vel: CGVector = .zero) -> Prop {
        let prop = Prop(id: nextID, kind: kind, pos: p, scale: scale)
        nextID += 1
        prop.vel = vel
        prop.window = PropWindow(prop: prop, props: self)
        items.append(prop)
        return prop
    }

    func remove(_ prop: Prop) {
        prop.dead = true
        prop.window.orderOut(nil)
        items.removeAll { $0 === prop }
    }

    var bed: Prop? { items.first { $0.kind == .bed } }
    var places: [Prop] { items.filter { if case .place = $0.kind { return true }; return false } }
    func place(_ p: Place) -> Prop? { items.first { $0.kind == .place(p) } }
    var ball: Prop? { items.first { $0.kind == .ball } }
    var foods: [Prop] { items.filter { if case .food = $0.kind { return true }; return false } }

    /// The bed is something the pet can stand (and sleep) on.
    func platforms() -> [Platform] {
        var out: [Platform] = []
        if let bed, bed.grounded {
            let r = bed.rect
            out.append(Platform(id: Self.bedBase + bed.id, frame: r, y: r.minY + r.height * 0.6,
                                segments: [(r.minX + 4)...(r.maxX - 4)]))
        }
        for p in places where p.grounded {
            guard case .place(let place) = p.kind, let l = place.ledge else { continue }
            let r = p.rect, s = scale
            out.append(Platform(id: Self.placeBase + p.id, frame: r, y: r.minY + CGFloat(l.y) * s,
                                segments: [(r.minX + CGFloat(l.x0) * s)...(r.minX + CGFloat(l.x1 + 1) * s)]))
        }
        return out
    }

    // MARK: - Saved places

    /// Places stay where you put them, across launches.
    func savePlaces() {
        let list = places.map { p -> [String: Any] in
            guard case .place(let pl) = p.kind else { return [:] }
            return ["kind": pl.rawValue, "x": Double(p.pos.x), "y": Double(p.pos.y), "stage": p.stage]
        }
        UserDefaults.standard.set(list, forKey: "places")
    }

    func restorePlaces() {
        for e in UserDefaults.standard.array(forKey: "places") as? [[String: Any]] ?? [] {
            guard let k = (e["kind"] as? String).flatMap(Place.init(rawValue:)), place(k) == nil,
                  let x = e["x"] as? Double, let y = e["y"] as? Double else { continue }
            let p = add(.place(k), at: CGPoint(x: x, y: y + 4))
            p.stage = e["stage"] as? Int ?? 0
        }
    }

    func tick(_ dt: Double) {
        for p in items where !p.dragged && !frozen(p.pos) { step(p, dt) }
        let now = CACurrentMediaTime()
        for p in places where p.kind == .place(.swing) {
            p.swingAngle = p.occupied ? CGFloat(sin(now * 2.3) * 0.6) : p.swingAngle * 0.96
        }
        items.forEach { $0.window.sync() }
    }

    private func step(_ p: Prop, _ dt: Double) {
        let b = world.bounds
        if let gid = p.groundID {
            guard let g = world.platform(gid), g.holds(p.pos.x) else { p.groundID = nil; return }
            if let old = p.groundFrame, gid > 0 { p.pos.x += g.frame.minX - old.minX }
            p.groundFrame = g.frame
            p.pos.y = g.y
            // rolling / sliding with friction
            let friction: CGFloat = p.kind == .ball ? 260 : 1800
            let dv = friction * CGFloat(dt)
            p.vel.dx = abs(p.vel.dx) <= dv ? 0 : p.vel.dx - (p.vel.dx > 0 ? dv : -dv)
            p.pos.x += p.vel.dx * CGFloat(dt)
            p.spin -= p.vel.dx / (p.size.width / 2) * CGFloat(dt)
            if !g.holds(p.pos.x) { p.groundID = nil }
        } else {
            p.vel.dy -= 2600 * World.gravityScale * dt
            let prevY = p.pos.y
            p.pos.x += p.vel.dx * CGFloat(dt)
            p.pos.y += p.vel.dy * CGFloat(dt)
            if p.kind == .ball { p.spin -= p.vel.dx / (p.size.width / 2) * CGFloat(dt) }
            if p.vel.dy <= 0, let g = world.landing(x: p.pos.x, from: prevY, to: p.pos.y, ignoring: p.kind == .bed ? Self.bedBase + p.id : nil) {
                p.pos.y = g.y
                let impact = -p.vel.dy
                if impact > 300 && p.kind.bounce > 0.1 {
                    p.vel.dy = impact * p.kind.bounce
                } else {
                    p.vel.dy = 0
                    p.groundID = g.id
                    p.groundFrame = g.frame
                }
            } else if p.pos.y < b.minY - 300 {
                remove(p)
                return
            }
        }
        let half = p.size.width / 2
        if p.pos.x < b.minX + half { p.pos.x = b.minX + half; p.vel.dx = abs(p.vel.dx) * 0.6 }
        if p.pos.x > b.maxX - half { p.pos.x = b.maxX - half; p.vel.dx = -abs(p.vel.dx) * 0.6 }
        if p.pos.y > b.maxY - p.size.height { p.pos.y = b.maxY - p.size.height; p.vel.dy = min(0, p.vel.dy) }
    }

    fileprivate func beginDrag(_ p: Prop, _ mouse: CGPoint) {
        if onClick?(p) == true { return }
        p.dragged = true
        p.groundID = nil
        p.dragOffset = CGVector(dx: p.pos.x - mouse.x, dy: p.pos.y - mouse.y)
        p.dragSamples = [(CACurrentMediaTime(), mouse)]
    }

    fileprivate func drag(_ p: Prop, _ mouse: CGPoint) {
        let now = CACurrentMediaTime()
        p.dragSamples.append((now, mouse))
        p.dragSamples.removeAll { now - $0.t > 0.1 }
        p.pos = CGPoint(x: mouse.x + p.dragOffset.dx, y: mouse.y + p.dragOffset.dy)
    }

    fileprivate func endDrag(_ p: Prop, _ mouse: CGPoint) {
        p.dragged = false
        if case .place = p.kind { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.savePlaces() } }
        let moved = p.dragSamples.count > 1
        if let first = p.dragSamples.first, CACurrentMediaTime() - first.t > 0.005 {
            let dt = CACurrentMediaTime() - first.t
            var v = CGVector(dx: (mouse.x - first.p.x) / dt, dy: (mouse.y - first.p.y) / dt)
            let speed = hypot(v.dx, v.dy)
            if speed > 3000 { v = CGVector(dx: v.dx * 3000 / speed, dy: v.dy * 3000 / speed) }
            p.vel = v
        }
        if !moved, p.kind == .gift { onGiftOpened?(p) }
        if case .place = p.kind { p.vel = CGVector(dx: p.vel.dx * 0.3, dy: min(p.vel.dy, 300)) }
    }
}

final class PropWindow: NSPanel {
    private unowned let prop: Prop
    private unowned let props: Props
    private let view: PropView

    init(prop: Prop, props: Props) {
        self.prop = prop
        self.props = props
        self.view = PropView(prop: prop)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = view
        view.onDown = { [weak self] in guard let self else { return }; self.props.beginDrag(self.prop, NSEvent.mouseLocation) }
        view.onDrag = { [weak self] in guard let self else { return }; self.props.drag(self.prop, NSEvent.mouseLocation) }
        view.onUp = { [weak self] in guard let self else { return }; self.props.endDrag(self.prop, NSEvent.mouseLocation) }
        sync()
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }

    func sync() {
        let s = prop.size
        let side = max(s.width, s.height) * 1.5
        setFrame(CGRect(x: (prop.pos.x - side / 2).rounded(), y: prop.pos.y.rounded(), width: side, height: side), display: false)
        view.needsDisplay = true
        let wants = prop.dragged || prop.rect.contains(NSEvent.mouseLocation)
        if ignoresMouseEvents == wants { ignoresMouseEvents = !wants }
    }
}

final class PropView: NSView {
    unowned let prop: Prop
    var onDown: (() -> Void)?
    var onDrag: (() -> Void)?
    var onUp: (() -> Void)?

    init(prop: Prop) {
        self.prop = prop
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onDown?() }
    override func mouseDragged(with event: NSEvent) { onDrag?() }
    override func mouseUp(with event: NSEvent) { onUp?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        let s = prop.size
        if case .place(let place) = prop.kind {
            drawPlace(ctx, place, s)
            return
        }
        ctx.translateBy(x: bounds.midX, y: s.height / 2)
        ctx.rotate(by: prop.spin)
        ctx.draw(prop.kind.image, in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
    }
}

extension PropView {
    /// Places animate: flickering fire, rippling water, lit windows, growing flowers and a swinging seat.
    func drawPlace(_ ctx: CGContext, _ place: Place, _ s: CGSize) {
        let t = CACurrentMediaTime()
        let frame = Int(t * (place == .campfire ? 6 : 1.5)) % 2
        let img = place.image(frame: frame, stage: prop.stage, lit: prop.occupied)
        let r = CGRect(x: bounds.midX - s.width / 2, y: 0, width: s.width, height: s.height)
        ctx.draw(img, in: r)
        if place == .swing {
            let px = prop.scale
            let pivot = CGPoint(x: r.midX, y: r.maxY - px * 1.5)
            let length = px * 17
            let a = prop.swingAngle
            let seatC = CGPoint(x: pivot.x + sin(a) * length, y: pivot.y - cos(a) * length)
            ctx.setStrokeColor(CGColor(red: 0.42, green: 0.27, blue: 0.14, alpha: 1))
            ctx.setLineWidth(max(1, px * 0.5))
            for dx in [-2.2, 2.2] {
                ctx.move(to: CGPoint(x: pivot.x + dx * px, y: pivot.y))
                ctx.addLine(to: CGPoint(x: seatC.x + dx * px * cos(a), y: seatC.y + dx * px * sin(a)))
            }
            ctx.strokePath()
            ctx.saveGState()
            ctx.translateBy(x: seatC.x, y: seatC.y)
            ctx.rotate(by: a)
            ctx.draw(Place.seat, in: CGRect(x: -3 * px, y: -px, width: 6 * px, height: 2 * px))
            ctx.restoreGState()
        }
    }
}

// MARK: - Particles

enum ParticleKind { case dust, heart, note, popcorn, crumb, fire, sparkle, sweat, tentacle, fist, flame }

struct Particle {
    var pos: CGPoint
    var vel: CGVector
    var life: Double
    let maxLife: Double
    let kind: ParticleKind
    let gravity: CGFloat
    var color: UInt32 = 0

    /// Flames take the particle's own colour (auras).
    static func image(for p: Particle) -> CGImage {
        guard p.kind == .flame else { return image(p.kind) }
        return SpriteSheet.cached("flame-\(p.color)") {
            let r = (p.color >> 16) & 0xFF, g = (p.color >> 8) & 0xFF, b = p.color & 0xFF
            let light = (min(255, r + (255 - r) / 2) << 16) | (min(255, g + (255 - g) / 2) << 8) | min(255, b + (255 - b) / 2)
            return Pixels.image([".c.", "cLc", ".c."], ["c": p.color, "L": light])
        }
    }

    static func image(_ k: ParticleKind) -> CGImage {
        SpriteSheet.cached("particle-\(k)") {
            switch k {
            case .dust: return Pixels.image([".d.", "ddd", ".d."], ["d": 0xD8D2CC])
            case .heart: return Pixels.image(["rr.rr", "rrrrr", ".rrr.", "..r.."], ["r": 0xFF4F86])
            case .note: return Pixels.image(["..nn", "..n.", "..n.", "nnn.", "nn.."], ["n": 0x4A3AFF])
            case .popcorn: return Pixels.image(["wy", "ww"], ["w": 0xFFF8E1, "y": 0xFFD54F])
            case .crumb: return Pixels.image(["c"], ["c": 0xB07A3A])
            case .fire: return Pixels.image([".y.", "yoy", "oro"], ["y": 0xFFE066, "o": 0xFF8A1F, "r": 0xE53935])
            case .sparkle: return Pixels.image([".s.", "sWs", ".s."], ["s": 0xFFD54F])
            case .sweat: return Pixels.image(["b", "b"], ["b": 0x6EC6FF])
            case .tentacle: return Pixels.image([".r.", "rRr", ".r."], ["r": 0xC8102E, "R": 0xFF4D5E])
            case .flame: return Pixels.image(["c"], ["c": 0xFFFFFF])
            case .fist: return Pixels.image([".oooo.", "oppppo", "oppppo", ".oooo."], ["o": 0x3A2470, "p": 0x8C6BE0])
            }
        }
    }
}
