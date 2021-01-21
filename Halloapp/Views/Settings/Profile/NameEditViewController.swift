//
//  NameEditViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/11/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

private extension Localizations {

    static var titleYourName: String {
        NSLocalizedString("profile.title.your.name", value: "Your Name", comment: "Title for the screen allowing to edit profile name")
    }

    static func nameLengthCounter(_ currentLength: Int, maxLength: Int) -> String {
        let format = NSLocalizedString("profile.name.length", value: "%1$d/%2$d",
                                       comment: "Displays remaining number of characters user is allowed to enter while editing their profile name, as well as maximum allowed name length.")
        return String.localizedStringWithFormat(format, maxLength - currentLength, maxLength)
    }
}

class NameEditViewController: UITableViewController, UITextFieldDelegate {

    private enum Constants {
        static let maxNameLength = 25
    }

    private enum Section {
        case one
    }

    private enum Row {
        case nameTextField
    }

    private typealias DataSource = UITableViewDiffableDataSource<Section, Row>
    private var dataSource: DataSource!
    private var cellNameTextField: UITableViewCell!
    private var textField: UITextField!

    typealias Completion = (NameEditViewController, String?) -> Void
    let completion: Completion

    init(completion: @escaping Completion) {
        self.completion = completion
        super.init(style: .insetGrouped)
        self.title = Localizations.titleYourName
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneAction))

        tableView.allowsSelection = false
        tableView.backgroundColor = .feedBackground
        tableView.preservesSuperviewLayoutMargins = true

        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)

        let counter = UILabel()
        counter.font = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitMonoSpace)!, size: 0)
        counter.textColor = .tertiaryLabel

        textField = UITextField()
        textField.delegate = self
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.textContentType = .name
        textField.returnKeyType = .done
        textField.spellCheckingType = .no
        textField.enablesReturnKeyAutomatically = true
        textField.font = UIFont(descriptor: fontDescriptor, size: 0)
        textField.rightView = counter
        textField.rightViewMode = .whileEditing
        textField.text = MainAppContext.shared.userData.name
        textField.placeholder = textField.text
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)

        validateUserInput()

        cellNameTextField = UITableViewCell(style: .default, reuseIdentifier: nil)
        cellNameTextField.contentView.preservesSuperviewLayoutMargins = true
        cellNameTextField.contentView.addSubview(textField)
        textField.constrainMargins(to: cellNameTextField.contentView)

        dataSource = DataSource(tableView: tableView, cellProvider: { [weak self] (tableView, indexPath, row) in
            guard let self = self else { return nil }
            switch row {
            case .nameTextField: return self.cellNameTextField
            }
        })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .one ])
        snapshot.appendItems([ .nameTextField ], toSection: .one)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textField.becomeFirstResponder()
    }

    @objc private func cancelAction() {
        completion(self, nil)
    }

    @objc private func doneAction() {
        completion(self, sanitizedName())
    }

    // MARK: Text Field

    private func sanitizedName() -> String {
        return (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateUserInput() {
        let currentName = sanitizedName()

        if let counter = textField.rightView as? UILabel {
            counter.text = Localizations.nameLengthCounter(currentName.count, maxLength: Constants.maxNameLength)
            counter.sizeToFit()
        }

        navigationItem.rightBarButtonItem?.isEnabled = !currentName.isEmpty
    }

    @objc private func textFieldEditingChanged(_ textField: UITextField) {
        validateUserInput()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text, let textRange = Range(range, in: text) else {
            return true
        }
        let updatedText = text.replacingCharacters(in: textRange, with: string)

        // Simple check to not allow user to enter whitespaces only.
        // Count > 1 check allows suggestions from the suggestion panel to be inserted.
        if updatedText.count > 1 && updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return updatedText.count <= Constants.maxNameLength
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard navigationItem.rightBarButtonItem?.isEnabled ?? false else {
            return false
        }
        textField.resignFirstResponder()
        doneAction()
        return true
    }


}
