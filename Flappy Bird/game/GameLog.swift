//
//  GameLog.swift
//  FlappyBird
//
//  Play log for the beta (Settings > Logs, on by default in beta builds): taps and how late
//  they arrived, flaps, points, slow frames, and where the bird and the pipe
//  were at each death. It exists to answer "did the game do that, or did I?"
//  with numbers.
//
//  During a round it only appends short lines to memory. Nothing touches the
//  disk, the system log or the audio session while the bird is flying: the
//  per-sound logging of 9/29 cost 33 ms a point. The file is written between
//  rounds and when the app leaves the screen, on a background queue.
//
//  The file is Documents/flappy-log.txt, visible in the Files app under
//  On My iPhone > Blappy Fird. Nothing is sent anywhere.
//
import Metal
import MetricKit
import SpriteKit
import UIKit

enum GameLog {
    static let settingKey = "logs"
    static let fileName = "flappy-log.txt"
    private static let oldFileName = "flappy-log-old.txt"

    /// Past this the file is renamed to flappy-log-old.txt and a new one starts.
    private static let maxFileBytes: UInt64 = 1_000_000

    /// A frame longer than this gets its own line (120 Hz is 8 ms, 60 Hz 17 ms).
    static let slowFrame: TimeInterval = 0.025
    private static let slowLinesPerRound = 60

    private static let writer = DispatchQueue(label: "flappybird.gamelog", qos: .utility)
    private static let launchTime = CACurrentMediaTime()

    private(set) static var enabled = true
    private static var started = false
    private static var lines: [String] = []

    // Per-round frame and tap numbers. Frame gaps are measured on the real
    // clock: the time SpriteKit passes to update() is the frame's scheduled
    // time, which stays perfectly even when the callback itself runs late.
    private static let bucketLimits: [Double] = [0.005, 0.007, 0.009, 0.011, 0.013, 0.018, 0.025, 0.034, 0.050, 0.100]
    private static let bucketNames = ["<=5", "<=7", "<=9", "<=11", "<=13", "<=18", "<=25", "<=34", "<=50", "<=100", ">100"]
    private static var buckets = [Int](repeating: 0, count: 11)
    private static var frames = 0
    private static var frameTime: TimeInterval = 0
    private static var worstFrame: TimeInterval = 0
    private static var gapBefore: TimeInterval = 0
    /// How long before its scheduled time each update started, at worst.
    private static var leastLead: TimeInterval = .infinity
    private static var slowLines = 0
    private static var taps = 0
    private static var lagTotal: TimeInterval = 0
    private static var worstLag: TimeInterval = 0
    private static var round = 0

    /// Frames the screen really received, counted by GameView's layer. The
    /// frame timer above cannot see a frame that was simulated but not drawn.
    static var drawnFrames = 0
    private static var drawnAtLastFrame = 0
    private static var notDrawn = 0
    private static let notDrawnLinesPerRound = 80

    /// Frames in which the flying bird did not move at all (physics ran no
    /// step that frame), counted by GameScene.
    static var stuckFrames = 0

    // What reached the glass: the time each drawn frame was really shown,
    // reported by the system on its own thread (hence the lock).
    private static let shownLock = NSLock()
    private static var shownCounting = false
    private static var shownLast: CFTimeInterval = 0
    private static var shownCount = 0
    private static var shownDropped = 0
    private static var shownLongest: CFTimeInterval = 0
    private static let shownLimits: [Double] = [0.009, 0.013, 0.018, 0.026, 0.034, 0.051]
    private static let shownNames = ["<=9", "<=13", "<=18", "<=26", "<=34", "<=51", ">51"]
    private static var shownBuckets = [Int](repeating: 0, count: 7)

    /// Called for every frame handed to the screen; `time` is 0 for one the
    /// system dropped without showing.
    static func shown(at time: CFTimeInterval) {
        shownLock.lock()
        defer { shownLock.unlock() }
        guard shownCounting else {
            return
        }
        guard time > 0 else {
            shownDropped += 1
            return
        }
        if shownLast > 0, time > shownLast {
            let gap = time - shownLast
            shownLongest = max(shownLongest, gap)
            shownBuckets[shownLimits.firstIndex { gap <= $0 } ?? shownLimits.count] += 1
        }
        shownLast = time
        shownCount += 1
    }

    /// Counting stops at death and while paused, and a new chain of gaps
    /// starts on resume: the time away is not a frame gap.
    static func shownLive(_ live: Bool) {
        shownLock.lock()
        shownCounting = live
        shownLast = 0
        shownLock.unlock()
    }

    private static func resetShown(counting: Bool) {
        shownLock.lock()
        shownCounting = counting
        shownLast = 0
        shownCount = 0
        shownDropped = 0
        shownLongest = 0
        shownBuckets = [Int](repeating: 0, count: shownBuckets.count)
        shownLock.unlock()
    }

    private static func shownSummary() -> String {
        shownLock.lock()
        defer { shownLock.unlock() }
        let gaps = zip(shownNames, shownBuckets).filter { $0.1 > 0 }.map { "\($0)ms:\($1)" }.joined(separator: " ")
        return String(format: "shown=%d gaps %@ longest=%.0fms dropped by system=%d",
                      shownCount, gaps, shownLongest * 1000, shownDropped)
    }

    // MARK: Setup

    /// On for TestFlight and Xcode installs, off for App Store installs: the
    /// log is for the beta. Those builds carry a "sandboxReceipt"; App Store
    /// builds a "receipt". (The API is deprecated in iOS 18 but still answers.)
    static let defaultOn = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    /// Call once at launch, on the main thread.
    static func start() {
        guard !started else {
            return
        }
        started = true
        _ = launchTime
        // Read once before observing, so later changes are reported.
        _ = ProcessInfo.processInfo.thermalState

        let defaults = UserDefaults.standard
        if defaults.object(forKey: settingKey) == nil {
            defaults.set(defaultOn, forKey: settingKey)
        }
        enabled = defaults.bool(forKey: settingKey)
        lines.reserveCapacity(1024)

        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                flush()
            }
        }
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            add("low-power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off")")
        }
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            add("thermal \(thermalName)")
        }

        writeHeader()

        // iOS reports freezes with what the app was doing at the time.
        MXMetricManager.shared.add(HangReports.shared)
    }

    /// The Settings switch. Turning it off writes what is still in memory first.
    static func setEnabled(_ on: Bool) {
        if on {
            enabled = true
            writeHeader()
        } else {
            add("logs switched off")
            flush()
            enabled = false
        }
    }

    /// Date and time for the header and each round's end line.
    private static let clock = DateFormatter().then {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    /// Which build and phone; repeated at the top of every new file.
    private static var buildLine = ""

    private static func writeHeader() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        buildLine = "v\(version) (\(build)) \(deviceModel) iOS \(UIDevice.current.systemVersion)"
        add("==== \(clock.string(from: Date())) \(buildLine)"
            + " low-power=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off")"
            + " screen=\(UIScreen.main.maximumFramesPerSecond)Hz thermal=\(thermalName)")
    }

    // MARK: Lines

    /// One line, stamped with seconds since launch. The text is only built
    /// when the log is on.
    static func add(_ text: @autoclosure () -> String) {
        guard enabled else {
            return
        }
        lines.append(String(format: "%9.3f ", CACurrentMediaTime() - launchTime) + text())
    }

    /// A tap, with how long it took to reach the game. UITouch.timestamp and
    /// CACurrentMediaTime are both seconds since the phone started.
    static func tap(_ touch: UITouch, in view: UIView?, fingers: Int, target: String) {
        guard enabled else {
            return
        }
        let lag = max(0, CACurrentMediaTime() - touch.timestamp)
        let point = touch.location(in: view)
        // The round summary counts flaps only, not taps after a death.
        if target == "flap" {
            taps += 1
            lagTotal += lag
            worstLag = max(worstLag, lag)
        }
        add(String(format: "tap lag=%.0fms x=%.0f y=%.0f r=%.0f fingers=%d -> %@",
                   lag * 1000, point.x, point.y, touch.majorRadius, fingers, target))
    }

    /// Every frame of a live round. Counts it; a slow one also gets a line.
    /// `scheduled` is the gap SpriteKit reports, `dt` the gap on the real
    /// clock, `lead` how long before its scheduled time this update began.
    static func frame(scheduled: TimeInterval, real dt: TimeInterval, lead: TimeInterval) {
        guard enabled else {
            return
        }
        leastLead = min(leastLead, lead)
        // No drawable handed out since the last update: that frame was
        // simulated but never reached the screen.
        if frames > 0, drawnFrames == drawnAtLastFrame {
            notDrawn += 1
            if notDrawn <= notDrawnLinesPerRound {
                add(String(format: "frame not drawn (real gaps before it: %.1fms, %.1fms)", gapBefore * 1000, dt * 1000))
            }
        }
        gapBefore = dt
        drawnAtLastFrame = drawnFrames
        frames += 1
        frameTime += dt
        worstFrame = max(worstFrame, dt)
        buckets[bucketLimits.firstIndex { dt <= $0 } ?? bucketLimits.count] += 1

        if max(dt, scheduled) > slowFrame, slowLines < slowLinesPerRound {
            slowLines += 1
            add(String(format: "slow frame %.0fms (scheduled gap %.0fms)", dt * 1000, scheduled * 1000))
        }
    }

    static func roundStarted(_ detail: String) {
        guard enabled else {
            return
        }
        round += 1
        buckets = [Int](repeating: 0, count: buckets.count)
        frames = 0
        frameTime = 0
        worstFrame = 0
        leastLead = .infinity
        slowLines = 0
        taps = 0
        lagTotal = 0
        worstLag = 0
        stuckFrames = 0
        notDrawn = 0
        resetShown(counting: true)
        add("round \(round) start low-power=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off") \(detail)")
    }

    /// Frame and tap totals for the round, then the file is written.
    static func roundEnded(score: Int) {
        guard enabled else {
            return
        }
        let histogram = zip(bucketNames, buckets).filter { $0.1 > 0 }.map { "\($0)ms:\($1)" }.joined(separator: " ")
        add(String(format: "round %d end %@ score=%d time=%.1fs frames=%d fps=%.1f worst=%.0fms flaps=%d lag avg=%.0fms worst=%.0fms",
                   round, clock.string(from: Date()), score, frameTime, frames,
                   frameTime > 0 ? Double(frames) / frameTime : 0, worstFrame * 1000,
                   taps, taps > 0 ? lagTotal / Double(taps) * 1000 : 0, worstLag * 1000))
        add("round \(round) frames \(histogram) | not drawn:\(notDrawn) bird stuck:\(stuckFrames)"
            + String(format: " least lead:%.1fms", leastLead.isFinite ? leastLead * 1000 : 0))
        // The picture as he saw it: time between frames reaching the glass.
        add("round \(round) on screen \(shownSummary())")
        resetShown(counting: false)
        flush()
    }

    // MARK: File

    /// Hands what is in memory to the background writer.
    static func flush() {
        guard !lines.isEmpty else {
            return
        }
        let text = lines.joined(separator: "\n") + "\n"
        // A file started mid-session (deleted in Files, or rotated) still
        // says which build and phone wrote it.
        let fresh = lines.first?.contains("====") == true
            ? text
            : "          ==== continued \(buildLine)\n" + text
        lines.removeAll(keepingCapacity: true)

        writer.async {
            guard let data = text.data(using: .utf8),
                  let freshData = fresh.data(using: .utf8),
                  let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let file = folder.appendingPathComponent(fileName)

            if !FileManager.default.fileExists(atPath: file.path) {
                try? freshData.write(to: file)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: file) else {
                return
            }
            let size = (try? handle.seekToEnd()) ?? 0
            if size > maxFileBytes {
                try? handle.close()
                let old = folder.appendingPathComponent(oldFileName)
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: file, to: old)
                try? freshData.write(to: file)
                return
            }
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    // MARK: Device

    private static var thermalName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// "iPhone19,2"
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

// MARK: - Drawn frames

/// The game's SKView with a layer that counts the frames it hands out.
final class GameView: SKView {
    override class var layerClass: AnyClass {
        CountingMetalLayer.self
    }
}

final class CountingMetalLayer: CAMetalLayer {
    override func nextDrawable() -> CAMetalDrawable? {
        let drawable = super.nextDrawable()
        if let drawable {
            GameLog.drawnFrames &+= 1
            // The simulator's drawables do not report presentation times.
            #if !targetEnvironment(simulator)
            if GameLog.enabled {
                drawable.addPresentedHandler { shown in
                    GameLog.shown(at: shown.presentedTime)
                }
            }
            #endif
        }
        return drawable
    }
}

// MARK: - Freezes

/// Saves iOS's own diagnostic reports (hangs with the main-thread call
/// stack, crashes) next to the play log, as diag-hang-<date>.json or
/// diag-crash-<date>.json. iOS delivers them after the event; nothing here
/// runs during a round.
final class HangReports: NSObject, MXMetricManagerSubscriber {
    static let shared = HangReports()
    private static let keep = 20

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard GameLog.enabled,
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let stamp = DateFormatter().then {
            $0.locale = Locale(identifier: "en_US_POSIX")
            $0.dateFormat = "yyyyMMdd-HHmmss-SSS"
        }
        for (index, payload) in payloads.enumerated() {
            let kind = payload.hangDiagnostics?.isEmpty == false ? "hang"
                : payload.crashDiagnostics?.isEmpty == false ? "crash" : "other"
            let name = "diag-\(kind)-\(stamp.string(from: Date()))-\(index).json"
            try? payload.jsonRepresentation().write(to: folder.appendingPathComponent(name))
        }

        // Keep the newest few.
        let reports = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("diag-") }
            .sorted()
        for name in reports.dropLast(Self.keep) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
