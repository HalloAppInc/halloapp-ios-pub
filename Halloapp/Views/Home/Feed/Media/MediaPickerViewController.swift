//
//  MediaPickerViewController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import Photos
import UIKit

fileprivate enum MediaPickerMode {
    case month, day, dayLarge
}

fileprivate enum TransitionState {
    case ready, inprogress, finishing
}

typealias MediaPickerViewControllerCallback = (MediaPickerViewController, [PendingMedia], Bool) -> Void

class MediaPickerViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, PickerViewCellDelegate {
    fileprivate var mode: MediaPickerMode = .day
    fileprivate var selected = [PickerItem]()
    
    private let didFinish: MediaPickerViewControllerCallback
    private var assets: PHFetchResult<PHAsset>?
    private var dataSource: UICollectionViewDiffableDataSource<Int, PickerItem>!
    private var collectionView: UICollectionView!
    private var transitionLayout: UICollectionViewTransitionLayout?
    private var initialTransitionVelocity: CGFloat = 0
    private var transitionState: TransitionState = .ready
    
    init(didFinish: @escaping MediaPickerViewControllerCallback) {
        self.didFinish = didFinish
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(didFinish:)")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationBar()
        fetchAssets()

        collectionView = makeCollectionView(layout: makeLayout())
        dataSource = makeDataSource(collectionView)
        dataSource.apply(makeSnapshot())

        self.view.addSubview(collectionView!)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: self.view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        
        setupZoom()
    }
    
    private func fetchAssets(album: PHAssetCollection? = nil) {
        switch(PHPhotoLibrary.authorizationStatus()) {
        case .authorized:
            break
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.fetchAssets()
                    self.dataSource.apply(self.makeSnapshot())
                }
            }
            return
        case .denied, .restricted:
            let alert = UIAlertController(title: "Photo Access Denied", message: "Please grant access from Settings", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        default:
            return
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        if let album = album {
            assets = PHAsset.fetchAssets(in: album, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: options)
        }
    }
    
    private func setupNavigationBar() {
        self.navigationController?.navigationBar.isTranslucent = false;
        self.navigationController?.navigationBar.shadowImage = UIImage()
        
        let titleBtn = UIButton(type: .system)
        titleBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleBtn.widthAnchor.constraint(equalToConstant: 260),
            titleBtn.heightAnchor.constraint(equalToConstant: 44),
        ])
        titleBtn.setTitle("Camera Roll", for: .normal)
        titleBtn.setImage(UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(scale: .small)), for: .normal)
        titleBtn.semanticContentAttribute = .forceRightToLeft // Workaround to move the image on the right side
        titleBtn.addTarget(self, action: #selector(openAlbumsAction), for: .touchUpInside)
        
        titleBtn.titleLabel?.font = UIFont.gothamFont(ofSize: 17, weight: .medium)
        self.navigationItem.titleView = titleBtn
        
        updateNavigationBarButtons()
    }
    
    private func updateNavigationBarButtons() {
        let icon = UIImage(systemName: selected.count > 0 ? "xmark" : "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: icon, style: .plain, target: self, action: #selector(cancelAction))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .done, target: self, action: #selector(nextAction))
        self.navigationItem.rightBarButtonItem?.tintColor = .systemGray
        self.navigationItem.rightBarButtonItem?.tintColor = selected.count > 0 ? .systemBlue : .systemGray
    }
    
    private func setupZoom() {
        let zoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(self.onZoom(sender:)))
        collectionView.addGestureRecognizer(zoomRecognizer)
    }
    
    @objc func onZoom(sender: UIPinchGestureRecognizer) {
        if transitionState == .finishing {
            return
        }
        
        if sender.state == .began || sender.state == .changed {
            if transitionState == .ready {
                if (sender.velocity > 0) {
                    switch mode {
                    case .month:
                        mode = .day
                    case .day:
                        mode = .dayLarge
                    default:
                        return
                    }
                } else {
                    switch mode {
                    case .dayLarge:
                        mode = .day
                    case .day:
                        mode = .month
                    default:
                        return
                    }
                }
                
                for cell in collectionView.visibleCells {
                    guard let cell = cell as? AssetViewCell else { continue }
                    cell.prepare()
                }
                
                transitionState = .inprogress
                initialTransitionVelocity = sender.velocity
                transitionLayout = collectionView.startInteractiveTransition(to: makeLayout()) { completed, finish in
                    self.transitionLayout = nil
                    self.transitionState = .ready
                }
            }
            
            if initialTransitionVelocity * sender.velocity > 0 {
                transitionLayout?.transitionProgress += 0.02
            } else {
                transitionLayout?.transitionProgress -= 0.02
            }
            
            transitionLayout?.invalidateLayout()
        } else if sender.state == .ended {
            if transitionState == .inprogress {
                transitionState = .finishing
                collectionView.finishInteractiveTransition()
            }
        }
    }
    
    private func makeCollectionView(layout: UICollectionViewFlowLayout) -> UICollectionView {
        let collectionView = UICollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.backgroundColor = .white
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.allowsMultipleSelection = true
        collectionView.register(AssetViewCell.self, forCellWithReuseIdentifier: AssetViewCell.reuseIdentifier)
        collectionView.register(LabelViewCell.self, forCellWithReuseIdentifier: LabelViewCell.reuseIdentifier)
        collectionView.register(PlaceHolderViewCell.self, forCellWithReuseIdentifier: PlaceHolderViewCell.reuseIdentifier)
        
        return collectionView
    }
    
    private func makeLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        return layout
    }
    
    private func makeDataSource(_ collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Int, PickerItem> {
        let source = UICollectionViewDiffableDataSource<Int, PickerItem>(collectionView: collectionView) { [weak self] collectionView, indexPath, asset in
            guard let self = self else { return nil }
            guard let source = self.dataSource else { return nil }
            guard let item = source.itemIdentifier(for: indexPath) else { return nil }
            
            switch item.type {
            case .asset:
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetViewCell.reuseIdentifier, for: indexPath) as? AssetViewCell else {
                    return nil
                }
                
                cell.delegate = self
                cell.item = item
                PHImageManager.default().requestImage(for: item.asset!, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: nil) { image, _ in
                    guard cell.item?.asset?.localIdentifier == item.asset?.localIdentifier else { return }
                    cell.image.image = image
                    cell.prepare()
                }
                
                return cell
            case .day, .month:
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LabelViewCell.reuseIdentifier, for: indexPath) as? LabelViewCell else { return nil }
                cell.title.text = item.label
                return cell
            case .placeholderDay, .placeholderMonth, .placeholderDayLarge:
                return collectionView.dequeueReusableCell(withReuseIdentifier: PlaceHolderViewCell.reuseIdentifier, for: indexPath)
            }
        }
        
        return source
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Int, PickerItem> {
        var snapshot = NSDiffableDataSourceSnapshot<Int, PickerItem>()
        guard let assets = assets else { return snapshot }
        guard assets.count > 0 else { return snapshot }
        
        let formatDay = DateFormatter()
        formatDay.locale = Locale.current
        formatDay.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        
        let formatDayYear = DateFormatter()
        formatDayYear.locale = Locale.current
        formatDayYear.setLocalizedDateFormatFromTemplate("EEEE, MMM d, YYYY")
        
        let formatMonth = DateFormatter()
        formatMonth.locale = Locale.current
        formatMonth.setLocalizedDateFormatFromTemplate("MMMM")
        
        let formatMonthYear = DateFormatter()
        formatMonthYear.locale = Locale.current
        formatMonthYear.setLocalizedDateFormatFromTemplate("MMMM YYYY")
        
        let thisYear = Calendar.current.component(.year, from: Date())
        var currentYear = -1
        var currentDay = -1
        var currentMonth = -1
        var itemsInMonth = 0
        var itemsInDay = 0
        
        snapshot.appendSections([0])
        for i in 0..<assets.count {
            guard let date = assets[i].creationDate else { continue }
            
            let year = Calendar.current.component(.year, from: date)
            let month = Calendar.current.component(.month, from: date)
            let day = Calendar.current.component(.day, from: date)
            
            if year != currentYear || month != currentMonth {
                if (itemsInDay % 4) > 0 {
                    snapshot.appendItems(placeholders(type: .placeholderDay, count: 4 - itemsInDay % 4, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
                }
                
                if (itemsInMonth % 5) > 0 {
                    snapshot.appendItems(placeholders(type: .placeholderMonth, count: 5 - itemsInMonth % 5, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
                }
                
                itemsInMonth = 0
                itemsInDay = 0
                if thisYear == currentYear {
                    snapshot.appendItems([
                        PickerItem(type: .month, label: formatMonth.string(from: date)),
                        PickerItem(type: .day, label: formatDay.string(from: date)),
                    ])
                } else {
                    snapshot.appendItems([
                        PickerItem(type: .month, label: formatMonthYear.string(from: date)),
                        PickerItem(type: .day, label: formatDayYear.string(from: date)),
                    ])
                }
            } else if day != currentDay {
                if (itemsInDay % 4) > 0 {
                    snapshot.appendItems(placeholders(type: .placeholderDay, count: 4 - itemsInDay % 4, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
                }

                let itemsInLastBlock = itemsInDay % 5
                if itemsInLastBlock == 1 {
                    snapshot.appendItems(placeholders(type: .placeholderDayLarge, count: 1, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
                } else if 2 < itemsInLastBlock {
                    snapshot.appendItems(placeholders(type: .placeholderDayLarge, count: 5 - itemsInLastBlock, indexInMonth: itemsInMonth, indexInDay: itemsInDay))
                }
                
                itemsInDay = 0
                if thisYear == currentYear {
                    snapshot.appendItems([PickerItem(type: .day, label: formatDay.string(from: date))])
                } else {
                    snapshot.appendItems([PickerItem(type: .day, label: formatDayYear.string(from: date))])
                }
            }

            snapshot.appendItems([PickerItem(asset: assets[i], indexInMonth: itemsInMonth, indexInDay: itemsInDay)])
            itemsInMonth += 1
            itemsInDay += 1
            
            currentYear = year
            currentMonth = month
            currentDay = day
        }
        
        return snapshot
    }
    
    private func placeholders(type: PickerItemType, count: Int, indexInMonth: Int, indexInDay: Int) -> [PickerItem] {
        var result = [PickerItem]()
        
        for j in 0..<count {
            result.append(PickerItem(type: type, indexInMonth: indexInMonth + j, indexInDay: indexInDay + j))
        }
        
        return result
    }
    
    @objc private func nextAction() {
        guard selected.count > 0 else { return }
        
        var result = [PendingMedia]()
        
        let manager = PHImageManager.default()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for i in 0..<self.selected.count {
                guard let asset = self.selected[i].asset else { continue }
                
                switch asset.mediaType {
                case .image:
                    let media = PendingMedia(type: .image)
                    media.order = i + 1
                    media.size = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
                    
                    
                    let options = PHImageRequestOptions()
                    options.isSynchronous = true
                    
                    group.enter()
                    manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { image, _ in
                        media.image = image
                        group.leave()
                    }
                    
                    result.append(media)
                case .video:
                    let media = PendingMedia(type: .video)
                    media.order = i + 1
                    
                    let options = PHVideoRequestOptions()
                    options.isNetworkAccessAllowed = true
                    
                    group.enter()
                    manager.requestAVAsset(forVideo: asset, options: options) { (avAsset, _, _) in
                        let video = avAsset as! AVURLAsset
                        media.videoURL = video.url
                        
                        if let size = VideoUtils.resolutionForLocalVideo(url: video.url) {
                            media.size = size
                        }
                        
                        group.leave()
                    }
                    
                    result.append(media)
                default:
                    continue
                }
            }
            
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                self.didFinish(self, result, false)
            }
        }
    }
    
    @objc private func cancelAction() {
        if selected.count > 0 {
            for item in selected {
                guard let indexPath = dataSource.indexPath(for: item) else { continue }
                collectionView.deselectItem(at: indexPath, animated: false)
            }
            
            selected.removeAll()
            
            for cell in collectionView.visibleCells {
                guard let cell = cell as? AssetViewCell else { continue }
                cell.prepare()
            }
            
            updateNavigationBarButtons()
        } else {
            didFinish(self, [], true)
        }
    }
    
    @objc private func openAlbumsAction() {
        let controller = MediaAlbumsViewController() {[weak self] controller, album, cancel in
            guard let self = self else { return }
            
            controller.dismiss(animated: true)
            
            if !cancel {
                self.fetchAssets(album: album)
                self.dataSource.apply(self.makeSnapshot())
            }
        }
        self.present(controller, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return CGSize.zero }
        
        switch (item.type, mode) {
        case (.asset, .month), (.placeholderMonth, .month):
            let size = (UIScreen.main.bounds.width - 0.1) * 0.2
            return CGSize(width: size, height: size)
        case (.asset, .day), (.placeholderDay, .day):
            let size = UIScreen.main.bounds.width * 0.25
            return CGSize(width: size, height: size)
        case (.asset, .dayLarge) where (item.indexInDay % 5) < 2:
            let size = UIScreen.main.bounds.width * 0.5
            return CGSize(width: size, height: size * 1.27)
        case (.placeholderDayLarge, .dayLarge) where (item.indexInDay % 5) < 2:
            let size = UIScreen.main.bounds.width * 0.5
            return CGSize(width: size, height: size * 1.27)
        case (.asset, .dayLarge), (.placeholderDayLarge, .dayLarge):
            let size = UIScreen.main.bounds.width * 0.3333
            return CGSize(width: size, height: size * 1.42)
        case (.day, .day), (.day, .dayLarge), (.month, .month):
            return CGSize(width: UIScreen.main.bounds.width, height: 50)
        default:
            return CGSize.zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        let isAsset = (collectionView.cellForItem(at: indexPath) as? AssetViewCell) != nil
        
        if isAsset && selected.count >= 10 {
            let alert = UIAlertController(title: "Maximum photos selected", message: "You can select up to 10 photos", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
        
        return isAsset && selected.count < 10
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell =  collectionView.cellForItem(at: indexPath) as? AssetViewCell else { return }
        guard let item = cell.item else { return }
        
        UIView.animateKeyframes(withDuration: 0.3, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2, animations: {
                cell.image.layer.cornerRadius = 15
                cell.image.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            })
            
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.1, animations: {
                cell.image.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            })
        }, completion: { [weak self] finished in
            guard let self = self else { return }
            self.selected.append(item)
            cell.prepare()
            self.updateNavigationBarButtons()
        })
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let cell =  collectionView.cellForItem(at: indexPath) as? AssetViewCell else { return }
        guard let item = cell.item else { return }
        
        UIView.animateKeyframes(withDuration: 0.3, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2, animations: {
                cell.image.layer.cornerRadius = 0
                cell.image.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            })
            
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.1, animations: {
                cell.image.transform = CGAffineTransform.identity
            })
        }, completion: { [weak self] finished in
            guard let self = self else { return }
            guard let idx = self.selected.firstIndex(of: item) else { return }
            
            self.selected.remove(at: idx)
            
            for cell in collectionView.visibleCells {
                guard let cell = cell as? AssetViewCell else { continue }
                cell.prepare()
            }
            
            self.updateNavigationBarButtons()
        })
    }
}

fileprivate protocol PickerViewCellDelegate: class {
    var mode: MediaPickerMode {get}
    var selected: [PickerItem] {get}
}

fileprivate enum PickerItemType {
    case asset, day, month, placeholderMonth, placeholderDay, placeholderDayLarge
}

fileprivate struct PickerItem: Hashable {
    let indexInMonth: Int
    let indexInDay: Int
    let type: PickerItemType
    let label: String?
    let asset: PHAsset?
    
    init(type: PickerItemType, indexInMonth: Int, indexInDay: Int) {
        self.type = type
        self.label = UUID().uuidString
        self.asset = nil
        self.indexInMonth = indexInMonth
        self.indexInDay = indexInDay
    }
    
    init(type: PickerItemType, label: String) {
        self.type = type
        self.label = label
        self.asset = nil
        indexInMonth = 0
        indexInDay = 0
    }
    
    init(asset: PHAsset, indexInMonth: Int, indexInDay: Int) {
        self.type = .asset
        self.label = nil
        self.asset = asset
        self.indexInMonth = indexInMonth
        self.indexInDay = indexInDay
    }
}

fileprivate class PlaceHolderViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: PlaceHolderViewCell.self)
    }
}

fileprivate class LabelViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: LabelViewCell.self)
    }
    
    lazy var title: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .left
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .systemBackground
        contentView.addSubview(title)
        contentView.clipsToBounds = true
        
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: contentView.topAnchor),
            title.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate class AssetViewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: AssetViewCell.self)
    }
    
    weak var delegate: PickerViewCellDelegate?
    var item: PickerItem?
    
    private var activeConstraints = [NSLayoutConstraint]()
    
    lazy var indicator: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.layer.cornerRadius = 10
        label.layer.borderWidth = 2.5
        label.layer.masksToBounds = true
        
        return label
    }()
    
    lazy var image: UIImageView = {
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        
        return image
    }()
    
    lazy var play: UIImageView = {
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large))?.withTintColor(.white, renderingMode: .alwaysOriginal)
        image.alpha = 0.7
        
        return image
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(image)
        contentView.addSubview(indicator)
        contentView.addSubview(play)
        contentView.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func calculateSpacing() -> (CGFloat, CGFloat, CGFloat) {
        guard let delegate = delegate else { return (0, 0, 0) }
        guard let item = item else { return (0, 0, 0) }
        
        let spacing = CGFloat(1)
        
        var column: CGFloat
        var columnCount: CGFloat
        
        switch delegate.mode {
        case .month:
            column = CGFloat(item.indexInMonth % 5)
            columnCount = 5
        case .day:
            column = CGFloat(item.indexInDay % 4)
            columnCount = 4
        case .dayLarge:
            let indexInBlock = item.indexInDay % 5
            
            if indexInBlock < 2 {
                column = CGFloat(indexInBlock)
                columnCount = 2
            } else {
                column = CGFloat((indexInBlock - 2) % 3)
                columnCount = 3
            }
        }
        
        return (spacing, column * spacing / columnCount, spacing - ((column + 1) * spacing / columnCount))
    }
    
    func prepare() {
        let (spacingBottom, spacingLead, spacingTrail) = calculateSpacing()
        
        NSLayoutConstraint.deactivate(activeConstraints)
        
        activeConstraints = [
            image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacingLead),
            image.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacingTrail),
            image.topAnchor.constraint(equalTo: contentView.topAnchor),
            image.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacingBottom),
            indicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            indicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            indicator.widthAnchor.constraint(equalToConstant: 20),
            indicator.heightAnchor.constraint(equalToConstant: 20),
            play.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            play.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ]
        
        NSLayoutConstraint.activate(activeConstraints)
        
        if let item = item, let idx = delegate?.selected.firstIndex(of: item) {
            image.layer.cornerRadius = 15
            image.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            
            self.indicator.layer.borderColor = UIColor.lavaOrange.cgColor
            self.indicator.backgroundColor = .lavaOrange
            self.indicator.text = "\(1 + idx)"
        } else {
            image.layer.cornerRadius = 0
            image.transform = CGAffineTransform.identity
            
            self.indicator.layer.borderColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.7)
            self.indicator.backgroundColor = .none
            self.indicator.text = ""
        }
        
        play.isHidden = item?.asset?.mediaType != .video
        
        setNeedsLayout()
    }
}
