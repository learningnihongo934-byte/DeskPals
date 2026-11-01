import AppKit

enum Pose: Hashable { case stand, walkA, walkB, air, sleep }
enum Eyes: Hashable { case open, closed, happy, dizzy }

/// Turns a PetKind's ASCII art into 16x16 images, one per pose and eye style.
final class SpriteSheet {
    static let size = 16
    let kind: PetKind
    private var cache: [String: CGImage] = [:]

    init(kind: PetKind) { self.kind = kind }

    func image(_ pose: Pose, _ eyes: Eyes) -> CGImage {
        let key = "\(pose)-\(eyes)"
        if let hit = cache[key] { return hit }
        let img = render(grid(pose, eyes))
        cache[key] = img
        return img
    }

    func grid(_ pose: Pose, _ eyes: Eyes) -> [[Character]] {
        let n = Self.size
        var g = [[Character]](repeating: [Character](repeating: ".", count: n), count: n)
        let rows: [[Character]] = kind.art.map { line in
            var r = Array(line.padding(toLength: n, withPad: ".", startingAt: 0))
            if kind.mirrored { r.reverse() }
            return r
        }
        let legH = kind.legs.isEmpty ? 0 : 2
        let top = n - legH - rows.count + (pose == .sleep ? legH : 0)
        let style = pose == .sleep ? Eyes.closed : eyes
        for (r, row) in rows.enumerated() where (0..<n).contains(top + r) {
            for x in 0..<n { g[top + r][x] = eyeChar(row, x, style) }
        }
        guard pose != .sleep else { return g }

        // Legs. A lifted foot is one pixel shorter and swings forward (art faces right).
        let base = n - legH
        for (i, legX) in kind.legs.enumerated() {
            let lx = kind.mirrored ? n - 2 - legX : legX
            let lifted = pose == .air || (pose == .walkA && i % 2 == 0) || (pose == .walkB && i % 2 == 1)
            let shift = lifted && pose != .air ? 1 : 0
            for dx in 0..<2 {
                let x = lx + dx + shift
                guard (0..<n).contains(x) else { continue }
                g[base][x] = "o"
                if !lifted { g[base + 1][x] = "o" }
            }
        }
        return g
    }

    private func eyeChar(_ row: [Character], _ x: Int, _ style: Eyes) -> Character {
        let ch = row[x]
        guard ch == "1" || ch == "2" else { return ch }
        let top = ch == "1"
        switch style {
        case .open:
            let rightPixel = x + 1 >= row.count || row[x + 1] != "1"
            return top && rightPixel ? "W" : "K"
        case .closed: return top ? "b" : "K"
        case .happy: return top ? "K" : "b"
        case .dizzy: return (x + (top ? 0 : 1)) % 2 == 0 ? "K" : "b"
        }
    }

    private func color(_ ch: Character) -> UInt32? {
        switch ch {
        case ".": return nil
        case "W": return 0xFFFFFF
        case "K": return kind.palette["K"] ?? 0x1A1A1A
        default: return kind.palette[ch]
        }
    }

    private func render(_ g: [[Character]]) -> CGImage {
        let n = Self.size
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                guard let rgb = color(g[y][x]) else { continue }
                let i = (y * n + x) * 4
                bytes[i] = UInt8((rgb >> 16) & 0xFF)
                bytes[i + 1] = UInt8((rgb >> 8) & 0xFF)
                bytes[i + 2] = UInt8(rgb & 0xFF)
                bytes[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Crisp icon for menus: nearest-neighbour at whatever backing scale the menu uses.
    static func icon(for kind: PetKind, points: CGFloat) -> NSImage {
        let cg = SpriteSheet(kind: kind).image(.stand, .open)
        return NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: rect)
            return true
        }
    }

    /// Every pet in every pose on one PNG, for checking the art (`DeskPals --preview out.png`).
    static func writePreview(to path: String) {
        let combos: [(Pose, Eyes)] = [(.stand, .open), (.walkA, .open), (.walkB, .open), (.air, .open),
                                      (.sleep, .closed), (.stand, .happy), (.stand, .dizzy)]
        let px = 8, cell = 16 * px + 16
        let w = combos.count * cell, h = PetKind.all.count * cell
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        for (r, kind) in PetKind.all.enumerated() {
            let sheet = SpriteSheet(kind: kind)
            for (c, combo) in combos.enumerated() {
                let rect = CGRect(x: c * cell + 8, y: h - (r + 1) * cell + 8, width: 16 * px, height: 16 * px)
                ctx.draw(sheet.image(combo.0, combo.1), in: rect)
            }
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
