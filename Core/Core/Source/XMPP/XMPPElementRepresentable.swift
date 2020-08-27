//
//  XMPPElementRepresentable.swift
//  Core
//
//  Created by Igor Solomennikov on 8/25/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import XMPPFramework

public protocol XMPPElementRepresentable {
    var xmppElement: XMPPElement { get }
}
