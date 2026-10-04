//
//  GameMode.swift
//  FlappyBird
//
//  The game's modes and everything that makes the hard ones hard: one
//  table of numbers (speed, sliding pipes, gap, jumps, extra lives) and the
//  rule that places each hard-mode pipe. NORMAL is the game as it always
//  was and uses none of this beyond its row of the table. Foundation only,
//  so it is checked from the command line (see modetest in the artifacts
//  folder).
//
import Foundation

enum GameMode: String, CaseIterable {
    case normal, hard, insane, impossible

    private static let key = "gameMode"

    /// The mode chosen on the menu. Nothing stored means NORMAL.
    static var current: GameMode {
        get { UserDefaults.standard.string(forKey: key).flatMap(GameMode.init) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var next: GameMode {
        let all = GameMode.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    var title: String {
        rawValue.uppercased()
    }

    /// Added to the storage keys of a mode's own records ("bestScoreHard").
    /// Written out, never derived: stored data must not move if a mode is
    /// renamed. NORMAL keeps the keys it always had.
    var suffix: String {
        switch self {
        case .normal: return ""
        case .hard: return "Hard"
        case .insane: return "Insane"
        case .impossible: return "Impossible"
        }
    }

    /// The field on the player's server record holding this mode's best.
    var serverField: String {
        "best" + suffix
    }

    var tuning: Tuning {
        switch self {
        case .normal:
            return Tuning(startSpeed: 1, ramps: [], speedCap: 1)

        case .hard:
            // Speed only: a little faster from the start, a little more
            // every five points.
            return Tuning(startSpeed: 1.10, ramps: [(from: 0, gain: 0.04)], speedCap: 1.9, lives: true)

        case .insane:
            // The same climb, and the pipes slide up and down.
            return Tuning(
                startSpeed: 1.15, ramps: [(from: 0, gain: 0.04)], speedCap: 2.0,
                slideFrom: 5, slideAmp: 30, slideRamp: 10, slidePeriod: 2.4,
                lives: true
            )

        case .impossible:
            // Big jumps between gaps, sliding pipes and a shrinking gap
            // from the first pipe. Normal speed until 30, a slow creep to
            // 50, faster after; capped low enough that the jumps stay big.
            return Tuning(
                startSpeed: 1.0, ramps: [(from: 30, gain: 0.02), (from: 50, gain: 0.03)], speedCap: 1.6,
                slideFrom: 1, slideAmp: 20, slideRamp: 10, slidePeriod: 2.0,
                gapShrink: 2, gapFloor: 110,
                yLow: 0.55, yHigh: 2.2
            )
        }
    }
}

/// One mode's numbers. Starting points, meant to be play-tested: change
/// them in GameMode.tuning and nowhere else.
struct Tuning {
    /// The world's speed as a multiple of the normal game's.
    var startSpeed: Double
    /// From each `from` score on, the speed gains `gain` every
    /// `speedEvery` points (on top of the earlier ramps), up to `speedCap`.
    var ramps: [(from: Int, gain: Double)]
    var speedEvery = 5
    var speedCap: Double

    /// Pipes slide up and down from this pipe on (nil: never), reaching
    /// `slideAmp` either side of their place over the next `slideRamp`
    /// pipes. One full slide takes `slidePeriod` seconds on the clock,
    /// whatever the speed.
    var slideFrom: Int?
    var slideAmp = 0.0
    var slideRamp = 1
    var slidePeriod = 2.0

    /// The opening between the pipes: 130 in the normal game, less by
    /// `gapShrink` every `gapEvery` pipes down to `gapFloor`.
    var gapShrink = 0.0
    var gapEvery = 5
    var gapFloor = Tuning.normalGap

    /// How low and high the opening can sit, in quarters of the screen
    /// height (the normal game: 1 to 2).
    var yLow = 1.0
    var yHigh = 2.0

    /// An extra life is earned at 50, then at 100 and every 100 after.
    var lives = false

    static let normalGap = 130.0

    /// How fast a player can climb by tapping, in units a second. With the
    /// time between pipes it decides how far apart two openings may be.
    static let climbRate = 250.0

    /// The world's speed once `score` points are on the board.
    func speed(forScore score: Int) -> Double {
        var speed = startSpeed

        for (index, ramp) in ramps.enumerated() {
            // A ramp runs until the next one starts.
            let end = index + 1 < ramps.count ? ramps[index + 1].from : Int.max
            let points = min(score, end) - ramp.from
            if points > 0 {
                speed += ramp.gain * Double(points / speedEvery)
            }
        }

        return min(speed, speedCap)
    }

    /// The opening of the `pipe`-th pipe (the one that scores `pipe`).
    func gap(forPipe pipe: Int) -> Double {
        max(gapFloor, Tuning.normalGap - gapShrink * Double((pipe - 1) / gapEvery))
    }

    /// How far the `pipe`-th pipe slides either side of its place.
    func slide(forPipe pipe: Int) -> Double {
        guard let slideFrom, pipe >= slideFrom else {
            return 0
        }
        return slideAmp * min(1, Double(pipe - slideFrom + 1) / Double(slideRamp))
    }

    /// The furthest the next opening's middle may be from the last one's
    /// and still be reachable: the player may be anywhere in an opening
    /// (the bird is 30 tall), climbs or falls between the pipes (0.55 of
    /// the way from one to the next), and both pipes may have slid apart.
    func reach(speed: Double, gap: Double, slide: Double) -> Double {
        max(40, (gap - 30) + 0.55 * Tuning.climbRate / speed - 2 * slide)
    }

    static func earnsLife(score: Int) -> Bool {
        score == 50 || (score >= 100 && score % 100 == 0)
    }
}

/// Where one hard-mode pipe goes.
struct PipePlan: Equatable {
    /// The bottom pipe's centre, as in the normal game, before any slide.
    var y: Double
    var gap: Double
    /// Slide either side of `y`; 0 for a pipe that stays put.
    var slide: Double
    /// Whether it starts at the top of its slide.
    var startsHigh: Bool
}

/// Places the pipes of a hard-mode round, one after another.
struct PipePlanner {
    let tuning: Tuning
    private var lastY: Double?

    init(tuning: Tuning) {
        self.tuning = tuning
    }

    /// The `pipe`-th pipe (1 is the first). `quarter` is a quarter of the
    /// screen height; `random` picks a whole number in a range.
    mutating func plan(pipe: Int, quarter: Double, random: (ClosedRange<Int>) -> Int) -> PipePlan {
        // The speed the world will have when the bird gets there.
        let speed = tuning.speed(forScore: pipe - 1)
        let gap = tuning.gap(forPipe: pipe)
        let slide = tuning.slide(forPipe: pipe)

        var low = quarter * tuning.yLow
        var high = quarter * tuning.yHigh

        // Never further from the last opening than a player can get.
        if let lastY {
            let reach = tuning.reach(speed: speed, gap: gap, slide: slide)
            low = max(low, lastY - reach)
            high = min(high, lastY + reach)
        }

        let y = Double(random(Int(low.rounded(.up))...max(Int(low.rounded(.up)), Int(high.rounded(.down)))))
        lastY = y

        return PipePlan(y: y, gap: gap, slide: slide, startsHigh: slide > 0 && random(0...1) == 1)
    }
}
