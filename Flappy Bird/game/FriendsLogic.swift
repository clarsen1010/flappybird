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
    /// Best score in the week and the month of `dayKey` (see
    /// FriendsLogic.weekKey). Optional: records and stored lists from
    /// before 5.3 do not have them.
    var weekKey: String?
    var weekBest: Int?
    var monthKey: String?
    var monthBest: Int?
}

/// The boards on the EVERYONE list.
enum BoardScope: String, CaseIterable {
    case today, week, month, all

    var title: String {
        switch self {
        case .today: return "TODAY"
        case .week: return "WEEK"
        case .month: return "MONTH"
        case .all: return "ALL TIME"
        }
    }
}

/// One line of a board.
struct BoardEntry: Equatable {
    var rank: Int
    var name: String
    var value: Int
    var isMe: Bool
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
        // Week and month follow the day's rule: the later period wins,
        // the same period keeps the higher best.
        let serverWeek = server.weekKey ?? "", localWeek = local.weekKey ?? ""
        if serverWeek > localWeek {
            row.weekKey = server.weekKey
            row.weekBest = server.weekBest
        } else if serverWeek == localWeek, !localWeek.isEmpty {
            row.weekBest = max(server.weekBest ?? 0, local.weekBest ?? 0)
        }
        let serverMonth = server.monthKey ?? "", localMonth = local.monthKey ?? ""
        if serverMonth > localMonth {
            row.monthKey = server.monthKey
            row.monthBest = server.monthBest
        } else if serverMonth == localMonth, !localMonth.isEmpty {
            row.monthBest = max(server.monthBest ?? 0, local.monthBest ?? 0)
        }
        if let theirs = server.lastPlayed, theirs > (local.lastPlayed ?? .distantPast) {
            row.lastPlayed = theirs
        }
        return row
    }

    // MARK: Weeks and months

    // Both come from the day key ("2026-10-03", the player's own local
    // day) by rules that do not depend on the phone's region or calendar
    // settings, so every phone gives the same day the same week.

    /// The Monday of that day's week, as a day key. Empty for a bad key.
    static func weekKey(dayKey: String) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard dayKey.count == 10, parts.count == 3 else {
            return ""
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return ""
        }

        // Weekday 1 is Sunday; Monday starts the week.
        let sinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: day) else {
            return ""
        }
        let date = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
    }

    /// "2026-10". Empty for a bad key.
    static func monthKey(dayKey: String) -> String {
        dayKey.count == 10 ? String(dayKey.prefix(7)) : ""
    }

    /// The best score in the week and in the month of `anchorDayKey`, from
    /// each day's best.
    static func periodBests(days: [String: Int], anchorDayKey: String) -> (weekKey: String, weekBest: Int, monthKey: String, monthBest: Int) {
        let week = weekKey(dayKey: anchorDayKey)
        let month = monthKey(dayKey: anchorDayKey)
        var weekBest = 0, monthBest = 0

        for (day, best) in days {
            if !week.isEmpty, weekKey(dayKey: day) == week {
                weekBest = max(weekBest, best)
            }
            if !month.isEmpty, monthKey(dayKey: day) == month {
                monthBest = max(monthBest, best)
            }
        }

        return (week, weekBest, month, monthBest)
    }

    // MARK: Boards

    /// A player's score on a board, 0 when they are not on it. `key` is
    /// the viewer's current day, week or month key (unused for all time).
    static func boardValue(_ row: PlayerRow, scope: BoardScope, key: String) -> Int {
        switch scope {
        case .today: return row.dayKey == key ? row.dayBest : 0
        case .week: return row.weekKey == key ? row.weekBest ?? 0 : 0
        case .month: return row.monthKey == key ? row.monthBest ?? 0 : 0
        case .all: return row.best
        }
    }

    /// A board as shown: the first `shown` players, and this player's own
    /// line when they have a score but are further down. `rows` is what
    /// the server sent; `me` is this player's score from the phone's own
    /// numbers (the server's copy can be a round behind), nil when the
    /// player is not on the server at all. `youRank` is nil when the rank
    /// is past the end of what was fetched.
    static func board(
        rows: [PlayerRow],
        scope: BoardScope,
        key: String,
        me: (id: String, name: String, value: Int)?,
        shown: Int,
        fetchedAll: Bool
    ) -> (top: [BoardEntry], you: BoardEntry?, youRankKnown: Bool) {
        var lines = rows
            .filter { $0.id != me?.id }
            .map { (name: $0.name, value: boardValue($0, scope: scope, key: key), isMe: false) }
            .filter { $0.value > 0 }

        if let me, me.value > 0 {
            lines.append((name: me.name, value: me.value, isMe: true))
        }

        lines.sort { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }

        let entries = lines.enumerated().map { BoardEntry(rank: $0 + 1, name: $1.name, value: $1.value, isMe: $1.isMe) }
        let mine = entries.first { $0.isMe }
        let you = mine.flatMap { $0.rank > shown ? $0 : nil }

        // Last of a list that was cut off: there may be players between.
        let known = fetchedAll || (mine?.rank ?? 0) < entries.count
        return (Array(entries.prefix(shown)), you, known)
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
        // Capped so the text never grows past seven characters.
        return seconds / 86400 > 99 ? "99D+" : "\(seconds / 86400)D AGO"
    }

    // MARK: Removing a friend

    // The friends list itself only ever grows: 5.2 and iCloud merge it as a
    // union. Removal is kept beside it as one time per player: positive
    // means removed then, negative means added again then. The later time
    // wins when two of the player's phones disagree.
    typealias Marks = [String: Double]

    static func removedIDs(_ marks: Marks) -> Set<String> {
        Set(marks.filter { $0.value > 0 }.keys)
    }

    /// The friends list as the player sees it.
    static func effectiveFriends(_ friends: [String], marks: Marks) -> [String] {
        let removed = removedIDs(marks)
        return friends.filter { !removed.contains($0) }
    }

    /// Later than any time already stored for this player, even if the
    /// clock was set back.
    private static func stamp(_ id: String, now: Double, _ marks: Marks) -> Double {
        max(now, abs(marks[id] ?? 0) + 1)
    }

    static func remove(_ id: String, now: Double, _ marks: Marks) -> Marks {
        var marks = marks
        marks[id] = stamp(id, now: now, marks)
        return marks
    }

    /// Adding someone again cancels their removal. Someone never removed
    /// gets no entry.
    static func readd(_ id: String, now: Double, _ marks: Marks) -> Marks {
        guard marks[id] != nil else {
            return marks
        }
        var marks = marks
        marks[id] = -stamp(id, now: now, marks)
        return marks
    }

    /// Per player the later time wins; at the same time, removal does.
    static func mergeMarks(_ a: Marks, _ b: Marks) -> Marks {
        a.merging(b) { one, two in
            abs(one) != abs(two) ? (abs(one) > abs(two) ? one : two) : max(one, two)
        }
    }

    /// The friends list to store on the player's record: this phone's
    /// list, then whatever else the server has (a reinstalled phone whose
    /// own list has not arrived must not empty it), without the removed.
    static func serverFriends(local: [String], server: [String], removed: Set<String>) -> [String] {
        var all = local.filter { !removed.contains($0) }
        for id in server where !all.contains(id) && !removed.contains(id) {
            all.append(id)
        }
        return all
    }

    // MARK: Who added you

    /// Friends who added this player too.
    static func mutualIDs(friends: [String], addedMe: [String]) -> Set<String> {
        Set(friends).intersection(addedMe)
    }

    /// The players waiting on ADDED YOU that this phone has not shown yet.
    static func unseen(waiting: [String], seen: Set<String>) -> [String] {
        waiting.filter { !seen.contains($0) }
    }

    /// The page a player is on in a list shown `perPage` at a time.
    static func pageIndex(of id: String, in ids: [String], perPage: Int) -> Int? {
        ids.firstIndex(of: id).map { $0 / perPage }
    }

    static func shareText(name: String) -> String {
        "Add me on Blappy Fird! My player name is \(name)"
    }
}
