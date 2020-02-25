//
//  UIImage.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import SwiftUI

extension UIImage {
    
    func getNewSize(res: Int) -> UIImage? {

        guard let imageData = self.pngData() else { return nil }

        //    print("orig: \(imageData.count/1000)")

        let options = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: res] as CFDictionary

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        guard let imageReference = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        //    let temp = UIImage(cgImage: imageReference)
        //    let temp2 = temp.pngData()
        //    print("thumb: \(temp2!.count/1000)")
        //    print("percent: \(Float(temp2!.count) / Float(imageData.count))")

        return UIImage(cgImage: imageReference)

    }
}
