//
//  FriendsLogic.swift
//  FlappyBird
//
//  The parts of the friends leaderboard that need no network: name rules,
//  the "best today" rule, row order and the "2H AGO" text. Foundation only,
//  so it is checked from the command line (see friendstest in the artifacts
//  folder).
//
import Foundation

/// One player as shown on the friends and everyone lists.
struct PlayerRow: Codable, Equatable {
    /// CloudKit record name.
    var id: String
    var name: String
    var best: Int
    /// Best score on `dayKey`, the player's own local day ("yyyy-MM-dd").
    var dayBest: Int
    var dayKey: String
    var lastPlayed: Date?
}

enum NameProblem: Equatable {
    case length, characters, blocked
}

enum NameRules {
    static let minLength = 3
    static let maxLength = 10

    /// Names that are refused outright.
    private static let blockedNames: Set<String> = [
        "ASS", "ANUS", "ANAL", "COCK", "CUM", "DICK", "FAG", "KKK", "NAZI",
        "NAZIS", "PENIS", "PORN", "PUSSY", "RAPE", "RAPIST", "SEX", "SHIT",
        "SLUT", "TIT", "TITS", "VAGINA", "WHORE",
    ]

    /// Refused anywhere inside a name. Only words that do not turn up inside
    /// ordinary names (CLASSIC, BASS7, THERAPIST and NAZIR must pass).
    private static let blockedParts = [
        "BITCH", "CUNT", "FAGGOT", "FUCK", "HITLER", "NIGG",
    ]

    /// What the name prompt keeps while typing: upper-case A-Z and 0-9,
    /// cut to the maximum length.
    static func cleaned(_ raw: String) -> String {
        let kept = raw.uppercased().unicodeScalars.filter {
            ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
        return String(String.UnicodeScalarView(kept.prefix(maxLength)))
    }

    /// Nil when the name is allowed. Expects the name exactly as it will be
    /// stored (upper-case).
    static func problem(_ name: String) -> NameProblem? {
        guard (minLength...maxLength).contains(name.count) else {
            return .length
        }
        guard name == cleaned(name) else {
            return .characters
        }
        // Digits read as letters (N1CE -> NICE) so a swap does not get past.
        let digits: [Character: Character] = ["0": "O", "1": "I", "3": "E", "4": "A", "5": "S", "7": "T"]
        let spelled = String(name.map { digits[$0] ?? $0 })
        for candidate in [name, spelled] {
            if blockedNames.contains(candidate) || blockedParts.contains(where: candidate.contains) {
                return .blocked
            }
        }
        return nil
    }
}

enum FriendsLogic {
    /// A player's best today, or nil when their last scoring day is not the
    /// viewer's today.
    static func todayBest(_ row: PlayerRow, todayKey: String) -> Int? {
        row.dayKey == todayKey ? row.dayBest : nil
    }

    /// Best first; equal bests in name order so the list does not reshuffle.
    static func sorted(_ rows: [PlayerRow]) -> [PlayerRow] {
        rows.sorted { $0.best != $1.best ? $0.best > $1.best : $0.name < $1.name }
    }

    /// What to store when this phone publishes its scores over an existing
    /// record: the server's name stays (only claiming a name changes it; a
    /// second phone may still hold an old one), and the best is never
    /// lowered nor the day moved back (a second phone may be ahead).
    static func merged(server: PlayerRow, local: PlayerRow) -> PlayerRow {
        var row = local
        row.name = server.name
        row.best = max(server.best, local.best)
        if server.dayKey > local.dayKey {
            row.dayKey = server.dayKey
            row.dayBest = server.dayBest
        } else if server.dayKey == local.dayKey {
            row.dayBest = max(server.dayBest, local.dayBest)
        }
        if let theirs = server.lastPlayed, theirs > (local.lastPlayed ?? .distantPast) {
            row.lastPlayed = theirs
        }
        return row
    }

    /// "NOW", "5M AGO", "2H AGO", "3D AGO"; empty when never played.
    static func agoText(_ date: Date?, now: Date) -> String {
        guard let date else {
            return ""
        }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 120 {
            return "NOW"
        }
        if seconds < 3600 {
            return "\(seconds / 60)M AGO"
        }
        if seconds < 86400 {
            return "\(seconds / 3600)H AGO"
        }
        return "\(seconds / 86400)D AGO"
    }
}
