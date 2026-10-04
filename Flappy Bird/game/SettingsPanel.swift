//
//  SettingsPanel.swift
//  FlappyBird
//
//  Created by Thatcher Clough on 3/30/20.
//  Copyright © 2020 Brandon Plank. All rights reserved.
//
import Foundation
import SpriteKit

/// Settings, built from the same sliced panel and labels as the Best Runs
/// and Friends panels: a title row, the player's name, then one row per
/// switch. BACK under the panel closes it.
class SettingsPanel: SKNode {

    enum Switch: CaseIterable {
        case sound, haptics, darkMode, logs

        var title: String {
            switch self {
            case .sound: return "SOUND"
            case .haptics: return "HAPTICS"
            case .darkMode: return "DARK MODE"
            case .logs: return "LOGS"
            }
        }

        var touchName: String {
            switch self {
            case .sound: return "toggleSounds"
            case .haptics: return "toggleHaptics"
            case .darkMode: return "toggleDarkMode"
            case .logs: return "toggleLogs"
            }
        }
    }

    private enum Layout {
        static let labelX: CGFloat = -72
        static let slotX: CGFloat = 57
        static let knobOnX: CGFloat = 68
        static let knobOffX: CGFloat = 46
        static let wordX: CGFloat = 80
        static let nameX: CGFloat = 48
        static let rowSize = CGSize(width: 222, height: 32)
    }

    private let switches: [Switch]
    private let rowCount: Int
    private var knobs: [Switch: SKSpriteNode] = [:]
    private var words: [Switch: SKNode] = [:]

    /// Panel height in its own units, for placing it on screen.
    var panelHeight: CGFloat { PanelArt.height(rows: rowCount) }

    let closeButton = PanelButton(name: "panelBack", text: "BACK")

    /// The player's leaderboard name, boxed so it reads as something to tap.
    let nameButton = PanelButton(name: "editName", text: "", textSize: 8, width: 104, height: 26, hit: CGSize(width: 104, height: 30))

    /// The play-log switch is for testers: `showsLogs` is false for App
    /// Store players, and the row is left out.
    init(showsLogs: Bool) {
        switches = Switch.allCases.filter { $0 != .logs || showsLogs }
        rowCount = switches.count + 2 // title, NAME, the switches

        super.init()

        PanelArt.background(rows: rowCount).forEach(addChild)
        addChild(PanelArt.label("SETTINGS", size: 12, x: 0, y: rowY(0)))

        // install.sh --test stamps the build, so one carrying test code
        // says so here. Store and TestFlight builds have no stamp.
        if let stamp = Bundle.main.infoDictionary?["FBBuildStamp"] as? String, !stamp.isEmpty {
            addChild(PanelArt.label(stamp, size: 8, x: 108, y: rowY(0), align: .right))
        }

        addChild(PanelArt.label("NAME", size: 10, x: Layout.labelX, y: rowY(1), align: .left))
        nameButton.position = CGPoint(x: Layout.nameX, y: rowY(1))
        addChild(nameButton)
        // The rest of the NAME row, under the button's own touch box.
        addChild(touchBox("editName", y: rowY(1), z: 2.5))

        for (index, item) in switches.enumerated() {
            let y = rowY(index + 2)

            addChild(PanelArt.label(item.title, size: 10, x: Layout.labelX, y: y, align: .left))
            addChild(SKSpriteNode(texture: SKTexture(imageNamed: "setting-toggle-background").then { $0.filteringMode = .nearest }).then {
                $0.position = CGPoint(x: Layout.slotX, y: y)
                $0.zPosition = 1
            })

            let knob = SKSpriteNode(texture: SKTexture(imageNamed: "toggle").then { $0.filteringMode = .nearest }).then {
                $0.position = CGPoint(x: Layout.knobOnX, y: y)
                $0.zPosition = 2
            }
            knobs[item] = knob
            addChild(knob)

            let word = SKNode()
            words[item] = word
            addChild(word)

            // The whole row is the switch.
            addChild(touchBox(item.touchName, y: y, z: 3))
        }

        closeButton.position = CGPoint(x: 0, y: PanelArt.closeButtonY(rows: rowCount, reference: rowCount))
        addChild(closeButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showName(_ name: String?) {
        nameButton.text = FriendsStore.isBusy ? "SAVING" : name ?? "TAP TO SET"
    }

    /// Moves a switch's knob and rewrites its ON / OFF word. Rows that are
    /// not showing (LOGS for App Store players) are ignored.
    func setSwitch(_ item: Switch, on: Bool, animated: Bool) {
        guard let knob = knobs[item], let word = words[item] else {
            return
        }

        let y = knob.position.y
        let targetX = on ? Layout.knobOnX : Layout.knobOffX

        knob.removeAllActions()
        if animated {
            knob.run(.sequence([
                .move(to: CGPoint(x: on ? targetX - 6 : targetX + 6, y: y), duration: 0.08),
                .move(to: CGPoint(x: targetX, y: y), duration: 0.12),
            ]))
        } else {
            knob.position.x = targetX
        }

        word.removeAllChildren()
        word.addChild(PanelArt.label(on ? "ON" : "OFF", size: 8, x: Layout.wordX, y: y, align: .left))
        word.alpha = on ? 1 : 0.55
    }

    private func rowY(_ row: Int) -> CGFloat {
        PanelArt.rowCenterY(row, rows: rowCount)
    }

    private func touchBox(_ name: String, y: CGFloat, z: CGFloat) -> SKSpriteNode {
        SKSpriteNode(color: .clear, size: Layout.rowSize).then {
            $0.name = name
            $0.position = CGPoint(x: 0, y: y)
            $0.zPosition = z
        }
    }
}
