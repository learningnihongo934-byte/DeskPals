import AppKit
import ApplicationServices

/// Something the pet can stand on: the visible top edge of a window, the Dock, a bed, or the floor.
struct Platform {
    let id: Int              // window number; negative for floors and the Dock; Props.bedBase+ for the bed
    let frame: CGRect        // Cocoa coordinates
    let y: CGFloat
    let segments: [ClosedRange<CGFloat>]   // stretches of the edge not hidden behind other windows

    func holds(_ x: CGFloat) -> Bool { segments.contains { $0.contains(x) } }
}

struct WindowInfo {
    let id: Int
    let pid: pid_t
    let frame: CGRect
}

struct DockItem {
    let title: String
    let frame: CGRect
    let isTrash: Bool
}

struct DockInfo {
    let frame: CGRect
    let items: [DockItem]
    var top: CGFloat { items.map(\.frame.maxY).max() ?? frame.maxY }
    var trash: DockItem? { items.first { $0.isTrash } }
}

/// The desktop as the pet sees it, rebuilt from the window list many times a second.
/// Only window bounds are read (no titles or contents), so no Screen Recording permission is needed.
final class World {
    static let dockID = -1000

    private(set) var platforms: [Platform] = []
    private(set) var windows: [WindowInfo] = []
    private(set) var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var dock: DockInfo?
    var ledges: Ledges?
    var extraPlatforms: (() -> [Platform])?
    private var byID: [Int: Platform] = [:]
    private var seen = Set<Int>()
    private var seeded = false
    private let me = ProcessInfo.processInfo.processIdentifier

    func platform(_ id: Int?) -> Platform? { id.flatMap { byID[$0] } }
    func windowInfo(_ id: Int) -> WindowInfo? { windows.first { $0.id == id } }

    func largestWindow(of pid: pid_t, minSize: CGSize = CGSize(width: 320, height: 200)) -> WindowInfo? {
        windows.filter { $0.pid == pid && $0.frame.width >= minSize.width && $0.frame.height >= minSize.height }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Rebuilds the platforms and returns windows that appeared since the last call.
    @discardableResult
    func refresh() -> [Int] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let flipH = primary.frame.height
        bounds = screens.reduce(CGRect.null) { $0.union($1.frame) }

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        // macOS keeps the Dock's space reserved even while it's hidden (full-screen apps),
        // so only stand above it when its window is actually on screen.
        let dockShowing = list.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == 20
        }

        var found: [Platform] = []
        for (i, s) in screens.enumerated() {
            let v = s.visibleFrame
            if !dockShowing {
                found.append(Platform(id: -(i + 1), frame: s.frame, y: s.frame.minY + 1, segments: [s.frame.minX...s.frame.maxX]))
            } else if let dock, s.frame.contains(CGPoint(x: dock.frame.midX, y: dock.frame.midY)) {
                // Stand on the Dock's icons; beside the Dock, the floor is the very bottom of the screen.
                found.append(Platform(id: Self.dockID, frame: dock.frame, y: dock.top,
                                      segments: [dock.frame.minX...dock.frame.maxX]))
                var segs: [ClosedRange<CGFloat>] = []
                if dock.frame.minX - s.frame.minX > 30 { segs.append(s.frame.minX...dock.frame.minX) }
                if s.frame.maxX - dock.frame.maxX > 30 { segs.append(dock.frame.maxX...s.frame.maxX) }
                if !segs.isEmpty { found.append(Platform(id: -(i + 1), frame: s.frame, y: s.frame.minY + 2, segments: segs)) }
            } else {
                found.append(Platform(id: -(i + 1), frame: v, y: v.minY, segments: [v.minX...v.maxX]))
            }
        }

        var inFront: [CGRect] = []
        var fresh: [Int] = []
        var infos: [WindowInfo] = []
        for w in list {   // front to back
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict) else { continue }
            let r = CGRect(x: cg.minX, y: flipH - cg.maxY, width: cg.width, height: cg.height)
            defer { inFront.append(r) }
            guard r.width >= 120, r.height >= 60 else { continue }
            infos.append(WindowInfo(id: id, pid: pid, frame: r))

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
        // Text boxes, buttons and toolbars inside the front window, if it's still in front.
        if let ledges, let front = infos.first, abs(front.frame.minX - ledges.window.minX) < 3,
           abs(front.frame.maxY - ledges.window.maxY) < 3, abs(front.frame.width - ledges.window.width) < 3 {
            for l in ledges.items where l.frame.maxY < front.frame.maxY - 8 {
                found.append(Platform(id: l.id, frame: l.frame, y: l.frame.maxY,
                                      segments: [(l.frame.minX + 2)...(l.frame.maxX - 2)]))
            }
        }
        found += extraPlatforms?() ?? []

        windows = infos
        platforms = found
        byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        seeded = true
        return fresh
    }

    /// The highest platform crossed while falling from y0 to y1 at x.
    func landing(x: CGFloat, from y0: CGFloat, to y1: CGFloat, ignoring: Int? = nil) -> Platform? {
        platforms.filter { $0.id != ignoring && $0.y <= y0 + 0.5 && $0.y >= y1 && $0.holds(x) }.max { $0.y < $1.y }
    }

    /// The highest platform under a point.
    func ground(below p: CGPoint) -> Platform? {
        platforms.filter { $0.y <= p.y + 0.5 && $0.holds(p.x) }.max { $0.y < $1.y }
    }

    /// A ledge just ahead that is a small step up or down from `y`, for walking off one platform onto another.
    func step(at x: CGFloat, from y: CGFloat, excluding id: Int?, self own: Int? = nil) -> Platform? {
        platforms.filter { $0.id != id && $0.id != own && $0.holds(x) && abs($0.y - y) < 220 }.max { $0.y < $1.y }
    }

    /// A random spot on another ledge within jumping range.
    func hopTarget(from p: CGPoint, excluding id: Int?, self own: Int? = nil, margin: CGFloat) -> CGPoint? {
        var options: [CGPoint] = []
        for pl in platforms where pl.id != id && pl.id != own {
            let rise = pl.y - p.y
            guard rise < 520, rise > -1400 else { continue }
            for s in pl.segments where s.upperBound - s.lowerBound > margin * 2 {
                let x = clamp(p.x + .random(in: -260...260), s.lowerBound + margin, s.upperBound - margin)
                if abs(x - p.x) < 650 { options.append(CGPoint(x: x, y: pl.y)) }
            }
        }
        return options.randomElement()
    }

    func screenFrame(at x: CGFloat) -> CGRect {
        NSScreen.screens.first { $0.frame.minX <= x && x < $0.frame.maxX }?.frame ?? bounds
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

/// Reads the Dock's icons through Accessibility, so the pet can walk on them.
/// Without that permission the pet stands on top of the Dock as one long ledge.
enum DockReader {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func read() -> DockInfo? {
        guard trusted, let primary = NSScreen.screens.first,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let flipH = primary.frame.height
        let dock = AXUIElementCreateApplication(app.processIdentifier)
        guard let list = (copy(dock, kAXChildrenAttribute) as? [AXUIElement])?.first,
              let listFrame = frame(list, flipH) else { return nil }
        // Bottom Dock only, and not while it's auto-hidden off screen.
        guard listFrame.width > listFrame.height,
              NSScreen.screens.contains(where: { $0.frame.intersects(listFrame) && listFrame.minY >= $0.frame.minY - 1 })
        else { return nil }
        var items: [DockItem] = []
        for el in copy(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            let subrole = copy(el, kAXSubroleAttribute) as? String ?? ""
            guard subrole != "AXSeparatorDockItem", let f = frame(el, flipH) else { continue }
            items.append(DockItem(title: copy(el, kAXTitleAttribute) as? String ?? "", frame: f,
                                  isTrash: subrole == "AXTrashDockItem"))
        }
        return items.isEmpty ? nil : DockInfo(frame: listFrame, items: items)
    }

    private static func copy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }

    private static func frame(_ el: AXUIElement, _ flipH: CGFloat) -> CGRect? {
        guard let pv = copy(el, kAXPositionAttribute), let sv = copy(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(x: p.x, y: flipH - p.y - s.height, width: s.width, height: s.height)
    }
}

struct Ledge {
    let id: Int
    let frame: CGRect
}

/// Things inside the front window that make good ledges, found with the same Accessibility
/// permission as the Dock. Only roles and positions are read, never any text or values.
struct Ledges {
    static let base = 1_000_000
    static let roles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXButton",
                                     "AXPopUpButton", "AXImage", "AXToolbar", "AXTabGroup", "AXWebArea"]
    let window: CGRect
    let items: [Ledge]

    /// Slow-ish (walks another app's accessibility tree), so call it off the main thread.
    static func read(pid: pid_t, flipH: CGFloat) -> Ledges? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Electron apps (like Claude, VS Code, Discord) only build their tree when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let win = attr(app, kAXFocusedWindowAttribute).map({ $0 as! AXUIElement }),
              let wf = frame(win, flipH) else { return nil }
        var items: [Ledge] = []
        var queue: [(AXUIElement, Int)] = [(win, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 900, items.count < 60 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            let role = attr(el, kAXRoleAttribute) as? String ?? ""
            if roles.contains(role), let f = frame(el, flipH), f.width >= 60, f.height >= 18,
               f.width < wf.width - 4 || role == "AXWebArea", wf.intersects(f), f.maxY < wf.maxY - 30 {
                let key = "\(role)|\(Int(f.minX / 8))|\(Int(f.width / 8))"
                items.append(Ledge(id: base + abs(key.hashValue % 900_000), frame: f.intersection(wf)))
            }
            if depth < 30, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                queue += kids.map { ($0, depth + 1) }
            }
        }
        return Ledges(window: wf, items: items)
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func frame(_ el: AXUIElement, _ flipH: CGFloat) -> CGRect? {
        guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(x: p.x, y: flipH - p.y - s.height, width: s.width, height: s.height)
    }
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    lo > hi ? lo : min(max(v, lo), hi)
}
