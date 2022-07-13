//
//  LocationSharingViewController.swift
//  HalloApp
//
//  Created by Cay Zhang on 6/30/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import MapKit
import CoreCommon

class LocationSharingViewController: UIViewController, UISearchControllerDelegate {
    typealias MapConfiguration = LocationSharingEnvironment.MapConfiguration
    typealias Alert = LocationSharingEnvironment.Alert
    
    init(viewModel: LocationSharingViewModel? = nil) {
        self.viewModel = viewModel ?? .init()  // to avoid "Call to main actor-isolated initializer 'init()' in a synchronous nonisolated context" warning
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private(set) var viewModel: LocationSharingViewModel
    private var cancelBag: Set<AnyCancellable> = []
    
    private lazy var mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: AnnotationReuseIdentifier.featureAnnotation.rawValue)
        mapView.showsUserLocation = true
        
#if swift(>=5.7)
        if #available(iOS 16.0, *) {
            mapView.selectableMapFeatures = [.pointsOfInterest]
        }
#endif
        
        return mapView
    }()
    
    private lazy var searchController: UISearchController = {
        let locationListViewController = LocationListViewController(viewModel: viewModel.locationList)
        let searchController = UISearchController(searchResultsController: locationListViewController)
        searchController.delegate = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.tintColor = .primaryBlue
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        return searchController
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Localizations.locationSharingNavTitle
        view.backgroundColor = .primaryBg

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: self, action: #selector(dismissPushed))
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        // Search is presenting a view controller, and needs a controller in the presented view controller hierarchy to define the presentation context.
        definesPresentationContext = true
        
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        viewModel.$userTrackingMode
            .sink { [mapView] mode in
                mapView.setUserTrackingMode(mode, animated: false)
            }
            .store(in: &cancelBag)
        
        mapView.alpha = 0
        
        viewModel.$showsMapView
            .removeDuplicates()
            .sink { [mapView] newValue in
                UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.3, delay: 0) {
                    mapView.alpha = newValue ? 1 : 0
                }
            }
            .store(in: &cancelBag)
        
        viewModel.$mapConfiguration
            .removeDuplicates()
            .sink { [mapView] config in
#if swift(>=5.7)
                if #available(iOS 16.0, *) {
                    switch config {
                    case .explore:
                        let mapConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
                        mapView.preferredConfiguration = mapConfiguration
                    case .satellite:
                        let mapConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
                        mapView.preferredConfiguration = mapConfiguration
                    }
                    return
                }
#endif
                switch config {
                case .explore:
                    mapView.mapType = .standard
                case .satellite:
                    mapView.mapType = .hybridFlyover
                }
            }
            .store(in: &cancelBag)
        
        // Right navigation bar item is dependent on location auth status and map configuration.
        Publishers.CombineLatest(viewModel.$isAuthorizedToAccessLocation, viewModel.$mapConfiguration)
            .removeDuplicates { $0 == $1 }  // Tuples can't conform to Equatable but there are == overloads for them.
            .map {
                [changeUserTrackingMode = viewModel.changeUserTrackingMode, changeMapConfiguration = viewModel.changeMapConfiguration]
                (isAuthorizedToAccessLocation: Bool, config: MapConfiguration) -> HAMenu in
                // Since our menu gets updated whenever its dependency changes, we don't need `.lazy` here :).
                HAMenu {
                    HAMenuButton(title: Localizations.locationSharingMyLocation, image: UIImage(systemName: isAuthorizedToAccessLocation ? "location.fill" : "location.slash.fill")) {
                        changeUserTrackingMode.send(.followWithHeading)
                    }
                    
                    HAMenu(title: Localizations.locationSharingChooseMap) {
                        HAMenuButton(title: Localizations.locationSharingMapTypeExplore, image: UIImage(systemName: "map.fill")) {
                            changeMapConfiguration.send(.explore)
                        }.on(config == .explore)
                        
                        HAMenuButton(title: Localizations.locationSharingMapTypeSatellite, image: UIImage(systemName: "globe")) {
                            changeMapConfiguration.send(.satellite)
                        }.on(config == .satellite)
                    }.displayInline()
                }
            }
            .map { menu in UIBarButtonItem(image: UIImage(systemName: "ellipsis")) { menu } }
            .sink { [navigationItem] barButtonItem in
                navigationItem.rightBarButtonItem = barButtonItem
            }
            .store(in: &cancelBag)
        
        viewModel.$selectedAnnotation
            .sink { [mapView] selectedAnnotation in
                if let annotation = selectedAnnotation {
                    if annotation !== mapView.selectedAnnotations.first {
                        mapView.selectAnnotation(annotation, animated: true)
                    }
                } else {
                    if !mapView.selectedAnnotations.isEmpty {
                        mapView.deselectAnnotation(nil, animated: true)
                    }
                }
            }
            .store(in: &cancelBag)
        
        viewModel.$alert
            .sink { [weak self] alert in
                guard let self = self else { return }
                if let alert = alert {
                    self.present(self.alertController(for: alert), animated: true)
                } else if self.presentedViewController is UIAlertController {
                    self.dismiss(animated: true)
                }
            }
            .store(in: &cancelBag)
    }
    
    private func alertController(for alert: Alert) -> UIAlertController {
        switch alert {
        case .locationAccessRequired:
            let result = UIAlertController(title: Localizations.locationSharingLocationAccessRequiredAlertTitle, message: Localizations.locationSharingLocationAccessRequiredAlertMessage, preferredStyle: .alert)
            let notNowAction = UIAlertAction(title: Localizations.buttonNotNow, style: .default) { [alertDismissed = viewModel.alertDismissed] _ in
                alertDismissed.send()
            }
            result.addAction(notNowAction)
            result.addAction(.init(title: Localizations.buttonGoToSettings, style: .default) {
                [openAppSettings = viewModel.openAppSettings, alertDismissed = viewModel.alertDismissed] _ in
                
                openAppSettings.send()
                alertDismissed.send()
            })
            result.preferredAction = notNowAction
            return result
        case .localSearchFailed:
            let result = UIAlertController(title: Localizations.locationSharingLocalSearchFailedAlertTitle, message: Localizations.locationSharingGeneralErrorMessage, preferredStyle: .alert)
            result.addAction(.init(title: Localizations.buttonOK, style: .default) { [alertDismissed = viewModel.alertDismissed] _ in
                alertDismissed.send()
            })
            return result
        case .locationResolvingFailed:
            let result = UIAlertController(title: Localizations.locationSharingLocationResolvingFailedAlertTitle, message: Localizations.locationSharingGeneralErrorMessage, preferredStyle: .alert)
            result.addAction(.init(title: Localizations.buttonOK, style: .default) { [alertDismissed = viewModel.alertDismissed] _ in
                alertDismissed.send()
            })
            return result
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.onAppear.send()
    }
    
    @objc
    private func dismissPushed(_ sender: UIButton) {
        dismiss(animated: true)
    }
}

extension LocationSharingViewController {
    private enum AnnotationReuseIdentifier: String {
        case featureAnnotation
    }
}

extension LocationSharingViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        if let searchText = searchController.searchBar.text, !searchText.isEmpty {
            viewModel.searchTextChanged.send(searchText)
        }
    }
}

extension LocationSharingViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        viewModel.userLocationUpdated.send(userLocation)
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        viewModel.mapRegionChanged.send(mapView.region)
    }
    
    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        viewModel.mapViewLoaded.send()
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
#if swift(>=5.7)
        if #available(iOS 16.0, *), let annotation = annotation as? MKMapFeatureAnnotation {
            return mapFeatureAnnotationView(for: annotation)
        }
#endif
        return nil
    }
    
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        if let userLocationView = views.first(where: { $0.annotation is MKUserLocation }) {
            userLocationView.canShowCallout = true
            
            let shareButton = UIButton(type: .system)
            shareButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
            shareButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            userLocationView.rightCalloutAccessoryView = shareButton
            
            if let horizontalAccuracy = mapView.userLocation.location?.horizontalAccuracy {
                let subtitleLabel = UILabel()
                subtitleLabel.adjustsFontForContentSizeCategory = true
                subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
                subtitleLabel.textColor = .secondaryLabel
                subtitleLabel.text = Localizations.locationSharingLocationAccuracy(horizontalAccuracy)
                userLocationView.detailCalloutAccessoryView = subtitleLabel
            }
            
            viewModel.userLocationViewAdded.send()
        }
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        view.annotation.map { viewModel.shareLocationWithAnnotation.send($0) }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        viewModel.annotationSelectionChanged.send(annotation)
    }
    
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        viewModel.annotationSelectionChanged.send(nil)
    }
    
#if swift(>=5.7)
    @available(iOS 16.0, *)
    private func mapFeatureAnnotationView(for annotation: MKMapFeatureAnnotation) -> MKMarkerAnnotationView? {
        guard let markerAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: AnnotationReuseIdentifier.featureAnnotation.rawValue, for: annotation) as? MKMarkerAnnotationView else {
            return nil
        }
        
        markerAnnotationView.animatesWhenAdded = true
        markerAnnotationView.canShowCallout = true
        
        let shareButton = UIButton(type: .system)
        shareButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        shareButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        markerAnnotationView.rightCalloutAccessoryView = shareButton
        
        if let iconStyle = annotation.iconStyle {
            let imageView = UIImageView(image: iconStyle.image.withTintColor(iconStyle.backgroundColor, renderingMode: .alwaysOriginal))
            imageView.bounds = CGRect(origin: .zero, size: CGSize(width: 44, height: 44))
            markerAnnotationView.leftCalloutAccessoryView = imageView
            
            shareButton.tintColor = iconStyle.backgroundColor
            markerAnnotationView.markerTintColor = iconStyle.backgroundColor
        }
        
        return markerAnnotationView
    }
#endif
}
