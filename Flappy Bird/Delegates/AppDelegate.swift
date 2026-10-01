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

        // Beta play log (Settings > Logs); see GameLog.swift.
        GameLog.start()

        // Pull scores and stats from iCloud before any screen reads them.
        CloudSync.start()

        activateAudioSession("launch")

        // A call, Siri or an alarm deactivates the session; turn it back on
        // when the interruption ends so sounds do not stay silent.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { note in
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else {
                return
            }
            activateAudioSession("interruptionEnded")
        }

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

/// Game sounds follow the volume slider, not the Silent switch (the owner's
/// preference), and mix with any music or podcast playing. Called at launch,
/// on every return to the foreground and after an interruption, because the
/// session set once at launch does not stay active on its own.
func activateAudioSession(_ context: String) {
    do {
        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            options: [.mixWithOthers]
        )
        try AVAudioSession.sharedInstance().setActive(true)
        logAudioSession(context)
    } catch {
        logAudioSession(context, error: error)
    }
}

/// Sound diagnostics (Debug builds only): prints the audio session state so a
/// device run shows whether the session is set up when a sound plays.
func logAudioSession(_ context: String, error: Error? = nil) {
    #if DEBUG
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs
        .map { $0.portType.rawValue }
        .joined(separator: ",")
    NSLog(
        "[audio] %@ category=%@ options=%lu volume=%.2f otherAudio=%ld outputs=%@ error=%@",
        context,
        session.category.rawValue,
        session.categoryOptions.rawValue,
        session.outputVolume,
        session.isOtherAudioPlaying ? 1 : 0,
        outputs,
        error.map { "\($0)" } ?? "none"
    )
    #endif
}
