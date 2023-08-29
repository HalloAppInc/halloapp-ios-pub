//
//  SlideshowSlideViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/24/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import UIKit
import Vision

class SlideshowSlideViewController: UIViewController {

    var mediaItem: FeedMedia? {
        didSet {
            if let mediaItem {
                imageView.configure(with: mediaItem)
            }
        }
    }

    private lazy var imageView: MediaImageView = {
        let imageView = MediaImageView(configuration: .mediaList)
        return imageView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        view.clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func startAnimation() {
        guard let cgImage = imageView.image?.cgImage else {
            return
        }

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])

        guard let results = request.results?.first as? VNSaliencyImageObservation, let salientObjects = results.salientObjects else {
            return
        }
        var unionOfSalientRegions = CGRect.null
        salientObjects.forEach { observation in
            unionOfSalientRegions = unionOfSalientRegions.union(observation.boundingBox)
        }

        let imageRectInView = AVMakeRect(aspectRatio: CGSize(width: cgImage.width, height: cgImage.height), insideRect: view.bounds)

        let salientRect = VNImageRectForNormalizedRect(unionOfSalientRegions, Int(imageRectInView.width), Int(imageRectInView.height))
            .offsetBy(dx: imageRectInView.minX, dy: imageRectInView.minY)

        // create transform
        let transform = CGAffineTransform.identity
            .translatedBy(x: (salientRect.midX - imageRectInView.midX) * 0.5, y: (salientRect.midY - imageRectInView.midY) * 0.5)
            .scaledBy(x: imageRectInView.width / salientRect.width, y: imageRectInView.width / salientRect.width)

        UIView.animate(withDuration: 4.0, delay: 0, options: [.curveEaseInOut]) {
            self.imageView.transform = transform
        }

    }

    func reset() {
        imageView.transform = .identity
    }
}
