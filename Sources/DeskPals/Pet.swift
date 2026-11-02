import AppKit

/// The pet's body and brain: physics, a state machine, needs and reactions to what you do.
/// `pos` is the point between its feet, in Cocoa screen coordinates.
final class Pet {
    enum State {
        case idle(until: Double)
        case sit(until: Double)
        case walk(to: CGFloat, run: Bool)
        case air
        case dragged
        case sleep
        case dance(until: Double)
        case dizzy(until: Double)
        case slide
        case climb(side: CGFloat, top: CGFloat)
        case hang(side: CGFloat, until: Double)
        case watch(window: Int)
        case eat(until: Double)
        case groom(until: Double)
        case stretch(until: Double)
        case zoomies(laps: Int)
        case sulk(until: Double)
        case trashed(until: Double)
        // places around the Mac
        case ceiling(dir: CGFloat, until: Double)
        case peek(side: CGFloat, start: Double)
        case hidden(until: Double)
        // places on the desktop
        case swinging(prop: Int, until: Double)
        case sliding(prop: Int, progress: Double)
        case fishing(prop: Int, until: Double)
        case inside(prop: Int, until: Double)
        // mini-games
        case game
        // power moves
        case powerUp(until: Double, move: Special)
        case dash(until: Double, dir: CGFloat)
        case pose(until: Double)
        case hiding(window: Int, until: Double)
    }

    struct Look {
        var pose = Pose.stand
        var eyes = Eyes.open
        var sx: CGFloat = 1, sy: CGFloat = 1
        var rot: CGFloat = 0
        var lift: CGFloat = 0     // in sprite pixels
        var flip = false
        var blush = false
        var glasses = false
        var hidden = false
        var popcorn = false
        var umbrella = false
        var aura: CGFloat = 0
    }

    static let gravity = 2600.0
    /// 0 = calm, 1 = chaotic. Set from Settings.
    static var chaos = 0.4
    static let musicApps: Set<String> = ["com.spotify.client", "com.apple.Music", "com.apple.iTunes"]

    var kind: PetKind
    var sheet: SpriteSheet
    var scale: CGFloat
    var name: String
    /// Platform id of the top of this pet's head, so other pets can stand on it.
    var headID = 0
    /// The other pets on screen.
    var friends: () -> [Pet] = { [] }
    var accessory: Accessory = .none
    /// 0.6 baby, 0.8 kid, 1 grown up.
    var growth: CGFloat = 1
    /// Size of one sprite pixel on screen.
    var px: CGFloat { scale * growth * formScale }
    var aura: CGFloat = 0
    var powerCooldown = 0.0
    var transformedUntil = 0.0
    var formSheet: SpriteSheet?
    var formScale: CGFloat = 1
    var lastStomp = 0.0
    /// Rival face-offs: aura and floating glyphs without a move.
    var menacingUntil = 0.0
    /// What's drawn: the transformed form while it lasts.
    var drawSheet: SpriteSheet { formSheet ?? sheet }
    var umbrella = false
    var shivering = false
    var onClicked: (() -> Void)?
    var gameTarget: CGFloat?
    var watchSecs = 0.0
    var notchVisited = false
    var hideOffset: CGFloat = 0
    /// Set while hiding behind a window in hide & seek; the pet's window goes behind that one.
    var hidingWindowID: Int?
    let world: World
    let needs: Needs
    let props: Props

    var pos = CGPoint(x: 400, y: 400)
    var vel = CGVector.zero
    var facingRight = true
    var state: State = .air
    var standingOn: Int?
    var groundFrame: CGRect?
    var groundMovedAt = 0.0
    var jumping = false
    var airTime = 0.0
    var arcTarget: CGPoint?
    var t = 0.0
    var squash = 0.0
    var happyUntil = 0.0, loveUntil = 0.0, blushUntil = 0.0
    var queue: [(at: Double, run: () -> Void)] = []
    var onLand: (() -> Void)?
    var onArrive: (() -> Void)?
    var bubbleText: String?
    var bubbleUntil = 0.0
    var speedBoost: CGFloat = 1
    var musicPlaying = false
    var particles: [Particle] = []

    // physics extras
    var spinAngle: CGFloat = 0, spinVel: CGFloat = 0
    var trick = false
    var shaken = false
    var hangOffset: CGFloat = 0
    var zoomCenter: CGFloat = 0

    // dragging
    var dragOffset = CGVector.zero
    var dragSamples: [(t: Double, p: CGPoint)] = []
    var dragDistance: CGFloat = 0
    var dragVX: CGFloat = 0
    var dragRot: CGFloat = 0, dragRotVel: CGFloat = 0
    var shakeDir = 0
    var shakeTimes: [Double] = []
    var wasSulking = false
    var thrownTimes: [Double] = []
    var pettings: [Double] = []
    var trashSpot = CGPoint.zero

    // watching videos
    var watchSeat: CGFloat = 0.8
    var watchSince = 0.0
    var nextWatchReact = 0.0
    var nextPopcorn = 0.0
    var watchDeclinedUntil = 0.0

    // cursor, care and chatter
    var cursorPos: CGPoint?
    var strokeDist: CGFloat = 0
    var strokeDir = 0
    var strokeFlips = 0
    var hoverSince: Double?
    var nextWhoosh = 0.0
    var clickTimes: [Double] = []
    var nextNote = 0.0
    var nextCareCheck = 0.0
    var nextGift = 1800.0
    var nextHungerTalk = 0.0
    var complainedAbout = Set<Int>()
    var eating: Prop?
    var lastInteraction = 0.0

    init(kind: PetKind, scale: CGFloat, name: String, world: World, needs: Needs, props: Props) {
        self.kind = kind
        self.sheet = SpriteSheet(kind: kind)
        self.scale = scale
        self.name = name
        self.world = world
        self.needs = needs
        self.props = props
    }

    // MARK: - Queries

    var size: CGFloat { 16 * px }
    var bodyRect: CGRect {
        if isHidden { return .zero }
        if case .hang = state { return CGRect(x: pos.x - size / 2, y: pos.y, width: size, height: size) }
        return CGRect(x: pos.x - size / 2, y: pos.y, width: size, height: size)
    }
    var bubble: String? {
        if isHidden { return nil }
        if case .sleep = state, bubbleText == nil { return ["z", "zZ", "zZz"][Int(t / 0.8) % 3] }
        return bubbleText
    }
    var isAsleep: Bool { if case .sleep = state { return true }; return false }
    var isHidden: Bool {
        switch state {
        case .trashed, .hidden, .inside: return true
        default: return false
        }
    }
    var isDragged: Bool { if case .dragged = state { return true }; return false }
    var isWatching: Bool { if case .watch = state { return true }; return false }
    var isGrounded: Bool { standingOn != nil }
    /// Idle, sitting or walking: free to react to something.
    var isCalm: Bool {
        switch state {
        case .idle, .walk, .sit: return isGrounded
        default: return false
        }
    }
    var facing: CGFloat { facingRight ? 1 : -1 }
    var head: CGPoint { CGPoint(x: pos.x, y: pos.y + size * 0.85) }
    var mouth: CGPoint { CGPoint(x: pos.x + facing * size * 0.38, y: pos.y + size * 0.45) }

    // MARK: - Control

    func setKind(_ k: PetKind, name: String) {
        kind = k
        sheet = SpriteSheet(kind: k)
        self.name = name
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
        arcTarget = nil
        airTime = 0
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
        updateParticles(dt)
        needs.tick(dt, asleep: isAsleep)
        powerTick(dt)
        if scriptedTick(dt) { return }

        switch state {
        case .dragged: dragTick(dt); return
        case .air: physics(dt); return
        case .slide: slide(dt); return
        case .climb(let side, let top): climb(side, top, dt); return
        case .hang(let side, let until): hang(side, until); return
        case .watch(let id): watch(id, dt); return
        case .trashed(let until): if t > until { popOutOfTrash() }; return
        default: break
        }
        followGround()
        guard isGrounded else { return }

        switch state {
        case .idle(let until), .sit(let until):
            idleTick(dt)
            if t > until { decide() }
        case .walk(let target, let run): walk(toward: target, run: run, dt)
        case .dance(let until):
            if t > nextNote { note() }
            if t > until { hold(0.4) }
        case .dizzy(let until), .groom(let until), .stretch(let until), .sulk(let until), .pose(let until):
            if t > until { hold(0.4) }
        case .eat(let until): eatTick(until)
        case .zoomies(let laps): zoomTick(laps, dt)
        default: break
        }
        if isCalm { careTick() }
    }

    /// Ride along with a moving window; fall if the ledge went away or got covered,
    /// and get flung off if the window is thrown around too fast.
    func followGround() {
        guard let p = world.platform(standingOn) else { fall(); return }
        if let old = groundFrame, p.id > 0 {
            let dx = p.frame.minX - old.minX, dy = p.frame.maxY - old.maxY
            if dx != 0 || dy != 0 {
                let span = max(t - groundMovedAt, 1.0 / 60)
                groundMovedAt = t
                pos.x += dx
                pos.y = p.y
                groundFrame = p.frame
                let v = CGVector(dx: dx / span, dy: dy / span)
                if hypot(v.dx, v.dy) > 2400, !isAsleep {
                    say("whoa!", 1)
                    launch(CGVector(dx: v.dx * 0.6, dy: max(v.dy * 0.6, 0) + 300), thrown: true)
                    return
                }
            }
        }
        groundFrame = p.frame
        pos.y = p.y
        if !p.holds(pos.x) { fall() }
    }

    func fall() {
        standingOn = nil
        jumping = false
        airTime = 0
        vel = CGVector(dx: facing * 40, dy: 0)
        state = .air
    }

    func physics(_ dt: Double) {
        airTime += dt
        let glide = kind.gravity < 1 && !jumping && airTime > 0.25
        vel.dy -= Self.gravity * World.gravityScale * (glide ? kind.gravity : 1) * dt
        if glide { vel.dy = max(vel.dy, -460) }
        spinAngle += spinVel * CGFloat(dt)
        let prevY = pos.y
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt

        if let target = arcTarget {
            if vel.dy <= 0, pos.y <= target.y {
                pos = target
                arcTarget = nil
                vel = .zero
                jumping = false
                spinAngle = 0
                spinVel = 0
                hold(1)
                let then = onLand
                onLand = nil
                then?()
            }
            return
        }

        let b = world.bounds, half = size / 2
        if pos.x < b.minX + half || pos.x > b.maxX - half {
            let side: CGFloat = pos.x < b.minX + half ? -1 : 1
            pos.x = side < 0 ? b.minX + half : b.maxX - half
            let speed = abs(vel.dx)
            if kind.climbs, speed > 500, !jumping, Double.random(in: 0..<1) < 0.6 {
                startClimb(side: side)   // grabs the wall instead of bouncing
                return
            }
            vel.dx = -side * speed * 0.5
            if speed > 900 {
                say("bonk!", 0.8)
                squash = 0.6
                spinVel = -spinVel * 0.5
                emit(.dust, at: CGPoint(x: pos.x + side * half, y: pos.y + half), count: 5)
            }
        }
        if pos.y > b.maxY - size {
            pos.y = b.maxY - size
            if vel.dy > 900 { say("ow!", 0.8) }
            vel.dy = min(vel.dy, 0)
        }

        if vel.dy <= 0, let p = world.landing(x: pos.x, from: prevY, to: pos.y, ignoring: headID) {
            land(on: p)
        } else if pos.y < b.minY - 300 {
            dropIn(atX: pos.x)   // slipped into a gap between screens
        }
    }

    func land(on p: Platform) {
        let impact = -vel.dy
        pos.y = p.y
        let dock = p.id == World.dockID
        if impact > 350 { emit(.dust, at: pos, count: min(10, Int(impact / 220)), spread: size * 0.4) }

        // Bounce: slimes are bouncy, and the Dock is a trampoline.
        let restitution = dock && impact > 700 ? max(kind.bounciness, 0.65) : kind.bounciness
        if !jumping || dock, impact > 650, impact * restitution > 260 {
            vel.dy = impact * restitution
            vel.dx *= 0.8
            spinVel *= 0.6
            squash = min(1, impact / 1400)
            if dock, impact > 900, bubbleText == nil { say("boing!", 0.8); Sound.shared.play(.boing) }
            return
        }

        standingOn = p.id
        groundFrame = p.frame
        groundMovedAt = t
        let vx = vel.dx
        let wasThrown = !jumping
        vel = .zero
        squash = min(1, impact / 1400)
        let spun = abs(spinAngle) > 7 && !trick
        spinAngle = 0
        spinVel = 0
        jumping = false
        let then = onLand
        onLand = nil

        if trick {
            trick = false
            say("ta-da!", 1.2)
            happyUntil = t + 1.2
            hold(1)
            return
        }
        if impact > 2300 || spun || shaken {
            shaken = false
            if kind.power != nil, chance(0.5) {   // fights back
                hold(0.4)
                after(0.4) { [weak self] in self?.powerMove() }
                return
            }
            state = .dizzy(until: t + 2.5)
            say("@_@", 2.5)
            emit(.sparkle, at: head, count: 3, vy: 40...90, gravity: 0)
            return
        }
        if wasThrown, abs(vx) > 260 {
            state = .slide
            vel.dx = vx
            return
        }
        hold(.random(in: 0.3...1.0))
        if wasThrown, thrownTimes.filter({ t - $0 < 60 }).count >= 3 {
            thrownTimes = []
            sulk()
            return
        }
        then?()
    }

    func slide(_ dt: Double) {
        guard let p = world.platform(standingOn) else { fall(); return }
        pos.y = p.y
        let dv = 1300 * CGFloat(dt)
        if abs(vel.dx) <= dv {
            vel = .zero
            hold(0.8)
            return
        }
        vel.dx -= vel.dx > 0 ? dv : -dv
        pos.x += vel.dx * dt
        facingRight = vel.dx > 0
        if Int(t * 40) % 3 == 0 { emit(.dust, at: CGPoint(x: pos.x - facing * size * 0.3, y: pos.y), count: 1, life: 0.3...0.5) }
        let b = world.bounds, half = size / 2
        if pos.x < b.minX + half || pos.x > b.maxX - half {
            pos.x = clamp(pos.x, b.minX + half, b.maxX - half)
            vel = .zero
            say("bonk!", 0.8)
            squash = 0.5
            hold(1)
            return
        }
        if !p.holds(pos.x) {
            standingOn = nil
            jumping = false
            airTime = 0
            state = .air
        }
    }

    // MARK: - Climbing and hanging

    func startClimb(side: CGFloat) {
        let b = world.bounds
        standingOn = nil
        vel = .zero
        spinAngle = 0
        spinVel = 0
        jumping = false
        pos.x = side < 0 ? b.minX : b.maxX
        let top = world.screenTop(at: pos.x) - size * 1.3
        state = .climb(side: side, top: min(top, pos.y + .random(in: 200...600)))
        say("!", 0.8)
    }

    func climb(_ side: CGFloat, _ top: CGFloat, _ dt: Double) {
        let b = world.bounds
        pos.x = side < 0 ? b.minX : b.maxX
        pos.y += kind.walkSpeed * scale * 0.8 * CGFloat(dt)
        if pos.y >= top {
            if reachedTopOfWall(side) { return }
            pos.x -= side * size * 0.6
            launch(CGVector(dx: -side * 320, dy: 380))
            say(Bool.random() ? "wheee" : kind.sound, 1)
        }
    }

    func startHang(on p: Platform, edge: CGFloat, side: CGFloat) {
        hangOffset = edge - p.frame.minX
        state = .hang(side: side, until: t + .random(in: 2...4.5))
        say(Bool.random() ? "eep!" : "uh oh", 1.2)
    }

    func hang(_ side: CGFloat, _ until: Double) {
        guard let p = world.platform(standingOn) else { fall(); return }
        pos = CGPoint(x: p.frame.minX + hangOffset, y: p.y - size * 0.92)
        guard t > until else { return }
        if Bool.random() {
            pos = CGPoint(x: pos.x - side * size * 0.5, y: p.y)   // pull up
            squash = 0.4
            say("hup!", 0.8)
            hold(1)
        } else {
            standingOn = nil
            vel = .zero
            jumping = false
            airTime = 0
            state = .air
            say("wah!", 0.8)
        }
    }

    // MARK: - Walking and deciding

    func walk(toward target: CGFloat, run: Bool, _ dt: Double) {
        let tired = needs.fullness < 0.15 || needs.energy < 0.1
        let speed = kind.walkSpeed * scale * (run ? 2.4 : 1) * speedBoost * (tired ? 0.7 : 1)
        let dir: CGFloat = target > pos.x ? 1 : -1
        facingRight = dir > 0
        let step = speed * dt
        if run, Int(t * 20) % 4 == 0 { emit(.dust, at: CGPoint(x: pos.x - dir * size * 0.3, y: pos.y), count: 1, life: 0.3...0.5) }
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
            // A higher ledge right ahead (like the Dock from the floor): hop up onto it.
            if let next = world.step(at: nx + dir * size * 0.3, from: pos.y, excluding: p.id, self: headID), next.y > pos.y + 4 {
                let resume = onArrive
                jump(to: CGPoint(x: nx + dir * size * 0.4, y: next.y)) { [weak self] in
                    self?.walk(to: target, run: run, then: resume)
                }
                return
            }
            let edge = p.segments.first { $0.contains(pos.x) }.map { dir > 0 ? $0.upperBound : $0.lowerBound } ?? pos.x
            if p.id > 0, p.id < Props.bedBase, !run, Double.random(in: 0..<1) < 0.3 {
                pos.x = edge
                startHang(on: p, edge: edge, side: dir)
                return
            }
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

    func decide() {
        let e = needs.energy
        if needs.fullness < 0.25, t > nextHungerTalk {
            nextHungerTalk = t + 150
            say(["hungry…", "food?", "*tummy rumble*"].randomElement()!, 2)
            sitDown(3)
            return
        }
        if e < 0.15, chance(0.4) {
            say("so sleepy…", 1.5)
            sitDown(4)
            return
        }
        if standingOn == World.dockID, chance(0.45), dockHop() { return }
        if kind.climbs, chance(0.05), walkToWall() { return }
        if e > 0.4, chance(kind.zoomy * needs.happiness * 1.5) { startZoomies(); return }
        if decideExtras() { return }
        if kind.clingy, chance(0.2), followCursor() { return }
        if chance(0.07), climbOnFriend() { return }

        let r = Double.random(in: 0..<1)
        if r < kind.jumpiness * (0.5 + e), let target = world.hopTarget(from: pos, excluding: standingOn, self: headID, margin: size / 2) {
            jump(to: target)
            return
        }
        if r < 0.55, let seg = currentSegment() {
            let lo = seg.lowerBound + size / 2, hi = seg.upperBound - size / 2
            if hi - lo > 40 {
                var x = CGFloat.random(in: lo...hi)
                if abs(x - pos.x) < 40 { x = pos.x > (lo + hi) / 2 ? lo : hi }
                walk(to: x, run: false)
                return
            }
        }
        if r < 0.70 { sitDown(.random(in: 3...7)); return }
        if r < 0.76 { say("*lick*", 1); state = .groom(until: t + 2.2); return }
        if r < 0.78 { sneeze(); return }
        if r < 0.81 { state = .stretch(until: t + 1.4); return }
        if r < 0.85, kind.special != .none { specialMove(); return }
        if r < 0.92 { say(kind.phrases.randomElement()!, 1.6) }
        hold(.random(in: 1.5...4))
    }

    func idleTick(_ dt: Double) {
        if let c = cursorPos, abs(c.x - pos.x) < 420, abs(c.y - pos.y) < 300, chance(dt * 0.8) { facingRight = c.x > pos.x }
        if case .sit = state, chance(dt * 0.15) { facingRight.toggle() }
        if musicPlaying {
            if t > nextNote { note() }
            if chance(dt / 40) { state = .dance(until: t + 5); say("♪", 2) }
        }
    }

    func note() {
        nextNote = t + .random(in: 1.2...2.5)
        emit(.note, at: head, count: 1, vx: -30...30, vy: 50...90, gravity: 0, life: 1.2...1.8)
    }

    // MARK: - Movement helpers

    func hold(_ seconds: Double) { state = .idle(until: t + seconds) }
    func sitDown(_ seconds: Double) { state = .sit(until: t + seconds) }

    func walk(to x: CGFloat, run: Bool, then: (() -> Void)? = nil) {
        onArrive = then
        state = .walk(to: x, run: run)
    }

    func launch(_ v: CGVector, thrown: Bool = false) {
        standingOn = nil
        vel = v
        jumping = !thrown
        airTime = 0
        state = .air
        if v.dx != 0 { facingRight = v.dx > 0 }
    }

    /// Ballistic jump that lands on `target`. With `exact`, it lands right there even with no ledge.
    func jump(to target: CGPoint, apex extra: Double = 70, exact: Bool = false, then: (() -> Void)? = nil) {
        let g = Self.gravity * World.gravityScale
        let dy = Double(target.y - pos.y)
        let apex = max(dy, 0) + extra
        let vy = (2 * g * apex).squareRoot()
        let time = vy / g + (2 * (apex - dy) / g).squareRoot()
        launch(CGVector(dx: (target.x - pos.x) / time, dy: vy))
        arcTarget = exact ? target : nil
        onLand = then
    }

    func after(_ seconds: Double, _ run: @escaping () -> Void) {
        queue.append((t + seconds, run))
    }

    func currentSegment() -> ClosedRange<CGFloat>? {
        world.platform(standingOn)?.segments.first { $0.contains(pos.x) }
    }

    func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

    // MARK: - Little behaviours

    func sneeze() {
        say("achoo!", 1)
        emit(.sparkle, at: mouth, count: 3, vx: -80...80, vy: 20...80, gravity: 100)
        launch(CGVector(dx: -facing * 140, dy: 260))
    }

    func specialMove() {
        switch kind.special {
        case .none: break
        case .timeStop, .transform, .auraKick: powerMove()
        case .fire:
            puffFire()
            hold(1.5)
        case .tentacles:
            say(kind.shout ?? "…", 1.4)
            let a = -facing * 60, b = -facing * 280
            emit(.tentacle, at: CGPoint(x: pos.x - facing * size * 0.3, y: pos.y + size * 0.5), count: 16, spread: 4,
                 vx: min(a, b)...max(a, b), vy: 140...340, gravity: 260, life: 0.6...1.0)
            squash = 0.4
            hold(1.5)
        case .spinKick:
            say(kind.shout ?? "hyah!", 1)
            emit(.dust, at: pos, count: 4)
            trick = true
            launch(CGVector(dx: facing * 120, dy: 700))
            spinVel = -facing * .pi * 2 / CGFloat(2 * 700 / Self.gravity)
        case .barrage:
            say(kind.shout ?? "!!!", 1.6)
            let a = facing * 280, b = facing * 620
            emit(.fist, at: CGPoint(x: pos.x + facing * size * 0.55, y: pos.y + size * 0.5), count: 18, spread: 12,
                 vx: min(a, b)...max(a, b), vy: -90...90, gravity: 0, life: 0.15...0.4)
            squash = 0.3
            hold(1.6)
        }
    }

    func puffFire() {
        say("*puff*", 1)
        let a = facing * 140, b = facing * 320
        emit(.fire, at: mouth, count: 8, spread: 2, vx: min(a, b)...max(a, b), vy: -20...60, gravity: -80, life: 0.35...0.6)
    }

    func startZoomies() {
        guard let seg = currentSegment(), seg.upperBound - seg.lowerBound > size * 4 else { return }
        say("zoom!", 1)
        zoomCenter = pos.x
        state = .zoomies(laps: Int.random(in: 3...6))
    }

    func zoomTick(_ laps: Int, _ dt: Double) {
        guard let seg = currentSegment() else { hold(0.5); return }
        let lo = max(seg.lowerBound + size / 2, zoomCenter - 280), hi = min(seg.upperBound - size / 2, zoomCenter + 280)
        let target = facingRight ? hi : lo
        let step = kind.walkSpeed * scale * 3.6 * CGFloat(dt)
        if Int(t * 30) % 2 == 0 { emit(.dust, at: CGPoint(x: pos.x - facing * size * 0.3, y: pos.y), count: 1, life: 0.25...0.4) }
        if abs(target - pos.x) <= step {
            pos.x = target
            facingRight.toggle()
            if laps <= 1 {
                say("hehe", 1.2)
                happyUntil = t + 1.5
                hold(1.5)
            } else {
                state = .zoomies(laps: laps - 1)
            }
        } else {
            pos.x += facing * step
        }
    }

    func walkToWall() -> Bool {
        guard let seg = currentSegment() else { return false }
        let b = world.bounds
        let left = seg.lowerBound <= b.minX + 2, right = seg.upperBound >= b.maxX - 2
        guard left || right else { return false }
        let side: CGFloat = left && right ? (pos.x < b.midX ? -1 : 1) : (left ? -1 : 1)
        walk(to: side < 0 ? b.minX + size / 2 : b.maxX - size / 2, run: true) { [weak self] in
            self?.startClimb(side: side)
        }
        return true
    }

    func followCursor() -> Bool {
        guard let c = cursorPos, let seg = currentSegment(), abs(c.x - pos.x) > 120 else { return false }
        walk(to: clamp(c.x, seg.lowerBound + size / 2, seg.upperBound - size / 2), run: false)
        if chance(0.3) { say(["hug?", "wait for me!", "*bloop bloop*"].randomElement()!, 1.4) }
        return true
    }

    func sulk() {
        state = .sulk(until: t + 15)
        say("hmph", 2)
        if let c = cursorPos { facingRight = c.x < pos.x }
    }

    // MARK: - Friends

    /// The top of this pet's head, as a tiny ledge for other pets.
    var headPlatform: Platform? {
        guard isGrounded else { return nil }
        switch state {
        case .hang, .trashed, .climb, .watch: return nil
        default: break
        }
        let top = pos.y + size * (isAsleep ? 0.62 : 0.88)
        let w = size * 0.6
        let frame = CGRect(x: pos.x - w / 2, y: pos.y, width: w, height: top - pos.y)
        return Platform(id: headID, frame: frame, y: top, segments: [frame.minX...frame.maxX])
    }

    func climbOnFriend() -> Bool {
        guard let f = friends().filter({ $0 !== self && $0.isCalm && $0.standingOn != headID && abs($0.pos.x - pos.x) < 500 }).randomElement(),
              let head = f.headPlatform else { return false }
        say(["hop!", "up I go", "tower time!"].randomElement()!, 1.2)
        jump(to: CGPoint(x: f.pos.x, y: head.y)) { [weak self] in
            guard let self else { return }
            self.happyUntil = self.t + 1.5
            if (f.standingOn ?? 0) >= 4_000_000 { self.say("tower!", 1.5); Economy.shared.record(.tower) }
            self.sitDown(4)
        }
        return true
    }

    /// Two pets bumped into each other.
    func greet(_ other: Pet) {
        guard isCalm else { return }
        facingRight = other.pos.x > pos.x
        say(["hi \(other.name)!", "hey!", kind.sound, "♥"].randomElement()!, 1.6)
        happyUntil = t + 1.5
        sitDown(2)
    }

    /// Tag: one runs off, the other chases.
    func runFrom(_ other: Pet) {
        guard let seg = currentSegment() else { return }
        let dir: CGFloat = pos.x > other.pos.x ? 1 : -1
        say("can't catch me!", 1.4)
        walk(to: clamp(pos.x + dir * 400, seg.lowerBound + size / 2, seg.upperBound - size / 2), run: true)
    }

    func chase(_ other: Pet) {
        guard let seg = currentSegment() else { return }
        after(0.5) { [weak self, weak other] in
            guard let self, let other, self.isCalm else { return }
            self.say("tag!", 1)
            self.walk(to: clamp(other.pos.x, seg.lowerBound + self.size / 2, seg.upperBound - self.size / 2), run: true)
        }
    }

    // MARK: - Dock

    func dockHop() -> Bool {
        guard let dock = world.dock else { return false }
        let items = dock.items.sorted { $0.frame.midX < $1.frame.midX }
        guard let i = items.indices.min(by: { abs(items[$0].frame.midX - pos.x) < abs(items[$1].frame.midX - pos.x) }) else { return false }
        let j = clamp(i + (Bool.random() ? 1 : -1) * Int.random(in: 1...4), 0, items.count - 1)
        guard j != i else { return false }
        hopAlongDock(items, from: i, to: j)
        return true
    }

    func hopAlongDock(_ items: [DockItem], from i: Int, to j: Int) {
        let next = i + (j > i ? 1 : -1)
        guard let top = world.dock?.top else { return }
        jump(to: CGPoint(x: items[next].frame.midX, y: top), apex: 28) { [weak self] in
            guard let self else { return }
            if items[next].isTrash, self.chance(0.6) { self.say("eww", 1) }
            if next != j {
                self.after(0.12) { [weak self] in
                    guard let self, self.isCalm, self.standingOn == World.dockID else { return }
                    self.hopAlongDock(items, from: next, to: j)
                }
            }
        }
    }

    /// Hop onto the Dock icon of an app that just opened.
    func visitDockIcon(named name: String) {
        guard isCalm, let dock = world.dock, let item = dock.items.first(where: { $0.title == name }) else { return }
        say("!", 0.8)
        jump(to: CGPoint(x: item.frame.midX, y: dock.top)) { [weak self] in
            guard let self else { return }
            self.say(["hi \(name)!", "ooh, \(name)", "*pat pat*"].randomElement()!, 1.8)
            self.happyUntil = self.t + 1.5
            self.sitDown(2.5)
        }
    }

    // MARK: - Care: food, toys, gifts

    func careTick() {
        guard t > nextCareCheck else { return }
        nextCareCheck = t + 0.5
        if let food = props.foods.filter({ $0.grounded }).min(by: { abs($0.pos.x - pos.x) < abs($1.pos.x - pos.x) }),
           abs(food.pos.x - pos.x) < 1600, case .food(let f) = food.kind {
            if needs.fullness > 0.92, f != kind.favorite {
                if complainedAbout.insert(food.id).inserted { say("I'm full…", 1.5) }
            } else {
                goEat(food)
                return
            }
        }
        if let ball = props.ball, !ball.dragged, needs.energy > 0.15, chance(0.6), abs(ball.pos.x - pos.x) < 1400 {
            chase(ball)
            return
        }
        if needs.happiness > 0.85, needs.level >= 1, t > nextGift {
            nextGift = t + .random(in: 1800...3600)
            props.add(.gift, at: CGPoint(x: pos.x + facing * size * 0.7, y: pos.y + size * 0.6), vel: CGVector(dx: facing * 120, dy: 250))
            say("for you!", 2)
            happyUntil = t + 2
        }
    }

    func goEat(_ food: Prop) {
        let side: CGFloat = food.pos.x > pos.x ? 1 : -1
        let x = food.pos.x - side * size * 0.35
        let arrive: () -> Void = { [weak self] in self?.startEating(food) }
        if food.groundID == standingOn {
            walk(to: x, run: true, then: arrive)
        } else {
            jump(to: CGPoint(x: x, y: food.pos.y), then: arrive)
        }
    }

    func startEating(_ food: Prop) {
        guard !food.dead, abs(food.pos.x - pos.x) < size, abs(food.pos.y - pos.y) < size else { return }
        facingRight = food.pos.x > pos.x
        eating = food
        say("nom", 1)
        Sound.shared.play(.munch)
        state = .eat(until: t + 2.4)
    }

    func eatTick(_ until: Double) {
        guard let food = eating, !food.dead else { eating = nil; hold(0.5); return }
        if Int(t * 8) % 3 == 0 { emit(.crumb, at: mouth, count: 1, vx: -50...50, vy: 30...90, gravity: 500, life: 0.3...0.6) }
        guard t > until else { return }
        let fav: Bool
        if case .food(let f) = food.kind { fav = f == kind.favorite } else { fav = false }
        props.remove(food)
        eating = nil
        needs.fed(favorite: fav)
        Economy.shared.record(.fed)
        if fav { Economy.shared.record(.favorite) }
        lastInteraction = t
        if fav {
            say("yum!! my favorite", 2)
            loveUntil = t + 2
            blushUntil = t + 2.5
            emit(.heart, at: head, count: 4, vx: -50...50, vy: 60...120, gravity: 0, life: 1...1.5)
        } else {
            say("yum", 1.2)
            happyUntil = t + 1.5
        }
        hold(1.2)
    }

    func chase(_ ball: Prop) {
        guard let seg = currentSegment() else { return }
        let reachable = ball.groundID == standingOn || (!ball.grounded && abs(ball.pos.y - pos.y) < size * 2)
        if reachable {
            walk(to: clamp(ball.pos.x, seg.lowerBound + size / 2, seg.upperBound - size / 2), run: true) { [weak self] in
                self?.kick(ball)
            }
        } else if ball.grounded {
            jump(to: ball.pos) { [weak self] in self?.kick(ball) }
        }
    }

    func kick(_ ball: Prop) {
        guard !ball.dead, abs(ball.pos.x - pos.x) < size * 0.9, abs(ball.pos.y - pos.y) < size else { return }
        ball.groundID = nil
        ball.vel = CGVector(dx: facing * .random(in: 350...700), dy: .random(in: 250...600))
        emit(.dust, at: CGPoint(x: ball.pos.x, y: ball.pos.y), count: 3)
        needs.played()
        Economy.shared.record(.kicked)
        Sound.shared.play(.pop)
        lastInteraction = t
        if chance(0.5) { say(Bool.random() ? "hehe" : kind.sound, 1) }
        happyUntil = t + 1
    }

    func giftOpened() {
        say(["it's a shiny rock!", "a flower for you", "found a feather!", "a pretty shell!"].randomElement()!, 2.5)
        happyUntil = t + 2
        emit(.heart, at: head, count: 2, vy: 60...110, gravity: 0, life: 1...1.4)
    }

    // MARK: - Videos

    /// `seat` is how far along the bottom of the video to sit, 0...1.
    func startWatching(_ win: WindowInfo, seat: CGFloat = .random(in: 0.55...0.9)) -> Bool {
        guard isCalm, t > watchDeclinedUntil else { return false }
        watchSeat = seat
        let seat = CGPoint(x: win.frame.minX + win.frame.width * watchSeat, y: win.frame.minY + 2)
        say(["ooh, a video!", "movie time!", "what are we watching?"].randomElement()!, 1.8)
        jump(to: seat, exact: true) { [weak self] in
            guard let self else { return }
            self.standingOn = nil
            self.state = .watch(window: win.id)
            self.watchSince = self.t
            self.nextWatchReact = self.t + .random(in: 15...30)
        }
        return true
    }

    func stopWatching(_ text: String?) {
        guard isWatching else { return }
        if let text { say(text, 2) }
        standingOn = nil
        jumping = true
        airTime = 0
        vel = CGVector(dx: 0, dy: 300)
        state = .air
    }

    func watch(_ id: Int, _ dt: Double) {
        guard let w = world.windowInfo(id) else { stopWatching("aw…"); return }
        pos = CGPoint(x: w.frame.minX + w.frame.width * watchSeat, y: w.frame.minY + 2)
        needs.watched(dt)
        watchSecs += dt
        if watchSecs >= 60 { watchSecs = 0; Economy.shared.record(.watchedMinute) }
        let long = t - watchSince > 1500
        if !long, t > nextPopcorn {
            nextPopcorn = t + .random(in: 1.5...4)
            emit(.popcorn, at: CGPoint(x: pos.x + size * 0.5, y: pos.y + size * 0.35), count: 1,
                 vx: -90 ... -40, vy: 120...200, gravity: 500, life: 0.5...0.7)
        }
        if t > nextWatchReact {
            nextWatchReact = t + .random(in: 25...60)
            say(long ? "zZ" : ["haha", "!", "ooh", "♥", "wow", "*munch*", "no way!", "hehe"].randomElement()!, 1.6)
        }
    }

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
                self?.sitDown(2.5)
            }
        }
    }

    func noticeClick(_ p: CGPoint) {
        clickTimes = clickTimes.filter { t - $0 < 2 } + [t]
        if isDragged || isWatching { return }
        if clickTimes.count >= 7, isGrounded, !isAsleep {
            clickTimes = []
            if kind.power != nil, chance(0.5), powerMove() { return }
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
                if self.kind.special == .spinKick { self.specialMove(); return }
                self.say(self.kind.sound, 1)
                self.launch(CGVector(dx: self.facing * 140, dy: 560))   // pounce
            }
        case .startle:
            guard dist < 220 else { return }
            if kind.power != nil, chance(0.2), powerMove() { return }
            say("!", 1)
            if kind.special == .barrage { specialMove(); return }
            if kind.special != .none { specialMove() }
            let away: CGFloat = dx > 0 ? -1 : 1
            launch(CGVector(dx: away * 180, dy: 650))
            onLand = { [weak self] in
                guard let self, let seg = self.currentSegment() else { return }
                let x = clamp(self.pos.x + away * 260, seg.lowerBound + self.size / 2, seg.upperBound - self.size / 2)
                self.walk(to: x, run: true)
            }
        }
    }

    /// Reactions to the app you just switched to.
    func reactToApp(_ bundleID: String, name: String) {
        guard isCalm else { return }
        if Self.musicApps.contains(bundleID) {
            state = .dance(until: t + 6)
            say("♪", 6)
            return
        }
        guard let r = AppReactions.find(bundleID) else { return }
        say(r.lines.randomElement()!.replacingOccurrences(of: "{app}", with: name), 1.8)
        switch r.action {
        case .hop: launch(CGVector(dx: 0, dy: 420))
        case .excited: launch(CGVector(dx: 0, dy: 520)); happyUntil = t + 2
        case .focus: sitDown(6)
        case .curious: facingRight.toggle(); sitDown(2)
        case .sweat:
            emit(.sweat, at: head, count: 3, vx: -40...40, vy: 40...90, gravity: 400)
            sitDown(2)
        case .jealous: sulk()
        case .none: break
        }
    }

    func appLaunched(name: String) {
        if world.dock != nil, chance(0.6) { visitDockIcon(named: name) }
        else if isCalm, chance(0.4) { say("!", 1); launch(CGVector(dx: 0, dy: 420)) }
    }

    /// You switched apps: if we're standing on a window that belongs to another app, hop down to the ground.
    func appSwitched(to pid: pid_t) {
        guard let id = standingOn, id > 0, id < Props.bedBase,
              let w = world.windowInfo(id), w.pid != pid else { return }
        after(0.35) { [weak self] in
            guard let self, self.isCalm, self.standingOn == id else { return }
            self.dropToGround()
        }
    }

    func spaceChanged() {
        if isWatching { stopWatching(nil) }
        if let id = standingOn, id > 0, id < Props.bedBase { dropToGround() }
    }

    func dropToGround() {
        say(["whoa", "oop!", "down I go"].randomElement()!, 1)
        let floor = world.platforms.filter { $0.id < 0 && $0.y < pos.y && $0.holds(pos.x) }.max { $0.y < $1.y }
        if let f = floor { jump(to: CGPoint(x: pos.x, y: f.y), apex: 40) } else { fall() }
    }

    func typingBurst() {
        guard isCalm else { return }
        if kind.power != nil, chance(0.25), powerMove() { return }
        say(chance(0.5) ? "!!" : "♪", 1.2)
        happyUntil = t + 1.2
        launch(CGVector(dx: 0, dy: 450))
    }

    func typingStopped() {
        guard isCalm else { return }
        say("phew", 1.8)
        state = .stretch(until: t + 1.4)
    }

    func yawn() {
        guard isCalm else { return }
        say("yawn…", 2)
        sitDown(2.5)
    }

    func remark(_ text: String, hop: Bool = false) {
        guard isCalm || isWatching else { return }
        say(text, 2.5)
        if hop, isCalm { launch(CGVector(dx: 0, dy: 380)) }
    }

    func batteryLow() {
        guard isCalm else { return }
        say("battery low…", 2.5)
        emit(.sweat, at: head, count: 2, vy: 40...80, gravity: 400)
        sitDown(4)
    }

    func pluggedIn() {
        guard isCalm else { return }
        say("yum, power!", 2)
        happyUntil = t + 2
        launch(CGVector(dx: 0, dy: 420))
    }

    func bored() {
        guard isCalm, let c = cursorPos, let seg = currentSegment() else { return }
        say("play with me?", 2.5)
        walk(to: clamp(c.x, seg.lowerBound + size / 2, seg.upperBound - size / 2), run: false)
    }

    @discardableResult
    func fallAsleep() -> Bool {
        guard isCalm else { return false }
        if let bed = props.bed, bed.grounded, standingOn != Props.bedBase + bed.id {
            say("bedtime", 1.2)
            jump(to: CGPoint(x: bed.pos.x, y: bed.rect.minY + bed.rect.height * 0.6)) { [weak self] in
                guard let self, self.standingOn != nil else { return }
                self.state = .sleep
                self.bubbleText = nil
            }
            return true
        }
        state = .sleep
        bubbleText = nil
        return true
    }

    func wake(_ text: String) {
        guard isAsleep else { return }
        say(text, 2.5)
        happyUntil = t + 1
        state = .stretch(until: t + 1.4)
    }

    // MARK: - Cursor

    func trackCursor(_ p: CGPoint, _ dt: Double, pressed: Bool) {
        let v = cursorPos.map { CGVector(dx: (p.x - $0.x) / dt, dy: (p.y - $0.y) / dt) } ?? .zero
        cursorPos = p
        guard dt > 0, !isDragged, !pressed else { return }
        let speed = hypot(v.dx, v.dy)
        let center = CGPoint(x: pos.x, y: pos.y + size / 2)
        let dist = hypot(p.x - center.x, p.y - center.y)

        // Stroking: rub the cursor back and forth over the pet.
        if bodyRect.insetBy(dx: -4, dy: -4).contains(p), speed > 120 {
            strokeDist += speed * CGFloat(dt)
            let dir = v.dx > 0 ? 1 : -1
            if dir != strokeDir { strokeDir = dir; strokeFlips += 1 }
            if strokeDist > 260, strokeFlips >= 3 {
                strokeDist = 0
                strokeFlips = 0
                stroked()
            }
        } else if !bodyRect.insetBy(dx: -30, dy: -30).contains(p) {
            strokeDist = max(0, strokeDist - 400 * CGFloat(dt))
            strokeFlips = 0
        }

        // The cursor whooshing past knocks it off balance.
        if speed > 4200, dist < size * 1.4, isCalm, t > nextWhoosh {
            nextWhoosh = t + 3
            say("whoa!", 0.8)
            launch(CGVector(dx: (v.dx > 0 ? 1 : -1) * 160, dy: 300))
        }

        // Chasers pounce at a cursor that hovers just above them.
        if kind.clickStyle == .chase, isCalm, speed < 40, p.y > pos.y + size, p.y < pos.y + size + 240, abs(p.x - pos.x) < 160 {
            if let since = hoverSince {
                if t - since > 1.4 {
                    hoverSince = nil
                    say("!", 0.6)
                    let rise = Double(p.y - pos.y) + 10
                    launch(CGVector(dx: (p.x - pos.x) * 1.2, dy: (2 * Self.gravity * rise).squareRoot()))
                }
            } else {
                hoverSince = t
            }
        } else {
            hoverSince = nil
        }
    }

    func stroked() {
        lastInteraction = t
        needs.petted()
        Economy.shared.record(.petted)
        Sound.shared.play(kind.id == "mochi" ? .purr : .ding, pitch: Double(1.4 - growth * 0.4))
        loveUntil = t + 1.5
        blushUntil = t + 2
        emit(.heart, at: head, count: 2, vx: -40...40, vy: 60...110, gravity: 0, life: 0.9...1.3)
        if bubbleText == nil { say(isAsleep ? "zz… ♥" : (kind.id == "mochi" ? "purr…" : "♥"), 1.2) }
    }

    // MARK: - Dragging

    func beginDrag(_ mouse: CGPoint) {
        if isWatching { watchDeclinedUntil = t + 120 }
        if case .sulk = state { wasSulking = true } else { wasSulking = false }
        dragOffset = CGVector(dx: pos.x - mouse.x, dy: pos.y - mouse.y)
        dragSamples = [(CACurrentMediaTime(), mouse)]
        dragDistance = 0
        dragVX = 0
        dragRot = 0
        dragRotVel = 0
        shakeTimes = []
        shaken = false
        standingOn = nil
        onLand = nil
        onArrive = nil
        arcTarget = nil
        eating = nil
        state = .dragged
    }

    func drag(_ mouse: CGPoint) {
        guard isDragged else { return }
        if let last = dragSamples.last { dragDistance += hypot(mouse.x - last.p.x, mouse.y - last.p.y) }
        let now = CACurrentMediaTime()
        dragSamples.append((now, mouse))
        dragSamples.removeAll { now - $0.t > 0.1 }
        if let first = dragSamples.first, now - first.t > 0.005 { dragVX = (mouse.x - first.p.x) / (now - first.t) }
        if dragDistance > 6, bubbleText == nil { say("!", 0.8) }
        pos = CGPoint(x: mouse.x + dragOffset.dx, y: mouse.y + dragOffset.dy)

        // Shaking it back and forth makes it dizzy.
        if abs(dragVX) > 700 {
            let dir = dragVX > 0 ? 1 : -1
            if dir != shakeDir { shakeDir = dir; shakeTimes.append(t) }
        }
        shakeTimes.removeAll { t - $0 > 1.2 }
        if shakeTimes.count >= 5, !shaken {
            shaken = true
            say("ahh!", 1)
            emit(.sweat, at: head, count: 3, vy: 40...90, gravity: 400)
        }
    }

    /// Swings like a pendulum from the cursor.
    func dragTick(_ dt: Double) {
        let target = clamp(-dragVX / 1800, -0.7, 0.7)
        dragRotVel += ((target - dragRot) * 120 - dragRotVel * 10) * CGFloat(dt)
        dragRot += dragRotVel * CGFloat(dt)
        dragVX *= 0.9
    }

    func endDrag(_ mouse: CGPoint) {
        guard isDragged else { return }
        jumping = false
        airTime = 0
        state = .air
        if let trash = world.dock?.trash, trash.frame.insetBy(dx: -6, dy: -6).contains(mouse) {
            trashSpot = CGPoint(x: trash.frame.midX, y: trash.frame.maxY)
            state = .trashed(until: t + 2.5)
            bubbleText = nil
            return
        }
        if dragDistance < 4 {   // a click, not a drag
            vel = .zero
            petted()
            return
        }
        if let first = dragSamples.first, CACurrentMediaTime() - first.t > 0.005 {
            let dt = CACurrentMediaTime() - first.t
            var v = CGVector(dx: (mouse.x - first.p.x) / dt, dy: (mouse.y - first.p.y) / dt)
            let speed = hypot(v.dx, v.dy)
            if speed > 2600 { v = CGVector(dx: v.dx * 2600 / speed, dy: v.dy * 2600 / speed) }
            vel = v
            if speed > 900 {
                spinVel = clamp(-v.dx / (size * 1.1), -16, 16)
                thrownTimes.append(t)
                needs.thrown()
                Economy.shared.record(.thrown)
                say("wheee", 1)
                Sound.shared.play(.whoosh)
            }
        } else {
            vel = .zero
        }
    }

    func petted() {
        lastInteraction = t
        needs.petted()
        Economy.shared.record(.petted)
        if let found = onClicked { onClicked = nil; found(); return }
        if wasSulking {
            say("…fine ♥", 1.5)
            happyUntil = t + 1.5
            return
        }
        pettings = pettings.filter { t - $0 < 6 } + [t]
        if pettings.count >= 4 {
            pettings = []
            say("♥♥♥", 1.8)
            loveUntil = t + 2
            blushUntil = t + 2.5
            emit(.heart, at: head, count: 5, vx: -60...60, vy: 60...130, gravity: 0, life: 1...1.6)
        } else {
            say("♥", 1.5)
            happyUntil = t + 1.5
            emit(.heart, at: head, count: 1, vy: 60...100, gravity: 0, life: 0.9...1.2)
        }
    }

    /// Double-click: a big jump with a flip.
    func superJump() {
        guard !isDragged else { return }
        if case .trashed = state { return }
        if isAsleep { wake("!"); return }
        trick = true
        launch(CGVector(dx: 0, dy: 1500))
        spinVel = -facing * .pi * 2 / CGFloat(2 * 1500 / Self.gravity)
        say("boing!", 1)
        Sound.shared.play(.boing)
    }

    func popOutOfTrash() {
        pos = trashSpot
        let b = world.bounds
        launch(CGVector(dx: pos.x > b.midX ? -260 : 260, dy: 1100), thrown: true)
        say("hey!!", 2)
        onLand = { [weak self] in self?.sulk() }
    }

    // MARK: - Particles

    func emit(_ k: ParticleKind, at p: CGPoint, count: Int, spread: CGFloat = 6,
              vx: ClosedRange<CGFloat> = -60...60, vy: ClosedRange<CGFloat> = 60...160,
              gravity: CGFloat = 300, life: ClosedRange<Double> = 0.5...0.9, color: UInt32 = 0) {
        for _ in 0..<max(0, count) {
            let l = Double.random(in: life)
            particles.append(Particle(pos: CGPoint(x: p.x + .random(in: -spread...spread), y: p.y + .random(in: -spread / 2...spread / 2)),
                                      vel: CGVector(dx: .random(in: vx), dy: .random(in: vy)),
                                      life: l, maxLife: l, kind: k, gravity: gravity, color: color))
        }
        if particles.count > 150 { particles.removeFirst(particles.count - 150) }
    }

    func updateParticles(_ dt: Double) {
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].vel.dy -= particles[i].gravity * CGFloat(dt)
            particles[i].pos.x += particles[i].vel.dx * CGFloat(dt)
            particles[i].pos.y += particles[i].vel.dy * CGFloat(dt)
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: - Appearance

    func look() -> Look {
        var l = Look()
        l.flip = !facingRight
        l.glasses = accessory == .sunglasses
        var eyes: Eyes = .open
        if let c = cursorPos, abs(c.x - pos.x) > 10 { eyes = (c.x > pos.x) == facingRight ? .open : .openAway }
        if needs.happiness < 0.3 || needs.fullness < 0.12 { eyes = .sad }
        if t.truncatingRemainder(dividingBy: 3.7) < 0.12 { eyes = .closed }
        if happyUntil > t { eyes = .happy }
        if loveUntil > t { eyes = .love }
        l.eyes = eyes
        l.blush = blushUntil > t

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
        case .zoomies:
            l.pose = Int(t * 16) % 2 == 0 ? .walkA : .walkB
            l.rot = -facing * 0.12
            l.eyes = .happy
        case .air:
            l.pose = .air
            let stretch = CGFloat(min(abs(vel.dy) / 2500, 0.18))
            l.sy = 1 + stretch
            l.sx = 1 - stretch * 0.6
            l.rot = spinAngle
            if kind.gravity < 1, !jumping, airTime > 0.25 { l.lift = CGFloat(abs(sin(t * 14)) * 1.5) }   // flapping
        case .slide:
            l.pose = .stand
            l.rot = vel.dx > 0 ? 0.25 : -0.25
            l.eyes = .open
        case .dragged:
            l.pose = .air
            l.rot = dragRot
            if shaken { l.eyes = .dizzy }
        case .sleep:
            l.pose = .sleep
            l.eyes = .closed
            l.sy = 1 + CGFloat(sin(t * 1.8) * 0.04)
        case .sit:
            l.pose = .sit
            l.sy = 1 + CGFloat(sin(t * 2.4) * 0.025)
            if musicPlaying { l.lift = CGFloat(abs(sin(t * .pi * 2))) }
        case .dance:
            l.pose = Int(t * 6) % 2 == 0 ? .walkA : .walkB
            l.eyes = .happy
            l.rot = CGFloat(sin(t * 6) * 0.2)
            l.lift = CGFloat(abs(sin(t * 6)) * 2)
            l.flip = sin(t * 3) > 0
        case .dizzy:
            l.eyes = .dizzy
            l.rot = CGFloat(sin(t * 9) * 0.12)
        case .climb(let side, _):
            l.pose = Int(t * 8) % 2 == 0 ? .walkA : .walkB
            l.rot = side < 0 ? -.pi / 2 : .pi / 2
            l.flip = side < 0
        case .hang:
            l.pose = .air
            l.rot = CGFloat(sin(t * 3) * 0.12)
            l.eyes = .open
        case .watch:
            l.pose = .back
            l.popcorn = t - watchSince < 1500
            if t - watchSince > 1500 { l.sy = 0.94; l.rot = 0.06 }
        case .eat:
            l.pose = .sit
            l.sy = 1 + CGFloat(sin(t * 16) * 0.05)
            if eyes != .love { l.eyes = Int(t * 3) % 2 == 0 ? .happy : .closed }
        case .groom:
            l.pose = .sit
            l.eyes = .closed
            l.rot = CGFloat(sin(t * 5) * 0.08)
        case .stretch(let until):
            let p = CGFloat(max(0, min(1, (until - t) / 1.4)))
            l.sx = 1 + 0.25 * sin(p * .pi)
            l.sy = 1 - 0.18 * sin(p * .pi)
            l.eyes = .closed
        case .sulk:
            l.pose = .sit
            l.eyes = .angry
        case .trashed, .hidden, .inside:
            l.hidden = true
        case .ceiling:
            l.pose = .air
            l.rot = CGFloat(sin(t * 6) * 0.15)
        case .peek:
            l.pose = .stand
        case .swinging(let id, _):
            l.pose = .sit
            l.eyes = .happy
            l.rot = props.items.first { $0.id == id }?.swingAngle ?? 0
        case .sliding:
            l.pose = .sit
            l.eyes = .happy
            l.rot = -0.6
        case .fishing:
            l.pose = .sit
            if kind.hops { l.lift = CGFloat(sin(t * 2) * 0.6) }
        case .game:
            let moving = gameTarget.map { abs($0 - pos.x) > 4 } ?? false
            l.pose = moving ? (Int(t * 12) % 2 == 0 ? .walkA : .walkB) : .stand
        case .hiding:
            l.pose = .stand
        case .powerUp:
            l.pose = .stand
            l.eyes = .angry
            l.sy = 0.92
            l.rot = CGFloat(sin(t * 50) * 0.03)
        case .pose:
            l.pose = .stand
            l.eyes = .angry
            l.rot = facing * CGFloat(0.28 + sin(t * 2) * 0.04)
            l.sx = 0.92
            l.sy = 1.08
        case .dash:
            l.pose = Int(t * 20) % 2 == 0 ? .walkA : .walkB
            l.rot = -facing * 0.25
            l.eyes = .angry
        case .idle:
            l.sy = 1 + CGFloat(sin(t * 2.4) * 0.025)
            if musicPlaying { l.lift = CGFloat(abs(sin(t * .pi * 2))) }
        }
        if shivering, !isAsleep { l.rot += CGFloat(sin(t * 60) * 0.03) }
        l.umbrella = umbrella && !l.hidden && !isWatching
        l.aura = aura
        if squash > 0 {
            l.sy *= 1 - CGFloat(squash) * 0.3
            l.sx *= 1 + CGFloat(squash) * 0.25
        }
        return l
    }
}

/// What the pet says and does when you switch to particular apps.
enum AppReactions {
    enum Action { case none, hop, excited, focus, curious, sweat, jealous }

    static let table: [(prefix: String, lines: [String], action: Action)] = [
        ("com.apple.dt.Xcode", ["code time!", "build it!", "no bugs today"], .focus),
        ("com.microsoft.VSCode", ["code time!", "bugs beware", "*nerd glasses on*"], .focus),
        ("com.apple.Terminal", ["hacker mode", "beep boop"], .focus),
        ("com.googlecode.iterm2", ["hacker mode", "beep boop"], .focus),
        ("com.anthropic", ["hi Claude!", "Claude's my friend"], .hop),
        ("com.openai", ["who's that?", "hmph"], .jealous),
        ("com.roblox", ["game time!!", "can I play?"], .excited),
        ("com.apple.mail", ["mail!", "anything for me?"], .hop),
        ("com.google.Gmail", ["mail!"], .hop),
        ("com.apple.finder", ["what's in there?", "files…"], .curious),
        ("com.apple.systempreferences", ["careful…", "don't break anything"], .curious),
        ("com.apple.SystemSettings", ["careful…"], .curious),
        ("com.apple.FaceTime", ["hi!!", "who's calling?"], .excited),
        ("com.apple.PhotoBooth", ["cheese!", "take my picture!"], .excited),
        ("com.apple.AppStore", ["ooh shiny", "new apps?"], .excited),
        ("com.apple.Notes", ["taking notes?", "write about me"], .curious),
        ("com.apple.iCal", ["busy day?"], .curious),
        ("com.apple.ActivityMonitor", ["am I using too much?", "*sweats*"], .sweat),
        ("com.canva", ["art!", "make it pretty"], .excited),
        ("com.figma", ["art!", "ooh, design"], .excited),
        ("com.blender", ["3D!", "ooh, shapes"], .excited),
        ("com.apple.Safari", ["browsing?", "find cat videos"], .none),
        ("com.google.Chrome", ["browsing?", "so many tabs"], .none),
        ("org.mozilla.firefox", ["browsing?", "foxes rule"], .none),
    ]

    static func find(_ bundleID: String) -> (lines: [String], action: Action)? {
        table.first { bundleID.hasPrefix($0.prefix) }.map { ($0.lines, $0.action) }
    }
}
