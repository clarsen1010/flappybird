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
    private lazy var pauseButton = makePauseButton()
    private lazy var resumeButton = makeResumeButton()
    private lazy var pauseOverlay = makePauseOverlay()

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

    private static var settingsButton =
        SKSpriteNode(
            texture: settingsButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "settings"
            $0.setScale(1.2)
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
        }

    private static var bestRunsButton =
        SKSpriteNode(
            texture: blankButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then {
            $0.name = "bestRuns"
            $0.setScale(1.2)
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

    /// Two birds facing each other.
    private static var friendsButton =
        SKSpriteNode(
            texture: blankButtonTexture.then {
                $0.filteringMode = .nearest
            }
        ).then { button in
            button.name = "friends"
            button.setScale(1.2)

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
        pauseButton.removeFromParent()
        resumeButton.removeFromParent()

        score = 0

        moving.speed = 1
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

        settingsNode.soundToggle.position = CGPoint(
            x: playSounds
                ? SettingsPositions.toggleOnX
                : SettingsPositions.toggleOffX,
            y: SettingsPositions.soundToggleY
        )

        settingsNode.hapticsToggle.position = CGPoint(
            x: haptics
                ? SettingsPositions.toggleOnX
                : SettingsPositions.toggleOffX,
            y: SettingsPositions.hapticsToggleY
        )

        settingsNode.darkModeToggle.position = CGPoint(
            x: darkMode
                ? SettingsPositions.toggleOnX
                : SettingsPositions.toggleOffX,
            y: SettingsPositions.darkModeToggleY
        )

        settingsNode.logsToggle.position = CGPoint(
            x: logsOn
                ? SettingsPositions.toggleOnX
                : SettingsPositions.toggleOffX,
            y: SettingsPositions.logsToggleY
        )
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

    private func makeSettingsNode() -> SettingsPanel {
        SettingsPanel().then {
            $0.setScale(1.2)
            $0.zPosition = GameZPosition.resultText + 4
            // 22 lower than before: the panel grew a row (LOGS) and its top
            // edge stays where it was, clear of the title.
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 - 7
            )
        }
    }

    private func makeBestRunsNode() -> BestRunsPanel {
        BestRunsPanel().then {
            $0.setScale(1.2)
            $0.zPosition = GameZPosition.resultText + 4
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 15
            )
        }
    }

    private func makeFriendsNode() -> FriendsPanel {
        FriendsPanel().then {
            $0.setScale(1.2)
            $0.zPosition = GameZPosition.resultText + 4
            $0.position = CGPoint(
                x: width / 2,
                y: height / 2 + 15
            )
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
            birdTextures[index] =
                Assets.shared.sprites.textureNamed(
                    "\(color)-bird-\(index + 1)"
                ).then {
                    $0.filteringMode = .nearest
                }
        }

        currentBirdColor = roundColor
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

        switch nodeName {
        case "play":
            handlePlayTap()
            
        case "pause":
            handlePauseTap()

        case "resume":
            handleResumeTap()

        case "settings":
            handleSettingsTap()

        case "birdPicker":
            handleBirdPickerTap()

        case "bestRuns":
            handleBestRunsTap()

        case "bestRunsBack":
            handleBestRunsBack()

        case "bestRunsNext":
            handleBestRunsNext()

        case "friends":
            handleFriendsTap()

        case "friendsBack":
            handleFriendsBack()

        case "friendsNext":
            handleFriendsNext()

        case "friendsAdd":
            handleFriendsAdd()

        case "friendsMe":
            handleFriendsMe()

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

        case "settingsBack":
            handleSettingsBack()

        default:
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

    /// A round in flight: started, not dead, not paused.
    private var isRoundLive: Bool {
        !isWaitingToStart && !isGameOver && !isPausedByUser
            && bird.physicsBody?.isDynamic == true
    }

    /// For the play log: what a tap landed on, or what the game will do with it.
    private func tapTarget(_ nodeName: String?) -> String {
        switch nodeName {
        case "play", "pause", "settings", "birdPicker", "bestRuns",
             "bestRunsBack", "bestRunsNext", "settingsBack", "friends",
             "friendsBack", "friendsNext", "friendsAdd", "friendsMe", "editName":
            // These ignore taps while the button lock is on.
            return (nodeName ?? "?") + (Self.hitButton ? " (locked, ignored)" : "")
        case "resume", "toggleSounds", "toggleHaptics", "toggleDarkMode",
             "toggleLogs":
            return nodeName ?? "?"
        default:
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
        startPipeSpawner()
        pipes.setScale(1)

        bird.physicsBody?.isDynamic = true

        GameLog.roundStarted(
            "theme=\(nightShown ? "night" : "day") bird=\(currentBirdColor)"
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

        isPaused = true
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

        settingsNode.setScale(0)
        addChild(settingsNode)

        scaleTwice(
            node: settingsNode,
            firstScale: 1,
            firstScaleDuration: 0.1,
            secondScale: 1.2,
            secondScaleDuration: 0.1
        )

        unlockButtons()
    }

    private func handleSettingsBack() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        settingsNode.backButton.setScale(0.8)

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
                    self.settingsNode.backButton.setScale(1)
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                self?.hideSettings()
                self?.unlockButtons()
            }
        )
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
        for node in menuButtons + [playButton, isGameOver ? resultNode : bird] {
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
        for node in menuButtons + [playButton] {
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

    private func handleBestRunsBack() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        bestRunsNode.backButton.setScale(0.8)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }

                    self.bestRunsNode.backButton.setScale(1)
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                self?.hideBestRuns()
                self?.unlockButtons()
            }
        )
    }

    private func handleBestRunsNext() {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        bestRunsNode.nextPage()
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

        unlockButtons()
        refreshFriends()
    }

    /// Fetches the lists; the panel shows what it has until they arrive.
    private func refreshFriends() {
        FriendsStore.refresh { [weak self] in
            guard let self, self.friendsNode.parent != nil else {
                return
            }

            self.friendsNode.reload(keepPage: true)

            // First visit with no name yet: ask once.
            if !Self.hitButton, FriendsStore.shouldAskForName() {
                Self.hitButton = true
                self.askForName()
            }
        }

        // Shows LOADING while the first fetch runs.
        friendsNode.reload(keepPage: true)
    }

    private func handleFriendsBack() {
        guard !Self.hitButton else {
            return
        }

        Self.hitButton = true

        playSound(swooshSound)

        friendsNode.backButton.setScale(0.8)

        run(
            SKAction.sequence([
                .wait(forDuration: 0.1),
                .run { [weak self] in
                    guard let self else { return }

                    if self.haptics {
                        self.impactFeedback.impactOccurred()
                    }

                    self.friendsNode.backButton.setScale(1)
                },
                .wait(forDuration: 0.1)
            ]),
            completion: { [weak self] in
                self?.hideFriends()
                self?.unlockButtons()
            }
        )
    }

    private func handleFriendsNext() {
        guard !Self.hitButton else {
            return
        }

        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        friendsNode.nextPage()
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
    }

    private func handleFriendsAdd() {
        guard takePromptTap() else {
            return
        }

        askForFriend()
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
    /// open and no other alert is up; otherwise the prompt is dropped and
    /// the buttons are released.
    private func present(_ alert: UIAlertController) {
        guard friendsNode.parent != nil || settingsNode.parent != nil,
              let presenter = promptPresenter,
              presenter.presentedViewController == nil else {
            endPrompt()
            return
        }

        Self.hitButton = true
        GameLog.add("prompt shown")
        presenter.present(alert, animated: true)
    }

    /// Every prompt flow ends here: redraws what a prompt can change, gives
    /// the spacebar handler its focus back and releases the buttons.
    private func endPrompt() {
        GameLog.add("prompt closed")
        friendsNode.reload(keepPage: true)
        settingsNode.showName(FriendsStore.myName)
        promptPresenter?.becomeFirstResponder()
        unlockButtons()
    }

    private func showNotice(title: String, message: String) {
        present(NamePrompt.notice(title: title, message: message) { [weak self] in
            self?.endPrompt()
        })
    }

    private func askForName(message: String? = nil, text: String? = nil) {
        let current = FriendsStore.myName

        present(NamePrompt.name(
            title: current == nil ? "Pick a name" : "Your name",
            message: message ?? "3 to 10 letters or numbers. Friends add you by this name.",
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
                        self.endPrompt()
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
                    }
                }
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

            FriendsStore.deleteProfile { [weak self] deleted in
                guard let self else { return }

                if deleted {
                    self.endPrompt()
                } else {
                    self.showNotice(title: "Not deleted", message: "No connection. Try again later.")
                }
            }
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
                }
            }
        })
    }

    private func unlockButtons() {
        run(
            .sequence([
                .wait(forDuration: 0.2),
                .run {
                    Self.hitButton = false
                }
            ])
        )
    }

    // MARK: Settings Toggles

    private func toggle(
        value: inout Bool,
        key: String,
        control: SKNode,
        y: CGFloat
    ) {
        value.toggle()

        saveSetting(value, key: key)

        let targetX = value
            ? SettingsPositions.toggleOnX
            : SettingsPositions.toggleOffX

        let overshootX = value
            ? targetX - 6
            : targetX + 6

        control.run(
            .sequence([
                .move(
                    to: CGPoint(
                        x: overshootX,
                        y: y
                    ),
                    duration: 0.08
                ),
                .move(
                    to: CGPoint(
                        x: targetX,
                        y: y
                    ),
                    duration: Constants.toggleAnimationDuration
                )
            ])
        )
    }

    private func handleSoundToggle() {
        if haptics {
            impactFeedback.impactOccurred()
        }

        toggle(
            value: &playSounds,
            key: "playSounds",
            control: settingsNode.soundToggle,
            y: SettingsPositions.soundToggleY
        )

        // playSound() is a no-op while sound is off, so this only swooshes
        // when sound was just turned on.
        playSound(swooshSound)
    }

    private func handleHapticsToggle() {
        playSound(swooshSound)

        toggle(
            value: &haptics,
            key: "haptics",
            control: settingsNode.hapticsToggle,
            y: SettingsPositions.hapticsToggleY
        )

        if haptics {
            impactFeedback.impactOccurred()
        }
    }

    private func handleDarkModeToggle() {
        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        toggle(
            value: &darkMode,
            key: "darkMode",
            control: settingsNode.darkModeToggle,
            y: SettingsPositions.darkModeToggleY
        )

        refreshTheme()
    }

    private func handleLogsToggle() {
        playSound(swooshSound)

        if haptics {
            impactFeedback.impactOccurred()
        }

        toggle(
            value: &logsOn,
            key: GameLog.settingKey,
            control: settingsNode.logsToggle,
            y: SettingsPositions.logsToggleY
        )

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
    private var nightShown = false

    /// Night when Dark Mode is on and the phone is in dark appearance.
    private var isNight: Bool {
        darkMode && view?.traitCollection.userInterfaceStyle == .dark
    }

    /// Swaps day/night art on the existing nodes, so nothing restarts or
    /// jumps. Called at launch, from the Dark Mode switch, at each new round,
    /// and by GameViewController when the phone's appearance changes.
    func refreshTheme() {
        let night = isNight
        if night != nightShown {
            // iOS flips the appearance light and back while it takes its
            // app-switcher snapshots; those lines are labelled.
            GameLog.add("theme \(night ? "night" : "day")"
                + (UIApplication.shared.applicationState == .active ? "" : " (app not on screen)"))
        }
        nightShown = night

        backgroundColor = night ? Self.nightSkyTop : Self.daySkyTop

        for node in skyNodes {
            node.texture = night ? nightTexture : dayTexture
        }

        for node in groundNodes {
            node.texture = night ? groundNightTexture : groundTexture
        }

        for group in pipes.children {
            for case let pipe as SKSpriteNode in group.children {
                applyPipeLook(to: pipe, night: night)
            }
        }
    }

    /// Night pipes use the recolored night art (milder than the first cut).
    private func applyPipeLook(to pipe: SKSpriteNode, night: Bool) {
        switch pipe.name {
        case "pipeUp":
            pipe.texture = night ? pipeNightTextureUp : pipeTextureUp
        case "pipeDown":
            pipe.texture = night ? pipeNightTextureDown : pipeTextureDown
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

    private func makePipe(
        name: String,
        texture: SKTexture,
        position: CGPoint
    ) -> SKSpriteNode {
        SKSpriteNode(texture: texture).then {
            $0.name = name
            applyPipeLook(to: $0, night: nightShown)
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

    private func makeScoreNode() -> SKNode {
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
                    width: 4,
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

        // Before resultNode.score saves a new best (see BestRuns.record).
        BestRuns.record(score)
        GameStats.record(score: score)
        Achievements.record(score: score)

        resultNode.setScale(0)
        resultNode.score = score
        addChild(resultNode)

        // After every save above (the result board saves a new best).
        CloudSync.merge()
        FriendsStore.roundEnded()

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

    // MARK: Reset

    private func resetScene() {
        isPaused = false
        isPausedByUser = false

        pauseButton.removeFromParent()
        resumeButton.removeFromParent()
        pauseOverlay.removeFromParent()
        
        pipes.removeAllChildren()

        resultNode.removeFromParent()
        gameOverNode.removeFromParent()
        graveNode.removeFromParent()
        clearMilestoneTint()

        refreshTheme()

        addChild(tapTap)
        addChild(getReady)
        addChild(scoreLabelNode)
        addChild(scoreLabelNodeInside)

        scoreLabelNode.setScale(1)
        scoreLabelNodeInside.setScale(1)

        score = 0

        moving.speed = 1
        bird.speed = 1
        pipes.setScale(0)

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
    private let superBirdTextures = (1...3).map {
        Assets.shared.sprites.textureNamed("super-bird-\($0)").then {
            $0.filteringMode = .nearest
        }
    }

    private func enableSuperBird() {
        birdTextures = superBirdTextures
        applyBirdAnimation()
    }

    private func handlePipeCollision() {
        gameOver()
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
    private func logPipeDeath(_ contact: SKPhysicsContact) {
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
        let moved = CGFloat(timeSinceDrawn / Constants.pipeMoveSpeed)
        let drawnCentreX = centre.x + moved

        let dx = max(abs(drawnBirdPosition.x - drawnCentreX) - halfWidth, 0)
        let dy = max(abs(drawnBirdPosition.y - centre.y) - halfHeight, 0)
        let lip = pipe.name == "pipeUp" ? centre.y + halfHeight : centre.y - halfHeight

        GameLog.add(String(
            format: "death PIPE (%@) score=%d | last drawn: bird=(%.1f,%.1f) vy=%.0f pipe x=%.1f..%.1f lip y=%.1f air=%.1f | since then: pipe moved %.1f, %d frame(s) not drawn | this frame %.0fms real (%.0fms scheduled), before=%.0fms, since tap=%.0fms",
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

    private func showGrave() {
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
            logPipeDeath(contact)
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
        let home = shakeCamera.position
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
