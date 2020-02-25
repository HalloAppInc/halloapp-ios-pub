//
//  MetaData.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/6/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

import CoreData

final class MetaData: ObservableObject {

    public var timeStartWhitelist = 0.0
    public var whiteListIds: [String] = []
    
    public var timeStartCheck = 0.0
    public var checkIds: [String] = []

}
