//
//  Utils.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/17/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Foundation

class Utils {
    
    func randomString(_ length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
}
