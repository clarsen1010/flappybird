//
//  FriendsStore.swift
//  FlappyBird
//
//  The friends leaderboard's data: this player's name, the list of friends,
//  the last lists fetched, and the calls that publish and fetch scores.
//
//  One public record per player (see FriendsCloud). The record's name comes
//  from the player's iCloud account, so a reinstall or a new phone finds the
//  same record without anything being stored. What the phone keeps:
//  - friendsName: this player's name, as last confirmed by the server.
//  - friends: the record names of the people added. Also in the iCloud
//    key-value store (CloudSync), so a reinstall keeps the list.
//  - friendsCache: the last lists fetched, shown at once and when offline.
//  - friendsLastRound: when the last round ended ("last played").
//
//  Every completion is called on the main thread, exactly once.
//
import Foundation

enum FriendsError: Error, Equatable {
    /// Not signed in to iCloud (or iCloud is off for this app).
    case noAccount
    /// No connection, or the server is busy.
    case offline
    /// Anything else; the text goes to the play log.
    case failed(String)
}

/// What FriendsStore needs from the server.
protocol FriendsCloud {
    /// The signed-in player's own record name.
    func myID(_ done: @escaping (Result<String, FriendsError>) -> Void)
    /// The records that exist among `ids`; missing ones are left out.
    func fetch(ids: [String], _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void)
    /// The player with exactly this name, if any.
    func find(name: String, _ done: @escaping (Result<PlayerRow?, FriendsError>) -> Void)
    /// The highest all-time bests, best first.
    func top(_ count: Int, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void)
    /// Writes `row` over the record `row.id` (merged with what the server
    /// has, see FriendsLogic.merged). Answers false, writing nothing, when
    /// the record does not exist and `createIfMissing` is off.
    func save(_ row: PlayerRow, createIfMissing: Bool, _ done: @escaping (Result<Bool, FriendsError>) -> Void)
    func delete(id: String, _ done: @escaping (FriendsError?) -> Void)
}

enum FriendsStore {
    static var cloud: FriendsCloud = NoFriendsCloud()

    /// Shared with CloudSync, which keeps this list in iCloud too.
    static let friendsKey = "friends"
    static let everyoneCount = 10

    private static let nameKey = "friendsName"
    private static let idKey = "friendsMyID"
    private static let cacheKey = "friendsCache"
    private static let lastRoundKey = "friendsLastRound"
    private static let publishedKey = "friendsPublished"
    private static let askedKey = "friendsNameAsked"

    enum Status {
        case ok, loading, offline, noAccount
    }

    enum NameResult: Equatable {
        case ok, invalid(NameProblem), taken, noAccount, offline
    }

    enum AddResult: Equatable {
        case added, invalid, notFound, isYou, already, offline
    }

    private struct Cache: Codable {
        var friends: [PlayerRow] = []
        var everyone: [PlayerRow] = []
    }

    private(set) static var status = Status.ok
    private static var refreshWaiters: [() -> Void] = []
    private static var isPublishing = false

    private static var defaults: UserDefaults { .standard }

    // MARK: What the panels show

    static var myName: String? {
        defaults.string(forKey: nameKey)
    }

    private(set) static var myID: String? {
        get { defaults.string(forKey: idKey) }
        set { defaults.set(newValue, forKey: idKey) }
    }

    static var friendIDs: [String] {
        defaults.stringArray(forKey: friendsKey) ?? []
    }

    /// This player's row from the phone's own numbers, never stale.
    static func myRow() -> PlayerRow {
        let lastRound = defaults.object(forKey: lastRoundKey) as? Date
        let dayKey = lastRound.map(GameStats.dayFormatter.string(from:)) ?? ""

        return PlayerRow(
            id: myID ?? "",
            name: myName ?? "",
            best: ResultBoard.bestScore(),
            dayBest: GameStats.loadDays()[dayKey]?.best ?? 0,
            dayKey: dayKey,
            lastPlayed: lastRound
        )
    }

    /// The people added, from the last fetch (without this player).
    static func friendRows() -> [PlayerRow] {
        let ids = Set(friendIDs)
        return loadCache().friends.filter { ids.contains($0.id) && $0.id != myID }
    }

    /// The top of all time, from the last fetch.
    static func everyoneRows() -> [PlayerRow] {
        loadCache().everyone
    }

    /// True once: the first time the lists load fine and the player has no
    /// name yet, the panel asks for one.
    static func shouldAskForName() -> Bool {
        guard status == .ok, myName == nil, !defaults.bool(forKey: askedKey) else {
            return false
        }
        defaults.set(true, forKey: askedKey)
        return true
    }

    // MARK: Fetching

    /// Fetches this player's record, the friends' records and the top list.
    /// Calls made while a fetch is running join it.
    static func refresh(_ done: @escaping () -> Void) {
        refreshWaiters.append(done)
        guard refreshWaiters.count == 1 else {
            return
        }

        let cached = loadCache()
        if cached.friends.isEmpty && cached.everyone.isEmpty {
            status = .loading
        }

        cloud.myID { result in
            var signedIn = true

            switch result {
            case .success(let id):
                if id != myID {
                    // Another iCloud account: the name on this phone was the
                    // other account's.
                    if myID != nil { forgetProfile() }
                    myID = id
                }
            case .failure(.noAccount):
                // Lists can still be read without an account.
                signedIn = false
            case .failure(let error):
                return finishRefresh(failed: error)
            }

            let wanted = friendIDs + (signedIn ? [myID].compactMap { $0 } : [])

            cloud.fetch(ids: wanted) { result in
                guard case .success(let rows) = result else {
                    if case .failure(let error) = result { return finishRefresh(failed: error) }
                    return
                }

                if signedIn {
                    if let mine = rows.first(where: { $0.id == myID }) {
                        // The server decides the name (a reinstall, or a
                        // rename made on another phone).
                        defaults.set(mine.name, forKey: nameKey)
                    } else if myName != nil {
                        // The profile was deleted elsewhere.
                        forgetProfile()
                    }
                }

                cloud.top(everyoneCount) { result in
                    guard case .success(let top) = result else {
                        if case .failure(let error) = result { return finishRefresh(failed: error) }
                        return
                    }

                    saveCache(Cache(friends: rows.filter { $0.id != myID }, everyone: top))
                    status = signedIn ? .ok : .noAccount
                    GameLog.add("friends refresh ok: \(rows.count) of \(wanted.count) records, top \(top.count)")
                    finishRefresh()
                    publish()
                }
            }
        }
    }

    private static func finishRefresh(failed error: FriendsError? = nil) {
        if let error {
            status = error == .noAccount ? .noAccount : .offline
            GameLog.add("friends refresh failed: \(error)")
        }

        let waiters = refreshWaiters
        refreshWaiters = []
        waiters.forEach { $0() }
    }

    // MARK: Publishing

    /// Call when a round ends, after the scores are saved.
    static func roundEnded() {
        defaults.set(Date(), forKey: lastRoundKey)
        publish()
    }

    /// Sends this player's numbers when they changed since the last send.
    /// A failed send is simply tried again after the next round or fetch.
    private static func publish() {
        let row = myRow()

        guard myName != nil, !row.id.isEmpty, !isPublishing, row != lastPublished() else {
            return
        }

        isPublishing = true

        cloud.save(row, createIfMissing: false) { result in
            isPublishing = false

            switch result {
            case .success(true):
                setLastPublished(row)
                GameLog.add("friends publish ok")
            case .success(false):
                // The profile was deleted elsewhere; do not bring it back.
                forgetProfile()
                GameLog.add("friends publish: no profile on the server")
            case .failure(let error):
                GameLog.add("friends publish failed: \(error)")
            }
        }
    }

    // MARK: Name

    /// Claims or changes this player's name.
    static func setName(_ name: String, _ done: @escaping (NameResult) -> Void) {
        if let problem = NameRules.problem(name) {
            return done(.invalid(problem))
        }

        func finish(_ result: NameResult) {
            GameLog.add("friends set name: \(result)")
            done(result)
        }

        cloud.myID { result in
            guard case .success(let id) = result else {
                return finish(result == .failure(.noAccount) ? .noAccount : .offline)
            }

            myID = id

            cloud.find(name: name) { result in
                guard case .success(let holder) = result else {
                    return finish(.offline)
                }

                if let holder, holder.id != id {
                    return finish(.taken)
                }

                var row = myRow()
                row.name = name

                cloud.save(row, createIfMissing: true) { result in
                    guard case .success = result else {
                        return finish(.offline)
                    }

                    defaults.set(name, forKey: nameKey)
                    setLastPublished(row)
                    status = .ok
                    finish(.ok)
                }
            }
        }
    }

    /// Removes this player's name and scores from the server. The phone's
    /// own scores and the friends list stay.
    static func deleteProfile(_ done: @escaping (Bool) -> Void) {
        cloud.myID { result in
            guard case .success(let id) = result else {
                GameLog.add("friends delete failed: \(result)")
                return done(false)
            }

            cloud.delete(id: id) { error in
                if let error {
                    GameLog.add("friends delete failed: \(error)")
                    return done(false)
                }

                forgetProfile()
                var cache = loadCache()
                cache.everyone.removeAll { $0.id == id }
                saveCache(cache)
                GameLog.add("friends delete ok")
                done(true)
            }
        }
    }

    private static func forgetProfile() {
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: publishedKey)
    }

    // MARK: Friends

    /// Adds the player with exactly this name to the friends list.
    static func addFriend(name: String, _ done: @escaping (AddResult) -> Void) {
        func finish(_ result: AddResult) {
            GameLog.add("friends add: \(result)")
            done(result)
        }

        guard NameRules.problem(name) == nil else {
            return finish(.invalid)
        }

        guard name != myName else {
            return finish(.isYou)
        }

        cloud.find(name: name) { result in
            guard case .success(let found) = result else {
                return finish(.offline)
            }

            guard let found else {
                return finish(.notFound)
            }

            if found.id == myID {
                return finish(.isYou)
            }

            if friendIDs.contains(found.id) {
                return finish(.already)
            }

            defaults.set(friendIDs + [found.id], forKey: friendsKey)
            var cache = loadCache()
            cache.friends.removeAll { $0.id == found.id }
            cache.friends.append(found)
            saveCache(cache)
            CloudSync.merge()
            finish(.added)
        }
    }

    // MARK: Storage

    private static func loadCache() -> Cache {
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return Cache()
        }
        return cache
    }

    private static func saveCache(_ cache: Cache) {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private static func lastPublished() -> PlayerRow? {
        guard let data = defaults.data(forKey: publishedKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PlayerRow.self, from: data)
    }

    private static func setLastPublished(_ row: PlayerRow) {
        if let data = try? JSONEncoder().encode(row) {
            defaults.set(data, forKey: publishedKey)
        }
    }
}

/// Stands in until the iCloud database is set up: every call fails.
private struct NoFriendsCloud: FriendsCloud {
    private let error = FriendsError.failed("no server set up")

    func myID(_ done: @escaping (Result<String, FriendsError>) -> Void) { done(.failure(error)) }
    func fetch(ids: [String], _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void) { done(.failure(error)) }
    func find(name: String, _ done: @escaping (Result<PlayerRow?, FriendsError>) -> Void) { done(.failure(error)) }
    func top(_ count: Int, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void) { done(.failure(error)) }
    func save(_ row: PlayerRow, createIfMissing: Bool, _ done: @escaping (Result<Bool, FriendsError>) -> Void) { done(.failure(error)) }
    func delete(id: String, _ done: @escaping (FriendsError?) -> Void) { done(error) }
}
