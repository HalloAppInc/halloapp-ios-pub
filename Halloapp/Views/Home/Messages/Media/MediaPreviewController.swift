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
    
    private var previewType: PreviewType = .media
    private var mediaIndex: Int = 0
    private var media: [ChatMedia]? = nil
    private var quotedMedia: [ChatQuotedMedia]? = nil
    
    init(previewType: PreviewType, media: [ChatMedia]?, quotedMedia: [ChatQuotedMedia]?, mediaIndex: Int) {
        DDLogDebug("ChatMediaPreview/init")
        self.previewType = previewType
        self.media = media
        self.quotedMedia = quotedMedia
        self.mediaIndex = mediaIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("MediaPreviewController/viewDidLoad")
        super.viewDidLoad()
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        self.navigationItem.title = ""
        self.navigationItem.standardAppearance = .transparentAppearance

        self.view.backgroundColor = UIColor.systemGray6
                
        if self.previewType == .quoted {
            
            guard let media = quotedMedia else { return }
            
            if let med = media.first {
                
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
            
            
        } else if previewType == .media {
            
            guard let media = media else { return }
            
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
    
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapToClose))
        self.view.addGestureRecognizer(tap)
        self.view.isUserInteractionEnabled = true
    }
    
    // MARK: Appearance
    
    private lazy var imageView: ZoomableImageView = {
        let zoomableView = ZoomableImageView(frame: view.bounds)
        zoomableView.contentMode = .scaleAspectFit
        view.addSubview(zoomableView)

        zoomableView.constrain(to: view)
        return zoomableView
    }()
    
    @objc private func cancelAction() {
        self.dismiss(animated: true)
    }
    
    @objc private func tapToClose() {
        self.dismiss(animated: true)
    }
}

