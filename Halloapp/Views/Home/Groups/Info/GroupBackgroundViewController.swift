//
//  GroupBackgroundViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

fileprivate struct Constants {
    static let ColorSelectionSize: CGFloat = 55
}

protocol GroupBackgroundViewControllerDelegate: AnyObject {
    func groupBackgroundViewController(_ groupBackgroundViewController: GroupBackgroundViewController)
}

class GroupBackgroundViewController: UIViewController {
    weak var delegate: GroupBackgroundViewControllerDelegate?

    private var chatGroup: Group
    private var selectedBackground: Int32 = 0
    
    private var colorSelectionDict: [Int32: UIView] = [:]

    init(chatGroup: Group) {
        self.chatGroup = chatGroup
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        DDLogInfo("EditGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonSave, style: .done, target: self, action: #selector(updateAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.primaryBlue
        
        navigationItem.title = Localizations.groupBgTitle
        
        view.addSubview(mainView)
        view.backgroundColor = UIColor.primaryBg

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))

        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first
        let safeAreaInsetBottom = keyWindow?.safeAreaInsets.bottom ?? 0
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: safeAreaInsetBottom).isActive = true

        setupColorSelection()
        changePreviewBg(theme: chatGroup.background)
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
    }

    private var canUpdate: Bool {
        guard selectedBackground != chatGroup.background else { return false }
        return true
    }

    private func setupColorSelection() {
        for n in 0...10 {
            let theme = Int32(n)
            let colorView = createColorView(theme: theme)

            switch n {
            case 0..<4:
                colorRowOne.insertArrangedSubview(colorView, at: n % 4)
            case 4..<8:
                colorRowTwo.insertArrangedSubview(colorView, at: n % 4)
            case 8..<11:
                colorRowThree.insertArrangedSubview(colorView, at: n % 4)
            default:
                break
            }
            colorSelectionDict[Int32(n)] = colorView
        }
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ previewRow, colorSelectionRow])

        view.axis = .vertical
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let topHeight = previewRow.bounds.size.height + pickAColorLabelRow.bounds.size.height
        let height = self.view.bounds.size.height - topHeight

        selectionRow.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width).isActive = true
        selectionRow.heightAnchor.constraint(lessThanOrEqualToConstant: height).isActive = true

        return view
    }()

    private lazy var previewRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [previewDeviceImage])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 50, left: 80, bottom: 50, right: 80)
        view.isLayoutMarginsRelativeArrangement = true

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .primaryBg
        view.insertSubview(subView, at: 0)

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: UIScreen.main.bounds.height/2).isActive = true

        return view
    }()
    
    private lazy var previewDeviceImage: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "BgPreviewDevice")
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()

    private lazy var colorSelectionRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [pickAColorLabelRow, selectionRow])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = UIColor.groupBgColorSelectionPanelBg
        view.insertSubview(subView, at: 0)

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var pickAColorLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [pickAColorLabel])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 20, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        return view
    }()
    
    private lazy var pickAColorLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.text = Localizations.groupBgPickAColorLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var selectionRow: UIScrollView = {
        let view = UIScrollView()
        view.backgroundColor = .clear
        view.addSubview(innerSelectionRow)

        let height = (Constants.ColorSelectionSize + 30) * 3
        view.contentSize = CGSize(width: UIScreen.main.bounds.width, height: height)

        return view
    }()
    
    private lazy var innerSelectionRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [colorRowOne, colorRowTwo, colorRowThree])
        view.axis = .vertical
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var colorRowOne: UIStackView = {
        let view = UIStackView(arrangedSubviews: [])

        view.axis = .horizontal
        view.distribution = .equalSpacing

        view.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 25)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width).isActive = true

        return view
    }()

    private lazy var colorRowTwo: UIStackView = {
        let view = UIStackView(arrangedSubviews: [])

        view.axis = .horizontal

        view.distribution = .equalSpacing
        view.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 25)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width).isActive = true
        return view
    }()

    private lazy var colorRowThree: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: Constants.ColorSelectionSize).isActive = true
        spacer.heightAnchor.constraint(equalToConstant: Constants.ColorSelectionSize).isActive = true

        let view = UIStackView(arrangedSubviews: [spacer])
        view.axis = .horizontal
        view.distribution = .equalSpacing

        view.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 25)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width).isActive = true
        return view
    }()

    private func createColorView(theme: Int32) -> UIView {
        let view = UIView()
        view.backgroundColor = ChatData.getThemeBackgroundColor(for: theme)

        view.layer.cornerRadius = Constants.ColorSelectionSize / 2
        view.clipsToBounds = true

        view.layer.borderColor = UIColor.groupBgColorSelectionPanelBg.cgColor
        view.layer.borderWidth = 5

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ColorSelectionSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ColorSelectionSize).isActive = true

        let radius = (Constants.ColorSelectionSize / 2) - 5
        let halfSize: CGFloat = Constants.ColorSelectionSize/2
        let circlePath = UIBezierPath(arcCenter: CGPoint(x: halfSize, y: halfSize), radius: radius, startAngle: CGFloat(0), endAngle: CGFloat(Double.pi * 2), clockwise: true)
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = circlePath.cgPath

        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor.primaryBlackWhite.withAlphaComponent(0.2).cgColor
        shapeLayer.lineWidth = 1.0

        view.layer.addSublayer(shapeLayer)

        let tapGesture = BackgroundThemeUITapGestureRecognizer(target: self, action: #selector(changePreviewBgAction(_:)))
        tapGesture.theme = theme
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }

    // MARK: Actions

    @objc private func closeAction() {
        dismiss(animated: true)
    }

    @objc private func updateAction() {
        navigationItem.rightBarButtonItem?.isEnabled = false

        MainAppContext.shared.chatData.setGroupBackground(groupID: chatGroup.id, background: selectedBackground) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.delegate?.groupBackgroundViewController(self)
                DispatchQueue.main.async {
                    self.dismiss(animated: true)
                }
            case .failure(let error):
                DDLogError("EditGroupViewController/updateAction/error \(error)")
            }
        }
    }

    @objc fileprivate func changePreviewBgAction(_ sender: BackgroundThemeUITapGestureRecognizer) {
        changePreviewBg(theme: sender.theme)
    }

    private func changePreviewBg(theme: Int32) {
        guard let currentColorView = colorSelectionDict[selectedBackground] else { return }
        guard let selectedColorView = colorSelectionDict[theme] else { return }

        currentColorView.layer.borderColor = UIColor.groupBgColorSelectionPanelBg.cgColor
        if let shapeLayer = currentColorView.layer.sublayers?[0] as? CAShapeLayer {
            shapeLayer.lineWidth = 1
        }

        selectedColorView.layer.borderColor = UIColor.primaryBlue.cgColor
        if let shapeLayer = selectedColorView.layer.sublayers?[0] as? CAShapeLayer {
            shapeLayer.lineWidth = 0
        }

        selectedBackground = theme

        previewRow.subviews[0].backgroundColor = ChatData.getThemeBackgroundColor(for: theme)

        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
    }
}

fileprivate class BackgroundThemeUITapGestureRecognizer: UITapGestureRecognizer {
    var theme: Int32 = 0
}

private extension Localizations {

    static var groupBgTitle: String {
        NSLocalizedString("group.bg.title", value: "Background", comment: "Title of group background screen")
    }

    static var groupBgPickAColorLabel: String {
        NSLocalizedString("group.bg.pick.a.color.label", value: "PICK A COLOR", comment: "Label for choosing a color at the group background preview screen")
    }
}
