//
//  VideoUtils.swift
//  Halloapp
//
//  Created by Tony Jiang on 3/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import AVFoundation
import SwiftUI

import UIKit
import AVKit

class VideoUtils {

    
    func cropVideo(sourceURL: URL, startTime: Double, endTime: Double, completion: ((_ outputUrl: URL) -> Void)? = nil)
    {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let asset = AVAsset(url: sourceURL)
        let length = Float(asset.duration.value) / Float(asset.duration.timescale)
        print("video length: \(length) seconds")

        var outputURL = documentDirectory.appendingPathComponent("output")
        do {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
            outputURL = outputURL.appendingPathComponent("\(sourceURL.lastPathComponent).mp4")
        }catch let error {
            print(error)
        }

        //Remove existing file
        try? fileManager.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        let timeRange = CMTimeRange(start: CMTime(seconds: startTime, preferredTimescale: 1000),
                                    end: CMTime(seconds: Double(length), preferredTimescale: 1000))

        exportSession.timeRange = timeRange
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("exported at \(outputURL)")
                completion?(outputURL)
            case .failed:
                print("failed \(exportSession.error.debugDescription)")
            case .cancelled:
                print("cancelled \(exportSession.error.debugDescription)")
            default: break
            }
        }
    }
    
   func compressFile(inputUrl: URL, outputUrl: URL, completion:@escaping (URL)->Void){
       //video file to make the asset
      
       var audioFinished = false
       var videoFinished = false
      
      
       let asset = AVAsset(url: inputUrl);
      
       //create asset reader
    
        var assetReader: AVAssetReader?
    
       do{
        assetReader = try AVAssetReader(asset: asset)
       } catch{
           assetReader = nil
       }
      
       guard let reader = assetReader else{
           fatalError("Could not initalize asset reader probably failed its try catch")
       }
      
    let videoTrack = asset.tracks(withMediaType: AVMediaType.video).first!
    let audioTrack = asset.tracks(withMediaType: AVMediaType.audio).first!

      
    let videoReaderSettings: [String:Any] =  [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB ]
    
    
    //Write video size
    let x:CGFloat = 0.1
    let numPixels = UIScreen.main.bounds.width * UIScreen.main.bounds.height
    //bits per pixel
    let bitsPerPixel = pow(2.0, x) // 'x' is the value you want to change for the compression
    var bitrate = numPixels * bitsPerPixel
    
    bitrate = CGFloat(2000000)
    
    
    print("bitrate: \(bitrate)")
    
    
       // ADJUST BIT RATE OF VIDEO HERE
      
//       let videoSettings:[String:Any] = [
//           AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
//           AVVideoCodecKey: AVVideoCodecType.h264,
//           AVVideoHeightKey: videoTrack.naturalSize.height,
//           AVVideoWidthKey: videoTrack.naturalSize.width
//       ]

           let videoSettings:[String:Any] = [
               AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
               AVVideoCodecKey: AVVideoCodecType.h264,
               AVVideoHeightKey: videoTrack.naturalSize.height,
               AVVideoWidthKey: videoTrack.naturalSize.width
           ]
      
       let assetReaderVideoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
       let assetReaderAudioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
      
      
       if reader.canAdd(assetReaderVideoOutput){
           reader.add(assetReaderVideoOutput)
       }else{
           fatalError("Couldn't add video output reader")
       }
      
       if reader.canAdd(assetReaderAudioOutput){
           reader.add(assetReaderAudioOutput)
       }else{
           fatalError("Couldn't add audio output reader")
       }
      
    let audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: nil)
    let videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
       videoInput.transform = videoTrack.preferredTransform
       //we need to add samples to the video input
      
       let videoInputQueue = DispatchQueue(label: "videoQueue")
       let audioInputQueue = DispatchQueue(label: "audioQueue")
      
        var assetWriter: AVAssetWriter?
    
       do{
        assetWriter = try AVAssetWriter(outputURL: outputUrl, fileType: AVFileType.mov)
       }catch{
           assetWriter = nil
       }
       guard let writer = assetWriter else{
           fatalError("assetWriter was nil")
       }
      
       writer.shouldOptimizeForNetworkUse = true
       writer.add(videoInput)
       writer.add(audioInput)
      
      
       writer.startWriting()
       reader.startReading()
    writer.startSession(atSourceTime: CMTime.zero)
      
      
       let closeWriter:()->Void = {
           if (audioFinished && videoFinished){
               assetWriter!.finishWriting(completionHandler: {
                  
                   let newSize = self.size(url: (assetWriter?.outputURL)!)
                  
                    print("newSize: \(newSize)")
                
                   completion((assetWriter?.outputURL)!)
                  
               })
              
               assetReader!.cancelReading()

           }
       }

      
       audioInput.requestMediaDataWhenReady(on: audioInputQueue) {
           while(audioInput.isReadyForMoreMediaData){
               let sample = assetReaderAudioOutput.copyNextSampleBuffer()
               if (sample != nil){
                   audioInput.append(sample!)
               }else{
                   audioInput.markAsFinished()
                   DispatchQueue.main.async {
                       audioFinished = true
                       closeWriter()
                   }
                   break;
               }
           }
       }
      
       videoInput.requestMediaDataWhenReady(on: videoInputQueue) {
           //request data here
          
           while(videoInput.isReadyForMoreMediaData){
               let sample = assetReaderVideoOutput.copyNextSampleBuffer()
               if (sample != nil){
                   videoInput.append(sample!)
               }else{
                   videoInput.markAsFinished()
                   DispatchQueue.main.async {
                       videoFinished = true
                       closeWriter()
                   }
                   break;
               }
           }

       }
      
      
   }

    func size(url: URL?) -> Double {
        guard let filePath = url?.path else {
            return 0.0
        }
        do {
            let attribute = try FileManager.default.attributesOfItem(atPath: filePath)
            if let size = attribute[FileAttributeKey.size] as? NSNumber {
                return size.doubleValue / 1000000.0
            }
        } catch {
            print("Error: \(error)")
        }
        return 0.0
    }

    func resolutionForLocalVideo(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
    
}
