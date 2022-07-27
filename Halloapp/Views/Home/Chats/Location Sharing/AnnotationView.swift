//
//  AnnotationView.swift
//  HalloApp
//
//  Created by Cay Zhang on 7/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import MapKit
import Combine
import CoreCommon
import CocoaLumberjackSwift

extension LocationSharingViewController {
    class AnnotationView: MKMarkerAnnotationView {
        typealias AnnotationViewModel = LocationSharingViewModel.AnnotationViewModel
        
        private(set) var viewModel: AnnotationViewModel? = nil
        private var cancelBag: Set<AnyCancellable> = []
        
        private let leftImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.preferredSymbolConfiguration = .init(font: .systemFont(forTextStyle: .subheadline, weight: .semibold), scale: .large)
            return imageView
        }()
        
        private lazy var leftImageContainer: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = true
            view.bounds = CGRect(origin: .zero, size: CGSize(width: 44, height: 44))
            view.directionalLayoutMargins = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
            view.backgroundColor = .tertiarySystemGroupedBackground
            view.layer.cornerRadius = 4
            view.layer.masksToBounds = true
            
            view.addSubview(leftImageView)
            NSLayoutConstraint.activate([
                leftImageView.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
                leftImageView.topAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.topAnchor),
                leftImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                leftImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            
            return view
        }()
        
        private let subtitleLabel: UILabel = {
            let label = UILabel()
            label.adjustsFontForContentSizeCategory = true
            label.font = .preferredFont(forTextStyle: .caption1)
            label.textColor = .secondaryLabel
            label.alpha = 0
            return label
        }()
        
        private let shareButton: UIButton = {
            let button = UIButton(type: .system)
            let font = UIFont.systemFont(forTextStyle: .subheadline, weight: .semibold)
            let attachment = NSTextAttachment()  // NSTextAttachment.init(image:) won't work here.
            attachment.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(font: font))?.withRenderingMode(.alwaysTemplate)
            let title = NSMutableAttributedString(attachment: attachment)
            title.append(.init(string: " " + Localizations.buttonShare, attributes: [.font: font]))
            button.setAttributedTitle(title, for: .normal)
            button.setBackgroundColor(.tertiarySystemGroupedBackground, for: .normal)
            button.bounds = CGRect(x: 0, y: 0, width: 88, height: 44)
            button.layer.cornerRadius = 4
            button.layer.masksToBounds = true
            return button
        }()
        
        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            commonInit()
        }
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            commonInit()
        }
        
        private func commonInit() {
            animatesWhenAdded = true
            canShowCallout = true
            leftCalloutAccessoryView = leftImageContainer
            rightCalloutAccessoryView = shareButton
        }
        
        func bind(to viewModel: AnnotationViewModel) {
            cancelBag = []
            
            viewModel.$leftImage
                .sink { [leftImageView] image in
                    if let image = image?.withRenderingMode(.alwaysTemplate) {
                        leftImageView.image = image
                        leftImageView.isHidden = false
                    } else {
                        leftImageView.isHidden = true
                    }
                }
                .store(in: &cancelBag)
            
            viewModel.$tintColor
                .assign(to: \.tintColor, onWeak: self)
                .store(in: &cancelBag)
            
            viewModel.$annotation
                .sink { annotation in
                    // Trigger layout updates on callout bubbles.
                    NotificationCenter.default.post(name: .MKAnnotationCalloutInfoDidChange, object: annotation)
                }
                .store(in: &cancelBag)
            
            viewModel.$subtitle
                .sink { [weak self] subtitle in
                    guard let self = self else { return }
                    if !subtitle.isEmpty {
                        self.detailCalloutAccessoryView = self.subtitleLabel
                        self.subtitleLabel.text = subtitle
                    } else {
                        self.detailCalloutAccessoryView = nil
                    }
                    NotificationCenter.default.post(name: .MKAnnotationCalloutInfoDidChange, object: self.annotation)
                }
                .store(in: &cancelBag)
            
            self.viewModel = viewModel
        }
    }
}

extension LocationSharingViewModel {
    @MainActor
    class AnnotationViewModel: ObservableObject {
        typealias LongPressAnnotation = LocationSharingEnvironment.LongPressAnnotation
        
        var environment: LocationSharingEnvironment = .default
        
        var cancelBag: Set<AnyCancellable> = []
        
        // MARK: States
        @Published var tintColor: UIColor? = nil
        @Published var leftImage: UIImage? = nil
        @Published var annotation: any MKAnnotation
        @Published var subtitle: String = ""
        
        // MARK: Actions
        let placemarkResolved: PassthroughSubject<CLPlacemark, Never> = .init()
        
#if swift(>=5.7)
        @available(iOS 16.0, *)
        init(mapFeatureAnnotation: MKMapFeatureAnnotation) {
            annotation = mapFeatureAnnotation
            if let iconStyle = mapFeatureAnnotation.iconStyle {
                leftImage = iconStyle.image
                tintColor = iconStyle.backgroundColor
            }
            
            placemarkResolved
                .map { $0.postalAddress?.street ?? "" }
                .assign(to: \.subtitle, onWeak: self)
                .store(in: &cancelBag)
            
            setupCommonReducer(annotation: mapFeatureAnnotation)
        }
#endif
        
        init(longPressAnnotation: LongPressAnnotation) {
            annotation = longPressAnnotation
            leftImage = UIImage(systemName: "mappin.and.ellipse")
            tintColor = .lavaOrange
            
            placemarkResolved
                .map { (placemark: CLPlacemark) -> (title: String?, subtitle: String) in
                    let title = placemark.postalAddress
                        .map(\.street)
                        .flatMap { !$0.isEmpty ? $0 : nil }  // Empty street strings cause layout errors.
                    return (title, placemark.postalAddress?.city ?? "")
                }
                .sink { [weak self] (title, subtitle) in
                    if let title = title {
                        longPressAnnotation.title = title
                        self?.annotation = longPressAnnotation
                    }
                    self?.subtitle = subtitle
                }
                .store(in: &cancelBag)
            
            setupCommonReducer(annotation: longPressAnnotation)
        }
        
        private func setupCommonReducer(annotation: any MKAnnotation) {
            environment.placemark(from: annotation)
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    if case let .failure(error) = completion {
                        DDLogError("AnnotationViewModel/resolvePlacemark/error: \(error)")
                    }
                } receiveValue: { [placemarkResolved] placemark in
                    placemarkResolved.send(placemark)
                }
                .store(in: &cancelBag)
        }
    }
}
