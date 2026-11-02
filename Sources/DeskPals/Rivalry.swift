import AppKit

/// Rivals: when a pet and its rival (`PetKind.rival`) are both on screen, they keep getting into it:
/// face-offs, barrage clashes, time-stop duels, dropping something enormous on each other,
/// bickering while watching videos, and the occasional dramatic pose or sulky truce.
enum Rivalry {
    private static var next: [String: Double] = [:]

    static let knife = Pixels.image(["hh.......", "hhbbbbbbW", "hh......."], ["h": 0x6B4423, "b": 0xC9CDD6])

    /// Called a couple of times a second with every pet on screen.
    static func tick(_ pets: [Pet], clock: Double) {
        bestieTick(pets, clock: clock)
        for a in pets {
            guard let rid = a.kind.rival, let b = pets.first(where: { $0 !== a && $0.kind.id == rid }) else { continue }
            if a.kind.rivalStyle == "chase" || b.kind.rivalStyle == "chase" {
                chaseTick(a, b, clock: clock)
                continue
            }
            let key = "\(a.headID)-\(b.headID)"
            if next[key] == nil { next[key] = clock + .random(in: 8...20) }
            guard clock > next[key]! else { continue }

            if a.isWatching, b.isWatching {
                next[key] = clock + .random(in: 20...40)
                bicker(a, b)
            } else if a.isCalm, b.isCalm {
                next[key] = clock + .random(in: 35...80) * (1.4 - Pet.chaos)
                let roll = Double.random(in: 0..<1)
                if roll < 0.35 {
                    faceOff(a, b) { clash(a, b) }
                } else if roll < 0.55, a.kind.power == .timeStop {
                    faceOff(a, b) { timeStopDuel(a, b) }
                } else if roll < 0.72, a.kind.dropArt != nil, a.kind.power == .timeStop {
                    faceOff(a, b) { dropOn(a, b) }
                } else if roll < 0.86 {
                    faceOff(a, b) { strikePoses(a, b) }
                } else {
                    truce(a, b)
                }
            }
        }
    }

    // MARK: - Besties

    private static func bestieTick(_ pets: [Pet], clock: Double) {
        for a in pets {
            guard let bid = a.kind.bestie, let b = pets.first(where: { $0 !== a && $0.kind.id == bid }), a.headID < b.headID || b.kind.bestie != a.kind.id
            else { continue }
            let key = "bestie-\(min(a.headID, b.headID))-\(max(a.headID, b.headID))"
            if next[key] == nil { next[key] = clock + .random(in: 6...15) }
            guard clock > next[key]! else { continue }
            if a.isWatching, b.isWatching {
                next[key] = clock + .random(in: 25...50)
                cuddleWatching(a, b)
                continue
            }
            guard a.isCalm, b.isCalm else { continue }
            next[key] = clock + .random(in: 30...70)
            switch Int.random(in: 0..<5) {
            case 0: hangOut(a, b, hug: false)
            case 1: hangOut(a, b, hug: true)
            case 2: danceTogether(a, b)
            case 3: shareFood(a, b)
            default: piggyback(a, b)
            }
        }
    }

    /// Walk over and sit together (or hug).
    static func hangOut(_ a: Pet, _ b: Pet, hug: Bool) {
        a.say(a.kind.bestieLines.randomElement() ?? "hi!", 1.8)
        let side: CGFloat = a.pos.x < b.pos.x ? -1 : 1
        let arrive = { [weak a, weak b] in
            guard let a, let b else { return }
            a.facingRight = b.pos.x > a.pos.x
            b.facingRight = a.pos.x > b.pos.x
            if hug {
                for p in [a, b] {
                    p.loveUntil = p.t + 2.5
                    p.blushUntil = p.t + 3
                    p.emit(.heart, at: p.head, count: 3, vx: -40...40, vy: 60...110, gravity: 0, life: 1...1.4)
                }
                a.squash = 0.5
                b.squash = 0.5
                b.say(b.kind.bestieLines.randomElement() ?? "♥", 1.8)
                a.sitDown(4)
                b.sitDown(4)
            } else {
                a.sitDown(10)
                b.sitDown(10)
                b.after(1.2) { b.say(b.kind.bestieLines.randomElement() ?? "♪", 1.8) }
            }
        }
        let x = b.pos.x + side * b.size * (hug ? 0.55 : 0.68)   // right next to each other
        if a.standingOn == b.standingOn, let seg = a.currentSegment() {
            a.walk(to: clamp(x, seg.lowerBound + a.size / 2, seg.upperBound - a.size / 2), run: false, then: arrive)
        } else {
            a.jump(to: CGPoint(x: x, y: b.pos.y), then: arrive)
        }
        b.hold(5)
    }

    static func danceTogether(_ a: Pet, _ b: Pet) {
        a.say("♪", 1.5)
        b.say("♪♪", 1.5)
        a.state = .dance(until: a.t + 5)
        b.state = .dance(until: b.t + 5)
        a.emit(.note, at: a.head, count: 3, vx: -50...50, vy: 50...100, gravity: 0, life: 1.2...1.6)
    }

    /// One drops some food for the other: their favorite.
    static func shareFood(_ a: Pet, _ b: Pet) {
        a.say(["here, for you!", "let's eat!", "I saved you some"].randomElement()!, 2)
        let x = b.pos.x + (a.pos.x < b.pos.x ? -1 : 1) * b.size * 0.8
        a.props.add(.food(b.kind.favorite), at: CGPoint(x: x, y: b.pos.y + b.size * 2.5), vel: CGVector(dx: 0, dy: 100))
        b.after(1.5) { [weak b] in b?.say("thank you!", 1.5) }
    }

    static func piggyback(_ a: Pet, _ b: Pet) {
        guard let head = b.headPlatform else { return }
        a.say(["piggyback!", "carry me!"].randomElement()!, 1.6)
        b.hold(6)
        a.jump(to: CGPoint(x: b.pos.x, y: head.y)) { [weak a, weak b] in
            guard let a, let b else { return }
            a.happyUntil = a.t + 3
            a.sitDown(6)
            b.say("hup!", 1.2)
            b.after(0.8) { [weak b] in
                guard let b, let seg = b.currentSegment() else { return }
                b.walk(to: clamp(b.pos.x + .random(in: -300...300), seg.lowerBound + b.size / 2, seg.upperBound - b.size / 2), run: false)
            }
        }
    }

    /// In the cinema seats: leaning on each other and sharing popcorn.
    static func cuddleWatching(_ a: Pet, _ b: Pet) {
        for p in [a, b] {
            p.loveUntil = p.t + 2
            p.emit(.heart, at: p.head, count: 1, vy: 40...80, gravity: 0, life: 1...1.3)
        }
        a.say(a.kind.bestieLines.randomElement() ?? "♥", 2)
        a.emit(.popcorn, at: CGPoint(x: a.pos.x, y: a.pos.y + a.size * 0.4), count: 3, vx: (a.pos.x < b.pos.x ? 40 : -140)...(a.pos.x < b.pos.x ? 140 : -40),
               vy: 100...200, gravity: 500, life: 0.5...0.8)
    }

    // MARK: - Chase rivals

    /// One hunts the other; the other is always one step ahead, and turns up right behind them.
    private static func chaseTick(_ a: Pet, _ b: Pet, clock: Double) {
        let (hunter, prey) = a.kind.power == .vanish ? (b, a) : (a, b)
        let key = "chase-\(min(a.headID, b.headID))-\(max(a.headID, b.headID))"
        if next[key] == nil { next[key] = clock + .random(in: 8...20) }
        guard clock > next[key]! else { return }
        if hunter.isWatching, prey.isWatching {
            next[key] = clock + .random(in: 20...40)
            bicker(prey, hunter)
            return
        }
        guard hunter.isCalm, prey.isCalm else { return }
        next[key] = clock + .random(in: 30...70) * (1.4 - Pet.chaos)
        let roll = Double.random(in: 0..<1)
        if roll < 0.5 {
            chase(hunter, prey)
        } else if roll < 0.75 {
            faceOff(hunter, prey) { prey.say(prey.kind.winLines.randomElement() ?? "…", 2) }
        } else {
            prey.vanishTarget = hunter
            prey.powerCooldown = 0
            prey.powerMove()
        }
    }

    static func chase(_ hunter: Pet, _ prey: Pet) {
        hunter.say(hunter.kind.rivalLines.randomElement() ?? "!", 1.8)
        let arrive = { [weak hunter, weak prey] in
            guard let hunter, let prey, prey.isCalm else { return }
            prey.vanishTarget = hunter
            prey.powerCooldown = 0
            prey.powerMove()
            hunter.after(1.6) { [weak hunter] in hunter?.say(hunter?.kind.loseLines.randomElement() ?? "gone…", 1.8) }
        }
        let x = prey.pos.x + (hunter.pos.x < prey.pos.x ? -1 : 1) * prey.size * 1.3
        if hunter.standingOn == prey.standingOn, let seg = hunter.currentSegment() {
            hunter.walk(to: clamp(x, seg.lowerBound + hunter.size / 2, seg.upperBound - hunter.size / 2), run: true, then: arrive)
        } else {
            hunter.jump(to: CGPoint(x: x, y: prey.pos.y), then: arrive)
        }
    }

    // MARK: - Moves

    /// Walk up to each other, menacingly.
    static func faceOff(_ a: Pet, _ b: Pet, then: @escaping () -> Void) {
        let side: CGFloat = a.pos.x < b.pos.x ? -1 : 1
        let spot = CGPoint(x: b.pos.x + side * b.size * 2.2, y: b.pos.y)
        a.say(a.kind.rivalLines.randomElement() ?? "…", 2.2)
        let arrive = { [weak a, weak b] in
            guard let a, let b else { return }
            a.facingRight = b.pos.x > a.pos.x
            b.facingRight = a.pos.x > b.pos.x
            a.menacingUntil = a.t + 2.8
            b.menacingUntil = b.t + 2.8
            b.say(b.kind.rivalLines.randomElement() ?? "…", 2.2)
            a.hold(2.6)
            b.hold(2.6)
            FX.shared.shake(0.15)
            a.after(2.4) { then() }
        }
        if a.standingOn == b.standingOn, let seg = a.currentSegment() {
            a.walk(to: clamp(spot.x, seg.lowerBound + a.size / 2, seg.upperBound - a.size / 2), run: false, then: arrive)
        } else {
            a.jump(to: spot, then: arrive)
        }
        b.facingRight = a.pos.x > b.pos.x
        b.hold(4)
    }

    /// Barrage vs barrage, fists meeting in the middle.
    static func clash(_ a: Pet, _ b: Pet) {
        guard !a.isHidden, !b.isHidden else { return }
        let mid = CGPoint(x: (a.pos.x + b.pos.x) / 2, y: (a.pos.y + b.pos.y) / 2 + a.size * 0.5)
        a.say(a.kind.shout ?? "!!!", 2.6)
        b.say(b.kind.shout ?? "!!!", 2.6)
        a.menacingUntil = a.t + 2.8
        b.menacingUntil = b.t + 2.8
        a.state = .pose(until: a.t + 2.7)
        b.state = .pose(until: b.t + 2.7)
        FX.shared.hits(at: mid, color: a.auraColor, duration: 2.5)
        FX.shared.ring(at: mid, color: b.auraColor, radius: 120, duration: 2.5)
        for i in 0..<8 {
            a.after(Double(i) * 0.3) { [weak a, weak b] in
                guard let a, let b else { return }
                for (p, q) in [(a, b), (b, a)] {
                    let dir: CGFloat = q.pos.x > p.pos.x ? 1 : -1
                    let lo = dir * 250, hi = dir * 520
                    p.emit(.fist, at: CGPoint(x: p.pos.x + dir * p.size * 0.5, y: p.pos.y + p.size * 0.5), count: 4, spread: 10,
                           vx: min(lo, hi)...max(lo, hi), vy: -60...60, gravity: 0, life: 0.15...0.3)
                }
                FX.shared.shake(0.25)
                Sound.shared.play(.pop, pitch: 0.8 + Double(i) * 0.05)
            }
        }
        a.after(2.6) { [weak a, weak b] in
            guard let a, let b else { return }
            let (win, lose) = Bool.random() ? (a, b) : (b, a)
            Sound.shared.play(.impact)
            FX.shared.flash(at: mid, color: 0xFFFFFF, radius: 100)
            lose.knockedBack(from: win)
            win.say(win.kind.winLines.randomElement() ?? "hmph.", 2.2)
            win.state = .pose(until: win.t + 2)
            lose.after(1.6) { [weak lose] in lose?.say(lose?.kind.loseLines.randomElement() ?? "ugh…", 2) }
        }
    }

    /// One stops time, but the other can move in it too. Knives fly, fists block them.
    static func timeStopDuel(_ a: Pet, _ b: Pet) {
        a.powerCooldown = 0
        guard a.powerMove() else { return }
        b.after(2.2) { [weak a, weak b] in
            guard let a, let b else { return }
            b.say("…I can move in it too.", 2)
            b.menacingUntil = b.t + 4
            a.after(0.8) { a.say("!?", 1.2) }
        }
        for i in 0..<3 {
            a.after(2.6 + Double(i) * 0.9) { [weak a, weak b] in
                guard let a, let b else { return }
                let from = CGPoint(x: a.pos.x, y: a.pos.y + a.size * 0.6), to = CGPoint(x: b.pos.x, y: b.pos.y + b.size * 0.5)
                if a.kind.projectile == "knife" { FX.shared.projectiles(knife, from: from, to: to, duration: 0.45) }
                b.after(0.45) { [weak b] in
                    guard let b else { return }
                    FX.shared.hits(at: to, color: b.auraColor, duration: 0.5)
                    if i == 0 { b.say(b.kind.shout ?? "!!!", 1.5) }
                    Sound.shared.play(.pop, pitch: 1.4)
                }
            }
        }
    }

    /// Stop time, then drop something enormous on them. They punch their way out.
    static func dropOn(_ a: Pet, _ b: Pet) {
        guard let art = a.kind.dropArt else { return }
        a.powerCooldown = 0
        guard a.powerMove() else { return }
        let img = SpriteSheet.cached("drop-\(a.kind.id)") { Pixels.image(art, a.kind.dropPalette) }
        a.after(2.4) { [weak a, weak b] in
            guard let a, let b else { return }
            a.say(a.kind.dropShout ?? "!!!", 2.5)
            FX.shared.drop(img, onto: b.pos, scale: a.px * 1.6, duration: 5)
            b.after(1.0) { [weak a, weak b] in
                guard let b else { return }
                Sound.shared.play(.impact, pitch: 0.6)
                FX.shared.shake(1.6)
                b.emit(.dust, at: b.pos, count: 16, spread: b.size)
                b.state = .hidden(until: b.t + 3)   // squashed underneath
                a?.state = .pose(until: (a?.t ?? 0) + 3)
                a?.after(0.8) { a?.say(a?.kind.winLines.randomElement() ?? "hahaha", 2) }
            }
            b.after(3.9) { [weak a, weak b] in
                guard let b else { return }
                FX.shared.hits(at: CGPoint(x: b.pos.x, y: b.pos.y + b.size), color: b.auraColor, duration: 0.8)
                Sound.shared.play(.impact)
                b.say(b.kind.shout ?? "!!!", 1.8)
                if let a { a.knockedBack(from: b) }
            }
        }
    }

    /// A dramatic pose-off, with menacing all around.
    static func strikePoses(_ a: Pet, _ b: Pet) {
        a.state = .pose(until: a.t + 3.5)
        b.state = .pose(until: b.t + 3.5)
        a.menacingUntil = a.t + 3.5
        b.menacingUntil = b.t + 3.5
        a.say("*poses*", 2)
        b.after(0.6) { [weak b] in b?.say("*poses harder*", 2) }
    }

    /// Too tired to fight: they sit back to back and ignore each other.
    static func truce(_ a: Pet, _ b: Pet) {
        guard a.standingOn == b.standingOn else { return }
        let side: CGFloat = a.pos.x < b.pos.x ? -1 : 1
        a.walk(to: b.pos.x + side * b.size * 0.68, run: false) { [weak a, weak b] in
            guard let a, let b else { return }
            a.facingRight = side < 0
            b.facingRight = side > 0
            a.sitDown(8)
            b.sitDown(8)
            a.say("…", 2)
            b.after(1) { b.say("…", 2) }
        }
    }

    /// In the cinema seats: popcorn theft and muttering.
    static func bicker(_ a: Pet, _ b: Pet) {
        let line = a.kind.watchLines.randomElement() ?? "*steals popcorn*"
        a.say(line, 2.2)
        a.emit(.popcorn, at: CGPoint(x: b.pos.x, y: b.pos.y + b.size * 0.4), count: 4, vx: (a.pos.x > b.pos.x ? 40 : -140)...(a.pos.x > b.pos.x ? 140 : -40),
               vy: 100...200, gravity: 500, life: 0.5...0.8)
        b.after(1.4) { [weak a, weak b] in
            guard let a, let b else { return }
            b.say(b.kind.watchLines.randomElement() ?? "hey!", 2)
            if Bool.random() {
                FX.shared.hits(at: CGPoint(x: (a.pos.x + b.pos.x) / 2, y: a.pos.y + a.size * 0.6), color: b.auraColor, duration: 0.7)
                Sound.shared.play(.pop)
            }
        }
    }
}
