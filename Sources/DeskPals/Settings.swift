import AppKit
import ServiceManagement
import SwiftUI

/// One pet on screen. `uid` keys its name, outfit and needs; the first of each kind uses the kind's id.
struct PetSlotInfo: Identifiable, Equatable {
    let uid: String
    let kindID: String
    var id: String { uid }
}

/// Every user setting lives here and in UserDefaults. The menu bar and the Settings window
/// both change these properties, and the app is told through the callbacks.
final class SettingsModel: ObservableObject {
    static let sizes: [(name: String, scale: Double)] = [("Small", 3), ("Medium", 4), ("Large", 6), ("Huge", 8)]
    static let reactions: [(name: String, key: String)] = [
        ("New windows & apps", Keys.windows), ("Mouse clicks", Keys.clicks), ("Typing", Keys.typing),
        ("Idle & time of day", Keys.idle), ("Videos (watches with you)", Keys.video), ("Music (dances)", Keys.music),
        ("Battery", Keys.battery), ("Walk on Dock icons", Keys.dock), ("Stand on text boxes & buttons", Keys.ledges),
    ]

    private let d = UserDefaults.standard
    var onAdd: ((PetSlotInfo) -> Void)?
    var onRemove: ((String) -> Void)?
    var onSelect: (() -> Void)?
    var onScale: ((CGFloat) -> Void)?
    var onCall: (() -> Void)?
    var onName: ((String, String) -> Void)?
    var onAccessory: ((String, Accessory) -> Void)?
    var onReactionsChanged: (() -> Void)?
    var onFeed: ((Food) -> Void)?
    var onBall: (() -> Void)?
    var onBed: (() -> Void)?
    var hasBed: () -> Bool = { false }
    var needsFor: (String) -> Needs? = { _ in nil }

    @Published private(set) var slots: [PetSlotInfo] {
        didSet { d.set(slots.map { ["uid": $0.uid, "kind": $0.kindID] }, forKey: Keys.pets) }
    }
    /// The pet the Settings window and the care buttons are about.
    @Published var selectedUID: String {
        didSet {
            guard selectedUID != oldValue, let slot = selected else { return }
            petName = d.string(forKey: Keys.name(slot.uid)) ?? ""
            accessory = Self.accessory(of: slot)
            onSelect?()
        }
    }
    @Published var petName: String {
        didSet { d.set(petName, forKey: Keys.name(selectedUID)); onName?(selectedUID, displayName) }
    }
    @Published var accessory: Accessory {
        didSet { d.set(accessory.rawValue, forKey: Keys.accessory(selectedUID)); onAccessory?(selectedUID, accessory) }
    }
    @Published var scale: Double { didSet { d.set(scale, forKey: Keys.scale); onScale?(CGFloat(scale)) } }
    @Published var reacts: [String: Bool] {
        didSet { reacts.forEach { d.set($0.value, forKey: $0.key) }; onReactionsChanged?() }
    }
    @Published var bubbles: Bool { didSet { d.set(bubbles, forKey: Keys.bubbles) } }
    @Published var sleepMinutes: Double { didSet { d.set(sleepMinutes * 60, forKey: Keys.sleepAfter) } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("DeskPals: launch at login failed: \(error)")
            }
        }
    }

    init() {
        let ud = UserDefaults.standard
        var list: [PetSlotInfo] = []
        if let saved = ud.array(forKey: Keys.pets) as? [[String: String]] {
            list = saved.compactMap { e in
                guard let u = e["uid"], let k = e["kind"], PetKind.all.contains(where: { $0.id == k }) else { return nil }
                return PetSlotInfo(uid: u, kindID: k)
            }
        } else if let old = ud.string(forKey: Keys.pet), PetKind.all.contains(where: { $0.id == old }) {
            list = [PetSlotInfo(uid: old, kindID: old)]   // from before you could have several
        }
        if list.isEmpty { list = [PetSlotInfo(uid: PetKind.all[0].id, kindID: PetKind.all[0].id)] }
        slots = list
        selectedUID = list[0].uid
        petName = ud.string(forKey: Keys.name(list[0].uid)) ?? ""
        accessory = Self.accessory(of: list[0])
        let saved = ud.double(forKey: Keys.scale)
        scale = saved > 0 ? saved : 4
        reacts = Dictionary(uniqueKeysWithValues: Self.reactions.map { ($0.key, Senses.on($0.key)) })
        bubbles = Senses.on(Keys.bubbles)
        sleepMinutes = Senses.sleepAfter / 60
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var selected: PetSlotInfo? { slots.first { $0.uid == selectedUID } }
    var kind: PetKind { selected.map(Self.kind(of:)) ?? PetKind.all[0] }
    var displayName: String { selected.map(Self.name(of:)) ?? kind.name }

    static func kind(of slot: PetSlotInfo) -> PetKind { PetKind.all.first { $0.id == slot.kindID } ?? PetKind.all[0] }

    static func name(of slot: PetSlotInfo) -> String {
        let n = (UserDefaults.standard.string(forKey: Keys.name(slot.uid)) ?? "").trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        let k = kind(of: slot)
        return slot.uid == k.id ? k.name : "\(k.name) \(slot.uid.split(separator: "-").last ?? "")"
    }

    static func accessory(of slot: PetSlotInfo) -> Accessory {
        Accessory(rawValue: UserDefaults.standard.string(forKey: Keys.accessory(slot.uid)) ?? "") ?? .none
    }

    func count(of kind: PetKind) -> Int { slots.filter { $0.kindID == kind.id }.count }

    /// Adds another pet; several of the same kind are fine.
    func add(_ kind: PetKind) {
        let used = Set(slots.map(\.uid))
        var uid = kind.id, n = 2
        while used.contains(uid) { uid = "\(kind.id)-\(n)"; n += 1 }
        let slot = PetSlotInfo(uid: uid, kindID: kind.id)
        slots.append(slot)
        onAdd?(slot)
        selectedUID = uid
    }

    func remove(_ uid: String) {
        guard slots.count > 1 else { return }
        slots.removeAll { $0.uid == uid }
        onRemove?(uid)
        if selectedUID == uid { selectedUID = slots[0].uid }
    }

    func reacts(_ key: String) -> Binding<Bool> {
        Binding(get: { self.reacts[key] ?? true }, set: { self.reacts[key] = $0 })
    }
}

final class SettingsWindow: NSWindow {
    init(model: SettingsModel) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        title = "DeskPals"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: SettingsView(model: model))
        center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabView {
                PetTab(model: model).tabItem { Text("Pets") }
                BehaviorTab(model: model).tabItem { Text("Behavior") }
            }
            HStack {
                Button("Call \(model.displayName) here") { model.onCall?() }
                Spacer()
                Button("Quit DeskPals") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

private struct PetTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your pets").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.slots) { slot in
                        SlotChip(slot: slot, selected: slot.uid == model.selectedUID, canRemove: model.slots.count > 1,
                                 select: { model.selectedUID = slot.uid }, remove: { model.remove(slot.uid) })
                    }
                }
                .padding(.vertical, 2)
            }

            Text("Add a pet (as many as you like)").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                ForEach(PetKind.all, id: \.id) { k in
                    PetCard(kind: k, count: model.count(of: k)) { model.add(k) }
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let needs = model.needsFor(model.selectedUID)
                let level = needs?.level ?? 0
                Form {
                    TextField("Name", text: $model.petName, prompt: Text(model.displayName))
                    LabeledContent("Bond") {
                        HStack {
                            Text("Level \(level)").monospacedDigit().frame(width: 60, alignment: .leading)
                            ProgressView(value: needs?.levelProgress ?? 0)
                        }
                    }
                    Meter(title: "Full", value: needs?.fullness ?? 0, tint: .orange)
                    Meter(title: "Happy", value: needs?.happiness ?? 0, tint: .pink)
                    Meter(title: "Energy", value: needs?.energy ?? 0, tint: .green)
                    LabeledContent("Care") {
                        HStack {
                            Menu("Feed") {
                                ForEach(Food.allCases, id: \.self) { f in
                                    Button(f == model.kind.favorite ? "\(f.title) ★ favorite" : f.title) { model.onFeed?(f) }
                                }
                            }
                            .fixedSize()
                            Button("Throw a ball") { model.onBall?() }
                            Button(model.hasBed() ? "Remove bed" : "Place a bed") { model.onBed?() }
                        }
                    }
                    LabeledContent("Wears") {
                        HStack(spacing: 6) {
                            ForEach(Accessory.allCases, id: \.self) { a in
                                let locked = a.level > level
                                Button(locked ? "🔒 Lv \(a.level)" : a.title) { model.accessory = a }
                                    .disabled(locked)
                                    .buttonStyle(.bordered)
                                    .tint(model.accessory == a ? Color.accentColor : nil)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            Text("Pet them by clicking or rubbing your cursor on them. Feed them, play ball, and your bond grows and unlocks outfits.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

/// One of your pets: click to edit it, × to send it away.
private struct SlotChip: View {
    let slot: PetSlotInfo
    let selected: Bool
    let canRemove: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(decorative: SpriteSheet(kind: SettingsModel.kind(of: slot)).image(.stand, .open), scale: 1)
                .interpolation(.none).resizable().frame(width: 28, height: 28)
            Text(SettingsModel.name(of: slot)).font(.system(.callout, design: .rounded).weight(.semibold))
            if canRemove {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove from screen")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Capsule())
        .onTapGesture(perform: select)
    }
}

private struct Meter: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        LabeledContent(title) {
            HStack {
                ProgressView(value: value).tint(tint)
                Text("\(Int(value * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
    }
}

private struct BehaviorTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker("Size", selection: $model.scale) {
                ForEach(SettingsModel.sizes, id: \.scale) { Text($0.name).tag($0.scale) }
            }
            .pickerStyle(.segmented)

            LabeledContent("Reacts to") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(SettingsModel.reactions, id: \.key) { r in
                        Toggle(r.name, isOn: model.reacts(r.key))
                    }
                }
            }

            if (model.reacts[Keys.dock] ?? true) || (model.reacts[Keys.ledges] ?? true) {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent("Access") {
                        if DockReader.trusted {
                            Text("✓ \(model.displayName) can see your Dock and things to stand on").foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button("Allow access…") { DockReader.requestAccess() }
                                Text("Accessibility, only to find where Dock icons and buttons are").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            LabeledContent("Naps after") {
                HStack {
                    Slider(value: $model.sleepMinutes, in: 1...15, step: 1)
                    Text("\(Int(model.sleepMinutes)) min idle").monospacedDigit().frame(width: 84, alignment: .trailing)
                }
            }
            .disabled(model.reacts[Keys.idle] == false)

            Toggle("Show speech bubbles", isOn: $model.bubbles)
            Toggle("Open DeskPals when I log in", isOn: $model.launchAtLogin)
        }
        .padding(12)
    }
}

/// A kind of pet to add: walks in place while you have at least one.
private struct PetCard: View {
    let kind: PetKind
    let count: Int
    let add: () -> Void
    private let sheet: SpriteSheet

    init(kind: PetKind, count: Int, add: @escaping () -> Void) {
        self.kind = kind
        self.count = count
        self.add = add
        self.sheet = SpriteSheet(kind: kind)
    }

    var body: some View {
        Button(action: add) {
            VStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 0.18)) { tl in
                    let frame = Int(tl.date.timeIntervalSinceReferenceDate / 0.18) % 2
                    let pose: Pose = count > 0 ? (frame == 0 ? .walkA : .walkB) : .stand
                    Image(decorative: sheet.image(pose, .open), scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                Text(kind.name).font(.system(.caption, design: .rounded).weight(.bold))
                Text(kind.species).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(alignment: .topTrailing) {
                Text(count > 0 ? "×\(count)" : "+")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(count > 0 ? Color.accentColor : Color.secondary.opacity(0.3)))
                    .foregroundStyle(.white)
                    .padding(4)
            }
            .help(kind.trait)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
