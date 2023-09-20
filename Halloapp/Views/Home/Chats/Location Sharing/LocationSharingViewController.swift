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

class LocationSharingViewController: UIViewController {
    typealias MapConfiguration = LocationSharingEnvironment.MapConfiguration
    typealias Alert = LocationSharingEnvironment.Alert
    typealias LongPressAnnotation = LocationSharingEnvironment.LongPressAnnotation
    
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
        mapView.register(AnnotationView.self, forAnnotationViewWithReuseIdentifier: AnnotationReuseIdentifier.featureAnnotation.rawValue)
        mapView.showsUserLocation = true
        
#if swift(>=5.7)
        if #available(iOS 16.0, *) {
            mapView.selectableMapFeatures = [.pointsOfInterest]
        }
#endif
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress))
        longPressGestureRecognizer.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPressGestureRecognizer)
        
        return mapView
    }()
    
    private lazy var bottomBar: BottomBar = {
        let bar = BottomBar(viewModel: viewModel.bottomBar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()
    
    private lazy var userTrackingButton: UIButton = {
        var userTrackingButtonConfiguration: UIButton.Configuration = .filled()
        userTrackingButtonConfiguration.background.strokeColor = .lightGray.withAlphaComponent(0.5)
        userTrackingButtonConfiguration.background.strokeWidth = 1.0 / UIScreen.main.scale
        userTrackingButtonConfiguration.baseBackgroundColor = .secondarySystemGroupedBackground
        userTrackingButtonConfiguration.baseForegroundColor = UIColor(white: 0.2, alpha: 1.0)
        userTrackingButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 12, bottom: 11, trailing: 12)
        userTrackingButtonConfiguration.cornerStyle = .capsule
        userTrackingButtonConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17)

        let button = UIButton(type: .system)
        button.configuration = userTrackingButtonConfiguration
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 20
        button.layer.shadowOffset = CGSize(width: 0, height: 10)
        button.layer.shadowOpacity = 0.2
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(userTrackingButtonTapped), for: .touchUpInside)

        return button
    }()

    // Safe area will be insetted to include bottom bar's height, so we constrain top of the bar to bottom of safe area.
    private lazy var bottomBarTopConstraint: NSLayoutConstraint = bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 8)
    
    private lazy var locationListViewController = LocationListViewController(viewModel: viewModel.locationList)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Localizations.locationSharingNavTitle
        view.backgroundColor = .primaryBg

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: self, action: #selector(dismissPushed))
        
        view.addSubview(mapView)
        view.addSubview(userTrackingButton)
        
        locationListViewController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(locationListViewController)
        view.addSubview(locationListViewController.view)
        
        view.addSubview(bottomBar)
        
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            locationListViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            locationListViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            locationListViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            locationListViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            bottomBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bottomBar.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            bottomBarTopConstraint,
            bottomBar.heightAnchor.constraint(equalToConstant: 48),
            
            userTrackingButton.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),
            userTrackingButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        ])
        
        locationListViewController.didMove(toParent: self)
        
        setupKeyboardAvoidance()
        preventSheetAutoResizingAfterKeyboardDidShow()
        
        viewModel.$userTrackingMode
            .sink { [mapView] mode in
                mapView.setUserTrackingMode(mode, animated: false)
            }
            .store(in: &cancelBag)
        
        Publishers.CombineLatest(viewModel.$isAuthorizedToAccessLocation, viewModel.$userTrackingMode)
            .removeDuplicates { $0 == $1 }
            .sink { [userTrackingButton] (isAuthorizedToAccessLocation: Bool, mode: MKUserTrackingMode) in
                if !isAuthorizedToAccessLocation {
                    userTrackingButton.setImage(UIImage(systemName: "location.slash"), for: .normal)
                } else if mode != .none {
                    userTrackingButton.setImage(UIImage(systemName: "location.fill"), for: .normal)
                } else {
                    userTrackingButton.setImage(UIImage(systemName: "location"), for: .normal)
                }
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
        
        locationListViewController.view.alpha = 0
        
        viewModel.$showsLocationListView
            .removeDuplicates()
            .sink { [locationListView = locationListViewController.view!] newValue in
                let timing = UISpringTimingParameters(dampingFraction: 1, response: 0.25)
                let animator = UIViewPropertyAnimator(duration: -1, timingParameters: timing)
                animator.addAnimations {
                    locationListView.alpha = newValue ? 1 : 0
                    locationListView.transform = newValue ? .identity : .init(scaleX: 0.8, y: 0.8)
                }
                animator.startAnimation()
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
        
        // Right navigation bar item is dependent on map configuration.
        viewModel.$mapConfiguration
            .removeDuplicates()
            .map { [changeMapConfiguration = viewModel.changeMapConfiguration] (config: MapConfiguration) -> HAMenu in
                // Since our menu gets updated whenever its dependency changes, we don't need `.lazy` here :).
                HAMenu {
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
        
        viewModel.$longPressAnnotation
            .removeDuplicates()
            .sink { [mapView, viewModel] newValue in
                // This is called on `willSet` so we are guaranteed to get the old value.
                if let oldValue = viewModel.longPressAnnotation {
                    mapView.removeAnnotation(oldValue)
                }
                if let newValue = newValue {
                    mapView.addAnnotation(newValue)
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
    
    private func setupKeyboardAvoidance() {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let self = self, let info = notification.userInfo else { return }
                UIViewPropertyAnimator(keyboardNotificationInfo: info) { keyboardEndFrame in
                    let additionalInset = keyboardEndFrame.height - self.view.safeAreaInsets.bottom
                    self.bottomBarTopConstraint.constant = -additionalInset - 8 - self.bottomBar.frame.height
                    self.locationListViewController.collectionView.contentInset.bottom = additionalInset
                    self.locationListViewController.collectionView.verticalScrollIndicatorInsets.bottom = additionalInset
                    self.view.layoutIfNeeded()
                }?.startAnimation()
            }
            .store(in: &cancelBag)

        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                guard let self = self, let info = notification.userInfo else { return }
                UIViewPropertyAnimator(keyboardNotificationInfo: info) { _ in
                    self.bottomBarTopConstraint.constant = 8
                    self.locationListViewController.collectionView.contentInset.bottom = 0
                    self.locationListViewController.collectionView.verticalScrollIndicatorInsets.bottom = 0
                    self.view.layoutIfNeeded()
                }?.startAnimation()
            }
            .store(in: &cancelBag)
    }
    
    private func preventSheetAutoResizingAfterKeyboardDidShow() {
        if let sheet = navigationController?.sheetPresentationController ?? sheetPresentationController {
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardDidShowNotification)
                .first()
                .sink { notification in
                    if sheet.detents.contains(.large()) {
                        sheet.selectedDetentIdentifier = .large
                    }
                }
                .store(in: &cancelBag)
        }
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        userTrackingButton.layer.shadowPath = UIBezierPath(roundedRect: userTrackingButton.bounds, cornerRadius: userTrackingButton.bounds.height / 2).cgPath
        self.additionalSafeAreaInsets.bottom = bottomBar.frame.height + 16
    }
    
    @objc
    private func userTrackingButtonTapped() {
        viewModel.userTrackingButtonTapped.send()
    }
    
    @objc
    private func dismissPushed(_ sender: UIButton) {
        dismiss(animated: true)
    }
    
    @objc
    private func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            let coordinate = mapView.convert(gestureRecognizer.location(in: mapView), toCoordinateFrom: mapView)
            viewModel.longPressedAtCoordinate.send(coordinate)
        }
    }
}

extension LocationSharingViewController {
    private enum AnnotationReuseIdentifier: String {
        case featureAnnotation
    }
}

extension LocationSharingViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        viewModel.userLocationUpdated.send(userLocation)
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        viewModel.mapRegionChanged.send(mapView.region)
    }
    
    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        viewModel.userTrackingModeChanged.send(mapView.userTrackingMode)
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
        if let longPressAnnotation = annotation as? LongPressAnnotation {
            return annotationView(for: longPressAnnotation)
        } else {
            return nil
        }
    }
    
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        if let userLocationView = views.first(where: { $0.annotation is MKUserLocation }) {
            userLocationView.tintColor = .systemBlue
            userLocationView.canShowCallout = true
            
            let shareButton = AnnotationView.shareButton()
            shareButton.tintColor = .primaryBlue
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
        guard let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: AnnotationReuseIdentifier.featureAnnotation.rawValue, for: annotation) as? AnnotationView else {
            return nil
        }
        
        annotationView.bind(to: LocationSharingViewModel.AnnotationViewModel(mapFeatureAnnotation: annotation))
        
        return annotationView
    }
#endif
    
    private func annotationView(for longPressAnnotation: LongPressAnnotation) -> MKMarkerAnnotationView? {
        guard let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: AnnotationReuseIdentifier.featureAnnotation.rawValue, for: longPressAnnotation) as? AnnotationView else {
            return nil
        }
        
        annotationView.bind(to: LocationSharingViewModel.AnnotationViewModel(longPressAnnotation: longPressAnnotation))
        
        return annotationView
    }
}

extension LocationSharingViewController {
    private class BottomBar: UIView, UITextFieldDelegate, UISearchTextFieldDelegate {
        typealias ViewModel = LocationSharingViewModel.BottomBarViewModel
        
        private(set) var viewModel: ViewModel
        private var cancelBag: Set<AnyCancellable> = []
        
        private lazy var searchTextField: UISearchTextField = {
            let textField = UISearchTextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.delegate = self
            textField.borderStyle = .none
            textField.attributedPlaceholder = NSAttributedString(string: Localizations.labelSearch, attributes: [.foregroundColor: UIColor.placeholder])
            textField.font = .preferredFont(forTextStyle: .callout)
            textField.textContentType = .location
            textField.returnKeyType = .search
            textField.clearButtonMode = .always
            
            textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
            
            return textField
        }()
        
        init(viewModel: ViewModel? = nil) {
            self.viewModel = viewModel ?? .init()
            super.init(frame: .zero)
            commonInit()
        }
        
        required init?(coder: NSCoder) {
            self.viewModel = .init()
            super.init(coder: coder)
            commonInit()
        }
        
        private func commonInit() {
            directionalLayoutMargins = .init(top: 10, leading: 10, bottom: 10, trailing: 10)
            addSubview(searchTextField)
            NSLayoutConstraint.activate([
                searchTextField.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                searchTextField.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                searchTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            
            backgroundColor = .secondarySystemGroupedBackground
            layer.cornerRadius = 16
            layer.cornerCurve = .continuous
            layer.borderColor = UIColor.lightGray.withAlphaComponent(0.5).cgColor
            layer.borderWidth = 1.0 / UIScreen.main.scale
            layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
            layer.shadowRadius = 3
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowOpacity = 1
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        }
        
        @objc
        private func textFieldEditingChanged(_ textField: UITextField) {
            viewModel.searchTextChanged.send(searchTextField.text ?? "")
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
        
        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            // Clear text manually to avoid automatically starting editing.
            searchTextField.text = ""
            searchTextField.sendActions(for: .editingChanged)
            return false
        }
    }
}

fileprivate extension UIViewPropertyAnimator {
    convenience init?(keyboardNotificationInfo notificationInfo: [AnyHashable: Any], animations: (@MainActor (_ keyboardEndFrame: CGRect) -> Void)? = nil) {
        guard let duration = notificationInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return nil }
        guard let keyboardFrameValue = notificationInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return nil }
        guard let curveValue = notificationInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int else { return nil }
        guard let curve = UIView.AnimationCurve(rawValue: curveValue) else { return nil }

        self.init(duration: duration, curve: curve) {
            animations?(keyboardFrameValue.cgRectValue)
        }
    }
}

fileprivate extension UISpringTimingParameters {
    // Adapted from https://medium.com/ios-os-x-development/demystifying-uikit-spring-animations-2bb868446773
    convenience init(dampingFraction: CGFloat = 0.825, response: CGFloat = 0.55) {
        precondition(dampingFraction >= 0)
        precondition(response > 0)

        let mass = 1 as CGFloat
        let stiffness = pow(2 * .pi / response, 2) * mass
        let damping = 4 * .pi * dampingFraction * mass / response

        self.init(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: .zero)
    }
}
