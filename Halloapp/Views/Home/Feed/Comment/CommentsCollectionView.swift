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

///TODO: use just one class
struct RootCommentView: View {
    var comment: FeedDataItem

    @ObservedObject var contacts: Contacts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Profile picture
                Button(action: { }) {
                    Image(systemName: "circle.fill")
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .foregroundColor(Color.gray)
                        .frame(width: 30, height: 30, alignment: .center)
                }

                // Name + Comment
                // Timestamp
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.contacts.getName(phone: comment.username))
                        .font(.system(size: 14, weight: .bold))

                    +

                    Text("   \(comment.text)")
                        .font(.system(size: 15, weight: .regular))

                    Text(Utils().timeForm(dateStr: String(comment.timestamp)))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.secondary)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))

            Divider()
        }
    }
}

class CommentHeaderView: UICollectionReusableView {
    public func configure(model: FeedDataItem, contacts: Contacts) {
        let controller = UIHostingController(rootView: RootCommentView(comment: model, contacts: contacts))
        controller.view.frame = self.bounds
        self.addSubview(controller.view)
    }
}


struct CommentView: View {
    var comment: FeedComment

    @Binding var scroll: String
    @Binding var replyTo: String
    @Binding var replyToName: String
    @Binding var msgToSend: String

    @ObservedObject var contacts: Contacts

    @State private var UserImage = Image(systemName: "nosign")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Profile picture
                Button(action: { }) {
                    Image(systemName: "circle.fill")
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .foregroundColor(Color.gray)
                        .frame(width: 30, height: 30, alignment: .center)
                }

                // Name + Comment
                // Timestamp + "Reply" button
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.contacts.getName(phone: comment.username))
                        .font(.system(size: 14, weight: .bold))

                    +

                    Text("   \(comment.text)")
                        .font(.system(size: 15, weight: .regular))

                    HStack(spacing: 16) {
                        Text(Utils().timeForm(dateStr: String(comment.timestamp)))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.secondary)

                        Button(action: {
                            self.replyTo = self.comment.id
                            self.replyToName = self.contacts.getName(phone: self.comment.username)
                            if (self.replyToName != "Me") {
                                self.msgToSend = ""
                            } else {
                                self.msgToSend = ""
                            }
                        }) {
                            Text("Reply")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.secondary)
                        }

                        Spacer()
                    }
                }
            }
            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
        }
        .padding(EdgeInsets(top: 0, leading: self.comment.parentCommentId == "" ? 0 : 20, bottom: 0, trailing: 0))
    }
}

class CommentCell: UICollectionViewCell {
    public func configure(model: FeedComment, con: Binding<String>, replyTo: Binding<String>, replyToName: Binding<String>, msgToSend: Binding<String>, contacts: Contacts) {
        let controller = UIHostingController(rootView: CommentView(comment: model, scroll: con, replyTo: replyTo, replyToName: replyToName, msgToSend: msgToSend, contacts: contacts))
        controller.view.frame = self.bounds
        self.addSubview(controller.view)
    }
    
    override func prepareForReuse() {
        let theSubviews: Array = (self.subviews)
        for view in theSubviews {
            view.removeFromSuperview()
        }
    }
}


struct CommentsCollectionView: UIViewRepresentable {
    static let cellReuseIdentifier = "CommentCell"
    static let headerReuseIdentifier = "MyHeaderFooter"

    @Binding var item: FeedDataItem

    @Binding var comments: [FeedComment]
    
    @Binding var scroll: String
    
    @Binding var replyTo: String
    @Binding var replyToName: String
    @Binding var msgToSend: String
    
    @ObservedObject var contacts: Contacts
    
    func makeUIView(context: Context) -> UICollectionView {
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 65, right: 0)
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(CommentHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: CommentsCollectionView.headerReuseIdentifier)
        collectionView.register(CommentCell.self, forCellWithReuseIdentifier: CommentsCollectionView.cellReuseIdentifier)
        collectionView.backgroundColor = UIColor.systemBackground
        
        let dataSource = UICollectionViewDiffableDataSource<MySection, FeedComment>(collectionView: collectionView) { collectionView, indexPath, modelObj in
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CommentsCollectionView.cellReuseIdentifier, for: indexPath) as? CommentCell {
                cell.configure(model: modelObj,
                               con: self.$scroll,
                               replyTo: self.$replyTo,
                               replyToName: self.$replyToName,
                               msgToSend: self.$msgToSend,
                               contacts: self.contacts)
                return cell
            }
            return CommentCell()
        }
        
        dataSource.supplementaryViewProvider = {(
           collectionView: UICollectionView,
           kind: String,
           indexPath: IndexPath) -> UICollectionReusableView? in

           switch kind {
                case UICollectionView.elementKindSectionHeader:
                    if let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: CommentsCollectionView.headerReuseIdentifier, for: indexPath) as? CommentHeaderView {
                        headerView.configure(model: self.item, contacts: self.contacts)
                        return headerView
                    }
                    return CommentHeaderView()

           default:
                   assert(false, "Unexpected element kind")

            }
            return CommentHeaderView()
        }

        populate(dataSource: dataSource)
        context.coordinator.dataSource = dataSource
        collectionView.delegate = context.coordinator

        return collectionView
    }
    
    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let dataSource = context.coordinator.dataSource
        populate(dataSource: dataSource!)
        if scroll == "0" && comments.count > 0 {
            UIView.animate(withDuration: 0.5, animations: {
                uiView.scrollToItem(at: IndexPath(item: uiView.numberOfItems(inSection: 0) - 1, section: 0), at: UICollectionView.ScrollPosition.bottom, animated: false)
            })
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
        var parent: CommentsCollectionView
        var dataSource: UICollectionViewDiffableDataSource<MySection, FeedComment>?
        
        @State var temp: String = ""
        
        init(_ view: CommentsCollectionView) {
            self.parent = view
        }
        
        // delegate
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let item = dataSource!.itemIdentifier(for: indexPath)
            let controller = UIHostingController(rootView: CommentView(comment: item!,
                                                                       scroll: self.$temp,
                                                                       replyTo: self.$temp,
                                                                       replyToName: self.$temp,
                                                                       msgToSend: self.$temp,
                                                                       contacts: self.parent.contacts))
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: collectionView.frame.width, height: size.height)
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
            let controller = UIHostingController(rootView: RootCommentView(comment: self.parent.item, contacts: self.parent.contacts))
            let size = controller.view.sizeThatFits(CGSize(width: collectionView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: collectionView.frame.width, height: size.height)
        }
    }
}
