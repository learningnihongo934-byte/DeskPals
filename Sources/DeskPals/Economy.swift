import Foundation

/// Things you do with your pets, counted for coins, daily quests and achievements.
enum Deed: String, CaseIterable {
    case petted, fed, favorite, kicked, watchedMinute, tower, gamePlayed, placeVisit, thrown, adopted, grewUp, sawSnow
}

/// Coins, the shop, daily quests and achievements. Saved in UserDefaults.
final class Economy {
    static let shared = Economy()
    private let d = UserDefaults.standard

    private(set) var coins: Int
    private(set) var owned: Set<String>
    private(set) var counts: [String: Int]
    private(set) var achieved: Set<String>
    private(set) var quests: [Quest] = []
    private(set) var spent: Int
    /// Coins earned per day from petting is capped so it can't be farmed.
    private var pettingCoinsToday = 0

    var onToast: ((String) -> Void)?

    struct Quest: Codable {
        let deed: String
        let title: String
        let target: Int
        let reward: Int
        var progress: Int
        var done: Bool { progress >= target }
    }

    private init() {
        coins = d.integer(forKey: "coins")
        owned = Set(d.stringArray(forKey: "owned") ?? [])
        counts = d.dictionary(forKey: "deeds") as? [String: Int] ?? [:]
        achieved = Set(d.stringArray(forKey: "achieved") ?? [])
        spent = d.integer(forKey: "spent")
        refreshQuests()
    }

    // MARK: - Coins and shop

    func earn(_ n: Int, _ why: String? = nil) {
        guard n > 0 else { return }
        coins += n
        save()
        if let why { onToast?("+\(n) 🪙 \(why)") }
    }

    func owns(_ item: ShopItem) -> Bool { item.price == 0 || owned.contains(item.id) }

    @discardableResult
    func buy(_ item: ShopItem) -> Bool {
        guard !owns(item), coins >= item.price else { return false }
        coins -= item.price
        spent += item.price
        owned.insert(item.id)
        save()
        check()
        return true
    }

    // MARK: - Deeds, quests, achievements

    func record(_ deed: Deed, _ amount: Int = 1) {
        counts[deed.rawValue, default: 0] += amount
        switch deed {
        case .petted:
            if pettingCoinsToday < 20 { pettingCoinsToday += 1; coins += 1 }
        case .fed: coins += 2
        case .favorite: coins += 3
        case .kicked: coins += 1
        case .watchedMinute: coins += 1
        case .tower: earn(5, "pet tower!")
        case .placeVisit: coins += 1
        default: break
        }
        refreshQuests()
        for i in quests.indices where quests[i].deed == deed.rawValue && !quests[i].done {
            quests[i].progress += amount
            if quests[i].done { earn(quests[i].reward, "quest: \(quests[i].title)") }
        }
        save()
        check()
    }

    func count(_ deed: Deed) -> Int { counts[deed.rawValue] ?? 0 }

    /// For "have N at once" goals: remembers the highest number seen.
    func atLeast(_ deed: Deed, _ n: Int) {
        guard count(deed) < n else { return }
        counts[deed.rawValue] = n
        save()
        check()
    }

    private static let pool: [(Deed, String, Int, Int)] = [
        (.petted, "Pet your pets 8 times", 8, 20),
        (.fed, "Serve 3 meals", 3, 20),
        (.favorite, "Feed someone their favorite food", 1, 25),
        (.kicked, "Play ball: 6 kicks", 6, 20),
        (.watchedMinute, "Watch videos together for 5 minutes", 5, 25),
        (.tower, "Build a pet tower", 1, 30),
        (.gamePlayed, "Play a mini-game", 1, 25),
        (.placeVisit, "Let them visit places 3 times", 3, 20),
        (.thrown, "Throw a pet 3 times", 3, 15),
    ]

    /// Three new quests each day.
    private func refreshQuests() {
        let today = Self.today()
        if d.string(forKey: "questDay") == today,
           let data = d.data(forKey: "quests"), let saved = try? JSONDecoder().decode([Quest].self, from: data), !saved.isEmpty {
            if quests.isEmpty { quests = saved }
            return
        }
        var rng = SeededRandom(seed: today.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 })
        quests = Self.pool.shuffled(using: &rng).prefix(3).map { Quest(deed: $0.0.rawValue, title: $0.1, target: $0.2, reward: $0.3, progress: 0) }
        pettingCoinsToday = 0
        d.set(today, forKey: "questDay")
        coins += 10   // daily visit
        save()
    }

    struct Achievement {
        let id: String
        let title: String
        let detail: String
        let test: (Economy) -> Bool
    }

    static let achievements: [Achievement] = [
        Achievement(id: "family", title: "Family", detail: "Have 2 pets at once") { $0.count(.adopted) >= 2 },
        Achievement(id: "fullhouse", title: "Full house", detail: "Have 5 pets at once") { $0.count(.adopted) >= 5 },
        Achievement(id: "tower", title: "Skyscraper", detail: "Build a pet tower") { $0.count(.tower) >= 1 },
        Achievement(id: "moviebuff", title: "Movie buff", detail: "Watch 60 minutes of videos together") { $0.count(.watchedMinute) >= 60 },
        Achievement(id: "foodie", title: "Foodie", detail: "Serve 50 meals") { $0.count(.fed) >= 50 },
        Achievement(id: "chef", title: "Chef's kiss", detail: "Serve 10 favorite foods") { $0.count(.favorite) >= 10 },
        Achievement(id: "grownup", title: "All grown up", detail: "Raise a baby into an adult") { $0.count(.grewUp) >= 2 },
        Achievement(id: "baller", title: "Baller", detail: "Kick the ball 100 times") { $0.count(.kicked) >= 100 },
        Achievement(id: "gamer", title: "Gamer", detail: "Play 10 mini-games") { $0.count(.gamePlayed) >= 10 },
        Achievement(id: "tourist", title: "Tourist", detail: "Visit places 25 times") { $0.count(.placeVisit) >= 25 },
        Achievement(id: "collector", title: "Collector", detail: "Own 5 places") { e in ShopItem.all.filter { $0.category == .place && e.owned.contains($0.id) }.count >= 5 },
        Achievement(id: "spender", title: "Big spender", detail: "Spend 500 coins") { $0.spent >= 500 },
        Achievement(id: "snow", title: "Let it snow", detail: "See snow on your screen") { $0.count(.sawSnow) >= 1 },
    ]

    private func check() {
        for a in Self.achievements where !achieved.contains(a.id) && a.test(self) {
            achieved.insert(a.id)
            coins += 50
            onToast?("🏆 \(a.title)! +50 🪙")
        }
        save()
    }

    private func save() {
        d.set(coins, forKey: "coins")
        d.set(Array(owned), forKey: "owned")
        d.set(counts, forKey: "deeds")
        d.set(Array(achieved), forKey: "achieved")
        d.set(spent, forKey: "spent")
        if let data = try? JSONEncoder().encode(quests) { d.set(data, forKey: "quests") }
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// Same quests for everyone on the same day, without storing a seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Shop

struct ShopItem: Identifiable {
    enum Category: String, CaseIterable { case place = "Places", outfit = "Outfits", theme = "Worlds" }

    let id: String
    let title: String
    let price: Int
    let category: Category
    let blurb: String

    static let all: [ShopItem] = [
        ShopItem(id: "place.house", title: "House", price: 120, category: .place, blurb: "Pets nap inside and sit on the roof"),
        ShopItem(id: "place.pond", title: "Pond", price: 150, category: .place, blurb: "Go fishing; slimes swim"),
        ShopItem(id: "place.garden", title: "Garden", price: 100, category: .place, blurb: "Flowers that grow when pets tend them"),
        ShopItem(id: "place.swing", title: "Swing", price: 80, category: .place, blurb: "Wheee, back and forth"),
        ShopItem(id: "place.slide", title: "Slide", price: 80, category: .place, blurb: "Climb up, slide down"),
        ShopItem(id: "place.campfire", title: "Campfire", price: 60, category: .place, blurb: "Pets gather round in the evening"),
        ShopItem(id: "outfit.wizardHat", title: "Wizard hat", price: 60, category: .outfit, blurb: "Magical"),
        ShopItem(id: "outfit.cowboyHat", title: "Cowboy hat", price: 60, category: .outfit, blurb: "Yeehaw"),
        ShopItem(id: "outfit.headphones", title: "Headphones", price: 80, category: .outfit, blurb: "Vibes to your music"),
        ShopItem(id: "outfit.flower", title: "Flower", price: 40, category: .outfit, blurb: "A pretty flower"),
        ShopItem(id: "outfit.bandana", title: "Bandana", price: 40, category: .outfit, blurb: "Cool kid"),
        ShopItem(id: "theme.beach", title: "Beach", price: 100, category: .theme, blurb: "Sand, shells and bubbles"),
        ShopItem(id: "theme.forest", title: "Forest", price: 100, category: .theme, blurb: "Grass, mushrooms and fireflies"),
        ShopItem(id: "theme.snowy", title: "Snowy", price: 100, category: .theme, blurb: "Snow on everything"),
        ShopItem(id: "theme.space", title: "Space", price: 200, category: .theme, blurb: "Moon rocks, stars and low gravity"),
    ]

    static func find(_ id: String) -> ShopItem? { all.first { $0.id == id } }
}
