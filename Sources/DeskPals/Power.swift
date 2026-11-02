import AppKit

/// Power moves: an aura charges up, then the pet unleashes its move (time stop, a transformation,
/// an aura-charged kick, or a big version of its usual special).
extension Pet {
    var auraColor: UInt32 { kind.aura ?? kind.palette["a"] ?? 0xFFD54F }
    var isTransformed: Bool { formSheet != nil }

    /// Double-click: pets with a power move use it, everyone else does a flip.
    func doubleClicked() {
        if kind.power != nil, powerMove() { return }
        superJump()
    }

    @discardableResult
    func powerMove() -> Bool {
        let move = kind.power ?? (kind.special != .none ? kind.special : .spinKick)
        if isWatching {   // hop down from the video first
            stopWatching(nil)
            after(1.0) { [weak self] in self?.powerMove() }
            return true
        }
        guard t > powerCooldown, !isDragged, !isHidden, isGrounded else { return false }
        if case .powerUp = state { return false }
        if move == .transform, isTransformed { return false }
        powerCooldown = t + 15
        state = .powerUp(until: t + 1.3, move: move)
        say(kind.auraText != nil ? "…" : "hnnngh…", 1.3)
        Sound.shared.play(.chime, pitch: 0.7)
        return true
    }

    /// Every tick: the aura eases toward how powered-up the pet is, and transformations grow and shrink.
    func powerTick(_ dt: Double) {
        var target: CGFloat = 0
        if case .powerUp(let until, _) = state { target = 0.3 + 0.7 * CGFloat(max(0, min(1, 1 - (until - t) / 1.3))) }
        if case .dash = state { target = 1 }
        if isTransformed { target = max(target, 0.55) }
        if FX.shared.owns(self) { target = max(target, 0.8) }
        if menacingUntil > t { target = max(target, 0.7) }
        if case .pose = state { target = max(target, 0.6) }
        aura += (target - aura) * CGFloat(min(1, dt * 6))

        if aura > 0.25, Int(t * 30) % 2 == 0 {
            emit(.flame, at: CGPoint(x: pos.x + .random(in: -size * 0.45...size * 0.45), y: pos.y + .random(in: 0...size * 0.7)),
                 count: 1, spread: 2, vx: -15...15, vy: 70...150, gravity: -40, life: 0.4...0.8, color: auraColor)
        }
        if aura > 0.5, let glyph = kind.auraText, chance(dt * 2.5) {
            FX.shared.glyph(glyph, at: CGPoint(x: pos.x + .random(in: -size * 1.4...size * 1.2), y: pos.y + .random(in: size * 0.2...size * 1.3)),
                            color: auraColor)
        }

        // transformation
        if transformedUntil > 0, t > transformedUntil {
            transformedUntil = 0
            emit(.dust, at: CGPoint(x: pos.x, y: pos.y + size * 0.4), count: 14, spread: size * 0.4, life: 0.6...1.1)
            say("…", 1.5)
        }
        let goal: CGFloat = transformedUntil > t ? kind.transformScale : 1
        if formScale != goal {
            formScale += (goal - formScale) * CGFloat(min(1, dt * 4))
            if abs(formScale - goal) < 0.01 {
                formScale = goal
                if goal == 1 { formSheet = nil }
            }
        }
        // stomp, stomp
        if isTransformed, case .walk = state, t - lastStomp > 0.45 {
            lastStomp = t
            emit(.dust, at: pos, count: 4, spread: size * 0.3)
            FX.shared.shake(0.3)
        }
    }

    func powerUpTick(_ until: Double, _ move: Special) {
        if Int(t * 20) % 3 == 0 { emit(.dust, at: pos, count: 1, spread: size * 0.4) }
        FX.shared.shake(0.12)
        guard t > until else { return }
        unleash(move)
    }

    func unleash(_ move: Special) {
        let center = CGPoint(x: pos.x, y: pos.y + size / 2)
        let shout = kind.powerShout
        switch move {
        case .timeStop:
            say(shout ?? "Time, stop!", 2.5)
            Sound.shared.play(.chime, pitch: 0.45)
            FX.shared.timeStop(owner: self, center: center, radius: 320, duration: 5)
            hold(5)
            // A flurry of hits on everyone frozen nearby; they feel it all when time moves again.
            after(0.7) { [weak self] in
                guard let self else { return }
                let targets = self.friends().filter { $0 !== self && hypot($0.pos.x - center.x, $0.pos.y - center.y) < 320 }
                for f in targets { FX.shared.hits(at: CGPoint(x: f.pos.x, y: f.pos.y + f.size / 2), color: self.auraColor, duration: 3.5) }
                self.say(self.kind.shout ?? "!!!", 3)
            }
            after(5.05) { [weak self] in
                guard let self else { return }
                for f in self.friends() where f !== self && hypot(f.pos.x - center.x, f.pos.y - center.y) < 320 { f.knockedBack(from: self) }
                Sound.shared.play(.impact)
                FX.shared.shake(0.8)
                self.say("…and time moves again.", 2)
            }
        case .transform:
            guard let art = kind.transformArt else { specialMove(); return }
            say(shout ?? "RAAAAH!", 2.5)
            Sound.shared.play(.roar)
            FX.shared.flash(at: center, color: auraColor, radius: 200)
            FX.shared.ring(at: center, color: auraColor, radius: 300, duration: 0.7)
            FX.shared.shake(1.4)
            emit(.tentacle, at: center, count: 40, spread: 10, vx: -320...320, vy: 80...420, gravity: 300, life: 0.6...1.2)
            var form = kind
            form.art = art
            if let p = kind.transformPalette { form.palette = p }
            formSheet = SpriteSheet(kind: form)
            transformedUntil = t + 20
            hold(1.4)
            for f in friends() where f !== self && hypot(f.pos.x - pos.x, f.pos.y - pos.y) < 500 && f.isCalm {
                f.say(["eek!", "!!", "run!"].randomElement()!, 1.2)
                f.launch(CGVector(dx: f.pos.x > pos.x ? 160 : -160, dy: 420))
            }
        case .auraKick:
            say(shout ?? "HYAH!", 1.6)
            Sound.shared.play(.whoosh)
            state = .dash(until: t + 0.5, dir: facing)
        case .fire, .tentacles, .barrage, .spinKick:
            FX.shared.ring(at: center, color: auraColor, radius: 160, duration: 0.45)
            if let shout { say(shout, 1.6) }
            specialMove()
        case .none:
            hold(0.5)
        }
    }

    func dashTick(_ until: Double, _ dir: CGFloat, _ dt: Double) {
        guard let p = world.platform(standingOn) else {
            standingOn = nil
            state = .air
            return
        }
        pos.y = p.y
        facingRight = dir > 0
        let nx = pos.x + dir * kind.walkSpeed * scale * 9 * CGFloat(dt)
        if p.holds(nx) { pos.x = nx }
        let a = -dir * 120, b = -dir * 40
        emit(.flame, at: CGPoint(x: pos.x - dir * size * 0.4, y: pos.y + size * 0.4), count: 2, spread: size * 0.2,
             vx: min(a, b)...max(a, b), vy: -20...40, gravity: 0, life: 0.2...0.4, color: auraColor)
        FX.shared.speedLines(at: CGPoint(x: pos.x, y: pos.y + size / 2), dir: dir)
        guard t > until else { return }

        // The kick.
        let c = CGPoint(x: pos.x + dir * size * 0.6, y: pos.y + size * 0.6)
        FX.shared.ring(at: c, color: auraColor, radius: 240, duration: 0.5)
        FX.shared.flash(at: c, color: 0xFFFFFF, radius: 90)
        FX.shared.shake(1)
        Sound.shared.play(.impact)
        emit(.sparkle, at: c, count: 10, vx: -260...260, vy: -100...260, gravity: 200)
        for f in friends() where f !== self && hypot(f.pos.x - c.x, f.pos.y - pos.y) < 260 { f.knockedBack(from: self) }
        for prop in props.items where hypot(prop.pos.x - c.x, prop.pos.y - pos.y) < 260 {
            if case .place = prop.kind { continue }
            prop.groundID = nil
            prop.vel = CGVector(dx: (prop.pos.x >= pos.x ? 1 : -1) * 700, dy: 600)
        }
        trick = true
        launch(CGVector(dx: dir * 120, dy: 650))
        spinVel = -dir * .pi * 2 / CGFloat(2 * 650 / (Pet.gravity * World.gravityScale))
    }

    /// Hit by someone's power move.
    func knockedBack(from other: Pet) {
        guard !isDragged, !isHidden else { return }
        let dir: CGFloat = pos.x >= other.pos.x ? 1 : -1
        say(["!!", "ow!", "whoa!", "!?"].randomElement()!, 1)
        launch(CGVector(dx: dir * 700, dy: 600), thrown: true)
        spinVel = -dir * 10
    }
}
