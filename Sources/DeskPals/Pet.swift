import AppKit

/// The pet's body and brain: physics, a small state machine, and reactions to what you do.
/// `pos` is the point between its feet, in Cocoa screen coordinates.
final class Pet {
    enum State {
        case idle(until: Double)
        case walk(to: CGFloat, run: Bool)
        case air
        case dragged
        case sleep
        case dance(until: Double)
        case dizzy(until: Double)
    }

    struct Look {
        var pose = Pose.stand
        var eyes = Eyes.open
        var sx: CGFloat = 1, sy: CGFloat = 1
        var rot: CGFloat = 0
        var lift: CGFloat = 0     // in sprite pixels
        var flip = false
    }

    static let musicApps: Set<String> = ["com.spotify.client", "com.apple.Music", "com.apple.iTunes"]
    static let gravity = 2600.0

    private(set) var kind: PetKind
    private(set) var sheet: SpriteSheet
    var scale: CGFloat
    let world: World

    var pos = CGPoint(x: 400, y: 400)
    private var vel = CGVector.zero
    private var facingRight = true
    private(set) var state: State = .air
    private var standingOn: Int?
    private var groundFrame: CGRect?
    private var jumping = false
    private var t = 0.0
    private var squash = 0.0
    private var happyUntil = 0.0
    private var queue: [(at: Double, run: () -> Void)] = []
    private var onLand: (() -> Void)?
    private var onArrive: (() -> Void)?
    private var clickTimes: [Double] = []
    private var dragOffset = CGVector.zero
    private var dragSamples: [(t: Double, p: CGPoint)] = []
    private var dragDistance: CGFloat = 0
    private var bubbleText: String?
    private var bubbleUntil = 0.0
    var speedBoost: CGFloat = 1

    init(kind: PetKind, scale: CGFloat, world: World) {
        self.kind = kind
        self.sheet = SpriteSheet(kind: kind)
        self.scale = scale
        self.world = world
    }

    // MARK: - Queries

    var size: CGFloat { 16 * scale }
    var bodyRect: CGRect { CGRect(x: pos.x - size / 2, y: pos.y, width: size, height: size) }
    var bubble: String? {
        if case .sleep = state, bubbleText == nil { return ["z", "zZ", "zZz"][Int(t / 0.8) % 3] }
        return bubbleText
    }
    var isAsleep: Bool { if case .sleep = state { return true }; return false }
    var isDragged: Bool { if case .dragged = state { return true }; return false }
    var isGrounded: Bool { standingOn != nil }
    /// Idle or walking: free to react to something.
    var isCalm: Bool {
        switch state {
        case .idle, .walk: return isGrounded
        default: return false
        }
    }

    // MARK: - Control

    func setKind(_ k: PetKind) {
        kind = k
        sheet = SpriteSheet(kind: k)
        say(k.sound, 1.5)
        happyUntil = t + 1.5
    }

    func say(_ text: String, _ seconds: Double) {
        bubbleText = text
        bubbleUntil = t + seconds
    }

    func dropIn(atX x: CGFloat) {
        pos = CGPoint(x: clamp(x, world.bounds.minX + size, world.bounds.maxX - size),
                      y: world.screenTop(at: x) - size - 4)
        vel = .zero
        standingOn = nil
        jumping = false
        state = .air
    }

    // MARK: - Tick

    func tick(_ dt: Double) {
        t += dt
        squash = max(0, squash - dt * 5)
        if bubbleText != nil, t > bubbleUntil { bubbleText = nil }
        let due = queue.filter { $0.at <= t }
        queue.removeAll { $0.at <= t }
        due.forEach { $0.run() }

        switch state {
        case .dragged: return
        case .air: physics(dt); return
        default: break
        }
        followGround()
        guard isGrounded else { return }

        switch state {
        case .idle(let until): if t > until { decide() }
        case .walk(let target, let run): walk(toward: target, run: run, dt)
        case .dance(let until), .dizzy(let until): if t > until { hold(0.4) }
        default: break
        }
    }

    /// Ride along with a moving window; fall if the ledge went away or got covered.
    private func followGround() {
        guard let p = world.platform(standingOn) else { fall(); return }
        if let old = groundFrame, p.id > 0 { pos.x += p.frame.minX - old.minX }
        groundFrame = p.frame
        pos.y = p.y
        if !p.holds(pos.x) { fall() }
    }

    private func fall() {
        standingOn = nil
        jumping = false
        vel = CGVector(dx: facingRight ? 40 : -40, dy: 0)
        state = .air
    }

    private func physics(_ dt: Double) {
        let g = Self.gravity * (jumping ? 1 : kind.gravity)
        vel.dy -= g * dt
        if kind.gravity < 1, !jumping { vel.dy = max(vel.dy, -480) }   // glide
        let prevY = pos.y
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt

        let b = world.bounds, half = size / 2
        if pos.x < b.minX + half { pos.x = b.minX + half; vel.dx = abs(vel.dx) * 0.5 }
        if pos.x > b.maxX - half { pos.x = b.maxX - half; vel.dx = -abs(vel.dx) * 0.5 }
        if pos.y > b.maxY - size { pos.y = b.maxY - size; vel.dy = min(vel.dy, 0) }

        if vel.dy <= 0, let p = world.landing(x: pos.x, from: prevY, to: pos.y) {
            land(on: p, impact: -vel.dy)
        } else if pos.y < b.minY - 300 {
            dropIn(atX: pos.x)   // slipped into a gap between screens
        }
    }

    private func land(on p: Platform, impact: Double) {
        pos.y = p.y
        standingOn = p.id
        groundFrame = p.frame
        vel = .zero
        jumping = false
        squash = min(1, impact / 1400)
        if impact > 2300 {
            state = .dizzy(until: t + 2.5)
            say("@_@", 2.5)
        } else {
            hold(.random(in: 0.3...1.0))
        }
        let then = onLand
        onLand = nil
        then?()
    }

    private func walk(toward target: CGFloat, run: Bool, _ dt: Double) {
        let speed = kind.walkSpeed * scale * (run ? 2.4 : 1) * speedBoost
        let dir: CGFloat = target > pos.x ? 1 : -1
        facingRight = dir > 0
        let step = speed * dt
        if abs(target - pos.x) <= step {
            pos.x = target
            hold(.random(in: 0.5...1.5))
            let then = onArrive
            onArrive = nil
            then?()
            return
        }
        let nx = pos.x + dir * step
        if let p = world.platform(standingOn), !p.holds(nx) {
            if run || Double.random(in: 0..<1) < 0.35 {
                pos.x = nx
                launch(CGVector(dx: dir * speed, dy: 160))   // hop off the edge
            } else {
                facingRight.toggle()
                hold(.random(in: 0.4...1.0))
            }
            return
        }
        pos.x = nx
    }

    private func decide() {
        let r = Double.random(in: 0..<1)
        if r < kind.jumpiness, let target = world.hopTarget(from: pos, excluding: standingOn, margin: size / 2) {
            jump(to: target)
            return
        }
        if r < 0.7, let seg = currentSegment() {
            let lo = seg.lowerBound + size / 2, hi = seg.upperBound - size / 2
            if hi - lo > 40 {
                var x = CGFloat.random(in: lo...hi)
                if abs(x - pos.x) < 40 { x = pos.x > (lo + hi) / 2 ? lo : hi }
                walk(to: x, run: false)
                return
            }
        }
        if r > 0.93 { say(kind.sound, 1.2) }
        hold(.random(in: 1.5...4.5))
    }

    // MARK: - Movement helpers

    private func hold(_ seconds: Double) {
        state = .idle(until: t + seconds)
    }

    private func walk(to x: CGFloat, run: Bool, then: (() -> Void)? = nil) {
        onArrive = then
        state = .walk(to: x, run: run)
    }

    private func launch(_ v: CGVector) {
        standingOn = nil
        vel = v
        jumping = true
        state = .air
        if v.dx != 0 { facingRight = v.dx > 0 }
    }

    /// Ballistic jump that lands on `target`, peaking a little above whichever end is higher.
    func jump(to target: CGPoint, then: (() -> Void)? = nil) {
        let g = Self.gravity
        let dy = Double(target.y - pos.y)
        let apex = max(dy, 0) + 70
        let vy = (2 * g * apex).squareRoot()
        let time = vy / g + (2 * (apex - dy) / g).squareRoot()
        launch(CGVector(dx: (target.x - pos.x) / time, dy: vy))
        onLand = then
    }

    private func after(_ seconds: Double, _ run: @escaping () -> Void) {
        queue.append((t + seconds, run))
    }

    private func currentSegment() -> ClosedRange<CGFloat>? {
        world.platform(standingOn)?.segments.first { $0.contains(pos.x) }
    }

    private func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

    // MARK: - Reactions

    func noticeWindow(_ id: Int) {
        guard isCalm, chance(kind.curiosity) else { return }
        say("!", 1)
        hold(1)
        after(0.5) { [weak self] in
            guard let self, self.isCalm, let p = self.world.platform(id),
                  let seg = p.segments.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound })
            else { return }
            let half = self.size / 2
            let x = seg.upperBound - seg.lowerBound > self.size
                ? clamp(p.frame.midX, seg.lowerBound + half, seg.upperBound - half)
                : (seg.lowerBound + seg.upperBound) / 2
            self.jump(to: CGPoint(x: x, y: p.y)) { [weak self] in
                self?.say("?", 1.5)
                self?.hold(2.5)
            }
        }
    }

    func noticeClick(_ p: CGPoint) {
        clickTimes = clickTimes.filter { t - $0 < 2 } + [t]
        if isDragged { return }
        if clickTimes.count >= 7, isGrounded, !isAsleep {
            clickTimes = []
            state = .dizzy(until: t + 3)
            say("@_@", 3)
            return
        }
        let dx = p.x - pos.x, dy = p.y - pos.y
        let dist = hypot(dx, dy)
        if isAsleep {
            if dist < 250 { wake("!") }
            return
        }
        guard isCalm else { return }

        switch kind.clickStyle {
        case .chase:
            guard abs(dx) < 900, dy > -80, dy < 350, chance(0.7), let seg = currentSegment() else { return }
            say("!", 0.8)
            walk(to: clamp(p.x, seg.lowerBound + size / 2, seg.upperBound - size / 2), run: true) { [weak self] in
                guard let self else { return }
                self.say(self.kind.sound, 1)
                self.launch(CGVector(dx: (self.facingRight ? 1 : -1) * 140, dy: 560))   // pounce
            }
        case .startle:
            guard dist < 220 else { return }
            say("!", 1)
            let away: CGFloat = dx > 0 ? -1 : 1
            launch(CGVector(dx: away * 180, dy: 650))
            onLand = { [weak self] in
                guard let self, let seg = self.currentSegment() else { return }
                let x = clamp(self.pos.x + away * 260, seg.lowerBound + self.size / 2, seg.upperBound - self.size / 2)
                self.walk(to: x, run: true)
            }
        }
    }

    func noticeApp(_ bundleID: String, launched: Bool) {
        guard isCalm else { return }
        if Self.musicApps.contains(bundleID) {
            state = .dance(until: t + 6)
            say("♪", 6)
        } else if launched, chance(0.5) {
            say("!", 1)
            launch(CGVector(dx: 0, dy: 420))
        }
    }

    func typingBurst() {
        guard isCalm else { return }
        say(chance(0.5) ? "!!" : "♪", 1.2)
        happyUntil = t + 1.2
        launch(CGVector(dx: 0, dy: 450))
    }

    func typingStopped() {
        guard isCalm else { return }
        say("phew", 1.8)
        hold(2)
    }

    func yawn() {
        guard isCalm else { return }
        say("yawn…", 2)
        hold(2.5)
    }

    @discardableResult
    func fallAsleep() -> Bool {
        guard isCalm else { return false }
        state = .sleep
        bubbleText = nil
        return true
    }

    func wake(_ text: String) {
        guard isAsleep else { return }
        hold(1.5)
        say(text, 2.5)
        happyUntil = t + 1
        launch(CGVector(dx: 0, dy: 380))
    }

    // MARK: - Dragging

    func beginDrag(_ mouse: CGPoint) {
        dragOffset = CGVector(dx: pos.x - mouse.x, dy: pos.y - mouse.y)
        dragSamples = [(CACurrentMediaTime(), mouse)]
        dragDistance = 0
        standingOn = nil
        onLand = nil
        state = .dragged
    }

    func drag(_ mouse: CGPoint) {
        guard isDragged else { return }
        if let last = dragSamples.last { dragDistance += hypot(mouse.x - last.p.x, mouse.y - last.p.y) }
        let now = CACurrentMediaTime()
        dragSamples.append((now, mouse))
        dragSamples.removeAll { now - $0.t > 0.1 }
        if dragDistance > 6, bubbleText == nil { say("!", 0.8) }
        pos = CGPoint(x: mouse.x + dragOffset.dx, y: mouse.y + dragOffset.dy)
    }

    func endDrag(_ mouse: CGPoint) {
        guard isDragged else { return }
        jumping = false
        state = .air
        if dragDistance < 4 {   // a click, not a drag: pets love being petted
            vel = .zero
            say("♥", 1.5)
            happyUntil = t + 1.5
            return
        }
        if let first = dragSamples.first, CACurrentMediaTime() - first.t > 0.005 {
            let dt = CACurrentMediaTime() - first.t
            var v = CGVector(dx: (mouse.x - first.p.x) / dt, dy: (mouse.y - first.p.y) / dt)
            let speed = hypot(v.dx, v.dy)
            if speed > 2600 { v = CGVector(dx: v.dx * 2600 / speed, dy: v.dy * 2600 / speed) }
            vel = v
            if speed > 1200 { say("wheee", 1) }
        } else {
            vel = .zero
        }
    }

    // MARK: - Appearance

    func look() -> Look {
        var l = Look()
        l.flip = !facingRight
        let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.12
        l.eyes = blink ? .closed : .open

        switch state {
        case .walk(_, let run):
            let rate = run ? 12.0 : 7.0
            l.pose = Int(t * rate) % 2 == 0 ? .walkA : .walkB
            if kind.hops {
                let s = abs(sin(t * rate * .pi / 2))
                l.lift = CGFloat(s * 3)
                l.sy = 1 + CGFloat(s - 0.5) * 0.12
                l.sx = 1 - CGFloat(s - 0.5) * 0.08
            }
        case .air:
            l.pose = .air
            let stretch = CGFloat(min(abs(vel.dy) / 2500, 0.18))
            l.sy = 1 + stretch
            l.sx = 1 - stretch * 0.6
        case .dragged:
            l.pose = .air
            l.rot = CGFloat(sin(t * 7) * 0.18)
        case .sleep:
            l.pose = .sleep
            l.eyes = .closed
            l.sy = 1 + CGFloat(sin(t * 1.8) * 0.04)
        case .dance:
            l.pose = Int(t * 6) % 2 == 0 ? .walkA : .walkB
            l.eyes = .happy
            l.rot = CGFloat(sin(t * 6) * 0.2)
            l.lift = CGFloat(abs(sin(t * 6)) * 2)
            l.flip = sin(t * 3) > 0
        case .dizzy:
            l.eyes = .dizzy
            l.rot = CGFloat(sin(t * 9) * 0.12)
        case .idle:
            l.sy = 1 + CGFloat(sin(t * 2.4) * 0.025)
        }
        if happyUntil > t, !isAsleep { l.eyes = .happy }
        if squash > 0 {
            l.sy *= 1 - CGFloat(squash) * 0.3
            l.sx *= 1 + CGFloat(squash) * 0.25
        }
        return l
    }
}
