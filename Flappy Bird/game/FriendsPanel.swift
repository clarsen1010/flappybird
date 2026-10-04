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

        static let slotX: CGFloat = -104 // left edge of "+ ADD FRIEND"
        static let rankX: CGFloat = -101
        static let nameX: CGFloat = -86 // left edge; ten characters end at 14
        static let todayX: CGFloat = 44
        static let bestX: CGFloat = 90

        // The Settings toggle-slot colour, behind your own row.
        static let ownRowColor = UIColor(red: 197 / 255, green: 194 / 255, blue: 141 / 255, alpha: 1)
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

    // The page showing: a list and a page within it. Kept per list so that
    // a redraw (a fetch arrived, someone was added back) stays on the list
    // the player is looking at.
    private var list = List.friends
    private var listPage = 0
    private let titleNode = SKNode()
    private let rowsNode = SKNode()

    private var pageCount = 1

    let closeButton = PanelButton(name: "panelBack", text: "BACK")

    // Under the panel, either side of BACK. Each is there only while its
    // page exists: the sprite hides and the touch box loses its name.
    private let prevArrow = FriendsPanel.arrow(mirrored: false)
    private let nextArrow = FriendsPanel.arrow(mirrored: true)
    private lazy var prevTouchBox = touchBox("friendsPrev", at: .zero, size: CGSize(width: 44, height: 44))
    private lazy var nextTouchBox = touchBox("friendsNext", at: .zero, size: CGSize(width: 44, height: 44))

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

        for (arrow, box, x) in [(prevArrow, prevTouchBox, CGFloat(-92)), (nextArrow, nextTouchBox, 92)] {
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
        }
        showPage()
    }

    /// A tap on one of the tab words.
    func select(tab name: String) {
        guard let tapped = List.allCases.first(where: { $0.tabName == name }), tapped != list else {
            return
        }
        list = tapped
        listPage = 0
        showPage()
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
        let rows = FriendsLogic.sorted(FriendsStore.friendRows() + [me])
        return rows.enumerated().map { (rank: $0 + 1, row: $1, isMe: $1.id == "me") }
    }

    private func addedYouEntries() -> [Entry] {
        FriendsLogic.sorted(FriendsStore.addedYouRows()).enumerated().map { (rank: $0 + 1, row: $1, isMe: false) }
    }

    private func everyoneEntries() -> [Entry] {
        let myID = FriendsStore.myID
        return FriendsStore.everyoneRows().enumerated().map { (rank: $0 + 1, row: $1, isMe: $1.id == myID) }
    }

    private func pages(_ entries: [Entry]) -> [[Entry]] {
        guard !entries.isEmpty else {
            return [[]]
        }
        return stride(from: 0, to: entries.count, by: Layout.playersPerPage).map {
            Array(entries[$0 ..< min($0 + Layout.playersPerPage, entries.count)])
        }
    }

    private func showPage() {
        let added = addedYouEntries()

        let entries: [Entry]
        switch list {
        case .friends: entries = friendEntries()
        case .everyone: entries = everyoneEntries()
        case .addedYou: entries = added
        }

        let group = pages(entries)
        // A redraw after the list shrank stays on its nearest page.
        listPage = min(listPage, group.count - 1)
        pageCount = group.count

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

        showHeader(list, isEmpty: entries.isEmpty)

        switch list {
        case .friends: showFriends(group[listPage])
        case .everyone: showEveryone(group[listPage])
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

        if let statusText {
            rowsNode.addChild(PanelArt.label(statusText, size: 8, x: Layout.slotX, y: y, align: .left))
        } else if list == .friends {
            rowsNode.addChild(PanelArt.label("+ ADD FRIEND", size: 8, x: Layout.slotX, y: y, align: .left))
            rowsNode.addChild(touchBox("friendsAdd", at: CGPoint(x: Layout.slotX + 48, y: y), size: CGSize(width: 104, height: 28)))
        } else if list == .addedYou, !isEmpty {
            rowsNode.addChild(PanelArt.label("TAP TO ADD BACK", size: 8, x: Layout.slotX, y: y, align: .left))
        }

        if list == .friends {
            rowsNode.addChild(PanelArt.label("TODAY", size: 8, x: Layout.todayX, y: y))
        }
        rowsNode.addChild(PanelArt.label("BEST", size: 8, x: Layout.bestX, y: y))
    }

    private func showFriends(_ entries: [Entry]) {
        let today = GameStats.dayFormatter.string(from: Date())
        let now = Date()

        for (index, entry) in entries.enumerated() {
            let y = rowCenterY(index + 2)
            let row = entry.row

            if entry.isMe {
                addOwnRowBand(y: y)
            }

            var name = row.name
            if entry.isMe && name.isEmpty {
                // No name yet: the row itself is the way to set one.
                name = FriendsStore.status == .noAccount ? "NO ICLOUD" : "SET NAME"
                rowsNode.addChild(touchBox("friendsMe", at: CGPoint(x: 0, y: y), size: CGSize(width: 226, height: 30)))
            }

            rowsNode.addChild(PanelArt.label("\(entry.rank)", size: 8, x: Layout.rankX, y: y))
            rowsNode.addChild(PanelArt.label(name, size: 10, x: Layout.nameX, y: y + 6, align: .left))
            rowsNode.addChild(PanelArt.label(FriendsLogic.agoText(row.lastPlayed, now: now), size: 8, x: Layout.nameX, y: y - 7, align: .left))

            let todayBest = FriendsLogic.todayBest(row, todayKey: today)
            rowsNode.addChild(PanelArt.label(todayBest.map { "\($0)" } ?? "-", size: 10, x: Layout.todayX, y: y))
            rowsNode.addChild(PanelArt.score("\(row.best)", x: Layout.bestX, y: y))
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
        }
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
            rowsNode.addChild(PanelArt.score("\(entry.row.best)", x: Layout.bestX, y: y))
            rowsNode.addChild(touchBox("friendsAddBack\(index)", at: CGPoint(x: 0, y: y), size: CGSize(width: 226, height: 30)))
            addBackRows.append(entry.row)
        }
    }

    private func showEveryone(_ entries: [Entry]) {
        guard !entries.isEmpty else {
            if statusText == nil {
                rowsNode.addChild(PanelArt.label("NO SCORES YET", size: 10, x: 0, y: rowCenterY(3)))
            }
            return
        }

        for (index, entry) in entries.enumerated() {
            let y = rowCenterY(index + 2)

            if entry.isMe {
                addOwnRowBand(y: y)
            }

            rowsNode.addChild(PanelArt.label("\(entry.rank)", size: 8, x: Layout.rankX, y: y))
            rowsNode.addChild(PanelArt.label(entry.row.name, size: 10, x: Layout.nameX, y: y, align: .left))
            rowsNode.addChild(PanelArt.score("\(entry.row.best)", x: Layout.bestX, y: y))
        }
    }

    // MARK: Building

    private func rowCenterY(_ row: Int) -> CGFloat {
        PanelArt.rowCenterY(row, rows: Layout.rowCount)
    }

    private func addOwnRowBand(y: CGFloat) {
        rowsNode.addChild(SKSpriteNode(color: Layout.ownRowColor, size: CGSize(width: 222, height: 28)).then {
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
