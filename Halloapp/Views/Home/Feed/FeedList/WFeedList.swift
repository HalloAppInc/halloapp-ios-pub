//
//  WFeedList.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct WFeedList: UIViewRepresentable {
    
    var isOnProfilePage: Bool
    
    var items: [FeedDataItem]
    
    @Binding var showSheet: Bool
    
    @Binding var showMessages: Bool
    
    @Binding var lastClickedComment: String
    
    @Binding var scroll: String
    
    @Binding var pageNum: Int
    
    @ObservedObject var homeRouteData: HomeRouteData
    @ObservedObject var contacts: Contacts
    
    var paging: (Int) -> Void
    
    var getItemMedia: (String) -> Void
    
    var removeItemMedia: (String) -> Void
    
    var setItemCellHeight: (String, Int) -> Void
    
    func makeUIView(context: Context) -> UICollectionView {
  
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()

        let width = UIScreen.main.bounds.width

        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 65, right: 0)
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 20

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        collectionView.register(WFeedListHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "WFeedListHeader")
        collectionView.register(WFeedListCell.self, forCellWithReuseIdentifier: "WFeedListCell")

        collectionView.backgroundColor = UIColor.systemGroupedBackground
        collectionView.showsVerticalScrollIndicator = false

        let dataSource = UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>(collectionView: collectionView) { collectionView, indexPath, model in
            
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "WFeedListCell", for: indexPath) as? WFeedListCell {

//                if (model.media.count > 0) {
//                    cell.configure(item: model,
//
//                                   showSheet: self.$showSheet,
//                                   showMessages: self.$showMessages,
//                                   lastClickedComment: self.$lastClickedComment,
//                                   scroll: self.$scroll,
//                                   contacts: self.contacts)
//                }
                
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

                            headerView.configure(isOnProfilePage: self.isOnProfilePage, contacts: self.contacts)

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

//        print("items count: \(items.count)")
        
        if (self.isOnProfilePage) {
            
            let profileItems = self.items.filter {
                return $0.username == self.contacts.xmpp.userData.phone
            }
            snapshot.appendItems(profileItems)
            
        } else {
            
            snapshot.appendItems(self.items)
        }
        
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
        @State var scroll: String = ""
        
        
        init(_ view: WFeedList) {
            self.parent = view
        }
        
        // delegate
        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {

            let item = dataSource!.itemIdentifier(for: indexPath)
            
//            print("mediaHeight: \(item!.mediaHeight) cellHeight: \(item!.cellHeight)")
            
            if item!.cellHeight == -1 {
                
//                item!.media = FeedMediaCore().getInfo(feedItemId: item!.itemId)
                
                print("finding cellHeight: \(item!.media.count)")
                
                let controller = UIHostingController(rootView: FeedListCell(isOnProfilePage: self.parent.isOnProfilePage,
                                                                                item: item!,
                                                                                    showSheet: self.$showSheet,
                                                                                    showMessages: self.$showMessages,
                                                                                    lastClickedComment: self.$lastClickedComment,
                                                                                    scroll: self.$temp,
                                                                                    homeRouteData: self.parent.homeRouteData,
                                                                                    contacts: self.parent.contacts))

                let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))

                var newHeight = size.height
                
            
                if item!.media.count == 0 {
                    newHeight = size.height + CGFloat(item!.mediaHeight)
                }
                
                
                print("-> \(newHeight)")
                
                self.parent.setItemCellHeight(item!.itemId, Int(newHeight))
                
                return CGSize(width: collectionView.frame.width, height: newHeight)

        //            return CGSize(width: collectionView.frame.width, height: 525.33)
            } else {
//                print("already have cellHeight: \(item!.cellHeight)")
                return CGSize(width: collectionView.frame.width, height: CGFloat(item!.cellHeight))
                
            }
            
        }
        
        
        
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {

            let controller = UIHostingController(rootView: FeedListHeader(isOnProfilePage: self.parent.isOnProfilePage, contacts: self.parent.contacts))
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            
            return CGSize(width: collectionView.frame.width, height: size.height)
        }
        
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
//            let pageHeight = scrollView.frame.size.height
//            let page = Int(floor((scrollView.contentOffset.y - pageHeight / 2) / pageHeight) + 1)
//            self.parent.pageNum = page
            
//            print("-->  page: \(page)")
//            self.parent.paging(page)
            
        }
        
        
        func collectionView(_ collectionView: UICollectionView, willDisplay c: UICollectionViewCell, forItemAt: IndexPath) {

            let cell = c as! WFeedListCell

            let item = dataSource!.itemIdentifier(for: forItemAt)

            self.parent.getItemMedia(item!.itemId)
            
            if item == nil {
                return
            }

//            let media = FeedMediaCore().get(feedItemId: item!.itemId)
//
//            cell.configure(item: item!,
//
//                           showSheet: self.parent.$showSheet,
//                           showMessages: self.parent.$showMessages,
//                           lastClickedComment: self.parent.$lastClickedComment,
//                           scroll: self.parent.$scroll,
//                           contacts: self.parent.contacts)

//            item!.media = FeedMediaCore().get(feedItemId: item!.itemId)
//            print("media: \(item!.media.count)")

            var controller: UIViewController

            
            
            controller = UIHostingController(rootView: FeedListCell(isOnProfilePage: self.parent.isOnProfilePage,
                                                                    item: item!,
                                                                    showSheet: self.parent.$showSheet,
                                                                    showMessages: self.parent.$showMessages,
                                                                    lastClickedComment: self.parent.$lastClickedComment,
                                                                    scroll: self.parent.$scroll,
                                                                    homeRouteData: self.parent.homeRouteData,
                                                                    contacts: self.parent.contacts))

            controller.view.frame = cell.bounds
            controller.view.backgroundColor = UIColor.systemGroupedBackground
            cell.addSubview(controller.view)
        
            
        }
        


        
        func collectionView(_ collectionView: UICollectionView, didEndDisplaying c: UICollectionViewCell, forItemAt: IndexPath) {

//            let item = dataSource!.itemIdentifier(for: forItemAt)

//            self.parent.removeItemMedia(item!.itemId)
            
        }
        
        
    }
}

// When using UICollectionViewDiffableDataSource, the model must be Hashable (which enums already are)
enum WFeedListSection {
    case main
}

class WFeedListHeader: UICollectionReusableView {

    public func configure(isOnProfilePage: Bool, contacts: Contacts) {
        
        var controller: UIViewController
        
        controller = UIHostingController(rootView: FeedListHeader(isOnProfilePage: isOnProfilePage, contacts: contacts))

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
    
    public func configure(
        isOnProfilePage: Bool,
                            item: FeedDataItem,
                        
                          showSheet: Binding<Bool>,
                          showMessages: Binding<Bool>,
                          lastClickedComment: Binding<String>,
                          scroll: Binding<String>,
                          homeRouteData: HomeRouteData,
                          contacts: Contacts) {
        
        

        
        var controller: UIViewController
        
        controller = UIHostingController(rootView: FeedListCell(
                                                                isOnProfilePage: isOnProfilePage,
                                                                item: item,
                                                                showSheet: showSheet,
                                                                showMessages: showMessages,
                                                                lastClickedComment: lastClickedComment,
                                                                scroll: scroll,
                                                                homeRouteData: homeRouteData,
                                                                contacts: contacts))

        controller.view.frame = self.bounds

        self.addSubview(controller.view)
        
    }
    
    override func prepareForReuse() {
        
        super.prepareForReuse()
        
        let theSubviews: Array = (self.subviews)
        for view in theSubviews
        {
            view.removeFromSuperview()
        }
        
    }
    

    
}
