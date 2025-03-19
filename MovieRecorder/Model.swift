//
//  CameraViewModel.swift
//  MovieRecorder
//
//  Created by jht2 on 3/18/25.
//

import SwiftUI
import AVFoundation
import Photos
import CoreImage.CIFilterBuiltins


enum VideoEffect: String, CaseIterable {
  case normal = "Normal"
  case pixellate = "Pixellate"
  case comic = "Comic"
  case sepia = "Sepia"
  case mono = "Mono"
  case vignette = "Vignette"
  
  var filterName: String? {
    switch self {
    case .normal: return nil
    case .pixellate: return "CIPixellate"
    case .comic: return "CIComicEffect"
    case .sepia: return "CISepiaTone"
    case .mono: return "CIPhotoEffectMono"
    case .vignette: return "CIVignette"
    }
  }
}

class Model: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
  @Published var session = AVCaptureSession()
  @Published var videoSaved = false
  @Published var previewImage: CGImage?
  @Published var showingSavedAlert = false
  @Published var selectedEffect: VideoEffect = .normal
  
  private var videoDevice: AVCaptureDevice?

  var videoOutput: AVCaptureMovieFileOutput?
  var videoDataOutput: AVCaptureVideoDataOutput?
  private var videoInput: AVCaptureDeviceInput?
  private var currentEffect: VideoEffect = .normal
  private var videoWriter: AVAssetWriter?
  //  private var videoWriterInput: AVAssetWriterInput?
  //  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var context: CIContext?
  
  // -- AVAssetWriter
  private var assetWriter: AVAssetWriter?
  private var videoWriterInput: AVAssetWriterInput?
  private var audioWriterInput: AVAssetWriterInput?
  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
//  private var currentFilter: FilterType = .comic
  private var isSessionReady = false
  private var isRecordingSession = false
  private var videoURL: URL?
  private var startTime: CMTime?
  
  override init() {
    super.init()
    context = CIContext(options: nil)
  }
  
  func checkPermissions() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      break
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        if granted {
          self.setupSession()
        }
      }
    default:
      print("Camera access denied")
    }
    
    switch PHPhotoLibrary.authorizationStatus() {
    case .authorized:
      break
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization { _ in }
    default:
      print("Photo library access denied")
    }
  }
  
  func setupSession() {
    session.beginConfiguration()
    
    // Video input
    guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
    self.videoDevice = videoDevice

    // Add video input
//    if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
//                                            for: .video,
//                                            position: .front) {
      do {
        videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(videoInput!) {
          session.addInput(videoInput!)
        }
      } catch {
        print("Error setting up video input: \(error)")
      }
//    }
    
    // Add video data output for processing frames
    videoDataOutput = AVCaptureVideoDataOutput()
    videoDataOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
    if let videoDataOutput = videoDataOutput, session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
      
      videoDataOutput.videoSettings =
      [kCVPixelBufferPixelFormatTypeKey
       as String: kCVPixelFormatType_32BGRA]
      
      let videoConnection = videoDataOutput.connection(with: .video)
      videoConnection?.videoOrientation = .portrait
      //      videoConnection?.videoRotationAngle = 90.0
    }
    
    // Add movie file output for recording
    videoOutput = AVCaptureMovieFileOutput()
    if let videoOutput = videoOutput, session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
    }
    
    session.commitConfiguration()
    
    DispatchQueue.global(qos: .userInitiated).async {
      self.session.startRunning()
    }
  }
  
  func changeEffect(to effect: VideoEffect) {
    currentEffect = effect
    selectedEffect = effect
  }
  
  func startRecording() {
    guard let videoOutput = videoOutput else { return }
    
    let tempDirectory = NSTemporaryDirectory()
    let tempFilePath = (tempDirectory as NSString).appendingPathComponent("video.mp4")
    let fileURL = URL(fileURLWithPath: tempFilePath)
    
//    print("startRecording fileURL: \(fileURL)")
    
    // Remove existing file
    if FileManager.default.fileExists(atPath: tempFilePath) {
      try? FileManager.default.removeItem(atPath: tempFilePath)
    }
    
    //    videoOutput.startRecording(to: fileURL, recordingDelegate: self)
    startRecording_asset(fileURL);
  }
  
  // Video dimensions - use device native resolution
  private var videoDimensions: CMVideoDimensions {
    guard let videoDevice = videoDevice else {
      return CMVideoDimensions(width: 1920, height: 1080)
    }
    
    let format = videoDevice.activeFormat.formatDescription
    
//    print("videoDimensions format: \(format)")
    
    return CMVideoFormatDescriptionGetDimensions(format)
  }

  func startRecording_asset(_ fileURL: URL ) {
    
//    print("startRecording_asset fileURL: \(fileURL)")
    
    videoURL = fileURL;
    guard let videoURL = videoURL else { return }
    
    do {
      // Create asset writer
      assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
      
      // Get the natural dimensions from the camera
      let dimensions = videoDimensions
      let width = Int(dimensions.width)
      let height = Int(dimensions.height)
      print("startRecording_asset width: \(width) height: \(height)")
      
      // Video settings
      let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: height, // Swap for portrait
        AVVideoHeightKey: width, // Swap for portrait
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
//        AVVideoWidthKey: 1920,
//        AVVideoHeightKey: 1080
      ]
      
      // Create video writer input
      videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
      videoWriterInput?.expectsMediaDataInRealTime = true
      
      // Create pixel buffer adaptor for filter application
      let sourcePixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
//        kCVPixelBufferWidthKey as String: 1920,
//        kCVPixelBufferHeightKey as String: 1080
      ]
      
      pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoWriterInput!,
        sourcePixelBufferAttributes: sourcePixelBufferAttributes
      )
      
      if assetWriter!.canAdd(videoWriterInput!) {
        assetWriter!.add(videoWriterInput!)
      }
      
      // Audio settings -- disabled
      
      // Start writing
      assetWriter!.startWriting()
      assetWriter!.startSession(atSourceTime: .zero)
      
      isRecordingSession = true
      startTime = nil
      
    } catch {
      print("Error setting up asset writer: \(error)")
      assetWriter = nil
      videoWriterInput = nil
      audioWriterInput = nil
      pixelBufferAdaptor = nil
    }
    
  }
  
  func stopRecording_asset() {
    isRecordingSession = false
    videoWriterInput?.markAsFinished()
    audioWriterInput?.markAsFinished()
    assetWriter?.finishWriting { [weak self] in
      DispatchQueue.main.async {
        // Save video to photo library
//        if let videoURL = self?.videoURL {
//          UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
//          print("Video saved at: \(videoURL)")
//        }
        self?.saveRecordingToPhotos()
        self?.assetWriter = nil
        self?.videoWriterInput = nil
        self?.audioWriterInput = nil
        self?.pixelBufferAdaptor = nil
        self?.startTime = nil
      }
    }
  }
  
  func stopRecording() {
    if isRecordingSession {
      stopRecording_asset()
    }
    else {
      videoOutput?.stopRecording()
    }
  }
  
  // MARK: - AVCaptureFileOutputRecordingDelegate
  
  func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    guard error == nil else {
      print("Error recording video: \(error!)")
      return
    }
    print("fileOutput outputFileURL: \(outputFileURL)")
//    PHPhotoLibrary.shared().performChanges({
//      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
//    }) { saved, error in
//      if saved {
//        DispatchQueue.main.async {
//          self.videoSaved = true
//        }
//      } else if let error = error {
//        print("Error saving video to library: \(error)")
//      }
//    }
  }
  
  func saveRecordingToPhotos() {
    print("saveRecordingToPhotos videoURL:", videoURL as Any)
    PHPhotoLibrary.shared().performChanges({
      if let videoURL = self.videoURL {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
      }
    }) { saved, error in
      if saved {
        DispatchQueue.main.async {
          self.videoSaved = true
        }
      } else if let error = error {
        print("Error saving video to library: \(error)")
      }
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension Model: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    
    if isRecordingSession {
      processVideoFrame(sampleBuffer)
      return;
    }
    
    let (_, _) = filterImage(pixelBuffer)
    
  }
  
  // Apply the filter and preview
  //
  func filterImage(_ pixelBuffer: CVPixelBuffer) -> (CIImage,Bool) {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    var filteredImage = ciImage
    var changed = false
    if let filterName = currentEffect.filterName {
      //      print("filterName: \(filterName)")
      if let filter = CIFilter(name: filterName) {
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        // Set additional parameters for specific filters
        switch currentEffect {
        case .pixellate:
          filter.setValue(30, forKey: kCIInputScaleKey)
        case .sepia:
          filter.setValue(0.7, forKey: kCIInputIntensityKey)
        case .vignette:
          filter.setValue(0.5, forKey: kCIInputIntensityKey)
          filter.setValue(1.0, forKey: kCIInputRadiusKey)
        default:
          break
        }
        if let outputImage = filter.outputImage {
          filteredImage = outputImage
          changed = true
          //          print("outputImage = filter.outputImage")
        } else {
          print("no filter.outputImage")
        }
      } else {
        print("no filter = CIFilter(name: filterName)")
      }
    }
    
    // Dispatch update to preview
    if let cgImage = context!.createCGImage(filteredImage, from: filteredImage.extent) {
      DispatchQueue.main.async {
        self.previewImage = cgImage
      }
    }
    
    return (filteredImage,changed)
  }
}

// --

extension Model {
  func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
    guard let videoInput = videoWriterInput, videoInput.isReadyForMoreMediaData,
          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    
    let currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    
    if startTime == nil {
      startTime = currentSampleTime
    }
    
    let adjustedTime = CMTimeSubtract(currentSampleTime, startTime ?? .zero)
    
    // Apply filter based on selection
    var filteredBuffer = pixelBuffer
    let (filteredImage, changed) = filterImage(pixelBuffer)
    
    if changed {
      // Create a new pixel buffer
      var newPixelBuffer: CVPixelBuffer?
      CVPixelBufferCreate(kCFAllocatorDefault,
                          CVPixelBufferGetWidth(pixelBuffer),
                          CVPixelBufferGetHeight(pixelBuffer),
                          kCVPixelFormatType_32BGRA,
                          nil,
                          &newPixelBuffer)
      
      if let newPixelBuffer {
        context!.render(filteredImage, to: newPixelBuffer)
        filteredBuffer = newPixelBuffer
      }
    }
    
    // Append filtered buffer to asset writer
    if let pixelBufferAdaptor {
      pixelBufferAdaptor.append(filteredBuffer, withPresentationTime: adjustedTime)
    }
  }
}
