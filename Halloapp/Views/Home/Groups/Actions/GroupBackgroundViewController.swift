//
//  GroupBackgroundViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit

fileprivate struct Constants {
    static let ColorSelectionSize: CGFloat = 55
}

protocol GroupBackgroundViewControllerDelegate: AnyObject {
    func groupBackgroundViewController(_ groupBackgroundViewController: GroupBackgroundViewController)
}

class GroupBackgroundViewController: UIViewController {
    weak var delegate: GroupBackgroundViewControllerDelegate?

    private var chatGroup: ChatGroup
    private var selectedBackground: Int32 = 0
    
    private var colorSelectionDict: [Int32: UIView] = [:]

    init(chatGroup: ChatGroup) {
        self.chatGroup = chatGroup
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        DDLogInfo("EditGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonSave, style: .plain, target: self, action: #selector(updateAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        
        navigationItem.title = Localizations.groupBgTitle
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        
        view.addSubview(mainView)
        view.backgroundColor = UIColor.primaryBg

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))

        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
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
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ previewRow, pickAColorLabelRow, selectionRow, spacer])

        view.axis = .vertical
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
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

        view.layoutMargins = UIEdgeInsets(top: 70, left: 70, bottom: 70, right: 70)
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

    private lazy var pickAColorLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [pickAColorLabel])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        return view
    }()
    
    private lazy var pickAColorLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.groupBgPickAColorLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var selectionRow: UIScrollView = {
        let view = UIScrollView()
        view.backgroundColor = .clear
        view.addSubview(innerSelectionRow)

        let height = (Constants.ColorSelectionSize + 35) * 3
        view.contentSize = CGSize(width: UIScreen.main.bounds.width, height: height)

        return view
    }()
    
    private lazy var innerSelectionRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [colorRowOne, colorRowTwo, colorRowThree])
        view.axis = .vertical
        view.spacing = 20
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var colorRowOne: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [spacer])

        view.axis = .horizontal
        view.spacing = 35
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var colorRowTwo: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [spacer])

        view.axis = .horizontal
        view.spacing = 35
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var colorRowThree: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [spacer])
        
        view.axis = .horizontal
        view.spacing = 35
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private func createColorView(theme: Int32) -> UIView {
        let view = UIView()
        if theme == 0, let defaultPatternImage = UIImage(named: "DefaultPattern") {
            view.backgroundColor = UIColor(patternImage: defaultPatternImage)
        } else {
            view.backgroundColor = ChatData.getThemeBackgroundColor(for: theme)
        }
        
        view.layer.cornerRadius = Constants.ColorSelectionSize / 2
        view.clipsToBounds = true

        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.widthAnchor.constraint(equalToConstant: Constants.ColorSelectionSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ColorSelectionSize).isActive = true
        
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

        MainAppContext.shared.chatData.setGroupBackground(groupID: chatGroup.groupId, background: selectedBackground) { [weak self] result in
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

        currentColorView.layer.borderWidth = 0
        
        selectedColorView.layer.borderColor = UIColor.primaryBlue.cgColor
        selectedColorView.layer.borderWidth = 5

        selectedBackground = theme
        
        if theme == 0, let defaultPatternImage = UIImage(named: "DefaultPatternLgSquare") {
            previewRow.subviews[0].backgroundColor = UIColor(patternImage: defaultPatternImage)
        } else {
            previewRow.subviews[0].backgroundColor = ChatData.getThemeBackgroundColor(for: theme)
        }
//        previewRow.subviews[0].backgroundColor = ChatData.getThemeBackgroundColor(for: theme)
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
