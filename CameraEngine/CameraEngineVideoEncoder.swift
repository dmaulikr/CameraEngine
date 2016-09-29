//
//  CameraEngineVideoEncoder.swift
//  CameraEngine2
//
//  Created by Remi Robert on 11/02/16.
//  Copyright © 2016 Remi Robert. All rights reserved.
//

import UIKit
import AVFoundation

public typealias blockHandlerPixelBuffer = (_ sampleBuffer: CVPixelBuffer, _ timestamp: CMTime, _ outputPixelBuffer: CVPixelBuffer) -> (Void)

public enum CameraEngineVideoEncoderEncoderSettings: String {
    case Preset640x480
    case Preset960x540
    case Preset1280x720
    case Preset1920x1080
    case Preset3840x2160
    case Unknow
    
    private func avFoundationPresetString() -> String? {
        switch self {
        case .Preset640x480: return AVOutputSettingsPreset640x480
        case .Preset960x540: return AVOutputSettingsPreset960x540
        case .Preset1280x720: return AVOutputSettingsPreset1280x720
        case .Preset1920x1080: return AVOutputSettingsPreset1920x1080
        case .Preset3840x2160:
            if #available(iOS 9.0, *) {
                return AVOutputSettingsPreset3840x2160
            }
            else {
                return nil
            }
        case .Unknow: return nil
        }
    }
    
    func configuration() -> AVOutputSettingsAssistant? {
        if let presetSetting = self.avFoundationPresetString() {
            return AVOutputSettingsAssistant(preset: presetSetting)
        }
        return nil
    }
    
    public static func availableFocus() -> [CameraEngineVideoEncoderEncoderSettings] {
        return AVOutputSettingsAssistant.availableOutputSettingsPresets().map {
            if #available(iOS 9.0, *) {
                switch $0 {
                case AVOutputSettingsPreset640x480: return .Preset640x480
                case AVOutputSettingsPreset960x540: return .Preset960x540
                case AVOutputSettingsPreset1280x720: return .Preset1280x720
                case AVOutputSettingsPreset1920x1080: return .Preset1920x1080
                case AVOutputSettingsPreset3840x2160: return .Preset3840x2160
                default: return .Unknow
                }
            }
            else {
                switch $0 {
                case AVOutputSettingsPreset640x480: return .Preset640x480
                case AVOutputSettingsPreset960x540: return .Preset960x540
                case AVOutputSettingsPreset1280x720: return .Preset1280x720
                case AVOutputSettingsPreset1920x1080: return .Preset1920x1080
                default: return .Unknow
                }
            }
        }
    }
    
    public func description() -> String {
        switch self {
        case .Preset640x480: return "Preset 640x480"
        case .Preset960x540: return "Preset 960x540"
        case .Preset1280x720: return "Preset 1280x720"
        case .Preset1920x1080: return "Preset 1920x1080"
        case .Preset3840x2160: return "Preset 3840x2160"
        case .Unknow: return "Preset Unknow"
        }
    }
}

extension UIDevice {
    static func orientationTransformation() -> CGFloat {
        switch UIDevice.current.orientation {
        case .portrait: return CGFloat(M_PI / 2)
        case .portraitUpsideDown: return CGFloat(M_PI / 4)
        case .landscapeRight: return CGFloat(M_PI)
        case .landscapeLeft: return CGFloat(M_PI * 2)
        default: return 0
        }
    }
}

class CameraEngineVideoEncoder {
    
    private var assetWriter: AVAssetWriter!
    private var videoInputWriter: AVAssetWriterInput!
    private var audioInputWriter: AVAssetWriterInput!
    private var firstFrame = false
    private var startTime: CMTime!
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    var blockHandlerPixelBuffer: blockHandlerPixelBuffer?
    
    
    lazy var presetSettingEncoder: AVOutputSettingsAssistant? = {
        return CameraEngineVideoEncoderEncoderSettings.Preset1920x1080.configuration()
    }()
    
    private func initVideoEncoder(_ url: URL) {
        self.firstFrame = false
        guard let presetSettingEncoder = self.presetSettingEncoder else {
            print("[Camera engine] presetSettingEncoder = nil")
            return
        }
        
        do {
            self.assetWriter = try AVAssetWriter(url: url, fileType: AVFileTypeMPEG4)
        }
        catch {
            fatalError("error init assetWriter")
        }
        
        let videoOutputSettings = presetSettingEncoder.videoSettings
        let audioOutputSettings = presetSettingEncoder.audioSettings
        
        guard self.assetWriter.canApply(outputSettings: videoOutputSettings, forMediaType: AVMediaTypeVideo) else {
            fatalError("Negative [VIDEO] : Can't apply the Output settings...")
        }
        guard self.assetWriter.canApply(outputSettings: audioOutputSettings, forMediaType: AVMediaTypeAudio) else {
            fatalError("Negative [AUDIO] : Can't apply the Output settings...")
        }
        
        self.videoInputWriter = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoOutputSettings)
        self.videoInputWriter.expectsMediaDataInRealTime = true
        self.videoInputWriter.transform = CGAffineTransform(rotationAngle: UIDevice.orientationTransformation())
        
        self.audioInputWriter = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioOutputSettings)
        self.audioInputWriter.expectsMediaDataInRealTime = true
        
        if self.assetWriter.canAdd(self.videoInputWriter) {
            self.assetWriter.add(self.videoInputWriter)
        }
        if self.assetWriter.canAdd(self.audioInputWriter) {
            self.assetWriter.add(self.audioInputWriter)
        }

        guard let w = videoOutputSettings?[AVVideoWidthKey] as? NSNumber else {fatalError()}
        guard let h = videoOutputSettings?[AVVideoHeightKey] as? NSNumber else {fatalError()}
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInputWriter,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: w.intValue,
                kCVPixelBufferHeightKey as String: h.intValue
            ])
    }
    
    func startWriting(_ url: URL) {
        self.firstFrame = false
        self.startTime = CMClockGetTime(CMClockGetHostTimeClock())
        self.initVideoEncoder(url)
    }
    
    func stopWriting(_ blockCompletion: blockCompletionCaptureVideo?) {
        self.videoInputWriter.markAsFinished()
        self.audioInputWriter.markAsFinished()
        
        self.assetWriter.finishWriting { () -> Void in
            if let blockCompletion = blockCompletion {
                blockCompletion(self.assetWriter.outputURL, nil)
            }
        }
    }
    
    func appendBuffer(_ sampleBuffer: CMSampleBuffer!, isVideo: Bool) {
        if !isVideo && !self.firstFrame {
            return
        }
        
        self.firstFrame = true
        if CMSampleBufferDataIsReady(sampleBuffer) {
            if self.assetWriter.status == AVAssetWriterStatus.unknown {
                let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter.startWriting()
                self.assetWriter.startSession(atSourceTime: startTime)
            }
            if isVideo {
                if let blockHandlerPixelBuffer = blockHandlerPixelBuffer {
                    guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
                        print("error1")
                        return
                    }
                    var outputPixelBuffer: CVPixelBuffer? = nil
                    let result = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)
                    if result != kCVReturnSuccess {
                        print("Cannot obtain a pixel buffer from the buffer pool with error: \(result)")
                        return
                    }
                    guard let inBuf = CMSampleBufferGetImageBuffer(sampleBuffer), let outBuf = outputPixelBuffer else {
                        print("error2")
                        return
                    }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    blockHandlerPixelBuffer(inBuf, timestamp, outBuf)

                    // TODO: PostProcess

                    // write the video data
                    if videoInputWriter.isReadyForMoreMediaData {
                        pixelBufferAdaptor.append(outBuf, withPresentationTime: timestamp)
                    }
                    /*
                     CVPixelBufferRef renderedOutputPixelBuffer = NULL;
                     
                     if (self.pixelBufferAdaptor) {
                     OSStatus err = CVPixelBufferPoolCreatePixelBuffer(nil, self.pixelBufferAdaptor.pixelBufferPool, &renderedOutputPixelBuffer);
                     if (err) {
                     NSLog(@"Cannot obtain a pixel buffer from the buffer pool with error: %d", (int)err);
                     return;
                     }
                     }
                     
                     self.pixelBufferHandler(imageBuffer, timestamp, renderedOutputPixelBuffer);
                     
                     // write the video data
                     if (renderedOutputPixelBuffer != NULL && [self canWriteVideo]) {
                     [self.pixelBufferAdaptor appendPixelBuffer:renderedOutputPixelBuffer withPresentationTime:timestamp];
                     }
                     
                     CVPixelBufferRelease(renderedOutputPixelBuffer);
                     */
                    
                } else if videoInputWriter.isReadyForMoreMediaData {
                    videoInputWriter.append(sampleBuffer)
                }
            }
            else {
                if self.audioInputWriter.isReadyForMoreMediaData {
                    self.audioInputWriter.append(sampleBuffer)
                }
            }
        }
    }
    
    func progressCurrentBuffer(_ sampleBuffer: CMSampleBuffer) -> Float64 {
        let currentTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let currentTime = CMTimeGetSeconds(CMTimeSubtract(currentTimestamp, self.startTime))
        return currentTime
    }
}
