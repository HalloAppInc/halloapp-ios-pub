//
//  WMediaSlider.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/31/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct WMediaSlider: UIViewRepresentable {
    @Binding var media: [FeedMedia]
    @Binding var pageNum: Int

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.sectionInset = .zero
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.scrollDirection = .horizontal

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(MediaSliderCell.self, forCellWithReuseIdentifier: "MediaSliderCell")
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = UIColor.clear

        let dataSource = UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>(collectionView: collectionView) { collectionView, indexPath, feedMedia in
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MediaSliderCell", for: indexPath) as? MediaSliderCell {
                cell.configure(with: feedMedia)
                return cell
            }
            return MediaSliderCell()
        }
        
        reload(dataSource: dataSource, animatingDifferences: false)
        context.coordinator.dataSource = dataSource
        collectionView.delegate = context.coordinator
        return collectionView
    }
    
    func updateUIView(_ uiView: UICollectionView, context: Context) {
        if let dataSource = context.coordinator.dataSource {
            let animate = uiView.window != nil && UIApplication.shared.applicationState == .active
            reload(dataSource: dataSource, animatingDifferences: animate)
        }
    }
    
    func reload(dataSource: UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>, animatingDifferences: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<MediaSliderSection, FeedMedia>()
        snapshot.appendSections([.main])
        snapshot.appendItems(self.media)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
        var parent: WMediaSlider
        var dataSource: UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>?
        
        init(_ view: WMediaSlider) {
            self.parent = view
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            return collectionView.frame.size
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let pageWidth = scrollView.frame.size.width
            let page = Int(floor((scrollView.contentOffset.x - pageWidth / 2) / pageWidth) + 1)
            self.parent.pageNum = page
        }
    }
}

enum MediaSliderSection {
    case main
}

class MediaSliderCell: UICollectionViewCell {
    func configure(with media: FeedMedia) {
        let controller = UIHostingController(rootView: MediaCell(media: media))
        controller.view.frame = self.contentView.bounds
        controller.view.backgroundColor = UIColor.clear
        self.contentView.addSubview(controller.view)
    }
    
    override func prepareForReuse() {
        let subviews = self.contentView.subviews
        for view in subviews {
            view.removeFromSuperview()
        }
    }
}

