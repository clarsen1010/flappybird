//
//  SettingsPanel.swift
//  FlappyBird
//
//  Created by Thatcher Clough on 3/30/20.
//  Copyright © 2020 Brandon Plank. All rights reserved.
//
import Foundation
import SpriteKit

struct SettingsPositions {
    static let toggleOnX: CGFloat = 68
    static let toggleOffX: CGFloat = 46
    
    // Rows top to bottom, 36 apart (44 before DARK MODE): NAME, SOUND,
    // HAPTICS, DARK MODE, LOGS. The labels are part of the panel art.
    static let nameRowY: CGFloat = 78
    static let soundToggleY: CGFloat = 42
    static let hapticsToggleY: CGFloat = 6
    static let darkModeToggleY: CGFloat = -38
    static let logsToggleY: CGFloat = -74
    
    static let backButtonX: CGFloat = -92
    static let backButtonY: CGFloat = 103
}

class SettingsPanel: SKSpriteNode {
    
    convenience init() {
        self.init(texture: SKTexture(imageNamed: "settings-panel").then { $0.filteringMode = .nearest })
        addChild(backButton)
        addChild(backButtonTouchBox)
        
        addChild(versionLabel)
        
        addChild(soundToggle)
        addChild(soundButton)
        
        addChild(hapticsToggle)
        addChild(hapticsButton)
        
        addChild(darkModeToggle)
        addChild(darkModeButton)
        
        addChild(logsToggle)
        addChild(logsButton)
    }
    
    lazy var versionLabel = MKOutlinedLabelNode(fontNamed: "KongtextRegular", fontSize: 12).then {
        $0.name = "versionLabel"
        $0.position = CGPoint(x: SettingsPositions.toggleOffX + (SettingsPositions.toggleOnX - SettingsPositions.toggleOffX) / 2, y: SettingsPositions.nameRowY + 20)
        $0.zPosition = 3
        $0.fontColor = UIColor.white
        $0.borderColor = UIColor.black
        $0.borderWidth = 1
        $0.borderOffset = CGPoint(x: 0, y: 0)
        // Shows the version (5.0.1, bumped for every phone install). install.sh --test sets
        // FBBuildStamp to TEST so a build carrying test code is obvious.
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let stamp = info?["FBBuildStamp"] as? String ?? ""
        $0.outlinedText = stamp.isEmpty ? version : stamp
    }
    
    lazy var backButton = SKSpriteNode(texture: SKTexture(imageNamed: "back-button").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: SettingsPositions.backButtonX, y: SettingsPositions.backButtonY)
        $0.zPosition = 1
    }
    
    lazy var backButtonTouchBox = SKSpriteNode().then {
        $0.name = "settingsBack"
        $0.zPosition = 2
        $0.position = CGPoint(x: SettingsPositions.backButtonX, y: SettingsPositions.backButtonY)
        $0.color = UIColor.clear
        $0.size = CGSize(width: 30, height: 30)
    }
    
    lazy var soundToggle = SKSpriteNode(texture: SKTexture(imageNamed: "toggle").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: SettingsPositions.toggleOnX, y: SettingsPositions.soundToggleY)
        $0.zPosition = 2
    }
    
    lazy var soundButton = SKSpriteNode().then {
        $0.name = "toggleSounds"
        $0.position = CGPoint(x: SettingsPositions.toggleOffX + (SettingsPositions.toggleOnX - SettingsPositions.toggleOffX) / 2, y: SettingsPositions.soundToggleY)
        $0.zPosition = 3
        $0.color = UIColor.clear
        $0.size = CGSize(width: 45, height: 25)
    }
    
    lazy var hapticsToggle = SKSpriteNode(texture: SKTexture(imageNamed: "toggle").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: SettingsPositions.toggleOnX, y: SettingsPositions.hapticsToggleY)
        $0.zPosition = 2
    }
    
    lazy var hapticsButton = SKSpriteNode().then {
        $0.name = "toggleHaptics"
        $0.position = CGPoint(x: SettingsPositions.toggleOffX + (SettingsPositions.toggleOnX - SettingsPositions.toggleOffX) / 2, y: SettingsPositions.hapticsToggleY)
        $0.zPosition = 3
        $0.color = UIColor.clear
        $0.size = CGSize(width: 45, height: 25)
    }
    
    lazy var darkModeToggle = SKSpriteNode(texture: SKTexture(imageNamed: "toggle").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: SettingsPositions.toggleOnX, y: SettingsPositions.darkModeToggleY)
        $0.zPosition = 2
    }
    
    lazy var darkModeButton = SKSpriteNode().then {
        $0.name = "toggleDarkMode"
        $0.position = CGPoint(x: SettingsPositions.toggleOffX + (SettingsPositions.toggleOnX - SettingsPositions.toggleOffX) / 2, y: SettingsPositions.darkModeToggleY)
        $0.zPosition = 3
        $0.color = UIColor.clear
        $0.size = CGSize(width: 45, height: 25)
    }
    
    lazy var logsToggle = SKSpriteNode(texture: SKTexture(imageNamed: "toggle").then { $0.filteringMode = .nearest }).then {
        $0.position = CGPoint(x: SettingsPositions.toggleOnX, y: SettingsPositions.logsToggleY)
        $0.zPosition = 2
    }
    
    lazy var logsButton = SKSpriteNode().then {
        $0.name = "toggleLogs"
        $0.position = CGPoint(x: SettingsPositions.toggleOffX + (SettingsPositions.toggleOnX - SettingsPositions.toggleOffX) / 2, y: SettingsPositions.logsToggleY)
        $0.zPosition = 3
        $0.color = UIColor.clear
        $0.size = CGSize(width: 45, height: 25)
    }
}
