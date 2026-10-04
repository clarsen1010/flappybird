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

    /// The run recorded at the end of the last round, highlighted on the
    /// board of the mode it was played in.
    static var lastRecorded: BestRun?
    static var lastRecordedMode = GameMode.normal

    static let keptCount = 10

    /// Each mode has its own list. NORMAL's key is the one it always had.
    static func key(mode: GameMode) -> String {
        "bestRuns" + mode.suffix
    }

    static func load(mode: GameMode) -> [BestRun] {
        if let data = UserDefaults.standard.data(forKey: key(mode: mode)),
           let runs = try? JSONDecoder().decode([BestRun].self, from: data) {
            return runs
        }

        // Nothing recorded yet: seed with the best score saved before this
        // board existed (its date was never stored). Only NORMAL is that
        // old; the hard modes came with their lists.
        let best = mode == .normal ? ResultBoard.bestScore() : 0
        return best > 0 ? [BestRun(score: best, date: nil)] : []
    }

    /// Call before ResultBoard saves a new best, so the seed above is the
    /// previous best rather than this run.
    static func record(_ score: Int, mode: GameMode) {
        lastRecorded = nil

        guard score > 0 else {
            return
        }

        var runs = load(mode: mode)
        let run = BestRun(score: score, date: Date())
        lastRecorded = run
        lastRecordedMode = mode
        runs.append(run)

        if let data = try? JSONEncoder().encode(Array(sorted(runs).prefix(keptCount))) {
            UserDefaults.standard.set(data, forKey: key(mode: mode))
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

/// Best Runs, Stats and Goals pages in one panel. The words on the top row
/// are tabs; BACK under the panel closes it.
class BestRunsPanel: SKNode {

    private enum Layout {
        static let rowCount = BestRuns.shownCount + 1 // title + rows

        static let rankX: CGFloat = -80
        static let scoreX: CGFloat = -40
        static let dateX: CGFloat = 35
        static let newX: CGFloat = 90
    }

    private enum Page: Int, CaseIterable {
        case runs, stats, goals, hard

        var title: String {
            switch self {
            case .runs: return "RUNS"
            case .stats: return "STATS"
            case .goals: return "GOALS"
            case .hard: return "HARD"
            }
        }

        /// The tab's touch name.
        var tabName: String {
            switch self {
            case .runs: return "tabRuns"
            case .stats: return "tabStats"
            case .goals: return "tabGoals"
            case .hard: return "tabHard"
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

    /// The goals past 100 wear the platinum medal in their own colour.
    private static let legendTints: [String: UIColor] = [
        "score150": UIColor(red: 0.25, green: 0.78, blue: 0.80, alpha: 1),
        "score200": UIColor(red: 0.30, green: 0.50, blue: 0.95, alpha: 1),
        "score250": UIColor(red: 0.62, green: 0.40, blue: 0.90, alpha: 1),
        "score300": UIColor(red: 0.85, green: 0.22, blue: 0.25, alpha: 1),
        "score400": UIColor(red: 0.98, green: 0.45, blue: 0.75, alpha: 1),
        "score500": UIColor(red: 0.35, green: 0.78, blue: 0.30, alpha: 1),
        "score1000": UIColor(red: 0.15, green: 0.13, blue: 0.16, alpha: 1),
        // The hard modes' goals, in their worlds' colours.
        "hard1": UIColor(red: 0.90, green: 0.40, blue: 0.20, alpha: 1),
        "hard2": UIColor(red: 0.90, green: 0.40, blue: 0.20, alpha: 1),
        "insane1": UIColor(red: 0.80, green: 0.10, blue: 0.15, alpha: 1),
        "insane2": UIColor(red: 0.80, green: 0.10, blue: 0.15, alpha: 1),
        "impossible1": UIColor(red: 0.25, green: 0.15, blue: 0.35, alpha: 1),
        "impossible2": UIColor(red: 0.25, green: 0.15, blue: 0.35, alpha: 1),
    ]

    /// With the goals past 100 showing, the Goals page is two rows taller.
    private static let legendRowCount = Layout.rowCount + 2

    private var page = Page.runs
    /// Whose runs are showing: the game's mode when the panel opens, then
    /// whatever the mode box under the panel is turned to.
    private var viewMode = GameMode.normal
    private let backgroundNode = SKNode()
    private let titleNode = SKNode()
    private let rowsNode = SKNode()

    let closeButton = PanelButton(name: "panelBack", text: "BACK")

    /// Left of BACK, on the runs page: which mode's runs.
    let modeButton = PanelArt.modeBox(name: "bestRunsMode")

    override init() {
        super.init()

        addChild(backgroundNode)
        addChild(closeButton)
        addChild(modeButton)
        addChild(titleNode)
        addChild(rowsNode)

        reload()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Opens on Best Runs, in the mode the game is in.
    func reload() {
        page = .runs
        viewMode = GameMode.current
        showPage()
    }

    /// The mode box: the next mode's runs. Looking only; the game's own
    /// mode does not change.
    func showNextMode() {
        viewMode = viewMode.next
        showPage()
    }

    /// A tap on one of the tab words.
    func select(tab name: String) {
        guard let tapped = Page.allCases.first(where: { $0.tabName == name }), tapped != page else {
            return
        }
        page = tapped
        showPage()
    }

    private func showPage() {
        titleNode.removeAllChildren()
        PanelArt.tabs(
            Page.allCases.map { (title: $0.title, name: $0.tabName, selected: $0 == page) },
            y: rowCenterY(0)
        ).forEach(titleNode.addChild)
        rowsNode.removeAllChildren()

        let legends = page == .goals && Achievements.legendsUnlocked
        showBackground(rows: legends ? Self.legendRowCount : Layout.rowCount)

        switch page {
        case .runs: showRuns()
        case .stats: showStats()
        case .goals:
            if legends {
                showMedalStrip(Achievements.all, row: 1)
                showGoals(Achievements.legends, firstRow: 2)
            } else {
                showGoals(Achievements.all, firstRow: 1)
            }
        case .hard:
            showGoals(Achievements.hard, firstRow: 1)
        }
    }

    private func showRuns() {
        let runs = Array(BestRuns.load(mode: viewMode).prefix(BestRuns.shownCount))

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
            if run == BestRuns.lastRecorded, viewMode == BestRuns.lastRecordedMode {
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

    private func makeMedal(_ goal: Achievement, done: Bool, scale: CGFloat, x: CGFloat, y: CGFloat) -> SKSpriteNode {
        let tint = Self.legendTints[goal.id]
        let name = Self.goalMedals[goal.id] ?? (tint == nil ? "copper-medal" : "platinum-medal")

        return SKSpriteNode(texture: Assets.shared.sprites.textureNamed(name).then { $0.filteringMode = .nearest }).then {
            $0.position = CGPoint(x: x, y: y)
            $0.setScale(scale)
            $0.zPosition = 1
            if !done {
                // Greyed out until earned.
                $0.color = .gray
                $0.colorBlendFactor = 1
                $0.alpha = 0.4
            } else if let tint {
                $0.color = tint
                $0.colorBlendFactor = 0.7
            }
        }
    }

    /// The six first goals in one row, once the goals past 100 are showing
    /// (CENTURY earned means all six are).
    private func showMedalStrip(_ goals: [Achievement], row: Int) {
        let earned = Achievements.earned()
        let y = rowCenterY(row)

        for (index, goal) in goals.enumerated() {
            let x = -85 + 34 * CGFloat(index)
            rowsNode.addChild(makeMedal(goal, done: earned.contains(goal.id), scale: 0.45, x: x, y: y + 4))
            rowsNode.addChild(makeLabel("\(goal.score)", size: 6, x: x, y: y - 11))
        }
    }

    private func showGoals(_ goals: [Achievement], firstRow: Int) {
        let earned = Achievements.earned()

        for (index, goal) in goals.enumerated() {
            let y = rowCenterY(index + firstRow)
            let done = earned.contains(goal.id)

            rowsNode.addChild(makeMedal(goal, done: done, scale: 0.55, x: -85, y: y))

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

    /// The panel with `rows` rows. Extra rows hang below: the top edge and
    /// the tabs stay where they are, and BACK follows the bottom edge.
    private func showBackground(rows: Int) {
        backgroundNode.removeAllChildren()
        backgroundNode.position.y = (PanelArt.height(rows: Layout.rowCount) - PanelArt.height(rows: rows)) / 2
        PanelArt.background(rows: rows).forEach(backgroundNode.addChild)
        closeButton.position.y = PanelArt.closeButtonY(rows: rows, reference: Layout.rowCount)
        modeButton.position.y = closeButton.position.y
        modeButton.isHidden = page != .runs
        modeButton.isEnabled = page == .runs
        modeButton.text = viewMode.title
    }

    private func makeLabel(_ text: String, size: CGFloat, x: CGFloat, y: CGFloat) -> SKNode {
        PanelArt.label(text, size: size, x: x, y: y)
    }

    private func makeScoreLabel(_ text: String, x: CGFloat, y: CGFloat) -> SKNode {
        PanelArt.score(text, x: x, y: y)
    }
}

/// The sliced panel, its label styles and its tab row, shared by the Best
/// Runs, Friends and Settings panels. Rows are 32 tall; row 0 is the top row.
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

    /// Centre of the BACK button: 6 under the bottom edge of a panel with
    /// `rows` rows whose top edge is where a `reference`-row panel's is.
    static func closeButtonY(rows: Int, reference: Int) -> CGFloat {
        height(rows: reference) / 2 - height(rows: rows) - 24
    }

    /// The box under a panel that says whose scores are showing; a tap
    /// turns it to the next mode. Wide enough for IMPOSSIBLE.
    static func modeBox(name: String) -> PanelButton {
        PanelButton(name: name, text: GameMode.normal.title, textSize: 8, width: 96, height: 30, hit: CGSize(width: 100, height: 44)).then {
            $0.position.x = -84
        }
    }

    static let tabColor = PanelButton.textColor
    static let panelColor = UIColor(red: 221 / 255, green: 217 / 255, blue: 156 / 255, alpha: 1)

    /// A row of tab words across the panel. The one showing sits on a
    /// dark band; each word is a touch box with the tab's name. Words sit
    /// in equal slots, or `packed` side by side when they are too uneven
    /// for that. `boxHeight` reaches up into the top border on row 0.
    static func tabs(
        _ tabs: [(title: String, name: String, selected: Bool)],
        y: CGFloat,
        size: CGFloat = 8,
        packed: Bool = false,
        boxHeight: CGFloat = 34
    ) -> [SKNode] {
        let gap: CGFloat = 10
        let widths = tabs.map { CGFloat($0.title.count) * size }
        let total = widths.reduce(0, +) + gap * CGFloat(tabs.count - 1)
        var left = -total / 2

        return tabs.enumerated().flatMap { index, tab -> [SKNode] in
            var slot = 216 / CGFloat(tabs.count)
            var x = (CGFloat(index) - CGFloat(tabs.count - 1) / 2) * slot
            if packed {
                slot = widths[index] + gap
                x = left + widths[index] / 2
                left += slot
            }
            var nodes: [SKNode] = []

            if tab.selected {
                nodes.append(SKSpriteNode(color: tabColor, size: CGSize(width: CGFloat(tab.title.count) * size + 8, height: 18)).then {
                    $0.position = CGPoint(x: x, y: y)
                    $0.zPosition = 0.5
                })
                nodes.append(SKLabelNode(fontNamed: "KongtextRegular").then {
                    $0.text = tab.title
                    $0.fontSize = size
                    $0.fontColor = panelColor
                    $0.verticalAlignmentMode = .center
                    $0.position = CGPoint(x: x, y: y)
                    $0.zPosition = 1
                })
            } else {
                nodes.append(label(tab.title, size: size, x: x, y: y))
            }

            nodes.append(SKSpriteNode(color: .clear, size: CGSize(width: slot, height: boxHeight)).then {
                $0.name = tab.name
                $0.position = CGPoint(x: x, y: y + (boxHeight - 32) / 2)
                $0.zPosition = 3
            })

            return nodes
        }
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
