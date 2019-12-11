//
//  LoadingTimer.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct LoadingTimer: View {
    
    @State var timeRemaining = 20
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        return VStack() {
            if (timeRemaining > 0) {
                Text("Optimizing... \(timeRemaining)s")
                    .padding(.top, 100)
                    .onReceive(timer) { _ in
                        
                        if (self.timeRemaining < 0) {
                            self.timer.upstream.connect().cancel()
                        }
                        self.timeRemaining -= 1
                    }
            } else {
                Text("Optimization finishing...")
                    .padding(.top, 100)
            }
        }
    }
}

struct LoadingTimer_Previews: PreviewProvider {
    static var previews: some View {
        LoadingTimer()
    }
}
