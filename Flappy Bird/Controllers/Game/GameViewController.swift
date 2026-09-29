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

    /// Landscape prototype: the game keeps whichever orientation the phone was
    /// held in when it appeared; turning the phone mid-game does nothing.
    private lazy var lockedOrientations: UIInterfaceOrientationMask = {
        let orientation = view.window?.windowScene?.interfaceOrientation
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
                .first
            ?? .portrait

        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { lockedOrientations }
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
        becomeFirstResponder()

        // Dark Mode follows the phone mid-game too. iOS 16 picks up a change
        // at the next round instead.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.scene?.refreshTheme()
            }
        }
    }
    
    /// The scene is presented on the first layout, once the view has its real
    /// size. In landscape the scene widens to the screen's shape at the same
    /// height (768), so the vertical layout is unchanged. Portrait keeps the
    /// original 1024-wide scene.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let skView = view as? SKView, skView.scene == nil, let scene else {
            return
        }

        _ = lockedOrientations
        let bounds = skView.bounds.size
        if bounds.width > bounds.height {
            scene.size = CGSize(
                width: (scene.size.height * bounds.width / bounds.height).rounded(),
                height: scene.size.height
            )
        }

        skView.presentScene(scene)
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
