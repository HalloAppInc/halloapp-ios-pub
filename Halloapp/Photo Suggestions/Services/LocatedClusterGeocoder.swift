//
//  LocatedClusterGeocoder.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/27/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import Foundation

/*
 Given a located cluster, geocode its latitude / longitude and save results
 */
class LocatedClusterGeocoder {

    enum LocatedClusterGeocoderError: Error {
        case locatedClusterNotFound
    }

    private class func geocodeClusterLocation(locatedClusterID: String, with photoSuggestionsData: PhotoSuggestionsData, geocoder: ServerGeocoder) async throws {
        DDLogInfo("LocatedClusterGeocoder/geocodeClusterLocation/geocoding located cluster \(locatedClusterID)")

        let location = try await photoSuggestionsData.performOnBackgroundContext { context in
            guard let locatedCluster = AssetLocatedCluster.find(id: locatedClusterID, in: context) else {
                DDLogError("LocatedClusterGeocoder/geocodeClusterLocation/could not find located cluster with id \(locatedClusterID)")
                throw LocatedClusterGeocoderError.locatedClusterNotFound
            }

            return locatedCluster.location
        }

        guard let location else {
            DDLogInfo("LocatedClusterGeocoder/geocodeClusterLocation/located cluster \(locatedClusterID) has no location")
            try await photoSuggestionsData.saveOnBackgroundContext { context in
                guard let locatedCluster = AssetLocatedCluster.find(id: locatedClusterID, in: context) else {
                    DDLogError("LocatedClusterGeocoder/geocodeClusterLocation/could not find located cluster with id \(locatedClusterID)")
                    throw LocatedClusterGeocoderError.locatedClusterNotFound
                }

                locatedCluster.locationStatus = .noLocation
            }
            return
        }

        var photoClusterLocation: PhotoClusterLocation? = nil
        var didComplete = false
        var retries = 3
        while retries > 0, !didComplete {
            do {
                photoClusterLocation = try await geocoder.reverseGeocode(location: location)
                didComplete = true
            } catch RequestError.retryDelay(let delay) {
                try? await Task.sleep(nanoseconds: UInt64(delay) * NSEC_PER_SEC)
                retries -= 1
            } catch {
                retries -= 1
            }
        }

        try await photoSuggestionsData.saveOnBackgroundContext { [photoClusterLocation, didComplete] context in
            guard let locatedCluster = AssetLocatedCluster.find(id: locatedClusterID, in: context) else {
                DDLogError("LocatedClusterGeocoder/geocodeClusterLocation/could not find located cluster with id \(locatedClusterID)")
                throw LocatedClusterGeocoderError.locatedClusterNotFound
            }

            guard let previousClusterLocation = locatedCluster.location,
                      location.distance(from: previousClusterLocation) <= PhotoSuggestionsUtilities.Constants.locationInvalidationDistance else {
                DDLogError("LocatedClusterGeocoder/geocodeClusterLocation/Location has moved from resolved location - ignoring result for \(locatedClusterID)")
                return
            }

            locatedCluster.geocodedAddress = photoClusterLocation?.address
            locatedCluster.geocodedLocation = photoClusterLocation?.location
            locatedCluster.geocodedLocationName = photoClusterLocation?.name
            locatedCluster.lastGeocodeDate = Date()

            locatedCluster.locationStatus = didComplete ? .located : .failed
        }

        DDLogInfo("LocatedClusterGeocoder/geocodeClusterLocation/completed geocoding for \(locatedClusterID)")
    }
}

extension LocatedClusterGeocoder {

    class func makeService(photoSuggestionsData: PhotoSuggestionsData, service: HalloService) -> PhotoSuggestionsService {
        let geocoder = ServerGeocoder(service: service)

        return PhotoSuggestionsSerialService {
            let fetchRequest = AssetLocatedCluster.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %ld", #keyPath(AssetLocatedCluster.rawLocationStatus), AssetLocatedCluster.LocationStatus.pending.rawValue),

                // TODO: remove 90 day limit on geocode lookups after testing
                NSPredicate(format: "%K >= %@", #keyPath(AssetLocatedCluster.startDate), Date(timeIntervalSinceNow: -90 * 24 * 60 * 60) as NSDate),
            ])
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \AssetLocatedCluster.startDate, ascending: false),
            ]
            return PhotoSuggestionsFetchedResultsControllerAsyncSequence(fetchRequest: fetchRequest, photoSuggestionsData: photoSuggestionsData)
        } task: {
            try? await Self.geocodeClusterLocation(locatedClusterID: $0, with: photoSuggestionsData, geocoder: geocoder)
        }

    }
}
