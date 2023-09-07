//
//  LocationPermissionsMonitor.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/6/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Combine
import CoreLocation

class LocationPermissionsMonitor: NSObject {

    static let shared = LocationPermissionsMonitor()

    let authorizationStatus = CurrentValueSubject<CLAuthorizationStatus, Never>(CLLocationManager.authorizationStatus())

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
    }
}

extension LocationPermissionsMonitor: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus.send(status)
    }
}
