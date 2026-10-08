
//
//  ResultBoard.swift
//  FlappyBird
//
//  Created by Brandon Plank on 12/2/19.
//  Modified by ThathcerDev on 3/22/20.
//  Copyright (c) 2016 Brandon Plank. All rights reserved.
//
import SpriteKit
import Network

public class ResultBoard: SKSpriteNode {
    
    override init(texture: SKTexture?, color: UIColor, size: CGSize) {
        super.init(texture: texture, color: color, size: size)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(score: Int) {
        let image = Assets.shared.sprites.textureNamed("scoreboard").then { $0.filteringMode = .nearest }
        self.init(texture: image, color: UIColor.clear, size: image.size())
        
        bestScore.text = "\(ResultBoard.best(mode: mode))"
        bestScoreInside.text = "\(ResultBoard.best(mode: mode))"
        currentScore.text = "0"
        currentScoreInside.text = "0"
        
        addChild(new)
        new.setScale(0)
        addChild(sparkle)
        addChild(currentScore)
        addChild(bestScore)
        addChild(currentScoreInside)
        addChild(bestScoreInside)
        addChild(medal)
        addChild(modeTag)
        addChild(modeTagInside)
        addChild(chaseLabelShadow)
        addChild(chaseLabel)
        self.score = score
    }
    
    // The mode's name along the card's top edge, in the score digits' style.
    private lazy var modeTag = SKLabelNode(fontNamed: "04b_19").then {
        $0.zPosition = GamezPosition.resultText + 1
        $0.fontSize = 12
        $0.fontColor = SKColor.black
        $0.verticalAlignmentMode = .center
        $0.position = CGPoint(x: frame.midX, y: frame.midY + 44)
    }

    private lazy var modeTagInside = SKLabelNode(fontNamed: "inside").then {
        $0.zPosition = GamezPosition.resultText
        $0.fontSize = 12
        $0.fontColor = SKColor.white
        $0.verticalAlignmentMode = .center
        $0.position = CGPoint(x: frame.midX - 0.37, y: frame.midY + 44)
    }

    // Just above the card, white on the sky with a dark edge under it.
    private lazy var chaseLabel = SKLabelNode(fontNamed: "KongtextRegular").then {
        $0.zPosition = GamezPosition.resultText + 1
        $0.fontSize = 8
        $0.fontColor = SKColor.white
        $0.verticalAlignmentMode = .center
        $0.position = CGPoint(x: frame.midX, y: frame.midY + 68)
    }

    private lazy var chaseLabelShadow = SKLabelNode(fontNamed: "KongtextRegular").then {
        $0.zPosition = GamezPosition.resultText
        $0.fontSize = 8
        $0.fontColor = PanelButton.textColor
        $0.verticalAlignmentMode = .center
        $0.position = CGPoint(x: frame.midX, y: frame.midY + 67)
    }

    private lazy var currentScore = SKLabelNode(fontNamed: "04b_19").then {
        $0.zPosition = GamezPosition.resultText + 1
        $0.fontSize = 16
        $0.fontColor = SKColor.black
        $0.position = CGPoint(x: frame.midX + 75, y: frame.midY + 7)
    }
    
    private lazy var currentScoreInside = SKLabelNode(fontNamed: "inside").then {
        $0.zPosition = GamezPosition.resultText
        $0.fontSize = 16
        $0.fontColor = SKColor.white
        $0.position = CGPoint(x: frame.midX + 75 - 0.49, y: frame.midY + 7)
    }
    
    private lazy var bestScore = SKLabelNode(fontNamed: "04b_19").then {
        $0.zPosition = GamezPosition.resultText + 1
        $0.fontSize = 16
        $0.fontColor = SKColor.black
        $0.position = CGPoint(x: frame.midX + 75, y: frame.midY - 35)
    }
    
    private lazy var bestScoreInside = SKLabelNode(fontNamed: "inside").then {
        $0.zPosition = GamezPosition.resultText
        $0.fontSize = 16
        $0.fontColor = SKColor.white
        $0.position = CGPoint(x: frame.midX + 75 - 0.49, y: frame.midY - 35)
    }
    
    private lazy var medal = SKSpriteNode().then {
        $0.zPosition = GamezPosition.resultText
        $0.position = CGPoint(x: frame.midX - 64, y: frame.midY - 6)
    }
    
    private lazy var new = SKSpriteNode(texture: Assets.shared.sprites.textureNamed("new").then { $0.filteringMode = .nearest }).then {
        $0.zPosition = GamezPosition.resultText
        $0.position = CGPoint(x: frame.midX + 35, y: frame.midY - 6)
        $0.setScale(0)
    }
    
    private lazy var sparkle = SKSpriteNode(texture: Assets.shared.sprites.textureNamed("sparkle").then { $0.filteringMode = .nearest }).then {
        $0.setScale(0)
        $0.zPosition = GamezPosition.resultText+1
    }
    
    private let sparkleAction = SKAction.repeatForever(SKAction.sequence([
        SKAction.customAction(withDuration: 0.0) { (node, _) in
            let newX = CGFloat(Float.random(in: -88...(-40)))
            let newY = CGFloat(Float.random(in: -26...15))
            node.run(SKAction.move(to: CGPoint(x: newX, y: newY), duration: 0.0))
        },
        SKAction.scale(to: 0.7, duration: 0.3),
        SKAction.wait(forDuration: 0.5),
        SKAction.scale(to: 0.0, duration: 0.3)
    ]))
    
    /// The mode the round was played in: which best the card shows. Set
    /// before `score`. The mode's name is no longer drawn on the card:
    /// next to the MODE button (the next round's mode) it read as a
    /// contradiction. To bring it back, set modeTag.text to mode.title.
    var mode = GameMode.normal {
        didSet {
            modeTag.text = ""
            modeTagInside.text = modeTag.text
        }
    }

    /// A line over the card: who is just ahead ("8 TO BEAT ALEX"). Nil
    /// for none.
    var chase: String? {
        didSet {
            chaseLabel.text = chase
            chaseLabelShadow.text = chase
        }
    }

    var score: Int = 0 {
        didSet {
            #if DEBUG
            print(timeTook)
            #endif
            guard canShowScore else {
                return
            }

            // Everything here touches SpriteKit nodes, so it stays on the main
            // thread; the count-up runs as SKActions instead of a background
            // thread + usleep. The best score is read and saved up front so the
            // medal below can't race the save.
            let finalScore = score
            let previousHighScore = ResultBoard.best(mode: mode)
            if finalScore > previousHighScore {
                ResultBoard.setBest(finalScore, mode: mode)
            }

            removeAction(forKey: "countUp")
            currentScore.text = "0"
            currentScoreInside.text = "0"
            bestScore.text = "\(previousHighScore)"
            bestScoreInside.text = "\(previousHighScore)"
            new.removeAllActions()
            new.setScale(0)

            // One 1.5s action rather than a wait per point: SpriteKit finishes
            // at most one wait per frame, so big scores counted up for seconds.
            let counter = CountUpProgress()
            let countUp = SKAction.customAction(withDuration: 1.5) { [weak self] _, elapsed in
                let i = min(finalScore, Int(CGFloat(finalScore) * elapsed / 1.5))
                guard i != counter.shown else {
                    return
                }
                counter.shown = i
                self?.showCount(i, of: finalScore, previousHighScore: previousHighScore)
            }
            let finish = SKAction.run { [weak self] in
                guard counter.shown != finalScore else {
                    return
                }
                counter.shown = finalScore
                self?.showCount(finalScore, of: finalScore, previousHighScore: previousHighScore)
            }
            run(.sequence([countUp, finish]), withKey: "countUp")

            // Classic medals: bronze 10, silver 20, gold 30, platinum 40.
            let medalName = ResultBoard.medalName(for: finalScore)
            let medalTexture = medalName.map { Assets.shared.sprites.textureNamed($0) } ?? SKTexture()
            medalTexture.filteringMode = .nearest
            medal.run(SKAction.setTexture(medalTexture, resize: true))

            sparkle.setScale(0)
            sparkle.removeAllActions()
            if medalName != nil {
                sparkle.run(sparkleAction)
            }
        }
    }

    private func showCount(_ i: Int, of finalScore: Int, previousHighScore: Int) {
        currentScore.text = "\(i)"
        currentScoreInside.text = "\(i)"
        if i > previousHighScore {
            bestScore.text = "\(i)"
            bestScoreInside.text = "\(i)"
            if i == finalScore {
                new.run(SKAction.sequence([
                    SKAction.scale(to: 0.7, duration: 0.05),
                    SKAction.scale(to: 1.0, duration: 0.05)
                ]))
            }
        }
    }
}

/// Last value shown by the result-board count-up.
private final class CountUpProgress {
    var shown = -1
}

extension ResultBoard {
    /// nil below 10: no medal.
    class func medalName(for score: Int) -> String? {
        switch score {
        case ..<10: return nil
        case ..<20: return "copper-medal"
        case ..<30: return "silver-medal"
        case ..<40: return "gold-medal"
        default: return "platinum-medal"
        }
    }

    /// Each mode has its own best. NORMAL's key is the one it always had.
    class func bestKey(mode: GameMode) -> String {
        "bestScore" + mode.suffix
    }

    class func best(mode: GameMode) -> Int {
        UserDefaults.standard.integer(forKey: bestKey(mode: mode))
    }

    /// The NORMAL best.
    class func bestScore() -> Int {
        best(mode: .normal)
    }

    class func setBest(_ score: Int, mode: GameMode) {
        UserDefaults.standard.set(score, forKey: bestKey(mode: mode))
        UserDefaults.standard.synchronize()
    }
}
