
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
        
        bestScore.text = "\(ResultBoard.bestScore())"
        bestScoreInside.text = "\(ResultBoard.bestScore())"
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
        self.score = score
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
            let previousHighScore = ResultBoard.bestScore()
            if finalScore > previousHighScore {
                ResultBoard.setBestScore(finalScore)
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

public extension ResultBoard {
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

    class func bestScore() -> Int {
        return UserDefaults.standard.integer(forKey: "bestScore")
    }
    
    class func setBestScore(_ score: Int) {
        UserDefaults.standard.set(score, forKey: "bestScore")
        UserDefaults.standard.synchronize()
    }
}
