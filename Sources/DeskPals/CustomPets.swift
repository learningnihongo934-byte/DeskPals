import Foundation

/// Your own pets, one JSON file each in ~/Library/Application Support/DeskPals/Pets.
/// Only `id`, `name`, `art` and `palette` are required; everything else has a sensible default.
/// See the README for the format.
enum CustomPets {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskPals/Pets", isDirectory: true)
    }

    private struct File: Decodable {
        let id: String
        let name: String
        let species: String?
        let sound: String?
        let trait: String?
        let art: [String]
        let mirrored: Bool?
        let legs: [Int]?
        let palette: [String: String]
        let walkSpeed: Double?
        let jumpiness: Double?
        let curiosity: Double?
        let sleepiness: Double?
        let clickStyle: String?
        let gravity: Double?
        let hops: Bool?
        let bounciness: Double?
        let zoomy: Double?
        let climbs: Bool?
        let clingy: Bool?
        let favorite: String?
        let phrases: [String]?
        let special: String?
        let backHair: [Int]?
        let shout: String?
        let power: String?
        let noAura: Bool?
        let series: String?
        let aura: String?
        let auraText: String?
        let powerShout: String?
        let transformArt: [String]?
        let transformPalette: [String: String]?
        let transformScale: Double?
        let rival: String?
        let rivalLines: [String]?
        let winLines: [String]?
        let loseLines: [String]?
        let watchLines: [String]?
        let projectile: String?
        let dropArt: [String]?
        let dropPalette: [String: String]?
        let dropShout: String?
        let startsGrown: Bool?
        let rivalStyle: String?
        let bestie: String?
        let bestieLines: [String]?
        let progression: [String]?
        let progressInterval: Double?
        let progressShout: String?
        let finaleShout: String?
        let resetShout: String?
    }

    static func load() -> [PetKind] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            do {
                return kind(from: try JSONDecoder().decode(File.self, from: data))
            } catch {
                NSLog("DeskPals: skipping \(url.lastPathComponent): \(error)")
                return nil
            }
        }
    }

    private static func hex(_ v: String) -> UInt32? { UInt32(v.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) }

    private static func colors(_ d: [String: String]) -> [Character: UInt32] {
        var out: [Character: UInt32] = [:]
        for (k, v) in d { if let ch = k.first, let rgb = hex(v) { out[ch] = rgb } }
        return out
    }

    private static func kind(from f: File) -> PetKind {
        let palette = colors(f.palette)
        var kind = PetKind(
            id: f.id, name: f.name, species: f.species ?? "pal", sound: f.sound ?? "!", trait: f.trait ?? "",
            art: f.art, mirrored: f.mirrored ?? false, legs: f.legs ?? [], palette: palette,
            walkSpeed: CGFloat(f.walkSpeed ?? 20), jumpiness: f.jumpiness ?? 0.2, curiosity: f.curiosity ?? 0.6,
            sleepiness: f.sleepiness ?? 1, clickStyle: ClickStyle(rawValue: f.clickStyle ?? "") ?? .chase,
            gravity: f.gravity ?? 1, hops: f.hops ?? false, bounciness: f.bounciness ?? 0.3, zoomy: f.zoomy ?? 0.08,
            climbs: f.climbs ?? false, clingy: f.clingy ?? false, favorite: Food(rawValue: f.favorite ?? "") ?? .cookie,
            phrases: f.phrases ?? [f.sound ?? "!"], special: Special(rawValue: f.special ?? "") ?? .none,
            backHair: f.backHair ?? [], shout: f.shout)
        kind.power = f.power.flatMap(Special.init(rawValue:))
        kind.noAura = f.noAura ?? false
        kind.series = f.series
        kind.aura = f.aura.flatMap(hex)
        kind.auraText = f.auraText
        kind.powerShout = f.powerShout
        kind.transformArt = f.transformArt
        kind.transformPalette = f.transformPalette.map(colors)
        kind.transformScale = CGFloat(f.transformScale ?? 2.5)
        kind.rival = f.rival
        kind.rivalLines = f.rivalLines ?? []
        kind.winLines = f.winLines ?? []
        kind.loseLines = f.loseLines ?? []
        kind.watchLines = f.watchLines ?? []
        kind.projectile = f.projectile
        kind.dropArt = f.dropArt
        kind.dropPalette = f.dropPalette.map(colors) ?? [:]
        kind.dropShout = f.dropShout
        kind.startsGrown = f.startsGrown ?? false
        kind.rivalStyle = f.rivalStyle
        kind.bestie = f.bestie
        kind.bestieLines = f.bestieLines ?? []
        kind.progression = f.progression
        kind.progressInterval = max(5, f.progressInterval ?? 60)
        kind.progressShout = f.progressShout
        kind.finaleShout = f.finaleShout
        kind.resetShout = f.resetShout
        return kind
    }
}
