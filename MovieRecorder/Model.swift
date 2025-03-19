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
  
  var videoOutput: AVCaptureMovieFileOutput?
  var videoDataOutput: AVCaptureVideoDataOutput?
  private var videoInput: AVCaptureDeviceInput?
  private var currentEffect: VideoEffect = .normal
  private var videoWriter: AVAssetWriter?
  private var videoWriterInput: AVAssetWriterInput?
  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var context: CIContext?
  
  private var assetWriter: AVAssetWriter?
//  private var videoWriterInput: AVAssetWriterInput?
  private var audioWriterInput: AVAssetWriterInput?
//  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  
  private var currentFilter: FilterType = .normal

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
    
    // Add video input
    if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                            for: .video,
                                            position: .front) {
      do {
        videoInput = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(videoInput!) {
          session.addInput(videoInput!)
        }
      } catch {
        print("Error setting up video input: \(error)")
      }
    }
    
    // Add audio input
    //    if let audioDevice = AVCaptureDevice.default(for: .audio) {
    //      do {
    //        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
    //        if session.canAddInput(audioInput) {
    //          session.addInput(audioInput)
    //        }
    //      } catch {
    //        print("Error setting up audio input: \(error)")
    //      }
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
    
    // Remove existing file
    if FileManager.default.fileExists(atPath: tempFilePath) {
      try? FileManager.default.removeItem(atPath: tempFilePath)
    }
    
    videoOutput.startRecording(to: fileURL, recordingDelegate: self)
  }
  
  func stopRecording() {
    videoOutput?.stopRecording()
  }
  
  // MARK: - AVCaptureFileOutputRecordingDelegate
  
  func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    guard error == nil else {
      print("Error recording video: \(error!)")
      return
    }
    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
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
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    // Apply effect
    var filteredImage: CIImage = ciImage
    if let filterName = currentEffect.filterName {
      //      print("filterName: \(filterName)")
      if let filter = CIFilter(name: filterName) {
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        // Set additional parameters for specific filters
        switch currentEffect {
        case .pixellate:
          filter.setValue(10, forKey: kCIInputScaleKey)
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
          //          print("outputImage = filter.outputImage")
        } else {
          print("no filter.outputImage")
        }
      } else {
        print("filter = CIFilter(name: filterName)")
      }
    }
    
    // Render filtered image back to the pixel buffer
    guard let context = context else { return  }
    //    context.render(filteredImage, to: pixelBuffer)
    
    //    let orientedImage = filteredImage.oriented(.up) // Change this based on the actual orientation
    // Create UIImage for preview
    //    if let cgImage = context.createCGImage(orientedImage, from: filteredImage.extent) {
    if let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent) {
      //      let uiImage = UIImage(cgImage: cgImage)
      DispatchQueue.main.async {
        self.previewImage = cgImage
      }
    }
  }
}


//

// Enum for available filters
enum FilterType: String, CaseIterable {
  case normal = "Normal"
  case sepia = "Sepia"
  case noir = "Noir"
  case comic = "Comic"
  case thermal = "Thermal"
  case vibrant = "Vibrant"
}

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
    
    if currentFilter != .normal {
      // Create CIImage from pixel buffer
      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      var filteredImage: CIImage?
      
      switch currentFilter {
      case .sepia:
        let filter = CIFilter.sepiaTone()
        filter.inputImage = ciImage
        filter.intensity = 0.8
        filteredImage = filter.outputImage
        
      case .noir:
        let filter = CIFilter.photoEffectNoir()
        filter.inputImage = ciImage
        filteredImage = filter.outputImage
        
      case .comic:
        let filter = CIFilter.comicEffect()
        filter.inputImage = ciImage
        filteredImage = filter.outputImage
        
      case .thermal:
        let filter = CIFilter.falseColor()
        filter.inputImage = ciImage
        filter.setValue(CIColor.red, forKey: "inputColor0")
        filter.setValue(CIColor.yellow, forKey: "inputColor1")
        filteredImage = filter.outputImage
        
      case .vibrant:
        let filter = CIFilter.vibrance()
        filter.inputImage = ciImage
        filter.setValue(50, forKey: "inputAmount")
        filteredImage = filter.outputImage
        
      default:
        filteredImage = ciImage
      }
      
      if let filteredImage = filteredImage {
        // Create a new pixel buffer
        var newPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,
                            CVPixelBufferGetWidth(pixelBuffer),
                            CVPixelBufferGetHeight(pixelBuffer),
                            kCVPixelFormatType_32BGRA,
                            nil,
                            &newPixelBuffer)
        
        if let newPixelBuffer = newPixelBuffer {
          context!.render(filteredImage, to: newPixelBuffer)
          filteredBuffer = newPixelBuffer
        }
      }
    }
    
    // Append filtered buffer to asset writer
    if let pixelBufferAdaptor = pixelBufferAdaptor {
      pixelBufferAdaptor.append(filteredBuffer, withPresentationTime: adjustedTime)
    }
  }
}
