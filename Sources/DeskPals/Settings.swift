import AppKit
import ServiceManagement
import SwiftUI

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
    var onPet: ((PetKind) -> Void)?
    var onScale: ((CGFloat) -> Void)?
    var onCall: (() -> Void)?
    var onName: ((String) -> Void)?
    var onAccessory: ((Accessory) -> Void)?
    var onReactionsChanged: (() -> Void)?
    var onFeed: ((Food) -> Void)?
    var onBall: (() -> Void)?
    var onBed: (() -> Void)?
    var hasBed: () -> Bool = { false }
    var needs: Needs?

    @Published var petID: String {
        didSet {
            guard petID != oldValue else { return }
            d.set(petID, forKey: Keys.pet)
            petName = d.string(forKey: Keys.name(petID)) ?? kind.name
            accessory = Accessory(rawValue: d.string(forKey: Keys.accessory(petID)) ?? "") ?? .none
            onPet?(kind)
        }
    }
    @Published var petName: String {
        didSet { d.set(petName, forKey: Keys.name(petID)); onName?(displayName) }
    }
    @Published var accessory: Accessory {
        didSet { d.set(accessory.rawValue, forKey: Keys.accessory(petID)); onAccessory?(accessory) }
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
        let saved = ud.double(forKey: Keys.scale)
        let savedPet = ud.string(forKey: Keys.pet)
        let id = PetKind.all.first { $0.id == savedPet }?.id ?? PetKind.all[0].id
        petID = id
        petName = ud.string(forKey: Keys.name(id)) ?? (PetKind.all.first { $0.id == id }?.name ?? "")
        accessory = Accessory(rawValue: ud.string(forKey: Keys.accessory(id)) ?? "") ?? .none
        scale = saved > 0 ? saved : 4
        reacts = Dictionary(uniqueKeysWithValues: Self.reactions.map { ($0.key, Senses.on($0.key)) })
        bubbles = Senses.on(Keys.bubbles)
        sleepMinutes = Senses.sleepAfter / 60
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var kind: PetKind { PetKind.all.first { $0.id == petID } ?? PetKind.all[0] }
    var displayName: String {
        let n = petName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? kind.name : n
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
                PetTab(model: model).tabItem { Text("Pet") }
                BehaviorTab(model: model).tabItem { Text("Behavior") }
            }
            HStack {
                Button("Call \(model.displayName) here") { model.onCall?() }
                Spacer()
                Button("Quit DeskPals") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}

private struct PetTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(PetKind.all, id: \.id) { k in
                    PetCard(kind: k, selected: model.petID == k.id) { model.petID = k.id }
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let level = model.needs?.level ?? 0
                Form {
                    TextField("Name", text: $model.petName, prompt: Text(model.kind.name))
                    LabeledContent("Bond") {
                        HStack {
                            Text("Level \(level)").monospacedDigit().frame(width: 60, alignment: .leading)
                            ProgressView(value: model.needs?.levelProgress ?? 0)
                        }
                    }
                    Meter(title: "Full", value: model.needs?.fullness ?? 0, tint: .orange)
                    Meter(title: "Happy", value: model.needs?.happiness ?? 0, tint: .pink)
                    Meter(title: "Energy", value: model.needs?.energy ?? 0, tint: .green)
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
                                    .tint(model.accessory == a ? .accentColor : nil)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            Text("Pet it by clicking or rubbing your cursor on it. Feed it, play ball, and your bond grows and unlocks outfits.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
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

/// A pet to pick: walks in place while selected.
private struct PetCard: View {
    let kind: PetKind
    let selected: Bool
    let pick: () -> Void
    private let sheet: SpriteSheet

    init(kind: PetKind, selected: Bool, pick: @escaping () -> Void) {
        self.kind = kind
        self.selected = selected
        self.pick = pick
        self.sheet = SpriteSheet(kind: kind)
    }

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 0.18)) { tl in
                    let frame = Int(tl.date.timeIntervalSinceReferenceDate / 0.18) % 2
                    let pose: Pose = selected ? (frame == 0 ? .walkA : .walkB) : .stand
                    Image(decorative: sheet.image(pose, selected ? .open : .closed), scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 56, height: 56)
                }
                Text(kind.name).font(.system(.body, design: .rounded).weight(.bold))
                Text("the \(kind.species)").font(.caption).foregroundStyle(.secondary)
                Text(kind.trait).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
