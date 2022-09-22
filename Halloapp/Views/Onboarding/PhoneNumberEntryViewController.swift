//
//  PhoneNumberEntryViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/1/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import PhoneNumberKit
import CoreCommon
import Core
import CocoaLumberjackSwift

fileprivate typealias Country = CountryCodePickerViewController.Country

struct RegistrationPhoneNumber {

    let countryCode: String
    let nationalNumber: String
    let formattedNumber: String
}

private extension PhoneNumberEntryViewController {

    static var minimumTableViewHeight: CGFloat {
        110
    }

    static var margin: CGFloat {
        20
    }

    static var textFieldInset: CGFloat {
        12
    }

    static var cornerRadius: CGFloat {
        10
    }
}

class PhoneNumberEntryViewController: UIViewController {

    let registrationManager: RegistrationManager

    private var cancellables: Set<AnyCancellable> = []
    private let model: PhoneNumberKit = AppContext.shared.phoneNumberFormatter

    private lazy var allCountries: [Country] = model.allCountries()
        .compactMap { Country(for: $0, with: model) }
        .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })

    private var filteredCountries: [Country] = []
    private lazy var defaultCountry = Country(for: PhoneNumberKit.defaultRegionCode(), with: model)

    @Published private var selectedCountry: Country?
    @Published private var rawNumberText = ""
    @Published private var phoneNumber: RegistrationPhoneNumber?

    private lazy var logoView: UIImageView = {
        let view = UIImageView()
        let image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = image
        view.tintColor = .lavaOrange
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInset = UIEdgeInsets(top: 25, left: 0, bottom: Self.margin, right: 0)
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [promptLabel, textFieldHStack, tableViewContainer, reasoningLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: Self.margin, bottom: 0, right: Self.margin)
        stack.spacing = 12
        stack.setCustomSpacing(0, after: tableViewContainer)

        return stack
    }()

    private lazy var promptLabel: UILabel = {
        let label = UILabel()
        let image = UIImage(systemName: "iphone") ?? UIImage()

        let textFont = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium, maximumPointSize: 20)
        let imageFont = UIFont.systemFont(ofSize: textFont.pointSize, weight: .medium)
        let string = NSMutableAttributedString.string(Localizations.registrationPhoneNumberPrompt,
                                                with: image,
                                             spacing: 2,
                                     imageAttributes: [.font: imageFont, .foregroundColor: UIColor.lavaOrange],
                                      textAttributes: [.font: textFont, .foregroundColor: UIColor.lavaOrange])

        label.attributedText = string
        return label
    }()

    private lazy var reasoningLabel: UILabel = {
        let label = UILabel()
        label.text = Localizations.registrationPhoneNumberReasoning
        label.font = .systemFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = true

        return label
    }()

    private lazy var textFieldHStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [countryCodeTextFieldContainer, phoneNumberTextFieldContainer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.semanticContentAttribute = .forceLeftToRight
        stack.axis = .horizontal
        stack.distribution = .fillProportionally
        stack.spacing = 15

        return stack
    }()

    private lazy var phoneNumberTextFieldContainer: ShadowView = {
        let view = ShadowView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .feedPostBackground
        view.layer.cornerRadius = Self.cornerRadius

        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0.75
        view.layer.shadowOpacity = 1

        return view
    }()

    private lazy var countryCodeTextFieldContainer: ShadowView = {
        let view = ShadowView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.semanticContentAttribute = .forceLeftToRight
        view.backgroundColor = .feedPostBackground
        view.layer.cornerRadius = Self.cornerRadius

        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0.75
        view.layer.shadowOpacity = 1

        return view
    }()

    private lazy var phoneNumberTextField: PhoneNumberTextField = {
        let textField = PhoneNumberTextField(withPhoneNumberKit: model)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.semanticContentAttribute = .forceLeftToRight
        textField.font = .systemFont(forTextStyle: .body)
        textField.tintColor = .systemBlue

        textField.withFlag = false
        textField.withExamplePlaceholder = true
        textField.withPrefix = false

        textField.addTarget(self, action: #selector(phoneNumberTextFieldDidChange), for: .editingChanged)
        textField.delegate = self
        return textField
    }()

    private lazy var codeTextField: CountryCodeTextField = {
        let textField = CountryCodeTextField(frame: .zero)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.semanticContentAttribute = .forceLeftToRight
        textField.font = .systemFont(forTextStyle: .body)
        textField.tintColor = .systemBlue

        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)

        textField.addTarget(self, action: #selector(countryCodeTextFieldDidChange), for: .editingChanged)
        textField.delegate = self
        return textField
    }()

    private lazy var countryCodeSearchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .feedPostBackground
        searchBar.searchTextField.backgroundColor = .clear
        searchBar.searchTextField.borderStyle = .none
        searchBar.tintColor = .systemBlue
        searchBar.placeholder = Localizations.labelSearch
        searchBar.delegate = self

        searchBar.layoutMargins = .zero
        searchBar.searchTextField.layoutMargins = .zero
        searchBar.layer.cornerRadius = Self.cornerRadius
        searchBar.layer.masksToBounds = true
        searchBar.layer.maskedCorners = CACornerMask([.layerMinXMinYCorner, .layerMaxXMinYCorner])

        return searchBar
    }()

    private lazy var tableViewContainerHeightConstraint: NSLayoutConstraint = {
        let constraint = tableViewContainer.heightAnchor.constraint(equalToConstant: 0)
        constraint.priority = .defaultHigh
        return constraint
    }()

    /// Contains `countryCodeSearchBar` and `countryCodeTableView`.
    private lazy var tableViewContainer: ShadowView = {
        let view = ShadowView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Self.cornerRadius

        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0.75
        view.layer.shadowOpacity = 1
        view.alpha = 0

        return view
    }()

    private lazy var countryCodeTableView: CountryCodeTableView = {
        let tableView = CountryCodeTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.layer.cornerRadius = Self.cornerRadius
        tableView.layer.maskedCorners = CACornerMask([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        tableView.layer.masksToBounds = true

        tableView.onSelect = { [weak self] in
            self?.selectedCountry = $0
            self?.phoneNumberTextField.becomeFirstResponder()
        }

        return tableView
    }()

    private lazy var footerStackBottomConstraint: NSLayoutConstraint = {
        let constraint = footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -OnboardingConstants.bottomButtonBottomDistance)
        return constraint
    }()

    private lazy var footerStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nextButton, smsDisclaimerLabel])
        let padding = OnboardingConstants.bottomButtonPadding
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)
        return stack
    }()

    private lazy var nextButton: RoundedRectChevronButton = {
        let button = RoundedRectChevronButton()
        button.contentEdgeInsets = OnboardingConstants.bottomButtonInsets
        button.backgroundTintColor = .lavaOrange
        button.tintColor = .white
        button.setTitle(Localizations.buttonNext, for: .normal)

        button.addTarget(self, action: #selector(nextButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var smsDisclaimerLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .caption1, maximumPointSize: 16)
        label.text = Localizations.registrationCodeDisclaimer
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    init(registrationManager: RegistrationManager) {
        self.registrationManager = registrationManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("PhoneNumberPickerViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        countryCodeTextFieldContainer.addSubview(codeTextField)
        phoneNumberTextFieldContainer.addSubview(phoneNumberTextField)
        view.addSubview(logoView)
        view.addSubview(scrollView)
        scrollView.addSubview(vStack)
        view.addSubview(footerStack)

        tableViewContainer.addSubview(countryCodeSearchBar)
        tableViewContainer.addSubview(countryCodeTableView)

        let textFieldInset = Self.textFieldInset

        NSLayoutConstraint.activate([
            logoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            logoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logoView.heightAnchor.constraint(equalToConstant: 30),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor),

            codeTextField.leadingAnchor.constraint(equalTo: countryCodeTextFieldContainer.leadingAnchor, constant: textFieldInset),
            codeTextField.trailingAnchor.constraint(equalTo: countryCodeTextFieldContainer.trailingAnchor, constant: -textFieldInset),
            codeTextField.topAnchor.constraint(equalTo: countryCodeTextFieldContainer.topAnchor, constant: textFieldInset),
            codeTextField.bottomAnchor.constraint(equalTo: countryCodeTextFieldContainer.bottomAnchor, constant: -textFieldInset),

            phoneNumberTextField.leadingAnchor.constraint(equalTo: phoneNumberTextFieldContainer.leadingAnchor, constant: textFieldInset),
            phoneNumberTextField.trailingAnchor.constraint(equalTo: phoneNumberTextFieldContainer.trailingAnchor, constant: -textFieldInset),
            phoneNumberTextField.topAnchor.constraint(equalTo: phoneNumberTextFieldContainer.topAnchor, constant: textFieldInset),
            phoneNumberTextField.bottomAnchor.constraint(equalTo: phoneNumberTextFieldContainer.bottomAnchor, constant: -textFieldInset),

            countryCodeSearchBar.leadingAnchor.constraint(equalTo: tableViewContainer.leadingAnchor),
            countryCodeSearchBar.trailingAnchor.constraint(equalTo: tableViewContainer.trailingAnchor),
            countryCodeSearchBar.topAnchor.constraint(equalTo: tableViewContainer.topAnchor),

            countryCodeTableView.topAnchor.constraint(equalTo: countryCodeSearchBar.bottomAnchor),
            countryCodeTableView.leadingAnchor.constraint(equalTo: tableViewContainer.leadingAnchor),
            countryCodeTableView.trailingAnchor.constraint(equalTo: tableViewContainer.trailingAnchor),
            countryCodeTableView.bottomAnchor.constraint(equalTo: tableViewContainer.bottomAnchor),

            vStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            tableViewContainerHeightConstraint,

            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerStackBottomConstraint,
        ])

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(keyboardSwipeGesture))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)

        countryCodeTableView.update(with: allCountries)

        formSubscriptions()
        selectedCountry = defaultCountry
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if codeTextField.text?.isEmpty ?? true {
            codeTextField.becomeFirstResponder()
        } else {
            phoneNumberTextField.becomeFirstResponder()
        }
    }

    private func formSubscriptions() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] in self?.updateLayout(using: $0, keyboardShowing: true) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] in self?.updateLayout(using: $0, keyboardShowing: false) }
            .store(in: &cancellables)

        $selectedCountry
            .compactMap { [weak self] in
                self?.codeTextField.country = $0
                return $0
            }
            .sink { [weak self] (country: Country) in
                self?.phoneNumberTextField.placeholder = self?.model.getFormattedExampleNumber(forCountry: country.code, withPrefix: false)
                self?.phoneNumberTextField.partialFormatter.defaultRegion = country.code
            }
            .store(in: &cancellables)

        Publishers
            .CombineLatest($selectedCountry, $rawNumberText)
            .map { [weak self] in
                if let country = $0, let number = self?.validate(number: $1, for: country) {
                    return number
                }

                return nil
            }
            .sink { [weak self] in
                self?.phoneNumber = $0
            }
            .store(in: &cancellables)

        $phoneNumber
            .map { return $0 == nil ? false : true }
            .assign(to: \.isEnabled, onWeak: nextButton)
            .store(in: &cancellables)

        AppContext.shared.didGetGroupInviteToken
            .sink {
                // TODO
            }
            .store(in: &cancellables)
    }

    /// Updates constraints and the visibility of views when the keyboard shows/hides.
    private func updateLayout(using info: KeyboardNotificationInfo, keyboardShowing: Bool) {
        let showTableView = (self.codeTextField.isFirstResponder || self.countryCodeSearchBar.isFirstResponder) && keyboardShowing
        if showTableView {
            self.showCountryCodeTableViewIfNeeded(info, keyboardShowing: keyboardShowing)
        } else {
            self.hideCountryCodeTableViewIfNeeded(info, keyboardShowing: keyboardShowing)
        }

        UIView.animate(withKeyboardNotificationInfo: info) {
            self.view.layoutIfNeeded()

            if showTableView {
                self.tableViewContainer.alpha = 1
            } else {
                self.tableViewContainer.alpha = 0
            }
        } completion: { _ in
            if self.countryCodeSearchBar.isFirstResponder {
                self.scrollToBottom()
            }
        }
    }

    private func showCountryCodeTableViewIfNeeded(_ info: KeyboardNotificationInfo, keyboardShowing: Bool) {
        footerStackBottomConstraint.constant = keyboardShowing ? -info.endFrame.height + view.safeAreaInsets.bottom + footerStack.bounds.height : -OnboardingConstants.bottomButtonBottomDistance
        /*
         The design calls for the bottom of the table view to be pinned to the top edge of the keyboard.
         When the user's system font size is very large, the actual height of the table view becomes borderline
         unusable due to the search bar's height. In this case, we extend the height of the table view to go
         beyond the top of the keyboard.
         */
        let origin = view.convert(tableViewContainer.frame.origin, from: tableViewContainer.superview)
        var height = (view.bounds.maxY - origin.y) - info.endFrame.height - scrollView.contentInset.bottom
        if height - countryCodeSearchBar.intrinsicContentSize.height < 100 {
            height = countryCodeSearchBar.intrinsicContentSize.height + 100
        }

        tableViewContainerHeightConstraint.constant = height

        footerStack.alpha = 0
        footerStack.isUserInteractionEnabled = false

        if !reasoningLabel.isHidden {
            // prevent cumulative hiding bug for `UIStackView`
            reasoningLabel.isHidden = true
            countryCodeTableView.isHidden = false
        }
    }

    private func hideCountryCodeTableViewIfNeeded(_ info: KeyboardNotificationInfo, keyboardShowing: Bool) {
        footerStackBottomConstraint.constant = keyboardShowing ? -info.endFrame.height + view.safeAreaInsets.bottom : -OnboardingConstants.bottomButtonBottomDistance

        footerStack.alpha = 1
        footerStack.isUserInteractionEnabled = true

        tableViewContainerHeightConstraint.constant = 0

        if reasoningLabel.isHidden {
            reasoningLabel.isHidden = false
            countryCodeTableView.isHidden = true
        }
    }

    @objc
    private func keyboardSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
        hideKeyboard()
    }

    private func hideKeyboard() {
        view.endEditing(true)
    }

    private func validate(number: String, for country: Country) -> RegistrationPhoneNumber? {
        var validNumber: RegistrationPhoneNumber?
        let lengths = model.possiblePhoneNumberLengths(forCountry: country.code,
                                                  phoneNumberType: .mobile,
                                                       lengthType: .national)

        if lengths.contains(number.count) {
            DDLogInfo("PhoneNumberPickerViewController/validation publisher/entered valid number: [\(number)] country: [\(country)]")

            var formattedNumber = "+\(country.prefix) \(number)"
            if let parsed = try? model.parse(number, withRegion: country.code) {
                formattedNumber = model.format(parsed, toType: .international)
            }

            validNumber = RegistrationPhoneNumber(countryCode: country.prefix, nationalNumber: number, formattedNumber: formattedNumber)
        } else {
            DDLogInfo("PhoneNumberPickerViewController/validation publisher/entered invalid number: [\(number)] country: [\(country)] lengths: \(lengths)")
        }

        return validNumber
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        guard let number = phoneNumber else {
            return
        }

        registrationManager.set(countryCode: number.countryCode, nationalNumber: number.nationalNumber, userName: "")
        hideKeyboard()

        let vc = PhoneNumberVerificationViewController(registrationManager: registrationManager, registrationNumber: number)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func scrollToTop(animated: Bool = false) {
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.contentInset.top), animated: animated)
    }

    private func scrollToBottom(animated: Bool = false) {
        let offset = CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
        scrollView.setContentOffset(offset, animated: animated)
    }
}

// MARK: UITextFieldDelegate methods

extension PhoneNumberEntryViewController: UITextFieldDelegate {

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        scrollToTop()
        return true
    }

    @objc
    private func countryCodeTextFieldDidChange(_ textField: UITextField) {
        guard
            let text = textField.text,
            let code = UInt64(text),
            let regionCode = model.mainCountry(forCode: code),
            let country = Country(for: regionCode, with: model)
        else {
            selectedCountry = nil
            return
        }

        if country.prefix == defaultCountry?.prefix {
            selectedCountry = defaultCountry
        } else {
            selectedCountry = country
        }
    }

    @objc
    private func phoneNumberTextFieldDidChange(_ textField: UITextField) {
        rawNumberText = phoneNumberTextField.nationalNumber
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {

    }

    func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {

    }
}

// MARK: - UISearchBar delegate methods

extension PhoneNumberEntryViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !searchText.isEmpty else {
            return countryCodeTableView.update(with: allCountries)
        }

        let searchText = searchText.lowercased()
        let filtered = allCountries.filter {
            $0.name.lowercased().contains(searchText) ||
            $0.code.lowercased().contains(searchText) ||
            $0.prefix.lowercased().contains(searchText)
        }

        countryCodeTableView.update(with: filtered)
    }

    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        // scroll to top so that we can size the table view correctly
        scrollToTop()
        return true
    }
}

fileprivate class CountryCodeTextField: PhoneNumberTextField {

    var country: Country? {
        didSet { refreshCountry() }
    }

    private lazy var flagLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, maximumPointSize: 30)
        label.textColor = .secondaryLabel
        label.semanticContentAttribute = .forceLeftToRight
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isPartialFormatterEnabled = false
        withFlag = false
        withPrefix = false

        leftView = flagLabel
        leftViewMode = .always
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("CountryCodeTextField coder init not implemented...")
    }

    private func refreshCountry() {
        let flag = country?.flag ?? "  "
        flagLabel.text = "\(flag) + "

        if let prefix = country?.prefix {
            text = prefix.first == "+" ? String(prefix.dropFirst(1)) : prefix
        }
    }
}

// MARK: - onboarding constants

/// Layout values that are used in the onboarding view controllers.
struct OnboardingConstants {

    static var bottomButtonBottomDistance: CGFloat {
        65
    }

    static var bottomButtonInsets: UIEdgeInsets {
        UIEdgeInsets(top: 12, left: 80, bottom: 12, right: 80)
    }

    static var bottomButtonPadding: CGFloat {
        10
    }
}

// MARK: - localization

extension Localizations {

    static var registrationPhoneNumberPrompt: String {
        NSLocalizedString("registration.phone.number.prompt",
                   value: "What is your phone number?",
                 comment: "Text that is above the field for the user's phone number during registration.")
    }

    static var registrationPhoneNumberReasoning: String {
        NSLocalizedString("registration.phone.number.reasoning",
                   value: "Your phone number is how you find your friends on HalloApp, and how they find you!",
                 comment: "Text that explains why HalloApp needs the user's phone number during registration.")
    }
}
