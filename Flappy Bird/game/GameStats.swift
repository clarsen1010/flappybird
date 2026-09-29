//
//  GameStats.swift
//  FlappyBird
//
//  Play history for the Stats page and achievements. Every finished round
//  adds to a per-day record (games, pipes, best), so Today / This Week /
//  This Month / All Time all come from one small dictionary that also syncs
//  through iCloud (see CloudSync). Counting starts with the build that added
//  this file; there is no earlier history to fill in.
//
import Foundation

struct DayStats: Codable, Equatable {
    var games: Int
    var pipes: Int
    var best: Int

    /// Deterministic merge winner: more games, then more pipes, then higher best.
    func beats(_ other: DayStats) -> Bool {
        (games, pipes, best) > (other.games, other.pipes, other.best)
    }
}

struct PeriodStats {
    let games: Int
    let pipes: Int
    let best: Int

    /// Zero-point rounds count, so this is the honest average.
    var average: Double {
        games == 0 ? 0 : Double(pipes) / Double(games)
    }
}

enum StatsPeriod: CaseIterable {
    case today, week, month, all

    var title: String {
        switch self {
        case .today: return "TODAY"
        case .week: return "WEEK"
        case .month: return "MONTH"
        case .all: return "ALL"
        }
    }
}

enum GameStats {
    static let daysKey = "dayStats"

    /// Day keys use the phone's calendar and time zone ("2026-09-29").
    static let dayFormatter = DateFormatter().then {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.calendar = Calendar(identifier: .gregorian)
        $0.timeZone = .autoupdatingCurrent
        $0.dateFormat = "yyyy-MM-dd"
    }

    static func loadDays() -> [String: DayStats] {
        guard let data = UserDefaults.standard.data(forKey: daysKey),
              let days = try? JSONDecoder().decode([String: DayStats].self, from: data) else {
            return [:]
        }
        return days
    }

    static func saveDays(_ days: [String: DayStats]) {
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: daysKey)
        }
    }

    /// Call once per finished round, zero scores included.
    static func record(score: Int, date: Date = Date()) {
        var days = loadDays()
        let key = dayFormatter.string(from: date)
        var day = days[key] ?? DayStats(games: 0, pipes: 0, best: 0)
        day.games += 1
        day.pipes += score
        day.best = max(day.best, score)
        days[key] = day
        saveDays(days)
    }

    static func summary(_ period: StatsPeriod, now: Date = Date()) -> PeriodStats {
        let calendar = Calendar.current
        let interval: DateInterval?

        switch period {
        case .today: interval = calendar.dateInterval(of: .day, for: now)
        case .week: interval = calendar.dateInterval(of: .weekOfYear, for: now)
        case .month: interval = calendar.dateInterval(of: .month, for: now)
        case .all: interval = nil
        }

        // "yyyy-MM-dd" sorts as text, so compare keys; end is exclusive.
        // (Parsing keys back to dates drops days whose midnight a DST change skips.)
        let range = interval.map { (dayFormatter.string(from: $0.start), dayFormatter.string(from: $0.end)) }
        var games = 0, pipes = 0, best = 0

        for (key, day) in loadDays() {
            if let (start, end) = range, !(key >= start && key < end) {
                continue
            }
            games += day.games
            pipes += day.pipes
            best = max(best, day.best)
        }

        return PeriodStats(games: games, pipes: pipes, best: best)
    }
}

// MARK: - Achievements

struct Achievement {
    let id: String
    let title: String
    let detail: String
}

enum Achievements {
    static let earnedKey = "achievements"
    static let birdsPlayedKey = "birdsPlayed"

    static let all = [
        Achievement(id: "first", title: "FIRST PIPE", detail: "SCORE 1"),
        Achievement(id: "ten", title: "TEN", detail: "SCORE 10"),
        Achievement(id: "quarter", title: "QUARTER", detail: "SCORE 25"),
        Achievement(id: "platinum", title: "PLATINUM", detail: "SCORE 40"),
        Achievement(id: "fifty", title: "FIFTY", detail: "SCORE 50"),
        Achievement(id: "century", title: "CENTURY", detail: "SCORE 100"),
        Achievement(id: "nightOwl", title: "NIGHT OWL", detail: "20 AT NIGHT"),
        Achievement(id: "rainbow", title: "RAINBOW", detail: "FLY EVERY BIRD"),
    ]

    static func earned() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: earnedKey) ?? [])
    }

    static func birdsPlayed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: birdsPlayedKey) ?? [])
    }

    /// Records a finished round and returns the achievements it newly earned.
    @discardableResult
    static func record(score: Int, bird: String, night: Bool, allBirds: [String]) -> [Achievement] {
        var birds = birdsPlayed()
        birds.insert(bird)
        UserDefaults.standard.set(birds.sorted(), forKey: birdsPlayedKey)

        var goals: [String] = []
        if score >= 1 { goals.append("first") }
        if score >= 10 { goals.append("ten") }
        if score >= 25 { goals.append("quarter") }
        if score >= 40 { goals.append("platinum") }
        if score >= 50 { goals.append("fifty") }
        if score >= 100 { goals.append("century") }
        if night && score >= 20 { goals.append("nightOwl") }
        if Set(allBirds).isSubset(of: birds) { goals.append("rainbow") }

        var earned = earned()
        let new = goals.filter { !earned.contains($0) }
        guard !new.isEmpty else {
            return []
        }
        earned.formUnion(new)
        UserDefaults.standard.set(earned.sorted(), forKey: earnedKey)
        return all.filter { new.contains($0.id) }
    }
}
