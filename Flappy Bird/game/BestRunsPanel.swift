//
//  BestRunsPanel.swift
//  FlappyBird
//
//  Local "best runs" board: the top scores played on this device, with dates.
//
import Foundation
import SpriteKit

struct BestRun: Codable, Equatable {
    let score: Int
    let date: Date?
}

enum BestRuns {
    static let shownCount = 6

    /// The run recorded at the end of the last round, highlighted on the board.
    static var lastRecorded: BestRun?

    private static let key = "bestRuns"
    static let keptCount = 10

    static func load() -> [BestRun] {
        if let data = UserDefaults.standard.data(forKey: key),
           let runs = try? JSONDecoder().decode([BestRun].self, from: data) {
            return runs
        }

        // Nothing recorded yet: seed with the best score saved before this
        // board existed (its date was never stored).
        let best = ResultBoard.bestScore()
        return best > 0 ? [BestRun(score: best, date: nil)] : []
    }

    /// Call before ResultBoard saves a new best, so the seed above is the
    /// previous best rather than this run.
    static func record(_ score: Int) {
        lastRecorded = nil

        guard score > 0 else {
            return
        }

        var runs = load()
        let run = BestRun(score: score, date: Date())
        lastRecorded = run
        runs.append(run)

        if let data = try? JSONEncoder().encode(Array(sorted(runs).prefix(keptCount))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Highest first; ties keep the earlier run on top.
    static func sorted(_ runs: [BestRun]) -> [BestRun] {
        runs.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
    }
}

/// Best Runs, Stats and Goals pages in one panel. The right arrow on the
/// title row flips pages; the left arrow closes the panel.
class BestRunsPanel: SKNode {

    private enum Layout {
        static let rowCount = BestRuns.shownCount + 1 // title + rows

        static let rankX: CGFloat = -80
        static let scoreX: CGFloat = -40
        static let dateX: CGFloat = 35
        static let newX: CGFloat = 90
    }

    private enum Page: Int, CaseIterable {
        case runs, stats, goals

        var title: String {
            switch self {
            case .runs: return "BEST RUNS"
            case .stats: return "STATS"
            case .goals: return "GOALS"
            }
        }
    }

    private static let dateFormatter = DateFormatter().then {
        $0.dateFormat = "M/d/yy"
    }

    // Local 12-hour time, e.g. "7:42 PM", shown under the date.
    // Fixed English locale: the pixel font cannot draw other AM/PM markers.
    private static let timeFormatter = DateFormatter().then {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "h:mm a"
    }

    /// Each goal reuses a medal from the result board.
    private static let goalMedals = [
        "first": "copper-medal", "ten": "copper-medal", "quarter": "silver-medal",
        "fifty": "gold-medal", "century": "platinum-medal", "platinum": "platinum-medal",
    ]

    private var page = Page.runs
    private let titleNode = SKNode()
    private let rowsNode = SKNode()

    lazy var backButton = SKSpriteNode(texture: SKTexture(imageNamed: "back-button").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: -92, y: rowCenterY(0))
        $0.zPosition = 1
    }

    lazy var backButtonTouchBox = SKSpriteNode().then {
        $0.name = "bestRunsBack"
        $0.zPosition = 2
        $0.position = backButton.position
        $0.color = UIColor.clear
        $0.size = CGSize(width: 30, height: 30)
    }

    lazy var nextButton = SKSpriteNode(texture: SKTexture(imageNamed: "back-button").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: 92, y: rowCenterY(0))
        $0.xScale = -1
        $0.zPosition = 1
    }

    lazy var nextButtonTouchBox = SKSpriteNode().then {
        $0.name = "bestRunsNext"
        $0.zPosition = 2
        $0.position = nextButton.position
        $0.color = UIColor.clear
        $0.size = CGSize(width: 30, height: 30)
    }

    override init() {
        super.init()

        addPanelBackground()
        addChild(backButton)
        addChild(backButtonTouchBox)
        addChild(nextButton)
        addChild(nextButtonTouchBox)
        addChild(titleNode)
        addChild(rowsNode)

        reload()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Opens on Best Runs.
    func reload() {
        page = .runs
        showPage()
    }

    func nextPage() {
        page = Page(rawValue: (page.rawValue + 1) % Page.allCases.count) ?? .runs
        showPage()
    }

    private func showPage() {
        titleNode.removeAllChildren()
        titleNode.addChild(makeLabel(page.title, size: 12, x: 0, y: rowCenterY(0)))
        rowsNode.removeAllChildren()

        switch page {
        case .runs: showRuns()
        case .stats: showStats()
        case .goals: showGoals(Achievements.all)
        }
    }

    private func showRuns() {
        let runs = Array(BestRuns.load().prefix(BestRuns.shownCount))

        guard !runs.isEmpty else {
            rowsNode.addChild(makeLabel("NO RUNS YET", size: 10, x: 0, y: rowCenterY(3)))
            return
        }

        for (index, run) in runs.enumerated() {
            let y = rowCenterY(index + 1)

            rowsNode.addChild(makeLabel("\(index + 1).", size: 10, x: Layout.rankX, y: y))
            rowsNode.addChild(makeScoreLabel("\(run.score)", x: Layout.scoreX, y: y))

            // Date over time: one line does not fit the 230-wide panel.
            if let date = run.date {
                rowsNode.addChild(makeLabel(Self.dateFormatter.string(from: date), size: 10, x: Layout.dateX, y: y + 6))
                rowsNode.addChild(makeLabel(Self.timeFormatter.string(from: date), size: 8, x: Layout.dateX, y: y - 7))
            } else {
                rowsNode.addChild(makeLabel("--", size: 10, x: Layout.dateX, y: y))
            }

            // The run you just played.
            if run == BestRuns.lastRecorded {
                rowsNode.addChild(SKSpriteNode(texture: Assets.shared.sprites.textureNamed("new").then { $0.filteringMode = .nearest }).then {
                    $0.position = CGPoint(x: Layout.newX, y: y)
                    $0.setScale(0.75)
                    $0.zPosition = 1
                })
            }
        }
    }

    private func showStats() {
        let columns: [(String, CGFloat)] = [("BEST", -18), ("AVG", 30), ("GAMES", 78)]

        for (title, x) in columns {
            rowsNode.addChild(makeLabel(title, size: 8, x: x, y: rowCenterY(1)))
        }

        for (index, period) in StatsPeriod.allCases.enumerated() {
            let y = rowCenterY(index + 2)
            let stats = GameStats.summary(period)

            rowsNode.addChild(makeLabel(period.title, size: 8, x: -80, y: y))
            rowsNode.addChild(makeScoreLabel("\(stats.best)", x: columns[0].1, y: y))
            rowsNode.addChild(makeLabel(String(format: "%.1f", stats.average), size: 10, x: columns[1].1, y: y))
            rowsNode.addChild(makeLabel("\(stats.games)", size: 10, x: columns[2].1, y: y))
        }

        let all = GameStats.summary(.all)
        rowsNode.addChild(makeLabel("PIPES PASSED \(all.pipes)", size: 8, x: 0, y: rowCenterY(6)))
    }

    private func showGoals(_ goals: [Achievement]) {
        let earned = Achievements.earned()

        for (index, goal) in goals.enumerated() {
            let y = rowCenterY(index + 1)
            let done = earned.contains(goal.id)

            let medal = SKSpriteNode(texture: Assets.shared.sprites.textureNamed(Self.goalMedals[goal.id] ?? "copper-medal").then { $0.filteringMode = .nearest }).then {
                $0.position = CGPoint(x: -85, y: y)
                $0.setScale(0.55)
                $0.zPosition = 1
                if !done {
                    // Greyed out until earned.
                    $0.color = .gray
                    $0.colorBlendFactor = 1
                    $0.alpha = 0.4
                }
            }
            rowsNode.addChild(medal)

            let text = SKNode().then { $0.alpha = done ? 1 : 0.45 }
            text.addChild(makeLabel(goal.title, size: 10, x: 5, y: y + 6))
            text.addChild(makeLabel(goal.detail, size: 8, x: 5, y: y - 7))
            rowsNode.addChild(text)
        }
    }

    // MARK: Building

    private func rowCenterY(_ row: Int) -> CGFloat {
        PanelArt.rowCenterY(row, rows: Layout.rowCount)
    }

    private func addPanelBackground() {
        PanelArt.background(rows: Layout.rowCount).forEach(addChild)
    }

    private func makeLabel(_ text: String, size: CGFloat, x: CGFloat, y: CGFloat) -> SKNode {
        PanelArt.label(text, size: size, x: x, y: y)
    }

    private func makeScoreLabel(_ text: String, x: CGFloat, y: CGFloat) -> SKNode {
        PanelArt.score(text, x: x, y: y)
    }
}

/// The sliced panel and its two label styles, shared by the Best Runs and
/// Friends panels. Rows are 32 tall; row 0 is the title row.
enum PanelArt {
    static let topHeight: CGFloat = 10
    static let rowHeight: CGFloat = 32
    static let bottomHeight: CGFloat = 14

    static let labelColor = UIColor(red: 252 / 255, green: 120 / 255, blue: 88 / 255, alpha: 1)
    static let labelShadowColor = UIColor(red: 239 / 255, green: 234 / 255, blue: 169 / 255, alpha: 1)

    static func height(rows: Int) -> CGFloat {
        topHeight + rowHeight * CGFloat(rows) + bottomHeight
    }

    static func rowCenterY(_ row: Int, rows: Int) -> CGFloat {
        height(rows: rows) / 2 - topHeight - rowHeight * (CGFloat(row) + 0.5)
    }

    static func background(rows: Int) -> [SKSpriteNode] {
        let top = height(rows: rows) / 2

        func slice(_ name: String, y: CGFloat) -> SKSpriteNode {
            SKSpriteNode(texture: Assets.shared.sprites.textureNamed(name).then { $0.filteringMode = .nearest }).then {
                $0.position = CGPoint(x: 0, y: y)
                $0.zPosition = 0
            }
        }

        return [slice("settings-panel-top", y: top - topHeight / 2)]
            + (0 ..< rows).map { slice("settings-panel-middle", y: rowCenterY($0, rows: rows)) }
            + [slice("settings-panel-bottom", y: -top + bottomHeight / 2)]
    }

    /// Salmon label with the pale drop shadow used by the Settings panel art.
    /// The SKView ignores sibling order, so the layers get explicit z.
    static func label(
        _ text: String,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat,
        align: SKLabelHorizontalAlignmentMode = .center
    ) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 1

        for (index, (color, offset)) in [(labelShadowColor, CGPoint(x: 0, y: -1)), (labelColor, .zero)].enumerated() {
            node.addChild(SKLabelNode(fontNamed: "KongtextRegular").then {
                $0.text = text
                $0.fontSize = size
                $0.fontColor = color
                $0.verticalAlignmentMode = .center
                $0.horizontalAlignmentMode = align
                $0.position = offset
                $0.zPosition = CGFloat(index)
            })
        }

        return node
    }

    /// Score digits in the game's own style (same fonts as the result board):
    /// white "inside" fill under the black "04b_19" outline.
    static func score(_ text: String, x: CGFloat, y: CGFloat) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 1

        node.addChild(SKLabelNode(fontNamed: "inside").then {
            $0.text = text
            $0.fontSize = 16
            $0.fontColor = .white
            $0.verticalAlignmentMode = .center
            $0.position = CGPoint(x: -0.49, y: 0)
            $0.zPosition = 0
        })

        node.addChild(SKLabelNode(fontNamed: "04b_19").then {
            $0.text = text
            $0.fontSize = 16
            $0.fontColor = .black
            $0.verticalAlignmentMode = .center
            $0.zPosition = 1
        })

        return node
    }
}
