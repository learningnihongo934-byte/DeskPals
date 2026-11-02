import AppKit

/// Big visual effects drawn over everything: shockwave rings, flashes, speed lines, floating glyphs,
/// flurries of hits, screen shake, and time-stop bubbles that freeze whatever is inside them.
final class FX {
    static let shared = FX()

    struct Effect {
        enum Kind { case ring, flash, speedLines, glyph(String), hits, projectiles(CGImage, CGPoint), drop(CGImage, CGPoint, CGFloat), rocket, moon(CGImage) }
        let kind: Kind
        let center: CGPoint
        let start: Double
        let duration: Double
        let color: UInt32
        let radius: CGFloat
        let dir: CGFloat
    }

    struct Zone {
        weak var owner: Pet?
        let center: CGPoint
        let radius: CGFloat
        let start: Double
        let until: Double
    }

    private(set) var effects: [Effect] = []
    private(set) var zones: [Zone] = []
    private(set) var shakeAmount: CGFloat = 0
    private var overlays: [FXOverlay] = []
    var now: Double { CACurrentMediaTime() }

    func rebuild() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { FXOverlay(screen: $0) }
    }

    private func add(_ kind: Effect.Kind, _ c: CGPoint, _ duration: Double, color: UInt32 = 0xFFFFFF, radius: CGFloat = 100, dir: CGFloat = 1) {
        effects.append(Effect(kind: kind, center: c, start: now, duration: duration, color: color, radius: radius, dir: dir))
    }

    func ring(at c: CGPoint, color: UInt32, radius: CGFloat, duration: Double = 0.5) { add(.ring, c, duration, color: color, radius: radius) }
    func flash(at c: CGPoint, color: UInt32, radius: CGFloat = 120) { add(.flash, c, 0.25, color: color, radius: radius) }
    func speedLines(at c: CGPoint, dir: CGFloat) { add(.speedLines, c, 0.18, dir: dir) }
    func glyph(_ text: String, at c: CGPoint, color: UInt32) { add(.glyph(text), c, 1.3, color: color) }
    func hits(at c: CGPoint, color: UInt32, duration: Double = 0.8) { add(.hits, c, duration, color: color, radius: 40) }
    func shake(_ amount: CGFloat) { shakeAmount = max(shakeAmount, amount) }
    /// A rocket that builds itself at `base`, counts down, and launches.
    func rocket(at base: CGPoint, scale: CGFloat) { add(.rocket, base, 8.6, radius: scale) }
    /// A moon in the corner of the main screen with a little pet waving from it.
    func moon(with pet: CGImage, scale: CGFloat, duration: Double) {
        let top = NSScreen.screens.first?.frame ?? .zero
        add(.moon(pet), CGPoint(x: top.maxX - 200, y: top.maxY - 230), duration, radius: scale)
    }
    /// A volley of thrown things flying from one point to another.
    func projectiles(_ img: CGImage, from: CGPoint, to: CGPoint, duration: Double = 0.5) {
        add(.projectiles(img, from), to, duration, radius: 0)
    }
    /// Something huge falls from the sky onto `to`, sits there, then gets knocked away.
    func drop(_ img: CGImage, onto to: CGPoint, scale: CGFloat, duration: Double) {
        add(.drop(img, CGPoint(x: to.x, y: to.y + 1400), scale), to, duration)
    }

    var shakeOffset: CGPoint {
        guard shakeAmount > 0.01 else { return .zero }
        return CGPoint(x: .random(in: -1...1) * shakeAmount * 7, y: .random(in: -1...1) * shakeAmount * 7)
    }

    /// Stop time in a bubble: everything inside freezes except the pet who did it.
    func timeStop(owner: Pet, center: CGPoint, radius: CGFloat, duration: Double) {
        zones.append(Zone(owner: owner, center: center, radius: radius, start: now, until: now + duration))
    }

    func isFrozen(_ pet: Pet) -> Bool {
        // anyone who can stop time can move in someone else's stopped time
        pet.kind.power != .timeStop &&
            zones.contains { $0.owner !== pet && now < $0.until && hypot(pet.pos.x - $0.center.x, pet.pos.y + pet.size / 2 - $0.center.y) < $0.radius }
    }

    func isFrozen(point p: CGPoint) -> Bool {
        zones.contains { now < $0.until && hypot(p.x - $0.center.x, p.y - $0.center.y) < $0.radius }
    }

    func owns(_ pet: Pet) -> Bool { zones.contains { $0.owner === pet && now < $0.until } }

    func tick(_ dt: Double) {
        shakeAmount = max(0, shakeAmount - CGFloat(dt) * 2.2)
        effects.removeAll { now - $0.start > $0.duration }
        zones.removeAll { now > $0.until + 0.4 }
        let active = !effects.isEmpty || !zones.isEmpty
        overlays.forEach { $0.refresh(visible: active) }
    }
}

/// One click-through layer per screen, above the pets.
final class FXOverlay: NSPanel {
    private let view = FXView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
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

private final class FXView: NSView {
    static let rocketImage = Pixels.image([
        "....r....", "...rrr...", "...rrr...", "..wwwww..", "..wwwww..", "..wwbww..", "..wbbbw..", "..wwbww..",
        "..wwwww..", "..wwwww..", "..wwwww..", "..wwwww..", ".rwwwwwr.", "rrwwwwwrr", "rr.ggg.rr", "r..ggg..r",
    ], ["r": 0xE53935, "w": 0xF4F4F4, "b": 0x4FC3F7, "g": 0x8A8A96])

    private func color(_ hex: UInt32, _ alpha: CGFloat) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let window else { return }
        let fx = FX.shared, now = fx.now
        let o = window.frame.origin
        ctx.interpolationQuality = .none

        // Time-stop bubbles: an inverted shockwave, then a gray, frozen world inside.
        for z in fx.zones {
            let c = CGPoint(x: z.center.x - o.x, y: z.center.y - o.y)
            let age = now - z.start, left = z.until - now
            let grow = CGFloat(min(1, age / 0.35)), shrink = CGFloat(max(0, min(1, left / 0.4)))
            let r = z.radius * grow * (left < 0.4 ? shrink : 1)
            guard r > 1 else { continue }
            let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if age < 0.35 {
                ctx.setFillColor(color(0xE8DDFF, 0.55 * (1 - grow)))
                ctx.fillEllipse(in: circle)
            }
            ctx.setFillColor(color(0x5A5470, 0.32))
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(color(0xB9A6FF, 0.9))
            ctx.setLineWidth(3)
            ctx.setLineDash(phase: CGFloat(now * 30), lengths: [10, 6])
            ctx.strokeEllipse(in: circle)
            ctx.setLineDash(phase: 0, lengths: [])
            if left > 0 {
                let text = NSAttributedString(string: "⏱ \(Int(ceil(left)))", attributes: [
                    .font: NSFont.systemFont(ofSize: 20, weight: .black), .foregroundColor: NSColor.white,
                    .strokeColor: NSColor(white: 0.1, alpha: 1), .strokeWidth: -3])
                text.draw(at: CGPoint(x: c.x - text.size().width / 2, y: c.y + r - 34))
            }
        }

        for e in fx.effects {
            let p = CGFloat((now - e.start) / e.duration)
            let c = CGPoint(x: e.center.x - o.x, y: e.center.y - o.y)
            switch e.kind {
            case .ring:
                let r = e.radius * (0.15 + 0.85 * p)
                ctx.setStrokeColor(color(e.color, 1 - p))
                ctx.setLineWidth(10 * (1 - p) + 2)
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            case .flash:
                let r = e.radius * (0.6 + 0.4 * p)
                ctx.setFillColor(color(e.color, 0.7 * (1 - p)))
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            case .speedLines:
                ctx.setStrokeColor(color(0xFFFFFF, 0.7 * (1 - p)))
                ctx.setLineWidth(2)
                for i in 0..<5 {
                    let y = c.y - 30 + CGFloat(i) * 15 + CGFloat(i % 2) * 4
                    let x0 = c.x - e.dir * (30 + CGFloat(i * 13 % 25))
                    ctx.move(to: CGPoint(x: x0, y: y))
                    ctx.addLine(to: CGPoint(x: x0 - e.dir * (60 + CGFloat(i * 17 % 40)), y: y))
                }
                ctx.strokePath()
            case .glyph(let s):
                let text = NSAttributedString(string: s, attributes: [
                    .font: NSFont.systemFont(ofSize: 30, weight: .black),
                    .foregroundColor: NSColor(cgColor: color(e.color, 1 - p)) ?? .purple,
                    .strokeColor: NSColor(white: 0.05, alpha: 1 - p), .strokeWidth: -4])
                text.draw(at: CGPoint(x: c.x, y: c.y + p * 40))
            case .projectiles(let img, let from):
                let a = CGPoint(x: from.x - o.x, y: from.y - o.y)
                let ang = atan2(c.y - a.y, c.x - a.x)
                for i in 0..<5 {
                    let k = min(1, p * 1.3 - CGFloat(i) * 0.06)
                    guard k > 0 else { continue }
                    let spread = CGFloat(i - 2) * 9
                    let x = a.x + (c.x - a.x) * k - sin(ang) * spread, y = a.y + (c.y - a.y) * k + cos(ang) * spread
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: ang)
                    ctx.draw(img, in: CGRect(x: -CGFloat(img.width) * 1.5, y: -CGFloat(img.height) * 1.5, width: CGFloat(img.width) * 3, height: CGFloat(img.height) * 3))
                    ctx.restoreGState()
                }
            case .drop(let img, let from, let scale):
                let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
                let a = CGPoint(x: from.x - o.x, y: from.y - o.y)
                var pos = c, rot: CGFloat = 0, alpha: CGFloat = 1
                if p < 0.2 {
                    let k = (p / 0.2) * (p / 0.2)   // falling, faster and faster
                    pos = CGPoint(x: a.x + (c.x - a.x) * k, y: a.y + (c.y - a.y) * k)
                } else if p > 0.8 {
                    let k = (p - 0.8) / 0.2   // smashed away
                    pos = CGPoint(x: c.x + k * 700, y: c.y + k * 500 - k * k * 300)
                    rot = -k * 6
                    alpha = 1 - k
                }
                ctx.saveGState()
                ctx.setAlpha(alpha)
                ctx.translateBy(x: pos.x, y: pos.y + h / 2)
                ctx.rotate(by: rot)
                ctx.draw(img, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                ctx.restoreGState()
            case .rocket:
                let age = now - e.start, px = e.radius
                let img = Self.rocketImage
                let w = CGFloat(img.width) * px, h = CGFloat(img.height) * px
                var y = c.y, alpha: CGFloat = 1
                if age < 2 { alpha = CGFloat(age / 2) }
                if age > 4.5 { y += CGFloat(0.5 * 900 * pow(age - 4.5, 2)) }
                if age > 4.2 {   // flames and smoke
                    for i in 0..<6 {
                        let f = CGFloat((Int(now * 30) + i * 7) % 5)
                        ctx.setFillColor(color(i % 2 == 0 ? 0xFFE066 : 0xFF8A1F, 0.9))
                        ctx.fill(CGRect(x: c.x - w * 0.3 + CGFloat(i) * w * 0.1, y: y - 10 - f * 6, width: w * 0.1, height: 14 + f * 4))
                    }
                    for i in 0..<5 {
                        let k = CGFloat(min(3, age - 4.2)) + CGFloat(i) * 0.3
                        ctx.setFillColor(color(0xCCCCCC, max(0, 0.6 - k * 0.15)))
                        ctx.fillEllipse(in: CGRect(x: c.x + CGFloat(i - 2) * 30 * k - 25, y: c.y - 10, width: 50 + k * 20, height: 30 + k * 10))
                    }
                }
                ctx.saveGState()
                ctx.setAlpha(alpha)
                ctx.draw(img, in: CGRect(x: c.x - w / 2, y: y, width: w, height: h))
                ctx.restoreGState()
                if age > 2.6, age < 4.5 {
                    let n = 3 - Int((age - 2.6) / 0.64)
                    let text = NSAttributedString(string: "\(max(1, n))", attributes: [
                        .font: NSFont.systemFont(ofSize: 40, weight: .black), .foregroundColor: NSColor.white,
                        .strokeColor: NSColor(white: 0.1, alpha: 1), .strokeWidth: -4])
                    text.draw(at: CGPoint(x: c.x - text.size().width / 2, y: c.y + h + 10))
                }
            case .moon(let img):
                guard window.screen == NSScreen.screens.first else { continue }
                let r: CGFloat = 90
                let bob = CGFloat(sin(now * 2) * 4)
                ctx.setFillColor(color(0xE6E2D6, 1))
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.setFillColor(color(0xC9C4B4, 1))
                for (dx, dy, cr) in [(-30.0, 20.0, 18.0), (25.0, -25.0, 14.0), (35.0, 30.0, 10.0), (-20.0, -40.0, 9.0)] {
                    ctx.fillEllipse(in: CGRect(x: c.x + dx - cr, y: c.y + dy - cr, width: cr * 2, height: cr * 2))
                }
                let pw = CGFloat(img.width) * e.radius
                ctx.draw(img, in: CGRect(x: c.x - pw / 2, y: c.y + r - 8 + bob, width: pw, height: pw))
                ctx.setFillColor(color(0xE53935, 1))   // a little flag
                ctx.fill(CGRect(x: c.x + pw * 0.6, y: c.y + r - 4, width: 3, height: 40))
                ctx.fill(CGRect(x: c.x + pw * 0.6 + 3, y: c.y + r + 24, width: 22, height: 14))
            case .hits:
                let img = Particle.image(.fist)
                for i in 0..<6 {
                    let seed = Double(i) * 1.7 + Double(Int(now * 20))
                    let dx = CGFloat(sin(seed * 3.1)) * e.radius, dy = CGFloat(cos(seed * 2.3)) * e.radius
                    ctx.draw(img, in: CGRect(x: c.x + dx - 12, y: c.y + dy - 8, width: 24, height: 16))
                }
                let star = NSAttributedString(string: "✦", attributes: [.font: NSFont.systemFont(ofSize: 26 + 10 * sin(CGFloat(now * 30))),
                                                                        .foregroundColor: NSColor(cgColor: color(e.color, 1)) ?? .white])
                star.draw(at: CGPoint(x: c.x - 10, y: c.y - 14))
            }
        }
    }
}
