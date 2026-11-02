import AppKit
import CoreAudio
import Darwin
import IOKit.ps
import IOKit.pwr_mgt

enum Keys {
    static let pet = "pet", scale = "scale"
    static let windows = "react.windows", clicks = "react.clicks", typing = "react.typing", idle = "react.idle"
    static let video = "react.video", music = "react.music", battery = "react.battery", dock = "react.dock"
    static let ledges = "react.ledges"
    static let bubbles = "bubbles", sleepAfter = "sleepAfter", launchedBefore = "launchedBefore"
    static func name(_ id: String) -> String { "name.\(id)" }
    static func accessory(_ id: String) -> String { "accessory.\(id)" }
}

/// Watches the desktop and tells the pet what happened. Nothing here records what you do:
/// clicks only give a position, typing is measured as "a key was pressed recently" (never which key),
/// idle time comes from the system's seconds-since-last-input counter, videos are noticed because an
/// app is keeping the screen awake, and music because the speakers are in use.
final class Senses {
    private let pet: Pet
    private let world: World
    private let me = ProcessInfo.processInfo.processIdentifier
    private let d = UserDefaults.standard
    private var clock = 0.0
    private var sampleClock = 0.0, slowClock = 0.0
    private var slowTicks = 0
    private var typingHistory: [Bool] = []
    private var typingRun = 0.0
    private var lastBurst = -100.0
    private var lastWindowReact = -100.0
    private var lastAppReact = -100.0
    private var appCooldown: [String: Double] = [:]
    private var lastYawn = 0.0
    private var lastNag = -10000.0
    private var lastBored = 0.0
    private var lastBatteryNag = -10000.0
    private var sleptAt: Date?
    private var videoSeen = 0.0, videoGone = 0.0
    private var battery: (percent: Int, charging: Bool)?
    private var monitors: [Any] = []
    private var readingLedges = false

    static let videoHelpers = ["helper", "webkit", "gpu", "renderer", "plugin", "video"]

    init(pet: Pet, world: World) {
        self.pet = pet
        self.world = world
    }

    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Seconds of no input before a nap (daytime; nights are shorter).
    static var sleepAfter: Double {
        let s = UserDefaults.standard.double(forKey: Keys.sleepAfter)
        return s > 0 ? s : 120
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.activated(app) }
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, Senses.on(Keys.windows),
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != self.me, app.activationPolicy == .regular else { return }
            self.pet.appLaunched(name: app.localizedName ?? "")
        }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pet.spaceChanged()
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.pet.isAsleep { self.pet.wake("hi again!") } else { self.pet.remark("hi again!", hop: true) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            guard Senses.on(Keys.clicks) else { return }
            self?.pet.noticeClick(NSEvent.mouseLocation)
        }) { monitors.append(m) }
        refreshDock()
        battery = Self.batteryState()
    }

    private func activated(_ app: NSRunningApplication) {
        guard app.processIdentifier != me else { return }
        pet.appSwitched(to: app.processIdentifier)
        guard Senses.on(Keys.windows), let id = app.bundleIdentifier else { return }
        let name = app.localizedName ?? "that"

        // Remember which apps you use most, and tease you about it now and then.
        var counts = d.dictionary(forKey: "appCounts") as? [String: Int] ?? [:]
        counts[id, default: 0] += 1
        d.set(counts, forKey: "appCounts")
        if let top = counts.max(by: { $0.value < $1.value }), top.key == id, top.value > 30, Double.random(in: 0..<1) < 0.08 {
            pet.remark("\(name) again?")
            return
        }

        guard clock - lastAppReact > 20, clock - (appCooldown[id] ?? -1e9) > 600 else { return }
        lastAppReact = clock
        appCooldown[id] = clock
        pet.reactToApp(id, name: name)
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
        slowClock += dt
        if sampleClock >= 0.25 {
            sampleClock = 0
            let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            typing(keyIdle < 0.5)
            idleAndTime(Self.secondsIdle())
        }
        if slowClock >= 1 {
            slowClock = 0
            slowTicks += 1
            pet.musicPlaying = Senses.on(Keys.music) && videoSeen == 0 && Self.audioPlaying()
            if slowTicks % 2 == 0 { checkVideo() }
            if slowTicks % 3 == 0 { refreshDock() }
            refreshLedges()
            if slowTicks % 10 == 0 { habits() }
            if slowTicks % 30 == 0 { checkBattery() }
        }
    }

    static func secondsIdle() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown,
                                    .scrollWheel, .leftMouseDragged, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // MARK: - Typing and idle

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
        let tired = pet.needs.energy < 0.2 ? 0.5 : 1
        let limit = Self.sleepAfter * (night ? 0.4 : 1) * tired / pet.kind.sleepiness
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
        } else if idle > limit, videoSeen == 0 {
            if pet.fallAsleep() { sleptAt = Date() }
        } else if night, idle < 5, clock - lastYawn > 300 {
            lastYawn = clock
            pet.yawn()
        }
    }

    // MARK: - Videos and music

    private func checkVideo() {
        guard Senses.on(Keys.video) else {
            videoSeen = 0
            if pet.isWatching { pet.stopWatching(nil) }
            return
        }
        if let win = videoWindow() {
            videoGone = 0
            videoSeen += 2
            if !pet.isWatching, videoSeen >= 2 { _ = pet.startWatching(win) }
        } else {
            videoSeen = 0
            guard pet.isWatching else { return }
            videoGone += 2
            if videoGone >= 4 {
                videoGone = 0
                pet.stopWatching(["that was good!", "the end!", "again?", "*claps*"].randomElement())
            }
        }
    }

    /// The window of an app that's keeping the display awake (which is what video players do).
    private func videoWindow() -> WindowInfo? {
        for pid in Self.displayAssertionPIDs() where pid != me {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                if let w = world.largestWindow(of: pid) { return w }
            } else if Self.videoHelpers.contains(where: Self.processName(pid).lowercased().contains),
                      let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me,
                      let w = world.largestWindow(of: front.processIdentifier) {
                return w   // a browser's helper process is playing it
            }
        }
        return nil
    }

    static func displayAssertionPIDs() -> [pid_t] {
        var ref: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess, let dict = ref?.takeRetainedValue() as NSDictionary? else { return [] }
        var out: [pid_t] = []
        for (key, value) in dict {
            guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [NSDictionary] else { continue }
            if list.contains(where: {
                let type = $0["AssertType"] as? String ?? ""
                return type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion"
            }) { out.append(pid) }
        }
        return out
    }

    static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buf, UInt32(buf.count))
        return String(cString: buf)
    }

    /// True while anything is playing through the default speakers or headphones.
    static func audioPlaying() -> Bool {
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: - Dock, battery, habits

    func refreshDock() {
        world.dock = Senses.on(Keys.dock) ? DockReader.read() : nil
    }

    /// Text boxes, buttons and toolbars in the app you're using, as extra ledges.
    func refreshLedges() {
        guard Senses.on(Keys.ledges), DockReader.trusted,
              let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me,
              let flipH = NSScreen.screens.first?.frame.height else {
            world.ledges = nil
            return
        }
        guard !readingLedges else { return }
        readingLedges = true
        let pid = front.processIdentifier
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ledges = Ledges.read(pid: pid, flipH: flipH)
            DispatchQueue.main.async {
                self?.world.ledges = ledges
                self?.readingLedges = false
            }
        }
    }

    static func batteryState() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (cap * 100 / max, (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }

    private func checkBattery() {
        guard Senses.on(Keys.battery), let now = Self.batteryState() else { return }
        defer { battery = now }
        guard let before = battery else { return }
        if now.charging, !before.charging {
            pet.pluggedIn()
        } else if now.charging, now.percent >= 100, before.percent < 100 {
            pet.remark("100%!", hop: true)
        } else if !now.charging, now.percent <= 15, clock - lastBatteryNag > 900 {
            lastBatteryNag = clock
            pet.batteryLow()
        }
    }

    private func habits() {
        let idle = Self.secondsIdle()
        guard idle < 30 else { return }
        let now = Date()
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: now)

        // A greeting for each new day together.
        let lastDay = d.string(forKey: "lastDay")
        if lastDay != today {
            let days = d.integer(forKey: "daysTogether") + 1
            d.set(days, forKey: "daysTogether")
            d.set(today, forKey: "lastDay")
            pet.remark(days == 1 ? "nice to meet you!" : "day \(days) together!", hop: true)
            return
        }

        let hour = cal.component(.hour, from: now)
        if (1..<5).contains(hour), clock - lastNag > 1800 {
            lastNag = clock
            pet.remark(["go to sleep!", "it's so late…", "bedtime?"].randomElement()!)
            return
        }
        if pet.t - pet.lastInteraction > 1500, clock - lastBored > 1200 {
            lastBored = clock
            pet.bored()
        }
    }
}
