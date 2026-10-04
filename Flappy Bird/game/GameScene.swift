//
//  GameScene.swift
//  FlappyBird
//
//  Created by Brandon Plank on 12/2/19.
//  Modified by Thatcher Clough on 4/1/20.
//  Copyright (c) 2020 Brandon Plank. All rights reserved.
//

import AVFoundation
import SpriteKit
import StoreKit

// MARK: - Extensions

extension SKTexture {
    var width: CGFloat {
        size().width
    }

    var height: CGFloat {
        size().height
    }
}

extension SKNode {
    var width: CGFloat {
        frame.width
    }

    var height: CGFloat {
        frame.height
    }
}

// MARK: - Physics

struct PhysicsCategory {
    static let bird: UInt32 = 1 << 0
    static let land: UInt32 = 1 << 1
    static let pipe: UInt32 = 1 << 2
    static let score: UInt32 = 1 << 3
}

// Keep the original name available if other project files use it.
typealias PhysicsCatagory = PhysicsCategory

// MARK: - Z Positions

struct GameZPosition {
    static let sky: CGFloat = -3
    static let pipe: CGFloat = -2
    static let bird: CGFloat = -1
    static let land: CGFloat = 0
    static let score: CGFloat = 1
    static let result: CGFloat = 2
    static let resultText: CGFloat = 3
}

// Keep the original name available if other project files use it.
typealias GamezPosition = GameZPosition

// MARK: - Global Game Data

public final class ScreenData {
    static let shared = ScreenData()

    var height: CGFloat = 0
    var width: CGFloat = 0

    private init() {}
}


// Keep compatibility with existing project code.
typealias screenData = ScreenData

var canShowScore = true
var timeTook: Double = 0
var rosesCounter = 0
var hasRanFor1time = false

// MARK: - Game Scene

final class GameScene: SKScene {

    // MARK: Constants

    private enum Constants {
        // Reachable, and not on a gold milestone (100, 200, ...).
        static let superScore = 250

        static let milestoneGold = UIColor(red: 1, green: 0.78, blue: 0.05, alpha: 1)

        static let gravity = CGVector(dx: 0, dy: -12)

        static let verticalPipeGap: CGFloat = 130
        static let pipeScale: CGFloat = 2
        static let birdScale: CGFloat = 1.25

        static let menuButtonSpacing: CGFloat = 84

        static let idleFloatDistance: CGFloat = 35
        static let idleFloatDuration: TimeInterval = 1

        static let flapImpulse: CGFloat = 15
        static let flapRotation: CGFloat = 0.45
        static let flapRotationHold: TimeInterval = 0.65

        static let minimumBirdYOffset: CGFloat = 20

        static let groundMoveSpeed: TimeInterval = 0.005
        static let skyMoveSpeed: TimeInterval = 0.1
        static let pipeMoveSpeed: TimeInterval = 0.005

        static let animationFrameDuration: TimeInterval = 0.1

        static let uiAnimationDuration: TimeInterval = 0.1
        static let toggleAnimationDuration: TimeInterval = 0.12

        static let pauseButtonScale: CGFloat = 2.4
        static let pauseButtonInset: CGFloat = 45

        static let gameOverDelay: TimeInterval = 0.8
        static let resultDelay: TimeInterval = 0.2

        /// See didFinishUpdate(): the longest pause before drawing, and the
        /// time always left for the draw itself before the frame is due.
        static let drawPause: TimeInterval = 0.003
        static let drawReserve: TimeInterval = 0.0045

        /// How far the ground (and the sky above it) sits below the original
        /// layout. 0 = original (ground top at 29% of the screen); 78 puts it
        /// at 19%, Christian's pick.
        static let groundDrop: CGFloat = 78
    }

    // The sky art's flat top color. The scene background matches it, so a
    // lowered sky (groundDrop) leaves no visible strip above it.
    private static let daySkyTop = UIColor(red: 78 / 255, green: 192 / 255, blue: 202 / 255, alpha: 1)
    private static let nightSkyTop = UIColor(red: 0, green: 135 / 255, blue: 147 / 255, alpha: 1)

    /// How the world is drawn: day or night in the normal game, and each
    /// hard mode's own colours (made by hard_art.py, which also prints
    /// the sky-top colours below).
    private enum Look: String {
        case day, night, hard, insane, impossible

        var skyTop: UIColor {
            switch self {
            case .day: return GameScene.daySkyTop
            case .night: return GameScene.nightSkyTop
            case .hard: return UIColor(red: 45 / 255, green: 53 / 255, blue: 68 / 255, alpha: 1)
            case .insane: return UIColor(red: 24 / 255, green: 3 / 255, blue: 8 / 255, alpha: 1)
            case .impossible: return UIColor(red: 6 / 255, green: 5 / 255, blue: 10 / 255, alpha: 1)
            }
        }

        /// The colour the screen flashes when the mode button turns to it.
        var flash: UIColor {
            switch self {
            case .day, .night: return .white
            case .hard: return UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1)
            case .insane: return UIColor(red: 0.70, green: 0.02, blue: 0.05, alpha: 1)
            case .impossible: return .black
            }
        }
    }

    private struct LookArt {
        let sky, ground, pipeUp, pipeDown: SKTexture
    }

    private lazy var lookArt: [Look: LookArt] = {
        func texture(_ name: String) -> SKTexture {
            Assets.shared.sprites.textureNamed(name).then { $0.filteringMode = .nearest }
        }

        var art: [Look: LookArt] = [
            .day: LookArt(sky: dayTexture, ground: groundTexture, pipeUp: pipeTextureUp, pipeDown: pipeTextureDown),
            .night: LookArt(sky: nightTexture, ground: groundNightTexture, pipeUp: pipeNightTextureUp, pipeDown: pipeNightTextureDown),
        ]
        for look in [Look.hard, .insane, .impossible] {
            art[look] = LookArt(
                sky: texture("\(look.rawValue)-sky"),
                ground: texture("\(look.rawValue)-land"),
                pipeUp: texture("\(look.rawValue)-PipeUp"),
                pipeDown: texture("\(look.rawValue)-PipeDown")
            )
        }
        return art
    }()

    private let groundNightTexture =
        Assets.shared.sprites.textureNamed("night-land").then { $0.filteringMode = .nearest }
    private let pipeNightTextureUp =
        Assets.shared.sprites.textureNamed("night-PipeUp").then { $0.filteringMode = .nearest }
    private let pipeNightTextureDown =
        Assets.shared.sprites.textureNamed("night-PipeDown").then { $0.filteringMode = .nearest }
    
    private struct SeededRandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed
        }

        mutating func next() -> UInt64 {
            // SplitMix64
            state &+= 0x9E3779B97F4A7C15

            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextInt(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(next() % span)
        }
    }

    // MARK: Game mode

    /// The mode of the round being played, fixed when it starts. The menu
    /// and the panels follow GameMode.current.
    private var roundMode = GameMode.normal
    /// The world's speed: 1 in the normal game.
    private var speedFactor: CGFloat = 1
    private var pipePlanner = PipePlanner(tuning: GameMode.normal.tuning)
    private var pipesSpawned = 0
    private var hasExtraLife = false
    /// The headstones of this round, by the pipe they stand before.
    private var graveMarkers: [Int: GraveMarker] = [:]

    /// Sets the world's speed: the scenery and pipes (everything under
    /// `moving`) and the pipe spawner together, so the pipes stay the same
    /// distance apart. The normal game passes 1.
    private func applySpeed(_ speed: Double) {
        speedFactor = CGFloat(speed)
        moving.speed = speedFactor
        action(forKey: "pipeSpawner")?.speed = speedFactor
    }

    /// The heart under the score while an extra life is held.
    private lazy var heartNode = SKLabelNode(fontNamed: "KongtextRegular").then {
        $0.text = "+1 LIFE"
        $0.fontSize = 12
        $0.fontColor = UIColor(red: 1, green: 0.35, blue: 0.40, alpha: 1)
        $0.verticalAlignmentMode = .center
        $0.position = CGPoint(x: width / 2, y: 3 * height / 4 - 26)
        $0.zPosition = GameZPosition.score + 1
    }

    // MARK: Pipe seed
    private var pipeSeed: UInt64 = 123456789
    private var pipeRandom = SeededRandomNumberGenerator(seed: UInt64(arc4random()))

    // These remain static because other project files may reference them.
    static let settingsButtonTexture =
        Assets.shared.sprites.textureNamed("settings")

    static let blankButtonTexture =
        Assets.shared.sprites.textureNamed("blank-button")
    
    static let smallPlayButtonTexture =
        Assets.shared.sprites.textureNamed("smallresume")
    
    static let smallPauseButtonTexture =
        Assets.shared.sprites.textureNamed("smallpause")
    

    static var hitButton = true

    // MARK: Game State

    private var score = 0 {
        didSet {
            scoreLabelNode.text = String(score)
            scoreLabelNodeInside.text = String(score)
        }
    }

    private var gameStartTime: TimeInterval = 0
    private var lastFlapTime: TimeInterval = 0

    /// Get Ready appears behind the black fade from Play; taps start the
    /// round only once the fade has cleared.
    private var startAllowedAt: TimeInterval = 0

    private var isWaitingToStart = false
    private var isGameOver = false
    private var hasHitGround = false
    private var isShowingGameOver = false

    private var playFlapSound = false

    private var playSounds = true
    private var haptics = true
    /// On: day or night follows the phone's appearance. Off: always day.
    private var darkMode = true
    /// On: the beta play log is recorded (see GameLog).
    private var logsOn = GameLog.defaultOn

    // For the play log: the last two frame times, and the last tap.
    private var lastFrameTime: TimeInterval = 0
    private var frameTimeBefore: TimeInterval = 0
    private var lastTapTime: TimeInterval = 0
    private var lastTapPoint = CGPoint.zero
    /// The first frame after a pause is as long as the pause; not a slow frame.
    private var skipFrameLog = false
    private var lastBirdY: CGFloat = 0
    private var lastUpdateClock: TimeInterval = 0
    /// The bird as it was drawn in the last frame (its state when update
    /// starts, before this frame's physics).
    private var drawnBirdPosition = CGPoint.zero
    private var drawnBirdVelocityY: CGFloat = 0
    /// Scheduled time simulated since that drawn frame, and how many
    /// frames in between were simulated without being drawn.
    private var timeSinceDrawn: TimeInterval = 0
    private var undrawnSinceDrawn = 0
    private var drawnCountAtLastUpdate = 0
    private var realFrameTime: TimeInterval = 0

    private var skyNodes = [SKSpriteNode]()
    private var groundNodes = [SKSpriteNode]()
    private var birdTextures = [SKTexture(), SKTexture(), SKTexture()]

    // MARK: Feedback

    private let impactFeedback = UIImpactFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let deathFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private let flapFeedback = UIImpactFeedbackGenerator(style: .light)
    /// Softer than the flap tick, so a point never feels like a tap he
    /// did not make.
    private let scoreFeedback = UIImpactFeedbackGenerator(style: .soft)

    // MARK: Sounds

    private let flapSound = SKAction.playSoundFileNamed(
        "sounds/sfx_wing.caf",
        waitForCompletion: false
    )

    private let dieSound = SKAction.playSoundFileNamed(
        "sounds/sfx_die.caf",
        waitForCompletion: false
    )

    private let pointSound = SKAction.playSoundFileNamed(
        "sounds/sfx_point.wav",
        waitForCompletion: false
    )

    private let hitSound = SKAction.playSoundFileNamed(
        "sounds/sfx_hit.caf",
        waitForCompletion: false
    )

    private let swooshSound = SKAction.playSoundFileNamed(
        "sounds/sfx_swooshing.caf",
        waitForCompletion: false
    )

    // MARK: Textures

    private let pipeTextureUp =
        Assets.shared.sprites.textureNamed("PipeUp").then {
            $0.filteringMode = .nearest
        }

    private let pipeTextureDown =
        Assets.shared.sprites.textureNamed("PipeDown").then {
            $0.filteringMode = .nearest
        }

    private let groundTexture =
        Assets.shared.sprites.textureNamed("land").then {
            $0.filteringMode = .nearest
        }

    private let gameOverTexture =
        Assets.shared.sprites.textureNamed("gameover")

    private let flappyBirdTexture =
        Assets.shared.sprites.textureNamed("flappybird")

    private let getReadyTexture =
        Assets.shared.sprites.textureNamed("get-ready")

    private let tapTapTexture =
        Assets.shared.sprites.textureNamed("taptap")

    private let defaultBirdTexture =
        Assets.shared.sprites.textureNamed("yellow-bird-1")

    private let playButtonTexture =
        Assets.shared.sprites.textureNamed("flappyplay")

    private let dayTexture =
        Assets.shared.sprites.textureNamed("day-sky").then {
            $0.filteringMode = .nearest
        }

    private let nightTexture =
        Assets.shared.sprites.textureNamed("night-sky").then {
            $0.filteringMode = .nearest
        }

    // MARK: Scene Nodes

    private let moving = SKNode()

    // Shakes the whole view on death. A camera, because gameOver() stops
    // `moving` (speed 0), which would freeze a shake run on the world nodes.
    private let shakeCamera = SKCameraNode()
    private let pipes = SKNode()

    private lazy var bird = makeBird()
    private lazy var ground = makeGround()

    /// Wooden cross that pops up where the bird lands.
    private lazy var graveNode = SKSpriteNode(
        texture: Assets.shared.sprites.textureNamed("grave-cross").then {
            $0.filteringMode = .nearest
        }
    ).then {
        $0.anchorPoint = CGPoint(x: 0.5, y: 0)
        $0.zPosition = GameZPosition.bird - 0.5
    }

    private lazy var flappyBird = makeFlappyBird()
    private lazy var getReady = makeGetReady()
    private lazy var tapTap = makeTapTap()

    private lazy var gameOverNode = makeGameOverNode()
    private lazy var resultNode = makeResultNode()
    private lazy var settingsNode = makeSettingsNode()
    private lazy var bestRunsNode = makeBestRunsNode()
    private lazy var friendsNode = makeFriendsNode()

    /// "random" or one of pickableBirds; chosen with the bird-picker button.
    private var birdChoice = "random"

    /// The color flying this round, for the dead-bird look and the play log.
    private var currentBirdColor = "yellow"

    private lazy var playButton = makePlayButton()

    /// Under Play on the title and Game Over screens: the game's mode. A
    /// tap turns it to the next one.
    private lazy var modeButton = PanelButton(name: "mode", text: "", textSize: 8, width: 152, height: 30, hit: CGSize(width: 160, height: 40)).then {
        $0.setScale(1.2)
        $0.position = CGPoint(x: width / 2, y: 196)
        $0.zPosition = GameZPosition.result
    }
    private lazy var pauseButton = makePauseButton()
    private lazy var resumeButton = makeResumeButton()
    private lazy var pauseOverlay = makePauseOverlay()

    /// On the pause screen: ends the round and goes to the menu.
    private lazy var pauseMenuButton = PanelButton(name: "pauseMenu", text: "MENU", width: 96, hit: CGSize(width: 110, height: 50)).then {
        $0.setScale(1.5)
        $0.position = CGPoint(x: width / 2, y: height / 2)
        $0.zPosition = 100
    }

    private var isPausedByUser = false

    private var lastUpdateTime: TimeInterval = 0

    private lazy var scoreLabelNode = SKLabelNode(
        fontNamed: "04b_19"
    ).then {
        $0.fontColor = .black
        $0.fontSize = 50
        $0.position = CGPoint(
            x: width / 2,
            y: 3 * height / 4
        )
        $0.zPosition = GameZPosition.score + 1
    }

    private lazy var scoreLabelNodeInside = SKLabelNode(
        fontNamed: "inside"
    ).then {
        $0.fontColor = .white
        $0.fontSize = 50
        $0.position = CGPoint(
            x: width / 2 - 1.5,
            y: 3 * height / 4
        )
        $0.zPosition = GameZPosition.score
    }

    // MARK: Static Buttons

    /// The word under a menu button. It carries the button's name, so a
    /// tap on the word presses the button.
    private static func caption(_ text: String, button name: String) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: 0, y: -27)

        for (z, (color, offset)) in [(PanelButton.textColor, CGPoint(x: 0, y: -1)), (UIColor.white, .zero)].enumerated() {
            node.addChild(SKLabelNode(fontNamed: "KongtextRegular").then {
                $0.name = name
                $0.text = text
                $0.fontSize = 8
                $0.fontColor = color
                $0.verticalAlignmentMode = .center
                $0.position = offset
                $0.zPosition = CGFloat(z + 1)
            })
        }

        return node
    }

    private static var settingsButton =
        SKSpriteNode(
            texture: settingsButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "settings"
            $0.setScale(1.2)
            $0.addChild(caption("SETTINGS", button: "settings"))
        }

    /// Taps resolve to the deepest node, so each icon carries its
    /// button's name.
    private static let birdPickerIcon =
        SKSpriteNode(
            texture: Assets.shared.sprites.textureNamed("yellow-bird-1").then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "birdPicker"
            $0.setScale(0.9)
            $0.position = CGPoint(x: 0, y: 1)
            $0.zPosition = 1
        }

    private static var birdPickerButton =
        SKSpriteNode(
            texture: blankButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "birdPicker"
            $0.setScale(1.2)
            $0.addChild(birdPickerIcon)
            $0.addChild(caption("BIRD", button: "birdPicker"))
        }

    private static var bestRunsButton =
        SKSpriteNode(
            texture: blankButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "bestRuns"
            $0.setScale(1.2)
            $0.addChild(caption("STATS", button: "bestRuns"))
            $0.addChild(
                SKSpriteNode(
                    texture: Assets.shared.sprites.textureNamed("charts-podium").then {
                        $0.filteringMode = .nearest
                    }
                ).then {
                    $0.name = "bestRuns"
                    $0.position = CGPoint(x: 0, y: 1)
                    $0.zPosition = 1
                }
            )
        }

    /// How many new people added you; on the Friends button's corner.
    private static let friendsBadgeLabel = SKLabelNode(fontNamed: "KongtextRegular").then {
        $0.name = "friends"
        $0.fontSize = 8
        $0.fontColor = .white
        $0.verticalAlignmentMode = .center
        $0.zPosition = 1
    }

    private static let friendsBadge = SKSpriteNode(
        color: UIColor(red: 228 / 255, green: 60 / 255, blue: 50 / 255, alpha: 1),
        size: CGSize(width: 18, height: 13)
    ).then {
        $0.name = "friends"
        $0.position = CGPoint(x: 24, y: 14)
        $0.zPosition = 2
        $0.isHidden = true
        $0.addChild(friendsBadgeLabel)
    }

    /// Two birds facing each other.
    private static var friendsButton =
        SKSpriteNode(
            texture: blankButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then { button in
            button.name = "friends"
            button.setScale(1.2)
            button.addChild(caption("FRIENDS", button: "friends"))
            button.addChild(friendsBadge)

            for (color, x, facing) in [("red", CGFloat(-11), CGFloat(1)), ("yellow", 11, -1)] {
                button.addChild(
                    SKSpriteNode(
                        texture: Assets.shared.sprites.textureNamed("\(color)-bird-1").then {
                            $0.filteringMode = .nearest
                        }
                    ).then {
                        $0.name = "friends"
                        $0.xScale = 0.6 * facing
                        $0.yScale = 0.6
                        $0.position = CGPoint(x: x, y: 1)
                        $0.zPosition = 1
                    }
                )
            }
        }

    private static let pickableBirds = [
        "yellow", "red", "blue", "green", "peach", "purple", "kup"
    ]

    // MARK: Idle Animation

    private lazy var idleAnimation: SKAction = {
        let floatUp = SKAction.moveBy(
            x: 0,
            y: Constants.idleFloatDistance,
            duration: Constants.idleFloatDuration
        )

        let floatDown = SKAction.moveBy(
            x: 0,
            y: -Constants.idleFloatDistance,
            duration: Constants.idleFloatDuration
        )

        return SKAction.repeatForever(
            SKAction.sequence([
                floatUp,
                floatDown
            ])
        )
    }()

    // MARK: Scene Setup

    override func didMove(to view: SKView) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        configureSettings()
        configureScene()
        configurePhysics()
        configureWorld()

        startIdleAnimation()
        checkFriendsBadge()
        startLightning()
    }

    private func configureScene() {
        ScreenData.shared.height = height
        ScreenData.shared.width = width

        addChild(flappyBird)
        addChild(moving)

        moving.addChild(pipes)

        addChild(bird)
        addChild(ground)

        // Centered on the scene, the camera shows exactly what the view
        // showed without one.
        shakeCamera.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(shakeCamera)
        camera = shakeCamera

        placeMenuButtons()
        refreshBirdPickerIcon()
        addChild(Self.birdPickerButton)
        addChild(Self.bestRunsButton)
        addChild(Self.friendsButton)
        addChild(Self.settingsButton)
        addChild(playButton)
        showModeName()
        addChild(modeButton)
        pauseButton.removeFromParent()
        resumeButton.removeFromParent()

        score = 0

        // The title's scenery already moves at the chosen mode's pace.
        moving.speed = CGFloat(GameMode.current.tuning.startSpeed)
        bird.speed = 1

        pipes.setScale(0)
    }

    private func configurePhysics() {
        physicsWorld.gravity = Constants.gravity
        physicsWorld.contactDelegate = self
    }

    private func configureWorld() {
        createGroundMovement()
        createSky()
        refreshTheme()
        updateBirdTextures()
        startPipeSpawner()
    }

    // MARK: Settings

    private func configureSettings() {
        playSounds = loadBoolSetting(
            key: "playSounds",
            defaultValue: true
        )

        haptics = loadBoolSetting(
            key: "haptics",
            defaultValue: true
        )

        darkMode = loadBoolSetting(
            key: "darkMode",
            defaultValue: true
        )

        logsOn = loadBoolSetting(
            key: GameLog.settingKey,
            defaultValue: GameLog.defaultOn
        )

        if let choice = UserDefaults.standard.string(forKey: "birdChoice"),
           Self.pickableBirds.contains(choice) {
            birdChoice = choice
        }

        updateSettingsUI()
    }

    private func loadBoolSetting(
        key: String,
        defaultValue: Bool
    ) -> Bool {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: key) == nil {
            defaults.set(defaultValue, forKey: key)
        }

        return defaults.bool(forKey: key)
    }

    private func saveSetting(
        _ value: Bool,
        key: String
    ) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func updateSettingsUI() {
        settingsNode.showName(FriendsStore.myName)
        settingsNode.modeButton.text = GameMode.current.title

        settingsNode.setSwitch(.sound, on: playSounds, animated: false)
        settingsNode.setSwitch(.haptics, on: haptics, animated: false)
        settingsNode.setSwitch(.darkMode, on: darkMode, animated: false)
        settingsNode.setSwitch(.logs, on: logsOn, animated: false)
    }

    // MARK: Node Creation

    private func makeBird() -> SKSpriteNode {
        SKSpriteNode(
            texture: defaultBirdTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.setScale(Constants.birdScale)
            $0.zPosition = GameZPosition.bird
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 75
            )

            $0.physicsBody = SKPhysicsBody(
                circleOfRadius: $0.height / 2
            ).then {
                $0.isDynamic = false
                $0.categoryBitMask = PhysicsCategory.bird
                $0.collisionBitMask =
                    PhysicsCategory.land |
                    PhysicsCategory.pipe
                $0.contactTestBitMask =
                    PhysicsCategory.land |
                    PhysicsCategory.pipe
            }
        }
    }

    private func makeGround() -> SKNode {
        SKNode().then {
            $0.position = CGPoint(
                x: 0,
                y: groundTexture.height - Constants.groundDrop
            )

            $0.zPosition = GameZPosition.land

            $0.physicsBody = SKPhysicsBody(
                rectangleOf: CGSize(
                    width: width,
                    height: groundTexture.height * 2
                )
            ).then {
                $0.isDynamic = false
                $0.categoryBitMask = PhysicsCategory.land
            }
        }
    }

    private func makeFlappyBird() -> SKSpriteNode {
        SKSpriteNode(
            texture: flappyBirdTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.setScale(1.5)
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 200
            )
        }
    }

    private func makeGetReady() -> SKSpriteNode {
        SKSpriteNode(
            texture: getReadyTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.setScale(1.2)
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 130
            )
        }
    }

    private func makeTapTap() -> SKSpriteNode {
        SKSpriteNode(
            texture: tapTapTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.setScale(1.5)
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2
            )
        }
    }

    private func makeGameOverNode() -> SKSpriteNode {
        SKSpriteNode(
            texture: gameOverTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.setScale(1.5)
            $0.zPosition = GameZPosition.score
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 210
            )
        }
    }

    private func makeResultNode() -> ResultBoard {
        ResultBoard(score: score).then {
            $0.zPosition = GameZPosition.result
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 75
            )
        }
    }

    /// Panels hang from one top edge, just under the title: a 7-row panel
    /// (Best Runs) is centred 15 above the middle of the screen, and a
    /// taller or shorter one moves by half the difference.
    private func panelPosition(height panelHeight: CGFloat) -> CGPoint {
        CGPoint(
            x: width / 2,
            y: height / 2 + 15 + (PanelArt.height(rows: 7) - panelHeight) * 1.2 / 2
        )
    }

    private func makeSettingsNode() -> SettingsPanel {
        // The play-log switch is for testers. A player who already has
        // logs on keeps the row, so it can be turned off.
        let showsLogs = GameLog.defaultOn || UserDefaults.standard.bool(forKey: GameLog.settingKey)

        return SettingsPanel(showsLogs: showsLogs).then {
            $0.setScale(1.2)
            $0.zPosition = GameZPosition.resultText + 4
            $0.position = panelPosition(height: $0.panelHeight)
        }
    }

    private func makeBestRunsNode() -> BestRunsPanel {
        BestRunsPanel().then {
            $0.setScale(1.2)
            $0.zPosition = GameZPosition.resultText + 4
            $0.position = panelPosition(height: PanelArt.height(rows: 7))
        }
    }

    private func makeFriendsNode() -> FriendsPanel {
        FriendsPanel().then {
            $0.setScale(1.2)
            $0.zPosition = GameZPosition.resultText + 4
            $0.position = panelPosition(height: PanelArt.height(rows: 8))
        }
    }

    private func makePlayButton() -> SKSpriteNode {
        SKSpriteNode(
            texture: playButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "play"
            $0.setScale(1.2)
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 - 115
            )
        }
    }
    
    private func pauseButtonPosition() -> CGPoint {
        guard let view = self.view else {
            return CGPoint(
                x: 32,
                y: height - 32
            )
        }

        let safeInsets = view.safeAreaInsets

        // Top-left corner of the device's safe area, in SKView coordinates.
        let topLeftInView = CGPoint(
            x: view.bounds.minX + safeInsets.left,
            y: view.bounds.minY + safeInsets.top
        )

        // Convert the actual visible top-left into scene coordinates.
        let topLeftInScene = convertPoint(fromView: topLeftInView)

        // The button's position is its center.
        let buttonHalfWidth =
            Self.smallPauseButtonTexture.size().width *
            Constants.pauseButtonScale / 2

        let buttonHalfHeight =
            Self.smallPauseButtonTexture.size().height *
            Constants.pauseButtonScale / 2

        let margin: CGFloat = 12

        return CGPoint(
            x: topLeftInScene.x + buttonHalfWidth + margin,
            y: topLeftInScene.y - buttonHalfHeight - margin
        )
    }

    private func makePauseButton() -> SKSpriteNode {
        SKSpriteNode(
            texture: Self.smallPauseButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "pause"
            $0.setScale(Constants.pauseButtonScale)
            $0.position = pauseButtonPosition()
            $0.zPosition = 100
        }
    }

    private func makeResumeButton() -> SKSpriteNode {
        SKSpriteNode(
            texture: Self.smallPlayButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "resume"
            $0.setScale(Constants.pauseButtonScale)
            $0.position = pauseButtonPosition()
            $0.zPosition = 100
        }
    }

    private func makePauseOverlay() -> SKShapeNode {
        SKShapeNode(
            rect: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        ).then {
            $0.name = "pauseOverlay"
            $0.fillColor = .black
            $0.strokeColor = .clear
            $0.alpha = 0.55
            $0.zPosition = GameZPosition.resultText + 4
        }
    }

    // MARK: Bird

    private func updateBirdTextures() {
        let randomValue = Float.random(in: 0..<1)
        var roundColor = "yellow"

        for index in 0...2 {
            let color: String

            if birdChoice != "random" {
                color = birdChoice
            } else {
                switch randomValue {
                case ..<0.161:
                    color = "yellow"
                case ..<0.322:
                    color = "red"
                case ..<0.483:
                    color = "blue"
                case ..<0.644:
                    color = "green"
                case ..<0.805:
                    color = "peach"
                case ..<0.97:
                    color = "purple"
                default:
                    color = "kup"
                }
            }

            roundColor = color
            birdTextures[index] = birdTexture(color, frame: index + 1)
        }

        currentBirdColor = roundColor
        applyBirdAnimation()
    }

    /// A wing frame of a bird as the game's mode draws it: the plain bird
    /// in the normal game, an angry brow in HARD, X eyes in INSANE and
    /// IMPOSSIBLE (art from bird_art.py).
    private func birdTexture(_ color: String, frame: Int) -> SKTexture {
        let look: String

        switch GameMode.current {
        case .normal: look = ""
        case .hard: look = "-angry"
        case .insane, .impossible: look = "-x"
        }

        return Assets.shared.sprites.textureNamed("\(color)-bird\(look)-\(frame)").then {
            $0.filteringMode = .nearest
        }
    }

    /// The same bird in the mode's look, after the mode button changed it.
    private func refreshBirdLook() {
        birdTextures = (1...3).map { birdTexture(currentBirdColor, frame: $0) }
        applyBirdAnimation()
    }

    private func applyBirdAnimation() {
        let animation = SKAction.animate(
            with: [
                birdTextures[0],
                birdTextures[1],
                birdTextures[2],
                birdTextures[1]
            ],
            timePerFrame: Constants.animationFrameDuration
        )

        bird.removeAction(forKey: "birdAnimation")

        bird.run(
            SKAction.repeatForever(animation),
            withKey: "birdAnimation"
        )
    }

    private func startIdleAnimation() {
        bird.removeAction(forKey: "idle")

        bird.run(
            idleAnimation,
            withKey: "idle"
        )
    }

    private func stopIdleAnimation() {
        bird.removeAction(forKey: "idle")
    }

    private func flapBird() {
        guard moving.speed > 0 else {
            return
        }

        guard bird.physicsBody?.isDynamic == true else {
            return
        }

        guard bird.position.y < height + Constants.minimumBirdYOffset else {
            GameLog.add(String(format: "flap ignored: bird above the screen (y=%.0f)", bird.position.y))
            return
        }

        lastFlapTime = CFAbsoluteTimeGetCurrent()

        bird.zRotation = Constants.flapRotation

        bird.physicsBody?.velocity = CGVector(
            dx: 0,
            dy: 0
        )

        bird.physicsBody?.applyImpulse(
            CGVector(
                dx: 0,
                dy: Constants.flapImpulse
            )
        )

        if playSounds {
            run(flapSound)
        }

        if haptics {
            flapFeedback.impactOccurred()
            // Keeps the engine ready so the next tick lands with the tap.
            flapFeedback.prepare()
        }
    }

    private func updateBirdRotation(deltaTime: TimeInterval) {
        guard let physicsBody = bird.physicsBody,
              physicsBody.isDynamic else {
            return
        }

        let timeSinceFlap =
            CFAbsoluteTimeGetCurrent() - lastFlapTime

        if timeSinceFlap < Constants.flapRotationHold {
            bird.zRotation = Constants.flapRotation
            return
        }

        let velocityY = physicsBody.velocity.dy

        let targetRotation = min(
            max(
                velocityY *
                    (velocityY < 0.4 ? 0.003 : 0.001),
                -1.57
            ),
            0.6
        )

        // 0.15 per frame at 60 Hz, scaled by elapsed time so the tilt eases
        // the same at 120 Hz instead of twice as fast.
        let smoothing = 1 - pow(0.85, CGFloat(deltaTime * 60))

        bird.zRotation +=
            (targetRotation - bird.zRotation) * smoothing

        bird.speed = targetRotation < -0.7 ? 2 : 1
    }

    // MARK: Game Loop

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = lastUpdateTime > 0 ?
            min(currentTime - lastUpdateTime, 1.0 / 30.0) : 1.0 / 60.0

        // Play log: the real frame time, counted while a round is live.
        frameTimeBefore = lastFrameTime
        lastFrameTime = lastUpdateTime > 0 ? currentTime - lastUpdateTime : 0

        // The bird as last seen: refreshed only when the previous frame
        // actually got drawn (SpriteKit can simulate a frame and skip it).
        if GameLog.drawnFrames != drawnCountAtLastUpdate {
            drawnBirdPosition = bird.position
            drawnBirdVelocityY = bird.physicsBody?.velocity.dy ?? 0
            timeSinceDrawn = 0
            undrawnSinceDrawn = 0
        } else {
            undrawnSinceDrawn += 1
        }
        drawnCountAtLastUpdate = GameLog.drawnFrames
        timeSinceDrawn += lastFrameTime
        let clock = CACurrentMediaTime()
        realFrameTime = lastUpdateClock > 0 ? clock - lastUpdateClock : 0
        lastUpdateClock = clock

        if skipFrameLog {
            skipFrameLog = false
        } else if isRoundLive, lastFrameTime > 0 {
            GameLog.frame(scheduled: lastFrameTime, real: realFrameTime, lead: currentTime - clock)

            // The bird is always moving in flight; the same height two
            // frames running means physics did not step last frame.
            if bird.position.y == lastBirdY, bird.physicsBody?.velocity.dy != 0 {
                GameLog.stuckFrames += 1
            }
        }
        lastBirdY = bird.position.y

        lastUpdateTime = currentTime

        guard !hasHitGround else {
            return
        }

        updateBirdRotation(deltaTime: deltaTime)
    }

    /// SpriteKit skips drawing a frame when no screen buffer is free at the
    /// moment it looks, and on this phone the buffer from two frames back
    /// is often a millisecond or two from being returned. The frame is then
    /// simulated but never shown: about 6 a second while tapping at 120 Hz,
    /// and worse in Low Power Mode with a finger on the glass, where iOS
    /// also delivers the frame callback late (measured on his iPhone 18 Pro,
    /// iOS 27.0.1, from the real presentation times).
    ///
    /// Pausing here, between the update and the draw, gives the buffer time
    /// to come back. Same 30 s rounds, frames shown late: tapping 190 -> 8,
    /// finger held 273 -> 19, untouched 74 -> 7; Low Power Mode with a
    /// finger held 194 -> 4. The pause is at most 3 ms and always leaves
    /// 4.5 ms before the frame is due, so it shrinks to nothing when the
    /// callback itself arrives late.
    override func didFinishUpdate() {
        guard !Self.drawPauseOff else {
            return
        }

        // lastUpdateTime is this frame's scheduled time (set in update).
        let leadAtStart = lastUpdateTime - lastUpdateClock
        let wake = lastUpdateClock + min(Constants.drawPause, leadAtStart - Constants.drawReserve)
        let now = CACurrentMediaTime()

        if now < wake {
            usleep(UInt32((wake - now) * 1_000_000))
        }
    }

    /// Launch with -noDrawPause to measure the game without the pause.
    private static let drawPauseOff =
        ProcessInfo.processInfo.arguments.contains("-noDrawPause")

    // MARK: Input

    override func touchesBegan(
        _ touches: Set<UITouch>?,
        with event: UIEvent?
    ) {
        guard let touch = touches?.first else {
            return
        }

        let location = touch.location(in: self)
        let nodeName = atPoint(location).name

        lastTapTime = CACurrentMediaTime()
        lastTapPoint = location
        GameLog.tap(
            touch,
            in: view,
            fingers: event?.allTouches?.count ?? 1,
            target: tapTarget(nodeName)
        )

        // Framed buttons look pushed in for a moment.
        if !Self.hitButton, let button = atPoint(location).parent as? PanelButton {
            button.press()
        }

        switch nodeName {
        case "play":
            handlePlayTap()
            
        case "pause":
            handlePauseTap()

        case "resume":
            handleResumeTap()

        case "pauseMenu":
            handlePauseMenu()

        case "settings":
            handleSettingsTap()

        case "birdPicker":
            handleBirdPickerTap()

        case "bestRuns":
            handleBestRunsTap()

        case "panelBack":
            handlePanelBack()

        case let name? where name.hasPrefix("tab"):
            handleTabTap(name)

        case let name? where name.hasPrefix("scope"):
            handleScopeTap(name)

        case "mode", "settingsMode":
            handleModeTap()

        case "friendsMode", "bestRunsMode":
            handlePanelModeTap()

        case "friends":
            handleFriendsTap()

        case "friendsPrev":
            handleFriendsTurn(by: -1)

        case "friendsNext":
            handleFriendsTurn(by: 1)

        case "friendsAdd":
            handleFriendsAdd()

        case "friendsMe":
            handleFriendsMe()

        case "friendsShare":
            handleFriendsShare()

        case let name? where name.hasPrefix("friendsRow"):
            handleFriendsRow(Int(name.dropFirst("friendsRow".count)) ?? 0)

        case let name? where name.hasPrefix("friendsAddBack"):
            handleFriendsAddBack(row: Int(name.dropFirst("friendsAddBack".count)) ?? 0)

        case "editName":
            handleNameTap()

        case "toggleSounds":
            handleSoundToggle()

        case "toggleHaptics":
            handleHapticsToggle()

        case "toggleDarkMode":
            handleDarkModeToggle()

        case "toggleLogs":
            handleLogsToggle()

        default:
            // A panel is open: a tap outside it closes it, a tap on it
            // (a label, an empty row) does nothing.
            if let panel = openPanel {
                if !panel.calculateAccumulatedFrame().contains(location) {
                    handlePanelBack()
                }
                return
            }

            // On the menu, tapping the bird switches birds like the picker.
            if isOnMenu, hypot(location.x - bird.position.x, location.y - bird.position.y) < 45 {
                handleBirdPickerTap()
                return
            }

            handleGameTap()
        }
    }

    /// Launch title screen with the menu row showing (no panel open). Not the
    /// game-over screen: the dead bird keeps its look there.
    private var isOnMenu: Bool {
        !isWaitingToStart && playButton.parent != nil && playButton.xScale > 1
            && !isGameOver
    }

    /// The panel on screen, if any. Looks only at what is on screen: naming
    /// the lazy panels would build them all on the first tap of a session,
    /// which is the tap that starts a round (up to ~9 ms).
    private var openPanel: SKNode? {
        children.first { $0 is SettingsPanel || $0 is BestRunsPanel || $0 is FriendsPanel }
    }

    /// A round in flight: started, not dead, not paused.
    private var isRoundLive: Bool {
        !isWaitingToStart && !isGameOver && !isPausedByUser
            && bird.physicsBody?.isDynamic == true
    }

    /// For the play log: what a tap landed on, or what the game will do with it.
    private func tapTarget(_ nodeName: String?) -> String {
        switch nodeName {
        case "play", "pause", "settings", "birdPicker", "bestRuns",
             "panelBack", "tabRuns", "tabStats", "tabGoals", "tabHard", "friends",
             "mode", "settingsMode", "friendsMode", "bestRunsMode",
             "tabFriends", "tabEveryone", "tabAdded", "scopeToday", "scopeWeek", "scopeMonth", "scopeAll",
             "friendsPrev", "friendsNext", "friendsAdd", "friendsMe", "friendsShare", "editName",
             "friendsRow0", "friendsRow1", "friendsRow2", "friendsRow3", "friendsRow4",
             "friendsAddBack0", "friendsAddBack1", "friendsAddBack2", "friendsAddBack3", "friendsAddBack4",
             "toggleSounds", "toggleHaptics", "toggleDarkMode", "toggleLogs":
            // These ignore taps while the button lock is on.
            return (nodeName ?? "?") + (Self.hitButton ? " (locked, ignored)" : "")
        case "resume", "pauseMenu":
            return nodeName ?? "?"
        default:
            if openPanel != nil {
                return Self.hitButton ? "nothing (panel locked)" : "panel (a tap outside it closes it)"
            }
            if isPausedByUser { return "nothing (paused)" }
            if isWaitingToStart {
                return CACurrentMediaTime() < startAllowedAt ? "nothing (fade not finished)" : "start"
            }
            if isRoundLive { return "flap" }
            if isGameOver { return "nothing (game over)" }
            return isOnMenu && hypot(bird.position.x - lastTapPoint.x, bird.position.y - lastTapPoint.y) < 45
                ? "birdPicker (tapped the bird)" + (Self.hitButton ? " (locked, ignored)" : "")
                : "nothing (menu)"
        }
    }

    public func keyboardFlapp() {
        handleGameTap()
    }

    private func handleGameTap() {
        guard !isPaused, !isPausedByUser else {
            return
        }

        if isWaitingToStart {
            startGame()
            return
        }

        flapBird()
    }

    private func startGame() {
        guard isWaitingToStart else {
            return
        }

        guard CACurrentMediaTime() >= startAllowedAt else {
            return
        }

        isWaitingToStart = false
        gameStartTime = CFAbsoluteTimeGetCurrent()

        stopIdleAnimation()

        removeStartUI()

        pauseButton.removeAllActions()
        pauseButton.removeFromParent()
        pauseButton.position = pauseButtonPosition()
        pauseButton.setScale(0)
        addChild(pauseButton)

        pauseButton.run(
            .scale(to: Constants.pauseButtonScale, duration: 0.1)
        )

        // First round: the launch spawner has been adding hidden pipes since
        // the title. Replays: gameOver stopped the spawner. Either way clear
        // the pipes and start it here, so the first pipe enters from the
        // right edge instead of popping in on top of the bird.
        pipes.removeAllChildren()
        removeAction(forKey: "pipeSpawner")

        roundMode = GameMode.current
        pipePlanner = PipePlanner(tuning: roundMode.tuning)
        pipesSpawned = 0
        // In the hard modes, headstones along the ground: where friends'
        // bests and this player's own rounds ended.
        graveMarkers = roundMode == .normal ? [:] : GraveMarker.all(
            friends: FriendsStore.friendRows().map { ($0.name, $0.best(roundMode)) },
            myBest: ResultBoard.best(mode: roundMode),
            deaths: Deaths.load(mode: roundMode)
        )
        hasExtraLife = false
        heartNode.removeFromParent()

        startPipeSpawner()
        applySpeed(roundMode.tuning.startSpeed)
        pipes.setScale(1)

        bird.physicsBody?.isDynamic = true

        GameLog.roundStarted(
            "theme=\(lookShown.rawValue) bird=\(currentBirdColor)"
                + (roundMode == .normal ? "" : " mode=\(roundMode.rawValue) speed=\(speedFactor)")
                + " sound=\(playSounds ? "on" : "off") haptics=\(haptics ? "on" : "off")"
        )

        if haptics {
            flapFeedback.prepare()
            scoreFeedback.prepare()
        }

        flapBird()
    }

    private func removeStartUI() {
        tapTap.run(
            SKAction.sequence([
                .scale(to: 0, duration: 0.1),
                .removeFromParent(),
                .scale(to: 1.5, duration: 0)
            ])
        )

        getReady.run(
            SKAction.sequence([
                .scale(to: 0, duration: 0.1),
                .removeFromParent(),
                .scale(to: 1.2, duration: 0)
            ])
        )
    }

    // MARK: Play Button

    private func handlePlayTap() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        playButton.setScale(1.15)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }
                },
                .run { [weak self] in
                    self?.playButton.setScale(1.2)
                },
                .run { [weak self] in
                    self?.flashScreen(
                        color: .black,
                        fadeInDuration: 0.25,
                        peakAlpha: 1,
                        fadeOutDuration: 0.25
                    )
                },
                .wait(forDuration: 0.25)
            ]),
            completion: { [weak self] in
                self?.prepareNewGame()
            }
        )
    }
    
    private func handlePauseTap(withFeedback feedback: Bool = true) {
        guard !Self.hitButton,
              !isWaitingToStart,
              !isGameOver,
              !isShowingGameOver,
              !isPausedByUser else {
            return
        }

        Self.hitButton = true
        isPausedByUser = true
        GameLog.add(feedback ? "pause" : "pause (left the app)")
        GameLog.shownLive(false)

        // No swoosh here: a sound queued on the scene cannot start once
        // the scene is paused below, so it played late, on top of the
        // Resume swoosh.
        if feedback, haptics {
            impactFeedback.impactOccurred()
        }

        pauseButton.removeAllActions()
        pauseButton.removeFromParent()

        // Resume fades the overlay out before removing it, so it can still be
        // attached if the app is interrupted right after resuming.
        pauseOverlay.removeAllActions()
        pauseOverlay.removeFromParent()
        pauseOverlay.setScale(1)
        pauseOverlay.alpha = 0.55
        addChild(pauseOverlay)

        resumeButton.removeAllActions()
        resumeButton.removeFromParent()
        resumeButton.position = pauseButtonPosition()
        resumeButton.setScale(Constants.pauseButtonScale)
        addChild(resumeButton)

        pauseMenuButton.removeFromParent()
        addChild(pauseMenuButton)

        isPaused = true
    }

    /// MENU on the pause screen: the round ends here, with its score, and
    /// the Game Over screen brings the menu.
    private func handlePauseMenu() {
        guard isPausedByUser else {
            return
        }

        isPaused = false
        isPausedByUser = false
        skipFrameLog = true
        lastUpdateTime = 0
        GameLog.add("ended from pause")
        GameLog.shownLive(true)

        // gameOver() takes the pause screen down, and the bird falls to
        // the ground as after a hit.
        gameOver()
    }

    /// Control Center, a call or leaving the app mid-round pauses the game
    /// instead of letting the bird fall.
    @objc private func applicationWillResignActive() {
        // The pause button only exists during a live round; the title screen
        // has all the round flags below false too.
        guard pauseButton.parent != nil,
              !isWaitingToStart,
              !isGameOver,
              !isShowingGameOver,
              !isPausedByUser else {
            return
        }

        Self.hitButton = false
        handlePauseTap(withFeedback: false)
    }

    /// SpriteKit unpauses the scene when the app becomes active again, which
    /// would let the bird fall behind the pause overlay; keep it paused.
    @objc private func applicationDidBecomeActive() {
        if isPausedByUser {
            isPaused = true
        }

        // The fade from Play is frozen while the app is away but the clock
        // is not; give it time to finish before a tap can start the round.
        if isWaitingToStart {
            startAllowedAt = CACurrentMediaTime() + 0.25
        }

        // Scores may have changed while the app was away.
        if friendsNode.parent != nil {
            refreshFriends()
        } else {
            checkFriendsBadge()
        }
    }

    private func handleResumeTap() {
        guard isPausedByUser else {
            return
        }

        isPaused = false
        isPausedByUser = false
        skipFrameLog = true
        // The first frame after a pause would otherwise be "as long as the
        // pause" in the death line and the tilt.
        lastUpdateTime = 0
        GameLog.add("resume")
        GameLog.shownLive(true)

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        resumeButton.removeAllActions()
        resumeButton.removeFromParent()
        pauseMenuButton.removeFromParent()

        pauseOverlay.run(
            .sequence([
                .fadeOut(withDuration: 0.1),
                .removeFromParent()
            ])
        )

        pauseButton.removeAllActions()
        pauseButton.removeFromParent()
        pauseButton.position = pauseButtonPosition()
        pauseButton.setScale(0)
        addChild(pauseButton)

        pauseButton.run(
            .sequence([
                .scale(
                    to: Constants.pauseButtonScale * 0.875,
                    duration: 0.1
                ),
                .scale(
                    to: Constants.pauseButtonScale,
                    duration: 0.1
                )
            ]),
            completion: {
                Self.hitButton = false
            }
        )
    }

    private func prepareNewGame() {
        if isGameOver {
            resetScene()
            updateBirdTextures()
        } else {
            prepareInitialGame()
            updateBirdTextures()
        }

        Self.birdPickerButton.removeFromParent()
        Self.bestRunsButton.removeFromParent()
        Self.friendsButton.removeFromParent()
        Self.settingsButton.removeFromParent()
        playButton.removeFromParent()
        modeButton.removeFromParent()

        isWaitingToStart = true
        isGameOver = false
        Self.hitButton = false

        // The fade is at full black right now and takes 0.25 s to clear.
        startAllowedAt = CACurrentMediaTime() + 0.25
    }

    private func prepareInitialGame() {
        bird.removeAction(forKey: "idle")

        addChild(tapTap)
        addChild(getReady)
        addChild(scoreLabelNode)
        addChild(scoreLabelNodeInside)

        bird.position = CGPoint(
            x: width / 2.5,
            y: height / 2
        )

        flappyBird.removeFromParent()

        startIdleAnimation()
    }

    // MARK: Settings UI

    private func handleSettingsTap() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        Self.settingsButton.setScale(1.15)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }
                },
                .run {
                    Self.settingsButton.setScale(1.2)
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                self?.showSettings()
            }
        )
    }

    private func showSettings() {
        hideMenu()

        // The name can change while Settings is closed (a fetch on the
        // friends panel brings it back after a reinstall).
        settingsNode.showName(FriendsStore.myName)

        settingsNode.setScale(0)
        addChild(settingsNode)

        scaleTwice(
            node: settingsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.2,
            secondScaleDuration: 0.1
        )

        // As for Friends: the switches appear under the button.
        unlockButtons(after: 0.4)
    }

    // MARK: Game Mode

    private func showModeName() {
        modeButton.text = "MODE: \(GameMode.current.title)"
        settingsNode.modeButton.text = GameMode.current.title
    }

    /// The mode button by Play, or the MODE row in Settings: the next
    /// mode. On the title and Game Over screens the world changes in a
    /// flash; behind the Settings panel it just changes.
    private func handleModeTap() {
        guard !Self.hitButton, bestRunsNode.parent == nil, friendsNode.parent == nil else {
            return
        }

        Self.hitButton = true

        GameMode.current = GameMode.current.next
        GameLog.add("mode \(GameMode.current.rawValue)")
        showModeName()

        playSound(swooshSound)

        let harder = GameMode.current != .normal

        if haptics {
            if harder {
                deathFeedback.impactOccurred()
            } else {
                impactFeedback.impactOccurred()
            }
        }

        // The round on a Game Over screen is over: only its colours
        // change, and the speed waits for the next round.
        let change = { [weak self] in
            guard let self else { return }

            self.refreshTheme()
            if !self.isGameOver {
                self.moving.speed = CGFloat(GameMode.current.tuning.startSpeed)
                // The bird on the title wears the mode's look too. On Game
                // Over the bird that died stays as it fell.
                self.refreshBirdLook()
            }
        }

        guard settingsNode.parent == nil else {
            change()
            return unlockButtons()
        }

        flashScreen(
            color: lookWanted.flash,
            fadeInDuration: 0.14,
            peakAlpha: 0.95,
            fadeOutDuration: 0.4
        )

        run(
            .sequence([
                .wait(forDuration: 0.14),
                .run { [weak self] in
                    change()

                    if harder {
                        self?.playSound(self?.hitSound)
                        self?.shakeScreen()
                    }
                },
                .wait(forDuration: 0.4),
                .run {
                    Self.hitButton = false
                }
            ])
        )
    }

    /// The mode box under Friends or Best Runs: looks at another mode's
    /// scores. The game's own mode stays.
    private func handlePanelModeTap() {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        if bestRunsNode.parent != nil {
            bestRunsNode.showNextMode()
        } else if friendsNode.parent != nil {
            friendsNode.showNextMode()
            loadFriendsBoard()
        }
    }

    // MARK: Leaving a Panel

    /// BACK under a panel, or a tap outside it.
    private func handlePanelBack() {
        guard !Self.hitButton, let panel = openPanel else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                guard let self else { return }

                if panel === self.settingsNode {
                    self.hideSettings()
                } else if panel === self.bestRunsNode {
                    self.hideBestRuns()
                } else {
                    self.hideFriends()
                }

                // Longer than after other buttons: Play comes back right
                // where BACK was, under a thumb that may tap twice.
                self.unlockButtons(after: 0.4)
            }
        )
    }

    /// One of the words on a panel's top row.
    private func handleTabTap(_ name: String) {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        if bestRunsNode.parent != nil {
            bestRunsNode.select(tab: name)
        } else if friendsNode.parent != nil {
            friendsNode.select(tab: name)
            loadFriendsBoard()
        }
    }

    /// TODAY / WEEK / MONTH / ALL TIME on the EVERYONE list.
    private func handleScopeTap(_ name: String) {
        guard !Self.hitButton else {
            return
        }

        if friendsNode.select(scope: name) {
            playSound(swooshSound)

            if haptics {
                impactFeedback.impactOccurred()
            }
        }

        // Also for the board already showing: a tap fetches it again (it
        // may be waiting since midnight, or since a failed try).
        loadFriendsBoard()
    }

    /// Fetches the board on screen, if EVERYONE is showing; the panel
    /// shows what it has (or LOADING) until it arrives.
    private func loadFriendsBoard() {
        guard let board = friendsNode.boardShowing else {
            return
        }

        FriendsStore.loadBoard(board.scope, mode: board.mode) { [weak self] in
            guard let self, self.friendsNode.parent != nil else {
                return
            }
            self.friendsNode.reload(keepPage: true)
        }

        friendsNode.reload(keepPage: true)
    }

    private func hideSettings() {
        scaleTwice(
            node: settingsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 0,
            secondScaleDuration: 0.1
        )

        settingsNode.removeFromParent()

        restoreMenu()
    }

    // MARK: Menu Row

    private var menuButtons: [SKSpriteNode] {
        [Self.birdPickerButton, Self.bestRunsButton, Self.friendsButton, Self.settingsButton]
    }

    /// Bird picker, best runs, friends and settings sit in one centred row
    /// above Play on both the title and game-over screens.
    private func placeMenuButtons() {
        let y = height / 2 - 25
        let middle = CGFloat(menuButtons.count - 1) / 2

        for (index, button) in menuButtons.enumerated() {
            button.position = CGPoint(
                x: width / 2 + (CGFloat(index) - middle) * Constants.menuButtonSpacing,
                y: y
            )
        }
    }

    /// Scales the menu away while a panel (Settings, Best Runs, Friends) is open.
    private func hideMenu() {
        for node in menuButtons + [playButton, modeButton, isGameOver ? resultNode : bird] as [SKNode] {
            scaleTwice(
                node: node,
                firstScale: 1,
                firstScaleDuration: 0.1,
                secondScale: 0,
                secondScaleDuration: 0.1
            )
        }
    }

    private func restoreMenu() {
        for node in menuButtons + [playButton, modeButton] as [SKNode] {
            scaleTwice(
                node: node,
                firstScale: 1,
                firstScaleDuration: 0.1,
                secondScale: 1.2,
                secondScaleDuration: 0.1
            )
        }

        scaleTwice(
            node: isGameOver ? resultNode : bird,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: isGameOver ? 1.25 : Constants.birdScale,
            secondScaleDuration: 0.1
        )
    }

    // MARK: Bird Picker

    private func handleBirdPickerTap() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        let options = ["random"] + Self.pickableBirds
        let next = ((options.firstIndex(of: birdChoice) ?? 0) + 1) % options.count
        birdChoice = options[next]
        UserDefaults.standard.set(birdChoice, forKey: "birdChoice")

        refreshBirdPickerIcon()

        // The dead bird on the game-over screen keeps its look; the pick
        // applies from the next round.
        if !isGameOver {
            updateBirdTextures()
        }

        Self.birdPickerButton.setScale(1.15)

        Self.birdPickerButton.run(
            .sequence([
                .wait(forDuration: 0.1),
                .scale(to: 1.2, duration: 0)
            ]),
            completion: {
                Self.hitButton = false
            }
        )
    }

    /// Flaps the chosen bird on the button; "random" flaps through the pool
    /// the next round will pick from.
    private func refreshBirdPickerIcon() {
        let colors: [String]

        if birdChoice != "random" {
            colors = [birdChoice]
        } else {
            colors = Self.pickableBirds
        }

        let frames = colors.flatMap { color in
            [1, 2, 3, 2].map { frame in
                Assets.shared.sprites.textureNamed("\(color)-bird-\(frame)").then {
                    $0.filteringMode = .nearest
                }
            }
        }

        let icon = Self.birdPickerIcon
        icon.removeAction(forKey: "flap")
        icon.texture = frames[0]

        icon.run(
            .repeatForever(
                .animate(
                    with: frames,
                    timePerFrame: Constants.animationFrameDuration
                )
            ),
            withKey: "flap"
        )
    }

    // MARK: Best Runs

    private func handleBestRunsTap() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        Self.bestRunsButton.setScale(1.15)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }
                },
                .run {
                    Self.bestRunsButton.setScale(1.2)
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                self?.showBestRuns()
            }
        )
    }

    private func showBestRuns() {
        hideMenu()

        bestRunsNode.reload()
        bestRunsNode.setScale(0)
        addChild(bestRunsNode)

        scaleTwice(
            node: bestRunsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.2,
            secondScaleDuration: 0.1
        )

        unlockButtons()
    }

    private func hideBestRuns() {
        scaleTwice(
            node: bestRunsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 0,
            secondScaleDuration: 0.1
        )

        bestRunsNode.removeFromParent()

        restoreMenu()
    }

    // MARK: Friends

    private func handleFriendsTap() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        Self.friendsButton.setScale(1.15)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }
                },
                .run {
                    Self.friendsButton.setScale(1.2)
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                self?.showFriends()
            }
        )
    }

    private func showFriends() {
        hideMenu()

        friendsNode.reload()
        friendsNode.setScale(0)
        addChild(friendsNode)

        scaleTwice(
            node: friendsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.2,
            secondScaleDuration: 0.1
        )

        // Longer than usual: the panel's rows appear under the button
        // just pressed, and a second tap would land on one.
        unlockButtons(after: 0.4)
        refreshFriends()
    }

    /// Fetches the lists; the panel shows what it has until they arrive.
    private func refreshFriends() {
        FriendsStore.refresh { [weak self] in
            guard let self, self.friendsNode.parent != nil else {
                return
            }

            self.friendsNode.reload(keepPage: true)
            self.updateFriendsBadge()

            // First visit with no name yet: ask once.
            if !Self.hitButton, FriendsStore.shouldAskForName() {
                Self.hitButton = true

                if self.askForName() {
                    FriendsStore.askedForName()
                }
            }
        }

        // Shows LOADING while the first fetch runs.
        friendsNode.reload(keepPage: true)
        // Back in the game with EVERYONE open: its board is fetched again.
        loadFriendsBoard()
    }

    /// The arrows under the panel: the pages of the list showing.
    private func handleFriendsTurn(by step: Int) {
        guard !Self.hitButton, friendsNode.turnPage(by: step) else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }
    }

    private func hideFriends() {
        scaleTwice(
            node: friendsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 0,
            secondScaleDuration: 0.1
        )

        friendsNode.removeFromParent()

        restoreMenu()
        updateFriendsBadge()
    }

    /// The count on the menu's Friends button: people who added you that
    /// this phone has not shown yet.
    private func updateFriendsBadge() {
        let count = FriendsStore.unseenAddedCount()
        Self.friendsBadge.isHidden = count == 0
        Self.friendsBadgeLabel.text = count > 9 ? "9+" : "\(count)"
    }

    /// Looks for new people at launch and on coming back to the game, so
    /// the count is there without opening the panel.
    private func checkFriendsBadge() {
        updateFriendsBadge()

        // The self-tests and screenshot runs drive the server themselves.
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-friendsSelfTest"), !arguments.contains("-friendsShot") else {
            return
        }

        FriendsStore.refreshForBadge { [weak self] in
            guard let self else { return }

            self.updateFriendsBadge()
            if self.friendsNode.parent != nil {
                self.friendsNode.reload(keepPage: true)
            }
        }
    }

    private func handleFriendsAdd() {
        guard takePromptTap() else {
            return
        }

        askForFriend()
    }

    /// A row on the ADDED YOU page: adds that player to your friends.
    private func handleFriendsAddBack(row: Int) {
        guard !Self.hitButton, friendsNode.addBackRows.indices.contains(row) else {
            return
        }

        // Locked for a moment: the rows move up, and a second tap would
        // add whoever lands under the thumb.
        Self.hitButton = true

        if haptics {
            impactFeedback.impactOccurred()
        }

        let player = friendsNode.addBackRows[row]
        FriendsStore.addBack(player)
        playSound(pointSound)
        friendsNode.show(message: "ADDED \(player.name)")
        updateFriendsBadge()
        unlockButtons()
    }

    /// A friend's row on FRIENDS: asks, then takes them off the list.
    private func handleFriendsRow(_ row: Int) {
        guard friendsNode.friendRowsOnPage.indices.contains(row),
              let friend = friendsNode.friendRowsOnPage[row],
              takePromptTap() else {
            return
        }

        present(NamePrompt.confirm(
            title: "Remove \(friend.name)?",
            message: "They are not told. You can add them again by name.",
            action: "Remove"
        ) { [weak self] confirmed in
            guard let self else { return }

            if confirmed {
                FriendsStore.removeFriend(friend)
            }

            self.endPrompt()

            if confirmed {
                self.friendsNode.show(message: "REMOVED \(friend.name)")
            }
        })
    }

    /// SHARE NAME: the system share sheet with the player's exact name, so
    /// a friend can add them. Without a name yet, it asks for one first.
    private func handleFriendsShare() {
        guard let name = FriendsStore.myName else {
            return handleFriendsMe()
        }

        guard takePromptTap() else {
            return
        }

        let sheet = UIActivityViewController(activityItems: [FriendsLogic.shareText(name: name)], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.endPrompt()
        }
        present(sheet)
    }

    /// Your own row, tappable while it has no name on it.
    private func handleFriendsMe() {
        guard takePromptTap() else {
            return
        }

        if FriendsStore.status == .noAccount {
            showNotice(
                title: "No iCloud",
                message: "Sign in to iCloud in Settings to put your name on the board."
            )
        } else {
            askForName()
        }
    }

    /// The NAME row in Settings.
    private func handleNameTap() {
        guard takePromptTap() else {
            return
        }

        askForName()
    }

    // MARK: Name Prompts

    /// Takes the button lock for a prompt; the lock stays on until
    /// endPrompt(), across any wait for the server.
    private func takePromptTap() -> Bool {
        guard !Self.hitButton else {
            return false
        }

        Self.hitButton = true

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        return true
    }

    /// The view controller showing the game.
    private var promptPresenter: UIViewController? {
        var responder: UIResponder? = view

        while let next = responder?.next {
            if let controller = next as? UIViewController {
                return controller
            }
            responder = next
        }

        return nil
    }

    /// Shows an alert over the game. Only while a panel that can ask is
    /// open and no other alert is up; otherwise the prompt is dropped, the
    /// buttons are released and the answer is false.
    @discardableResult
    private func present(_ alert: UIViewController) -> Bool {
        guard friendsNode.parent != nil || settingsNode.parent != nil,
              let presenter = promptPresenter,
              presenter.presentedViewController == nil else {
            endPrompt()
            return false
        }

        Self.hitButton = true
        GameLog.add("prompt shown")
        presenter.present(alert, animated: true)
        return true
    }

    /// While a request waits for the server the panels say so (CHECKING,
    /// SAVING); the buttons stay locked until endPrompt().
    private func showBusy() {
        friendsNode.reload(keepPage: true)
        settingsNode.showName(FriendsStore.myName)
    }

    /// Every prompt flow ends here: redraws what a prompt can change, gives
    /// the spacebar handler its focus back and releases the buttons.
    private func endPrompt() {
        GameLog.add("prompt closed")
        friendsNode.reload(keepPage: true)
        settingsNode.showName(FriendsStore.myName)
        promptPresenter?.becomeFirstResponder()
        unlockButtons()

        // A new name or a removed profile changes the lists.
        if friendsNode.parent != nil {
            FriendsStore.refresh { [weak self] in
                guard let self, self.friendsNode.parent != nil else {
                    return
                }
                self.friendsNode.reload(keepPage: true)
            }
        }
    }

    private func showNotice(title: String, message: String) {
        present(NamePrompt.notice(title: title, message: message) { [weak self] in
            self?.endPrompt()
        })
    }

    @discardableResult
    private func askForName(message: String? = nil, text: String? = nil) -> Bool {
        let current = FriendsStore.myName

        return present(NamePrompt.name(
            title: current == nil ? "Pick a name" : "Your name",
            message: message ?? "3 to 10 letters or numbers. Friends add you by this name. Everyone can see it and your scores.",
            text: text ?? current ?? "",
            action: "Save",
            deleteTitle: current == nil ? nil : "Delete my name and scores"
        ) { [weak self] answer in
            guard let self else { return }

            switch answer {
            case .cancel:
                self.endPrompt()

            case .delete:
                self.confirmDeleteProfile()

            case .text(let name):
                guard name != current else {
                    return self.endPrompt()
                }

                FriendsStore.setName(name) { [weak self] result in
                    guard let self else { return }

                    switch result {
                    case .ok:
                        if current == nil, self.friendsNode.parent != nil, FriendsStore.friendIDs.isEmpty {
                            // A new player with nobody added yet: straight on
                            // to adding the first friend.
                            self.askForFriend()
                        } else {
                            self.endPrompt()
                        }
                    case .invalid(.blocked):
                        self.askForName(message: "That name isn't allowed.", text: name)
                    case .invalid:
                        self.askForName(message: "Use 3 to 10 letters or numbers.", text: name)
                    case .taken:
                        self.askForName(message: "Someone already has that name.", text: name)
                    case .noAccount:
                        self.askForName(message: "Sign in to iCloud in Settings to put your name on the board.", text: name)
                    case .offline:
                        self.askForName(message: "No connection. Try again later.", text: name)
                    case .failed:
                        self.askForName(message: "That didn't work. Try again.", text: name)
                    }
                }

                self.showBusy()
            }
        })
    }

    private func confirmDeleteProfile() {
        present(NamePrompt.confirm(
            title: "Delete your name and scores?",
            message: "They come off the friends lists for everyone. The scores on this phone stay.",
            action: "Delete"
        ) { [weak self] confirmed in
            guard let self else { return }

            guard confirmed else {
                return self.endPrompt()
            }

            FriendsStore.deleteProfile { [weak self] error in
                guard let self else { return }

                switch error {
                case nil:
                    self.endPrompt()
                case .noAccount:
                    self.showNotice(title: "Not deleted", message: "Sign in to iCloud in Settings first.")
                case .offline:
                    self.showNotice(title: "Not deleted", message: "No connection. Try again later.")
                case .failed:
                    self.showNotice(title: "Not deleted", message: "That didn't work. Try again.")
                }
            }

            self.showBusy()
        })
    }

    private func askForFriend(message: String? = nil, text: String = "") {
        present(NamePrompt.name(
            title: "Add a friend",
            message: message ?? "Type their name exactly.",
            text: text,
            action: "Add"
        ) { [weak self] answer in
            guard let self else { return }

            guard case .text(let name) = answer else {
                return self.endPrompt()
            }

            FriendsStore.addFriend(name: name) { [weak self] result in
                guard let self else { return }

                switch result {
                case .added:
                    self.endPrompt()
                    self.playSound(self.pointSound)
                    self.friendsNode.show(
                        message: "ADDED \(name)",
                        jumpTo: FriendsStore.friendRows().first { $0.name == name }?.id
                    )
                case .invalid:
                    self.askForFriend(message: "Use 3 to 10 letters or numbers.", text: name)
                case .notFound:
                    self.askForFriend(message: "No player is called \(name).", text: name)
                case .isYou:
                    self.askForFriend(message: "That's your own name.", text: name)
                case .already:
                    self.askForFriend(message: "\(name) is already on your list.", text: name)
                case .offline:
                    self.askForFriend(message: "No connection. Try again later.", text: name)
                case .failed:
                    self.askForFriend(message: "That didn't work. Try again.", text: name)
                }
            }

            self.showBusy()
        })
    }

    private func unlockButtons(after delay: TimeInterval = 0.2) {
        run(
            .sequence([
                .wait(forDuration: delay),
                .run {
                    Self.hitButton = false
                }
            ])
        )
    }

    // MARK: Settings Toggles

    // The switches honour the button lock: their rows are wide, and a
    // second tap on the Settings button would otherwise land on one as
    // the panel appears.

    private func toggle(
        value: inout Bool,
        key: String,
        item: SettingsPanel.Switch
    ) {
        value.toggle()

        saveSetting(value, key: key)

        settingsNode.setSwitch(item, on: value, animated: true)
    }

    private func handleSoundToggle() {
        guard !Self.hitButton else {
            return
        }

        if haptics {
            impactFeedback.impactOccurred()
        }

        toggle(value: &playSounds, key: "playSounds", item: .sound)

        // playSound() is a no-op while sound is off, so this only swooshes
        // when sound was just turned on.
        playSound(swooshSound)
    }

    private func handleHapticsToggle() {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        toggle(value: &haptics, key: "haptics", item: .haptics)

        if haptics {
            impactFeedback.impactOccurred()
        }
    }

    private func handleDarkModeToggle() {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        toggle(value: &darkMode, key: "darkMode", item: .darkMode)

        refreshTheme()
    }

    private func handleLogsToggle() {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        toggle(value: &logsOn, key: GameLog.settingKey, item: .logs)

        GameLog.setEnabled(logsOn)
    }

    // MARK: Ground

    private func createGroundMovement() {
        let groundWidth = groundTexture.width * 2

        let moveGround = SKAction.moveBy(
            x: -groundWidth,
            y: 0,
            duration: Constants.groundMoveSpeed * groundWidth
        )

        let resetGround = SKAction.moveBy(
            x: groundWidth,
            y: 0,
            duration: 0
        )

        let movement = SKAction.repeatForever(
            .sequence([
                moveGround,
                resetGround
            ])
        )

        let count = 2 + Int(width / groundWidth)

        for index in 0..<count {
            let node = SKSpriteNode(
                texture: groundTexture
            ).then {
                $0.setScale(2)
                $0.position = CGPoint(
                    x: CGFloat(index) * ($0.width - 1),
                    y: $0.height / 2 - Constants.groundDrop
                )
                $0.run(movement)
            }

            groundNodes.append(node)
            moving.addChild(node)
        }
    }

    // MARK: Sky and Theme

    /// What refreshTheme last applied; new pipes match it without a trait lookup.
    private var lookShown = Look.day

    /// Night when Dark Mode is on and the phone is in dark appearance.
    private var isNight: Bool {
        darkMode && view?.traitCollection.userInterfaceStyle == .dark
    }

    /// The hard modes have their own look, whatever the time of day; the
    /// normal game is day or night.
    private var lookWanted: Look {
        switch GameMode.current {
        case .normal: return isNight ? .night : .day
        case .hard: return .hard
        case .insane: return .insane
        case .impossible: return .impossible
        }
    }

    /// Swaps the art on the existing nodes, so nothing restarts or jumps.
    /// Called at launch, from the Dark Mode switch and the mode button, at
    /// each new round, and by GameViewController when the phone's
    /// appearance changes.
    func refreshTheme() {
        let look = lookWanted
        if look != lookShown {
            // iOS flips the appearance light and back while it takes its
            // app-switcher snapshots; those lines are labelled.
            GameLog.add("theme \(look.rawValue)"
                + (UIApplication.shared.applicationState == .active ? "" : " (app not on screen)"))
        }
        lookShown = look

        backgroundColor = look.skyTop

        guard let art = lookArt[look] else {
            return
        }

        for node in skyNodes {
            node.texture = art.sky
        }

        for node in groundNodes {
            node.texture = art.ground
        }

        for group in pipes.children {
            for case let pipe as SKSpriteNode in group.children {
                applyPipeLook(to: pipe)
            }
        }
    }

    // MARK: Lightning

    /// Behind the pipes and the ground, in front of the sky: only the sky
    /// lights up.
    private lazy var lightningNode = SKSpriteNode(color: .white, size: CGSize(width: width, height: height)).then {
        $0.position = CGPoint(x: width / 2, y: height / 2)
        $0.zPosition = GameZPosition.sky + 0.5
        $0.alpha = 0
    }

    /// The hard modes are stormy: every so often the sky flickers. Runs
    /// for as long as the scene does and does nothing in the normal game.
    private func startLightning() {
        addChild(lightningNode)

        let strike = SKAction.run { [weak self] in
            guard let self, self.lookShown != .day, self.lookShown != .night else {
                return
            }

            self.lightningNode.run(.sequence([
                .fadeAlpha(to: 0.45, duration: 0.04),
                .fadeAlpha(to: 0.05, duration: 0.08),
                .fadeAlpha(to: 0.30, duration: 0.04),
                .fadeAlpha(to: 0, duration: 0.3)
            ]))
        }

        run(.repeatForever(.sequence([
            .wait(forDuration: 9, withRange: 8),
            strike
        ])))
    }

    /// A pipe in the look showing.
    private func applyPipeLook(to pipe: SKSpriteNode) {
        guard let art = lookArt[lookShown] else {
            return
        }

        switch pipe.name {
        case "pipeUp":
            pipe.texture = art.pipeUp
        case "pipeDown":
            pipe.texture = art.pipeDown
        default:
            break
        }
    }

    private func createSky() {
        let skyTexture = dayTexture

        let skyWidth = skyTexture.width * 1.5

        let moveSky = SKAction.moveBy(
            x: -skyWidth,
            y: 0,
            duration: Constants.skyMoveSpeed * skyWidth
        )

        let resetSky = SKAction.moveBy(
            x: skyWidth,
            y: 0,
            duration: 0
        )

        let movement = SKAction.repeatForever(
            .sequence([
                moveSky,
                resetSky
            ])
        )

        let requiredCount = 2 + Int(width / skyWidth)

        for index in 0..<requiredCount {
            let node = SKSpriteNode(
                texture: skyTexture
            ).then {
                $0.setScale(1.5)
                $0.zPosition = GameZPosition.sky
                $0.position = CGPoint(
                    x: CGFloat(index) * ($0.width - 1),
                    y: $0.height / 3.5 +
                        groundTexture.height * 2 -
                        Constants.groundDrop
                )
                $0.run(movement)
            }

            skyNodes.append(node)
            moving.addChild(node)
        }
    }

    // MARK: Pipes

    private func startPipeSpawner() {
        let spawn = SKAction.run { [weak self] in
            self?.spawnPipe()
        }

        let delay = SKAction.wait(forDuration: 1)

        run(
            .repeatForever(
                .sequence([
                    spawn,
                    delay
                ])
            ),
            withKey: "pipeSpawner"
        )
    }

    private func spawnPipe() {
        // The normal game's pipes are placed below, as they always were.
        // The hard modes plan theirs.
        guard roundMode == .normal else {
            return spawnHardPipe()
        }

        let quarterHeight = Int(height / 4)

        let y = CGFloat(
            pipeRandom.nextInt(
                in: quarterHeight...(quarterHeight * 2)
            )
        )

        let pipeDown = makePipe(
            name: "pipeDown",
            texture: pipeTextureDown,
            position: CGPoint(
                x: 0,
                y: y + pipeTextureDown.height * 2 +
                    Constants.verticalPipeGap
            )
        )

        let pipeUp = makePipe(
            name: "pipeUp",
            texture: pipeTextureUp,
            position: CGPoint(
                x: 0,
                y: y
            )
        )

        let scoreNode = makeScoreNode()

        let distance =
            width +
            2 * pipeTextureUp.width +
            25

        let movement = SKAction.moveBy(
            x: -distance,
            y: 0,
            duration: Constants.pipeMoveSpeed * distance
        )

        let pipeGroup = SKNode().then {
            $0.position = CGPoint(
                x: width + pipeTextureUp.width * 2,
                y: -352
            )

            $0.zPosition = GameZPosition.pipe

            $0.addChild(pipeDown)
            $0.addChild(pipeUp)
            $0.addChild(scoreNode)

            $0.run(
                .sequence([
                    movement,
                    .removeFromParent()
                ])
            )
        }

        pipes.addChild(pipeGroup)
    }

    /// A hard-mode pipe: placed by the planner, with that pipe's gap, and
    /// sliding up and down when the mode has it.
    private func spawnHardPipe() {
        pipesSpawned += 1

        let plan = pipePlanner.plan(pipe: pipesSpawned, quarter: Double(height / 4)) {
            pipeRandom.nextInt(in: $0)
        }

        // A smaller gap closes evenly from both sides.
        let squeeze = CGFloat(Tuning.normalGap - plan.gap) / 2
        let y = CGFloat(plan.y)

        let pipeDown = makePipe(
            name: "pipeDown",
            texture: pipeTextureDown,
            position: CGPoint(
                x: 0,
                y: y + pipeTextureDown.height * 2 +
                    Constants.verticalPipeGap - squeeze
            )
        )

        let pipeUp = makePipe(
            name: "pipeUp",
            texture: pipeTextureUp,
            position: CGPoint(x: 0, y: y + squeeze)
        )

        // At speed a slow frame could carry the bird clean past a sensor
        // 4 wide: this one is 16, grown on its far side so the point
        // still lands at the same moment.
        let scoreNode = makeScoreNode(width: 16)
        scoreNode.position.x += 6

        let distance =
            width +
            2 * pipeTextureUp.width +
            25

        let slide = CGFloat(plan.slide)
        let side: CGFloat = plan.startsHigh ? 1 : -1

        let pipeGroup = SKNode().then {
            $0.position = CGPoint(
                x: width + pipeTextureUp.width * 2,
                y: -352 + side * slide
            )

            $0.zPosition = GameZPosition.pipe

            $0.addChild(pipeDown)
            $0.addChild(pipeUp)
            $0.addChild(scoreNode)

            $0.run(
                .sequence([
                    .moveBy(x: -distance, y: 0, duration: Constants.pipeMoveSpeed * distance),
                    .removeFromParent()
                ])
            )

            if slide > 0 {
                // These actions run at the world's speed: stretched by it,
                // one slide takes the same time on the clock at any speed.
                let half = pipePlanner.tuning.slidePeriod / 2 * Double(speedFactor)
                let away = SKAction.moveBy(x: 0, y: -2 * side * slide, duration: half)
                away.timingMode = .easeInEaseOut
                let back = SKAction.moveBy(x: 0, y: 2 * side * slide, duration: half)
                back.timingMode = .easeInEaseOut
                $0.run(.repeatForever(.sequence([away, back])))
            }
        }

        pipes.addChild(pipeGroup)

        if let marker = graveMarkers[pipesSpawned] {
            addGraveMarker(marker, distance: distance)
        }
    }

    /// A headstone on the ground a little before the pipe just spawned,
    /// travelling with it (but not sliding with it).
    private func addGraveMarker(_ marker: GraveMarker, distance: CGFloat) {
        let node = SKNode()
        node.position = CGPoint(
            x: width + pipeTextureUp.width * 2 - 75,
            y: groundTexture.height * 2 - Constants.groundDrop
        )
        // Behind the pipes, in front of the sky.
        node.zPosition = GameZPosition.sky + 0.75

        let stone = SKSpriteNode(texture: Assets.shared.sprites.textureNamed("grave-stone").then { $0.filteringMode = .nearest })
        stone.anchorPoint = CGPoint(x: 0.5, y: 0)
        stone.setScale(Constants.birdScale)
        node.addChild(stone)

        for (index, line) in marker.lines.reversed().enumerated() {
            let y = stone.size.height + 8 + CGFloat(index) * 12

            for (z, (color, offset)) in [(PanelButton.textColor, CGPoint(x: 0, y: -1)), (UIColor.white, .zero)].enumerated() {
                node.addChild(SKLabelNode(fontNamed: "KongtextRegular").then {
                    $0.text = line
                    $0.fontSize = 9
                    $0.fontColor = color
                    $0.verticalAlignmentMode = .center
                    $0.position = CGPoint(x: offset.x, y: y + offset.y)
                    $0.zPosition = CGFloat(z + 1) * 0.01
                })
            }
        }

        node.run(.sequence([
            .moveBy(x: -distance, y: 0, duration: Constants.pipeMoveSpeed * distance),
            .removeFromParent()
        ]))

        pipes.addChild(node)
    }

    private func makePipe(
        name: String,
        texture: SKTexture,
        position: CGPoint
    ) -> SKSpriteNode {
        SKSpriteNode(texture: texture).then {
            $0.name = name
            applyPipeLook(to: $0)
            $0.setScale(Constants.pipeScale)
            $0.position = position

            $0.physicsBody = SKPhysicsBody(
                rectangleOf: $0.size
            ).then {
                $0.isDynamic = false
                $0.categoryBitMask = PhysicsCategory.pipe
                $0.contactTestBitMask = PhysicsCategory.bird
            }
        }
    }

    private func makeScoreNode(width sensorWidth: CGFloat = 4) -> SKNode {
        SKNode().then {
            // The scoring sensor sits just past the pipe's trailing edge:
            // the point lands when the bird's centre is about 6 units
            // beyond it. Fixed offset (half the level bird's width):
            // bird.width is the tilted frame, 30 to 52 units, so the
            // scoring moment used to shift from pipe to pipe.
            $0.position = CGPoint(
                x: pipeTextureDown.width
                    + defaultBirdTexture.width * Constants.birdScale / 2 + 2,
                y: height / 2 + 400
            )

            $0.physicsBody = SKPhysicsBody(
                rectangleOf: CGSize(
                    width: sensorWidth,
                    height: height
                )
            ).then {
                $0.isDynamic = false
                $0.categoryBitMask = PhysicsCategory.score
                $0.contactTestBitMask = PhysicsCategory.bird
                $0.collisionBitMask = 0
            }
        }
    }

    // MARK: Game Over

    private func gameOver() {
        guard !isShowingGameOver else {
            return
        }
        
        pauseButton.removeFromParent()
        resumeButton.removeFromParent()
        pauseOverlay.removeFromParent()

        pauseMenuButton.removeFromParent()
        removeAction(forKey: "revive")
        bird.alpha = 1
        heartNode.removeFromParent()

        // Resume releases the tap lock from a pauseButton action; dying before
        // it finishes removed the button, the action never ran, and every
        // button stayed dead. Nothing is tappable until the results appear.
        pauseButton.removeAllActions()
        Self.hitButton = false

        isPausedByUser = false
        isPaused = false

        timeTook =
            CFAbsoluteTimeGetCurrent() - gameStartTime

        isShowingGameOver = true
        isGameOver = true
        playFlapSound = false
        GameLog.shownLive(false)

        // Ends the nose-up hold from the last flap, or the dead bird keeps
        // pointing up for up to 0.65 s while it falls.
        lastFlapTime = 0

        // The shake is part of the death look; only the buzz follows Haptics.
        shakeScreen()
        if haptics {
            notificationFeedback.notificationOccurred(.error)
            deathFeedback.impactOccurred()
        }

        flashScreen(
            color: .white,
            fadeInDuration: 0.1,
            peakAlpha: 0.9,
            fadeOutDuration: 0.25
        )

        bird.physicsBody?.isDynamic = false
        bird.physicsBody?.collisionBitMask =
            PhysicsCategory.land
        bird.physicsBody?.isDynamic = true

        // A milestone flash in progress would freeze mid-tint once the world
        // stops; clear it on the bird, the score and the pipes.
        clearMilestoneTint()

        // X eyes: the dead frame replaces the flapping animation.
        bird.removeAction(forKey: "birdAnimation")
        bird.texture = Assets.shared.sprites.textureNamed(
            score >= Constants.superScore ? "super-bird-dead" : "\(currentBirdColor)-bird-dead"
        ).then {
            $0.filteringMode = .nearest
        }

        playSound(hitSound)

        // In INSANE and IMPOSSIBLE the bird does not just drop.
        if roundMode == .insane || roundMode == .impossible {
            explodeBird()
        }

        run(
            .sequence([
                .wait(forDuration: 0.2),
                .run { [weak self] in
                    self?.playSound(self?.dieSound)
                }
            ])
        )

        gameOverNode.setScale(0)
        addChild(gameOverNode)

        run(
            .sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    self?.scoreLabelNode.removeFromParent()
                    self?.scoreLabelNodeInside.removeFromParent()
                },
                .run { [weak self] in
                    guard let self else { return }

                    self.scaleTwice(
                        node: self.gameOverNode,
                        firstScale: 1,
                        firstScaleDuration: 0.1,
                        secondScale: 1.25,
                        secondScaleDuration: 0.1
                    )
                }
            ])
        )

        moving.speed = 0

        // The spawner runs on the scene, not on `moving`, so it kept adding
        // one frozen pipe group a second for as long as the Game Over
        // screen stayed up. startGame() starts it again.
        removeAction(forKey: "pipeSpawner")

        bird.physicsBody?.velocity = .zero
        bird.physicsBody?.applyImpulse(
            CGVector(dx: 0, dy: 13)
        )
    }

    // MARK: Results

    private func addResultsAndButtons() {
        guard canShowScore else {
            return
        }

        // Each mode keeps its own best, runs and goals. The day-by-day
        // stats (and with them the day, week and month scores friends see)
        // are the normal game's alone.

        // Before resultNode.score saves a new best (see BestRuns.record).
        BestRuns.record(score, mode: roundMode)
        if roundMode == .normal {
            GameStats.record(score: score)
        } else {
            Deaths.record(score: score, mode: roundMode)
        }
        Achievements.record(score: score, mode: roundMode)

        let bestBefore = ResultBoard.best(mode: roundMode)

        resultNode.setScale(0)
        resultNode.mode = roundMode
        resultNode.score = score
        addChild(resultNode)

        // After every save above (the result board saves a new best).
        CloudSync.merge()
        FriendsStore.roundEnded(mode: roundMode)

        // Who to go after next, among the friends last fetched.
        resultNode.chase = FriendsStore.chaseTarget(mode: roundMode).map { "\($0.points) TO BEAT \($0.name)" }

        if roundMode == .normal, score > bestBefore {
            askForRating(newBest: score)
        }

        scaleTwice(
            node: resultNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.25,
            secondScaleDuration: 0.1
        )

        placeMenuButtons()

        for button in menuButtons {
            button.removeFromParent()
            button.setScale(0)
            addChild(button)

            scaleTwice(
                node: button,
                firstScale: 1,
                firstScaleDuration: 0.1,
                secondScale: 1.2,
                secondScaleDuration: 0.1
            )
        }

        playButton.setScale(0)
        addChild(playButton)

        scaleTwice(
            node: playButton,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.2,
            secondScaleDuration: 0.1
        )

        modeButton.removeFromParent()
        modeButton.setScale(0)
        showModeName()
        addChild(modeButton)

        scaleTwice(
            node: modeButton,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.2,
            secondScaleDuration: 0.1
        )

        // The buttons appear where the thumb has been tapping; a tap still
        // in flight from the round must not press Play or switch birds.
        // Released from a scene action: a node's own action dies with the
        // node and would leave every button dead (see gameOver).
        Self.hitButton = true
        run(
            .sequence([
                .wait(forDuration: 0.35),
                .run {
                    Self.hitButton = false
                }
            ])
        )

        GameLog.roundEnded(score: score)
    }


    /// After a new best worth being pleased about, once per version, the
    /// system may ask for an App Store rating (it decides whether to, and
    /// never does on TestFlight).
    private func askForRating(newBest: Int) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let defaults = UserDefaults.standard

        guard newBest >= 20, defaults.string(forKey: "ratingAskedVersion") != version else {
            return
        }

        defaults.set(version, forKey: "ratingAskedVersion")

        // Once the card has counted up and the buttons are in. Keyed so the
        // next round (resetScene) cancels it: it must not come up over a
        // later Game Over.
        run(.sequence([
            .wait(forDuration: 2.5),
            .run { [weak self] in
                guard let self, self.isGameOver, self.openPanel == nil,
                      let windowScene = self.view?.window?.windowScene else {
                    return
                }

                if #available(iOS 16.0, *) {
                    AppStore.requestReview(in: windowScene)
                }
            }
        ]), withKey: "ratingAsk")
    }

    // MARK: Reset

    private func resetScene() {
        isPaused = false
        isPausedByUser = false

        pauseButton.removeFromParent()
        resumeButton.removeFromParent()
        pauseOverlay.removeFromParent()
        
        pauseMenuButton.removeFromParent()
        pipes.removeAllChildren()

        resultNode.removeFromParent()
        gameOverNode.removeFromParent()
        graveNode.removeFromParent()
        clearMilestoneTint()
        // A rating prompt still waiting belongs to the round just left.
        removeAction(forKey: "ratingAsk")

        refreshTheme()

        addChild(tapTap)
        addChild(getReady)
        addChild(scoreLabelNode)
        addChild(scoreLabelNodeInside)

        scoreLabelNode.setScale(1)
        scoreLabelNodeInside.setScale(1)

        score = 0

        applySpeed(GameMode.current.tuning.startSpeed)
        bird.speed = 1
        pipes.setScale(0)

        hasExtraLife = false
        heartNode.removeFromParent()
        removeAction(forKey: "revive")
        bird.alpha = 1

        bird.zRotation = 0
        bird.position = CGPoint(
            x: width / 2.5,
            y: height / 2
        )

        bird.removeAllActions()
        applyBirdAnimation()

        bird.physicsBody?.isDynamic = false
        bird.physicsBody?.velocity = .zero
        bird.physicsBody?.collisionBitMask =
            PhysicsCategory.land |
            PhysicsCategory.pipe

        hasHitGround = false
        isGameOver = false
        isShowingGameOver = false
        isWaitingToStart = true

        lastFlapTime = 0

        startIdleAnimation()
    }

    // MARK: Physics

    private func isContact(
        _ contact: SKPhysicsContact,
        with category: UInt32
    ) -> Bool {
        let bodyA = contact.bodyA.categoryBitMask
        let bodyB = contact.bodyB.categoryBitMask

        return
            bodyA & category == category ||
            bodyB & category == category
    }

    private func handleScore() {
        score += 1
        GameLog.add("point \(score)")

        if score == Constants.superScore {
            enableSuperBird()
        }

        if haptics {
            scoreFeedback.impactOccurred(intensity: 0.5)
            scoreFeedback.prepare()
        }

        playSound(pointSound)

        if Self.isMilestone(score) {
            celebrateMilestone()
        }

        if roundMode != .normal {
            let tuning = roundMode.tuning
            let speed = tuning.speed(forScore: score)
            if CGFloat(speed) != speedFactor {
                applySpeed(speed)
            }

            if tuning.lives, !hasExtraLife, Tuning.earnsLife(score: score) {
                earnExtraLife()
            }
        }

        scaleTwice(
            node: scoreLabelNode,
            firstScale: 1.5,
            firstScaleDuration: 0.1,
            secondScale: 1,
            secondScaleDuration: 0.1
        )

        scaleTwice(
            node: scoreLabelNodeInside,
            firstScale: 1.5,
            firstScaleDuration: 0.1,
            secondScale: 1,
            secondScaleDuration: 0.1
        )
    }

    /// 10, 25, 50, 100, then every 100.
    private static func isMilestone(_ score: Int) -> Bool {
        switch score {
        case 10, 25, 50: return true
        default: return score >= 100 && score % 100 == 0
        }
    }

    /// Score and bird flash gold for about a second; from 50 up the pipes on
    /// screen flash too. Tint actions only; nothing is created per point.
    private func celebrateMilestone() {
        let gold = Constants.milestoneGold
        let flash = SKAction.sequence([
            .colorize(with: gold, colorBlendFactor: 1, duration: 0.08),
            .wait(forDuration: 0.6),
            .colorize(withColorBlendFactor: 0, duration: 0.4)
        ])

        scoreLabelNodeInside.run(flash, withKey: "milestone")

        bird.run(
            .sequence([
                .colorize(with: gold, colorBlendFactor: 0.65, duration: 0.08),
                .wait(forDuration: 0.6),
                .colorize(withColorBlendFactor: 0, duration: 0.4)
            ]),
            withKey: "milestone"
        )

        guard score >= 50 else {
            return
        }

        let pipeFlash = SKAction.sequence([
            // Strong blend: at 0.6 the green pipes read as olive, not gold.
            .colorize(with: gold, colorBlendFactor: 0.85, duration: 0.08),
            .wait(forDuration: 0.5),
            .colorize(withColorBlendFactor: 0, duration: 0.3)
        ])

        for group in pipes.children {
            for case let pipe as SKSpriteNode in group.children {
                pipe.run(pipeFlash, withKey: "milestone")
            }
        }
    }

    private func clearMilestoneTint() {
        for node in [bird, scoreLabelNodeInside] as [SKNode] {
            node.removeAction(forKey: "milestone")
        }
        bird.colorBlendFactor = 0
        scoreLabelNodeInside.colorBlendFactor = 0

        for group in pipes.children {
            for case let pipe as SKSpriteNode in group.children {
                pipe.removeAction(forKey: "milestone")
                pipe.colorBlendFactor = 0
            }
        }
    }

    /// Looked up once; the switch happens inside the scoring contact callback.
    private var superBirdTextures: [SKTexture] {
        (1...3).map { birdTexture("super", frame: $0) }
    }

    private func enableSuperBird() {
        birdTextures = superBirdTextures
        applyBirdAnimation()
    }

    private func handlePipeCollision() {
        gameOver()
    }

    // MARK: Extra Life

    private func earnExtraLife() {
        hasExtraLife = true
        GameLog.add("life earned score=\(score)")

        heartNode.removeFromParent()
        heartNode.setScale(0)
        addChild(heartNode)
        scaleTwice(node: heartNode, firstScale: 1.4, firstScaleDuration: 0.1, secondScale: 1, secondScaleDuration: 0.1)
    }

    /// A pipe was hit with an extra life in hand: the life goes, that pipe
    /// pair turns to a ghost the bird flies through, and the round goes
    /// on. False when there is no life to spend.
    private func tryRevive(_ contact: SKPhysicsContact) -> Bool {
        let pipeBody = contact.bodyA.categoryBitMask & PhysicsCategory.pipe != 0
            ? contact.bodyA
            : contact.bodyB

        guard hasExtraLife, let group = pipeBody.node?.parent else {
            return false
        }

        hasExtraLife = false
        heartNode.removeFromParent()
        GameLog.add("life used score=\(score)")

        // This pair no longer touches anything; its score sensor still
        // counts. The pairs behind it are as solid as ever.
        for case let pipe as SKSpriteNode in group.children where pipe.name == "pipeUp" || pipe.name == "pipeDown" {
            pipe.physicsBody?.categoryBitMask = 0
            pipe.physicsBody?.contactTestBitMask = 0
            pipe.alpha = 0.35
        }

        // The hit has already shoved and spun the bird: put it back on
        // its line with a small hop, as after a flap.
        bird.position.x = width / 2.5
        bird.physicsBody?.velocity = CGVector(dx: 0, dy: 150)
        bird.physicsBody?.angularVelocity = 0
        bird.zRotation = Constants.flapRotation
        lastFlapTime = CFAbsoluteTimeGetCurrent()

        // Blinks on the scene's clock: the bird's own speed changes with
        // its tilt.
        let blink = SKAction.sequence([
            .run { [weak self] in self?.bird.alpha = 0.35 },
            .wait(forDuration: 0.08),
            .run { [weak self] in self?.bird.alpha = 1 },
            .wait(forDuration: 0.08)
        ])
        run(.repeat(blink, count: 5), withKey: "revive")

        flashScreen(
            color: UIColor(red: 1, green: 0.55, blue: 0.60, alpha: 1),
            fadeInDuration: 0.05,
            peakAlpha: 0.6,
            fadeOutDuration: 0.2
        )

        if haptics {
            notificationFeedback.notificationOccurred(.warning)
        }

        playSound(hitSound)
        return true
    }

    /// Play log: what was on screen in the last drawn frame before a pipe
    /// death, so a death that looked unfair can be checked.
    ///
    /// Pipes are moved once per frame, before the bird's physics, so inside
    /// this callback the pipe is already at this frame's place while the
    /// bird is still where it was drawn. "air" is the space he saw between
    /// the bird's body and the pipe in that last drawn frame. At a smooth
    /// frame rate it is a few units (the pipe moves 1.7 a frame at 120 Hz,
    /// the bird up to about 8). A large "air" together with a long frame
    /// means the hit happened in a jump he never saw.
    private func logPipeDeath(_ contact: SKPhysicsContact, revived: Bool) {
        guard GameLog.enabled else {
            return
        }

        let pipeBody = contact.bodyA.categoryBitMask & PhysicsCategory.pipe != 0
            ? contact.bodyA
            : contact.bodyB

        guard let pipe = pipeBody.node as? SKSpriteNode,
              let group = pipe.parent else {
            return
        }

        let centre = group.convert(pipe.position, to: self)
        let halfWidth = pipe.size.width / 2
        let halfHeight = pipe.size.height / 2
        let radius = defaultBirdTexture.height * Constants.birdScale / 2

        // Where the pipe was when he last saw it: it has since moved this far.
        let moved = CGFloat(timeSinceDrawn / Constants.pipeMoveSpeed) * moving.speed
        let drawnCentreX = centre.x + moved

        let dx = max(abs(drawnBirdPosition.x - drawnCentreX) - halfWidth, 0)
        let dy = max(abs(drawnBirdPosition.y - centre.y) - halfHeight, 0)
        let lip = pipe.name == "pipeUp" ? centre.y + halfHeight : centre.y - halfHeight

        GameLog.add(String(
            format: (revived ? "hit PIPE, life used" : "death PIPE") + " (%@) score=%d | last drawn: bird=(%.1f,%.1f) vy=%.0f pipe x=%.1f..%.1f lip y=%.1f air=%.1f | since then: pipe moved %.1f, %d frame(s) not drawn | this frame %.0fms real (%.0fms scheduled), before=%.0fms, since tap=%.0fms",
            pipe.name == "pipeUp" ? "bottom" : "top",
            score, drawnBirdPosition.x, drawnBirdPosition.y, drawnBirdVelocityY,
            drawnCentreX - halfWidth, drawnCentreX + halfWidth, lip,
            hypot(dx, dy) - radius,
            moved, undrawnSinceDrawn,
            realFrameTime * 1000, lastFrameTime * 1000,
            frameTimeBefore * 1000,
            millisecondsSinceTap
        ))
    }

    /// -1 when no tap has happened yet.
    private var millisecondsSinceTap: Double {
        lastTapTime > 0 ? (CACurrentMediaTime() - lastTapTime) * 1000 : -1
    }

    /// The bird bursts into pieces where it was hit. What is left of it
    /// still falls (unseen) to the ground, which brings the headstone and
    /// the results as after any death.
    private func explodeBird() {
        let colors: [UIColor] = [
            .white,
            UIColor(red: 1, green: 0.86, blue: 0.31, alpha: 1),
            UIColor(red: 1, green: 0.59, blue: 0.16, alpha: 1),
            UIColor(red: 0.90, green: 0.20, blue: 0.16, alpha: 1),
            PanelButton.textColor,
        ]
        let pieces = 30

        for index in 0..<pieces {
            let side = CGFloat([4, 6, 8, 10][index % 4])
            let angle = CGFloat(index) / CGFloat(pieces) * 2 * .pi + CGFloat.random(in: -0.2...0.2)
            let reach = CGFloat.random(in: 70...190)

            let piece = SKSpriteNode(color: colors[index % colors.count], size: CGSize(width: side, height: side)).then {
                $0.position = bird.position
                $0.zPosition = GameZPosition.bird + 0.5
            }
            addChild(piece)

            let fly = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach, duration: 0.5)
            fly.timingMode = .easeOut

            piece.run(.sequence([
                .group([
                    fly,
                    .rotate(byAngle: .pi * 2, duration: 0.5),
                    .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.25)])
                ]),
                .removeFromParent()
            ]))
        }

        bird.alpha = 0

        flashScreen(
            color: UIColor(red: 1, green: 0.55, blue: 0.10, alpha: 1),
            fadeInDuration: 0.04,
            peakAlpha: 0.8,
            fadeOutDuration: 0.3
        )

        // A second jolt on top of the death shake.
        run(.sequence([.wait(forDuration: 0.25), .run { [weak self] in self?.shakeScreen() }]))
    }

    private func showGrave() {
        // A headstone in the hard modes, the wooden cross in the normal game.
        graveNode.texture = Assets.shared.sprites.textureNamed(roundMode == .normal ? "grave-cross" : "grave-stone").then {
            $0.filteringMode = .nearest
        }
        graveNode.size = graveNode.texture?.size() ?? graveNode.size

        graveNode.removeAllActions()
        graveNode.removeFromParent()
        graveNode.position = CGPoint(
            x: bird.position.x + 30,
            y: groundTexture.height * 2 - Constants.groundDrop
        )
        graveNode.setScale(0)
        addChild(graveNode)

        // Same pixel size as the bird.
        graveNode.run(
            .sequence([
                .wait(forDuration: 0.15),
                .scale(to: Constants.birdScale * 1.15, duration: 0.1),
                .scale(to: Constants.birdScale, duration: 0.08)
            ])
        )
    }

    private func handleGroundCollision() {
        guard !hasHitGround else {
            return
        }

        hasHitGround = true
        bird.speed = 0.5

        if !isShowingGameOver {
            GameLog.add(String(
                format: "death GROUND score=%d bird=(%.1f,%.1f) frame=%.0fms before=%.0fms since tap=%.0fms",
                score, bird.position.x, bird.position.y,
                lastFrameTime * 1000, frameTimeBefore * 1000,
                millisecondsSinceTap
            ))
            gameOver()
        } else {
            GameLog.add("landed")
        }

        showGrave()

        bird.physicsBody?.velocity = .zero

        run(
            .sequence([
                .wait(forDuration: Constants.gameOverDelay),
                .run { [weak self] in
                    self?.bird.speed = 0
                },
                .wait(forDuration: Constants.resultDelay),
                .run { [weak self] in
                    guard let self else { return }

                    self.playSound(self.swooshSound)
                    self.addResultsAndButtons()
                }
            ])
        )
    }
}

// MARK: - Physics Contact Delegate

extension GameScene: SKPhysicsContactDelegate {

    func didBegin(_ contact: SKPhysicsContact) {
        guard !hasHitGround else {
            return
        }

        if !isShowingGameOver &&
            (bird.speed == 1 || bird.speed == 2) {

            if isContact(
                contact,
                with: PhysicsCategory.score
            ) {
                handleScore()
                return
            }
        }

        if !isShowingGameOver &&
            isContact(
                contact,
                with: PhysicsCategory.pipe
            ) {
            // Logged either way, so a hit that cost a life can be checked too.
            logPipeDeath(contact, revived: hasExtraLife)
            if tryRevive(contact) {
                return
            }
            handlePipeCollision()
            return
        }

        if isContact(
            contact,
            with: PhysicsCategory.land
        ) {
            handleGroundCollision()
        }
    }
}

// MARK: - UI Helpers

private extension GameScene {

    func playSound(_ sound: SKAction?) {
        guard playSounds, let sound else {
            return
        }

        run(sound)
    }

    func scaleTwice(
        node: SKNode,
        firstScale: CGFloat,
        firstScaleDuration: TimeInterval,
        secondScale: CGFloat,
        secondScaleDuration: TimeInterval
    ) {
        node.run(
            .sequence([
                .scale(
                    to: firstScale,
                    duration: firstScaleDuration
                ),
                .scale(
                    to: secondScale,
                    duration: secondScaleDuration
                )
            ])
        )
    }

    /// ~0.25 s shake on death, back to exactly where the camera started.
    func shakeScreen() {
        // The centre, not where the camera is now: a shake that starts while
        // another is ending (the explosion's second jolt) would otherwise keep
        // the last bit of offset for good.
        let home = CGPoint(x: frame.midX, y: frame.midY)
        let offsets: [CGFloat] = [8, -7, 6, -5, 3, -2]

        shakeCamera.removeAction(forKey: "shake")
        shakeCamera.run(
            .sequence(
                offsets.map { .moveTo(x: home.x + $0, duration: 0.04) }
                    + [.move(to: home, duration: 0.02)]
            ),
            withKey: "shake"
        )
    }

    func flashScreen(
        color: UIColor,
        fadeInDuration: TimeInterval,
        peakAlpha: CGFloat,
        fadeOutDuration: TimeInterval
    ) {
        let flash = SKShapeNode(
            // Padded past the death shake (8 units) so no edge shows.
            rect: CGRect(
                x: -15,
                y: -15,
                width: width + 30,
                height: height + 30
            )
        )

        flash.zPosition = 7
        flash.fillColor = color
        flash.alpha = 0

        addChild(flash)

        flash.run(
            .sequence([
                .fadeAlpha(
                    to: peakAlpha,
                    duration: fadeInDuration
                ),
                .fadeAlpha(
                    to: 0,
                    duration: fadeOutDuration
                ),
                .removeFromParent()
            ])
        )
    }
}
