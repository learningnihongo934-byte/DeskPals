import AppKit

enum Keys {
    static let pet = "pet", scale = "scale"
    static let windows = "react.windows", clicks = "react.clicks", typing = "react.typing", idle = "react.idle"
}

/// Watches the desktop and tells the pet what happened. Nothing here records what you do:
/// clicks only give a position, typing is measured as "a key was pressed recently" (never which key),
/// and idle time comes from the system's seconds-since-last-input counter.
final class Senses {
    private let pet: Pet
    private var clock = 0.0
    private var sampleClock = 0.0
    private var typingHistory: [Bool] = []
    private var typingRun = 0.0
    private var lastBurst = -100.0
    private var lastWindowReact = -100.0
    private var lastYawn = 0.0
    private var sleptAt: Date?
    private var monitors: [Any] = []

    init(pet: Pet) { self.pet = pet }

    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            self?.app(n, launched: false)
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            self?.app(n, launched: true)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            guard Senses.on(Keys.clicks) else { return }
            self?.pet.noticeClick(NSEvent.mouseLocation)
        }) { monitors.append(m) }
    }

    private func app(_ n: Notification, launched: Bool) {
        guard Senses.on(Keys.windows),
              let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        pet.noticeApp(app.bundleIdentifier ?? "", launched: launched)
    }

    /// Several windows at once means a Space switch, not something worth a look.
    func newWindows(_ ids: [Int]) {
        guard Senses.on(Keys.windows), !ids.isEmpty, ids.count <= 2, clock - lastWindowReact > 4 else { return }
        lastWindowReact = clock
        pet.noticeWindow(ids[0])
    }

    func tick(_ dt: Double) {
        clock += dt
        sampleClock += dt
        guard sampleClock >= 0.25 else { return }
        sampleClock = 0
        let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        typing(keyIdle < 0.5)
        idleAndTime(Self.secondsIdle())
    }

    static func secondsIdle() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown,
                                    .scrollWheel, .leftMouseDragged, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func typing(_ active: Bool) {
        typingHistory.append(active)
        if typingHistory.count > 24 { typingHistory.removeFirst() }   // last 6 seconds
        guard Senses.on(Keys.typing) else { pet.speedBoost = 1; return }
        let level = Double(typingHistory.filter { $0 }.count) / 24
        pet.speedBoost = 1 + CGFloat(level) * 0.8
        if level > 0.45 {
            typingRun += 0.25
            if typingRun > 8, clock - lastBurst > 15 {
                lastBurst = clock
                pet.typingBurst()
            }
        } else if level == 0 {
            if typingRun > 25 { pet.typingStopped() }
            typingRun = 0
        }
    }

    private func idleAndTime(_ idle: Double) {
        guard Senses.on(Keys.idle) else {
            if pet.isAsleep { pet.wake("!") }
            return
        }
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 5
        let limit = (night ? 45 : 120) / pet.kind.sleepiness
        if pet.isAsleep {
            guard idle < 1 else { return }
            let away = sleptAt.map { Date().timeIntervalSince($0) + limit } ?? 0
            if away > 1200 && (5..<12).contains(hour) {
                pet.wake("morning!")
            } else if away > 1200 {
                pet.wake("welcome back!")
            } else {
                pet.wake(pet.kind.sound)
            }
            sleptAt = nil
        } else if idle > limit {
            if pet.fallAsleep() { sleptAt = Date() }
        } else if night, idle < 5, clock - lastYawn > 300 {
            lastYawn = clock
            pet.yawn()
        }
    }
}
