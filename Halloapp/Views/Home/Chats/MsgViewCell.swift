//
//  MsgViewCell.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit

class MsgViewCell: UITableViewCell {
    
    // MARK: Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func prepareForReuse() {
        super.prepareForReuse()
        dateColumn.isHidden = true
        dateLabel.text = nil
    }
    
    func addDateRow(timestamp: Date?) {
        guard let timestamp = timestamp else { return }
        dateColumn.isHidden = false
        dateLabel.text = timestamp.chatMsgGroupingTimestamp()
    }
    
    // MARK:
    
    lazy var dateColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [dateWrapper])
        view.axis = .vertical
        view.alignment = .center
        
        view.layoutMargins = UIEdgeInsets(top: 5, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.isHidden = true
                
        return view
    }()
    
    lazy var dateWrapper: UIStackView = {

        let view = UIStackView(arrangedSubviews: [ dateLabel ])
        view.axis = .horizontal
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 5, left: 15, bottom: 5, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.systemBlue
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        return view
    }()
    
    lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        let baseFont = UIFont.preferredFont(forTextStyle: .footnote)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        label.font = boldFont
        label.textColor = .systemGray6
        return label
    }()

}
