//
//  CountryCodeTableView.swift
//  HalloApp
//
//  Created by Tanveer on 8/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import PhoneNumberKit

extension CountryCodePickerViewController.Country: Hashable {

    public static func == (lhs: CountryCodePickerViewController.Country, rhs: CountryCodePickerViewController.Country) -> Bool {
        return lhs.code == rhs.code
            && lhs.flag == rhs.flag
            && lhs.name == rhs.name
            && lhs.prefix == rhs.prefix
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(flag)
        hasher.combine(name)
        hasher.combine(prefix)
    }
}

class CountryCodeTableView: UITableView {

    typealias Country = CountryCodePickerViewController.Country

    private lazy var data: UITableViewDiffableDataSource<Int, Country> = {
        let source = UITableViewDiffableDataSource<Int, Country>(tableView: self) { collectionView, indexPath, country in
            if let cell = collectionView.dequeueReusableCell(withIdentifier: CountryCodeTableViewCell.reuseIdentifier, for: indexPath) as? CountryCodeTableViewCell {
                cell.configure(with: country)
                return cell
            }

            return UITableViewCell()
        }

        return source
    }()

    var onSelect: ((Country) -> Void)?

    override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)

        register(CountryCodeTableViewCell.self, forCellReuseIdentifier: CountryCodeTableViewCell.reuseIdentifier)
        dataSource = data
        delegate = self

        separatorStyle = .none
        semanticContentAttribute = .forceLeftToRight
    }

    required init?(coder: NSCoder) {
        fatalError("CountryCollectionView coder init not implemented...")
    }

    func update(with countries: [Country]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Country>()
        snapshot.appendSections([0])
        snapshot.appendItems(countries, toSection: 0)

        data.apply(snapshot)
    }
}

// MARK: - UITableViewDelegate methods

extension CountryCodeTableView: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let country = data.itemIdentifier(for: indexPath) else {
            return
        }

        deselectRow(at: indexPath, animated: true)
        onSelect?(country)
    }
}

// MARK: - CountryCodeTableViewCell implementation

fileprivate class CountryCodeTableViewCell: UITableViewCell {

    static let reuseIdentifier = "countryCollectionViewCell"

    private lazy var countryCodeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private lazy var countryNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.baselineAdjustment = .alignCenters
        label.numberOfLines = 0
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false

        backgroundView = UIView()
        backgroundView?.backgroundColor = .feedPostBackground
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = .secondarySystemFill

        contentView.addSubview(countryCodeLabel)
        contentView.addSubview(countryNameLabel)

        let edgeMargin: CGFloat = 15
        let widthMultiplier: CGFloat = 0.4
        contentView.layoutMargins = UIEdgeInsets(top: 7, left: edgeMargin, bottom: 7, right: edgeMargin)

        let minimizeHeight = contentView.heightAnchor.constraint(equalToConstant: 0)
        minimizeHeight.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            countryCodeLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            countryCodeLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            countryCodeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            countryCodeLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: widthMultiplier, constant: -edgeMargin),

            countryNameLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            countryNameLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            countryNameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            countryNameLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1 - (widthMultiplier + 0.05), constant: -edgeMargin),

            minimizeHeight,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("CountryCollectionViewCell coder init not implemented...")
    }

    func configure(with country: CountryCodePickerViewController.Country) {
        countryCodeLabel.text = country.flag + " " + country.prefix
        countryNameLabel.text = country.name
    }
}
