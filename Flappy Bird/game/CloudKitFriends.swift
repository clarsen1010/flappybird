//
//  CloudKitFriends.swift
//  FlappyBird
//
//  The friends leaderboard's server: the public iCloud database of this
//  app's own container. One "Player" record per iCloud account, readable by
//  everyone, writable only by the account that made it (CloudKit's rule for
//  public records). It holds the name, the scores and the record names of
//  the people that player added. Nothing here is secret; access comes from the app's
//  signature and the player's iCloud sign-in.
//
//  Every call is user-initiated and gives up after ten seconds. CloudKit's
//  defaults are a low-priority request with a one-minute timeout that waits
//  in Low Power Mode, and the panels keep their buttons locked while a
//  request is out.
//
import CloudKit

struct CloudKitFriends: FriendsCloud {
    static let containerID = "iCloud.com.clarsen1010.flappybird"

    private static let recordType = "Player"
    private static let fields = ["name", "best", "dayBest", "dayKey", "lastPlayed"]
    /// CloudKit takes at most 400 records in one request.
    private static let fetchLimit = 300
    private static let addedMeLimit = 100

    private static var configuration: CKOperation.Configuration {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        return configuration
    }

    // MARK: FriendsCloud

    func myID(_ done: @escaping (Result<String, FriendsError>) -> Void) {
        run(done) {
            let container = CKContainer(identifier: Self.containerID)

            return try await container.configuredWith(configuration: Self.configuration) { container in
                // Anything but a usable account reads as "no account": the
                // lists can still be fetched without one.
                guard try await container.accountStatus() == .available else {
                    throw FriendsError.noAccount
                }

                // The same on every phone and after a reinstall, so nothing
                // has to be stored to find the record again.
                return "player" + (try await container.userRecordID()).recordName
            }
        }
    }

    func fetch(ids: [String], _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void) {
        run(done) {
            let recordIDs = ids.prefix(Self.fetchLimit).map { CKRecord.ID(recordName: $0) }

            guard !recordIDs.isEmpty else {
                return []
            }

            return try await Self.database { database in
                let results = try await database.records(for: recordIDs, desiredKeys: Self.fields)

                return try results.values.compactMap { result in
                    switch result {
                    case .success(let record):
                        return Self.row(record)
                    case .failure(let error as CKError) where error.code == .unknownItem:
                        // No such player (any more).
                        return nil
                    case .failure(let error):
                        // Not "missing": the caller treats a missing own
                        // record as a deleted profile.
                        throw error
                    }
                }
            }
        }
    }

    func find(name: String, _ done: @escaping (Result<PlayerRow?, FriendsError>) -> Void) {
        run(done) {
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "name == %@", name))
            // Two players can hold one name only if both claimed it in the
            // same moment; the lower record name wins everywhere.
            return try await Self.query(query, limit: 2).min { $0.id < $1.id }
        }
    }

    func addedMe(id: String, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void) {
        run(done) {
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "friends CONTAINS %@", id))
            return try await Self.query(query, limit: Self.addedMeLimit)
        }
    }

    func top(_ count: Int, _ done: @escaping (Result<[PlayerRow], FriendsError>) -> Void) {
        run(done) {
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "best > 0"))
            query.sortDescriptors = [NSSortDescriptor(key: "best", ascending: false)]
            return FriendsLogic.sorted(try await Self.query(query, limit: count))
        }
    }

    func save(_ row: PlayerRow, friends: [String], removed: [String], claimingName: Bool, _ done: @escaping (Result<Bool, FriendsError>) -> Void) {
        run(done) {
            try await Self.database { database in
                let recordID = CKRecord.ID(recordName: row.id)
                let record: CKRecord
                var values = row
                var allFriends = friends

                do {
                    record = try await database.record(for: recordID)

                    // The server's list is kept too: a phone whose own list
                    // has not arrived yet (a reinstall) must not empty it.
                    // Only the players removed on purpose are left out.
                    allFriends = FriendsLogic.serverFriends(
                        local: friends,
                        server: record["friends"] as? [String] ?? [],
                        removed: Set(removed)
                    )

                    if let server = Self.row(record) {
                        values = FriendsLogic.merged(server: server, local: row)
                        if claimingName {
                            values.name = row.name
                        }
                    }
                } catch let error as CKError where error.code == .unknownItem {
                    guard claimingName else {
                        return false
                    }
                    record = CKRecord(recordType: Self.recordType, recordID: recordID)
                }

                record["name"] = values.name
                record["best"] = values.best
                record["dayBest"] = values.dayBest
                record["dayKey"] = values.dayKey
                record["lastPlayed"] = values.lastPlayed
                // CloudKit has no empty lists; none means no field.
                record["friends"] = allFriends.isEmpty ? nil : allFriends

                // Refused if another phone saved in between; the next round
                // publishes again.
                let (saved, _) = try await database.modifyRecords(
                    saving: [record],
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: true
                )
                _ = try saved[recordID]?.get()
                return true
            }
        }
    }

    func delete(id: String, _ done: @escaping (FriendsError?) -> Void) {
        run({ (result: Result<Void, FriendsError>) in
            if case .failure(let error) = result {
                done(error)
            } else {
                done(nil)
            }
        }) {
            try await Self.database { database in
                let recordID = CKRecord.ID(recordName: id)

                do {
                    let (_, deleted) = try await database.modifyRecords(saving: [], deleting: [recordID])
                    _ = try deleted[recordID]?.get()
                } catch let error as CKError where error.code == .unknownItem {
                    // Already gone.
                }
            }
        }
    }

    // MARK: Helpers

    /// Runs `work` off the main thread and answers on it, once.
    private func run<T>(_ done: @escaping (Result<T, FriendsError>) -> Void, _ work: @escaping () async throws -> T) {
        Task {
            let result: Result<T, FriendsError>

            do {
                result = .success(try await work())
            } catch {
                result = .failure(Self.friendsError(error))
            }

            await MainActor.run {
                done(result)
            }
        }
    }

    private static func database<T>(_ body: @escaping @Sendable (CKDatabase) async throws -> T) async throws -> T {
        try await CKContainer(identifier: containerID).publicCloudDatabase
            .configuredWith(configuration: configuration, body: body)
    }

    /// A record type nobody has saved to yet does not exist on the server;
    /// a query on it means "no players", not a failure.
    private static func query(_ query: CKQuery, limit: Int) async throws -> [PlayerRow] {
        try await database { database in
            do {
                let (matches, _) = try await database.records(matching: query, desiredKeys: fields, resultsLimit: limit)
                return matches.compactMap { try? $0.1.get() }.compactMap(row)
            } catch let error as CKError where error.code == .unknownItem {
                return []
            }
        }
    }

    private static func row(_ record: CKRecord) -> PlayerRow? {
        guard let name = record["name"] as? String else {
            return nil
        }

        return PlayerRow(
            id: record.recordID.recordName,
            name: name,
            best: record["best"] as? Int ?? 0,
            dayBest: record["dayBest"] as? Int ?? 0,
            dayKey: record["dayKey"] as? String ?? "",
            lastPlayed: record["lastPlayed"] as? Date
        )
    }

    private static func friendsError(_ error: Error) -> FriendsError {
        if let error = error as? FriendsError {
            return error
        }

        guard let error = error as? CKError else {
            return .failed("\(error)")
        }

        switch error.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .noAccount
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .serverResponseLost:
            return .offline
        default:
            return .failed("CKError \(error.code.rawValue)")
        }
    }
}
