//
//  WUICollectionView.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

// This represents the different sections in our UICollectionView. When using UICollectionViewDiffableDataSource, the model must be Hashable (which enums already are)
enum MySection {
    case main
}

// This represents a model object that we would have in our collection. When using UICollectionViewDiffableDataSource, the model must be Hashable
class MyModelObject: Hashable {
    let id = UUID()

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MyModelObject, rhs: MyModelObject) -> Bool {
        return lhs.id == rhs.id
    }
}


struct WUICollectionView: UIViewRepresentable {
    
    
    func makeUIView(context: Context) -> UICollectionView {
  
        //Define Layout here
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()

        //Get device width
        let width = UIScreen.main.bounds.width

        //set section inset as per your requirement.
//        layout.sectionInset = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)

        //set cell item size here
        layout.itemSize = CGSize(width: width / 2, height: width / 2)

        //set Minimum spacing between 2 items
        layout.minimumInteritemSpacing = 20

        //set minimum vertical line spacing here between two lines in collectionview
        layout.minimumLineSpacing = 50


        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
//        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        
        
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "myCell")
        
        let dataSource = UICollectionViewDiffableDataSource<MySection, MyModelObject>(collectionView: collectionView) { collectionView, indexPath, myModelObject in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "myCell", for: indexPath)
            cell.backgroundColor = .red
            
            // ...
            // Do whatever customization you want with your cell here!
            // ...
            
            return cell
        }
        populate(dataSource: dataSource)
        context.coordinator.dataSource = dataSource

        collectionView.delegate = context.coordinator
        
        return collectionView
    }
    
    func updateUIView(_ uiView: UICollectionView, context: Context) {
        
    }
    
    func populate(dataSource: UICollectionViewDiffableDataSource<MySection, MyModelObject>) {
        var snapshot = NSDiffableDataSourceSnapshot<MySection, MyModelObject>()
        snapshot.appendSections([.main])
        snapshot.appendItems([MyModelObject(), MyModelObject(), MyModelObject()])
        dataSource.apply(snapshot)
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: WUICollectionView
        
        var dataSource: UICollectionViewDiffableDataSource<MySection, MyModelObject>?
        
        init(_ view: WUICollectionView) {
            self.parent = view
        }
        

    }
}



