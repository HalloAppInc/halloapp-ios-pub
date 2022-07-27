//
//  LocationSharingViewModel.swift
//  HalloApp
//
//  Created by Cay Zhang on 7/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import MapKit
import Combine
import CocoaLumberjackSwift

@MainActor
class LocationSharingViewModel: ObservableObject {
    typealias MapConfiguration = LocationSharingEnvironment.MapConfiguration
    typealias Alert = LocationSharingEnvironment.Alert
    typealias LongPressAnnotation = LocationSharingEnvironment.LongPressAnnotation
    
    var environment: LocationSharingEnvironment = .default
    
    var cancelBag: Set<AnyCancellable> = []
    
    var locationList: LocationListViewModel = .init()
    var bottomBar: BottomBarViewModel = .init()
    
    // MARK: States
    @Published var isAuthorizedToAccessLocation: Bool = false
    @Published var userLocation: MKUserLocation = .init()
    @Published var userTrackingMode: MKUserTrackingMode = .none
    @Published var showsMapView: Bool = false
    @Published var showsLocationListView: Bool = false
    @Published var mapConfiguration: MapConfiguration = .explore
    @Published var mapRegion: MKCoordinateRegion = .init()
    @Published var selectedAnnotation: (any MKAnnotation)? = nil
    @Published var longPressAnnotation: LongPressAnnotation? = nil  // No more than one long press annotations on the map.
    @Published var alert: Alert? = nil
    
    // MARK: Actions
    var onAppear: PassthroughSubject<Void, Never> = .init()
    var userLocationUpdated: PassthroughSubject<MKUserLocation, Never> = .init()
    var userTrackingModeChanged: PassthroughSubject<MKUserTrackingMode, Never> = .init()
    var userTrackingButtonTapped: PassthroughSubject<Void, Never> = .init()
    var mapViewLoaded: PassthroughSubject<Void, Never> = .init()
    var mapRegionChanged: PassthroughSubject<MKCoordinateRegion, Never> = .init()
    var changeMapConfiguration: PassthroughSubject<MapConfiguration, Never> = .init()
    var shareLocationWithAnnotation: PassthroughSubject<any MKAnnotation, Never> = .init()
    var sharePlacemark: PassthroughSubject<CLPlacemark, Never> = .init()
    var annotationSelectionChanged: PassthroughSubject<(any MKAnnotation)?, Never> = .init()
    var userLocationViewAdded: PassthroughSubject<Void, Never> = .init()
    var openAppSettings: PassthroughSubject<Void, Never> = .init()
    var showAlert: PassthroughSubject<Alert, Never> = .init()
    var alertDismissed: PassthroughSubject<Void, Never> = .init()
    var longPressedAtCoordinate: PassthroughSubject<CLLocationCoordinate2D, Never> = .init()
    
    init() {
        setupReducer()
    }
    
    private func setupReducer() {
        environment.locationManager.$authorizationStatus
            .map { (status: CLAuthorizationStatus) -> Bool in
                switch status {
                case .authorizedAlways, .authorizedWhenInUse:
                    return true
                default:
                    return false
                }
            }
            .assign(to: \.isAuthorizedToAccessLocation, onWeak: self)
            .store(in: &cancelBag)
        
        onAppear
            .first()
            .merge(with: environment.onAppEnterForeground)
            .sink { [environment] in
                environment.locationManager.requestWhenInUseAuthorization()
            }
            .store(in: &cancelBag)
        
        userLocationUpdated
            .assign(to: \.userLocation, onWeak: self)
            .store(in: &cancelBag)
        
        userLocationUpdated
            .first()
            .map { _ in MKUserTrackingMode.followWithHeading }
            .assign(to: \.userTrackingMode, onWeak: self)
            .store(in: &cancelBag)
        
        userTrackingModeChanged
            .assign(to: \.userTrackingMode, onWeak: self)
            .store(in: &cancelBag)
        
        userTrackingButtonTapped
            .compactMap { [weak self] in self?.userTrackingMode }
            .map { ($0 != .none) ? MKUserTrackingMode.none : .followWithHeading }
            .sink { [weak self] newMode in
                guard let self = self else { return }
                guard self.isAuthorizedToAccessLocation else {
                    self.alert = .locationAccessRequired
                    return
                }
                
                self.userTrackingMode = newMode
                
                // Select/Deselect user location based on new tracking mode.
                if newMode != .none {
                    self.selectedAnnotation = self.userLocation
                } else if self.selectedAnnotation === self.userLocation {
                    self.selectedAnnotation = nil
                }
            }
            .store(in: &cancelBag)
        
        // Show the map view when it finishes loading for the first time after the user location has been determined,
        // with a timeout of 1 second.
        mapViewLoaded
            .filter { [weak self] _ in self?.userLocation.coordinate != nil }
            .first()
            .map { _ in true }
            .assign(to: \.showsMapView, onWeak: self)
            .store(in: &cancelBag)
        
        onAppear
            .delay(for: 1, scheduler: RunLoop.main)
            .map { _ in true }
            .assign(to: \.showsMapView, onWeak: self)
            .store(in: &cancelBag)
        
        mapRegionChanged
            .assign(to: \.mapRegion, onWeak: self)
            .store(in: &cancelBag)
        
        changeMapConfiguration
            .assign(to: \.mapConfiguration, onWeak: self)
            .store(in: &cancelBag)
        
        shareLocationWithAnnotation
            .flatMap { [environment] annotation in environment.placemark(from: annotation).mapToResult() }
            .receive(on: DispatchQueue.main)
            .sink { [sharePlacemark, showAlert] (result: Result<CLPlacemark?, any Error>) in
                switch result {
                case let .success(placemark):
                    placemark.map(sharePlacemark.send)
                case let .failure(error):
                    DDLogError("LocationSharingViewModel/resolvePlacemarkFromAnnotation/error: \(error)")
                    showAlert.send(.locationResolvingFailed)
                }
            }
            .store(in: &cancelBag)
        
        shareLocationWithAnnotation
            .map { _ in Optional<any MKAnnotation>.none }
            .assign(to: \.selectedAnnotation, onWeak: self)
            .store(in: &cancelBag)
        
        locationList.locationSelected
            .map(\.placemark)
            .sink { [sharePlacemark] placemark in
                sharePlacemark.send(placemark)
            }
            .store(in: &cancelBag)
        
        sharePlacemark
            .sink { placemark in
                DDLogInfo("LocationSharingViewModel/sharePlacemark: \(placemark)")
            }
            .store(in: &cancelBag)
        
        annotationSelectionChanged
            .assign(to: \.selectedAnnotation, onWeak: self)
            .store(in: &cancelBag)
        
        Publishers.CombineLatest(userLocationViewAdded, userLocationUpdated)
            .first()
            .map { $1 as (any MKAnnotation)? }
            .assign(to: \.selectedAnnotation, onWeak: self)
            .store(in: &cancelBag)
        
        openAppSettings
            .sink { [environment] in
                Task(operation: environment.openAppSettings)
            }
            .store(in: &cancelBag)
        
        showAlert
            .map(Optional.some)  // convert to Optional
            .assign(to: \.alert, onWeak: self)
            .store(in: &cancelBag)
        
        alertDismissed
            .map { nil }
            .assign(to: \.alert, onWeak: self)
            .store(in: &cancelBag)
        
        longPressedAtCoordinate
            .map(LongPressAnnotation.init(coordinate:))
            .sink { [weak self] annotation in
                self?.longPressAnnotation = annotation
                self?.selectedAnnotation = annotation
            }
            .store(in: &cancelBag)
        
        // MARK: Search
        bottomBar.searchTextChanged
            .map { !$0.isEmpty }
            .assign(to: \.showsLocationListView, onWeak: self)
            .store(in: &cancelBag)
        
        bottomBar.searchTextChanged
            .debounce(for: 0.3, scheduler: RunLoop.main)
            .map { [weak self, environment] (searchText: String) -> AnyPublisher<Result<[MKMapItem], Error>, Never> in
                if let region = self?.mapRegion, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return environment.performLocalSearch(for: searchText, around: region)
                        .mapToResult()
                        .eraseToAnyPublisher()
                } else {
                    return Just(.success([])).eraseToAnyPublisher()
                }
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [updateLocations = locationList.updateLocations, showAlert] (result: Result<[MKMapItem], any Error>) in
                switch result {
                case let .success(locations):
                    updateLocations.send(locations)
                case let .failure(error):
                    DDLogError("LocationSharingViewModel/performLocalSearchFromSearchText/error: \(error)")
                    showAlert.send(.localSearchFailed)
                }
            }
            .store(in: &cancelBag)
    }
}

extension LocationSharingViewModel {
    @MainActor
    class BottomBarViewModel: ObservableObject {
        var cancelBag: Set<AnyCancellable> = []
        
        // MARK: Actions
        var searchTextChanged: PassthroughSubject<String, Never> = .init()
    }
}
