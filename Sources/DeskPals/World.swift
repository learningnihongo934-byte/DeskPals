import AppKit

/// Something the pet can stand on: the visible top edge of a window, or the floor of a screen.
struct Platform {
    let id: Int              // window number, or negative for a screen floor
    let frame: CGRect        // Cocoa coordinates
    let y: CGFloat
    let segments: [ClosedRange<CGFloat>]   // stretches of the edge not hidden behind other windows

    func holds(_ x: CGFloat) -> Bool { segments.contains { $0.contains(x) } }
}

/// The desktop as the pet sees it, rebuilt from the window list many times a second.
/// Only window bounds are read (no titles or contents), so no Screen Recording permission is needed.
final class World {
    private(set) var platforms: [Platform] = []
    private(set) var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private var byID: [Int: Platform] = [:]
    private var seen = Set<Int>()
    private var seeded = false
    private let me = ProcessInfo.processInfo.processIdentifier

    func platform(_ id: Int?) -> Platform? { id.flatMap { byID[$0] } }

    /// Rebuilds the platforms and returns windows that appeared since the last call.
    @discardableResult
    func refresh() -> [Int] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let flipH = primary.frame.height
        bounds = screens.reduce(CGRect.null) { $0.union($1.frame) }

        var found: [Platform] = screens.enumerated().map { i, s in
            let v = s.visibleFrame
            return Platform(id: -(i + 1), frame: v, y: v.minY, segments: [v.minX...v.maxX])
        }

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var inFront: [CGRect] = []
        var fresh: [Int] = []
        for w in list {   // front to back
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict) else { continue }
            let r = CGRect(x: cg.minX, y: flipH - cg.maxY, width: cg.width, height: cg.height)
            defer { inFront.append(r) }
            guard r.width >= 120, r.height >= 60 else { continue }

            if seen.insert(id).inserted, seeded { fresh.append(id) }

            // Maximised windows have their top under the menu bar: nowhere to stand.
            let top = r.maxY
            if let s = screens.first(where: { $0.frame.minX <= r.midX && r.midX < $0.frame.maxX }),
               top > s.visibleFrame.maxY - 30 { continue }

            var segs: [ClosedRange<CGFloat>] = [r.minX...r.maxX]
            for f in inFront where f.minY < top + 4 && f.maxY > top - 2 {
                segs = segs.flatMap { cut($0, f.minX, f.maxX) }
            }
            segs = segs.filter { $0.upperBound - $0.lowerBound > 24 }
            if !segs.isEmpty { found.append(Platform(id: id, frame: r, y: top, segments: segs)) }
        }

        platforms = found
        byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        seeded = true
        return fresh
    }

    /// The highest platform crossed while falling from y0 to y1 at x.
    func landing(x: CGFloat, from y0: CGFloat, to y1: CGFloat) -> Platform? {
        platforms.filter { $0.y <= y0 + 0.5 && $0.y >= y1 && $0.holds(x) }.max { $0.y < $1.y }
    }

    /// A random spot on another ledge within jumping range.
    func hopTarget(from p: CGPoint, excluding id: Int?, margin: CGFloat) -> CGPoint? {
        var options: [CGPoint] = []
        for pl in platforms where pl.id != id {
            let rise = pl.y - p.y
            guard rise < 520, rise > -1400 else { continue }
            for s in pl.segments where s.upperBound - s.lowerBound > margin * 2 {
                let x = clamp(p.x + .random(in: -260...260), s.lowerBound + margin, s.upperBound - margin)
                if abs(x - p.x) < 650 { options.append(CGPoint(x: x, y: pl.y)) }
            }
        }
        return options.randomElement()
    }

    func screenTop(at x: CGFloat) -> CGFloat {
        let s = NSScreen.screens.first { $0.frame.minX <= x && x < $0.frame.maxX }
        return s?.visibleFrame.maxY ?? bounds.maxY
    }

    private func cut(_ s: ClosedRange<CGFloat>, _ a: CGFloat, _ b: CGFloat) -> [ClosedRange<CGFloat>] {
        if b <= s.lowerBound || a >= s.upperBound { return [s] }
        var out: [ClosedRange<CGFloat>] = []
        if a > s.lowerBound { out.append(s.lowerBound...a) }
        if b < s.upperBound { out.append(b...s.upperBound) }
        return out
    }
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    lo > hi ? lo : min(max(v, lo), hi)
}
