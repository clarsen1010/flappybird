//
//  LoadingViewController.swift
//  Flappy Bird
//
//  Created by Brandon Plank on 6/11/22.
//  Copyright © 2022 Brandon Plank & Thatcher Clough. All rights reserved.
//

import Foundation
import UIKit
//import Sentry

class LoadingViewController: UIViewController {
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var infoLabel: UILabel!

    // Match the game screen; without this the status bar flashes during load.
    override var prefersStatusBarHidden: Bool { true }

    // This screen stays underneath the game as the window's root, and iOS
    // asks the root which screen edges should give touches to the app
    // first. See GameViewController for why the bottom edge does.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.bottom] }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("Showing launch screen")
        // "5.0.3" -> "5.0 Edition": the patch number changes every install, the edition doesn't.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let edition = version.split(separator: ".").prefix(2).joined(separator: ".")
        infoLabel.text = """
Flappy Bird \(edition) Edition
by Christian Larsen

Original game © 2019 - \(Calendar.current.component(.year, from: Date()))
Brandon Plank, ThatcherDev

See license for details.
"""
        DispatchQueue.global(qos: .background).async {
            sleep(1)
            DispatchQueue.main.async {
                self.progressLabel.text = "Loading"
//                SentrySDK.start { options in
//                    options.dsn = "https://991041777f23449d8f13e438d7911c1f@o956450.ingest.sentry.io/5983798"
//                    options.tracesSampleRate = 0.5
//                    options.debug = false
//                }
            }
            DispatchQueue.main.async {
                self.progressLabel.text = "Preloading sprites"
                Assets.shared.preloadAssets()
                self.progressLabel.text = "Done"
            }
            //sleep(2)
            DispatchQueue.main.async {
                let gameViewController = self.storyboard?.instantiateViewController(withIdentifier: "GameViewController") as! GameViewController
                gameViewController.modalPresentationStyle = .fullScreen
                gameViewController.modalTransitionStyle = .crossDissolve
                        
                self.present(gameViewController, animated: true, completion: nil)
            }
        }
    }
}
