//
//  WFeedList.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

// When using UICollectionViewDiffableDataSource, the model must be Hashable (which enums already are)
enum WFeedListSection {
    case main
}

class WFeedListHeader: UICollectionReusableView {

    public func configure() {
        
        var controller: UIViewController
        
        controller = UIHostingController(rootView: FeedListHeader())

        controller.view.frame = self.bounds

        self.addSubview(controller.view)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Customize here
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}


class WFeedListCell: UICollectionViewCell {

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    public func configure(item: FeedDataItem,
                          showSheet: Binding<Bool>,
                          showMessages: Binding<Bool>,
                          lastClickedComment: Binding<String>,
                          scroll: Binding<String>,
                          contacts: Contacts) {
        
        var controller: UIViewController
        
        controller = UIHostingController(rootView: FeedListCell(
                                                                item: item,
                                                                showSheet: showSheet,
                                                                showMessages: showMessages,
                                                                lastClickedComment: lastClickedComment,
                                                                scroll: scroll,
                                                                contacts: contacts))

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


struct WFeedList: UIViewRepresentable {
    
    @Binding var items: [FeedDataItem]
    
    @Binding var showSheet: Bool
    
    @Binding var showMessages: Bool
    
    @Binding var lastClickedComment: String
    
    @Binding var scroll: String
    
    @ObservedObject var contacts: Contacts
    
    func makeUIView(context: Context) -> UICollectionView {
  
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()

        let width = UIScreen.main.bounds.width

        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 65, right: 0)
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        collectionView.register(WFeedListHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "WFeedListHeader")
        collectionView.register(WFeedListCell.self, forCellWithReuseIdentifier: "WFeedListCell")
        
//        collectionView.backgroundColor = UIColor(displayP3Red: 248.0/255.0, green: 248.0/255.0, blue: 248.0/255.0, alpha: 1.0)
        collectionView.backgroundColor = UIColor.white
        
        let dataSource = UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>(collectionView: collectionView) { collectionView, indexPath, model in

            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "WFeedListCell", for: indexPath) as? WFeedListCell {

                cell.configure(item: model,
                               showSheet: self.$showSheet,
                               showMessages: self.$showMessages,
                               lastClickedComment: self.$lastClickedComment,
                               scroll: self.$scroll,
                               contacts: self.contacts)
                
                return cell
            }

            return WFeedListCell()
        }
        
        func configureHeader() {
            dataSource.supplementaryViewProvider = { (
               collectionView: UICollectionView,
               kind: String,
               indexPath: IndexPath) -> UICollectionReusableView? in

               switch kind {

                    case UICollectionView.elementKindSectionHeader:
                        if let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "WFeedListHeader", for: indexPath) as? WFeedListHeader {

                            headerView.configure()

                            return headerView
                        }
                        return WFeedListHeader()

                    default:
                       assert(false, "Unexpected element kind")
                
                }
                return WFeedListHeader()
            }
        }
        
        configureHeader()
        
        populate(dataSource: dataSource)
        context.coordinator.dataSource = dataSource

        collectionView.delegate = context.coordinator
                
        return collectionView
    }
    
    
    func updateUIView(_ uiView: UICollectionView, context: Context) {
        
        let dataSource = context.coordinator.dataSource

        populate(dataSource: dataSource!)
                
        if scroll == "0" {
            UIView.animate(withDuration: 0.5, animations: {
                uiView.scrollToItem(at: IndexPath(item: uiView.numberOfItems(inSection: 0) - 1, section: 0), at: UICollectionView.ScrollPosition.bottom, animated: false)
            })
        }
    
    }
    

    func populate(dataSource: UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>) {
        
        var snapshot = NSDiffableDataSourceSnapshot<WFeedListSection, FeedDataItem>()
 
        snapshot.appendSections([.main])

        snapshot.appendItems(self.items)
        
        dataSource.apply(snapshot, animatingDifferences: true)
        
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
        
        var parent: WFeedList
        
        var dataSource: UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>?
        
        @State var temp: String = ""
        @State var showSheet: Bool = false
        @State var showMessages: Bool = false
        @State var lastClickedComment: String = ""
        
        init(_ view: WFeedList) {
            self.parent = view
        }
        
        // delegate
        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {

            let item = dataSource!.itemIdentifier(for: indexPath)
            
            let controller = UIHostingController(rootView: FeedListCell(item: item!,
                                                                        showSheet: self.$showSheet,
                                                                        showMessages: self.$showMessages,
                                                                        lastClickedComment: self.$lastClickedComment,
                                                                        scroll: self.$temp,
                                                                        contacts: self.parent.contacts))
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))

            return CGSize(width: collectionView.frame.width, height: size.height)
        }
        

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {

            let controller = UIHostingController(rootView: FeedListHeader())
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            
            return CGSize(width: collectionView.frame.width, height: size.height)
        }
        
        
    }
}

