//
//  XMPPMediaRequests.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

struct MediaURL {
    var get: URL, put: URL
}

class XMPPMediaUploadURLRequest : XMPPRequest {
    typealias XMPPMediaUploadURLRequestCompletion = (MediaURL?, Error?) -> Void

    var completion: XMPPMediaUploadURLRequestCompletion

    init(completion: @escaping XMPPMediaUploadURLRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo), elementID: UUID().uuidString)
        iq.addChild(XMPPElement(name: "upload_media", xmlns: "ns:upload_media"))
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        var urls: MediaURL?
        if let mediaURLs = response.childElement?.element(forName: "media_urls") {
            if let get = mediaURLs.attributeStringValue(forName: "get"), let put = mediaURLs.attributeStringValue(forName: "put") {
                if let getURL = URL(string: get), let putURL = URL(string: put) {
                    urls = MediaURL(get: getURL, put: putURL)
                }
            }
        }
        self.completion(urls, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}
