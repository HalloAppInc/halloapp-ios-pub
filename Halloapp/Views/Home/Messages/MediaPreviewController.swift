//
//  HalloApp
//
//  Created by Tony Jiang on 5/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjack
import Combine
import CoreData
import SwiftUI
import UIKit
import AVKit
import Core

class MediaPreviewController: UIViewController {
    
    private var chatMessage: ChatMessage?
    
    init(for chatMessage: ChatMessage) {
        Log.d("ChatMediaPreview/init")
        self.chatMessage = chatMessage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        Log.i("MediaPreviewController/viewDidLoad")
        super.viewDidLoad()  
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        self.navigationItem.title = ""
        self.navigationItem.standardAppearance = Self.noBorderNavigationBarAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6

        self.view.backgroundColor = UIColor.systemGray6
        
        if let quoted = self.chatMessage?.quoted {

            if let media = quoted.media {
                
                if let med = media.first(where: { $0.order == chatMessage!.feedPostMediaIndex }) {
                  
                    let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)

                    if let image = UIImage(contentsOfFile: fileURL.path) {
                        
                        self.imageView.update(with: image)
                        
                        self.view.addSubview(self.imageView)
                        self.imageView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
                        self.imageView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
                        self.imageView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
                        self.imageView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

                    } else if med.type == .video {

                        let avPlayer = AVPlayer(url: fileURL)

                        let avPlayerController = AVPlayerViewController()
                        avPlayerController.player = avPlayer
                        avPlayerController.showsPlaybackControls = true
                        
                        avPlayerController.willMove(toParent: self)
  
                        self.view.addSubview(avPlayerController.view)
                        self.addChild(avPlayerController)
                        
                        avPlayerController.view.translatesAutoresizingMaskIntoConstraints = false

                        avPlayerController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
                        avPlayerController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
                        avPlayerController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
                        avPlayerController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

                        avPlayerController.didMove(toParent: self)
                    }
                }
            }
        }
    }
    
    // MARK: Appearance

    static var noBorderNavigationBarAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.shadowColor = nil
            return appearance
        }
    }
    
    private lazy var imageView: ImageZoomView = {
        let view = ImageZoomView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    @objc(cancelAction)
    private func cancelAction() {
        self.dismiss(animated: true)
    }
}


