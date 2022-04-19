//
//  FavoritesInformationViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 4/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class FavoritesInformationViewController: UIViewController {

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    func setupView() {
        view.backgroundColor = UIColor.primaryBlackWhite.withAlphaComponent(0.5)

        navigationController?.setNavigationBarHidden(true, animated: true)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.didTapBackground(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        view.addSubview(mainView)
        NSLayoutConstraint.activate([
            mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [favoritesImageView, titleLabel, descriptionView, setFavoritesButton, notNowLink])
        view.axis = .vertical
        view.alignment = .leading
        view.spacing = 40
        view.setCustomSpacing(10, after: favoritesImageView)
        view.setCustomSpacing(10, after: titleLabel)
        view.setCustomSpacing(10, after: setFavoritesButton)

        view.layoutMargins = UIEdgeInsets(top: 44, left: 23, bottom: 20, right: 23)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 20
        subView.backgroundColor = UIColor.primaryBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        view.insertSubview(closeButton, at: 1)

        NSLayoutConstraint.activate([
            setFavoritesButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            notNowLink.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        
        return view
    }()

    private lazy var closeButton: UIButton = {
        let closeButton = UIButton(type: .custom)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(named: "CloseCircle")
        closeButton.setImage(image, for: .normal)
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        return closeButton
    }()

    private lazy var favoritesImageView: UIView = {
        let imageView = UIImageView(image: UIImage(named: "PrivacySettingFavoritesWithBackground")!.withRenderingMode(.alwaysOriginal))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .favoritesBg
        container.layer.cornerRadius = 30
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 60),
            container.heightAnchor.constraint(equalTo: container.widthAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 33, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.favoritesTitle
        return label
    }()
    
    private lazy var descriptionView: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.setFavoritesDescription
        return label
    }()
    
    private lazy var setFavoritesButton: UIButton = {
        let setFavoritesButton = UIButton()
        setFavoritesButton.clipsToBounds = true
        setFavoritesButton.setTitleColor(.white, for: .normal)
        setFavoritesButton.setBackgroundColor(.systemBlue, for: .normal)
        setFavoritesButton.titleLabel?.adjustsFontSizeToFitWidth = true
        setFavoritesButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        setFavoritesButton.titleLabel?.minimumScaleFactor = 0.5
        setFavoritesButton.setTitle(Localizations.setFavorites, for: .normal)
        setFavoritesButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        setFavoritesButton.layer.cornerRadius = 10

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.didTapSetFavorites(_:)))
        setFavoritesButton.isUserInteractionEnabled = true
        setFavoritesButton.addGestureRecognizer(tapGesture)
        return setFavoritesButton
    }()
    
    private lazy var notNowLink: UILabel = {
        let notNowLink = UILabel()
        notNowLink.translatesAutoresizingMaskIntoConstraints = true
        notNowLink.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        notNowLink.textColor = .systemBlue
        notNowLink.text = Localizations.dismissEditFavorites

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.didTapNotNow(_:)))
        notNowLink.isUserInteractionEnabled = true
        notNowLink.addGestureRecognizer(tapGesture)
        notNowLink.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        notNowLink.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        notNowLink.textAlignment = .center
        return notNowLink
    }()

    @objc func didTapSetFavorites(_ sender: UITapGestureRecognizer) {
        let presentingViewController = presentingViewController
        dismiss(animated: false)
        let privacyVC = ContactSelectionViewController.forPrivacyList(MainAppContext.shared.privacySettings.whitelist, in: MainAppContext.shared.privacySettings, setActiveType: true, doneAction: { [weak self] in
            presentingViewController?.dismiss(animated: false)
            }, dismissAction: nil)
        presentingViewController?.present(UINavigationController(rootViewController: privacyVC), animated: true)
   }
    
    @objc func didTapNotNow(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true)
    }

    @objc func didTapBackground(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true)
    }

    @objc private func didTapClose() {
        dismiss(animated: true)
    }
}
