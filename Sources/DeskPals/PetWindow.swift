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

    func sync() {
        let w = max(pet.size + 40, 210), h = pet.size * 1.3 + 60
        setFrame(CGRect(x: (pet.pos.x - w / 2).rounded(), y: pet.pos.y.rounded(), width: w, height: h), display: false)
        petView.needsDisplay = true
        let wantsMouse = pet.isDragged || pet.bodyRect.contains(NSEvent.mouseLocation)
        if ignoresMouseEvents == wantsMouse { ignoresMouseEvents = !wantsMouse }
    }
}

final class PetView: NSView {
    private let pet: Pet

    init(pet: Pet) {
        self.pet = pet
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pet.beginDrag(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { pet.drag(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { pet.endDrag(NSEvent.mouseLocation) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        let l = pet.look(), s = pet.size
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: l.lift * pet.scale)
        ctx.rotate(by: l.rot)
        ctx.scaleBy(x: (l.flip ? -1 : 1) * l.sx, y: l.sy)
        ctx.draw(pet.sheet.image(l.pose, l.eyes), in: CGRect(x: -s / 2, y: 0, width: s, height: s))
        ctx.restoreGState()
        if let text = pet.bubble, Senses.on(Keys.bubbles) { drawBubble(text, at: s * l.sy + l.lift * pet.scale + 4) }
    }

    private func drawBubble(_ text: String, at y: CGFloat) {
        let size = max(11, 3.2 * pet.scale)
        var font = NSFont.systemFont(ofSize: size, weight: .heavy)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: size) ?? font }
        let ink = NSColor(white: 0.12, alpha: 1)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        let ts = str.size()
        let pad: CGFloat = 6
        let r = CGRect(x: bounds.midX - ts.width / 2 - pad, y: y, width: ts.width + pad * 2, height: ts.height + 4)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        NSColor.white.setFill()
        path.fill()
        ink.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        str.draw(at: CGPoint(x: r.minX + pad, y: r.minY + 2))
    }
}
