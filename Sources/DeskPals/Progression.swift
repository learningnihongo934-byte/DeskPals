import AppKit

/// Pets with a `progression` make a new discovery every `progressInterval` seconds (saved across launches).
/// After the last one they build a rocket, fly to the moon, and come back petrified to start over.
extension Pet {
    private var progressKey: String { "progress.\(needs.petID)" }

    var progressStep: Int {
        get { UserDefaults.standard.integer(forKey: progressKey) }
        set { UserDefaults.standard.set(newValue, forKey: progressKey) }
    }

    func progressTick(_ dt: Double) {
        guard let list = kind.progression, !list.isEmpty else { return }
        switch state {
        case .rocketRide, .onMoon, .statue: return
        default: break
        }
        progressClock += dt
        guard progressClock >= kind.progressInterval else { return }
        progressClock = 0
        let step = progressStep
        guard step < list.count else {
            startFinale()
            return
        }
        progressStep = step + 1
        discover(list[step], number: step + 1, of: list.count)
    }

    func discover(_ item: String, number: Int, of total: Int) {
        guard !isHidden else { return }
        say("💡 \(item)! (\(number)/\(total))", 3.5)
        Sound.shared.play(.ding, pitch: 1 + Double(number % 5) * 0.08)
        emit(.sparkle, at: head, count: 6, vx: -90...90, vy: 60...150, gravity: 120)
        FX.shared.ring(at: CGPoint(x: pos.x, y: pos.y + size / 2), color: auraColor, radius: 120, duration: 0.5)
        if isCalm { launch(CGVector(dx: 0, dy: 380)) }
        if number % 10 == 0 {
            after(3.6) { [weak self] in
                guard let self else { return }
                self.say(self.kind.progressShout ?? "!!!", 2.5)
                FX.shared.flash(at: CGPoint(x: self.pos.x, y: self.pos.y + self.size / 2), color: self.auraColor, radius: 160)
                self.menacingUntil = self.t + 2.5
            }
        }
        if number == total {
            after(7) { [weak self] in self?.say("next stop: the moon.", 3) }
        }
    }

    // MARK: - Rocket, moon, and back to stone

    func startFinale() {
        guard isGrounded, !isDragged else {
            progressClock = kind.progressInterval - 5   // try again in a few seconds
            return
        }
        if isWatching { stopWatching(nil) }
        rocketBase = CGPoint(x: pos.x + facing * size * 1.5, y: pos.y)
        say(kind.finaleShout ?? "to the moon!", 2.5)
        FX.shared.rocket(at: rocketBase, scale: px)
        state = .rocketRide(start: t)
        standingOn = nil
    }

    func rocketTick(_ start: Double) {
        let age = t - start
        facingRight = rocketBase.x > pos.x
        if age < 2 {
            if Int(t * 12) % 3 == 0 { emit(.sparkle, at: CGPoint(x: rocketBase.x, y: rocketBase.y + size), count: 1, vx: -80...80, vy: 40...120) }
        } else if age < 2.6 {
            let k = CGFloat((age - 2) / 0.6)   // hop in
            pos = CGPoint(x: pos.x + (rocketBase.x - pos.x) * k * 0.3, y: rocketBase.y + size * 1.2 * sin(k * .pi))
        } else if age > 4.5, age < 4.55 {
            Sound.shared.play(.thunder)
            FX.shared.shake(1.2)
        } else if age > 8.4 {
            pos = CGPoint(x: rocketBase.x, y: world.screenTop(at: rocketBase.x) + 200)
            state = .onMoon(until: t + 25)
            FX.shared.moon(with: sheet.image(.stand, .happy), scale: 4, duration: 25)
        }
    }

    func moonTick(_ until: Double) {
        guard t > until else { return }
        // Back down to earth... as a stone statue.
        progressStep = 0
        progressClock = 0
        var stone = kind
        stone.palette = kind.palette.mapValues { rgb in
            let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
            let l = UInt32(min(255, 40 + (0.3 * r + 0.59 * g + 0.11 * b) * 0.7))
            return (l << 16) | (l << 8) | l
        }
        formSheet = SpriteSheet(kind: stone)
        pos = CGPoint(x: clamp(rocketBase.x, world.bounds.minX + size, world.bounds.maxX - size), y: world.screenTop(at: rocketBase.x) - size)
        vel = .zero
        standingOn = nil
        state = .statue(until: .infinity)
    }

    func statueTick(_ until: Double, _ dt: Double) {
        if standingOn == nil {
            let prev = pos.y
            vel.dy -= Pet.gravity * dt
            pos.y += vel.dy * dt
            if let g = world.landing(x: pos.x, from: prev, to: pos.y, ignoring: headID) {
                pos.y = g.y
                standingOn = g.id
                groundFrame = g.frame
                vel = .zero
                FX.shared.shake(1)
                Sound.shared.play(.impact, pitch: 0.7)
                emit(.dust, at: pos, count: 14, spread: size * 0.5)
                state = .statue(until: t + 4)
            }
            return
        }
        guard t > until else { return }
        // crack!
        formSheet = nil
        FX.shared.flash(at: CGPoint(x: pos.x, y: pos.y + size / 2), color: 0xFFFFFF, radius: 110)
        Sound.shared.play(.pop, pitch: 0.6)
        emit(.dust, at: CGPoint(x: pos.x, y: pos.y + size / 2), count: 16, spread: size * 0.4, vx: -160...160, vy: 40...220, gravity: 500)
        say(kind.resetShout ?? "back to square one!", 3)
        launch(CGVector(dx: 0, dy: 420))
    }

    // MARK: - Experiments

    func experiment() {
        let center = CGPoint(x: pos.x + facing * size * 0.6, y: pos.y + size * 0.6)
        say(kind.powerShout ?? "let's experiment!", 1.6)
        after(1.2) { [weak self] in
            guard let self else { return }
            let works = Bool.random()
            for c: UInt32 in [0xFF5C8A, 0x5BD68A, 0x4FC3F7, 0xFFD54F] {
                self.emit(.flame, at: center, count: 6, spread: 6, vx: -200...200, vy: 40...260, gravity: 300, life: 0.5...1.0, color: c)
            }
            if works {
                FX.shared.ring(at: center, color: 0x5BD68A, radius: 140, duration: 0.5)
                Sound.shared.play(.chime, pitch: 1.4)
                self.say("it worked!", 2)
                self.happyUntil = self.t + 2
            } else {
                FX.shared.flash(at: center, color: 0xFFD54F, radius: 120)
                FX.shared.shake(0.6)
                Sound.shared.play(.impact)
                self.squash = 0.8
                self.state = .dizzy(until: self.t + 2)
                self.say("…ten billion percent failure.", 2.2)
            }
        }
        hold(1.6)
    }
}
