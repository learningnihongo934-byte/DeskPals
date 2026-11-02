import AppKit
import ScreenCaptureKit

/// Watch party: while pets watch a video, a small local vision model (through Ollama) looks at
/// a snapshot of just that video window every few seconds and writes an in-character reaction
/// for each pet. Snapshots go only to Ollama on this Mac and are never saved.
final class WatchParty {
    static let shared = WatchParty()

    private let d = UserDefaults.standard
    var enabled: Bool {
        get { d.bool(forKey: "party.on") }
        set { d.set(newValue, forKey: "party.on"); if newValue { checkOllama() } }
    }
    var model: String {
        get { d.string(forKey: "party.model") ?? "qwen3.5:4b" }
        set { d.set(newValue, forKey: "party.model"); checkOllama() }
    }
    var interval: Double {
        get { d.object(forKey: "party.interval") as? Double ?? 10 }
        set { d.set(newValue, forKey: "party.interval") }
    }
    private(set) var status = "Off"
    var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }

    private var busy = false
    private var nextAt = 0.0
    private var history: [String] = []
    private let endpoint = URL(string: "http://localhost:11434")!

    func requestScreenAccess() { _ = CGRequestScreenCaptureAccess() }

    /// Is Ollama running, and does it have the model?
    func checkOllama() {
        let model = self.model
        var req = URLRequest(url: endpoint.appendingPathComponent("api/tags"))
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            let names = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["models"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String } ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil || data == nil {
                    self.status = "Ollama isn't running: open Ollama or run `ollama serve`"
                } else if !names.contains(where: { $0 == model || $0 == model + ":latest" }) {
                    self.status = "Model not found: run `ollama pull \(model)`"
                } else {
                    self.status = self.hasScreenAccess ? "Ready" : "Needs Screen Recording permission"
                }
            }
        }.resume()
    }

    /// Called every frame; does something every `interval` seconds while pets watch a video.
    func tick(pets: [Pet], video: WindowInfo?, clock: Double) {
        let watchers = pets.filter(\.isWatching)
        guard enabled, !busy, clock >= nextAt, let video, !watchers.isEmpty else {
            if video == nil, !history.isEmpty, !busy { history = [] }   // new video, fresh conversation
            return
        }
        nextAt = clock + interval
        guard hasScreenAccess else { status = "Needs Screen Recording permission"; return }
        guard #available(macOS 14.0, *) else { status = "Needs macOS 14 or later"; return }
        busy = true
        let cast = watchers.map { Cast(pet: $0) }
        let said = history
        let model = self.model
        Task { [weak self] in
            guard let self else { return }
            let shot = await Self.snapshot(windowID: video.id)
            let jpeg = shot?.jpeg
            let prompt = Self.makePrompt(cast, title: shot?.title, said: said)
            let reply = jpeg == nil ? nil : await self.ask(model: model, prompt: prompt, jpeg: jpeg!)
            DispatchQueue.main.async {
                self.busy = false
                guard let reply else {
                    if jpeg == nil { self.status = "Couldn't see the video window" }
                    return
                }
                self.status = "Ready"
                self.apply(reply, to: watchers)
            }
        }
    }

    // MARK: - Prompt and reply

    private struct Cast {
        let id: String, name: String, species: String, trait: String, samples: [String]
        let rival: String?, bestie: String?, series: String?
        init(pet: Pet) {
            id = pet.kind.id
            name = pet.name
            species = pet.kind.species
            trait = pet.kind.trait
            samples = Array(pet.kind.lines.shuffled().prefix(6))
            rival = pet.kind.rival
            bestie = pet.kind.bestie
            series = pet.kind.series
        }
    }

    private static func makePrompt(_ cast: [Cast], title: String?, said history: [String]) -> String {
        var p = "You voice a watch party of tiny pixel desktop pets watching a video together with their human.\nCharacters:\n"
        for c in cast {
            let from = c.series.map { " from \($0)" } ?? ""
            p += "- id \"\(c.id)\": \(c.name), a \(c.species)\(from). \(c.trait). Talks like: \(c.samples.joined(separator: " | "))\n"
        }
        let ids = Set(cast.map(\.id))
        for c in cast {
            if let r = c.rival, ids.contains(r), c.id < r { p += "\(c.name) and \(cast.first { $0.id == r }!.name) are rivals and bicker.\n" }
            if let b = c.bestie, ids.contains(b), c.id < b { p += "\(c.name) and \(cast.first { $0.id == b }!.name) are best friends.\n" }
        }
        if let title, !title.isEmpty { p += "The video window's title is: \"\(title)\"\n" }
        if cast.contains(where: { $0.series != nil }) {
            p += """
            If the video is from a character's own show (check the title, the characters and the art style), that \
            character recognises it and reacts to seeing themselves, their friends or their own story, like "wait… that's me!". \
            The others can tease them about it. Don't claim it's their show unless it clearly is.

            """
        }
        if !history.isEmpty { p += "What they said a moment ago:\n" + history.joined(separator: "\n") + "\n" }
        p += """
        Look at this frame of the video and write what each character says right now, reacting to what is \
        actually on screen (people, places, text, action, mood). Stay in character, under 10 words each, \
        no repeats of earlier lines; a character may answer another; use "" to stay quiet. \
        Reply with JSON only, keyed by id: {"id": {"line": "...", "mood": "calm|happy|laugh|shocked|scared|sad|angry|love"}}
        """
        return p
    }

    private func ask(model: String, prompt: String, jpeg: Data) async -> [String: (line: String, mood: String)]? {
        let body: [String: Any] = [
            "model": model, "stream": false, "think": false, "format": "json", "keep_alive": "15m",
            "messages": [["role": "user", "content": prompt, "images": [jpeg.base64EncodedString()]]],
            "options": ["temperature": 0.9, "num_predict": 200],
        ]
        var req = URLRequest(url: endpoint.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 90
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? [String: Any],
              let content = (msg["content"] as? String)?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any] else {
            DispatchQueue.main.async { self.checkOllama() }
            return nil
        }
        var out: [String: (String, String)] = [:]
        for (k, v) in json {
            if let o = v as? [String: Any] {
                out[k.lowercased()] = ((o["line"] as? String) ?? "", (o["mood"] as? String) ?? "calm")
            } else if let s = v as? String {
                out[k.lowercased()] = (s, "calm")
            }
        }
        return out
    }

    private func apply(_ reply: [String: (line: String, mood: String)], to watchers: [Pet]) {
        var delay = 0.0
        for pet in watchers.shuffled() {
            guard let r = reply[pet.kind.id] ?? reply[pet.name.lowercased()] else { continue }
            let line = r.line.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            if !line.isEmpty { history.append("\(pet.name): \(line)") }
            let mood = r.mood.lowercased()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak pet] in pet?.partyReact(String(line.prefix(80)), mood: mood) }
            if !line.isEmpty { delay += 1.8 }
        }
        if history.count > 8 { history.removeFirst(history.count - 8) }
    }

    // MARK: - Snapshot

    /// Just the video window's own pixels (not the pets on top, not other windows), about 640px wide.
    @available(macOS 14.0, *)
    private static func snapshot(windowID: Int) async -> (jpeg: Data, title: String?)? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let win = content.windows.first(where: { $0.windowID == CGWindowID(windowID) }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = SCStreamConfiguration()
            let scale = 640 / max(win.frame.width, win.frame.height, 1)
            cfg.width = max(64, Int(win.frame.width * scale))
            cfg.height = max(64, Int(win.frame.height * scale))
            cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            guard let jpeg = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return nil }
            return (jpeg, win.title)
        } catch {
            NSLog("DeskPals: watch party snapshot failed: \(error)")
            return nil
        }
    }
}
