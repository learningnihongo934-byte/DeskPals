import Foundation

enum ClickStyle: String { case chase, startle }

/// A pet's signature move, used when it's startled or showing off.
enum Special: String { case none, fire, tentacles, spinKick, barrage }

/// One kind of pet: its pixel art and its personality.
///
/// Art is 16 columns wide and drawn facing right (or left, with `mirrored`).
/// `o` outline, `b` base, `s` shade, `h` highlight (or hair), `a` accent, `n` nose or mouth, `K` dark, `.` empty.
/// `1` and `2` mark the top and bottom rows of each 2x2 eye, so the renderer can
/// open, close or swirl them; `3` and `4` mark an eye whose pupil uses the `R` colour instead.
/// Legs are 2px stubs drawn under the art.
struct PetKind {
    let id: String
    let name: String
    let species: String
    let sound: String
    let trait: String
    let art: [String]
    let mirrored: Bool
    let legs: [Int]
    let palette: [Character: UInt32]
    let walkSpeed: CGFloat   // sprite pixels per second
    let jumpiness: Double    // chance per idle decision to hop to another ledge
    let curiosity: Double    // chance to go and inspect a new window
    let sleepiness: Double   // higher naps sooner
    let clickStyle: ClickStyle
    let gravity: Double      // below 1 glides
    let hops: Bool           // moves by bouncing instead of stepping
    let bounciness: Double   // how much of a hard landing turns into a bounce
    let zoomy: Double        // chance of a burst of zoomies when happy
    let climbs: Bool         // climbs up the sides of the screen
    let clingy: Bool         // follows your cursor around
    let favorite: Food
    let phrases: [String]
    var special: Special = .none
    var backHair: [Int] = []   // art rows painted as hair when seen from behind (for people)
    var shout: String? = nil   // what it yells during its special move

    static let builtIn: [PetKind] = [mochi, gloop, ember, pip]
    /// Built-in pets plus any custom pets from ~/Library/Application Support/DeskPals/Pets.
    static let all: [PetKind] = builtIn + CustomPets.load()

    static let mochi = PetKind(
        id: "mochi", name: "Mochi", species: "cat", sound: "mew!", trait: "Chases clicks, naps a lot",
        art: [
            "................",
            "....o.......o...",
            "...oao.....oao..",
            "...obbooooobbo..",
            "...obbbsbsbbbo..",
            "...ob11bbb11bo..",
            "...ob22bnb22bo..",
            "...obbbbbbbbbo..",
            ".o.obbbbbbbbbo..",
            "oboobbbbbbbbbo..",
            "oboobhhhhbbbbo..",
            ".ooobhhhhbbbbo..",
            "...obhhhhbbbbo..",
            "...ooooooooooo..",
        ],
        mirrored: false, legs: [4, 11],
        palette: ["o": 0x4A3530, "b": 0xF6D7A7, "s": 0xE0A868, "h": 0xFFF4E0, "a": 0xF29AA3, "n": 0xF29AA3, "K": 0x2B1D1A],
        walkSpeed: 22, jumpiness: 0.25, curiosity: 0.7, sleepiness: 1.5,
        clickStyle: .chase, gravity: 1, hops: false,
        bounciness: 0.3, zoomy: 0.12, climbs: true, clingy: false, favorite: .fish,
        phrases: ["mew", "mrrp?", "purr…", "*stares*", "feed me?", "mrow"])

    static let gloop = PetKind(
        id: "gloop", name: "Gloop", species: "slime", sound: "blub", trait: "Slow, bouncy, easily startled",
        art: [
            "................",
            "................",
            "................",
            "................",
            "......oooo......",
            "....oohhbboo....",
            "...ohhbbbbbbo...",
            "..ohbbbbbbbbbo..",
            "..obb11bb11bbo..",
            ".obbb22bb22bbbo.",
            ".obbbbbnnbbbbbo.",
            ".obbbbbbbbbbbbo.",
            "obbbbbbbbbbbbbso",
            "obsbbbbbbbbbbsso",
            "osssssssssssssso",
            ".oooooooooooooo.",
        ],
        mirrored: false, legs: [],
        palette: ["o": 0x1D4A36, "b": 0x7BE495, "s": 0x46B46F, "h": 0xD4FFE0, "a": 0xFF9AAE, "n": 0x1D4A36, "K": 0x173B2B],
        walkSpeed: 14, jumpiness: 0.1, curiosity: 0.4, sleepiness: 1,
        clickStyle: .startle, gravity: 1, hops: true,
        bounciness: 0.6, zoomy: 0.03, climbs: false, clingy: true, favorite: .berry,
        phrases: ["blub", "bloop!", "*wobble*", "squish", "glorp?", "hug?"])

    static let ember = PetKind(
        id: "ember", name: "Ember", species: "fox", sound: "yip!", trait: "Fast and nosy about new windows",
        art: [
            "................",
            "..o.......o.....",
            "..oo.....oo.....",
            "..oao...oao.....",
            "..obbooobbo.....",
            "..obbbbbbbo.....",
            "..ob11b11bo.....",
            "..ob22b22bo.....",
            "..ohhhnhhho.....",
            "...ohhhhho..oho.",
            "...obhhhbbbooho.",
            "...obhhhbbbobbo.",
            "...obbbbbbbbbbo.",
            "...oooooooooooo.",
        ],
        mirrored: true, legs: [4, 9],
        palette: ["o": 0x3D2216, "b": 0xF0803A, "s": 0xC85D22, "h": 0xFFF2E2, "a": 0xFFC9A8, "n": 0x1D110B, "K": 0x1D110B],
        walkSpeed: 30, jumpiness: 0.2, curiosity: 0.9, sleepiness: 0.8,
        clickStyle: .chase, gravity: 1, hops: false,
        bounciness: 0.3, zoomy: 0.25, climbs: true, clingy: false, favorite: .cookie,
        phrases: ["yip!", "what's that?", "*sniff sniff*", "play?", "heehee", "zoom?"])

    static let pip = PetKind(
        id: "pip", name: "Pip", species: "dragon", sound: "rawr!", trait: "Jumpy, glides instead of falling",
        art: [
            "................",
            ".....a.....a....",
            ".....ao...oa....",
            "....obbooobbo...",
            "...obbbbbbbbbo..",
            "...ob11bbb11bo..",
            "...ob22bbb22bo..",
            "...obbbbbbbbbo..",
            "....obbnbnbbo...",
            ".oo.obbbbbbbo...",
            "ossoobaaaabbo...",
            ".osoobaaaabbo...",
            "o...obaaaabbo...",
            "obooooooooooo...",
        ],
        mirrored: false, legs: [5, 9],
        palette: ["o": 0x2D1A45, "b": 0xA77AE0, "s": 0x7A4FB8, "h": 0xD2B8F5, "a": 0xFFD36E, "n": 0x7A4FB8, "K": 0x1B1029],
        walkSpeed: 18, jumpiness: 0.3, curiosity: 0.6, sleepiness: 1.2,
        clickStyle: .startle, gravity: 0.6, hops: false,
        bounciness: 0.35, zoomy: 0.08, climbs: false, clingy: false, favorite: .pepper,
        phrases: ["rawr!", "*puff*", "treasure?", "I'm fierce", "smol but mighty", "hoard time"],
        special: .fire)
}

/// Things the pet can wear, unlocked as your bond grows.
enum Accessory: String, CaseIterable {
    case none, bow, partyHat, sunglasses, santaHat, crown

    var title: String {
        switch self {
        case .none: return "Nothing"
        case .bow: return "Bow"
        case .partyHat: return "Party hat"
        case .sunglasses: return "Sunglasses"
        case .santaHat: return "Santa hat"
        case .crown: return "Crown"
        }
    }

    var level: Int {
        switch self {
        case .none: return 0
        case .bow: return 1
        case .partyHat: return 2
        case .sunglasses: return 3
        case .santaHat: return 4
        case .crown: return 5
        }
    }

    /// Pixel art and where it sits: x offset from the eyes' centre, bottom row relative to the head top.
    var art: (rows: [String], palette: [Character: UInt32], dx: Int, lift: Int)? {
        switch self {
        case .none, .sunglasses: return nil
        case .bow:
            return (["pp.pp", "ppPpp", "pp.pp"], ["p": 0xFF6FA5, "P": 0xC2366F], 3, 1)
        case .partyHat:
            return (["..y..", "..b..", ".bpb.", ".pbp.", "bpbpb"],
                    ["y": 0xFFD54F, "b": 0x4FC3F7, "p": 0xFF6FA5], 0, 0)
        case .santaHat:
            return (["....rw", "...rr.", "..rrr.", ".rrrr.", "wwwwww"], ["r": 0xE53935, "w": 0xFFFFFF], 0, 0)
        case .crown:
            return (["y.y.y", "yyyyy", "yrysy", "yyyyy"], ["y": 0xFFC83D, "r": 0xE53935, "s": 0x4FC3F7], 0, 0)
        }
    }
}
