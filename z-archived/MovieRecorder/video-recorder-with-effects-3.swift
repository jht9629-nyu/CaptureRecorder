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
    
    private var videoOutput: AVCaptureMovieFileOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var currentEffect: VideoEffect = .normal
    private var context: CIContext?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init() {
        super.init()
        context = CIContext(options: nil)
        setupSession()
    }
    
    func checkPermissions() {
        // Check camera permissions
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.session.startRunning()
                    }
                }
            }
        } else if cameraAuthStatus == .authorized {
            DispatchQueue.main.async {
                self.session.startRunning()
            }
        }
        
        // Check photo library permissions
        let photoAuthStatus = PHPhotoLibrary.authorizationStatus()
        if photoAuthStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization { _ in }
        }
    }
    
    func setupSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Create a session
            self.session = AVCaptureSession()
            
            // Configure the session for high quality video
            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }
            
            self.session.beginConfiguration()
            
            // Add video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(videoInput) else {
                print("Failed to set up video input")
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(videoInput)
            
            // Add audio input
            guard let audioDevice = AVCaptureDevice.default(for: .audio),
                  let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                  self.session.canAddInput(audioInput) else {
                print("Failed to set up audio input")
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(audioInput)
            
            // Set up video data output for processing frames
            self.videoDataOutput = AVCaptureVideoDataOutput()
            guard let videoDataOutput = self.videoDataOutput,
                  self.session.canAddOutput(videoDataOutput) else {
                print("Failed to set up video data output")
                self.session.commitConfiguration()
                return
            }
            
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            self.session.addOutput(videoDataOutput)
            
            // Set the connection properties
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            }
            
            // Set up movie file output for recording
            self.videoOutput = AVCaptureMovieFileOutput()
            guard let videoOutput = self.videoOutput,
                  self.session.canAddOutput(videoOutput) else {
                print("Failed to set up movie file output")
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(videoOutput)
            
            // Set the connection properties for recording
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            }
            
            self.session.commitConfiguration()
            
            // Start running the session on a background thread
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    func changeEffect(to effect: VideoEffect) {
        currentEffect = effect
        print("Changed effect to: \(effect.rawValue)")
    }
    
    func startRecording() {
        guard let videoOutput = videoOutput, session.isRunning else {
            print("Cannot start recording: session not running")
            return
        }
        
        if videoOutput.isRecording {
            print("Already recording")
            return
        }
        
        // Create a unique file URL
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = formatter.string(from: Date())
        let tempFilename = "video-\(dateString).mp4"
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(tempFilename)
        
        // Remove any existing file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        print("Starting recording to: \(fileURL.path)")
        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
    }
    
    func stopRecording() {
        guard let videoOutput = videoOutput, videoOutput.isRecording else {
            print("Not recording")
            return
        }
        
        print("Stopping recording")
        videoOutput.stopRecording()
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Recording started to: \(fileURL.path)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error recording video: \(error)")
            return
        }
        
        print("Recording finished to: \(outputFileURL.path)")
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            print("Error: Recorded file does not exist")
            return
        }
        
        // Save to photo library
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                print("Photo library access not authorized")
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { saved, error in
                if saved {
                    print("Video saved to photo library")
                    DispatchQueue.main.async {
                        self.videoSaved = true
                    }
                } else if let error = error {
                    print("Error saving to photo library: \(error)")
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip processing if using normal (no effect)
        guard currentEffect != .normal else { return }
        
        // Get the pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Could not get pixel buffer")
            return
        }
        
        // Lock the base address
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        // Create CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply filter
        guard let filterName = currentEffect.filterName,
              let filter = CIFilter(name: filterName) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }
        
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Configure filter parameters
        switch currentEffect {
        case .sepia:
            filter.setValue(0.7, forKey: kCIInputIntensityKey)
        case .pixellate:
            filter.setValue(10.0, forKey: kCIInputScaleKey)
        case .vignette:
            filter.setValue(0.5, forKey: kCIInputIntensityKey)
            filter.setValue(1.0, forKey: kCIInputRadiusKey)
        default:
            break
        }
        
        // Get filtered image
        guard let outputImage = filter.outputImage else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }
        
        // Create a new buffer to hold the filtered image
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        // Render filter output back to the original pixel buffer
        guard let context = self.context else { return }
        context.render(outputImage, to: pixelBuffer)
        
        print("Applied \(currentEffect.rawValue) effect to frame")
    }
}

// MARK: - SwiftUI View for Camera Preview
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
