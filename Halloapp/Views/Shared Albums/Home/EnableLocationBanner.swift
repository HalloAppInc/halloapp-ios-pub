//
//  EnableLocationBanner.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/29/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import CoreLocation
import UIKit

class EnableLocationBanner: UIView {

    private let explanationLabel: UILabel = {
        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.text = Localizations.enableAlwaysOnLocationExplanation
        explanationLabel.textColor = .white
        return explanationLabel
    }()

    private let enableLocationButton: UIButton = {
        let enableLocationButton = UIButton(type: .system)
        enableLocationButton.tintColor = .systemBlue
        enableLocationButton.setTitle(Localizations.enableAlwaysOnLocationAction, for: .normal)
        return enableLocationButton
    }()

    private let locationManager = CLLocationManager()

    override init(frame: CGRect) {
        super.init(frame: frame)

        locationManager.delegate = self

        backgroundColor = .lavaOrange
        layer.cornerRadius = 16

        enableLocationButton.addTarget(self, action: #selector(enableLocation), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [explanationLabel, enableLocationButton])
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        updateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func updateVisibility() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways:
            isHidden = true
        default:
            isHidden = false
        }
    }

    @objc private func enableLocation() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways:
            break
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        default:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        }
    }
}

extension EnableLocationBanner: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        updateVisibility()
    }
}

extension Localizations {

    static var enableAlwaysOnLocationExplanation: String {
        return NSLocalizedString("enablelocationbanner.label", value: "Get notified of new post suggestions", comment: "")
    }

    static var enableAlwaysOnLocationAction: String {
        return NSLocalizedString("enablelocationbanner.action", value: "Enable", comment: "")
    }
}
