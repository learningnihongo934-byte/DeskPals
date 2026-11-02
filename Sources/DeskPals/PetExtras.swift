import AppKit

/// Places around the Mac (menu bar, notch, screen corners, other screens), places on the desktop,
/// mischief, weather and mini-game control.
extension Pet {
    /// Runs the states that move the pet by script instead of physics. Returns true if it handled one.
    func scriptedTick(_ dt: Double) -> Bool {
        switch state {
        case .ceiling(let dir, let until): ceilingTick(dir, until, dt)
        case .peek(let side, let start): peekTick(side, start)
        case .hidden(let until): if t > until { reappear() }
        case .swinging(let id, let until): swingTick(id, until)
        case .sliding(let id, let progress): slideTick(id, progress, dt)
        case .fishing(let id, let until): fishTick(id, until)
        case .inside(let id, let until): insideTick(id, until, dt)
        case .game: gameTick(dt)
        case .hiding(let id, let until): hidingTick(id, until)
        case .powerUp(let until, let move): powerUpTick(until, move)
        case .dash(let until, let dir): dashTick(until, dir, dt)
        default: return false
        }
        return true
    }

    func decideExtras() -> Bool {
        let c = Pet.chaos
        if kind.power != nil, needs.happiness > 0.8, chance(0.004 + c * 0.012), powerMove() { return true }
        if chance(0.12 + c * 0.08), visitPlace() { return true }
        if chance(0.02), peekFromCorner() { return true }
        if chance(0.015), travelToOtherScreen() { return true }
        if c > 0.6, chance((c - 0.6) * 0.6), mischief() { return true }
        if c < 0.25, chance(0.4) {   // calm pets mostly rest
            sitDown(.random(in: 4...9))
            return true
        }
        return false
    }

    // MARK: - Menu bar and notch

    /// Called at the top of a wall climb: sometimes swing along under the menu bar like monkey bars.
    func reachedTopOfWall(_ side: CGFloat) -> Bool {
        let top = world.screenTop(at: pos.x)
        guard pos.y > top - size * 1.7, chance(0.65) else { return false }
        pos = CGPoint(x: pos.x - side * size * 0.6, y: top - size * 0.92)
        notchVisited = false
        state = .ceiling(dir: -side, until: t + .random(in: 6...14))
        say(["monkey bars!", "look, no feet!", "wheee"].randomElement()!, 1.5)
        return true
    }

    func ceilingTick(_ dir: CGFloat, _ until: Double, _ dt: Double) {
        facingRight = dir > 0
        pos.x += dir * kind.walkSpeed * scale * 0.7 * CGFloat(dt)
        pos.y = world.screenTop(at: pos.x) - size * 0.92
        if !notchVisited, let notch = world.notch(at: pos.x), notch.minX < pos.x, pos.x < notch.maxX {
            notchVisited = true
            if chance(0.7) {
                state = .hidden(until: t + .random(in: 3...7))   // in the notch
                return
            }
        }
        let b = world.screenFrame(at: pos.x)
        if t > until || pos.x < b.minX + size / 2 || pos.x > b.maxX - size / 2 {
            vel = CGVector(dx: dir * 60, dy: 0)
            jumping = false
            airTime = 0
            standingOn = nil
            state = .air
            say("wheee", 1)
        }
    }

    func reappear() {
        standingOn = nil
        jumping = false
        airTime = 0
        if let v = vanishTarget, !v.isHidden {
            // turn up right behind them
            vanishTarget = nil
            pos = CGPoint(x: v.pos.x - v.facing * v.size * 1.1, y: v.pos.y + 2)
            facingRight = v.pos.x > pos.x
            vel = .zero
            state = .air
            say(kind.rivalLines.randomElement() ?? kind.powerShout ?? "…", 2.2)
            menacingUntil = t + 2.5
            v.after(0.5) { [weak v] in
                guard let v, v.isCalm else { return }
                v.say("!?", 1.2)
                v.facingRight.toggle()
                v.launch(CGVector(dx: 0, dy: 420))
            }
            return
        }
        vel = CGVector(dx: facing * 80, dy: -50)
        state = .air
        say("boo!", 1.5)
    }

    // MARK: - Screen corners and other screens

    func peekFromCorner() -> Bool {
        guard let seg = currentSegment() else { return false }
        let b = world.screenFrame(at: pos.x)
        let left = seg.lowerBound <= b.minX + 2, right = seg.upperBound >= b.maxX - 2
        guard left || right else { return false }
        let side: CGFloat = left && right ? (pos.x < b.midX ? -1 : 1) : (left ? -1 : 1)
        walk(to: side < 0 ? b.minX + size / 2 : b.maxX - size / 2, run: false) { [weak self] in
            guard let self else { return }
            self.state = .peek(side: side, start: self.t)
        }
        return true
    }

    /// Walk off the side of the screen, wait, peek back in, then come back.
    func peekTick(_ side: CGFloat, _ start: Double) {
        let p = t - start
        let b = world.screenFrame(at: pos.x - side * size)
        let inside = side < 0 ? b.minX + size / 2 : b.maxX - size / 2
        let out: CGFloat
        switch p {
        case ..<1.2: out = CGFloat(p / 1.2) * 1.3; facingRight = side > 0
        case ..<4: out = 1.3
        case ..<6.5:
            out = 0.55
            facingRight = side < 0
            if bubbleText == nil { say("peekaboo!", 1.5) }
        case ..<7.5: out = 0.55 - CGFloat(p - 6.5) * 0.55
        default:
            pos.x = inside
            hold(1)
            return
        }
        pos.x = inside + side * out * size
    }

    func travelToOtherScreen() -> Bool {
        guard NSScreen.screens.count > 1, isGrounded else { return false }
        let mine = world.screenFrame(at: pos.x)
        let floors = world.platforms.filter { $0.id < 0 && !mine.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        guard let f = floors.randomElement(), let seg = f.segments.first else { return false }
        let x = f.frame.midX < pos.x ? seg.upperBound - size : seg.lowerBound + size
        say("road trip!", 1.5)
        jump(to: CGPoint(x: x, y: f.y))
        return true
    }

    // MARK: - Places on the desktop

    func visitPlace() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let evening = hour >= 18 || hour < 6
        let options = props.places.filter { p in
            guard p.grounded, !p.dragged, abs(p.pos.x - pos.x) < 1600, case .place(let pl) = p.kind else { return false }
            switch pl {
            case .campfire: return evening || chance(0.25)
            case .swing, .house: return !p.occupied
            default: return true
            }
        }
        guard let p = options.randomElement(), case .place(let place) = p.kind else { return false }
        Economy.shared.record(.placeVisit)
        let ppx = p.scale, r = p.rect
        switch place {
        case .house:
            goTo(x: p.pos.x, on: p) { [weak self] in self?.enterHouse(p) }
        case .pond:
            let x = kind.hops ? p.pos.x : (pos.x < p.pos.x ? r.minX - size * 0.1 : r.maxX + size * 0.1)
            goTo(x: x, on: p) { [weak self] in
                guard let self, !p.dead else { return }
                self.facingRight = p.pos.x > self.pos.x
                self.say(self.kind.hops ? "splish splash" : "fishing…", 1.5)
                self.state = .fishing(prop: p.id, until: self.t + .random(in: 8...14))
            }
        case .garden:
            goTo(x: r.minX + size * 0.4, on: p) { [weak self] in
                self?.walk(to: r.maxX - (self?.size ?? 0) * 0.4, run: false) { [weak self] in self?.tend(p) }
            }
        case .swing:
            goTo(x: p.pos.x, on: p) { [weak self] in
                guard let self, !p.dead, !p.occupied else { return }
                p.occupied = true
                self.standingOn = nil
                self.say("wheee", 1.2)
                self.state = .swinging(prop: p.id, until: self.t + .random(in: 6...12))
            }
        case .slide:
            jump(to: CGPoint(x: r.minX + 3 * ppx, y: r.minY + 18 * ppx)) { [weak self] in
                guard let self, !p.dead else { return }
                self.after(0.6) { [weak self] in
                    guard let self, self.isCalm else { return }
                    self.standingOn = nil
                    self.facingRight = true
                    self.say("wheee!", 1.2)
                    self.state = .sliding(prop: p.id, progress: 0)
                }
            }
        case .campfire:
            let side: CGFloat = Bool.random() ? -1 : 1
            goTo(x: p.pos.x + side * size * 1.3, on: p) { [weak self] in
                guard let self else { return }
                self.facingRight = side < 0
                self.say(["cozy…", "warm", "s'mores?"].randomElement()!, 1.6)
                self.needs.happiness = min(1, self.needs.happiness + 0.05)
                self.sitDown(.random(in: 10...20))
            }
        }
        return true
    }

    /// Walk there if it's on the same ledge, otherwise jump.
    func goTo(x: CGFloat, on p: Prop, then: @escaping () -> Void) {
        if let g = p.groundID, g == standingOn {
            walk(to: x, run: false, then: then)
        } else {
            jump(to: CGPoint(x: x, y: p.pos.y), then: then)
        }
    }

    func enterHouse(_ p: Prop) {
        guard !p.dead, !p.occupied, abs(p.pos.x - pos.x) < size else { return }
        p.occupied = true
        say("home!", 1)
        state = .inside(prop: p.id, until: t + .random(in: 8...20))
    }

    func insideTick(_ id: Int, _ until: Double, _ dt: Double) {
        needs.energy = min(1, needs.energy + dt / 600)
        guard let p = props.items.first(where: { $0.id == id }) else { reappear(); return }
        pos = CGPoint(x: p.pos.x, y: p.pos.y)
        guard t > until else { return }
        p.occupied = false
        standingOn = p.groundID
        groundFrame = world.platform(p.groundID)?.frame
        say(["*stretch*", "good nap", "hi!"].randomElement()!, 1.4)
        hold(1)
    }

    func fishTick(_ id: Int, _ until: Double) {
        guard let p = props.items.first(where: { $0.id == id }) else { hold(0.5); return }
        if Int(t * 10) % 25 == 0 {
            emit(.sweat, at: CGPoint(x: kind.hops ? pos.x : p.rect.midX, y: p.rect.minY + p.size.height * 0.6), count: 3,
                 vx: -60...60, vy: 80...160, gravity: 500, life: 0.4...0.7)
        }
        guard t > until else { return }
        if chance(0.5) {
            say("caught one!", 1.8)
            Sound.shared.play(.splash)
            needs.fullness = min(1, needs.fullness + 0.1)
            Economy.shared.earn(3)
            emit(.sparkle, at: head, count: 4, vy: 60...120, gravity: 0)
            happyUntil = t + 1.5
        } else {
            say("nothing…", 1.2)
        }
        hold(1.2)
    }

    func tend(_ p: Prop) {
        guard !p.dead else { return }
        say("*sniff sniff*", 1.4)
        emit(.heart, at: head, count: 1, vy: 50...90, gravity: 0, life: 0.9...1.2)
        let key = "garden.tended", today = Economy.today()
        if UserDefaults.standard.string(forKey: key) != today, p.stage < 2 {
            UserDefaults.standard.set(today, forKey: key)
            p.stage += 1
            props.savePlaces()
            after(1.5) { [weak self] in self?.say(p.stage == 2 ? "they bloomed!" : "growing!", 1.6) }
        }
        sitDown(2.5)
    }

    func seatPoint(_ p: Prop) -> CGPoint {
        let r = p.rect, ppx = p.scale
        let pivot = CGPoint(x: r.midX, y: r.maxY - ppx * 1.5)
        let length = ppx * 17
        return CGPoint(x: pivot.x + sin(p.swingAngle) * length, y: pivot.y - cos(p.swingAngle) * length + ppx)
    }

    func swingTick(_ id: Int, _ until: Double) {
        guard let p = props.items.first(where: { $0.id == id }), !p.dragged else { reappear(); return }
        pos = seatPoint(p)
        guard t > until else { return }
        p.occupied = false
        launch(CGVector(dx: sin(p.swingAngle) * 600 + facing * 80, dy: 420))
        say("wheee!", 1)
    }

    func slideTick(_ id: Int, _ progress: Double, _ dt: Double) {
        guard let p = props.items.first(where: { $0.id == id }) else { reappear(); return }
        let r = p.rect, ppx = p.scale
        let a = CGPoint(x: r.minX + 7 * ppx, y: r.minY + 17 * ppx)
        let b = CGPoint(x: r.minX + 25 * ppx, y: r.minY + 1 * ppx)
        let k = CGFloat(min(1, progress * progress))   // speeds up as it goes
        pos = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        if progress >= 1 {
            launch(CGVector(dx: 460, dy: 90), thrown: true)
            return
        }
        state = .sliding(prop: id, progress: progress + dt / 0.9)
    }

    // MARK: - Mischief (chaos above 60%)

    func mischief() -> Bool {
        switch Int.random(in: 0..<3) {
        case 0:
            guard let f = friends().filter({ $0 !== self && $0.isCalm && $0.standingOn == standingOn && abs($0.pos.x - pos.x) < 400 }).randomElement()
            else { return false }
            say("hehe", 1)
            walk(to: f.pos.x - (f.pos.x > pos.x ? 1 : -1) * size * 0.6, run: true) { [weak self, weak f] in
                guard let self, let f, f.isCalm else { return }
                f.say("hey!", 1.2)
                f.launch(CGVector(dx: self.facing * 380, dy: 420), thrown: true)
            }
            return true
        case 1:
            guard let thing = (props.foods + [props.ball].compactMap { $0 }).filter({ $0.groundID == standingOn }).randomElement()
            else { return false }
            walk(to: thing.pos.x - (thing.pos.x > pos.x ? 1 : -1) * size * 0.4, run: true) { [weak self] in
                guard let self, !thing.dead else { return }
                thing.groundID = nil
                thing.vel = CGVector(dx: self.facing * 520, dy: 320)
                self.say("oops", 1)
            }
            return true
        default:
            // At full chaos they tug your cursor a little.
            guard Pet.chaos > 0.85, let c = cursorPos, hypot(c.x - pos.x, c.y - pos.y) < 260,
                  let flipH = NSScreen.screens.first?.frame.height else { return false }
            say("mine!", 1)
            let target = CGPoint(x: c.x + (pos.x - c.x) * 0.25, y: c.y + (pos.y + size / 2 - c.y) * 0.25)
            CGWarpMouseCursorPosition(CGPoint(x: target.x, y: flipH - target.y))
            CGAssociateMouseAndMouseCursorPosition(1)
            return true
        }
    }

    // MARK: - Weather

    func weatherChanged(_ w: WeatherKind, temperature: Double?) {
        umbrella = w == .rain || w == .storm
        shivering = (temperature ?? 20) < 4
        guard isCalm else { return }
        switch w {
        case .rain: say(["rain…", "pitter patter", "*opens umbrella*"].randomElement()!, 1.8)
        case .snow:
            say("snow!!", 1.8)
            launch(CGVector(dx: 0, dy: 450))
            Economy.shared.record(.sawSnow)
        case .storm:
            say("eek!", 1.4)
            if let h = props.place(.house), !h.occupied { goTo(x: h.pos.x, on: h) { [weak self] in self?.enterHouse(h) } }
        case .clear: say(["nice day!", "sunny ☀", "what a day"].randomElement()!, 1.8)
        case .leaves, .petals: say(["ooh, leaves", "so pretty"].randomElement()!, 1.6)
        default: break
        }
        if (temperature ?? 20) > 30 { emit(.sweat, at: head, count: 2, vy: 30...70, gravity: 400) }
    }

    func thunder() {
        guard isCalm else { return }
        say("!!", 1)
        emit(.sweat, at: head, count: 3, vy: 40...90, gravity: 400)
        launch(CGVector(dx: 0, dy: 520))
    }

    // MARK: - Growing up

    func grewUp(to stage: Int) {
        growth = [0.6, 0.8, 1][min(stage, 2)]
        say(stage >= 2 ? "all grown up!" : "I'm getting bigger!", 2)
        emit(.sparkle, at: head, count: 8, vx: -90...90, vy: 40...140, gravity: 0, life: 0.8...1.3)
        happyUntil = t + 2
        Economy.shared.record(.grewUp)
    }

    // MARK: - Mini-games

    /// Put the pet on the ground at x, under the game's control.
    func enterGame(at x: CGFloat) {
        guard let f = world.platforms.filter({ $0.id < 0 && $0.holds(x) }).max(by: { $0.y < $1.y }) else { return }
        pos = CGPoint(x: x, y: f.y)
        standingOn = f.id
        groundFrame = f.frame
        vel = .zero
        gameTarget = x
        state = .game
    }

    func leaveGame() {
        gameTarget = nil
        if case .game = state { hold(1) }
    }

    func gameTick(_ dt: Double) {
        guard let p = world.platform(standingOn), let target = gameTarget else { return }
        pos.y = p.y
        let step = kind.walkSpeed * scale * 4 * CGFloat(dt)
        let seg = p.segments.first { $0.contains(pos.x) } ?? (pos.x...pos.x)
        let goal = clamp(target, seg.lowerBound + size / 2, seg.upperBound - size / 2)
        if abs(goal - pos.x) <= step { pos.x = goal } else {
            facingRight = goal > pos.x
            pos.x += facing * step
        }
    }

    /// Hide & seek: duck behind a window and peek over its top now and then.
    func startHiding(behind w: WindowInfo, seconds: Double) {
        standingOn = nil
        hideOffset = .random(in: size...(max(size, w.frame.width - size)))
        hidingWindowID = w.id
        state = .hiding(window: w.id, until: t + seconds)
    }

    func hidingTick(_ id: Int, _ until: Double) {
        guard let w = world.windowInfo(id), t < until else {
            hidingWindowID = nil
            onClicked = nil
            reappear()
            say(t >= until ? "you didn't find me!" : "boo!", 2)
            return
        }
        let peeking = t.truncatingRemainder(dividingBy: 7) > 5.6
        pos = CGPoint(x: w.frame.minX + hideOffset, y: w.frame.maxY - size * (peeking ? 0.45 : 1.1))
    }

    func found() {
        hidingWindowID = nil
        say("you found me!", 2)
        happyUntil = t + 2
        emit(.heart, at: head, count: 3, vy: 60...120, gravity: 0, life: 1...1.4)
        launch(CGVector(dx: 0, dy: 500))
    }
}
