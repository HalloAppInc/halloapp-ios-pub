//
//  DeveloperSetting.swift
//  Core
//
//  Created by Garrett on 8/25/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import Foundation

public struct DeveloperSetting {
    public static var showDecryptionResults: Bool {
        get { AppContext.shared.userDefaults.bool(forKey: "showDecryptionResults", defaultValue: true) }
        set { AppContext.shared.userDefaults.set(newValue, forKey: "showDecryptionResults") }
    }
    public static var showMLImageRank: Bool {
        get { AppContext.shared.userDefaults.bool(forKey: "showMLImageRank", defaultValue: false) }
        set { AppContext.shared.userDefaults.set(newValue, forKey: "showMLImageRank") }
    }
    public static var showPhotoSuggestions: Bool {
        get { AppContext.shared.userDefaults.bool(forKey: "showPhotoSuggestions", defaultValue: false) }
        set { AppContext.shared.userDefaults.set(newValue, forKey: "showPhotoSuggestions") }
    }

    @UserDefaultsBackedSetting(key: "shown.photosuggestions.explainer")
    public static var didHidePhotoSuggestionsFirstUse = false
}

extension DeveloperSetting {

    @propertyWrapper fileprivate struct UserDefaultsBackedSetting<Value> {
        let key: String
        let defaultValue: Value
        let userDefaults: UserDefaults

        init(wrappedValue: Value, key: String, userDefaults: UserDefaults = AppContext.shared.userDefaults) {
            self.defaultValue = wrappedValue
            self.key = key
            self.userDefaults = userDefaults
        }

        var wrappedValue: Value {
            get {
                return userDefaults.value(forKey: key) as? Value ?? defaultValue
            }
            set {
                userDefaults.setValue(newValue, forKey: key)
            }
        }
    }
}
