//
//  AppDelegate.swift
//  Flappy Bird
//
//  Created by Thatcher Clough on 4/30/20.
//  Copyright © 2020 Brandon Plank & Thatcher Clough. All rights reserved.
//

import UIKit
import AVFoundation
import Foundation
import SpriteKit
// import Sentry

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Assets.shared.preloadAssets()

        // Game sounds follow the volume slider, not the Silent switch (the
        // owner's preference), and mix with any music or podcast playing.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        // SentrySDK.start { options in
        //     options.dsn = "..."
        //     options.tracesSampleRate = 0.5
        //     options.debug = false
        // }

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {

        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Called when the user discards a scene session.
    }
}
