//
//  CloudSync.swift
//  FlappyBird
//
//  Keeps scores and stats in iCloud (key-value store) so a reinstall or a
//  second phone gets them back. Settings stay on the phone.
//
//  Merge rules (built for one phone plus reinstalls):
//  - bestScore: the higher value wins.
//  - bestRuns: both lists combined, duplicates dropped, a dateless row
//    dropped when a dated row has the same score, sorted, top 10 kept.
//  - dayStats: per day, the record with more games wins (two phones playing
//    on the same day under-count; accepted).
//  - achievements, birdsPlayed: union.
//
import Foundation

enum CloudSync {
    private static let store = NSUbiquitousKeyValueStore.default
    private static var started = false

    /// Called when merged cloud data changed what is stored locally.
    static var onChange: (() -> Void)?

    /// Merges at launch and whenever iCloud delivers new data.
    static func start() {
        guard !started else {
            return
        }
        started = true

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in
            merge()
        }

        store.synchronize()
        merge()
    }

    /// Pulls cloud values into the phone, then writes back anything the
    /// cloud is missing. Writes only when something changed.
    static func merge() {
        let defaults = UserDefaults.standard
        var localChanged = false
        var cloudChanged = false

        // Best score
        let localBest = defaults.integer(forKey: "bestScore")
        let cloudBest = Int(store.longLong(forKey: "bestScore"))
        let best = max(localBest, cloudBest)
        if best != localBest { defaults.set(best, forKey: "bestScore"); localChanged = true }
        if best != cloudBest { store.set(Int64(best), forKey: "bestScore"); cloudChanged = true }

        // Best runs
        let localRuns = decodeRuns(defaults.data(forKey: "bestRuns"))
        let cloudRuns = decodeRuns(store.data(forKey: "bestRuns"))
        let runs = mergeRuns(localRuns, cloudRuns)
        if let data = try? JSONEncoder().encode(runs) {
            if runs != localRuns { defaults.set(data, forKey: "bestRuns"); localChanged = true }
            if runs != cloudRuns { store.set(data, forKey: "bestRuns"); cloudChanged = true }
        }

        // Day stats
        let localDays = GameStats.loadDays()
        let cloudDays = decodeDays(store.data(forKey: GameStats.daysKey))
        var days = localDays
        for (key, cloudDay) in cloudDays {
            if let localDay = days[key], localDay.games >= cloudDay.games {
                continue
            }
            days[key] = cloudDay
        }
        if days != localDays { GameStats.saveDays(days); localChanged = true }
        if days != cloudDays, let data = try? JSONEncoder().encode(days) {
            store.set(data, forKey: GameStats.daysKey); cloudChanged = true
        }

        // Sets
        for key in [Achievements.earnedKey, Achievements.birdsPlayedKey] {
            let local = Set(defaults.stringArray(forKey: key) ?? [])
            let cloud = Set(store.array(forKey: key) as? [String] ?? [])
            let union = local.union(cloud)
            if union != local { defaults.set(union.sorted(), forKey: key); localChanged = true }
            if union != cloud { store.set(union.sorted(), forKey: key); cloudChanged = true }
        }

        if cloudChanged {
            store.synchronize()
        }
        if localChanged {
            onChange?()
        }
    }

    // MARK: Helpers

    private static func decodeRuns(_ data: Data?) -> [BestRun] {
        guard let data, let runs = try? JSONDecoder().decode([BestRun].self, from: data) else {
            return []
        }
        return runs
    }

    private static func decodeDays(_ data: Data?) -> [String: DayStats] {
        guard let data, let days = try? JSONDecoder().decode([String: DayStats].self, from: data) else {
            return [:]
        }
        return days
    }

    static func mergeRuns(_ a: [BestRun], _ b: [BestRun]) -> [BestRun] {
        var runs: [BestRun] = []
        for run in a + b where !runs.contains(run) {
            runs.append(run)
        }

        let datedScores = Set(runs.filter { $0.date != nil }.map(\.score))
        runs.removeAll { $0.date == nil && datedScores.contains($0.score) }

        return Array(BestRuns.sorted(runs).prefix(BestRuns.keptCount))
    }
}
