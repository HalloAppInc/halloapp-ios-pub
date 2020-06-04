//
//  UserDefaults.swift
//  Core
//
//  Created by Igor Solomennikov on 6/2/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

extension UserDefaults {
    class var shared: UserDefaults { AppContext.shared.userDefaults }
}
