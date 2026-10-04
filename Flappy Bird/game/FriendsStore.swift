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
//    key-value store (CloudSync), so a reinstall keeps the list, and on the
//    player's public record, so the people added can see who added them.
//  - friendsMarks: who was removed from that list, and when (the list
//    itself only grows; see FriendsLogic). In the key-value store too.
//  - friendsSeenAdded: the people who added this player that this phone
//    has already shown, for the "new" count on the menu button.
//  - friendsCache: the last lists fetched, shown at once and when offline.
//  - friendsLastRound: when the last round ended ("last played").
//  - friendsLastNormalRound: when the last NORMAL round ended. The day,
//    week and month scores belong to the normal game, so their period
//    comes from this one.
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
    /// One board of the EVERYONE list, best first, at most `limit` players:
    /// the players whose day, week or month is `key` (their score that
    /// period), or for all time the highest bests.
    /// A hard `mode` has one board, all time: its highest bests.
    func board(_ scope: BoardScope, mode: GameMode, key: String, limit: Int, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void)
    /// The players whose friends list holds `id`.
    func addedMe(id: String, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void)
    /// Writes `row` and the friends list to the record `row.id`. Publishing scores
    /// (`claimingName` off) merges with what the server has, keeps the
    /// server's name (see FriendsLogic.merged) and answers false, writing
    /// nothing, when the record does not exist. Claiming a name writes the
    /// name too and creates the record when missing.
    /// `removed` are the players taken off the friends list: they are left
    /// out of the stored list even if the server still has them.
    func save(_ row: PlayerRow, friends: [String], removed: [String], claimingName: Bool, _ done: @escaping (Result<Bool, FriendsError>) -> Void)
    func delete(id: String, _ done: @escaping (FriendsError?) -> Void)
}

enum FriendsStore {
    static var cloud: FriendsCloud = CloudKitFriends()

    /// Shared with CloudSync, which keeps this list in iCloud too.
    static let friendsKey = "friends"
    /// Shared with CloudSync too: JSON of FriendsLogic.Marks.
    static let marksKey = "friendsMarks"
    /// Shown on a board; more are fetched so a player further down can be
    /// told their place.
    static let everyoneCount = 10
    static let boardFetchLimit = 100

    private static let nameKey = "friendsName"
    private static let idKey = "friendsMyID"
    private static let cacheKey = "friendsCache"
    private static let lastRoundKey = "friendsLastRound"
    private static let lastNormalRoundKey = "friendsLastNormalRound"
    /// Set once the date from before the hard modes has been taken over
    /// as the last normal round's (or there was none to take).
    private static let normalRoundSortedKey = "friendsNormalRoundSorted"
    private static let publishedKey = "friendsPublished"
    private static let askedKey = "friendsNameAsked"
    private static let seenAddedKey = "friendsSeenAdded"

    enum Status {
        case ok, loading, offline, noAccount
    }

    enum NameResult: Equatable {
        case ok, invalid(NameProblem), taken, noAccount, offline, failed
    }

    enum BoardState {
        case loading, ok, offline, failed
    }

    /// A board as last fetched. `key` is the day, week or month it was
    /// fetched for: last week's board is never shown as this week's.
    private struct Board {
        var key: String
        var rows: [PlayerRow]
        var state: BoardState
    }

    /// Today, week and month live only as long as the app runs; all time
    /// is also kept in the cache.
    private static var boards: [String: Board] = [:]

    /// The hard modes have one board each, all time.
    private static func boardID(_ scope: BoardScope, _ mode: GameMode) -> (id: String, scope: BoardScope) {
        mode == .normal ? (scope.rawValue, scope) : (mode.rawValue, .all)
    }

    enum AddResult: Equatable {
        case added, invalid, notFound, isYou, already, offline, failed
    }

    private struct Cache: Codable {
        var friends: [PlayerRow] = []
        var addedMe: [PlayerRow] = []
        var everyone: [PlayerRow] = []
    }

    /// What was last sent, to skip sending the same again.
    private struct Published: Codable, Equatable {
        var row: PlayerRow
        var friends: [String]
    }

    private(set) static var status = Status.ok
    /// True while a name, add or delete request is waiting for the server.
    private(set) static var isBusy = false
    private static var refreshWaiters: [() -> Void] = []
    private static var isPublishing = false
    /// Something changed while a send was out; send again when it is back.
    private static var publishAgain = false
    /// Counts name changes made on this phone, so a fetch that started
    /// before one does not undo it when its (older) answer arrives.
    private static var nameChanges = 0

    private static var defaults: UserDefaults { .standard }

    // MARK: What the panels show

    static var myName: String? {
        defaults.string(forKey: nameKey)
    }

    private(set) static var myID: String? {
        get { defaults.string(forKey: idKey) }
        set { defaults.set(newValue, forKey: idKey) }
    }

    /// The friends list as the player sees it: everyone added, without
    /// the ones removed since.
    static var friendIDs: [String] {
        FriendsLogic.effectiveFriends(rawFriendIDs, marks: marks)
    }

    /// Everyone ever added; this list only grows.
    private static var rawFriendIDs: [String] {
        defaults.stringArray(forKey: friendsKey) ?? []
    }

    static func decodeMarks(_ data: Data?) -> FriendsLogic.Marks {
        data.flatMap { try? JSONDecoder().decode(FriendsLogic.Marks.self, from: $0) } ?? [:]
    }

    private static var marks: FriendsLogic.Marks {
        get { decodeMarks(defaults.data(forKey: marksKey)) }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: marksKey) }
    }

    /// This player's row from the phone's own numbers, never stale.
    static func myRow() -> PlayerRow {
        let lastRound = defaults.object(forKey: lastRoundKey) as? Date
        // The day whose score is published: the last NORMAL round's. A
        // phone updated from 5.2 has only the one date, from normal rounds,
        // until its first round on 5.3 sorts that out.
        let fromBefore = defaults.bool(forKey: normalRoundSortedKey) ? nil : lastRound
        let lastNormalRound = defaults.object(forKey: lastNormalRoundKey) as? Date ?? fromBefore
        let dayKey = lastNormalRound.map(GameStats.dayFormatter.string(from:)) ?? ""

        let days = GameStats.loadDays().mapValues(\.best)
        // The week and the month of the last round, like the day.
        let period = FriendsLogic.periodBests(days: days, anchorDayKey: dayKey)

        var row = PlayerRow(
            id: myID ?? "",
            name: myName ?? "",
            best: ResultBoard.bestScore(),
            dayBest: days[dayKey] ?? 0,
            dayKey: dayKey,
            lastPlayed: lastRound,
            weekKey: period.weekKey.isEmpty ? nil : period.weekKey,
            weekBest: period.weekKey.isEmpty ? nil : period.weekBest,
            monthKey: period.monthKey.isEmpty ? nil : period.monthKey,
            monthBest: period.monthKey.isEmpty ? nil : period.monthBest
        )
        for mode in [GameMode.hard, .insane, .impossible] {
            row.setBest(ResultBoard.best(mode: mode), mode)
        }
        return row
    }

    /// The people added, from the last fetch (without this player).
    static func friendRows() -> [PlayerRow] {
        let ids = Set(friendIDs)
        return loadCache().friends.filter { ids.contains($0.id) && $0.id != myID }
    }

    /// The people who added this player and are not on the friends list
    /// (yet), from the last fetch.
    static func addedYouRows() -> [PlayerRow] {
        let ids = Set(friendIDs)
        return loadCache().addedMe.filter { !ids.contains($0.id) && $0.id != myID }
    }

    /// For the Game Over card: the friend just ahead of this player's best
    /// in `mode` and the points that pass them, from the last fetch.
    static func chaseTarget(mode: GameMode) -> (name: String, points: Int)? {
        FriendsLogic.chaseTarget(friends: friendRows(), mode: mode, myBest: ResultBoard.best(mode: mode))
    }

    /// Friends who added this player too, from the last fetch.
    static func mutualIDs() -> Set<String> {
        FriendsLogic.mutualIDs(friends: friendIDs, addedMe: loadCache().addedMe.map(\.id))
    }

    // MARK: Who added you, and who is new

    /// Nil until this phone has a baseline: nobody counts as new before.
    private static var seenAdded: Set<String>? {
        get { defaults.stringArray(forKey: seenAddedKey).map(Set.init) }
        set { defaults.set(newValue?.sorted(), forKey: seenAddedKey) }
    }

    /// How many people waiting on ADDED YOU this phone has not shown yet.
    static func unseenAddedCount() -> Int {
        guard let seen = seenAdded else {
            return 0
        }
        return FriendsLogic.unseen(waiting: addedYouRows().map(\.id), seen: seen).count
    }

    /// The ADDED YOU list was looked at.
    static func markAddedSeen() {
        guard let seen = seenAdded else {
            return
        }
        let all = seen.union(loadCache().addedMe.map(\.id))
        if all != seen {
            seenAdded = all
        }
    }

    // MARK: Boards

    /// The viewer's current day, week or month key; empty for all time.
    static func boardKey(_ scope: BoardScope, now: Date = Date()) -> String {
        let today = GameStats.dayFormatter.string(from: now)

        switch scope {
        case .today: return today
        case .week: return FriendsLogic.weekKey(dayKey: today)
        case .month: return FriendsLogic.monthKey(dayKey: today)
        case .all: return ""
        }
    }

    /// This player's score on a board right now, from the phone's numbers.
    private static func myBoardValue(_ scope: BoardScope, mode: GameMode, now: Date) -> Int {
        guard mode == .normal else {
            return ResultBoard.best(mode: mode)
        }

        let days = GameStats.loadDays().mapValues(\.best)
        let today = GameStats.dayFormatter.string(from: now)

        switch scope {
        case .today: return days[today] ?? 0
        case .week: return FriendsLogic.periodBests(days: days, anchorDayKey: today).weekBest
        case .month: return FriendsLogic.periodBests(days: days, anchorDayKey: today).monthBest
        case .all: return ResultBoard.bestScore()
        }
    }

    /// A board as the panel draws it, from the last fetch.
    static func boardView(_ scope: BoardScope, mode: GameMode = .normal, now: Date = Date()) -> (top: [BoardEntry], you: BoardEntry?, youRankKnown: Bool, state: BoardState) {
        let (id, scope) = boardID(scope, mode)
        let key = boardKey(scope, now: now)
        let fetched = boards[id].flatMap { $0.key == key ? $0 : nil }
        let rows = fetched?.rows ?? (id == BoardScope.all.rawValue ? loadCache().everyone : [])

        // Only a player with a name is on the server at all.
        var me: (id: String, name: String, value: Int)?
        if let id = myID, let name = myName {
            me = (id, name, myBoardValue(scope, mode: mode, now: now))
        }

        let board = FriendsLogic.board(
            rows: rows,
            scope: scope,
            key: key,
            mode: mode,
            me: me,
            shown: everyoneCount,
            fetchedAll: rows.count < boardFetchLimit
        )
        return (board.top, board.you, board.youRankKnown, fetched?.state ?? .loading)
    }

    /// False once the day, week or month the board was fetched for is
    /// over (or it was never fetched): it then shows LOADING until asked
    /// for again.
    static func boardIsCurrent(_ scope: BoardScope, mode: GameMode = .normal, now: Date = Date()) -> Bool {
        let (id, scope) = boardID(scope, mode)
        return boards[id]?.key == boardKey(scope, now: now)
    }

    /// Fetches one board. A board that fails says so on its own: the
    /// friends lists and the other boards are untouched. Does nothing,
    /// and never calls back, while that board is already being fetched.
    static func loadBoard(_ scope: BoardScope, mode: GameMode = .normal, now: Date = Date(), _ done: @escaping () -> Void) {
        let (id, scope) = boardID(scope, mode)
        let key = boardKey(scope, now: now)
        let isAllTime = id == BoardScope.all.rawValue

        if let board = boards[id], board.key == key, board.state == .loading {
            return
        }

        let known = boards[id].flatMap { $0.key == key ? $0.rows : nil } ?? (isAllTime ? loadCache().everyone : [])
        boards[id] = Board(key: key, rows: known, state: .loading)

        cloud.board(scope, mode: mode, key: key, limit: boardFetchLimit) { result in
            // Another account, or a new day, since this was asked.
            guard boards[id]?.key == key else {
                return done()
            }

            switch result {
            case .success(let rows):
                boards[id] = Board(key: key, rows: rows, state: .ok)
                if isAllTime {
                    var cache = loadCache()
                    cache.everyone = rows
                    saveCache(cache)
                }
            case .failure(let error):
                boards[id]?.state = error == .offline ? .offline : .failed
                GameLog.add("board \(id) failed: \(error)")
            }

            done()
        }
    }

    /// The first time the lists load fine and the player has no name yet,
    /// the panel asks for one. Call askedForName() once the prompt is up.
    static func shouldAskForName() -> Bool {
        status == .ok && myName == nil && !defaults.bool(forKey: askedKey)
    }

    static func askedForName() {
        defaults.set(true, forKey: askedKey)
    }

    // MARK: Fetching

    /// Fetches this player's record, the friends' records and who added
    /// this player. Calls made while a fetch is running join it. The
    /// EVERYONE boards are fetched on their own (loadBoard).
    static func refresh(_ done: @escaping () -> Void) {
        refreshWaiters.append(done)
        guard refreshWaiters.count == 1 else {
            return
        }

        let cached = loadCache()
        if status == .offline || (cached.friends.isEmpty && cached.everyone.isEmpty) {
            status = .loading
        }

        let nameChangesAtStart = nameChanges

        cloud.myID { result in
            var signedIn = true

            switch result {
            case .success(let id):
                adoptID(id)
            case .failure(.noAccount):
                // Lists can still be read without an account.
                signedIn = false
            case .failure(let error):
                return finishRefresh(failed: error)
            }

            // Who was already listed as having added this player, if this
            // phone has a list at all. Read after adoptID: another account's
            // list is gone by now.
            let listedBefore = defaults.data(forKey: cacheKey) != nil ? loadCache().addedMe : nil

            // Own record first, so it is never the one cut off by the
            // server's limit; no id twice.
            var wanted = signedIn ? [myID].compactMap { $0 } : []
            for id in friendIDs where !wanted.contains(id) {
                wanted.append(id)
            }

            cloud.fetch(ids: wanted) { result in
                guard case .success(let rows) = result else {
                    if case .failure(let error) = result { return finishRefresh(failed: error) }
                    return
                }

                if signedIn && nameChanges == nameChangesAtStart {
                    if let mine = rows.first(where: { $0.id == myID }) {
                        // The server decides the name (a reinstall, or a
                        // rename made on another phone).
                        defaults.set(mine.name, forKey: nameKey)
                    } else if myName != nil {
                        // The profile was deleted elsewhere.
                        forgetProfile()
                    }
                }

                // Who added this player: only a signed-in player has an id
                // to look for.
                let lookFor = signedIn ? myID : nil

                addedMe(id: lookFor) { result in
                    guard case .success(let added) = result else {
                        if case .failure(let error) = result { return finishRefresh(failed: error) }
                        return
                    }

                    do {
                        // Friends added while this fetch was out were not
                        // asked for; keep their rows.
                        var cache = loadCache()
                        let addedMeanwhile = cache.friends.filter { !wanted.contains($0.id) }
                        cache.friends = rows.filter { $0.id != myID } + addedMeanwhile
                        cache.addedMe = added
                        saveCache(cache)
                        // The first answer about who added this player sets
                        // what counts as already seen: the list last shown
                        // (an update from 5.2), or else everyone waiting now
                        // (a new phone must not call them all new).
                        if lookFor != nil, seenAdded == nil {
                            seenAdded = Set((listedBefore ?? added).map(\.id))
                        }

                        status = signedIn ? .ok : .noAccount
                        GameLog.add("friends refresh ok: \(rows.count) of \(wanted.count) records, added me \(added.count)")
                        finishRefresh()
                        publish()
                    }
                }
            }
        }
    }

    private static var lastBadgeCheck: Date?

    /// For the count on the menu's Friends button: fetches the lists when
    /// the player has a name (nothing is asked for anyone who never joined
    /// the board), at most once in ten minutes. Answers false, without
    /// calling back later, when it does not fetch.
    @discardableResult
    static func refreshForBadge(now: Date = Date(), _ done: @escaping () -> Void) -> Bool {
        guard myName != nil, now.timeIntervalSince(lastBadgeCheck ?? .distantPast) >= 600 else {
            return false
        }
        lastBadgeCheck = now
        refresh(done)
        return true
    }

    private static func addedMe(id: String?, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void) {
        guard let id else {
            return done(.success([]))
        }
        cloud.addedMe(id: id, done)
    }

    /// Records the signed-in player's record name. A different one means
    /// another iCloud account: the name, friends and lists on this phone
    /// were the other account's.
    private static func adoptID(_ id: String) {
        guard id != myID else {
            return
        }

        if myID != nil {
            forgetProfile()
            for key in [cacheKey, friendsKey, marksKey, seenAddedKey] {
                defaults.removeObject(forKey: key)
            }
            boards = [:]
        }

        myID = id
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
    static func roundEnded(mode: GameMode) {
        let now = Date()

        // Once, on the first round with hard modes in the game: the date
        // kept so far (if any) was a normal round's. After this a hard
        // round's date can never pass for one.
        if !defaults.bool(forKey: normalRoundSortedKey) {
            if defaults.object(forKey: lastNormalRoundKey) == nil, let before = defaults.object(forKey: lastRoundKey) {
                defaults.set(before, forKey: lastNormalRoundKey)
            }
            defaults.set(true, forKey: normalRoundSortedKey)
        }

        if mode == .normal {
            defaults.set(now, forKey: lastNormalRoundKey)
        }

        defaults.set(now, forKey: lastRoundKey)
        publish()
    }

    /// Sends this player's numbers and friends list when they changed since
    /// the last send. A failed send is simply tried again after the next
    /// round or fetch.
    private static func publish() {
        let row = myRow()
        let sending = Published(row: row, friends: friendIDs)

        guard myName != nil, !row.id.isEmpty, status != .noAccount, sending != lastPublished() else {
            return
        }

        guard !isPublishing else {
            publishAgain = true
            return
        }

        isPublishing = true

        cloud.save(row, friends: sending.friends, removed: removedIDs, claimingName: false) { result in
            isPublishing = false
            defer {
                if publishAgain {
                    publishAgain = false
                    publish()
                }
            }

            switch result {
            case .success(true):
                setLastPublished(sending)
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
            isBusy = false
            GameLog.add("friends set name: \(result)")
            done(result)
        }

        isBusy = true

        func failure<T>(_ result: Result<T, FriendsError>) -> NameResult {
            switch result {
            case .failure(.noAccount): return .noAccount
            case .failure(.offline): return .offline
            default: return .failed
            }
        }

        cloud.myID { result in
            guard case .success(let id) = result else {
                return finish(failure(result))
            }

            adoptID(id)

            cloud.find(name: name) { result in
                guard case .success(let holder) = result else {
                    return finish(failure(result))
                }

                if let holder, holder.id != id {
                    return finish(.taken)
                }

                var row = myRow()
                row.name = name
                let sending = Published(row: row, friends: friendIDs)

                cloud.save(row, friends: sending.friends, removed: removedIDs, claimingName: true) { result in
                    guard case .success = result else {
                        return finish(failure(result))
                    }

                    nameChanges += 1
                    defaults.set(name, forKey: nameKey)
                    setLastPublished(sending)
                    finish(.ok)
                }
            }
        }
    }

    /// Removes this player's name and scores from the server. The phone's
    /// own scores and the friends list stay.
    static func deleteProfile(_ done: @escaping (FriendsError?) -> Void) {
        func finish(_ error: FriendsError?) {
            isBusy = false
            GameLog.add("friends delete: \(error.map { "failed, \($0)" } ?? "ok")")
            done(error)
        }

        isBusy = true

        cloud.myID { result in
            guard case .success(let id) = result else {
                if case .failure(let error) = result { finish(error) }
                return
            }

            adoptID(id)

            cloud.delete(id: id) { error in
                if let error {
                    return finish(error)
                }

                nameChanges += 1
                forgetProfile()
                var cache = loadCache()
                cache.everyone.removeAll { $0.id == id }
                saveCache(cache)
                for board in boards.keys {
                    boards[board]?.rows.removeAll { $0.id == id }
                }
                finish(nil)
            }
        }
    }

    /// No name any more (deleted here or elsewhere, or another account):
    /// the next visit to the friends panel asks for one again, once.
    private static func forgetProfile() {
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: publishedKey)
        defaults.removeObject(forKey: askedKey)
    }

    // MARK: Friends

    /// Adds the player with exactly this name to the friends list.
    static func addFriend(name: String, _ done: @escaping (AddResult) -> Void) {
        func finish(_ result: AddResult) {
            isBusy = false
            GameLog.add("friends add: \(result)")
            done(result)
        }

        guard NameRules.problem(name) == nil else {
            return finish(.invalid)
        }

        guard name != myName else {
            return finish(.isYou)
        }

        isBusy = true

        cloud.find(name: name) { result in
            guard case .success(let found) = result else {
                return finish(result == .failure(.offline) ? .offline : .failed)
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

            keep(found)
            finish(.added)
        }
    }

    /// Adds someone from the ADDED YOU list. No lookup is needed: the row
    /// is already here.
    static func addBack(_ row: PlayerRow) {
        guard !friendIDs.contains(row.id), row.id != myID else {
            return
        }

        keep(row)
        GameLog.add("friends add back")
    }

    /// Takes a friend off the list. They are not told, but the list on
    /// this player's record no longer names them.
    static func removeFriend(_ friend: PlayerRow) {
        guard friendIDs.contains(friend.id) else {
            return
        }

        marks = FriendsLogic.remove(friend.id, now: Date().timeIntervalSince1970, marks)

        var cache = loadCache()
        cache.friends.removeAll { $0.id == friend.id }
        saveCache(cache)

        // If they added this player, they are back on ADDED YOU: not news.
        if let seen = seenAdded {
            seenAdded = seen.union([friend.id])
        }

        CloudSync.merge()
        // Always sent: another of the player's phones may have added this
        // friend, so the list last sent from here can look unchanged.
        defaults.removeObject(forKey: publishedKey)
        publish()
        GameLog.add("friends remove")
    }

    private static var removedIDs: [String] {
        FriendsLogic.removedIDs(marks).sorted()
    }

    private static func keep(_ friend: PlayerRow) {
        if !rawFriendIDs.contains(friend.id) {
            defaults.set(rawFriendIDs + [friend.id], forKey: friendsKey)
        }
        marks = FriendsLogic.readd(friend.id, now: Date().timeIntervalSince1970, marks)
        if let seen = seenAdded {
            seenAdded = seen.union([friend.id])
        }
        var cache = loadCache()
        cache.friends.removeAll { $0.id == friend.id }
        cache.friends.append(friend)
        saveCache(cache)
        CloudSync.merge()
        // The friends list on the server is how they see who added them.
        publish()
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

    private static func lastPublished() -> Published? {
        guard let data = defaults.data(forKey: publishedKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Published.self, from: data)
    }

    private static func setLastPublished(_ sent: Published) {
        if let data = try? JSONEncoder().encode(sent) {
            defaults.set(data, forKey: publishedKey)
        }
    }
}
