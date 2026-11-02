import AppKit

/// A clear, click-through panel that follows the pet around. It only takes the mouse
/// while the cursor is over the pet itself, so everything else on screen stays clickable.
final class PetWindow: NSPanel {
    private let pet: Pet
    private let petView: PetView

    init(pet: Pet) {
        self.pet = pet
        self.petView = PetView(pet: pet)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = petView
        sync()
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Room around the pet for hats, speech bubbles, particles and climbing sideways.
    var margin: CGFloat { pet.size * 0.7 + 10 }

    func sync() {
        let w = max(pet.size * 3.4, 340), h = pet.size * 2.4 + 160 + pet.bubbleOffset
        let shake = FX.shared.shakeOffset
        let origin = CGPoint(x: (pet.pos.x - w / 2 + shake.x).rounded(), y: (pet.pos.y - margin + shake.y).rounded())
        setFrame(CGRect(origin: origin, size: CGSize(width: w, height: h)), display: false)
        petView.feet = CGPoint(x: pet.pos.x - origin.x, y: pet.pos.y - origin.y)
        petView.needsDisplay = true
        // Hide & seek: tuck the pet's window behind the window it's hiding behind.
        if let id = pet.hidingWindowID {
            if level != .normal { level = .normal }
            order(.below, relativeTo: id)
        } else if FX.shared.owns(pet) {
            // the one who stopped time stays in full colour, above the gray bubble
            let above = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            if level != above { level = above; orderFrontRegardless() }
        } else if level != .floating {
            level = .floating
            orderFrontRegardless()
        }
        let wantsMouse = pet.isDragged || pet.bodyRect.contains(NSEvent.mouseLocation)
        if ignoresMouseEvents == wantsMouse { ignoresMouseEvents = !wantsMouse }
    }
}

final class PetView: NSView {
    private let pet: Pet
    var feet = CGPoint.zero

    init(pet: Pet) {
        self.pet = pet
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { pet.doubleClicked() } else { pet.beginDrag(NSEvent.mouseLocation) }
    }
    override func mouseDragged(with event: NSEvent) { pet.drag(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { pet.endDrag(NSEvent.mouseLocation) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let window else { return }
        ctx.interpolationQuality = .none
        let l = pet.look(), s = pet.size, px = pet.px

        if !l.hidden {
            ctx.saveGState()
            ctx.translateBy(x: feet.x, y: feet.y + l.lift * px)
            ctx.rotate(by: l.rot)
            ctx.scaleBy(x: (l.flip ? -1 : 1) * l.sx, y: l.sy)
            if l.aura > 0.05 {
                ctx.setAlpha(min(1, l.aura) * (pet.isTransformed ? 0.45 : 0.75))
                ctx.draw(pet.drawSheet.auraImage(l.pose, color: pet.auraColor, frame: Int(CACurrentMediaTime() * 12) % 3),
                         in: CGRect(x: -s / 2 - 2 * px, y: -2 * px, width: s + 4 * px, height: s + 4 * px))
                ctx.setAlpha(1)
            }
            ctx.draw(pet.drawSheet.image(l.pose, l.eyes, blush: l.blush, glasses: l.glasses), in: CGRect(x: -s / 2, y: 0, width: s, height: s))
            if l.eyes == .love, l.pose != .back, l.pose != .sleep { drawHeartEyes(ctx, pose: l.pose) }
            drawAccessory(ctx, pose: l.pose)
            ctx.restoreGState()
            if l.umbrella {
                let img = Self.umbrella
                let w = CGFloat(img.width) * px, h = CGFloat(img.height) * px
                ctx.draw(img, in: CGRect(x: feet.x - w / 2 + px * 2, y: feet.y + s * 0.75 + l.lift * px, width: w, height: h))
            }
            if l.popcorn {
                let img = SpriteSheet.popcorn
                ctx.draw(img, in: CGRect(x: feet.x + s * 0.35, y: feet.y, width: CGFloat(img.width) * px, height: CGFloat(img.height) * px))
            }
        }

        let origin = window.frame.origin
        for p in pet.particles {
            let img = Particle.image(for: p)
            let fade = p.kind == .dust || p.kind == .fire ? CGFloat(p.life / p.maxLife) : min(1, CGFloat(p.life / p.maxLife) * 3)
            ctx.setAlpha(fade)
            let ppx = px * (p.kind == .heart || p.kind == .note ? 0.8 : 0.7)
            let w = CGFloat(img.width) * ppx, h = CGFloat(img.height) * ppx
            ctx.draw(img, in: CGRect(x: p.pos.x - origin.x - w / 2, y: p.pos.y - origin.y - h / 2, width: w, height: h))
        }
        ctx.setAlpha(1)

        if !l.hidden, let text = pet.bubble, Senses.on(Keys.bubbles) {
            drawBubble(text, at: feet.y + s * l.sy + l.lift * px + (pet.accessory.art == nil ? 4 : 4 + 4 * px) + pet.bubbleOffset)
        }
    }

    /// Love eyes: a small heart over each eye, at about half the pet's pixel size.
    private func drawHeartEyes(_ ctx: CGContext, pose: Pose) {
        let img = SpriteSheet.heartEye
        let n = CGFloat(SpriteSheet.size), px = pet.px, s = pet.size
        let mini = px * 0.62
        let w = CGFloat(img.width) * mini, h = CGFloat(img.height) * mini
        let cy = (n - CGFloat(pet.drawSheet.eyeGridRow(pose)) - 1) * px
        for cx in pet.drawSheet.eyeCenters {
            ctx.draw(img, in: CGRect(x: -s / 2 + cx * px - w / 2, y: cy - h / 2, width: w, height: h))
        }
    }

    /// Hats sit on top of the head and move with every squash, flip and spin.
    private func drawAccessory(_ ctx: CGContext, pose: Pose) {
        guard let art = pet.accessory.art, let img = SpriteSheet.accessoryImage(pet.accessory) else { return }
        let n = CGFloat(SpriteSheet.size), px = pet.px, s = pet.size
        let bottomRow = CGFloat(pet.drawSheet.eyeGridRow(pose) - 2 - art.lift)
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let x = -s / 2 + (pet.drawSheet.eyeCenterX + CGFloat(art.dx) - w / 2) * px
        let y = (n - 1 - bottomRow) * px
        ctx.draw(img, in: CGRect(x: x, y: y, width: w * px, height: h * px))
    }

    static let umbrella = Pixels.image([".....o.....", "..rrrrrrr..", ".rrWrrrWrr.", "rrrrrrrrrrr", ".....o.....", ".....o.....", "....oo....."],
                                       ["r": 0x3FA9F5, "o": 0x444444])

    private func drawBubble(_ text: String, at y: CGFloat) {
        let (str, size) = Bubble.layout(text, scale: pet.scale)
        let r = CGRect(x: feet.x - size.width / 2, y: y, width: size.width, height: size.height)
        let radius = min(r.height / 2, 11)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        path.fill()
        Bubble.ink.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        str.draw(with: r.insetBy(dx: Bubble.pad, dy: 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// Speech bubbles: long lines wrap, and bubbles of pets close together stack instead of overlapping.
enum Bubble {
    static let maxWidth: CGFloat = 200
    static let pad: CGFloat = 6
    static let ink = NSColor(white: 0.12, alpha: 1)

    static func layout(_ text: String, scale: CGFloat) -> (NSAttributedString, CGSize) {
        let pt = max(11, 3.2 * scale)
        var font = NSFont.systemFont(ofSize: pt, weight: .heavy)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: pt) ?? font }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: para])
        let r = str.boundingRect(with: CGSize(width: maxWidth, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return (str, CGSize(width: ceil(r.width) + pad * 2, height: ceil(r.height) + 4))
    }

    /// Called every frame: nudges bubbles upward until none of them overlap.
    static func stack(_ pets: [Pet]) {
        let talking = pets.compactMap { p -> (Pet, CGRect)? in
            guard let text = p.bubble else {
                p.bubbleOffset *= 0.8
                return nil
            }
            let size = layout(text, scale: p.scale).1
            let y = p.pos.y + p.size + 4 + (p.accessory.art == nil ? 0 : 4 * p.scale)
            return (p, CGRect(x: p.pos.x - size.width / 2, y: y, width: size.width, height: size.height))
        }.sorted { ($0.1.minY, $0.1.minX) < ($1.1.minY, $1.1.minX) }
        var placed: [CGRect] = []
        for (p, base) in talking {
            var r = base
            while let hit = placed.first(where: { $0.insetBy(dx: -4, dy: -3).intersects(r) }) { r.origin.y = hit.maxY + 4 }
            placed.append(r)
            p.bubbleOffset += (r.minY - base.minY - p.bubbleOffset) * 0.35
        }
    }
}
