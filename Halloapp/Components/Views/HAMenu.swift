//
//  HAMenu.swift
//  HalloApp
//
//  Created by Cay Zhang on 6/1/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CocoaLumberjackSwift
import CoreCommon

/**
 A common configuration data type for ``ActionSheetViewController``, `UIAlertController`, and `UIMenu`.
 
 ``HAMenu`` is designed with these features in mind:

 **Automatic fallback solution for lower system versions**: No additional effort is required.
 
 **Lazy loading support**: Seamless transition from delegate patterns.
 
 **SwiftUI-style syntax**: Result builders and modifiers.
 
 **Better and stricter Swift Concurrency support**: Actions are required to conform to Sendable.
 
 > For a brief documentation and a transition guide, please refer to [its original pull request](https://github.com/HalloAppInc/halloapp-ios/pull/2773).
 */
struct HAMenu {
    typealias Content = [HAMenuItem]
    
    var title: String = ""
    var subtitle: String? = nil
    var image: UIImage? = nil
    
    fileprivate var identifier: UIMenu.Identifier? = nil
    fileprivate var options: UIMenu.Options = []
    fileprivate(set) var content: () -> Content
    fileprivate(set) var isLazy: Bool

    private init(title: String = "", subtitle: String? = nil, image: UIImage? = nil, @HAMenuContentBuilder buildContent: @escaping () -> Content, isLazy: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.content = buildContent
        self.isLazy = isLazy
    }
    
    init(title: String = "", subtitle: String? = nil, image: UIImage? = nil, @HAMenuContentBuilder _ buildContent: () -> Content) {
        let content = buildContent()
        self.init(title: title, subtitle: subtitle, image: image, buildContent: { return content }, isLazy: false)
    }
    
    static func `lazy`(title: String = "", subtitle: String? = nil, image: UIImage? = nil, @HAMenuContentBuilder _ lazyBuildContent: @escaping () -> Content) -> Self {
        HAMenu(title: title, subtitle: subtitle, image: image, buildContent: lazyBuildContent, isLazy: true)
    }
    
    fileprivate func flattenedContent() -> Content {
        _flattenedContent(content())
    }
    
    private func _flattenedContent(_ content: Content) -> Content {
        content.flatMap { (item: HAMenuItem) -> [HAMenuItem] in
            switch item {
            case let .menu(menu):
                return _flattenedContent(menu.content())
            default:
                return [item]
            }
        }
    }
    
    private func modifying(_ modify: (inout Self) -> Void) -> Self {
        var copy = self
        modify(&copy)
        return copy
    }
    
    func displayInline(_ newValue: Bool = true) -> Self {
        modifying { copy in
            if newValue {
                copy.options.insert(.displayInline)
            } else {
                copy.options.remove(.displayInline)
            }
        }
    }
    
    func destructive(_ newValue: Bool = true) -> Self {
        modifying { copy in
            if newValue {
                copy.options.insert(.destructive)
            } else {
                copy.options.remove(.destructive)
            }
        }
    }
}

@resultBuilder
struct HAMenuContentBuilder {
    static func buildExpression(_ expression: HAMenuButton) -> [HAMenuItem] {
        return [.button(expression)]
    }
    
    static func buildExpression(_ expression: HAMenu) -> [HAMenuItem] {
        return [.menu(expression)]
    }

    static func buildExpression(_ expression: [HAMenuItem]?) -> [HAMenuItem] {
        return expression ?? []
    }
    
    static func buildExpression(_ expression: HAMenuButton?) -> [HAMenuItem] {
        return expression.map(buildExpression(_:)) ?? []
    }
    
    static func buildExpression(_ expression: HAMenu?) -> [HAMenuItem] {
        return expression.map(buildExpression(_:)) ?? []
    }
    
    static func buildArray(_ components: [[HAMenuItem]]) -> [HAMenuItem] {
        return Array(components.joined())
    }

    static func buildEither(first component: [HAMenuItem]) -> [HAMenuItem] {
        return component
    }

    static func buildEither(second component: [HAMenuItem]) -> [HAMenuItem] {
        return component
    }

    static func buildOptional(_ component: [HAMenuItem]?) -> [HAMenuItem] {
        return component ?? []
    }
    
    static func buildBlock(_ components: [HAMenuItem]...) -> [HAMenuItem] {
        return Array(components.joined())
    }
}

enum HAMenuItem {
    case button(HAMenuButton)
    case menu(HAMenu)
}

struct HAMenuButton {
    
    var title: String
    var image: UIImage?
    var action: @Sendable @MainActor () async -> Void
    
    fileprivate var identifier: UIAction.Identifier? = nil
    fileprivate var discoverabilityTitle: String? = nil
    fileprivate var attributes: UIMenuElement.Attributes = []
    fileprivate var state: UIMenuElement.State = .off
    
    init(title: String, image: UIImage? = nil, action: @escaping @Sendable @MainActor () async -> Void) {
        self.image = image
        self.title = title
        self.action = action
    }
    
    init(title: String, imageName: String, action: @escaping @Sendable @MainActor () async -> Void) {
        self.init(title: title, image: UIImage(named: imageName), action: action)
    }
    
    private func modifying(_ modify: (inout Self) -> Void) -> Self {
        var copy = self
        modify(&copy)
        return copy
    }
    
    func destructive(_ newValue: Bool = true) -> Self {
        modifying { copy in
            if newValue {
                copy.attributes.insert(.destructive)
            } else {
                copy.attributes.remove(.destructive)
            }
        }
    }
    
    func discoverabilityTitle(_ newValue: String?) -> Self {
        modifying { copy in
            copy.discoverabilityTitle = newValue
        }
    }
    
    func disabled(_ newValue: Bool = true) -> Self {
        modifying { copy in
            if newValue {
                copy.attributes.insert(.disabled)
            } else {
                copy.attributes.remove(.disabled)
            }
        }
    }
    
    func hidden(_ newValue: Bool = true) -> Self {
        modifying { copy in
            if newValue {
                copy.attributes.insert(.hidden)
            } else {
                copy.attributes.remove(.hidden)
            }
        }
    }
}

extension UIAlertController {
    convenience init(preferredStyle: UIAlertController.Style, buildMenu: () -> HAMenu) {
        let menu = buildMenu()
        self.init(title: menu.title, message: menu.subtitle, preferredStyle: preferredStyle)
        for item in menu.flattenedContent() {
            switch item {
            case let .button(button):
                if !button.attributes.contains(.hidden) {
                    let action = UIAlertAction(title: button.title, style: button.attributes.contains(.destructive) ? .destructive : .default) { _ in
                        Task { await button.action() }
                    }
                    action.isEnabled = !button.attributes.contains(.disabled)
                    addAction(action)
                }
            default:
                assertionFailure()
            }
        }
        addAction(.init(title: Localizations.buttonCancel, style: .cancel))
    }
}

extension ActionSheetViewController {
    convenience init?(buildMenu: () -> HAMenu) {
        let menu = buildMenu()
        self.init(title: menu.title, message: menu.subtitle)
        let flattenedContent = menu.flattenedContent()
        guard !flattenedContent.isEmpty else { return nil }
        for item in menu.flattenedContent() {
            switch item {
            case let .button(button):
                if !button.attributes.contains(.hidden) && !button.attributes.contains(.disabled) {
                    addAction(.init(title: button.title, image: button.image, style: button.attributes.contains(.destructive) ? .destructive : .default) { _ in
                        Task { await button.action() }
                    })
                }
            default:
                assertionFailure()
            }
        }
        addAction(.init(title: Localizations.buttonCancel, style: .cancel))
    }
}

extension HAMenu {
    fileprivate func uiMenuElements() -> [UIMenuElement] {
        _uiMenuElements(from: content())
    }
    
    private func _uiMenuElements(from items: [HAMenuItem]) -> [UIMenuElement] {
        items.map { (item: HAMenuItem) -> UIMenuElement in
            switch item {
            case let .menu(menu):
                return UIMenu(menu: menu)
            case let .button(button):
                return UIAction(title: button.title, image: button.image, identifier: button.identifier, discoverabilityTitle: button.discoverabilityTitle, attributes: button.attributes, state: button.state) { _ in
                    Task { await button.action() }
                }
            }
        }
    }
}

extension UIMenu {
    convenience init(menu: HAMenu) {
        self.init(menu: menu, uncacheAction: nil)
    }
    
    fileprivate convenience init(menu: HAMenu, uncacheAction: (@MainActor () -> Void)?) {
        let children: [UIMenuElement] = {
            if #available(iOS 14.0, *), menu.isLazy {
                if #available(iOS 15.0, *) {
                    return [UIDeferredMenuElement.uncached { completion in
                        completion(menu.uiMenuElements())
                    }]
                } else {
                    return [UIDeferredMenuElement { completion in
                        completion(menu.uiMenuElements())
                        uncacheAction?()
                    }]
                }
            } else {
                return menu.uiMenuElements()
            }
        }()
        
        if #available(iOS 15.0, *) {
            self.init(title: menu.title, subtitle: menu.subtitle, image: menu.image, identifier: menu.identifier, options: menu.options, children: children)
        } else {
            self.init(title: menu.subtitle.map { "\(menu.title) (\($0))" } ?? menu.title, image: menu.image, identifier: menu.identifier, options: menu.options, children: children)
        }
    }
}

extension UIBarButtonItem {

    private static var _legacyMenuActionKey: Void = ()
    
    private var _legacyMenuAction: () -> Void {
        get {
            return objc_getAssociatedObject(self, &Self._legacyMenuActionKey) as! () -> ()
        }
        set {
            objc_setAssociatedObject(self, &Self._legacyMenuActionKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    @objc
    private func _performLegacyMenuAction(sender: UIBarButtonItem) {
        _legacyMenuAction()
    }
}

extension UIButton {
    
    private static var _legacyMenuActionKey: Void = ()
    
    private var _legacyMenuAction: () -> Void {
        get {
            return objc_getAssociatedObject(self, &Self._legacyMenuActionKey) as! () -> ()
        }
        set {
            objc_setAssociatedObject(self, &Self._legacyMenuActionKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    @objc
    private func _performLegacyMenuAction(sender: UIBarButtonItem) {
        _legacyMenuAction()
    }
}

extension UIBarButtonItem {
    @MainActor convenience init(title: String? = nil, image: UIImage? = nil, buildMenu: () -> HAMenu) {
        let menu = buildMenu()
        if #available(iOS 14.0, *) {
            self.init(title: title, image: image, primaryAction: nil, menu: nil)
            if menu.isLazy {
                // A workaround to backport uncaching deferred menus to iOS 14.
                // `uncache` reassigns the menu to itself to invalidate the cache.
                // It is run immediately after the `UIDeferredMenuElement` resolves its content.
                weak var weakSelf = self
                func uncache() {
                    weakSelf?.menu = UIMenu(menu: menu, uncacheAction: uncache)
                }
                uncache()
            } else {
                self.menu = UIMenu(menu: menu)
            }
        } else {
            if let image = image {
                self.init(image: image, style: .plain, target: nil, action: #selector(_performLegacyMenuAction(sender:)))
            } else {
                self.init(title: title, style: .plain, target: nil, action: #selector(_performLegacyMenuAction(sender:)))
            }
            self.target = self
            
            self._legacyMenuAction = { [weak self] in
                guard let viewController = (self?.value(forKey: "view") as? UIView)?.firstViewController() else {
                    assertionFailure("A view controller associated with the bar button can't be found")
                    return
                }
                if let actionSheet = ActionSheetViewController(buildMenu: { menu }) {
                    viewController.present(actionSheet, animated: true)
                }
            }
        }
    }
    
    @MainActor convenience init(systemItem: UIBarButtonItem.SystemItem, buildMenu: () -> HAMenu) {
        let menu = buildMenu()
        if #available(iOS 14.0, *) {
            self.init(systemItem: systemItem, primaryAction: nil, menu: nil)
            if menu.isLazy {
                weak var weakSelf = self
                func uncache() {
                    weakSelf?.menu = UIMenu(menu: menu, uncacheAction: uncache)
                }
                uncache()
            } else {
                self.menu = UIMenu(menu: menu)
            }
        } else {
            self.init(barButtonSystemItem: systemItem, target: nil, action: #selector(_performLegacyMenuAction(sender:)))
            self.target = self

            self._legacyMenuAction = { [weak self] in
                guard let viewController = (self?.value(forKey: "view") as? UIView)?.firstViewController() else {
                    assertionFailure("A view controller associated with the bar button can't be found")
                    return
                }
                if let actionSheet = ActionSheetViewController(buildMenu: { menu }) {
                    viewController.present(actionSheet, animated: true)
                }
            }
        }
    }
}

extension UIButton {
    @MainActor func configureWithMenu(_ buildMenu: () -> HAMenu) {
        let menu = buildMenu()
        if #available(iOS 14.0, *) {
            if menu.isLazy {
                weak var weakSelf = self
                func uncache() {
                    weakSelf?.menu = UIMenu(menu: menu, uncacheAction: uncache)
                }
                uncache()
            } else {
                self.menu = UIMenu(menu: menu)
            }
            self.showsMenuAsPrimaryAction = true
        } else {
            self.addTarget(self, action: #selector(_performLegacyMenuAction(sender:)), for: .touchUpInside)
            self._legacyMenuAction = { [weak self] in
                guard let viewController = self?.firstViewController() else {
                    assertionFailure("A view controller associated with the button can't be found")
                    return
                }
                if let actionSheet = ActionSheetViewController(buildMenu: { menu }) {
                    viewController.present(actionSheet, animated: true)
                }
            }
        }
    }
}

fileprivate extension UIView {
    @MainActor func firstViewController() -> UIViewController? {
        sequence(first: self, next: { $0.next }).lazy.compactMap({ $0 as? UIViewController }).first
    }
}
