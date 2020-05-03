//
//  CharacterSet.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/2/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension CharacterSet {

    static var phoneNumberCharacters: CharacterSet {
        get { CharacterSet(charactersIn: "0123456789-+(). ") }
    }
}
