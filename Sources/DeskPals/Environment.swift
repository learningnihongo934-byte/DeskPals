import AppKit

enum WeatherKind: String, CaseIterable {
    case clear, cloudy, rain, storm, snow, fog, leaves, petals

    var title: String {
        switch self {
        case .clear: return "Sunny"
        case .cloudy: return "Cloudy"
        case .rain: return "Rain"
        case .storm: return "Storm"
        case .snow: return "Snow"
        case .fog: return "Fog"
        case .leaves: return "Falling leaves"
        case .petals: return "Blossoms"
        }
    }
}

enum Theme: String, CaseIterable {
    case none, beach, forest, snowy, space

    var title: String { self == .none ? "None" : rawValue.capitalized }
    var shopID: String? { self == .none ? nil : "theme.\(rawValue)" }
}

/// Weather, seasons, holidays and themed worlds, drawn on a click-through layer over the desktop
/// (under the pets). Real weather is optional and only sends the city you typed to Open-Meteo.
final class Environment {
    enum Mode: String, CaseIterable {
        case off, seasons, real
        var title: String { ["off": "Off", "seasons": "Seasons only", "real": "Real weather"][rawValue]! }
    }

    private let d = UserDefaults.standard
    let world: World
    private let pets: () -> [Pet]
    private var overlays: [EnvOverlay] = []
    private(set) var particles: [EnvParticle] = []
    private(set) var snowCaps: [Int: CGFloat] = [:]
    private(set) var flash: CGFloat = 0
    private(set) var weather: WeatherKind = .clear
    private(set) var real: (kind: WeatherKind, temp: Double, place: String)?
    private var nextThunder = 10.0
    private var lastFetch = -10000.0
    private var clock = 0.0
    private var drawClock = 0.0
    private var told: WeatherKind?

    var mode: Mode {
        get { Mode(rawValue: d.string(forKey: "weather.mode") ?? "") ?? .seasons }
        set { d.set(newValue.rawValue, forKey: "weather.mode"); lastFetch = -10000 }
    }
    var city: String {
        get { d.string(forKey: "weather.city") ?? "" }
        set { d.set(newValue, forKey: "weather.city"); real = nil; lastFetch = -10000 }
    }
    /// Pick the weather yourself from the menu; nil means automatic.
    var override: WeatherKind? {
        get { d.string(forKey: "weather.override").flatMap(WeatherKind.init(rawValue:)) }
        set { d.set(newValue?.rawValue, forKey: "weather.override") }
    }
    var theme: Theme {
        get { Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .none }
        set { d.set(newValue.rawValue, forKey: "theme"); applyTheme() }
    }

    init(world: World, pets: @escaping () -> [Pet]) {
        self.world = world
        self.pets = pets
        rebuildOverlays()
        applyTheme()
    }

    func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { EnvOverlay(screen: $0, env: self) }
    }

    private func applyTheme() {
        World.gravityScale = theme == .space ? 0.45 : 1
    }

    // MARK: - Seasons and holidays

    enum Holiday { case none, halloween, christmas, newYear, valentine }

    /// Holiday decorations (pumpkins, lights, fireworks) can be turned off.
    var holidaysOn: Bool {
        get { d.object(forKey: "holidays") as? Bool ?? true }
        set { d.set(newValue, forKey: "holidays") }
    }

    /// No world at all: plain desktop, no weather, no holiday decorations.
    func clearWorld() {
        theme = .none
        mode = .off
        override = nil
        holidaysOn = false
    }

    var holiday: Holiday {
        guard holidaysOn else { return .none }
        let c = Calendar.current.dateComponents([.month, .day, .hour], from: Date())
        switch (c.month ?? 0, c.day ?? 0) {
        case (10, 15...31), (11, 1): return .halloween
        case (12, 31) where (c.hour ?? 0) >= 22, (1, 1) where (c.hour ?? 0) < 2: return .newYear
        case (12, 1...30): return .christmas
        case (2, 10...14): return .valentine
        default: return .none
        }
    }

    private var seasonal: WeatherKind {
        switch Calendar.current.component(.month, from: Date()) {
        case 9, 10, 11: return .leaves
        case 3, 4, 5: return .petals
        case 12, 1: return .snow
        default: return .clear
        }
    }

    // MARK: - Tick

    func tick(_ dt: Double) {
        clock += dt
        if mode == .real, !city.isEmpty, clock - lastFetch > 1200 {
            lastFetch = clock
            fetchWeather()
        }
        let now: WeatherKind = override ?? {
            switch mode {
            case .off: return .clear
            case .seasons: return seasonal
            case .real: return real?.kind ?? seasonal
            }
        }()
        if now != weather || told == nil, clock > 4 {
            weather = now
            told = now
            pets().forEach { $0.weatherChanged(now, temperature: real?.temp) }
        }
        spawn(dt)
        update(dt)
        if weather == .storm {
            nextThunder -= dt
            if nextThunder <= 0 {
                nextThunder = .random(in: 9...22)
                flash = 0.35
                Sound.shared.play(.thunder)
                pets().forEach { $0.thunder() }
            }
        }
        flash = max(0, flash - CGFloat(dt) * 0.9)

        // Snow piles up on window tops while it snows, and melts after.
        let snowing = weather == .snow || theme == .snowy
        for p in world.platforms where p.id > 0 && p.id < Ledges.base || p.id < 0 && p.id != World.dockID {
            let cap = snowCaps[p.id] ?? 0
            snowCaps[p.id] = snowing ? min(7, cap + CGFloat(dt) * (theme == .snowy ? 7 : 0.04)) : max(0, cap - CGFloat(dt) * 0.1)
        }

        drawClock += dt
        if drawClock >= 1.0 / 30 {
            drawClock = 0
            let active = !particles.isEmpty || flash > 0 || theme != .none || holiday != .none || snowCaps.values.contains { $0 > 0.2 }
            overlays.forEach { $0.refresh(visible: active) }
        }
    }

    private func spawn(_ dt: Double) {
        let b = world.bounds
        func add(_ k: EnvParticle.Kind, _ p: CGPoint, _ v: CGVector, life: Double) {
            particles.append(EnvParticle(pos: p, vel: v, life: life, maxLife: life, kind: k, seed: .random(in: 0...6.28)))
        }
        func rate(_ perSecond: Double) -> Int {
            let n = perSecond * dt
            return Int(n) + (Double.random(in: 0..<1) < n.truncatingRemainder(dividingBy: 1) ? 1 : 0)
        }
        let top = b.maxY
        switch weather {
        case .rain, .storm:
            for _ in 0..<rate(weather == .storm ? 160 : 90) {
                add(.rain, CGPoint(x: .random(in: b.minX...b.maxX), y: top), CGVector(dx: -60, dy: -1100), life: 2)
            }
            // drips off the ends of window tops
            for p in world.platforms where p.id > 0 && p.id < Ledges.base {
                for seg in p.segments where Double.random(in: 0..<1) < dt * 0.6 {
                    add(.drip, CGPoint(x: Bool.random() ? seg.lowerBound : seg.upperBound, y: p.y), CGVector(dx: 0, dy: -100), life: 1.5)
                }
            }
        case .snow:
            for _ in 0..<rate(35) { add(.snow, CGPoint(x: .random(in: b.minX...b.maxX), y: top), CGVector(dx: .random(in: -20...20), dy: -.random(in: 40...90)), life: 30) }
        case .leaves:
            for _ in 0..<rate(1.2) { add(.leaf, CGPoint(x: .random(in: b.minX...b.maxX), y: top), CGVector(dx: .random(in: -40...40), dy: -.random(in: 50...90)), life: 30) }
        case .petals:
            for _ in 0..<rate(1.5) { add(.petal, CGPoint(x: .random(in: b.minX...b.maxX), y: top), CGVector(dx: .random(in: -30...50), dy: -.random(in: 40...70)), life: 30) }
        default: break
        }
        if theme == .snowy, weather != .snow {
            for _ in 0..<rate(6) { add(.snow, CGPoint(x: .random(in: b.minX...b.maxX), y: top), CGVector(dx: .random(in: -15...15), dy: -.random(in: 40...70)), life: 30) }
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if theme == .forest, hour >= 19 || hour < 6 {
            for _ in 0..<rate(0.6) { add(.firefly, CGPoint(x: .random(in: b.minX...b.maxX), y: .random(in: b.minY...(b.minY + 300))), CGVector(dx: .random(in: -15...15), dy: .random(in: -10...10)), life: 8) }
        }
        if theme == .beach {
            for _ in 0..<rate(0.5) { add(.bubble, CGPoint(x: .random(in: b.minX...b.maxX), y: b.minY + 10), CGVector(dx: .random(in: -10...10), dy: .random(in: 30...60)), life: 10) }
        }
        if theme == .space {
            for _ in 0..<rate(0.4) { add(.star, CGPoint(x: .random(in: b.minX...b.maxX), y: .random(in: b.minY...b.maxY)), .zero, life: 6) }
        }
        if holiday == .newYear, Double.random(in: 0..<1) < dt * 0.8 {
            let c = CGPoint(x: .random(in: b.minX...b.maxX), y: .random(in: (b.maxY - 400)...(b.maxY - 120)))
            for i in 0..<28 {
                let a = Double(i) / 28 * .pi * 2
                add(.spark, c, CGVector(dx: cos(a) * 160, dy: sin(a) * 160), life: 1.4)
            }
        }
        if particles.count > 900 { particles.removeFirst(particles.count - 900) }
    }

    private func update(_ dt: Double) {
        let floorY = world.bounds.minY
        for i in particles.indices {
            var p = particles[i]
            if FX.shared.isFrozen(point: p.pos) { continue }   // time stop
            p.life -= dt
            switch p.kind {
            case .leaf, .petal, .snow:
                p.pos.x += (p.vel.dx + CGFloat(sin(clock * 1.5 + p.seed) * 25)) * CGFloat(dt)
                p.pos.y += p.vel.dy * CGFloat(dt)
            case .spark:
                p.vel.dy -= 120 * CGFloat(dt)
                p.pos.x += p.vel.dx * CGFloat(dt)
                p.pos.y += p.vel.dy * CGFloat(dt)
            case .drip:
                p.vel.dy -= 900 * CGFloat(dt)
                p.pos.y += p.vel.dy * CGFloat(dt)
            default:
                p.pos.x += p.vel.dx * CGFloat(dt)
                p.pos.y += p.vel.dy * CGFloat(dt)
            }
            if p.pos.y < floorY - 20 { p.life = 0 }
            // rain and snow stop on window tops and the floor
            if p.kind == .rain || p.kind == .snow || p.kind == .leaf || p.kind == .petal,
               let g = world.ground(below: p.pos), p.pos.y < g.y + 1 {
                p.life = p.kind == .rain ? 0 : min(p.life, 3)
                p.vel = .zero
            }
            particles[i] = p
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: - Real weather (Open-Meteo, no key, only the city name and rounded coordinates are sent)

    private func fetchWeather() {
        let name = city.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return }
        geo.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1")]
        guard let url = geo.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else { return }
            let label = first["name"] as? String ?? name
            let q = String(format: "latitude=%.1f&longitude=%.1f&current=weather_code,temperature_2m", lat, lon)
            guard let wurl = URL(string: "https://api.open-meteo.com/v1/forecast?\(q)") else { return }
            URLSession.shared.dataTask(with: wurl) { data, _, _ in
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cur = json["current"] as? [String: Any], let code = cur["weather_code"] as? Int else { return }
                let temp = cur["temperature_2m"] as? Double ?? 15
                DispatchQueue.main.async { self?.real = (Self.kind(code), temp, label) }
            }.resume()
        }.resume()
    }

    static func kind(_ code: Int) -> WeatherKind {
        switch code {
        case 0, 1: return .clear
        case 2, 3: return .cloudy
        case 45, 48: return .fog
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .clear
        }
    }

    var summary: String {
        if let real, mode == .real { return "\(real.kind.title), \(Int(real.temp.rounded()))°C in \(real.place)" }
        return weather.title
    }
}

struct EnvParticle {
    enum Kind { case rain, drip, snow, leaf, petal, firefly, bubble, star, spark }
    var pos: CGPoint
    var vel: CGVector
    var life: Double
    let maxLife: Double
    let kind: Kind
    let seed: Double
}

/// One click-through layer per screen, just under the pets.
final class EnvOverlay: NSPanel {
    private let view: EnvView

    init(screen: NSScreen, env: Environment) {
        view = EnvView(env: env)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }

    func refresh(visible: Bool) {
        if visible {
            if !isVisible { orderFrontRegardless() }
            view.needsDisplay = true
        } else if isVisible {
            orderOut(nil)
        }
    }
}

private final class EnvView: NSView {
    unowned let env: Environment

    init(env: Environment) {
        self.env = env
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static let leaf = Pixels.image([".o.", "ooo", "o.."], ["o": 0xE07A2B])
    private static let leaf2 = Pixels.image([".r.", "rrr", "..r"], ["r": 0xC2453A])
    private static let petal = Pixels.image(["pp", "p."], ["p": 0xFFB7D0])
    private static let shell = Pixels.image([".w.", "www"], ["w": 0xFFE9D6])
    private static let tuft = Pixels.image(["g.g", ".g."], ["g": 0x4CAF50])
    private static let mushroom = Pixels.image(["rrr", "rWr", ".w."], ["r": 0xE53935, "w": 0xF5E6D3])
    private static let pumpkin = Pixels.image([".g..", "oooo", "oKoK", "oooo"], ["g": 0x4CAF50, "o": 0xF28C28, "K": 0x3A1A0A])
    private static let rock = Pixels.image([".gg", "ggg"], ["g": 0x9E9EA8])

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let window else { return }
        ctx.interpolationQuality = .none
        let o = window.frame.origin
        let px: CGFloat = 3
        let t = CACurrentMediaTime()

        // Ground decorations along floors and window tops
        let theme = env.theme, holiday = env.holiday
        for p in env.world.platforms where (p.id > 0 && p.id < Ledges.base) || (p.id < 0 && p.id != World.dockID) {
            for seg in p.segments {
                let y = p.y - o.y
                if let cap = env.snowCaps[p.id], cap > 0.2 {
                    ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
                    let r = CGRect(x: seg.lowerBound - o.x, y: y - 1, width: seg.upperBound - seg.lowerBound, height: cap)
                    ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(cap, 3), cornerHeight: min(cap, 3), transform: nil))
                    ctx.fillPath()
                }
                var x = seg.lowerBound + 10
                var i = 0
                while x < seg.upperBound - 10 {
                    let img: CGImage?
                    switch theme {
                    case .forest: img = i % 7 == 3 ? Self.mushroom : Self.tuft
                    case .beach: img = p.id < 0 ? (i % 5 == 2 ? Self.shell : nil) : nil
                    case .space: img = i % 4 == 1 ? Self.rock : nil
                    default: img = nil
                    }
                    if let img {
                        ctx.draw(img, in: CGRect(x: x - o.x, y: y, width: CGFloat(img.width) * px, height: CGFloat(img.height) * px))
                    }
                    if holiday == .halloween, p.id < 0, i % 9 == 4 {
                        ctx.draw(Self.pumpkin, in: CGRect(x: x - o.x, y: y, width: 4 * px * 1.5, height: 4 * px * 1.5))
                    }
                    if holiday == .christmas, p.id > 0, i % 2 == 0 {
                        let colors: [CGColor] = [CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), CGColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1),
                                                 CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), CGColor(red: 0.4, green: 0.7, blue: 1, alpha: 1)]
                        let on = (Int(t * 2) + i) % 3 != 0
                        ctx.setFillColor(colors[i % 4].copy(alpha: on ? 1 : 0.35)!)
                        ctx.fillEllipse(in: CGRect(x: x - o.x, y: y - 4, width: 5, height: 5))
                    }
                    x += theme == .beach ? 46 : 24
                    i += 1
                }
                if theme == .beach, p.id < 0 {
                    ctx.setFillColor(CGColor(red: 0.96, green: 0.86, blue: 0.62, alpha: 0.85))
                    ctx.fill(CGRect(x: seg.lowerBound - o.x, y: y - 1, width: seg.upperBound - seg.lowerBound, height: 5))
                }
            }
        }

        for p in env.particles {
            let x = p.pos.x - o.x, y = p.pos.y - o.y
            guard bounds.insetBy(dx: -20, dy: -20).contains(CGPoint(x: x, y: y)) else { continue }
            let fade = CGFloat(min(1, p.life / min(p.maxLife, 1.5)))
            switch p.kind {
            case .rain:
                ctx.setStrokeColor(CGColor(red: 0.6, green: 0.75, blue: 1, alpha: 0.45))
                ctx.setLineWidth(1.2)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + 0.6, y: y + 11))
                ctx.strokePath()
            case .drip:
                ctx.setFillColor(CGColor(red: 0.6, green: 0.8, blue: 1, alpha: 0.8))
                ctx.fillEllipse(in: CGRect(x: x - 1.5, y: y - 2, width: 3, height: 4))
            case .snow:
                let s = 2 + CGFloat(p.seed.truncatingRemainder(dividingBy: 1)) * 2.5
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.9 * fade))
                ctx.fillEllipse(in: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
            case .leaf, .petal:
                let img = p.kind == .petal ? Self.petal : (p.seed > 3.14 ? Self.leaf : Self.leaf2)
                ctx.saveGState()
                ctx.setAlpha(fade)
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: CGFloat(t * 1.3 + p.seed))
                ctx.draw(img, in: CGRect(x: -4, y: -4, width: CGFloat(img.width) * px, height: CGFloat(img.height) * px))
                ctx.restoreGState()
            case .firefly:
                let glow = CGFloat(0.5 + 0.5 * sin(t * 3 + p.seed)) * fade
                ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.4, alpha: glow))
                ctx.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
            case .bubble:
                ctx.setStrokeColor(CGColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.7 * fade))
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
            case .star:
                let tw = CGFloat(sin(Double.pi * (1 - p.life / p.maxLife)))
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.8 * tw))
                ctx.fill(CGRect(x: x - 1, y: y - 1, width: 2.5, height: 2.5))
            case .spark:
                let hue = CGFloat(p.seed / 6.28)
                ctx.setFillColor(NSColor(hue: hue, saturation: 0.8, brightness: 1, alpha: fade).cgColor)
                ctx.fill(CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
            }
        }

        if env.flash > 0 {
            ctx.setFillColor(CGColor(gray: 1, alpha: env.flash))
            ctx.fill(bounds)
        }
    }
}
