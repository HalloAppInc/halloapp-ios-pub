//
//  UserDefault.swift
//  HalloApp
//
//  Created by Tanveer on 7/21/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import CoreCommon

@propertyWrapper
struct UserDefault<T> {

    private let storage = MainAppContext.shared.userDefaults
    private let key: String
    private let defaultValue: T

    init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get {
            storage?.value(forKey: key) as? T ?? defaultValue
        }

        set {
            storage?.setValue(newValue, forKey: key)
        }
    }
}
