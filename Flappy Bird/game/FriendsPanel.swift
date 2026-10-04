//
//  FriendsPanel.swift
//  FlappyBird
//
//  Friends leaderboard: the people you added (best today, best ever, when
//  they last played), the top of everyone, and the people who added you
//  (tap to add them back). The words on the top row are tabs. Under the
//  panel, BACK closes it and the arrows turn the pages of a long list.
//
import Foundation
import SpriteKit

class FriendsPanel: SKNode {

    private enum Layout {
        static let rowCount = 8 // tabs, column header, five players, a spare row
        static let playersPerPage = 5

        static let slotX: CGFloat = -104 // left edge of the header row
        static let rankX: CGFloat = -101
        static let nameX: CGFloat = -86 // left edge; ten characters end at 14
        static let todayX: CGFloat = 44
        static let bestX: CGFloat = 90

        static let mutualX: CGFloat = -22 // left edge, after the longest "99D AGO"

        // The Settings toggle-slot colour, behind your own row.
        static let ownRowColor = UIColor(red: 197 / 255, green: 194 / 255, blue: 141 / 255, alpha: 1)
        // Behind a row that was just added.
        static let newRowColor = PanelButton.textColor.withAlphaComponent(0.18)
    }

    private enum List: CaseIterable {
        case friends, everyone, addedYou

        /// The tab's touch name.
        var tabName: String {
            switch self {
            case .friends: return "tabFriends"
            case .everyone: return "tabEveryone"
            case .addedYou: return "tabAdded"
            }
        }
    }

    /// The ADDED YOU rows on screen, top to bottom; row n is the touch box
    /// "friendsAddBack<n>".
    private(set) var addBackRows: [PlayerRow] = []

    /// The friends on screen, top to bottom; row n is the touch box
    /// "friendsRow<n>" (tap to remove). Nil for your own row.
    private(set) var friendRowsOnPage: [PlayerRow?] = []

    // "ADDED ALEX" / "REMOVED ALEX" over the header row for a moment, and
    // the row it is about.
    private var message: String?
    private var highlightID: String?

    // The page showing: a list and a page within it. Kept per list so that
    // a redraw (a fetch arrived, someone was added back) stays on the list
    // the player is looking at.
    private var list = List.friends
    private var listPage = 0
    /// The board showing on EVERYONE.
    private var scope = BoardScope.today
    /// Whose scores are showing: the game's mode when the panel opens,
    /// then whatever the mode box under the panel is turned to.
    private var viewMode = GameMode.normal
    private let titleNode = SKNode()
    private let rowsNode = SKNode()

    private var pageCount = 1

    let closeButton = PanelButton(name: "panelBack", text: "BACK")

    /// Left of BACK: which mode's scores.
    let modeButton = PanelArt.modeBox(name: "friendsMode")

    // Under the panel, right of BACK. Each is there only while its page
    // exists: the sprite hides and the touch box loses its name.
    private let prevArrow = FriendsPanel.arrow(mirrored: false)
    private let nextArrow = FriendsPanel.arrow(mirrored: true)
    private lazy var prevTouchBox = touchBox("friendsPrev", at: .zero, size: CGSize(width: 32, height: 44))
    private lazy var nextTouchBox = touchBox("friendsNext", at: .zero, size: CGSize(width: 32, height: 44))

    private static func arrow(mirrored: Bool) -> SKSpriteNode {
        SKSpriteNode(texture: SKTexture(imageNamed: "back-button").then { $0.filteringMode = .nearest }).then {
            $0.xScale = mirrored ? -1 : 1
            $0.zPosition = 1
        }
    }

    override init() {
        super.init()

        PanelArt.background(rows: Layout.rowCount).forEach(addChild)

        let barY = PanelArt.closeButtonY(rows: Layout.rowCount, reference: Layout.rowCount)
        closeButton.position = CGPoint(x: 0, y: barY)
        addChild(closeButton)
        modeButton.position.y = barY
        addChild(modeButton)

        for (arrow, box, x) in [(prevArrow, prevTouchBox, CGFloat(64)), (nextArrow, nextTouchBox, 100)] {
            arrow.position = CGPoint(x: x, y: barY)
            box.position = arrow.position
            addChild(arrow)
            addChild(box)
        }

        addChild(titleNode)
        addChild(rowsNode)

        reload()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Redraws from FriendsStore. Opens on the first friends page unless
    /// `keepPage` is set (a fetch finished while the panel was open).
    func reload(keepPage: Bool = false) {
        if !keepPage {
            list = .friends
            listPage = 0
            scope = .today
            viewMode = GameMode.current
            clearMessage()
        }
        showPage()
    }

    /// Says what just happened ("ADDED ALEX") on the header row for a
    /// moment. With `jumpTo`, also turns to that player's row on FRIENDS
    /// and marks it.
    func show(message text: String, jumpTo id: String? = nil) {
        clearMessage()
        message = text

        if let id {
            list = .friends
            listPage = FriendsLogic.pageIndex(of: id, in: friendEntries().map(\.row.id), perPage: Layout.playersPerPage) ?? 0
            highlightID = id
        }

        showPage()

        run(.sequence([
            .wait(forDuration: 2.5),
            .run { [weak self] in
                self?.clearMessage()
                self?.showPage()
            }
        ]), withKey: "message")
    }

    private func clearMessage() {
        removeAction(forKey: "message")
        message = nil
        highlightID = nil
    }

    /// A tap on one of the tab words.
    func select(tab name: String) {
        guard let tapped = List.allCases.first(where: { $0.tabName == name }), tapped != list else {
            return
        }
        list = tapped
        listPage = 0
        clearMessage()
        showPage()
    }

    /// The board to fetch for what is showing, if it is a board.
    var boardShowing: (scope: BoardScope, mode: GameMode)? {
        list == .everyone ? (scope, viewMode) : nil
    }

    /// The mode box: the next mode's scores. Looking only; the game's own
    /// mode does not change.
    func showNextMode() {
        viewMode = viewMode.next
        listPage = 0
        clearMessage()
        showPage()
    }

    /// A tap on TODAY / WEEK / MONTH / ALL TIME. False when it was
    /// already showing.
    @discardableResult
    func select(scope name: String) -> Bool {
        guard let tapped = BoardScope.allCases.first(where: { Self.scopeName($0) == name }), tapped != scope else {
            return false
        }
        scope = tapped
        listPage = 0
        showPage()
        return true
    }

    private static func scopeName(_ scope: BoardScope) -> String {
        "scope" + scope.rawValue.capitalized
    }

    /// The arrows: one page back or on within the list showing. False when
    /// there is no such page.
    @discardableResult
    func turnPage(by step: Int) -> Bool {
        guard (0 ..< pageCount).contains(listPage + step) else {
            return false
        }
        listPage += step
        showPage()
        return true
    }

    // MARK: Pages

    private typealias Entry = (rank: Int, row: PlayerRow, isMe: Bool)

    private func friendEntries() -> [Entry] {
        var me = FriendsStore.myRow()
        me.id = "me"
        let rows = FriendsLogic.sorted(FriendsStore.friendRows() + [me], mode: viewMode)
        return rows.enumerated().map { (rank: $0 + 1, row: $1, isMe: $1.id == "me") }
    }

    private func addedYouEntries() -> [Entry] {
        FriendsLogic.sorted(FriendsStore.addedYouRows(), mode: viewMode).enumerated().map { (rank: $0 + 1, row: $1, isMe: false) }
    }

    private func pages<T>(_ entries: [T]) -> [[T]] {
        guard !entries.isEmpty else {
            return [[]]
        }
        return stride(from: 0, to: entries.count, by: Layout.playersPerPage).map {
            Array(entries[$0 ..< min($0 + Layout.playersPerPage, entries.count)])
        }
    }

    private func showPage() {
        let added = addedYouEntries()

        let board = FriendsStore.boardView(scope, mode: viewMode)
        modeButton.text = viewMode.title

        let entries: [Entry]
        switch list {
        case .friends: entries = friendEntries()
        case .everyone: entries = []
        case .addedYou: entries = added
        }

        let group = pages(entries)
        let boardPages = pages(board.top)
        // A redraw after the list shrank stays on its nearest page.
        pageCount = list == .everyone ? boardPages.count : group.count
        listPage = min(listPage, pageCount - 1)

        for (arrow, box, name, shown) in [
            (prevArrow, prevTouchBox, "friendsPrev", listPage > 0),
            (nextArrow, nextTouchBox, "friendsNext", listPage + 1 < pageCount),
        ] {
            arrow.isHidden = !shown
            box.name = shown ? name : nil
        }

        let waiting = added.isEmpty ? "" : " \(added.count > 9 ? "9+" : "\(added.count)")"
        let titles: [List: String] = [.friends: "FRIENDS", .everyone: "EVERYONE", .addedYou: "ADDED" + waiting]

        titleNode.removeAllChildren()
        PanelArt.tabs(
            List.allCases.map { (title: titles[$0] ?? "", name: $0.tabName, selected: $0 == list) },
            y: rowCenterY(0)
        ).forEach(titleNode.addChild)
        rowsNode.removeAllChildren()
        addBackRows = []
        friendRowsOnPage = []

        if list == .everyone {
            showScopes()
        } else {
            showHeader(list, isEmpty: entries.isEmpty)
        }

        if list == .addedYou {
            // Looked at: they no longer count as new.
            FriendsStore.markAddedSeen()
        }

        switch list {
        case .friends: showFriends(group[listPage])
        case .everyone: showEveryone(boardPages[listPage], you: board.you, rankKnown: board.youRankKnown, state: board.state)
        case .addedYou: showAddedYou(group[listPage])
        }
    }

    private var statusText: String? {
        if FriendsStore.isBusy {
            return "CHECKING"
        }

        switch FriendsStore.status {
        case .loading: return "LOADING"
        case .offline: return "OFFLINE"
        case .ok, .noAccount: return nil
        }
    }

    private func showHeader(_ list: List, isEmpty: Bool) {
        let y = rowCenterY(1)

        if let message {
            rowsNode.addChild(PanelArt.label(message, size: 8, x: 0, y: y))
            return
        }

        if list == .friends {
            // A button; while a request is out it says so instead, dimmed
            // and deaf, in the same place.
            let button = PanelButton(
                name: "friendsAdd",
                text: statusText ?? "+ ADD FRIEND",
                textSize: 8,
                width: 112,
                height: 26,
                hit: CGSize(width: 112, height: 30)
            )
            button.position = CGPoint(x: Layout.slotX + 56, y: y)
            button.isEnabled = statusText == nil
            rowsNode.addChild(button)
        } else if let statusText {
            rowsNode.addChild(PanelArt.label(statusText, size: 8, x: Layout.slotX, y: y, align: .left))
        } else if list == .addedYou, !isEmpty {
            rowsNode.addChild(PanelArt.label("TAP TO ADD BACK", size: 8, x: Layout.slotX, y: y, align: .left))
        }

        // Today's best belongs to the normal game.
        if list == .friends, viewMode == .normal {
            rowsNode.addChild(PanelArt.label("TODAY", size: 8, x: Layout.todayX, y: y))
        }
        rowsNode.addChild(PanelArt.label("BEST", size: 8, x: Layout.bestX, y: y))
    }

    /// EVERYONE's header row: which board. The word showing says what the
    /// numbers on the right are.
    private func showScopes() {
        // A hard mode has one board.
        guard viewMode == .normal else {
            rowsNode.addChild(PanelArt.label("\(viewMode.title) - ALL TIME", size: 8, x: 0, y: rowCenterY(1)))
            return
        }

        PanelArt.tabs(
            BoardScope.allCases.map { (title: $0.title, name: Self.scopeName($0), selected: $0 == scope) },
            y: rowCenterY(1),
            packed: true,
            boxHeight: 32
        ).forEach(rowsNode.addChild)
    }

    private func showFriends(_ entries: [Entry]) {
        let today = GameStats.dayFormatter.string(from: Date())
        let now = Date()
        let mutual = FriendsStore.mutualIDs()

        for (index, entry) in entries.enumerated() {
            let y = rowCenterY(index + 2)
            let row = entry.row

            if entry.isMe {
                addOwnRowBand(y: y)
            } else {
                if row.id == highlightID {
                    addRowBand(Layout.newRowColor, y: y)
                }
                if mutual.contains(row.id) {
                    rowsNode.addChild(PanelArt.label("MUTUAL", size: 8, x: Layout.mutualX, y: y - 7, align: .left))
                }
                // The row itself: tap to remove this friend.
                rowsNode.addChild(touchBox("friendsRow\(index)", at: CGPoint(x: 0, y: y), size: CGSize(width: 226, height: 30)))
            }
            friendRowsOnPage.append(entry.isMe ? nil : row)

            var name = row.name
            if entry.isMe && name.isEmpty {
                // No name yet: the row itself is the way to set one.
                name = FriendsStore.status == .noAccount ? "NO ICLOUD" : "SET NAME"
                rowsNode.addChild(touchBox("friendsMe", at: CGPoint(x: 0, y: y), size: CGSize(width: 226, height: 30)))
            }

            rowsNode.addChild(PanelArt.label("\(entry.rank)", size: 8, x: Layout.rankX, y: y))
            rowsNode.addChild(PanelArt.label(name, size: 10, x: Layout.nameX, y: y + 6, align: .left))
            rowsNode.addChild(PanelArt.label(FriendsLogic.agoText(row.lastPlayed, now: now), size: 8, x: Layout.nameX, y: y - 7, align: .left))

            if viewMode == .normal {
                let todayBest = FriendsLogic.todayBest(row, todayKey: today)
                rowsNode.addChild(PanelArt.label(todayBest.map { "\($0)" } ?? "-", size: 10, x: Layout.todayX, y: y))
            }
            if viewMode != .normal, row.best(viewMode) == 0 {
                // No score in this mode yet.
                rowsNode.addChild(PanelArt.label("-", size: 10, x: Layout.bestX, y: y))
            } else {
                rowsNode.addChild(PanelArt.score("\(row.best(viewMode))", x: Layout.bestX, y: y))
            }
        }

        // Only your own row: say how to get company. The hint is a button
        // too, whenever "+ ADD FRIEND" above is.
        if FriendsStore.friendIDs.isEmpty {
            rowsNode.addChild(PanelArt.label("NO FRIENDS YET", size: 10, x: 0, y: rowCenterY(4)))
            rowsNode.addChild(PanelArt.label("TAP + ADD FRIEND", size: 8, x: 0, y: rowCenterY(5)))

            if statusText == nil {
                let y = (rowCenterY(4) + rowCenterY(5)) / 2
                rowsNode.addChild(touchBox("friendsAdd", at: CGPoint(x: 0, y: y), size: CGSize(width: 200, height: 60)))
            }
        } else {
            let y = rowCenterY(7)
            rowsNode.addChild(PanelArt.label("TAP A FRIEND", size: 8, x: Layout.slotX, y: y + 6, align: .left))
            rowsNode.addChild(PanelArt.label("TO REMOVE", size: 8, x: Layout.slotX, y: y - 6, align: .left))
        }

        // Sends your exact name to someone, so they can add you.
        let share = PanelButton(name: "friendsShare", text: "SHARE NAME", textSize: 8, width: 100, height: 26, hit: CGSize(width: 100, height: 30))
        share.position = CGPoint(x: 58, y: rowCenterY(7))
        rowsNode.addChild(share)
    }

    private func showAddedYou(_ entries: [Entry]) {
        if entries.isEmpty, statusText == nil {
            rowsNode.addChild(PanelArt.label("NOBODY NEW", size: 10, x: 0, y: rowCenterY(3)))
            rowsNode.addChild(PanelArt.label("PLAYERS WHO ADD YOU", size: 8, x: 0, y: rowCenterY(4) + 6))
            rowsNode.addChild(PanelArt.label("SHOW UP HERE", size: 8, x: 0, y: rowCenterY(4) - 7))
        }

        for (index, entry) in entries.enumerated() {
            let y = rowCenterY(index + 2)

            rowsNode.addChild(PanelArt.label("+", size: 10, x: Layout.rankX, y: y))
            rowsNode.addChild(PanelArt.label(entry.row.name, size: 10, x: Layout.nameX, y: y, align: .left))
            rowsNode.addChild(PanelArt.score("\(entry.row.best(viewMode))", x: Layout.bestX, y: y))
            rowsNode.addChild(touchBox("friendsAddBack\(index)", at: CGPoint(x: 0, y: y), size: CGSize(width: 226, height: 30)))
            addBackRows.append(entry.row)
        }
    }

    private func showEveryone(_ entries: [BoardEntry], you: BoardEntry?, rankKnown: Bool, state: FriendsStore.BoardState) {
        // Until the server has answered there is nothing to rank against:
        // the board says what it is waiting for instead of a list of one.
        let waiting = state != .ok && entries.allSatisfy(\.isMe)

        if entries.isEmpty || waiting {
            let text: String
            switch state {
            case .loading: text = "LOADING"
            case .offline: text = "OFFLINE"
            case .failed: text = "UNAVAILABLE"
            case .ok:
                switch viewMode == .normal ? scope : .all {
                case .today: text = "NO SCORES TODAY"
                case .week: text = "NO SCORES THIS WEEK"
                case .month: text = "NO SCORES THIS MONTH"
                case .all: text = "NO SCORES YET"
                }
            }
            rowsNode.addChild(PanelArt.label(text, size: 10, x: 0, y: rowCenterY(4)))
        }

        guard !waiting else {
            return
        }

        for (index, entry) in entries.enumerated() {
            showBoardLine(entry, rank: "\(entry.rank)", y: rowCenterY(index + 2))
        }

        // Further down than the list goes: your own line, under it.
        if let you {
            showBoardLine(you, rank: rankKnown ? "\(you.rank)" : "99+", y: rowCenterY(7))
        }
    }

    private func showBoardLine(_ entry: BoardEntry, rank: String, y: CGFloat) {
        if entry.isMe {
            addOwnRowBand(y: y)
        }

        rowsNode.addChild(PanelArt.label(rank, size: 8, x: Layout.rankX, y: y))
        rowsNode.addChild(PanelArt.label(entry.name, size: 10, x: Layout.nameX, y: y, align: .left))
        // A little left of the BEST column: three digits must clear the edge.
        rowsNode.addChild(PanelArt.score("\(entry.value)", x: Layout.bestX - 4, y: y))
    }

    // MARK: Building

    private func rowCenterY(_ row: Int) -> CGFloat {
        PanelArt.rowCenterY(row, rows: Layout.rowCount)
    }

    private func addOwnRowBand(y: CGFloat) {
        addRowBand(Layout.ownRowColor, y: y)
    }

    private func addRowBand(_ color: UIColor, y: CGFloat) {
        rowsNode.addChild(SKSpriteNode(color: color, size: CGSize(width: 222, height: 28)).then {
            $0.position = CGPoint(x: 0, y: y)
            $0.zPosition = 0.5
        })
    }

    /// Clear and above the label layers (z 1 and 2): a tap on a glyph would
    /// otherwise land on the unnamed label.
    private func touchBox(_ name: String, at position: CGPoint, size: CGSize) -> SKSpriteNode {
        SKSpriteNode(color: .clear, size: size).then {
            $0.name = name
            $0.position = position
            $0.zPosition = 3
        }
    }
}
