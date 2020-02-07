//
//  FeedListHeader.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct FeedListHeader: View {
        
    var body: some View {
      
        VStack(spacing: 0) {

            HStack() {

                VStack (spacing: 0) {

                    
                    Spacer()
                }
                
                Spacer()

            }
            
            Spacer()
            
            Divider()
                .padding(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
      
        .padding(EdgeInsets(top: 65, leading: 0, bottom: 10, trailing: 0))
    
        
    }
    

}


