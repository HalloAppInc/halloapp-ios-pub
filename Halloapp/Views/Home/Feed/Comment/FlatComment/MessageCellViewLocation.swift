//
//  MessageCellViewLocation.swift
//  HalloApp
//
//  Created by Cay Zhang on 8/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CocoaLumberjackSwift
import Core
import CoreLocation
import MapKit
import CoreCommon

final class MessageCellViewLocation: MessageCellViewBase {

    private lazy var snapshotButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.mapSnapshotSize.width),
            button.heightAnchor.constraint(equalToConstant: Self.mapSnapshotSize.height),
        ])
        
        button.configureWithMenu {
            HAMenu {
                HAMenuButton(title: Localizations.openInMaps) { [weak self] in
                    self?.openInMaps()
                }
                
                HAMenuButton(title: Localizations.openInGoogleMaps) { [weak self] in
                    self?.openInGoogleMaps()
                }
            }
        }
        
        return button
    }()
    
    private var snapshotFetchingTask: Task<Void, Never>? = nil
    
    override func prepareForReuse() {
        super.prepareForReuse()
        snapshotButton.setBackgroundImage(nil, for: .normal)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        nameContentTimeRow.addArrangedSubview(nameRow)
        nameContentTimeRow.addArrangedSubview(forwardCountLabel)
        nameContentTimeRow.addArrangedSubview(snapshotButton)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(timeRow)
        nameContentTimeRow.setCustomSpacing(0, after: textRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))

        NSLayoutConstraint.activate([
            rightAlignedConstraint,
            leftAlignedConstraint
        ])

        // Tapping on user name should take you to the user's feed
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUserFeedForPostAuthor)))
        // Reply gesture
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureCellAction))
        panGestureRecognizer.delegate = self
        self.addGestureRecognizer(panGestureRecognizer)
    }

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        // TODO: Configure with post comment
    }

    override func configureWith(message: ChatMessage, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(message: message, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        
        guard let location = message.location else { return }
        
        let snapshotConfig = LocationMessage.MapSnapshotConfiguration(
            centerCoordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            traitCollection: .current,
            size: Self.mapSnapshotSize
        )

        snapshotFetchingTask?.cancel()
        let placeholderImage = UIImage(systemName: "map")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 36))
            .withTintColor(.systemGray, renderingMode: .alwaysOriginal)
        snapshotButton.setImage(placeholderImage, for: .normal)
        snapshotFetchingTask = Task.detached(priority: .userInitiated) { [location, self] in
            if let (image, isFromCache) = try? await LocationMessage.adaptiveMapSnapshot(configuration: snapshotConfig), !Task.isCancelled {
                await { @MainActor in
                    if chatMessage?.location == location {
                        if isFromCache {
                            // Only background images can be adaptive to user interface styles.
                            snapshotButton.setImage(nil, for: .normal)
                            snapshotButton.setBackgroundImage(image, for: .normal)
                        } else {
                            UIView.transition(with: snapshotButton, duration: 0.1, options: .transitionCrossDissolve) {
                                self.snapshotButton.setImage(nil, for: .normal)
                                self.snapshotButton.setBackgroundImage(image, for: .normal)
                            }
                        }
                    }
                }()
            }
        }
        
        configureText(
            text: LocationMessage.description(for: ChatLocation(location), isGoogleMapsLinkIncluded: false),
            cryptoResultString: "",
            mentions: []
        )

        configureCell()

        // hide empty space above media on incomming messages
        nameRow.isHidden = true
    }
    
    func openInMaps() {
        guard let location = chatMessage?.location else { return }
        let coordinates = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let placemark = MKPlacemark(coordinate: coordinates, addressDictionary: nil)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.name
        mapItem.openInMaps()
    }
    
    func openInGoogleMaps() {
        if let location = chatMessage?.location, let url = LocationMessage.googleMapsLink(for: ChatLocation(location)) {
            UIApplication.shared.open(url, completionHandler: nil)
        }
    }
}

// MARK: Constants
extension MessageCellViewLocation {
    static let mapSnapshotSize: CGSize = .init(width: 238, height: 238)
}

// MARK: Localizations
extension Localizations {
    static var openInMaps: String {
        NSLocalizedString("openInMapsApp.maps", value: "Open in Maps", comment: "Menu option to open a location in (Apple) Maps.")
    }
    
    static var openInGoogleMaps: String {
        NSLocalizedString("openInMapsApp.googleMaps", value: "Open in Google Maps", comment: "Menu option to open a location in Google Maps.")
    }
}
