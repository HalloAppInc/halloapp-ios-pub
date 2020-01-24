//
//  WUICollectionView.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

// When using UICollectionViewDiffableDataSource, the model must be Hashable (which enums already are)
enum MySection {
    case main
}

class MyHeaderFooterClass: UICollectionReusableView {

    public func configure(model: FeedDataItem, contacts: Contacts) {
        
        var controller: UIViewController
        
        controller = UIHostingController(rootView: CommentHeader(comment: model, contacts: contacts))


        controller.view.frame = self.bounds

        self.addSubview(controller.view)
        
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.purple

        // Customize here

    }

    required init?(coder aDecoder: NSCoder) {
        
        super.init(coder: aDecoder)

    }
    
    

    
}


class CommentCell: UICollectionViewCell {

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    public func configure(model: FeedComment, con: Binding<String>, replyTo: Binding<String>, replyToName: Binding<String>, msgToSend: Binding<String>, contacts: Contacts) {
        
        var controller: UIViewController
        
        controller = UIHostingController(rootView: CommentSubCell(comment: model, scroll: con, replyTo: replyTo, replyToName: replyToName, msgToSend: msgToSend, contacts: contacts))


        controller.view.frame = self.bounds

        self.addSubview(controller.view)
        
//        print("configure: \(self.subviews.count)")
    }
    
    override func prepareForReuse() {
        let theSubviews: Array = (self.subviews)
        for view in theSubviews
        {
            view.removeFromSuperview()
        }
    }

}


struct WUICollectionView: UIViewRepresentable {
    
    @Binding var item: FeedDataItem

    @Binding var comments: [FeedComment]
    
    @Binding var scroll: String
    
    @Binding var replyTo: String
    @Binding var replyToName: String
    
    @Binding var msgToSend: String
    
    @ObservedObject var contacts: Contacts
    
    func makeUIView(context: Context) -> UICollectionView {
  
        //Define Layout here
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()

        //Get device width
        let width = UIScreen.main.bounds.width

        //set section inset as per your requirement.
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 65, right: 0)
        

//        layout.estimatedItemSize = CGSize(width: width, height: 1)
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        
        //set cell item size here
//        layout.itemSize = CGSize(width: width, height: 100)

        
        //set Minimum spacing between 2 items
        layout.minimumInteritemSpacing = 0

        //set minimum vertical line spacing here between two lines in collectionview
        layout.minimumLineSpacing = 0


//        layout.headerReferenceSize = CGSize(width: 30, height: 30)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        let collectionViewHeaderFooterReuseIdentifier = "MyHeaderFooterClass"
        collectionView.register(MyHeaderFooterClass.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: collectionViewHeaderFooterReuseIdentifier)

//        collectionView.register(MyHeaderFooterClass.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: collectionViewHeaderFooterReuseIdentifier)
        
        collectionView.register(CommentCell.self, forCellWithReuseIdentifier: "CommentCell")
        
//        collectionView.backgroundColor = UIColor(displayP3Red: 248.0/255.0, green: 248.0/255.0, blue: 248.0/255.0, alpha: 1.0)
        
        collectionView.backgroundColor = UIColor.white
        
        let dataSource = UICollectionViewDiffableDataSource<MySection, FeedComment>(collectionView: collectionView) { collectionView, indexPath, modelObj in

            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CommentCell", for: indexPath) as? CommentCell {

                cell.configure(model: modelObj, con: self.$scroll,
                               replyTo: self.$replyTo, replyToName: self.$replyToName, msgToSend: self.$msgToSend,
                               contacts: self.contacts)
                
                return cell
            }

            return CommentCell()
        }
        
        func configureHeader() {
            dataSource.supplementaryViewProvider = { (
               collectionView: UICollectionView,
               kind: String,
               indexPath: IndexPath) -> UICollectionReusableView? in

               let collectionViewHeaderFooterReuseIdentifier = "MyHeaderFooterClass"

               switch kind {

                    case UICollectionView.elementKindSectionHeader:
                        if let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: collectionViewHeaderFooterReuseIdentifier, for: indexPath) as? MyHeaderFooterClass {

                        headerView.configure(model: self.item, contacts: self.contacts)

                        return headerView
                        }
                        return MyHeaderFooterClass()

//                   case UICollectionView.elementKindSectionFooter:
//                       let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: collectionViewHeaderFooterReuseIdentifier, for: indexPath)
//
//                       footerView.backgroundColor = UIColor.green
//                       return footerView

                    default:
                       assert(false, "Unexpected element kind")
                
                }
                return MyHeaderFooterClass()
            }
        }
        
        configureHeader()
        
        populate(dataSource: dataSource)
        context.coordinator.dataSource = dataSource

        collectionView.delegate = context.coordinator
        
        
        return collectionView
    }
    
    func updateUIView(_ uiView: UICollectionView, context: Context) {
//        print("updateUIView")
//        print("comments count: \(comments.count)")
        
        let dataSource = context.coordinator.dataSource

        populate(dataSource: dataSource!)
        

//        print("scroll: \(scroll)")
        
        if scroll == "0" && comments.count > 0 {
            
//            let rect = uiView.layoutAttributesForItem(at: IndexPath(row: 0, section: 0))?.frame
//            uiView.scrollRectToVisible(rect!, animated: true)
            
//            let sectionNumber = 0

//            uiView.scrollToItem(
//                at: NSIndexPath.init(row:(uiView.numberOfItems(inSection: sectionNumber)) - 1, section: sectionNumber) as IndexPath,
//                at: UICollectionView.ScrollPosition.top,
//                animated: true
//            )
            
//            let attributes = uiView.collectionViewLayout.layoutAttributesForSupplementaryViewOfKind(UICollectionElementKindSectionHeader, atIndexPath: NSIndexPath(item: 0, section: 0) as IndexPath)
//            uiView.setContentOffset(CGPoint(x: 0, y: 0 - uiView.contentInset.top), animated: true)
            
            UIView.animate(withDuration: 0.5, animations: {
//                uiView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
                uiView.scrollToItem(at: IndexPath(item: 0, section: 0), at: UICollectionView.ScrollPosition.bottom, animated: false)
            })
            
//            uiView.scrollToItem(
//                at: NSIndexPath.init(row: 1, section: sectionNumber) as IndexPath,
//                at: UICollectionView.ScrollPosition.top,
//                animated: true
//            )
            
        }
        

        
    }
    


    func populate(dataSource: UICollectionViewDiffableDataSource<MySection, FeedComment>) {
        
        var snapshot = NSDiffableDataSourceSnapshot<MySection, FeedComment>()
 
        snapshot.appendSections([.main])

        snapshot.appendItems(self.comments)
        
        dataSource.apply(snapshot, animatingDifferences: true)
        
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
        
        var parent: WUICollectionView
        
        var dataSource: UICollectionViewDiffableDataSource<MySection, FeedComment>?
        
        @State var temp: String = ""
        
        init(_ view: WUICollectionView) {
            self.parent = view
        }
        
        // delegate
        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {

            let item = dataSource!.itemIdentifier(for: indexPath)
            let controller = UIHostingController(rootView: CommentSubCell(comment: item!, scroll: self.$temp,
                                                                          replyTo: self.$temp,
                                                                          replyToName: self.$temp,
                                                                          msgToSend: self.$temp,
                                                                          contacts: self.parent.contacts))
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))

            return CGSize(width: collectionView.frame.width, height: size.height)
        }
        

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {

            let controller = UIHostingController(rootView: CommentHeader(comment: self.parent.item, contacts: self.parent.contacts))
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            
            return CGSize(width: collectionView.frame.width, height: size.height)
        }

//        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
//            return CGSize(width: collectionView.frame.width, height: 50)
//        }
        
        
    }
}



