//
//  HalloApp
//
//  Created by Tony Jiang on 5/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjack
import Combine
import CoreData
import Foundation
import UIKit
import SwiftUI

class MediaPreviewController: UIViewController {
    
    enum PreviewType: Int {
        case media = 0
        case quoted = 1
    }
    
    private var chatMessage: ChatMessage?
    private var previewType: PreviewType = .media
    private var mediaIndex: Int = 0
    
    init(for chatMessage: ChatMessage, previewType: PreviewType, mediaIndex: Int) {
        DDLogDebug("ChatMediaPreview/init")
        self.chatMessage = chatMessage
        self.previewType = previewType
        self.mediaIndex = mediaIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        DDLogInfo("MediaPreviewController/viewDidLoad")
        super.viewDidLoad()  
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        self.navigationItem.title = ""
        self.navigationItem.standardAppearance = .transparentAppearance

        self.view.backgroundColor = UIColor.systemGray6
                
        if self.previewType == .quoted {
            if let quoted = self.chatMessage?.quoted {
                
                if let media = quoted.media {
                    
                    if let med = media.first(where: { $0.order == chatMessage!.feedPostMediaIndex }) {
                        
                        let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)
                        
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            self.imageView.image = image
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
        } else if previewType == .media {
            if let media = self.chatMessage?.media {
                
                if let med = media.first(where: { $0.order == self.mediaIndex }) {
                    
                    let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)
                    
                    if med.type == .image {
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            self.imageView.image = image
                            self.view.addSubview(self.imageView)

                        }
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
    
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapToClose))
        self.view.addGestureRecognizer(tap)
        self.view.isUserInteractionEnabled = true
    }
    
    // MARK: Appearance
    
    private lazy var imageView: ZoomableImageView = {
        let view = ZoomableImageView(frame: self.view.bounds)
        view.contentMode = .scaleAspectFit
        self.view.addSubview(view)

        view.translatesAutoresizingMaskIntoConstraints = false
        view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        return view
    }()
    
    @objc(cancelAction) private func cancelAction() {
        self.dismiss(animated: true)
    }
    
    @objc(tapToClose) private func tapToClose() {
        self.dismiss(animated: true)
    }
}


