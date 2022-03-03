//
//  StorageViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import CocoaLumberjackSwift
import UIKit

// Storage Screen, for Internal Use/debugging only for now
class StorageViewController: UITableViewController {

    private enum Section {
        case one
    }

    private enum Row {
        case feedUsage
    }

    private class StorageTableViewDataSource: UITableViewDiffableDataSource<Section, Row> {

        override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            let section = snapshot().sectionIdentifiers[section]
            if section == .one {
                let spaceUsage = getSpaceUsage()
                return spaceUsage
            }
            return nil
        }
    }

    private var dataSource: StorageTableViewDataSource!

    // MARK: View Controller

    init() {
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Localizations.titleStorage

        tableView.backgroundColor = .primaryBg
        tableView.delegate = self

        dataSource = StorageTableViewDataSource(tableView: tableView, cellProvider: { (_, _, row) -> UITableViewCell? in
            return UITableViewCell()
        })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .one ])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Helpers

    private static func getSpaceUsage() -> String {
        let feedMediaUsage = ByteCountFormatter.string(fromByteCount: Int64(getSpaceOfDir(at: MainAppContext.mediaDirectoryURL)), countStyle: ByteCountFormatter.CountStyle.decimal)
        let chatMediaUsage = ByteCountFormatter.string(fromByteCount: Int64(getSpaceOfDir(at: MainAppContext.chatMediaDirectoryURL)), countStyle: ByteCountFormatter.CountStyle.decimal)
      
        return [
            "FEED MEDIA",
            feedMediaUsage,
            "CHAT MEDIA",
            chatMediaUsage
        ]
        .joined(separator: "\n\n")
    }

    private static func getSpaceOfDir(at url: URL, depth: Int = 0) -> Int {
        var result = 0
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .nameKey, .isDirectoryKey],
                options: .includesDirectoriesPostOrder)

            contents.forEach { url in
                guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey, .isDirectoryKey]) else {
                    return
                }

                if resourceValues.isDirectory ?? false {
                    result += getSpaceOfDir(at: url, depth: depth + 1)
                } else {
                    result += resourceValues.fileSize ?? 0
                }
            }

            return result
        } catch {
            DDLogError("getSpaceOfDir/\(url.absoluteString)/error [\(error)]")
            return result
        }
    }

    // MARK: Temporary Helpers used for debugging

    private static func makeDirectoryListing() -> String {
        return [
            "FEED MEDIA",
            directoryContents(at: MainAppContext.mediaDirectoryURL)
        ]
        .joined(separator: "\n\n")
    }

    private static func directoryContents(at url: URL, depth: Int = 0) -> String {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .nameKey, .isDirectoryKey],
                options: .includesDirectoriesPostOrder)
            return contents
                .compactMap { url in
                    guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey, .isDirectoryKey]) else {
                        return nil
                    }
                    let line = fileDetails(name: resourceValues.name, size: resourceValues.fileSize, depth: depth)
                    let children = resourceValues.isDirectory ?? false ? directoryContents(at: url, depth: depth + 1) : ""
                    return children.isEmpty ? line : [line, children].joined(separator: "\n")
                }
                .joined(separator: "\n")
        } catch {
            DDLogError("directoryContents/\(url.absoluteString)/error [\(error)]")
            return ""
        }
    }

    private static func fileDetails(name: String?, size: Int?, depth: Int) -> String {
        var str = String(repeating: "| ", count: depth)
        str += name ?? "[unknown]"
        if let size = size {
            let sizeString = "[\(size)]"
            str += String(repeating: ".", count: max(0, 80 - str.count - sizeString.count))
            
            let size64 = Int64(size)
            let format = ByteCountFormatter.string(fromByteCount: size64, countStyle: ByteCountFormatter.CountStyle.decimal)
            
            str += format
        }
        return str
    }
}
