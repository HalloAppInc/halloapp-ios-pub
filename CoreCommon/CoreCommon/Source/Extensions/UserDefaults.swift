//
//  UserDefaults.swift
//  Core
//
//  Created by Igor Solomennikov on 6/2/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

extension UserDefaults {
    public class var shared: UserDefaults { AppContextCommon.shared.userDefaults }
}

extension UserDefaults {
    public func codable<T: Codable>(forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else { return nil }
        let decodedData = try PropertyListDecoder().decode(T.self, from: data)
        
        return decodedData
    }
    
    public func setCodable<T: Codable>(_ value: T, forKey key: String) throws {
        let data = try PropertyListEncoder().encode(value)
        return setValue(data, forKey: key)
    }
}
