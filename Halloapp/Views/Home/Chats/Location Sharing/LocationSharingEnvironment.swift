//
//  LocationSharingEnvironment.swift
//  HalloApp
//
//  Created by Cay Zhang on 7/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import CoreLocation
import Combine
import MapKit
import Contacts

struct LocationSharingEnvironment {
    var locationManager: LocationManager
    
    static var `default`: Self = .init(locationManager: .shared)
    
    func performLocalSearch(for queryString: String?, around region: MKCoordinateRegion) -> Future<[MKMapItem], Error> {
        Future {
            let searchRequest = MKLocalSearch.Request()
            searchRequest.pointOfInterestFilter = MKPointOfInterestFilter.includingAll
            searchRequest.naturalLanguageQuery = queryString
            searchRequest.region = region
            searchRequest.resultTypes = [.address, .pointOfInterest]
            
            let localSearch = MKLocalSearch(request: searchRequest)
            return try await localSearch.start().mapItems
        }
    }
    
    func placemark(from annotation: any MKAnnotation) -> Future<CLPlacemark?, Error> {
#if swift(>=5.7)
        if #available(iOS 16, *), let mapFeatureAnnotation = annotation as? MKMapFeatureAnnotation {
            return placemark(from: mapFeatureAnnotation)
        }
#endif
        if let userLocation = annotation as? MKUserLocation, let location = userLocation.location {
            return placemark(from: location)
        } else if let longPressAnnotation = annotation as? LongPressAnnotation {
            return placemark(from: CLLocation(latitude: longPressAnnotation.coordinate.latitude, longitude: longPressAnnotation.coordinate.longitude))
        } else {
            return Future { promise in
                promise(.success(nil))
            }
        }
    }
    
#if swift(>=5.7)
    @available(iOS 16, *)
    private func placemark(from mapFeatureAnnotation: MKMapFeatureAnnotation) -> Future<CLPlacemark?, Error> {
        Future {
            /*
             An `MKMapFeatureAnnotation` only has limited information about the point of interest, such as the `title` and `coordinate`
             properties. To get additional information, use `MKMapItemRequest` to get an `MKMapItem`.
             */
            let request = MKMapItemRequest(mapFeatureAnnotation: mapFeatureAnnotation)
            return try await request.mapItem.placemark
        }
    }
#endif
    
    private func placemark(from location: CLLocation) -> Future<CLPlacemark?, Error> {
        Future {
            try await CLGeocoder().reverseGeocodeLocation(location).first
        }
    }
    
    @discardableResult @MainActor @Sendable
    func openAppSettings() async -> Bool {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            return await UIApplication.shared.open(url)
        } else {
            return false
        }
    }
    
    var onAppEnterForeground: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

extension LocationSharingEnvironment {
    enum MapConfiguration {
        case explore
        case satellite
    }
}

extension LocationSharingEnvironment {
    enum Alert {
        case locationAccessRequired
        case localSearchFailed
        case locationResolvingFailed
    }
}

extension LocationSharingEnvironment {
    final class LongPressAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        var title: String? = Localizations.locationSharingSelectedLocation
        
        init(coordinate: CLLocationCoordinate2D) {
            self.coordinate = coordinate
            super.init()
        }
    }
}

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    private let errorSubject: PassthroughSubject<Error, Never> = .init()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    
    var errors: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    override init() {
        authorizationStatus = Self.authorizationStatus(of: locationManager)
        super.init()
        locationManager.delegate = self
    }

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    private static func authorizationStatus(of clLocationManager: CLLocationManager) -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return clLocationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorSubject.send(error)
    }
}

struct LocationMessage {
    let text: String
    let image: UIImage?
    
    static func from(placemark: CLPlacemark) -> Future<LocationMessage, Never> {
        Future { promise in
            Task(priority: .userInitiated) {
                let text = text(from: placemark)
                let image = try? await image(from: placemark)
                promise(.success(LocationMessage(text: text, image: image)))
            }
        }
    }
    
    private static func text(from placemark: CLPlacemark) -> String {
        let address = placemark.postalAddress.map { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress) }
        
        // Don't repeat address in place name.
        let name: String? = {
            guard let name = placemark.name else { return nil }
            guard let address = address else { return name }
            return address.contains(name) ? nil : name
        }()
        
        let googleMapsLink = placemark.location
            .map(\.coordinate)
            .flatMap { (coordinate: CLLocationCoordinate2D) -> String? in
                var url = URLComponents(string: "https://www.google.com/maps/search/")!
                url.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(coordinate.latitude),\(coordinate.longitude)")]
                return url.string
            }
        
        return [name, address, googleMapsLink]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
    
    @MainActor
    private static func image(from placemark: CLPlacemark) async throws -> UIImage? {
        guard let coordinate = placemark.location?.coordinate else { return nil }
        
        let options = MKMapSnapshotter.Options()
        options.mapType = .standard
        options.pointOfInterestFilter = .includingAll
        options.size = CGSize(width: 390, height: 390)
        options.camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 200, pitch: 45, heading: 0)
        options.traitCollection = UIScreen.main.traitCollection

        let snapshot = try await MKMapSnapshotter(options: options).start()
        
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: CGPoint.zero)

            let annotation = MKPlacemark(coordinate: coordinate)
            let point = snapshot.point(for: annotation.coordinate)
            let annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            annotationView.setSelected(true, animated: false)
            annotationView.markerTintColor = .lavaOrange
            
            // the annotation view is aligned at the bottom in its bounds
            annotationView.bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
            annotationView.drawHierarchy(
                in: CGRect(
                    x: point.x - annotationView.bounds.size.width / 2.0,
                    y: point.y - annotationView.bounds.size.height,
                    width: annotationView.bounds.width,
                    height: annotationView.bounds.height
                ),
                afterScreenUpdates: true
            )
        }
    }
}

extension Localizations {
    static var locationSharingNavTitle: String {
        NSLocalizedString("locationSharing.navTitle", value: "Location", comment: "Title of the location sharing main screen.")
    }
    
    static var locationSharingMyLocation: String {
        NSLocalizedString("locationSharing.myLocation", value: "My Location", comment: "The menu action to focus on user location.")
    }
    
    static var locationSharingChooseMap: String {
        NSLocalizedString("locationSharing.chooseMap", value: "Choose Map", comment: "Title of the menu to choose map type.")
    }
    
    static var locationSharingMapTypeExplore: String {
        NSLocalizedString("locationSharing.mapType.explore", value: "Explore", comment: "The explore map type (as in Apple Maps).")
    }
    
    static var locationSharingMapTypeSatellite: String {
        NSLocalizedString("locationSharing.mapType.satellite", value: "Satellite", comment: "The satellite map type (as in Apple Maps).")
    }
    
    static var locationSharingLocationAccessRequiredAlertTitle: String {
        NSLocalizedString("locationSharing.alert.locationAccessRequired.title", value: "HalloApp requires access to your location for this feature.", comment: "Title of the alert requesting location access for a feature.")
    }
    
    static var locationSharingLocationAccessRequiredAlertMessage: String {
        NSLocalizedString("locationSharing.alert.locationAccessRequired.message", value: "You can enable this permission in Settings.", comment: "Message of the alert requesting location access for a feature.")
    }
    
    static var locationSharingLocalSearchFailedAlertTitle: String {
        NSLocalizedString("locationSharing.alert.localSearchFailed.title", value: "Location search failed", comment: "Title of the alert for failures in location searches.")
    }
    
    static var locationSharingLocationResolvingFailedAlertTitle: String {
        NSLocalizedString("locationSharing.alert.locationResolvingFailed.title", value: "Could not resolve location", comment: "Title of the alert for failures resolving a location from the map.")
    }
    
    static var locationSharingGeneralErrorMessage: String {
        NSLocalizedString("locationSharing.alert.error", value: "Something went wrong. Please try again later.", comment: "General message of the alert for failures in location sharing features.")
    }
    
    static func locationSharingLocationAccuracy(_ accuracy: CLLocationAccuracy) -> String {
        let measurement = Measurement(value: accuracy, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.numberFormatter.roundingMode = .ceiling
        formatter.unitStyle = .medium
        formatter.unitOptions = .naturalScale
        let format = NSLocalizedString("locationSharing.locationAccuracyDescription", value: "Accurate to %@", comment: "Subtitle of the user location callout. Parameter is the formatted length measurement of accuracy (including unit).")
        return String(format: format, formatter.string(from: measurement))
    }
    
    static var locationSharingUntitledLocation: String {
        NSLocalizedString("locationSharing.untitledLocation", value: "Untitled Location", comment: "Title of a location in location list if it does not have a name.")
    }
    
    static var locationSharingSelectedLocation: String {
        NSLocalizedString("locationSharing.selectedLocation", value: "Selected Location", comment: "Initial title of the callout bubble for locations selected by long pressing on the map.")
    }
    
    static func locationSharingDetailedAddress(for address: CNPostalAddress) -> String? {
        let arguments: [String] = [!address.street.isEmpty ? address.street : nil, !address.city.isEmpty ? address.city : nil]
            .compactMap { $0 }
        if arguments.count == 2 {
            let format = NSLocalizedString("locationSharing.detailedAddress", value: "%@, %@", comment: "Addresses displayed as subtitles in location list. Parameters are non-empty street address and city.")
            return String(format: format, arguments: arguments)
        } else if arguments.count == 1 {
            return arguments[0]
        } else {
            return nil
        }
    }
}
