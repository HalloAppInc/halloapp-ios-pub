//
//  WAVPlayer.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import AVKit
import Combine
import SwiftUI

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
        playerController.view.backgroundColor = UIColor.clear
        return playerController
    }

    func updateUIViewController(_ uiViewController: WAVPlayer.UIViewControllerType, context: UIViewControllerRepresentableContext<WAVPlayer>) {
        /*
         disabling swiping to close when AVPlayerViewController is in FullScreen for now as there's an issue
         where the AVPlayerViewController is not in the view controller hierarchy
         furthermore, gesture is disabled in updateUIViewController instead of during makeUIViewController as
         the gesture recognizers are added after viewDidAppear
         */
        uiViewController.disableGestureRecognition()
        return
    }

    class Coordinator: NSObject, UINavigationControllerDelegate {
        var parent: WAVPlayer

        init(_ wAVPlayer: WAVPlayer) {
            self.parent = wAVPlayer
        }
    }
}

extension AVPlayerViewController {
    func disableGestureRecognition() {
        let contentView = view.value(forKey: "contentView") as? UIView
        contentView?.gestureRecognizers = contentView?.gestureRecognizers?.filter {
            $0 is UITapGestureRecognizer
        }
    }
}
