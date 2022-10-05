//
//  MomentComposerViewController.swift
//  HalloApp
//
//  Created by Tanveer on 6/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreLocation
import Core
import CoreCommon
import CocoaLumberjackSwift

class MomentComposerViewController: UIViewController, UIScrollViewDelegate {

    let context: NewMomentViewController.Context

    private var media: PendingMedia?
    /// Used to wait for the creation of the media's file path.
    private var sendCancellable: AnyCancellable?

    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        return manager
    }()

    private var locationString: String?

    private lazy var audienceIndicator: UIView = {
        let pill = PillView()
        let image = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        let imageView = UIImageView(image: image)
        let label = UILabel()
        let stack = UIStackView(arrangedSubviews: [imageView, label])

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.fillColor = .darkGray.withAlphaComponent(0.8)
        imageView.contentMode = .scaleAspectFit

        label.text = PrivacyList.title(forPrivacyListType: .all)
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel

        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pill.topAnchor),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])

        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5

        return pill
    }()

    /// Displayed when the user taps on `audienceIndicator`
    private var audienceDisclaimerView: UIView?
    private var hideAudienceDisclaimerItem: DispatchWorkItem?

    private lazy var scrollViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = NewCameraViewController.Layout.innerRadius(for: .moment)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var leadingImageScrollView: ScrollableImageView = {
        let view = ScrollableImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var trailingImageScrollView: ScrollableImageView = {
        let view = ScrollableImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var trailingImageLeadingConstraint: NSLayoutConstraint = {
        let constraint = trailingImageScrollView.leadingAnchor.constraint(equalTo: background.centerXAnchor)
        constraint.priority = .defaultHigh
        return constraint
    }()

    private lazy var hideTrailingImageViewConstraint: NSLayoutConstraint = {
        let constraint = trailingImageScrollView.leadingAnchor.constraint(equalTo: scrollViewContainer.trailingAnchor)
        return constraint
    }()

    private lazy var closeTrailingImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.addTarget(self, action: #selector(pushedCloseTrailingImageButton), for: .touchUpInside)
        return button
    }()

    private(set) lazy var background: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .momentPolaroid
        view.layer.cornerRadius = NewCameraViewController.Layout.cornerRadius(for: .moment)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var sendButtonContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var sendButton: CircleButton = {
        let button = CircleButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "icon_share"), for: .normal)
        button.setBackgroundColor(.lavaOrange, for: .normal)
        button.setBackgroundColor(.lavaOrange.withAlphaComponent(0.6), for: .disabled)
        button.addTarget(self, action: #selector(sendButtonPushed), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()

    private lazy var locationButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .primaryBlue
        button.titleLabel?.font = .systemFont(forTextStyle: .body, weight: .medium, maximumPointSize: 22)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.addTarget(self, action: #selector(locationButtonPushed), for: .touchUpInside)

        let inset: CGFloat = -10
        switch view.effectiveUserInterfaceLayoutDirection {
        case .rightToLeft:
            button.imageEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: inset)
        default:
            button.imageEdgeInsets = .init(top: 0, left: inset, bottom: 0, right: 0)
        }

        return button
    }()

    @UserDefault(key: "shown.replace.moment.disclaimer", defaultValue: false)
    private static var hasShownReplacementDisclaimer: Bool

    var onPost: (() -> Void)?
    var onCancel: (() -> Void)?

    init(context: NewMomentViewController.Context) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        title = Localizations.newMomentTitle
    }

    required init?(coder: NSCoder) {
        fatalError("MomentComposerViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(audienceIndicator)
        view.addSubview(background)
        view.addSubview(locationButton)
        background.addSubview(scrollViewContainer)

        scrollViewContainer.addSubview(leadingImageScrollView)
        scrollViewContainer.addSubview(trailingImageScrollView)
        trailingImageScrollView.addSubview(closeTrailingImageButton)

        background.addSubview(sendButtonContainer)
        sendButtonContainer.addSubview(sendButton)

        let padding = NewCameraViewController.Layout.padding(for: .moment)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollViewContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: padding),
            scrollViewContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -padding),
            scrollViewContainer.topAnchor.constraint(equalTo: background.topAnchor, constant: padding),
            scrollViewContainer.heightAnchor.constraint(equalTo: scrollViewContainer.widthAnchor),

            leadingImageScrollView.leadingAnchor.constraint(equalTo: scrollViewContainer.leadingAnchor),
            leadingImageScrollView.trailingAnchor.constraint(equalTo: trailingImageScrollView.leadingAnchor),
            leadingImageScrollView.topAnchor.constraint(equalTo: scrollViewContainer.topAnchor),
            leadingImageScrollView.heightAnchor.constraint(equalTo: scrollViewContainer.heightAnchor),

            trailingImageScrollView.trailingAnchor.constraint(equalTo: scrollViewContainer.trailingAnchor),
            trailingImageLeadingConstraint,
            trailingImageScrollView.topAnchor.constraint(equalTo: scrollViewContainer.topAnchor),
            trailingImageScrollView.heightAnchor.constraint(equalTo: scrollViewContainer.heightAnchor),
            hideTrailingImageViewConstraint,

            sendButtonContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            sendButtonContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            sendButtonContainer.topAnchor.constraint(equalTo: leadingImageScrollView.bottomAnchor),
            sendButtonContainer.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            sendButton.centerXAnchor.constraint(equalTo: sendButtonContainer.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendButtonContainer.centerYAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 65),
            sendButton.widthAnchor.constraint(equalToConstant: 65),

            closeTrailingImageButton.leadingAnchor.constraint(equalTo: trailingImageScrollView.frameLayoutGuide.leadingAnchor, constant: 10),
            closeTrailingImageButton.topAnchor.constraint(equalTo: trailingImageScrollView.frameLayoutGuide.topAnchor, constant: 10),

            audienceIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            audienceIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            locationButton.topAnchor.constraint(equalTo: background.bottomAnchor, constant: 15),
            locationButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            locationButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        
        navigationItem.setHidesBackButton(true, animated: false)
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "xmark", withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
        let barButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(dismissTapped))

        navigationItem.leftBarButtonItem = barButton
        barButton.tintColor = .white

        let showTap = UITapGestureRecognizer(target: self, action: #selector(audiencePillTapped))
        audienceIndicator.addGestureRecognizer(showTap)

        let hideTap = UITapGestureRecognizer(target: self, action: #selector(hideAudiencePillTapped))
        view.addGestureRecognizer(hideTap)
        hideTap.cancelsTouchesInView = false

        updateLocationButton(.none, animated: false)
    }

    func configure(with media: PendingMedia) {
        DDLogInfo("MomentComposerViewController/configure/start")
        self.media = media

        sendCancellable = media.ready
            .first { $0 }
            .sink { [weak self] _ in
                guard let self = self else {
                    return
                }

                self.leadingImageScrollView.imageView.image = media.image
                self.leadingImageScrollView.sizeImage()

                self.sendButton.isEnabled = true
                self.sendCancellable = nil
            }
    }

    func configure(with results: [CaptureResult], animateTrailing: Bool) {
        for result in results {
            let scrollView = result.isPrimary ? leadingImageScrollView : trailingImageScrollView

            scrollView.configure(with: result)
            scrollView.sizeImage()

            if !result.isPrimary {
                updateTrailingImageViewDisplay(show: true, animate: animateTrailing)
            }
        }
    }

    private func updateTrailingImageViewDisplay(show: Bool, animate: Bool) {
        hideTrailingImageViewConstraint.isActive = !show
        leadingImageScrollView.setNeedsLayout()
        trailingImageScrollView.setNeedsLayout()

        if animate {
            return UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseOut) {
                self.view.layoutIfNeeded()
                self.leadingImageScrollView.sizeImage()
                self.trailingImageScrollView.sizeImage()
            }
        }

        view.layoutIfNeeded()
        leadingImageScrollView.sizeImage()
        trailingImageScrollView.sizeImage()
    }

    @objc
    private func pushedCloseTrailingImageButton(_ button: UIButton) {
        updateTrailingImageViewDisplay(show: false, animate: true)
    }

    @objc
    private func dismissTapped(_ button: UIBarButtonItem) {
        sendCancellable = nil

        leadingImageScrollView.imageView.image = nil
        trailingImageScrollView.imageView.image = nil
        hideTrailingImageViewConstraint.isActive = true

        sendButton.isEnabled = false
        onCancel?()
    }

    @objc
    private func sendButtonPushed(_ button: UIButton) {
        DDLogInfo("MomentComposerViewController/send/start")
        guard let publisher = dualImagePublisher ?? singleImagePublisher else {
            DDLogError("MomentComposerViewController/sendButtonPushed/could not get publisher")
            return
        }

        sendButton.isEnabled = false

        sendCancellable = publisher
            .sink { [weak self] content in
                self?.post(info: content.info, media: content.media)
            }
    }

    private func cropAndJoinImages() -> UIImage? {
        guard
            let leading = leadingImageScrollView.croppedImage,
            let trailing = trailingImageScrollView.croppedImage
        else {
            return nil
        }

        let size = CGSize(width: leading.size.height, height: leading.size.height)

        UIGraphicsBeginImageContext(size)
        leading.draw(in: .init(x: 0, y: 0, width: leading.size.width, height: leading.size.height))
        trailing.draw(in: .init(x: leading.size.width, y: 0, width: leading.size.width, height: size.width))

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return result
    }

    private func post(info: PendingMomentInfo, media: [PendingMedia]) {
        if MainAppContext.shared.feedData.validMoment.value != nil {
            // user has already posted a moment for the day
            presentReplacementDisclaimerIfNeeded { [weak self] shouldReplace in
                if shouldReplace {
                    self?.replaceMoment(info: info, with: media)
                } else {
                    self?.sendButton.isEnabled = true
                }
            }
        } else {
            MainAppContext.shared.feedData.postMoment(info: info, media: media)
            onPost?()
        }
    }

    @objc
    private func audiencePillTapped(_ gesture: UITapGestureRecognizer) {
        if audienceDisclaimerView == nil {
            showAudienceDisclaimer()
        } else {
            hideAudienceDisclaimer()
        }
    }

    @objc
    private func hideAudiencePillTapped(_ gesture: UITapGestureRecognizer) {
        if audienceDisclaimerView != nil {
            hideAudienceDisclaimer()
        }
    }

    private func showAudienceDisclaimer() {
        let label = UILabel()
        label.text = Localizations.momentAllContactsDisclaimer
        label.font = .systemFont(forTextStyle: .subheadline, maximumPointSize: 22)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center

        let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
        container.translatesAutoresizingMaskIntoConstraints = false

        let background = UIView()
        background.backgroundColor = .black
        background.translatesAutoresizingMaskIntoConstraints = false

        container.contentView.addSubview(label)
        view.addSubview(container)

        let padding: CGFloat = 12
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -padding),
            label.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -padding),

            container.topAnchor.constraint(equalTo: audienceIndicator.bottomAnchor, constant: padding),
            container.centerXAnchor.constraint(equalTo: audienceIndicator.centerXAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: view.bounds.width - 100),
        ])

        container.layer.masksToBounds = true
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        container.layer.borderWidth = 0.5

        container.transform = .identity.scaledBy(x: 0.2, y: 0.2)
        container.alpha = 0

        audienceDisclaimerView = container

        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            container.transform = .identity
            container.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleAudienceDisclaimerHide()
        }
    }

    private func scheduleAudienceDisclaimerHide() {
        let item = DispatchWorkItem { [weak self] in
            self?.hideAudienceDisclaimer()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
        hideAudienceDisclaimerItem = item
    }

    private func hideAudienceDisclaimer() {
        hideAudienceDisclaimerItem?.cancel()
        hideAudienceDisclaimerItem = nil

        UIView.animate(withDuration: 0.65, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.audienceDisclaimerView?.transform = .identity.scaledBy(x: 0.2, y: 0.2)
            self.audienceDisclaimerView?.alpha = 0
        } completion: { [weak self] _ in
            self?.audienceDisclaimerView?.removeFromSuperview()
            self?.audienceDisclaimerView = nil
        }
    }

    private func presentReplacementDisclaimerIfNeeded(_ completion: @escaping (Bool) -> Void) {
        guard !Self.hasShownReplacementDisclaimer else {
            return completion(true)
        }

        let alert = UIAlertController(title: Localizations.momentReplacementDisclaimerTitle,
                                    message: Localizations.momentReplacementDisclaimerBody,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { _ in
            completion(true)
        })

        present(alert, animated: true) {
            Self.hasShownReplacementDisclaimer = true
        }
    }

    private func replaceMoment(info: PendingMomentInfo, with media: [PendingMedia]) {
        Task {
            do {
                try await MainAppContext.shared.feedData.replaceMoment(info: info, media: media)
                DDLogInfo("FeedData/replaceMoment task/replace task finished")
            } catch {
                // not sure if this is sufficient; would like to show some error to the user but the
                // view controller will have been dismissed by this point
                DDLogError("FeedData/replaceMoment task/replace failed with error: \(String(describing: error))")
            }
        }

        onPost?()
    }
}

// MARK: - Publishers for posting

extension MomentComposerViewController {
    private typealias NewMomentContent = (media: [PendingMedia], info: PendingMomentInfo)

    private var dualImagePublisher: AnyPublisher<NewMomentContent, Never>? {
        guard
            !hideTrailingImageViewConstraint.isActive,
            let leadingResult = leadingImageScrollView.captureResult,
            let leadingCropped = leadingImageScrollView.croppedImage,
            let trailingCropped = trailingImageScrollView.croppedImage
        else {
            return nil
        }

        let backMedia = PendingMedia(type: .image)
        let frontMedia = PendingMedia(type: .image)
        let isSelfieLeading = leadingResult.direction == .front
        let unlockUserID = unlockUserID

        let orderedMedia = [backMedia, frontMedia]
        let info = PendingMomentInfo(isSelfieLeading: isSelfieLeading, locationString: locationString, unlockUserID: unlockUserID)

        backMedia.image = isSelfieLeading ? trailingCropped : leadingCropped
        frontMedia.image = isSelfieLeading ? leadingCropped : trailingCropped

        return Publishers.Merge(backMedia.ready, frontMedia.ready)
            .collect()
            .allSatisfy {
                $0.allSatisfy { ready in ready }
            }
            .flatMap { _ -> Just<NewMomentContent> in
                Just((orderedMedia, info))
            }
            .eraseToAnyPublisher()
    }

    private var singleImagePublisher: AnyPublisher<NewMomentContent, Never>? {
        guard
            hideTrailingImageViewConstraint.isActive,
            let cropped = leadingImageScrollView.croppedImage
        else {
            return nil
        }

        let media = PendingMedia(type: .image)
        let unlockUserID = unlockUserID
        let info = PendingMomentInfo(isSelfieLeading: false, locationString: locationString, unlockUserID: unlockUserID)

        media.image = cropped

        return media.ready
            .first { $0 }
            .flatMap { _ -> Just<NewMomentContent> in
                Just(([media], info))
            }
            .eraseToAnyPublisher()
    }

    private var unlockUserID: UserID? {
        if case let .unlock(post) = context {
            return post.userID
        }

        return nil
    }
}

// MARK: - FeedData extension for posting moments

extension FeedData {
    /// - note: These methods are `@MainActor` since creating new `FeedPost` objects is done using
    ///         the view context.
    @MainActor
    func replaceMoment(info: PendingMomentInfo, media: [PendingMedia]) async throws {
        guard let current = MainAppContext.shared.feedData.validMoment.value else {
            await MainActor.run { postMoment(info: info, media: media) }
            return
        }

        DDLogInfo("FeedData/replaceMoment/start")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            MainAppContext.shared.feedData.retract(post: current) { result in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        DDLogInfo("FeedData/replaceMoment/finished retraction of post with id: \(current.id)")
        await MainActor.run { postMoment(info: info, media: media) }
    }

    func postMoment(info: PendingMomentInfo, media: [PendingMedia]) {
        DDLogInfo("FeedData/postMoment/start")
        MainAppContext.shared.feedData.post(text: MentionText(collapsedText: "", mentionArray: []),
                                           media: media,
                                 linkPreviewData: nil,
                                linkPreviewMedia: nil,
                                              to: .feed(.all),
                                      momentInfo: info)
    }
}

// MARK: - CLLocationManagerDelegate methods

extension MomentComposerViewController: CLLocationManagerDelegate {

    enum LocationFetchState { case none, fetching, fetched(String), error }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }

    @discardableResult
    private func checkLocationAuthorization() -> CLAuthorizationStatus {
        let authorization: CLAuthorizationStatus
        if #available(iOS 14, *) {
            authorization = locationManager.authorizationStatus
        } else {
            authorization = CLLocationManager.authorizationStatus()
        }

        DDLogInfo("MomentComposerViewController/checkLocationAuthorization/authorization [\(authorization)]")
        return authorization
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            return
        }

        DDLogInfo("MomentComposerViewController/didUpdateLocations")
        Task { await parse(location: location) }
    }

    private func parse(location: CLLocation) async {
        var locationString: String?

        do {
            if let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first {
                locationString = placemark.locality ?? placemark.administrativeArea ?? placemark.country
            }
        } catch {
            DDLogError("MomentComposerViewController/parse-location/failed with error [\(String(describing: error))]")
        }

        DDLogInfo("MomentComposerViewController/parse-location/parsed \(locationString ?? "nil")")

        let state: LocationFetchState
        if let locationString {
            state = .fetched(locationString)
        } else {
            state = .error
        }

        updateLocationButton(state)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DDLogError("MomentComposerViewController/locationManager-didFailWithError/error [\(String(describing: error))]")

        DispatchQueue.main.async {
            self.updateLocationButton(.error)
        }
    }

    @objc
    private func locationButtonPushed(_ button: UIButton) {
        if locationString != nil {
            // remove location
            return updateLocationButton(.none)
        }

        let authorization = checkLocationAuthorization()
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            // perform a one-time request when the button is pushed
            locationManager.requestLocation()
            updateLocationButton(.fetching)

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            presentLocationPermissionDeniedAlert()

        @unknown default:
            DDLogError("MomentComposerViewController/locationButtonPushed/unknown authorization status \(authorization)")
        }
    }

    /// - note: Updates `locationString`.
    @MainActor
    private func updateLocationButton(_ state: LocationFetchState, animated: Bool = true) {
        if animated {
            return UIView.transition(with: view, duration: 0.3, options: [.transitionCrossDissolve]) {
                self.updateLocationButton(state, animated: false)
            }
        }

        var tintColor = UIColor.primaryBlue
        var isEnabled = true
        var title = Localizations.addLocationTitle
        var location: String?

        switch state {
        case .none:
            break
        case .fetching:
            isEnabled = false
            title = Localizations.fetchingTitle
        case .fetched(let locationString):
            title = locationString
            location = locationString
        case .error:
            tintColor = .systemRed
            title = Localizations.locationFetchError
        }

        locationButton.setTitle(title, for: .normal)
        locationButton.tintColor = tintColor
        locationButton.isEnabled = isEnabled

        locationString = location
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

// MARK: - ScrollableImageView implementation

fileprivate class ScrollableImageView: UIScrollView, UIScrollViewDelegate {

    private(set) lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        return view
    }()

    var image: UIImage? {
        get { imageView.image }
    }

    private(set) var captureResult: CaptureResult?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self

        clipsToBounds = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = false
        bouncesZoom = false
        maximumZoomScale = 2

        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("ScrollableImageView coder init not implemented...")
    }

    func configure(with result: CaptureResult) {
        imageView.image = result.image
        captureResult = result
    }

    func configure(with image: UIImage) {
        imageView.image = image
        captureResult = nil
    }

    func sizeImage() {
        guard let image = imageView.image else {
            return
        }

        setZoomScale(1, animated: false)

        let size = bounds.size
        let factor = max(size.width / image.size.width, size.height / image.size.height)
        let height = image.size.height * factor
        let width = image.size.width * factor

        let imageViewSize = CGSize(width: width, height: height)
        imageView.frame = CGRect(origin: .zero, size: imageViewSize)
        contentSize = imageViewSize

        center()
    }

    private func center() {
        if contentSize.width > contentSize.height {
            // Landscape image
            contentOffset.x = (contentSize.width - frame.size.width) / 2
        } else {
            // Portrait image
            contentOffset.y = (contentSize.height - frame.size.height) / 2
        }
    }

    var croppedImage: UIImage? {
        guard let image = imageView.image else {
            return nil
        }

        let scaleFactor = max(image.size.width / imageView.bounds.size.width, image.size.height / imageView.bounds.size.height)
        let zoomFactor = 1 / zoomScale
        let x = contentOffset.x * scaleFactor * zoomFactor
        let y = contentOffset.y * scaleFactor * zoomFactor

        let width = bounds.size.width * scaleFactor * zoomFactor
        let height = bounds.size.height * scaleFactor * zoomFactor
        let rect = CGRect(x: x, y: y, width: width, height: height).integral

        if let cropped = image.cgImage?.cropping(to: rect) {
            return UIImage(cgImage: cropped)
        }

        return nil
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let currentOffset = scrollView.contentOffset
        targetContentOffset.pointee = currentOffset
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

// MARK: - localization

fileprivate extension Localizations {
    static var momentReplacementDisclaimerTitle: String {
        NSLocalizedString("moment.replacement.title",
                   value: "Heads Up",
                 comment: "Title of text displayed the first time the user acts to post a second moment in the same day.")
    }

    static var momentReplacementDisclaimerBody: String {
        NSLocalizedString("moment.replacement.disclaimer",
                   value: "This new moment will replace your previous one.",
                 comment: "Text displayed the first time the user acts to post a second moment in the same day.")
    }

    static var momentAllContactsDisclaimer: String {
        NSLocalizedString("moment.contacts.disclaimer",
                   value: "Your Moment will only be shared with your contacts on HalloApp",
                 comment: "Disclaimer to tell the user that their moments go to all of their contacts on HalloApp.")
    }

    static var addLocationTitle: String {
        NSLocalizedString("add.location.title",
                   value: "Add Location",
                 comment: "Title of a button that allows a location to be added.")
    }

    static var fetchingTitle: String {
        NSLocalizedString("fetching.title",
                   value: "Fetching",
                 comment: "Title to indicate that a fetch operation is in progress.")
    }

    static var locationFetchError: String {
        NSLocalizedString("location.fetch.error",
                   value: "Error fetching location",
                 comment: "Displayed when a location fetch fails.")
    }
}
