import Foundation

/// Spieler mit eigenem Rekord, eigener Steuerung und dem letzten Stand.
struct Roster: Codable {
    struct Player: Codable {
        var id: UUID
        var name: String
        var best: Int
        var mouse: Bool
        var save: Sim.Save?
        var difficulty: Int? = nil

        var rank: Sim.Rank {
            Sim.Rank(rawValue: difficulty ?? Sim.Rank.medium.rawValue) ?? .medium
        }
    }

    struct Mark: Codable {
        var name: String
        var score: Int
        var round: Int
        var rank: Int
    }

    var lastID: UUID?
    var lastPlayedID: UUID?
    var players: [Player]
    var marks: [Mark]? = nil

    var board: [Mark] {
        (marks ?? []).sorted { $0.score > $1.score }
    }

    mutating func note(name: String, score: Int, round: Int, rank: Int) {
        guard score > 0 else { return }
        var list = marks ?? []
        list.append(Mark(name: name, score: score, round: round, rank: rank))
        list.sort { $0.score > $1.score }
        if list.count > 10 { list = Array(list.prefix(10)) }
        marks = list
    }

    var selected: Player? {
        if let lastID, let player = players.first(where: { $0.id == lastID }) { return player }
        return players.first
    }

    static func load(defaultName: String) -> Roster {
        let url = file
        if let data = try? Data(contentsOf: url),
           let roster = try? JSONDecoder().decode(Roster.self, from: data),
           !roster.players.isEmpty {
            return roster
        }
        var mouse = true
        if UserDefaults.standard.object(forKey: "klinker.mouse") != nil {
            mouse = UserDefaults.standard.bool(forKey: "klinker.mouse")
        }
        let player = Player(
            id: UUID(),
            name: defaultName,
            best: UserDefaults.standard.integer(forKey: "klinker.best"),
            mouse: mouse,
            save: nil)
        var roster = Roster(lastID: player.id, lastPlayedID: nil, players: [player], marks: nil)
        roster.write()
        return roster
    }

    mutating func write() {
        let url = Self.file
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            // Der nächste Speichervorgang versucht es erneut.
        }
    }

    static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Klinker/roster.json")
    }
}
