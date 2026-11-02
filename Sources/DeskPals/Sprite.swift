import AppKit

enum Pose: Hashable { case stand, walkA, walkB, air, sleep, sit, back }
enum Eyes: Hashable { case open, openAway, closed, happy, dizzy, sad, angry, love }

/// Turns ASCII pixel art into images.
enum Pixels {
    static func image(_ rows: [String], _ palette: [Character: UInt32]) -> CGImage {
        let grid = rows.map { Array($0) }
        let w = grid.map(\.count).max() ?? 1, h = grid.count
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let rgb = ch == "W" ? 0xFFFFFF : palette[ch] else { continue }
                let i = (y * w + x) * 4
                bytes[i] = UInt8((rgb >> 16) & 0xFF)
                bytes[i + 1] = UInt8((rgb >> 8) & 0xFF)
                bytes[i + 2] = UInt8(rgb & 0xFF)
                bytes[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// Turns a PetKind's ASCII art into 16x16 images for every pose and expression.
final class SpriteSheet {
    static let size = 16
    let kind: PetKind
    private var cache: [String: CGImage] = [:]
    private let rows: [[Character]]
    private let eyeRow: Int            // art row of the eyes' top line
    let eyeCenterX: CGFloat            // in pixels from the left, after mirroring
    let eyeCenters: [CGFloat]          // centre of each eye, in pixels from the left

    init(kind: PetKind) {
        self.kind = kind
        let n = Self.size
        rows = kind.art.map { line in
            var r = Array(line.padding(toLength: n, withPad: ".", startingAt: 0))
            if kind.mirrored { r.reverse() }
            return r
        }
        let eyes = rows.enumerated().flatMap { r, row in row.indices.filter { row[$0] == "1" }.map { (r, $0) } }
        let er = eyes.first?.0 ?? 4
        eyeRow = er
        let xs = eyes.map { CGFloat($0.1) }
        eyeCenterX = xs.isEmpty ? 8 : (xs.min()! + xs.max()! + 1) / 2
        let topXs = eyes.filter { $0.0 == er }.map(\.1).sorted()
        var runs: [[Int]] = []
        for x in topXs { if let last = runs.last?.last, x == last + 1 { runs[runs.count - 1].append(x) } else { runs.append([x]) } }
        eyeCenters = runs.map { CGFloat($0.first! + $0.last! + 1) / 2 }
    }

    private var legH: Int { kind.legs.isEmpty ? 0 : 2 }

    /// How far the body is pushed down in this pose.
    private func drop(_ pose: Pose) -> Int {
        switch pose {
        case .sleep: return legH
        case .sit, .back: return legH > 0 ? 1 : 0
        default: return 0
        }
    }

    /// Grid row (from the top) of the eyes' top line in this pose.
    func eyeGridRow(_ pose: Pose) -> Int { Self.size - legH - rows.count + drop(pose) + eyeRow }

    func image(_ pose: Pose, _ eyes: Eyes, blush: Bool = false, glasses: Bool = false) -> CGImage {
        let key = "\(pose)-\(eyes)-\(blush)-\(glasses)"
        if let hit = cache[key] { return hit }
        var pal = kind.palette
        pal["L"] = 0xFF4F86      // love-eyes pink
        pal["P"] = 0xFF9AAE      // blush
        pal["G"] = 0x111111      // sunglasses
        pal["g"] = 0x8A8AA8
        let img = Pixels.image(grid(pose, eyes, blush: blush, glasses: glasses).map { String($0) }, pal)
        cache[key] = img
        return img
    }

    func grid(_ pose: Pose, _ eyes: Eyes, blush: Bool = false, glasses: Bool = false) -> [[Character]] {
        let n = Self.size
        var g = [[Character]](repeating: [Character](repeating: ".", count: n), count: n)
        let top = n - legH - rows.count + drop(pose)
        let style: Eyes = pose == .sleep ? .closed : eyes
        let center = eyeCenterX
        for (r, row) in rows.enumerated() where (0..<n).contains(top + r) {
            for x in 0..<n {
                var ch = row[x]
                if pose == .back, ch == "1" || ch == "2" || ch == "n" {
                    ch = "b"   // seen from behind: no face
                } else if ch == "1" || ch == "2" {
                    ch = glasses && style != .closed ? lens(ch, row, x) : eyeChar(ch, row, x, style, inner: CGFloat(x) + 0.5 < center ? 1 : -1)
                }
                g[top + r][x] = ch
            }
        }
        if blush, pose != .back {
            let y = top + eyeRow + 2
            let eyeXs = rows[eyeRow].indices.filter { rows[eyeRow][$0] == "1" }
            if let l = eyeXs.min(), let r = eyeXs.max(), (0..<n).contains(y) {
                for x in [l - 1, r + 1] where (0..<n).contains(x) && g[y][x] != "." && g[y][x] != "o" { g[y][x] = "P" }
            }
        }
        if glasses, pose != .back, pose != .sleep {
            // bridge between the lenses
            let y = top + eyeRow
            let eyeXs = rows[eyeRow].indices.filter { rows[eyeRow][$0] == "1" }
            if let l = eyeXs.min(), let r = eyeXs.max() {
                for x in max(0, l - 1)...min(n - 1, r + 1) where g[y][x] != "G" && g[y][x] != "g" && g[y][x] != "." { g[y][x] = "G" }
            }
        }
        guard pose != .sleep else { return g }

        // Legs. A lifted foot is one pixel shorter and swings forward (art faces right).
        let base = n - legH
        for (i, legX) in kind.legs.enumerated() {
            let lx = kind.mirrored ? n - 2 - legX : legX
            switch pose {
            case .sit, .back:
                for dx in 0..<2 where (0..<n).contains(lx + dx + 1) { g[n - 1][lx + dx + 1] = "o" }
            default:
                let lifted = pose == .air || (pose == .walkA && i % 2 == 0) || (pose == .walkB && i % 2 == 1)
                let shift = lifted && pose != .air ? 1 : 0
                for dx in 0..<2 {
                    let x = lx + dx + shift
                    guard (0..<n).contains(x) else { continue }
                    g[base][x] = "o"
                    if !lifted { g[base + 1][x] = "o" }
                }
            }
        }
        return g
    }

    /// `inner` is +1 for the left eye (inner side is to the right), -1 for the right eye.
    private func eyeChar(_ ch: Character, _ row: [Character], _ x: Int, _ style: Eyes, inner: CGFloat) -> Character {
        let top = ch == "1"
        let rightPixel = x + 1 >= row.count || row[x + 1] != ch
        let innerPixel = inner > 0 ? rightPixel : !rightPixel
        switch style {
        case .open: return top && rightPixel ? "W" : "K"
        case .openAway: return top && !rightPixel ? "W" : "K"
        case .closed: return top ? "b" : "K"
        case .happy: return top ? "K" : "b"
        case .dizzy: return (x + (top ? 0 : 1)) % 2 == 0 ? "K" : "b"
        case .sad: return top ? (innerPixel ? "K" : "b") : "K"
        case .angry: return top ? (innerPixel ? "b" : "K") : "K"
        case .love: return "b"   // drawn on top as mini-pixel hearts (see heartEye)
        }
    }

    private func lens(_ ch: Character, _ row: [Character], _ x: Int) -> Character {
        let rightPixel = x + 1 >= row.count || row[x + 1] != ch
        return ch == "1" && rightPixel ? "g" : "G"
    }

    // MARK: - Extras

    private static var extraCache: [String: CGImage] = [:]

    static func cached(_ key: String, _ make: () -> CGImage) -> CGImage {
        if let hit = extraCache[key] { return hit }
        let img = make()
        extraCache[key] = img
        return img
    }

    static func accessoryImage(_ a: Accessory) -> CGImage? {
        guard let art = a.art else { return nil }
        return cached("acc-\(a.rawValue)") { Pixels.image(art.rows, art.palette) }
    }

    /// A heart drawn with pixels smaller than the pet's, so it reads as a heart and not a blob.
    static let heartEye = Pixels.image(["rr.rr", "rWrrr", "rrrrr", ".rrr.", "..r.."], ["r": 0xFF3D7F])

    static let popcorn = Pixels.image([".wyw.", "wywyw", "rWrWr", "rWrWr", ".rWr."], ["w": 0xFFF8E1, "y": 0xFFD54F, "r": 0xE53935])

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

    static func icon(_ cg: CGImage, points: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .none
            let s = min(rect.width / CGFloat(cg.width), rect.height / CGFloat(cg.height))
            let w = CGFloat(cg.width) * s, h = CGFloat(cg.height) * s
            ctx.draw(cg, in: CGRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
            return true
        }
    }

    /// Every pet in every pose on one PNG, for checking the art (`DeskPals --preview out.png`).
    static func writePreview(to path: String) {
        let combos: [(Pose, Eyes, Bool, Bool)] = [
            (.stand, .open, false, false), (.walkA, .open, false, false), (.walkB, .open, false, false),
            (.air, .open, false, false), (.sleep, .closed, false, false), (.sit, .open, false, false),
            (.back, .open, false, false), (.stand, .happy, true, false), (.stand, .dizzy, false, false),
            (.stand, .sad, false, false), (.stand, .angry, false, false), (.stand, .love, true, false),
            (.stand, .open, false, true),
        ]
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
                ctx.draw(sheet.image(combo.0, combo.1, blush: combo.2, glasses: combo.3), in: rect)
                if combo.1 == .love {
                    let mini = CGFloat(px) * 0.62, img = heartEye
                    let w = CGFloat(img.width) * mini, hh = CGFloat(img.height) * mini
                    let cy = rect.minY + (16 - CGFloat(sheet.eyeGridRow(combo.0)) - 1) * CGFloat(px)
                    for cx in sheet.eyeCenters {
                        ctx.draw(img, in: CGRect(x: rect.minX + cx * CGFloat(px) - w / 2, y: cy - hh / 2, width: w, height: hh))
                    }
                }
            }
            // accessories on the last column's neighbours are checked in-app
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
