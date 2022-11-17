//
//  WhatsAppShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

class WhatsAppShareProvider: DestinationShareProvider {

    static var analyticsShareDestination: String {
        return "whatsapp"
    }

    static var title: String {
        NSLocalizedString("shareprovider.whatsapp.title", value: "WhatsApp", comment: "Whatsapp messages share destination")
    }

    static var canShare: Bool {
        guard let url = URL(string: "whatsapp://app") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }
    
    static func share(destination: CoreCommon.ABContact.NormalizedPhoneNumber?, text: String?, image: UIImage?, completion: ShareProviderCompletion?) {
        guard var urlComponents = URLComponents(string: "https://wa.me") else {
            completion?(.failed)
            return
        }

        if let destination = destination {
            urlComponents.path = destination
        }

        var queryItems = [URLQueryItem]()

        if let text = text {
            queryItems.append(URLQueryItem(name: "text", value: text))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            completion?(.failed)
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            completion?(success ? .success : .failed)
        }
    }
}
