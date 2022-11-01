//
//  ReactionPicker.swift
//  HalloApp
//
//  Created by Coulson Zhang on 8/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Core
import SwiftUI

public protocol ReactionPickerDelegate: AnyObject {
    func reactionPicker(_ reactionPicker: ReactionPicker, didSelectReaction reaction: String?)
}

public final class ReactionPicker: UIControl {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    public override var bounds: CGRect {
        didSet { updateShapeLayers() }
    }

    public let reactions: [String] = ["❤️", "👏", "🔥", "😡", "😢", "😮", "😂"]
    public var currentReaction: String? {
        didSet { updateButtons() }
    }
    public var arrowXPosition: CGFloat? {
        didSet { updateShapeLayers() }
    }
    public let arrowHeight: CGFloat = 9
    public weak var delegate: ReactionPickerDelegate?

    private func commonInit() {
        layer.addSublayer(borderLayer)
        layer.addSublayer(gradientLayer)
        addSubview(emojiStack)

        emojiStack.translatesAutoresizingMaskIntoConstraints = false
        emojiStack.constrain([.leading, .trailing, .top], to: self)
        emojiStack.constrain(anchor: .bottom, to: self, constant: -arrowHeight)
    }

    private func updateShapeLayers() {
        let shapeMask = makeShapeMask()

        borderLayer.frame = bounds
        borderLayer.path = shapeMask.path
        borderLayer.shadowPath = shapeMask.path
        borderLayer.setNeedsDisplay()

        gradientLayer.frame = bounds
        gradientLayer.mask = shapeMask
        gradientLayer.setNeedsDisplay()
    }

    private lazy var emojiButtons: [EmojiButton] = {
        reactions.map {
            let button = EmojiButton(reaction: $0, selected: currentReaction == $0)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(didTapEmoji), for: .touchUpInside)
            return button
        }
    }()

    private lazy var emojiStack: UIStackView = {
        let emojiStack = UIStackView(arrangedSubviews: emojiButtons)
        emojiStack.distribution = .equalSpacing
        emojiStack.axis = .horizontal
        emojiStack.spacing = 5
        emojiStack.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        emojiStack.isLayoutMarginsRelativeArrangement = true
        return emojiStack
    }()

    private lazy var gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor.reactionGradientBgTop.cgColor, UIColor.reactionGradientBgBottom.cgColor]
        layer.mask = makeShapeMask()
        return layer
    }()

    private lazy var borderLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.path = makeShapeMask().path
        layer.lineWidth = 1
        layer.strokeColor = UIColor.reactionGradientBgBottom.cgColor
        layer.fillColor = CGColor(gray: 0, alpha: 0)
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowPath = layer.path
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 5)
        layer.shadowOpacity = 0.15
        return layer
    }()

    private func makeShapeMask() -> CAShapeLayer {
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = makeShape(
            bubbleSize: CGSize(width: bounds.width, height: bounds.height - arrowHeight),
            arrowXPosition: arrowXPosition).cgPath
        return mask
    }

    /// Draws bubble with downward arrow.
    private func makeShape(bubbleSize: CGSize, arrowXPosition: CGFloat?) -> UIBezierPath {
        let radius = bubbleSize.height / 2

        let path = UIBezierPath()

        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: bubbleSize.width - radius, y: 0))
        path.addArc(withCenter: CGPoint(x: bubbleSize.width-radius, y: radius), radius: radius, startAngle: -.pi/2, endAngle: .pi/2, clockwise: true)
        if let arrowXPosition = arrowXPosition {
            path.addLine(to: CGPoint(x: arrowXPosition + arrowHeight, y: bubbleSize.height))
            path.addLine(to: CGPoint(x: arrowXPosition, y: bubbleSize.height + arrowHeight))
            path.addLine(to: CGPoint(x: arrowXPosition - arrowHeight, y: bubbleSize.height))
        }
        path.addLine(to: CGPoint(x: radius, y: bubbleSize.height))
        path.addArc(withCenter: CGPoint(x: radius,y: radius), radius: radius, startAngle: .pi/2, endAngle: -.pi/2, clockwise: true)
        path.close()
        return path
    }

    private func updateButtons() {
        emojiButtons.forEach {
            $0.isSelected = currentReaction == $0.reaction
        }
    }

    @objc private func didTapEmoji(_ button: EmojiButton) {
        if currentReaction == button.reaction {
            currentReaction = nil
        } else {
            currentReaction = button.reaction
        }
        delegate?.reactionPicker(self, didSelectReaction: currentReaction)
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        borderLayer.strokeColor = UIColor.reactionGradientBorder.cgColor
        borderLayer.setNeedsDisplay()

        gradientLayer.colors = [UIColor.reactionGradientBgTop.cgColor, UIColor.reactionGradientBgBottom.cgColor]
        gradientLayer.setNeedsDisplay()
    }
}


private class EmojiButton: UIControl {
    var reaction: String
    
    init(reaction: String, selected: Bool) {
        self.reaction = reaction
        
        super.init(frame: .zero)
        addSubview(circleView)
        addSubview(emojiLabel)

        self.isSelected = selected
        updateForSelection()

        circleView.constrain(to: self)
        NSLayoutConstraint.activate([
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
            widthAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            updateForSelection()
        }
    }

    private lazy var emojiLabel: UILabel = {
        let emojiLabel = UILabel()
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.text = reaction
        emojiLabel.numberOfLines = 1
        emojiLabel.font = .systemFont(ofSize: 30)
        emojiLabel.isUserInteractionEnabled = false
        return emojiLabel
    }()

    private lazy var circleView: CircleView = {
        let circle = CircleView()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.fillColor = .clear
        circle.isUserInteractionEnabled = false
        return circle
    }()
    
    private func updateForSelection() {
        circleView.fillColor = isSelected ? .reactionSelected : .clear
    }
}
