//
//  MediaCell.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/31/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct MediaCell: View {
    
    @ObservedObject var med: FeedMedia
    @Binding var height: CGFloat
    var numMedia: Int = 0 // used to position the picture in the middle or not
    
    var body: some View {

        VStack(spacing: 0) {
            
            if numMedia > 1 && med.image.size.width > 0 && med.image.size.height < height {
                Spacer()
            }
            
            HStack(spacing: 0) {
                    
                if (med.image.size.width > 0) { // important, app crashes without this check
                    
//                    Button(action: {
//
//                    }) {
//
//                      Image(uiImage: med.image)
//                            .renderingMode(.original)
//                          .resizable()
//                          .aspectRatio(med.image.size, contentMode: .fit)
//                          .background(Color.gray)
//                          .cornerRadius(10)
//                          .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
//                          .frame(height: height)
//
//                    }
//                    .buttonStyle(BorderlessButtonStyle())
                
                    Image(uiImage: med.image)
                          .renderingMode(.original)
                        .resizable()
                        .aspectRatio(med.image.size, contentMode: .fit)
                        .background(Color.gray)
                        .cornerRadius(10)
                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                        .frame(height: height)
                    .pinchToZoom()
                    
                    
                    
                } else {
       
                    VStack() {
                        Spacer()
                        Image(systemName: "photo")
                            .foregroundColor(Color.gray)
                        Spacer()
                    }.frame(height: height)
                    
           
                        
                }
   
            }
            Spacer()
        }
        .padding(0)
        
        
    }
}

