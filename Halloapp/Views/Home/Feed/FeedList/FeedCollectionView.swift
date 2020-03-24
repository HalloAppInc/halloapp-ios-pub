//
//  WFeedList.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct FeedCollectionView: UIViewRepresentable {
    private let cellReuseIdentifier = "WFeedListCell"
    private let headerReuseIdentifier = "WFeedListHeader"

    @EnvironmentObject var mainViewController: MainViewController

    var isOnProfilePage: Bool
    var items: [FeedDataItem]
    var getItemMedia: (String) -> Void
    var setItemCellHeight: (String, Int) -> Void

    func makeUIView(context: Context) -> UICollectionView {
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 20

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(WFeedListHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: headerReuseIdentifier)
        collectionView.register(WFeedListCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        collectionView.backgroundColor = UIColor.systemGroupedBackground

        let dataSource = UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>(collectionView: collectionView) { collectionView, indexPath, model in
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: self.cellReuseIdentifier, for: indexPath) as? WFeedListCell {
//                if (model.media.count > 0) {
//                    cell.configure(item: model)
//                }
                
                return cell
            }
            return WFeedListCell()
        }
        
        dataSource.supplementaryViewProvider = {(
           collectionView: UICollectionView,
           kind: String,
           indexPath: IndexPath) -> UICollectionReusableView? in

           switch kind {
                case UICollectionView.elementKindSectionHeader:
                    if let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "WFeedListHeader", for: indexPath) as? WFeedListHeader {
                        headerView.configure(isOnProfilePage: self.isOnProfilePage)
                        return headerView
                    }
                    return WFeedListHeader()

                default:
                   assert(false, "Unexpected element kind")

            }
            return WFeedListHeader()
        }

        populate(dataSource: dataSource)
        context.coordinator.dataSource = dataSource

        collectionView.delegate = context.coordinator
                
        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        uiView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: BottomBarView.currentBarHeight(), right: 0);
        uiView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: BottomBarView.currentBarHeight(), right: 0);

        let dataSource = context.coordinator.dataSource
        populate(dataSource: dataSource!)
//        if scroll == "0" {
//            UIView.animate(withDuration: 0.5, animations: {
//                uiView.scrollToItem(at: IndexPath(item: uiView.numberOfItems(inSection: 0) - 1, section: 0), at: UICollectionView.ScrollPosition.bottom, animated: false)
//            })
//        }
    }

    func populate(dataSource: UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>) {
        var snapshot = NSDiffableDataSourceSnapshot<WFeedListSection, FeedDataItem>()
        snapshot.appendSections([.main])
        if (self.isOnProfilePage) {
            ///TODO: compare by sender id, not name
            let profileItems = self.items.filter {
                return $0.username == AppContext.shared.userData.phone
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
        private var parent: FeedCollectionView
        var dataSource: UICollectionViewDiffableDataSource<WFeedListSection, FeedDataItem>?
        
        @State var temp: String = ""

        init(_ view: FeedCollectionView) {
            self.parent = view
        }
        
        // delegate
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let item = dataSource!.itemIdentifier(for: indexPath)
            var cellHeight: CGFloat = (CGFloat)(item!.cellHeight)
            if cellHeight == -1 {
//                item!.media = FeedMediaCore().getInfo(feedItemId: item!.itemId)
                
                ///TODO: calculate row height without creating cell
                let controller = UIHostingController(rootView: FeedItemView(item: item!))
                let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))

                let newHeight = size.height
                self.parent.setItemCellHeight(item!.itemId, Int(newHeight))
                
                cellHeight = newHeight
            }
            ///TODO: check if it is possible to use automatic cell width here
            return CGSize(width: collectionView.frame.width, height: cellHeight)
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
            var sectionHeight: CGFloat = 0
            if (self.parent.isOnProfilePage) {
                let controller = UIHostingController(rootView: FeedHeaderView(isOnProfilePage: self.parent.isOnProfilePage))
                sectionHeight = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude)).height
            }
            return CGSize(width: collectionView.frame.width, height: sectionHeight)
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay c: UICollectionViewCell, forItemAt: IndexPath) {
            let cell = c as! WFeedListCell
            let item = dataSource!.itemIdentifier(for: forItemAt)
            self.parent.getItemMedia(item!.itemId)
            
            guard item != nil else { return }

//            let media = FeedMediaCore().get(feedItemId: item!.itemId)
//
//            cell.configure(item: item!)

//            item!.media = FeedMediaCore().get(feedItemId: item!.itemId)
//            print("media: \(item!.media.count)")

            let controller = UIHostingController(rootView: FeedItemView(item: item!))
            controller.view.frame = cell.bounds
            controller.view.backgroundColor = UIColor.clear
            cell.addSubview(controller.view)
        }
    }
}


// When using UICollectionViewDiffableDataSource, the model must be Hashable (which enums already are)
enum WFeedListSection {
    case main
}


struct FeedHeaderView: View {
    var isOnProfilePage: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if (isOnProfilePage) {
                ///TODO: make this tapable
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color.gray)
                    .clipShape(Circle())
                    .frame(width: 50, height: 50, alignment: .center)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

                Text("\(AppContext.shared.userData.phone)")
            }
        }
        .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
        .background(Color(UIColor.systemGroupedBackground))
    }
}


class WFeedListHeader: UICollectionReusableView {
    public func configure(isOnProfilePage: Bool) {
        let controller = UIHostingController(rootView: FeedHeaderView(isOnProfilePage: isOnProfilePage))
        controller.view.frame = self.bounds
        controller.view.backgroundColor = UIColor.systemGroupedBackground
        self.addSubview(controller.view)
    }
}


struct FeedItemView: View {
    private let contactStore = AppContext.shared.contactStore

    var item: FeedDataItem

    @State private var showSheet: Bool = false
    @State private var localUnreadComments: Int = 0
    
    var body: some View {
        
        return VStack(spacing: 0) {
            HStack() {
                HStack(spacing: 10) {
                    // Profile picture
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color.gray)
                        .clipShape(Circle())
                        .frame(width: 30, height: 30, alignment: .center)

                    // Contact name
                    Text(self.contactStore.fullName(for: item.username))
                        .font(.system(.headline))
                }

                Spacer()

                // Timestamp
                Text(Utils().timeForm(dateStr: String(item.timestamp)))
                    .foregroundColor(Color.secondary)
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .buttonStyle(BorderlessButtonStyle())

            // Media
            if item.mediaHeight > -1 {
                MediaSlider(item, item.mediaHeight)
            } else {
                // Extra space above text if no media
                Divider()
                    .frame(height: 10)
                    .hidden()
            }

            // Text / Media Comment
            if (!item.text.isEmpty) {
                HStack() {
                    Text(item.text)
                        .font(.system(size: 16, weight: .light))
                    Spacer()
                }.padding(EdgeInsets(top: 0, leading: 20, bottom: 15, trailing: 20))
            }

            Divider()

            HStack {
                // Comment button
                NavigationLink(destination: CommentsView(item: item).navigationBarTitle("Comments", displayMode: .inline).edgesIgnoringSafeArea(.bottom)) {
                    HStack {
                        Image(systemName: "message")
                            .font(.system(size: 20, weight: .regular))
                            .padding(.zero)

                        Text("Comment")

                        // Green Dot if there are unread comments
                        if (self.localUnreadComments > 0) {
                            Image(systemName: "circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color.green)
                                .clipShape(Circle())
                                .frame(width: 10, height: 10, alignment: .center)
                                .padding(EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 0))
                        }
                    }
                    // careful on padding, greater than 15 on sides wraps on smaller phones
                    .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                }

                Spacer()

                // Message button
                if (AppContext.shared.userData.phone != item.username) {
                    Button(action: {
                        self.showSheet = true
                    }) {
                        HStack {
                            Image(systemName: "envelope")
                                .font(.system(size: 20, weight: .regular))
                                .padding(.zero)

                            Text("Message")
                        }
                        .padding(EdgeInsets(top: 10, leading: 25, bottom: 10, trailing: 25))
                    }
                }
            }
            .foregroundColor(Color.primary)
            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
            .buttonStyle(BorderlessButtonStyle())
        }

        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color(UIColor.systemGray5), radius: 5)
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

        .sheet(isPresented: self.$showSheet, content: {
            MessageUser(onDismiss: {
                self.showSheet = false
            })
        })
        
        .onAppear {
            self.localUnreadComments = self.item.unreadComments
        }
        /* used to catch changes to num comments */
        .onReceive(self.item.commentsChange) { num in
            self.localUnreadComments = num
        }
        
    }
}


class WFeedListCell: UICollectionViewCell {
    public func configure(item: FeedDataItem) {
        let controller = UIHostingController(rootView: FeedItemView(item: item))
        controller.view.frame = self.bounds
        self.addSubview(controller.view)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        let theSubviews: Array = (self.subviews)
        for view in theSubviews {
            view.removeFromSuperview()
        }
    }
}
