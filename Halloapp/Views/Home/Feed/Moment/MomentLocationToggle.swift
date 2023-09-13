//
//  MomentLocationToggle.swift
//  HalloApp
//
//  Created by Tanveer on 10/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreLocation
import CoreCommon
import CocoaLumberjackSwift

protocol MomentLocationToggleDelegate: AnyObject {
    func locationToggleRequestedLocationWithoutPermission(_ toggle: MomentLocationToggle)
}

class MomentLocationToggle: UIControl {

    private enum FetchState { case none, fetching, fetched(String), error }
    private var fetchState: FetchState = .none

    private var currentLocation: CLLocation?
    private var continuation: AsyncStream<CLLocation>.Continuation?
    private var processTask: Task<Void, Never>?

    weak var delegate: MomentLocationToggleDelegate?

    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()

    /// The most recently fetched location string.
    var locationString: String? {
        if case let .fetched(location) = fetchState {
            return location
        }

        return nil
    }

    /// Used when location permission are `.notDetermined`. If the user grants us permission, we
    /// request the location without requiring an additional tap.
    private var shouldLocateAfterPermissionsGranted = false

    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [activityIndicator, locationImageView, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 7, left: 10, bottom: 7, right: 10)
        stack.spacing = 7
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.isUserInteractionEnabled = false
        return stack
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .callout, weight: .medium, maximumPointSize: 22)
        label.adjustsFontSizeToFitWidth = true
        label.numberOfLines = 0
        return label
    }()

    private lazy var locationImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(systemName: "location.fill")
        view.contentMode = .center
        return view
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isHidden = true
        indicator.hidesWhenStopped = false
        return indicator
    }()

    override var isHighlighted: Bool {
        didSet { setState(fetchState) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isEnabled = true
        isUserInteractionEnabled = true
        addTarget(self, action: #selector(didPush), for: .touchUpInside)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        tintColor = .primaryBlue

        setState(.none)
        startProcessingLocations()
    }

    required init?(coder: NSCoder) {
        fatalError("MomentLocationToggle coder init not implemented...")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColors()
    }

    deinit {
        processTask?.cancel()
    }

    @objc
    private func didPush(_ sender: UIControl) {
        guard locationString == nil else {
            return removeLocation()
        }

        switch checkLocationAuthorization() {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            setState(.fetching)

        case .notDetermined:
            shouldLocateAfterPermissionsGranted = true
            locationManager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            delegate?.locationToggleRequestedLocationWithoutPermission(self)

        @unknown default:
            DDLogError("MomentLocationToggle/locationButtonPushed/unknown authorization status")
        }
    }

    func removeLocation() {
        locationManager.stopUpdatingLocation()
        currentLocation = nil
        setState(.none)
    }

    @MainActor
    private func setState(_ newState: FetchState) {
        DDLogInfo("MomentLocationToggle/setState [\(newState)]")
        fetchState = newState
        var text = Localizations.addLocationTitle
        var image = UIImage(systemName: "location.fill")
        var hideSpinner = true

        switch newState {
        case .none:
            break
        case .fetched(let location):
            text = location
        case .fetching:
            text = Localizations.locatingTitle
            hideSpinner = false
        case .error:
            text = Localizations.locationFetchError
            image = UIImage(systemName: "location.slash.fill")
        }

        updateColors()
        statusLabel.text = text
        locationImageView.image = image

        if case .fetching = newState {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if hideSpinner != activityIndicator.isHidden {
            activityIndicator.isHidden = hideSpinner
            locationImageView.isHidden = !hideSpinner
        }

        setNeedsLayout()
    }

    private func updateColors() {
        var fetching = false
        var error = false
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        switch fetchState {
        case .fetching:
            fetching = true
        case .error:
            error = true
        default:
            break
        }

        let color = error ? UIColor.systemRed : tintColor ?? .primaryBlue
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return
        }

        if fetching || !isEnabled {
            saturation = 0.2
            brightness -= 0.35
        } else if isHighlighted {
            brightness -= 0.35
        }

        let adjusted = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        statusLabel.textColor = adjusted
        locationImageView.tintColor = adjusted
    }
}

// MARK: - CLLocationManagerDelegate methods

extension MomentLocationToggle: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = checkLocationAuthorization()

        if shouldLocateAfterPermissionsGranted, status == .authorizedWhenInUse || status == .authorizedAlways {
            shouldLocateAfterPermissionsGranted = false

            locationManager.startUpdatingLocation()
            setState(.fetching)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { await MainActor.run { setState(.error) } }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else {
            return
        }

        DDLogInfo("MomentLocationToggle/didUpdateLocations")
        continuation?.yield(latest)
    }

    @discardableResult
    private func checkLocationAuthorization() -> CLAuthorizationStatus {
        let authorization = locationManager.authorizationStatus

        DDLogInfo("MomentLocationToggle/checkAuthorization/status [\(authorization)]")
        return authorization
    }

    func requestLocation() {
        switch checkLocationAuthorization() {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            setState(.fetching)
        default:
            break
        }
    }

    private func startProcessingLocations() {
        // calls to `reverseGeocodeLocation()` are rate limited
        // check that the two locations are different enough before parsing
        func areDifferent(_ l1: CLLocation, _ l2: CLLocation?) -> Bool {
            guard let l2 else { return true }
            return l1.distance(from: l2) >= 100
        }

        let locations = AsyncStream<CLLocation> { [weak self] in
            self?.continuation = $0
        }

        processTask = Task { [weak self] in
            for await location in locations {
                guard let self, areDifferent(location, self.currentLocation) else {
                    continue
                }

                self.currentLocation = location
                if let parsed = await self.parse(location) {
                    self.setState(.fetched(parsed))
                } else {
                    self.setState(.error)
                }
            }
        }
    }

    private func parse(_ location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            DDLogError("MomentLocationToggle/unable to parse location")
            return nil
        }

        let areas = [
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country,
        ]
        .compactMap { $0 }

        let result: String?
        let (firstComponent, secondComponent) = areas.count > 1 ? (areas[0], areas[1]) : (areas.first, nil)

        switch (firstComponent, secondComponent) {
        case (.some(let first), .some(let second)) where first.range(of: second, options: .caseInsensitive) != nil:
            // avoid cases like "Downtown Mountain View, Mountain View"
            result = first
        case (.some(let first), .some(let second)):
            result = String(format: Localizations.momentLocationFormat, first, second)
        case (.some(let first), _):
            result = first
        case (_, .some(let second)):
            result = second
        default:
            result = nil
        }

        DDLogInfo("MomentLocationToggle/parsed [\(String(describing: result))]")
        return result
    }
}

// MARK: - MomentLocationToggleDelegate default implementations

extension MomentLocationToggleDelegate where Self: UIViewController {

    func locationToggleRequestedLocationWithoutPermission(_ toggle: MomentLocationToggle) {
        presentLocationPermissionDeniedAlert()
    }

    private func presentLocationPermissionDeniedAlert() {
        let alert = UIAlertController(title: Localizations.locationSharingLocationAccessRequiredAlertTitle,
                                    message: Localizations.locationSharingLocationAccessRequiredAlertMessage,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in })
        alert.addAction(UIAlertAction(title: Localizations.buttonGoToSettings, style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return
            }

            UIApplication.shared.open(url)
        })

        present(alert, animated: true)
    }
}

// MARK: - Localization

extension Localizations {

    static var addLocationTitle: String {
        NSLocalizedString("add.location.title",
                   value: "Add Location",
                 comment: "Title of a button that allows a location to be added.")
    }

    static var locatingTitle: String {
        NSLocalizedString("locating.title",
                   value: "Locating",
                 comment: "Title to indicate that a fetch operation is in progress.")
    }

    static var locationFetchError: String {
        NSLocalizedString("location.fetch.error",
                   value: "Unable to Find Location",
                 comment: "Displayed when a location fetch fails.")
    }

    static var momentLocationFormat: String {
        NSLocalizedString("moment.location.format",
                   value: "%@, %@",
                 comment: """
                          The format of a moment's location string. The first argument could be a point of interest \
                          or the name of a neighborhood, whereas the second could be a city or state name. E.g., "Brooklyn Bridge, New York".
                          """
        )
    }
}
