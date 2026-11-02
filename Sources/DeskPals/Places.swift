import AppKit

/// A tiny drawing surface for building pixel art in code.
struct PixelCanvas {
    let w: Int, h: Int
    private(set) var rows: [[Character]]

    init(_ w: Int, _ h: Int) {
        self.w = w
        self.h = h
        rows = Array(repeating: Array(repeating: ".", count: w), count: h)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: Character) {
        guard (0..<w).contains(x), (0..<h).contains(y) else { return }
        rows[y][x] = c
    }

    mutating func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Character) {
        for y in y0...y1 { for x in x0...x1 { set(x, y, c) } }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Character, outline: Character? = nil) {
        for y in 0..<h {
            for x in 0..<w {
                let d = pow((Double(x) + 0.5 - cx) / rx, 2) + pow((Double(y) + 0.5 - cy) / ry, 2)
                if d <= 1 { set(x, y, c) }
            }
        }
        guard let outline else { return }
        let inside = rows
        for y in 0..<h {
            for x in 0..<w where inside[y][x] == c {
                let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                    let nx = x + dx, ny = y + dy
                    return !(0..<w).contains(nx) || !(0..<h).contains(ny) || inside[ny][nx] == "."
                }
                if edge { set(x, y, outline) }
            }
        }
    }

    var strings: [String] { rows.map { String($0) } }
}

/// Places you can put on your desktop. Pets visit them on their own.
enum Place: String, CaseIterable {
    case house, pond, garden, swing, slide, campfire

    var shopID: String { "place.\(rawValue)" }
    var title: String { rawValue.capitalized }

    /// Where pets stand on the place (relative to its rect, in pixels from the left and bottom), if anywhere.
    var ledge: (x0: Int, x1: Int, y: Int)? {
        switch self {
        case .house: return (9, 14, 20)
        case .slide: return (0, 6, 18)
        default: return nil
        }
    }

    func image(frame: Int = 0, stage: Int = 0, lit: Bool = false) -> CGImage {
        SpriteSheet.cached("place-\(rawValue)-\(frame)-\(stage)-\(lit)") {
            let (rows, pal) = art(frame: frame, stage: stage, lit: lit)
            return Pixels.image(rows, pal)
        }
    }

    private func art(frame: Int, stage: Int, lit: Bool) -> ([String], [Character: UInt32]) {
        switch self {
        case .house:
            var c = PixelCanvas(24, 20)
            for r in 0..<8 {
                let half = 2 + r * 10 / 7
                c.fill(12 - half, r, 11 + half, r, "r")
                c.set(12 - half, r, "o")
                c.set(11 + half, r, "o")
            }
            c.fill(10, 0, 13, 0, "o")
            c.fill(17, 1, 18, 4, "k")
            c.fill(2, 8, 21, 19, "w")
            c.fill(2, 8, 2, 19, "o")
            c.fill(21, 8, 21, 19, "o")
            c.fill(1, 8, 22, 8, "o")
            c.fill(2, 19, 21, 19, "o")
            c.fill(10, 13, 13, 18, "d")
            c.set(12, 16, "y")
            c.fill(4, 10, 7, 13, lit ? "l" : "g")
            c.fill(16, 10, 19, 13, lit ? "l" : "g")
            c.fill(5, 11, 5, 12, "W")
            return (c.strings, ["r": 0xC2453A, "o": 0x4A2A22, "k": 0x9C4A3A, "w": 0xF2E2C4, "d": 0x8A5A34,
                                "y": 0xFFD54F, "g": 0x9AD7FF, "l": 0xFFE08A])
        case .pond:
            var c = PixelCanvas(30, 9)
            c.ellipse(15, 4.5, 15, 4.5, "s", outline: "o")
            c.ellipse(15, 4.8, 12.5, 3.3, "b")
            let ripples = frame == 0 ? [(8, 4), (19, 5)] : [(11, 5), (21, 4)]
            for (x, y) in ripples { c.fill(x, y, x + 2, y, "h") }
            c.set(5, 1, "g"); c.set(5, 0, "g"); c.set(25, 1, "g"); c.set(24, 0, "g")
            return (c.strings, ["s": 0xB8A58A, "o": 0x5C5040, "b": 0x4FA3E0, "h": 0xBDE6FF, "g": 0x4CAF50])
        case .garden:
            var c = PixelCanvas(26, 11)
            c.fill(0, 8, 25, 10, "d")
            c.fill(0, 8, 25, 8, "D")
            let flowers = [2, 7, 12, 17, 22]
            for (i, x) in flowers.enumerated() {
                let height = stage == 0 ? 1 : (stage == 1 ? 3 : 5)
                c.fill(x + 1, 8 - height, x + 1, 7, "g")
                if stage == 0 { c.set(x, 7, "g"); c.set(x + 2, 7, "g"); continue }
                let bloom: Character = ["p", "y", "r", "p", "y"][i]
                let top = 7 - height
                if stage == 1 { c.set(x + 1, top, bloom) } else {
                    c.set(x + 1, top - 1, bloom); c.set(x, top, bloom); c.set(x + 2, top, bloom); c.set(x + 1, top, "y")
                    c.set(x + 1, top + 1, bloom)
                }
            }
            return (c.strings, ["d": 0x7A5134, "D": 0x5A3A22, "g": 0x4CAF50, "p": 0xFF7EB6, "y": 0xFFD54F, "r": 0xE53935])
        case .swing:
            var c = PixelCanvas(20, 24)
            c.fill(0, 0, 19, 1, "w")
            c.fill(0, 0, 19, 0, "o")
            for y in 2..<24 {
                let spread = y / 6
                c.set(2 - spread, y, "w"); c.set(3 - spread, y, "o")
                c.set(17 + spread, y, "w"); c.set(16 + spread, y, "o")
            }
            return (c.strings, ["w": 0xC9894A, "o": 0x6B4423])
        case .slide:
            var c = PixelCanvas(26, 20)
            c.fill(0, 2, 0, 19, "m"); c.fill(5, 2, 5, 19, "m")
            for y in stride(from: 4, to: 20, by: 3) { c.fill(1, y, 4, y, "m") }
            c.fill(0, 2, 6, 3, "p")
            for i in 0..<19 {
                let x = 6 + i, y = 3 + i * 16 / 19
                c.set(x, y, "y"); c.set(x, y + 1, "Y")
            }
            return (c.strings, ["m": 0x8E9AAF, "p": 0x4FC3F7, "y": 0xFFD54F, "Y": 0xE0A23A])
        case .campfire:
            var c = PixelCanvas(14, 11)
            c.fill(1, 9, 12, 10, "l"); c.fill(3, 8, 10, 8, "L")
            let flame = frame == 0
                ? ["....y.....", "...yoy....", "..yorry...", "..orrro...", "...oro...."]
                : [".....y....", "....yoy...", "...yrroy..", "...orrro..", "....oro..."]
            for (dy, row) in flame.enumerated() {
                for (dx, ch) in row.enumerated() where ch != "." { c.set(2 + dx, 3 + dy, ch) }
            }
            return (c.strings, ["l": 0x6B4423, "L": 0x8A5A34, "y": 0xFFE066, "o": 0xFF8A1F, "r": 0xE53935])
        }
    }

    /// Swing seat, drawn separately so it can swing.
    static let seat = Pixels.image(["oooooo", "wwwwww"], ["o": 0x6B4423, "w": 0xC9894A])
}
