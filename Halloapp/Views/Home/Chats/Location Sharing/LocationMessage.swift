//
//  LocationMessage.swift
//  HalloApp
//
//  Created by Cay Zhang on 8/10/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import MapKit
import Core
import Combine

struct LocationMessage {
    let description: String
    let mapSnapshot: UIImage?
    
    static func from(placemark: CLPlacemark) -> Future<LocationMessage, Never> {
        Future { promise in
            Task(priority: .userInitiated) {
                let text = description(for: ChatLocation(placemark: placemark), isGoogleMapsLinkIncluded: true)
                let image: UIImage? = await { @MainActor in
                    if let coordinate = placemark.location?.coordinate,
                       let (result, _) = try? await Self.adaptiveMapSnapshot(configuration: .init(centerCoordinate: coordinate, traitCollection: .current, size: CGSize(width: 390, height: 390)))
                    {
                        return result
                    } else {
                        return nil
                    }
                }()
                promise(.success(LocationMessage(description: text, mapSnapshot: image)))
            }
        }
    }
    
    static func description(for location: any ChatLocationProtocol, isGoogleMapsLinkIncluded: Bool) -> String {
        let address: String? = {
            let result = location.formattedAddressLines.joined(separator: "\n")
            return !result.isEmpty ? result : nil
        }()
        
        // Don't repeat address in place name.
        let name: String? = {
            guard !location.name.isEmpty else { return nil }
            guard let address = address else { return location.name }
            return address.contains(location.name) ? nil : location.name
        }()
        
        let googleMapsLink: String? = isGoogleMapsLinkIncluded ? googleMapsLink(for: location)?.absoluteString : nil
        
        return [name, address, googleMapsLink]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
    
    static func googleMapsLink(for location: any ChatLocationProtocol) -> URL? {
        var urlComponents = URLComponents(string: "https://www.google.com/maps/search/")!
        urlComponents.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(location.latitude),\(location.longitude)")]
        return urlComponents.url
    }
}

// MARK: Snapshot Rendering
extension LocationMessage {
    struct MapSnapshotConfiguration {
        var centerCoordinate: CLLocationCoordinate2D
        var traitCollection: UITraitCollection
        var size: CGSize
        
        private func modifying(_ modify: (inout Self) -> Void) -> Self {
            var copy = self
            modify(&copy)
            return copy
        }
        
        func userInterfaceStyle(_ newValue: UIUserInterfaceStyle) -> Self {
            precondition(newValue != .unspecified)
            return modifying {
                $0.traitCollection = UITraitCollection(traitsFrom: [$0.traitCollection, .init(userInterfaceStyle: newValue)])
            }
        }
    }
    
    static func adaptiveMapSnapshot(configuration: MapSnapshotConfiguration) async throws -> (snapshot: UIImage, isFromCache: Bool) {
        if let result = adaptiveMapSnapshotCache.object(forKey: adaptiveMapSnapshotCacheKey(for: configuration)) {
            return (result, true)
        } else {
            let result = try await _adaptiveMapSnapshot(configuration: configuration)
            adaptiveMapSnapshotCache.setObject(result, forKey: adaptiveMapSnapshotCacheKey(for: configuration))
            return (result, false)
        }
    }
    
    // Swift Bug: @MainActor sometimes won't call static let variables on the main thread. Used static var instead.
    @MainActor
    private static var annotationImage: UIImage = {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
        return UIGraphicsImageRenderer(bounds: bounds).image { context in
            let annotationView = MKMarkerAnnotationView(annotation: nil, reuseIdentifier: nil)
            annotationView.setSelected(true, animated: false)
            annotationView.markerTintColor = .lavaOrange
            
            // the annotation view is aligned at the bottom in its bounds
            annotationView.bounds = bounds
            _ = annotationView.drawHierarchy(
                in: annotationView.bounds,
                afterScreenUpdates: true
            )
        }
    }()
    
    private static func mapSnapshot(configuration: MapSnapshotConfiguration) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.mapType = .standard
        options.pointOfInterestFilter = .includingAll
        options.size = configuration.size
        options.camera = MKMapCamera(lookingAtCenter: configuration.centerCoordinate, fromDistance: 200, pitch: 45, heading: 0)
        options.traitCollection = configuration.traitCollection

        let snapshot = try await MKMapSnapshotter(options: options).start()
        
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        let annotationImage = await annotationImage
        return renderer.image { context in
            snapshot.image.draw(at: CGPoint.zero)

            let point = snapshot.point(for: configuration.centerCoordinate)
            annotationImage.draw(in: CGRect(
                x: point.x - annotationImage.size.width / 2.0,
                y: point.y - annotationImage.size.height,
                width: annotationImage.size.width,
                height: annotationImage.size.height
            ))
        }
    }
    
    private static func _adaptiveMapSnapshot(configuration: MapSnapshotConfiguration) async throws -> UIImage {
        let lightConfig = configuration.userInterfaceStyle(.light)
        let darkConfig = configuration.userInterfaceStyle(.dark)
        async let lightImage = mapSnapshot(configuration: lightConfig)
        async let darkImage = mapSnapshot(configuration: darkConfig)
        let adaptiveImage = UIImage()
        if let asset = adaptiveImage.imageAsset {
            asset.register(try await lightImage, with: lightConfig.traitCollection)
            asset.register(try await darkImage, with: darkConfig.traitCollection)
        }
        return adaptiveImage
    }
}

// MARK: Adaptive Map Snapshots Cache
extension LocationMessage {
    private static let adaptiveMapSnapshotCache: NSCache<NSString, UIImage> = .init()
    
    // Trait collections are ignored in the cache key.
    private static func adaptiveMapSnapshotCacheKey(for configuration: MapSnapshotConfiguration) -> NSString {
        NSString(
            format: "%.20f %.20f %.20f %.20f",
            configuration.centerCoordinate.latitude,
            configuration.centerCoordinate.longitude,
            configuration.size.width,
            configuration.size.height
        )
    }
}
