//
//  GameLog.swift
//  FlappyBird
//
//  Play log for the beta (Settings > Logs, on by default): taps and how late
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
//  On My iPhone > Flappy Bird. Nothing is sent anywhere.
//
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

    // Per-round frame and tap numbers.
    private static let bucketLimits: [Double] = [0.009, 0.013, 0.018, 0.025, 0.034, 0.050, 0.100]
    private static var buckets = [Int](repeating: 0, count: 8)
    private static var frames = 0
    private static var frameTime: TimeInterval = 0
    private static var worstFrame: TimeInterval = 0
    private static var slowLines = 0
    private static var taps = 0
    private static var lagTotal: TimeInterval = 0
    private static var worstLag: TimeInterval = 0
    private static var round = 0

    // MARK: Setup

    /// Call once at launch, on the main thread.
    static func start() {
        guard !started else {
            return
        }
        started = true
        _ = launchTime

        let defaults = UserDefaults.standard
        if defaults.object(forKey: settingKey) == nil {
            defaults.set(true, forKey: settingKey)
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

    private static func writeHeader() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let stamp = DateFormatter().then {
            $0.locale = Locale(identifier: "en_US_POSIX")
            $0.dateFormat = "yyyy-MM-dd HH:mm:ss"
        }.string(from: Date())

        add("==== \(stamp) v\(version) (\(build)) \(deviceModel) iOS \(UIDevice.current.systemVersion)"
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
        taps += 1
        lagTotal += lag
        worstLag = max(worstLag, lag)
        add(String(format: "tap lag=%.0fms x=%.0f y=%.0f r=%.0f fingers=%d -> %@",
                   lag * 1000, point.x, point.y, touch.majorRadius, fingers, target))
    }

    /// Every frame of a live round. Counts it; a slow one also gets a line.
    static func frame(_ dt: TimeInterval) {
        guard enabled else {
            return
        }
        frames += 1
        frameTime += dt
        worstFrame = max(worstFrame, dt)
        buckets[bucketLimits.firstIndex { dt <= $0 } ?? bucketLimits.count] += 1

        if dt > slowFrame, slowLines < slowLinesPerRound {
            slowLines += 1
            add(String(format: "slow frame %.0fms", dt * 1000))
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
        slowLines = 0
        taps = 0
        lagTotal = 0
        worstLag = 0
        add("round \(round) start low-power=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off") \(detail)")
    }

    /// Frame and tap totals for the round, then the file is written.
    static func roundEnded(score: Int) {
        guard enabled else {
            return
        }
        let names = ["<=9", "<=13", "<=18", "<=25", "<=34", "<=50", "<=100", ">100"]
        let histogram = zip(names, buckets).map { "\($0)ms:\($1)" }.joined(separator: " ")
        add(String(format: "round %d end score=%d time=%.1fs frames=%d fps=%.1f worst=%.0fms taps=%d lag avg=%.0fms worst=%.0fms",
                   round, score, frameTime, frames,
                   frameTime > 0 ? Double(frames) / frameTime : 0, worstFrame * 1000,
                   taps, taps > 0 ? lagTotal / Double(taps) * 1000 : 0, worstLag * 1000))
        add("round \(round) frames \(histogram)")
        flush()
    }

    // MARK: File

    /// Hands what is in memory to the background writer.
    static func flush() {
        guard !lines.isEmpty else {
            return
        }
        let text = lines.joined(separator: "\n") + "\n"
        lines.removeAll(keepingCapacity: true)

        writer.async {
            guard let data = text.data(using: .utf8),
                  let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let file = folder.appendingPathComponent(fileName)

            if !FileManager.default.fileExists(atPath: file.path) {
                try? data.write(to: file)
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
                try? data.write(to: file)
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
