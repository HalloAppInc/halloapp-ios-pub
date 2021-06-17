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

extension UserDefaults {
    public func codable<T: Codable>(forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else { return nil }
        let decodedData = try PropertyListDecoder().decode(T.self, from: data)
        
        return decodedData
    }
    
    public func setValue<T: Codable>(value: T, forKey key: String) throws {
        let data = try PropertyListEncoder().encode(value)
        return setValue(data, forKey: key)
    }
}
