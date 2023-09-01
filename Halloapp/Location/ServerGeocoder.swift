//
//  ServerGeocoder.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/25/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Contacts
import CoreCommon
import CoreLocation
import Foundation

class ServerGeocoder {

    private let service: HalloService
    private let locationCache = LocationCache()

    init(service: HalloService) {
        self.service = service
    }

    func reverseGeocode(location: CLLocation) async throws -> PhotoClusterLocation? {
        if let photoClusterLocation = await locationCache.get(location) {
            return photoClusterLocation
        }

        // Attempt to use Apple Geocoder first, as its free
        let placemark: CLPlacemark?
        do {
            placemark = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale.current).first
        } catch {
            placemark = nil
            DDLogError("ServerGeocoder/error: \(error)")
        }

        let photoClusterLocation: PhotoClusterLocation?

        // If the placemark has a name that's not its address, we can use it directly
        if let placemark,
           let name = placemark.name,
           let thoroughfare = placemark.thoroughfare,
           !name.localizedCaseInsensitiveContains(thoroughfare) {
            photoClusterLocation = PhotoClusterLocation(placemark: placemark)
        // Perform a lookup using our geocoding service
        } else if let serverLocation = try await requestLocation(location) {
            photoClusterLocation = PhotoClusterLocation(serverLocation: serverLocation)
        // fall back to placemark address
        } else if let location = placemark?.location, let city = placemark?.locality {
            let address = placemark?.postalAddress.flatMap { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress) }
            photoClusterLocation = PhotoClusterLocation(name: city, location: location, address: address)
        } else {
            photoClusterLocation = nil
        }

        // never clear cache if we don't have a location
        if let photoClusterLocation {
            await locationCache.set(photoClusterLocation, for: location)
        }

        return photoClusterLocation
    }

    private func requestLocation(_ location: CLLocation, retries: Int = 3) async throws -> Server_ReverseGeocodeLocation? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                service.reverseGeolocation(lat: location.coordinate.latitude, lng: location.coordinate.longitude) {
                    continuation.resume(with: $0)
                }
            }
        } catch RequestError.retryDelay(let delay) {
            guard retries > 0 else {
                throw RequestError.retryDelay(delay)
            }
            try await Task.sleep(nanoseconds: UInt64(delay) * NSEC_PER_SEC)
            return try await requestLocation(location, retries: retries - 1)
        } catch {
            throw error
        }
    }
}

extension ServerGeocoder {

    actor LocationCache {

        // Meters / degree at 0,0, giving us roughly meter resolution for our cache
        // This prevents floating point drift errors
        private static let coordinateNormalizationFactor = 111132.954

        private struct CacheKey: Hashable {
            let latitude: Int
            let longitude: Int

            init(_ location: CLLocation) {
                latitude = Int(location.coordinate.latitude * LocationCache.coordinateNormalizationFactor)
                longitude = Int(location.coordinate.longitude * LocationCache.coordinateNormalizationFactor)
            }
        }

        private var cache: [CacheKey: PhotoClusterLocation] = [:]

        func get(_ location: CLLocation) -> PhotoClusterLocation? {
            return cache[CacheKey(location)]
        }

        func set(_ photoClusterLocation: PhotoClusterLocation, for location: CLLocation) {
            cache[CacheKey(location)] = photoClusterLocation
        }
    }
}

extension PhotoClusterLocation {

    init(serverLocation: Server_ReverseGeocodeLocation) {
        location = CLLocation(latitude: serverLocation.location.latitude, longitude: serverLocation.location.longitude)
        if !serverLocation.name.isEmpty {
            name = serverLocation.name
        } else if !serverLocation.place.isEmpty {
            name = serverLocation.place
        } else if !serverLocation.address.isEmpty {
            name = serverLocation.address
        } else {
            name = serverLocation.name
        }
        address = serverLocation.address
    }
}
