//
//  FriendsPanel.swift
//  FlappyBird
//
//  Friends leaderboard: the people you added (best today, best ever, when
//  they last played), then the top of everyone. Same frame and arrows as the
//  Best Runs panel: the right arrow flips pages, the left arrow closes.
//
import Foundation
import SpriteKit

class FriendsPanel: SKNode {

    private enum Layout {
        static let rowCount = 7 // title, column header, five players
        static let playersPerPage = 5

        static let slotX: CGFloat = -104 // left edge of "+ ADD FRIEND"
        static let rankX: CGFloat = -101
        static let nameX: CGFloat = -86 // left edge; ten characters end at 14
        static let todayX: CGFloat = 44
        static let bestX: CGFloat = 90

        // The Settings toggle-slot colour, behind your own row.
        static let ownRowColor = UIColor(red: 197 / 255, green: 194 / 255, blue: 141 / 255, alpha: 1)
    }

    private enum List {
        case friends, everyone
    }

    private var pageIndex = 0
    private let titleNode = SKNode()
    private let rowsNode = SKNode()

    lazy var backButton = SKSpriteNode(texture: SKTexture(imageNamed: "back-button").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: -92, y: rowCenterY(0))
        $0.zPosition = 1
    }

    lazy var nextButton = SKSpriteNode(texture: SKTexture(imageNamed: "back-button").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: 92, y: rowCenterY(0))
        $0.xScale = -1
        $0.zPosition = 1
    }

    override init() {
        super.init()

        PanelArt.background(rows: Layout.rowCount).forEach(addChild)
        addChild(backButton)
        addChild(touchBox("friendsBack", at: backButton.position, size: CGSize(width: 30, height: 30)))
        addChild(nextButton)
        addChild(touchBox("friendsNext", at: nextButton.position, size: CGSize(width: 30, height: 30)))
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
            pageIndex = 0
        }
        showPage()
    }

    func nextPage() {
        pageIndex += 1
        showPage()
    }

    // MARK: Pages

    private typealias Entry = (rank: Int, row: PlayerRow, isMe: Bool)

    private func friendEntries() -> [Entry] {
        var me = FriendsStore.myRow()
        me.id = "me"
        let rows = FriendsLogic.sorted(FriendsStore.friendRows() + [me])
        return rows.enumerated().map { (rank: $0 + 1, row: $1, isMe: $1.id == "me") }
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
        let friendPages = pages(friendEntries())
        let everyonePages = pages(everyoneEntries())
        pageIndex %= friendPages.count + everyonePages.count

        let list: List = pageIndex < friendPages.count ? .friends : .everyone
        let group = list == .friends ? friendPages : everyonePages
        let index = list == .friends ? pageIndex : pageIndex - friendPages.count

        var title = list == .friends ? "FRIENDS" : "EVERYONE"
        if group.count > 1 {
            title += " \(index + 1)/\(group.count)"
        }

        titleNode.removeAllChildren()
        titleNode.addChild(PanelArt.label(title, size: 12, x: 0, y: rowCenterY(0)))
        rowsNode.removeAllChildren()

        showHeader(list)

        switch list {
        case .friends: showFriends(group[index])
        case .everyone: showEveryone(group[index])
        }
    }

    private var statusText: String? {
        switch FriendsStore.status {
        case .loading: return "LOADING"
        case .offline: return "OFFLINE"
        case .ok, .noAccount: return nil
        }
    }

    private func showHeader(_ list: List) {
        let y = rowCenterY(1)

        if let statusText {
            rowsNode.addChild(PanelArt.label(statusText, size: 8, x: Layout.slotX, y: y, align: .left))
        } else if list == .friends {
            rowsNode.addChild(PanelArt.label("+ ADD FRIEND", size: 8, x: Layout.slotX, y: y, align: .left))
            rowsNode.addChild(touchBox("friendsAdd", at: CGPoint(x: Layout.slotX + 48, y: y), size: CGSize(width: 104, height: 28)))
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

        // Only your own row: say how to get company.
        if FriendsStore.friendIDs.isEmpty {
            rowsNode.addChild(PanelArt.label("NO FRIENDS YET", size: 10, x: 0, y: rowCenterY(4)))
            rowsNode.addChild(PanelArt.label("TAP + ADD FRIEND", size: 8, x: 0, y: rowCenterY(5)))
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
