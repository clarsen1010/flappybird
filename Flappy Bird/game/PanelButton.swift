//
//  PanelButton.swift
//  FlappyBird
//
//  A framed word button for the panels (BACK, ADD FRIEND, SHARE, ...): the
//  menu buttons' own frame stretched to fit a word, so it reads as something
//  to press.
//
import Foundation
import SpriteKit

final class PanelButton: SKNode {

    static let textColor = UIColor(red: 79 / 255, green: 57 / 255, blue: 70 / 255, alpha: 1)

    // The frame art is 62x36: 8 px corners left and right, 12 px rows top
    // and bottom. Only the middle stretches.
    private static let artSize = CGSize(width: 62, height: 36)
    private static let centre = CGRect(x: 8.0 / 62, y: 12.0 / 36, width: 46.0 / 62, height: 12.0 / 36)

    private let frameNode = SKSpriteNode(texture: Assets.shared.sprites.textureNamed("blank-button").then { $0.filteringMode = .nearest })
    private let label = SKLabelNode(fontNamed: "KongtextRegular")
    private let touchBox: SKSpriteNode
    private let touchName: String

    let size: CGSize

    /// `width` defaults to the word plus a margin, never narrower than the
    /// art. `hit` is the touch area; it defaults to the frame plus 4 a side.
    init(name: String, text: String, textSize: CGFloat = 10, width: CGFloat? = nil, height: CGFloat = 36, hit: CGSize? = nil) {
        let width = width ?? max(Self.artSize.width, CGFloat(text.count) * textSize + 24)
        size = CGSize(width: width, height: height)
        touchName = name
        touchBox = SKSpriteNode(color: .clear, size: hit ?? CGSize(width: width + 8, height: height + 8))

        super.init()

        frameNode.centerRect = Self.centre
        frameNode.xScale = width / Self.artSize.width
        frameNode.yScale = height / Self.artSize.height
        frameNode.zPosition = 1
        addChild(frameNode)

        label.fontSize = textSize
        label.fontColor = Self.textColor
        label.verticalAlignmentMode = .center
        label.text = text
        // The face sits a pixel above the frame's middle: the bottom edge
        // is the thicker one.
        label.position = CGPoint(x: 0, y: 1)
        label.zPosition = 2
        addChild(label)

        // Above the label, or a tap on a glyph lands on the unnamed label.
        touchBox.name = name
        touchBox.zPosition = 3
        addChild(touchBox)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    /// Off: dimmed and deaf to taps (CHECKING, OFFLINE).
    var isEnabled = true {
        didSet {
            alpha = isEnabled ? 1 : 0.5
            touchBox.name = isEnabled ? touchName : nil
        }
    }

    /// A short pushed-in look. Buttons act on touch down, so this is a
    /// flash rather than a held state.
    func press() {
        removeAction(forKey: "press")
        label.position.y = -1
        frameNode.color = Self.textColor
        frameNode.colorBlendFactor = 0.25

        run(.sequence([
            .wait(forDuration: 0.12),
            .run { [weak self] in
                self?.label.position.y = 1
                self?.frameNode.colorBlendFactor = 0
            }
        ]), withKey: "press")
    }
}
