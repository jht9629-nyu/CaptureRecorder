import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Camera View Model
class CameraViewModel: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var previewImage: UIImage?
    @Published var recordedVideoURL: URL?
    @Published var filterIntensity: Float = 0.5
    @Published var selectedFilter: FilterType = .sepia
    
    enum FilterType: String, CaseIterable, Identifiable {
        case sepia = "Sepia"
        case noir = "Noir"
        case vibrance = "Vibrance"
        case colorInvert = "Color Invert"
        case none = "No Filter"
        
        var id: String { self.rawValue }
    }
    
    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "videoProcessingQueue")
    private let context = CIContext()
    
    private var videoDevice: AVCaptureDevice?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    func setupCaptureSession() {
        captureSession.beginConfiguration()
        
        // Set up camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Failed to access camera")
            return
        }
        
        self.videoDevice = videoDevice
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        // Set up audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
            print("Failed to access microphone")
            return
        }
        
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        // Set up video data output for processing frames
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        // Set up movie output for recording
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }
        
        captureSession.commitConfiguration()
        
        // Create preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
    }
    
    func startSession() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    func startRecording() {
        guard !movieOutput.isRecording else { return }
        
        let outputPath = NSTemporaryDirectory() + UUID().uuidString + ".mov"
        let outputURL = URL(fileURLWithPath: outputPath)
        
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecording() {
        guard movieOutput.isRecording else { return }
        
        movieOutput.stopRecording()
        isRecording = false
    }
    
    func applyFilter(to ciImage: CIImage) -> CIImage {
        var filteredImage = ciImage
        
        switch selectedFilter {
        case .sepia:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = ciImage
            filter.intensity = filterIntensity
            if let outputImage = filter.outputImage {
                filteredImage = outputImage
            }
            
        case .noir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = ciImage
            if let outputImage = filter.outputImage {
                filteredImage = outputImage
            }
            
        case .vibrance:
            let filter = CIFilter.vibrance()
            filter.inputImage = ciImage
            filter.amount = filterIntensity * 2 - 1 // Scale from 0..1 to -1..1
            if let outputImage = filter.outputImage {
                filteredImage = outputImage
            }
            
        case .colorInvert:
            let filter = CIFilter.colorInvert()
            filter.inputImage = ciImage
            if let outputImage = filter.outputImage {
                filteredImage = outputImage
            }
            
        case .none:
            // No filter
            break
        }
        
        return filteredImage
    }
}

// MARK: - Video Processing for Preview
extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let filteredImage = applyFilter(to: ciImage)
        
        // Create UIImage for preview
        if let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.previewImage = uiImage
            }
        }
    }
}

// MARK: - Recording Delegate
extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Recording finished
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordedVideoURL = outputFileURL
        }
        
        // For real-time filtering during recording, we need to post-process the video
        // This is where we would apply filters to the recorded video if not doing it in real-time
        // For this example, we're showing the filtered preview but recording the unfiltered video
        // A more advanced solution would involve AVAssetWriter to record filtered frames
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let cameraViewModel: CameraViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        if let previewLayer = cameraViewModel.previewLayer {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
    }
}

// MARK: - Camera View
struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showFilterControls = false
    
    var body: some View {
        ZStack {
            // Live camera preview
            CameraPreviewView(cameraViewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Filtered image overlay
            if let previewImage = viewModel.previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Controls
            VStack {
                Spacer()
                
                if showFilterControls {
                    VStack(spacing: 20) {
                        // Filter picker
                        Picker("Filter", selection: $viewModel.selectedFilter) {
                            ForEach(CameraViewModel.FilterType.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Filter intensity slider
                        if viewModel.selectedFilter != .none && viewModel.selectedFilter != .noir && viewModel.selectedFilter != .colorInvert {
                            HStack {
                                Text("Intensity")
                                Slider(value: $viewModel.filterIntensity, in: 0...1)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding()
                }
                
                HStack(spacing: 30) {
                    // Toggle filter controls
                    Button(action: {
                        showFilterControls.toggle()
                    }) {
                        Image(systemName: "camera.filters")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    // Record button
                    Button(action: {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }) {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4)
                            .background(viewModel.isRecording ? Circle().fill(Color.red) : Circle().fill(Color.clear))
                            .frame(width: 70, height: 70)
                    }
                    
                    // Placeholder to balance layout
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 50, height: 50)
                }
                .padding(.bottom, 30)
            }
            
            // Recording indicator
            if viewModel.isRecording {
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("REC")
                            .foregroundColor(.red)
                            .font(.caption)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            }
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let videoURL: URL
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var cameraViewModel = CameraViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                CameraView()
                    .environmentObject(cameraViewModel)
                
                if let videoURL = cameraViewModel.recordedVideoURL {
                    NavigationLink(
                        destination: VideoPlayerView(videoURL: videoURL),
                        label: {
                            Text("View Recording")
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    )
                    .position(x: UIScreen.main.bounds.width / 2, y: 50)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - App Entry Point
@main
struct FilteredCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
