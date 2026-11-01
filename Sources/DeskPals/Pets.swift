import Foundation

enum ClickStyle { case chase, startle }

/// One kind of pet: its pixel art and its personality.
///
/// Art is 16 columns wide and drawn facing right (or left, with `mirrored`).
/// `o` outline, `b` base, `s` shade, `h` highlight, `a` accent, `K` dark, `.` empty.
/// `1` and `2` mark the top and bottom rows of each 2x2 eye, so the renderer can
/// open, close or swirl them. Legs are 2px stubs drawn under the art.
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

    static let all: [PetKind] = [mochi, gloop, ember, pip]

    static let mochi = PetKind(
        id: "mochi", name: "Mochi", species: "cat", sound: "mew!", trait: "Chases clicks, naps a lot",
        art: [
            "................",
            "....o.......o...",
            "...oao.....oao..",
            "...obbooooobbo..",
            "...obbbsbsbbbo..",
            "...ob11bbb11bo..",
            "...ob22bab22bo..",
            "...obbbbbbbbbo..",
            ".o.obbbbbbbbbo..",
            "oboobbbbbbbbbo..",
            "oboobhhhhbbbbo..",
            ".ooobhhhhbbbbo..",
            "...obhhhhbbbbo..",
            "...ooooooooooo..",
        ],
        mirrored: false, legs: [4, 11],
        palette: ["o": 0x4A3530, "b": 0xF6D7A7, "s": 0xE0A868, "h": 0xFFF4E0, "a": 0xF29AA3, "K": 0x2B1D1A],
        walkSpeed: 22, jumpiness: 0.25, curiosity: 0.7, sleepiness: 1.5,
        clickStyle: .chase, gravity: 1, hops: false)

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
            ".obbbbbaabbbbbo.",
            ".obbbbbbbbbbbbo.",
            "obbbbbbbbbbbbbso",
            "obsbbbbbbbbbbsso",
            "osssssssssssssso",
            ".oooooooooooooo.",
        ],
        mirrored: false, legs: [],
        palette: ["o": 0x1D4A36, "b": 0x7BE495, "s": 0x46B46F, "h": 0xD4FFE0, "a": 0x1D4A36, "K": 0x173B2B],
        walkSpeed: 14, jumpiness: 0.1, curiosity: 0.4, sleepiness: 1,
        clickStyle: .startle, gravity: 1, hops: true)

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
            "..ohhhKhhho.....",
            "...ohhhhho..oho.",
            "...obhhhbbbooho.",
            "...obhhhbbbobbo.",
            "...obbbbbbbbbbo.",
            "...oooooooooooo.",
        ],
        mirrored: true, legs: [4, 9],
        palette: ["o": 0x3D2216, "b": 0xF0803A, "s": 0xC85D22, "h": 0xFFF2E2, "a": 0xFFC9A8, "K": 0x1D110B],
        walkSpeed: 30, jumpiness: 0.2, curiosity: 0.9, sleepiness: 0.8,
        clickStyle: .chase, gravity: 1, hops: false)

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
            "....obbsbsbbo...",
            ".oo.obbbbbbbo...",
            "ossoobaaaabbo...",
            ".osoobaaaabbo...",
            "o...obaaaabbo...",
            "obooooooooooo...",
        ],
        mirrored: false, legs: [5, 9],
        palette: ["o": 0x2D1A45, "b": 0xA77AE0, "s": 0x7A4FB8, "h": 0xD2B8F5, "a": 0xFFD36E, "K": 0x1B1029],
        walkSpeed: 18, jumpiness: 0.3, curiosity: 0.6, sleepiness: 1.2,
        clickStyle: .startle, gravity: 0.6, hops: false)
}
