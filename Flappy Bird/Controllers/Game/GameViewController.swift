//
//  GameViewController.swift
//  Flappy Bird
//
//  Created by Thatcher Clough on 4/30/20.
//  Copyright © 2020 Brandon Plank & Thatcher Clough. All rights reserved.
//

import UIKit
import Foundation
import SpriteKit
import GameplayKit
import Network

class GameViewController: UIViewController {
    public static let shared = GameViewController()
    
    override var shouldAutorotate: Bool { false }
    override var prefersStatusBarHidden: Bool { true }
    override var canBecomeFirstResponder: Bool { true }
    
    lazy var scene = GameScene(fileNamed: "GameScene")?.then {
        $0.scaleMode = .aspectFill
    }
    
    override func loadView() {
        view = SKView().then {
            $0.ignoresSiblingOrder = true
            // ProMotion: let SpriteKit render at up to 120 Hz (needs
            // CADisableMinimumFrameDurationOnPhone in Info.plist).
            $0.preferredFramesPerSecond = 120
            // Launch with -showFPS to see the real frame rate; normal
            // launches never show it.
            $0.showsFPS = ProcessInfo.processInfo.arguments.contains("-showFPS")
            $0.showsNodeCount = false
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        GameScene.hitButton = false
        guard let scene = scene, let skView = self.view as? SKView else { return }
        skView.presentScene(scene)
        becomeFirstResponder()

        // Dark Mode follows the phone mid-game too. iOS 16 picks up a change
        // at the next round instead.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.scene?.refreshTheme()
            }
        }
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }
            if #available(iOS 13.4, macCatalyst 13.4, *) {
                if key.keyCode == UIKeyboardHIDUsage.keyboardSpacebar { // Space
                    scene?.keyboardFlapp()
                    didHandleEvent = true
                }
            } else {
            }
        }
        
        if didHandleEvent == false {
            super.pressesBegan(presses, with: event)
        }
    }
}
