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
        // Weeks run Monday to Sunday for everyone, like the WEEK board,
        // whatever the phone's region says.
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
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
    /// Earned by one round with at least this score...
    let score: Int
    /// ...played in this mode.
    var mode = GameMode.normal

    var detail: String {
        mode == .normal ? "SCORE \(score)" : "\(mode.title) \(score)"
    }
}

enum Achievements {
    static let earnedKey = "achievements"

    static let all = [
        Achievement(id: "first", title: "FIRST PIPE", score: 1),
        Achievement(id: "ten", title: "TEN", score: 10),
        Achievement(id: "quarter", title: "QUARTER", score: 25),
        Achievement(id: "platinum", title: "PLATINUM", score: 40),
        Achievement(id: "fifty", title: "FIFTY", score: 50),
        Achievement(id: "century", title: "CENTURY", score: 100),
    ]

    /// The goals past 100. The Goals page keeps them hidden until CENTURY
    /// is earned.
    static let legends = [
        Achievement(id: "score150", title: "PIPE WIZARD", score: 150),
        Achievement(id: "score200", title: "SKY PIRATE", score: 200),
        Achievement(id: "score250", title: "BIRD BRAIN", score: 250),
        Achievement(id: "score300", title: "SPARTAN", score: 300),
        Achievement(id: "score400", title: "UNHINGED", score: 400),
        Achievement(id: "score500", title: "TOUCH GRASS", score: 500),
        Achievement(id: "score1000", title: "BIRD GOD", score: 1000),
    ]

    /// One round in a hard mode with at least this score. Ids are by rank
    /// within the mode, so a score can be retuned without losing who
    /// earned what.
    static let hard = [
        Achievement(id: "hard1", title: "SPICY", score: 10, mode: .hard),
        Achievement(id: "hard2", title: "EXTRA SPICY", score: 50, mode: .hard),
        Achievement(id: "insane1", title: "LOSING IT", score: 10, mode: .insane),
        Achievement(id: "insane2", title: "SEND HELP", score: 25, mode: .insane),
        Achievement(id: "impossible1", title: "WORTH A TRY", score: 5, mode: .impossible),
        Achievement(id: "impossible2", title: "NO WAY", score: 25, mode: .impossible),
    ]

    static var legendsUnlocked: Bool {
        earned().contains("century")
    }

    static func earned() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: earnedKey) ?? [])
    }

    /// Records a finished round and returns the achievements it newly
    /// earned: the normal game's goals for a NORMAL round, a hard mode's
    /// own for a round in it. Never the other's.
    @discardableResult
    static func record(score: Int, mode: GameMode) -> [Achievement] {
        let candidates = mode == .normal ? all + legends : hard.filter { $0.mode == mode }
        let goals = candidates.filter { score >= $0.score }.map(\.id)

        var earned = earned()
        let new = goals.filter { !earned.contains($0) }
        guard !new.isEmpty else {
            return []
        }
        earned.formUnion(new)
        UserDefaults.standard.set(earned.sorted(), forKey: earnedKey)
        return candidates.filter { new.contains($0.id) }
    }
}
