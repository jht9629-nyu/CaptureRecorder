import SwiftUI
import AVFoundation
import Photos

struct ContentView: View {
  @StateObject private var cameraViewModel = CameraViewModel()
  @State private var selectedEffect: VideoEffect = .normal
  @State private var isRecording = false
  @State private var showingSavedAlert = false
  
  var body: some View {
    ZStack {
      // Camera preview
      CameraPreviewView(session: cameraViewModel.session)
        .edgesIgnoringSafeArea(.all)
      
      VStack {
        Spacer()
        
        // Effect selector
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 20) {
            ForEach(VideoEffect.allCases, id: \.self) { effect in
              Button(action: {
                selectedEffect = effect
                cameraViewModel.changeEffect(to: effect)
              }) {
                Text(effect.rawValue)
                  .padding(8)
                  .background(selectedEffect == effect ? Color.blue : Color.gray.opacity(0.7))
                  .foregroundColor(.white)
                  .cornerRadius(8)
              }
            }
          }
          .padding()
        }
        .background(Color.black.opacity(0.5))
        
        // Record button
        Button(action: {
          if isRecording {
            cameraViewModel.stopRecording()
          } else {
            cameraViewModel.startRecording()
          }
          isRecording.toggle()
        }) {
          Circle()
            .fill(isRecording ? Color.red : Color.white)
            .frame(width: 70, height: 70)
            .padding()
            .overlay(
              Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 80, height: 80)
            )
        }
        .padding(.bottom, 30)
      }
    }
    .onAppear {
      cameraViewModel.checkPermissions()
      cameraViewModel.setupSession()
    }
    .alert(isPresented: $showingSavedAlert) {
      Alert(title: Text("Success"), message: Text("Video saved to your photo library"), dismissButton: .default(Text("OK")))
    }
    .onReceive(cameraViewModel.$videoSaved) { saved in
      if saved {
        showingSavedAlert = true
        cameraViewModel.videoSaved = false
      }
    }
  }
}

enum VideoEffect: String, CaseIterable {
  case normal = "Normal"
  case sepia = "Sepia"
  case mono = "Mono"
  case comic = "Comic"
  case pixellate = "Pixellate"
  case vignette = "Vignette"
  
  var filterName: String? {
    switch self {
    case .normal: return nil
    case .sepia: return "CISepiaTone"
    case .mono: return "CIPhotoEffectMono"
    case .comic: return "CIComicEffect"
    case .pixellate: return "CIPixellate"
    case .vignette: return "CIVignette"
    }
  }
}

class CameraViewModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
  @Published var session = AVCaptureSession()
  @Published var videoSaved = false
  
  var videoOutput: AVCaptureMovieFileOutput?
  var videoDataOutput: AVCaptureVideoDataOutput?
  private var videoInput: AVCaptureDeviceInput?
  private var currentEffect: VideoEffect = .normal
  private var videoWriter: AVAssetWriter?
  private var videoWriterInput: AVAssetWriterInput?
  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var context: CIContext?
  
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
    if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
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
    if let audioDevice = AVCaptureDevice.default(for: .audio) {
      do {
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        if session.canAddInput(audioInput) {
          session.addInput(audioInput)
        }
      } catch {
        print("Error setting up audio input: \(error)")
      }
    }
    
    // Add video data output for processing frames
    videoDataOutput = AVCaptureVideoDataOutput()
    videoDataOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
    if let videoDataOutput = videoDataOutput, session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
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
extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard currentEffect != .normal,
          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    // Apply effect
    let filteredImage: CIImage
    if let filterName = currentEffect.filterName {
      if let filter = CIFilter(name: filterName) {
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Set additional parameters for specific filters
        switch currentEffect {
        case .sepia:
          filter.setValue(0.7, forKey: kCIInputIntensityKey)
        case .pixellate:
          filter.setValue(10, forKey: kCIInputScaleKey)
        case .vignette:
          filter.setValue(0.5, forKey: kCIInputIntensityKey)
          filter.setValue(1.0, forKey: kCIInputRadiusKey)
        default:
          break
        }
        
        if let outputImage = filter.outputImage {
          filteredImage = outputImage
        } else {
          filteredImage = ciImage
        }
      } else {
        filteredImage = ciImage
      }
    } else {
      filteredImage = ciImage
    }
    
    // Render filtered image back to the pixel buffer
    guard let context = context else { return }
    context.render(filteredImage, to: pixelBuffer)
  }
}

// MARK: - SwiftUI View for Camera Preview
struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: UIScreen.main.bounds)
    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.frame = view.bounds
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)
    return view
  }
  
  func updateUIView(_ uiView: UIView, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
