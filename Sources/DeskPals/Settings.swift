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
    var onPlace: ((Place) -> Void)?
    var hasPlace: (Place) -> Bool = { _ in false }
    var onGame: ((MiniGames.Kind) -> Void)?
    var onPower: (() -> Void)?
    var onNoPlaces: (() -> Void)?
    var env: Environment?

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
    /// 0 calm ... 1 chaotic
    @Published var chaos: Double { didSet { d.set(chaos, forKey: "chaos"); Pet.chaos = chaos } }
    /// Bumped to make views re-read things that live elsewhere (coins, weather, shop).
    @Published var tick = 0
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
        chaos = ud.object(forKey: "chaos") as? Double ?? 0.4
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
                WorldTab(model: model).tabItem { Text("World") }
                ShopTab(model: model).tabItem { Text("Shop") }
                GoalsTab(model: model).tabItem { Text("Goals & games") }
                BehaviorTab(model: model).tabItem { Text("Behavior") }
                WatchPartyTab().tabItem { Text("Watch party") }
            }
            HStack {
                Button("Call \(model.displayName) here") { model.onCall?() }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("🪙 \(Economy.shared.coins)").font(.system(.body, design: .rounded).weight(.bold)).monospacedDigit()
                }
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
                            Text(["Baby", "Kid", "Grown-up"][min(needs?.stage ?? 2, 2)]).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                            ProgressView(value: needs?.levelProgress ?? 0)
                        }
                    }
                    if let list = model.kind.progression, !list.isEmpty {
                        let step = UserDefaults.standard.integer(forKey: "progress.\(model.selectedUID)")
                        LabeledContent("Discoveries") {
                            HStack {
                                ProgressView(value: Double(min(step, list.count)), total: Double(list.count))
                                Text(step < list.count ? "\(step)/\(list.count) · next: \(list[step])" : "off to the moon!")
                                    .monospacedDigit().frame(width: 220, alignment: .leading)
                            }
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
                            Button("Power up ⚡") { model.onPower?() }
                        }
                    }
                    LabeledContent("Wears") {
                        HStack(spacing: 6) {
                            ForEach(Accessory.allCases.filter { a in a.shopID.map { Economy.shared.owned.contains($0) } ?? true }, id: \.self) { a in
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

/// Live AI reactions to whatever the pets are watching (see WatchParty).
private struct WatchPartyTab: View {
    @State private var on = WatchParty.shared.enabled
    @State private var modelName = WatchParty.shared.model
    @State private var interval = WatchParty.shared.interval

    var body: some View {
        Form {
            Toggle("Pets react live to what you watch", isOn: $on)
                .onChange(of: on) { WatchParty.shared.enabled = $0 }
            TextField("Model", text: $modelName, prompt: Text("qwen3.5:4b"))
                .onSubmit { WatchParty.shared.model = modelName }
            LabeledContent("React every") {
                HStack {
                    Slider(value: $interval, in: 5...30, step: 1)
                        .onChange(of: interval) { WatchParty.shared.interval = $0 }
                    Text("\(Int(interval)) s").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                LabeledContent("Status") {
                    HStack {
                        Text(on ? WatchParty.shared.status : "Off").foregroundStyle(.secondary)
                        if on, !WatchParty.shared.hasScreenAccess {
                            Button("Allow screen recording…") { WatchParty.shared.requestScreenAccess() }
                        }
                        Button("Check again") { WatchParty.shared.model = modelName }
                    }
                }
            }
            Text("""
            While your pets watch a video, a small AI model on your Mac (through Ollama) looks at a snapshot of \
            just that video window every few seconds and writes what each pet says. They turn around, react, and \
            answer each other. Nothing leaves your Mac and nothing is saved. Any Ollama model that can see images works.
            """)
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .onAppear { WatchParty.shared.checkOllama() }
        .onDisappear { if modelName != WatchParty.shared.model, !modelName.isEmpty { WatchParty.shared.model = modelName } }
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

            LabeledContent("Personality") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Calm").font(.caption)
                        Slider(value: $model.chaos, in: 0...1)
                        Text("Chaotic").font(.caption)
                    }
                    Text(model.chaos > 0.85 ? "Full chaos: they push each other, knock things over and tug your cursor."
                         : model.chaos > 0.6 ? "Mischief: they push each other off ledges and knock things over."
                         : model.chaos < 0.25 ? "Calm: they mostly rest and stay quiet." : "Balanced.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            SoundControls()
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

private struct SoundControls: View {
    @State private var effects = Sound.shared.effectsOn
    @State private var volume = Double(Sound.shared.volume)

    var body: some View {
        LabeledContent("Sound") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Sound effects", isOn: $effects).onChange(of: effects) { Sound.shared.effectsOn = $0 }
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1).onChange(of: volume) { Sound.shared.volume = Float($0) }
                }
            }
        }
    }
}

private struct WorldTab: View {
    @ObservedObject var model: SettingsModel
    @State private var city = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Form {
                if let env = model.env {
                    LabeledContent("World") {
                        HStack(spacing: 6) {
                            ForEach(Theme.allCases, id: \.self) { th in
                                let owned = th.shopID.map { Economy.shared.owned.contains($0) } ?? true
                                Button(owned ? th.title : "🔒 \(th.title)") {
                                    if th == .none { env.clearWorld() } else { env.theme = th }
                                    model.tick += 1
                                }
                                    .disabled(!owned)
                                    .buttonStyle(.bordered)
                                    .tint(env.theme == th ? Color.accentColor : nil)
                            }
                        }
                        .controlSize(.small)
                    }
                    Picker("Weather", selection: Binding(get: { env.mode }, set: { env.mode = $0; model.tick += 1 })) {
                        ForEach(Environment.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if env.mode == .real {
                        LabeledContent("City") {
                            HStack {
                                TextField("e.g. Austin", text: $city).onSubmit { env.city = city }
                                Button("Use") { env.city = city }
                            }
                        }
                        Text("Only the city name goes to open-meteo.com to look up the weather.").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Right now", selection: Binding(get: { env.override?.rawValue ?? "auto" },
                                                           set: { env.override = WeatherKind(rawValue: $0); model.tick += 1 })) {
                        Text("Automatic").tag("auto")
                        ForEach(WeatherKind.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Holiday decorations", isOn: Binding(get: { env.holidaysOn }, set: { env.holidaysOn = $0; model.tick += 1 }))
                    LabeledContent("Now") { Text(env.summary + (env.holiday != .none ? " · holiday decorations on" : "")).foregroundStyle(.secondary) }
                }
                LabeledContent("Places") {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("None (put them all away)") { model.onNoPlaces?(); model.tick += 1 }
                        ForEach(Place.allCases, id: \.self) { p in
                            HStack {
                                Image(decorative: p.image(), scale: 1).interpolation(.none).resizable().scaledToFit().frame(width: 36, height: 28)
                                Text(p.title).frame(width: 80, alignment: .leading)
                                if Economy.shared.owned.contains(p.shopID) {
                                    Button(model.hasPlace(p) ? "Put away" : "Place on desktop") { model.onPlace?(p); model.tick += 1 }
                                } else {
                                    Text("in the Shop").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("Pets visit places on their own. Drag places anywhere, even onto windows. Your pets also explore the menu bar, hide in the notch and peek out from the screen edges.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .onAppear { city = model.env?.city ?? "" }
        }
    }
}

private struct ShopTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("🪙 \(Economy.shared.coins) coins").font(.title2.weight(.bold)).monospacedDigit()
                    Text("Earn coins by petting, feeding and playing, daily quests, mini-games and achievements.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ShopItem.Category.allCases, id: \.self) { cat in
                        Text(cat.rawValue).font(.headline)
                        ForEach(ShopItem.all.filter { $0.category == cat }) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title).fontWeight(.semibold)
                                    Text(item.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if Economy.shared.owns(item) {
                                    Text("Owned ✓").foregroundStyle(.green)
                                } else {
                                    Button("Buy  🪙 \(item.price)") {
                                        if Economy.shared.buy(item) { Sound.shared.play(.coin); model.tick += 1 }
                                    }
                                    .disabled(Economy.shared.coins < item.price)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: 460)
        }
    }
}

private struct GoalsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today's quests").font(.headline)
                    ForEach(Array(Economy.shared.quests.enumerated()), id: \.offset) { _, q in
                        HStack {
                            Image(systemName: q.done ? "checkmark.circle.fill" : "circle").foregroundStyle(q.done ? .green : .secondary)
                            Text(q.title)
                            Spacer()
                            ProgressView(value: Double(min(q.progress, q.target)), total: Double(q.target)).frame(width: 90)
                            Text("🪙 \(q.reward)").monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                    }
                    Text("Mini-games").font(.headline).padding(.top, 6)
                    ForEach(MiniGames.Kind.allCases, id: \.self) { g in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.title).fontWeight(.semibold)
                                Text(g.how).font(.caption).foregroundStyle(.secondary)
                                if MiniGames.best(g) > 0 { Text("Best: \(MiniGames.best(g))").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Play with \(model.displayName)") { model.onGame?(g) }
                        }
                    }
                    Text("Achievements").font(.headline).padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                        ForEach(Economy.achievements, id: \.id) { a in
                            let done = Economy.shared.achieved.contains(a.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((done ? "🏆 " : "🔒 ") + a.title).fontWeight(.semibold)
                                Text(a.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(done ? Color.yellow.opacity(0.15) : Color.primary.opacity(0.04)))
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: 460)
        }
    }
}
