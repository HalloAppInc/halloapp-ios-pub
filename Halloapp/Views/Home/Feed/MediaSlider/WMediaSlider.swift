//
//  WMediaSlider.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/31/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

enum MediaSliderSection {
    case main
}

class MediaSliderCell: UICollectionViewCell {

    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    public func configure(med: FeedMedia, height: Binding<CGFloat>, numMedia: Int) {
        var controller: UIViewController
        controller = UIHostingController(rootView: MediaCell(med: med, height: height, numMedia: numMedia))
        controller.view.frame = self.bounds
        self.addSubview(controller.view)
    }
    
    override func prepareForReuse() {
        let theSubviews: Array = (self.subviews)
        for view in theSubviews
        {
            view.removeFromSuperview()
        }
    }

}


struct WMediaSlider: UIViewRepresentable {
    
    @Binding var media: [FeedMedia]
    @Binding var scroll: String
    @Binding var height: CGFloat
    @Binding var pageNum: Int
    
    var maxHeight: CGFloat = 0
    
    func makeUIView(context: Context) -> UICollectionView {
  
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()

        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        
        layout.minimumInteritemSpacing = 0

        layout.minimumLineSpacing = 0

        layout.scrollDirection = UICollectionView.ScrollDirection.horizontal

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    
        collectionView.register(MediaSliderCell.self, forCellWithReuseIdentifier: "MediaSliderCell")
        
        collectionView.backgroundColor = UIColor.white
//        collectionView.backgroundColor = UIColor(displayP3Red: 248.0/255.0, green: 248.0/255.0, blue: 248.0/255.0, alpha: 1.0)
        
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        
        let dataSource = UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>(collectionView: collectionView) { collectionView, indexPath, modelObj in

            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MediaSliderCell", for: indexPath) as? MediaSliderCell {

                cell.configure(med: modelObj, height: self.$height, numMedia: self.media.count)
                
                return cell
            }

            return MediaSliderCell()
        }
        
    
        populate(dataSource: dataSource)
        context.coordinator.dataSource = dataSource

        collectionView.delegate = context.coordinator
        
        return collectionView
    }
    
    func updateUIView(_ uiView: UICollectionView, context: Context) {

        
        let dataSource = context.coordinator.dataSource
        populate(dataSource: dataSource!)


    }
    


    func populate(dataSource: UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>) {
        
        var snapshot = NSDiffableDataSourceSnapshot<MediaSliderSection, FeedMedia>()
 
        snapshot.appendSections([.main])

        snapshot.appendItems(self.media)
        
        dataSource.apply(snapshot, animatingDifferences: true)
        
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

        
        // delegate
        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            
            var tempHeight = collectionView.frame.height - 2
            if tempHeight < 0 {
                tempHeight = 0
            }
            
//            print("frame: \(collectionView.frame.width) height: \(tempHeight)")
            return CGSize(width: collectionView.frame.width, height: tempHeight)
            
            
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let pageWidth = scrollView.frame.size.width
            let page = Int(floor((scrollView.contentOffset.x - pageWidth / 2) / pageWidth) + 1)
            self.parent.pageNum = page
            
        }

        
    }
}




