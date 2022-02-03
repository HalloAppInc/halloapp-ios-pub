//
//  MsgViewCell.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

protocol MsgViewCellDelegate: AnyObject {
    func msgViewCell(_ msgViewCell: MsgViewCell, replyTo msgId: String)
}

class MsgViewCell: UITableViewCell {
    weak var msgViewCellDelegate: MsgViewCellDelegate?
    public var tableIndexPath: IndexPath? = nil
    public var indexPath: IndexPath? = nil
    public var messageID: String? = nil

    private var isReplyTriggered = false // track if swiping gesture on cell is enough to trigger reply

    // MARK: Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageID = nil
        tableIndexPath = nil
        indexPath = nil
    }

    func highlight() {
        UIView.animate(withDuration: 0.5, animations: {
            self.contentView.backgroundColor = .systemGray4
        })
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            UIView.animate(withDuration: 0.5, animations: {
                self.contentView.backgroundColor = .primaryBg
            })
        }
    }

    private lazy var replyArrow: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))
        view.tintColor = UIColor.systemGray4
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 25).isActive = true
        view.heightAnchor.constraint(equalToConstant: 25).isActive = true
        view.isHidden = true
        return view
    }()

    @objc func panGestureCellAction(recognizer: UIPanGestureRecognizer)  {
        guard let view = recognizer.view else { return } // presumed to be bubbleRow
        guard let superview = view.superview else { return } // presumed to be mainView
        let replyArrowStartOffset:CGFloat = -25.0
        let replyArrowOffset:CGFloat = replyArrowStartOffset - replyArrow.frame.width
        let replyTriggerThreshold = UIScreen.main.bounds.size.width / 4.5

        // add to mainView so arrow can appear off-screen and slide in
        if !superview.subviews.contains(replyArrow) {
            superview.addSubview(replyArrow)
            replyArrow.isHidden = false

            replyArrow.trailingAnchor.constraint(equalTo: superview.leadingAnchor, constant: replyArrowStartOffset).isActive = true

            // anchor to bubbleRow since mainView can have the timestamp row also
            replyArrow.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        }

        let translation = recognizer.translation(in: view) // movement in the gesture
        let originX = view.frame.origin.x
        let originY = view.frame.origin.y

        let newViewCenter = CGPoint(x: view.center.x + translation.x, y: view.center.y)
        let newReplyArrowCenter = CGPoint(x: replyArrow.center.x + translation.x, y: replyArrow.center.y)

        if (originX + translation.x) > 0 {
            view.center = newViewCenter // move bubbleRow view
            if originX < replyTriggerThreshold {
                replyArrow.center = newReplyArrowCenter // only move reply arrow forward if it's not past threshold
            } else {
                let replyArrowCenterMaxX = replyTriggerThreshold - replyArrow.frame.width
                replyArrow.center = CGPoint(x: replyArrowCenterMaxX, y: replyArrow.center.y)
            }
        } else {
            // move back to 0, barely noticeable but helps eliminate small stutter when dragging towards 0 to negatives
            view.frame = CGRect(x: 0, y: originY, width: view.frame.size.width, height: view.frame.size.height)
            replyArrow.frame = CGRect(x: replyArrowOffset, y: replyArrow.frame.origin.y, width: replyArrow.frame.size.width, height: replyArrow.frame.size.height)
        }

        recognizer.setTranslation(CGPoint(x: 0, y: 0), in: view)

        let isOriginXPastThreshold = originX > replyTriggerThreshold

        if !isReplyTriggered, isOriginXPastThreshold {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isReplyTriggered = true
            replyArrow.tintColor = UIColor.primaryBlue
        }

        if !isOriginXPastThreshold {
            self.isReplyTriggered = false
            replyArrow.tintColor = UIColor.systemGray4
        }

        if recognizer.state == .ended {

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) { [weak self] in
                guard let self = self else { return }
                view.frame = CGRect(x: 0, y: originY, width: view.frame.size.width, height: view.frame.size.height)

                self.replyArrow.frame = CGRect(x: replyArrowOffset, y: self.replyArrow.frame.origin.y, width: self.replyArrow.frame.size.width, height: self.replyArrow.frame.size.height)
            } completion: { (finished) in
                guard let messageID = self.messageID else { return }

                if self.isReplyTriggered {
                    self.msgViewCellDelegate?.msgViewCell(self, replyTo: messageID)
                    self.isReplyTriggered = false
                }

                if superview.subviews.contains(self.replyArrow) {
                    self.replyArrow.removeFromSuperview()
                }
            }
        }
    }

}

extension MsgViewCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        guard MainAppContext.shared.chatData.proceedIfNotGroupInviteLink(URL) else { return false }
        return true
    }
}
