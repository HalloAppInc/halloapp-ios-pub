//
//  MsgUIProtocol.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/16/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

protocol MsgUIProtocol {
    
    var TextFontStyle: UIFont.TextStyle { get }
    var MaxWidthOfMsgBubble: CGFloat { get }
    
    func getNameColor(for userId: UserID, name: String, groupId: GroupID) -> UIColor
    func preferredSize(for media: [ChatMedia]) -> CGSize
    
}

extension MsgUIProtocol {
    
    var TextFontStyle: UIFont.TextStyle { return .subheadline }
    var MaxWidthOfMsgBubble: CGFloat { return UIScreen.main.bounds.width * 0.8 }
    
    func getNameColor(for userId: UserID, name: String, groupId: GroupID) -> UIColor {
        let groupIdSuffix = String(groupId.suffix(4))
        let userIdSuffix = String(userId.suffix(8))
        let str = "\(groupIdSuffix)\(userIdSuffix)\(name)"
        let colorInt = str.utf8.reduce(0) { return $0 + Int($1) } % 14
        
        // cyan not good
        let color: UIColor = {
            switch colorInt {
            case 0: return UIColor.systemBlue
            case 1: return UIColor.systemGreen
            case 2: return UIColor.systemIndigo
            case 3: return UIColor.systemOrange
            case 4: return UIColor.systemPink
            case 5: return UIColor.systemPurple
            case 6: return UIColor.systemRed
            case 7: return UIColor.systemTeal
            case 8: return UIColor.systemYellow
            case 9: return UIColor.systemGray
            case 10: return UIColor.systemBlue.withAlphaComponent(0.5)
            case 11: return UIColor.systemGreen.withAlphaComponent(0.5)
            case 12: return UIColor.brown
            case 13: return UIColor.magenta
            default: return UIColor.secondaryLabel
            }
        }()
        
        return color
    }
    
    func preferredSize(for media: [ChatMedia]) -> CGSize {
        guard !media.isEmpty else { return CGSize(width: 0, height: 0) }
        
        let maxRatio: CGFloat = 5/4 // height/width
        // should be smaller than bubble width to avoid constraint conflicts
        let maxWidth = MaxWidthOfMsgBubble - 10
        let maxHeight = maxWidth*maxRatio
        
        var tallest: CGFloat = 0
        var widest: CGFloat = 0
        for med in media {
            let ratio = med.size.height/med.size.width
            let height = maxWidth*ratio
            let width = maxHeight/ratio
            
            tallest = max(tallest, height)
            widest = max(widest, width)
        }
        
        tallest = min(tallest, maxHeight)
        widest = min(widest, maxWidth)
        return CGSize(width: widest, height: tallest)
    }
    
}
