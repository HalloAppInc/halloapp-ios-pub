//
//  WUITableView.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI


struct WUITableView: UIViewRepresentable {
    
    
    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView()
        
        tableView.delegate = context.coordinator
        
        return tableView
    }
    
    func updateUIView(_ uiView: UITableView, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITableViewDelegate {
        var parent: WUITableView
        
        init(_ tableView: WUITableView) {
            self.parent = tableView
        }
        

    }
}


