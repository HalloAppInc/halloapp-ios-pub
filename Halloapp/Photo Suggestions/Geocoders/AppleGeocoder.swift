//
//  AppleGeocoder.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/15/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Contacts
import CoreLocation
import MapKit

class AppleGeocoder {

    private struct Constants {
        static let searchRadius: CLLocationDistance = 250
        static let pointOfInterestFilter = MKPointOfInterestFilter(excluding: [.atm, .parking, .evCharger, .restroom])
    }

    static let shared = AppleGeocoder()

    func reverseGeocode(location: CLLocation) async throws -> PhotoClusterLocation? {
        // attempt to use placemark
        let placemark = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale.current).first

        // If the placemark has a name that's not its address, we can use it directly
        if let placemark,
           let name = placemark.name,
           let thoroughfare = placemark.thoroughfare,
           !name.localizedCaseInsensitiveContains(thoroughfare) {
            return PhotoClusterLocation(placemark: placemark)
        }

        let searchLocation = placemark?.location ?? location
        let request = MKLocalPointsOfInterestRequest(center: searchLocation.coordinate, radius: Constants.searchRadius)
        request.pointOfInterestFilter = Constants.pointOfInterestFilter
        let localSearch = MKLocalSearch(request: request)

        let response: MKLocalSearch.Response

        do {
            response = try await localSearch.start()
        } catch {
            DDLogError("AppleGeocoder/reverseGeocodingFailed error: \(error)")
            let nsError = error as NSError
            // MapKit throws an error if there are no mapItems found - ignore the error, and return the placemark if available.
            if nsError.domain == MKErrorDomain, nsError.code == MKError.Code.placemarkNotFound.rawValue {
                return placemark.flatMap { PhotoClusterLocation(placemark: $0) }
            }
            throw error
        }

        let closestMapItem = response.mapItems.min {
            let distance0 = $0.placemark.location?.distance(from: searchLocation) ?? .greatestFiniteMagnitude
            let distance1 = $1.placemark.location?.distance(from: searchLocation) ?? .greatestFiniteMagnitude
            return distance0 < distance1
        }

        return closestMapItem.flatMap { PhotoClusterLocation(mapItem: $0) } ?? placemark.flatMap { PhotoClusterLocation(placemark: $0) }
    }
}
