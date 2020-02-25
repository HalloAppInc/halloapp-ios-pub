//
//  WAVPlayer.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

import AVKit
import AVFoundation

struct WAVPlayer: UIViewControllerRepresentable {

    typealias UIViewControllerType = AVPlayerViewController
  
    var videoURL: URL?
    
    private var player: AVPlayer {
        return AVPlayer(url: videoURL!)
    }
    
    func makeCoordinator() -> WAVPlayer.Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<WAVPlayer>) -> WAVPlayer.UIViewControllerType {
        
        let playerController = AVPlayerViewController()
        playerController.player = player
        
//        playerController.view.isUserInteractionEnabled = true

        return playerController

    }

    func updateUIViewController(_ uiViewController: WAVPlayer.UIViewControllerType, context: UIViewControllerRepresentableContext<WAVPlayer>) {
        return
    }

    class Coordinator: NSObject, UINavigationControllerDelegate {

        var parent: WAVPlayer

        init(_ wAVPlayer: WAVPlayer) {
            self.parent = wAVPlayer
        }
        
    }

}
