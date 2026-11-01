import AppKit
import ServiceManagement
import SwiftUI

/// Every user setting lives here and in UserDefaults. The menu bar and the Settings window
/// both change these properties, and the pet is told through the callbacks.
final class SettingsModel: ObservableObject {
    static let sizes: [(name: String, scale: Double)] = [("Small", 3), ("Medium", 4), ("Large", 6), ("Huge", 8)]
    static let reactions: [(name: String, key: String)] = [("New windows & apps", Keys.windows), ("Mouse clicks", Keys.clicks),
                                                           ("Typing", Keys.typing), ("Idle & time of day", Keys.idle)]

    private let d = UserDefaults.standard
    var onPet: ((PetKind) -> Void)?
    var onScale: ((CGFloat) -> Void)?
    var onCall: (() -> Void)?

    @Published var petID: String { didSet { d.set(petID, forKey: Keys.pet); if petID != oldValue { onPet?(kind) } } }
    @Published var scale: Double { didSet { d.set(scale, forKey: Keys.scale); onScale?(CGFloat(scale)) } }
    @Published var reacts: [String: Bool] { didSet { reacts.forEach { d.set($0.value, forKey: $0.key) } } }
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
        let saved = UserDefaults.standard.double(forKey: Keys.scale)
        let savedPet = UserDefaults.standard.string(forKey: Keys.pet)
        petID = PetKind.all.first { $0.id == savedPet }?.id ?? PetKind.all[0].id
        scale = saved > 0 ? saved : 4
        reacts = Dictionary(uniqueKeysWithValues: Self.reactions.map { ($0.key, Senses.on($0.key)) })
        bubbles = Senses.on(Keys.bubbles)
        sleepMinutes = Senses.sleepAfter / 60
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var kind: PetKind { PetKind.all.first { $0.id == petID } ?? PetKind.all[0] }

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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your pet").font(.headline)
                HStack(spacing: 10) {
                    ForEach(PetKind.all, id: \.id) { k in
                        PetCard(kind: k, selected: model.petID == k.id) { model.petID = k.id }
                    }
                }
            }

            Form {
                Picker("Size", selection: $model.scale) {
                    ForEach(SettingsModel.sizes, id: \.scale) { Text($0.name).tag($0.scale) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Reacts to") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(SettingsModel.reactions, id: \.key) { r in
                            Toggle(r.name, isOn: model.reacts(r.key))
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

            HStack {
                Button("Call \(model.kind.name) here") { model.onCall?() }
                Spacer()
                Button("Quit DeskPals") { NSApp.terminate(nil) }
            }
        }
        .padding(22)
        .frame(width: 560)
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
                        .frame(width: 64, height: 64)
                }
                Text(kind.name).font(.system(.body, design: .rounded).weight(.bold))
                Text("the \(kind.species)").font(.caption).foregroundStyle(.secondary)
                Text(kind.trait).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
