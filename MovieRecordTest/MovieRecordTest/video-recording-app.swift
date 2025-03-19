import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var selectedFilter: FilterType = .normal
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraModel: cameraModel, selectedFilter: $selectedFilter)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Filter selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(FilterType.allCases, id: \.self) { filter in
                            Button(action: {
                                selectedFilter = filter
                            }) {
                                Text(filter.rawValue)
                                    .foregroundColor(selectedFilter == filter ? .white : .gray)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(selectedFilter == filter ? Color.blue : Color.black.opacity(0.6))
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.6))
                
                // Recording controls
                HStack(spacing: 40) {
                    Button(action: {
                        // Toggle recording
                        isRecording.toggle()
                        if isRecording {
                            cameraModel.startRecording(with: selectedFilter)
                        } else {
                            cameraModel.stopRecording()
                        }
                    }) {
                        Circle()
                            .fill(isRecording ? Color.red : Color.white)
                            .frame(width: 80, height: 80)
                            .overlay(
                                isRecording ?
                                    RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .frame(width: 30, height: 30) : nil
                            )
                    }
                    
                    Button(action: {
                        cameraModel.switchCamera()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            cameraModel.checkPermissions()
        }
    }
}

// Enum for available filters
enum FilterType: String, CaseIterable {
    case normal = "Normal"
    case sepia = "Sepia"
    case noir = "Noir"
    case comic = "Comic"
    case thermal = "Thermal"
    case vibrant = "Vibrant"
}

// Camera preview using UIViewRepresentable
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraModel: CameraModel
    @Binding var selectedFilter: FilterType
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        cameraModel.preview = AVCaptureVideoPreviewLayer(session: cameraModel.session)
        cameraModel.preview.frame = view.frame
        cameraModel.preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(cameraModel.preview)
        
        // Start session
        DispatchQueue.global(qos: .userInitiated).async {
            cameraModel.session.startRunning()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update filter if needed
        cameraModel.updateFilter(to: selectedFilter)
    }
}

class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    var session = AVCaptureSession()
    var preview: AVCaptureVideoPreviewLayer!
    
    private var videoDevice: AVCaptureDevice?
    private var audioDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput = AVCaptureVideoDataOutput()
    private var audioOutput = AVCaptureAudioDataOutput()
    
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var currentFilter: FilterType = .normal
    private var context = CIContext()
    
    private var isSessionReady = false
    private var isRecordingSession = false
    private var videoURL: URL?
    private var startTime: CMTime?
    
    override init() {
        super.init()
        setupSession()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.setupSession()
                }
            }
        default:
            break
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            break
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        
        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        self.videoDevice = videoDevice
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                self.videoInput = videoInput
            }
        } catch {
            print("Error setting up video input: \(error)")
            return
        }
        
        // Audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else { return }
        self.audioDevice = audioDevice
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                self.audioInput = audioInput
            }
        } catch {
            print("Error setting up audio input: \(error)")
        }
        
        // Video output
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }
        }
        
        // Audio output
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
        
        session.commitConfiguration()
        isSessionReady = true
    }
    
    func switchCamera() {
        guard let currentPosition = videoDevice?.position else { return }
        
        // Stop session for configuration
        session.beginConfiguration()
        
        // Remove current input
        session.removeInput(videoInput!)
        
        // Get new camera position
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return }
        
        // Add new input
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoInput = newInput
                videoDevice = newDevice
            }
        } catch {
            print("Error switching camera: \(error)")
        }
        
        // Fix video orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if newPosition == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        session.commitConfiguration()
    }
    
    func updateFilter(to filter: FilterType) {
        currentFilter = filter
    }
    
    func startRecording(with filter: FilterType) {
        currentFilter = filter
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "video_\(Date().timeIntervalSince1970).mp4"
        videoURL = documentsPath.appendingPathComponent(filename)
        
        guard let videoURL = videoURL else { return }
        
        do {
            // Create asset writer
            assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
            
            // Video settings
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080
            ]
            
            // Create video writer input
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            // Create pixel buffer adaptor for filter application
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            if assetWriter!.canAdd(videoWriterInput!) {
                assetWriter!.add(videoWriterInput!)
            }
            
            // Audio settings
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100.0,
                AVEncoderBitRateKey: 128000
            ]
            
            // Create audio writer input
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput?.expectsMediaDataInRealTime = true
            
            if assetWriter!.canAdd(audioWriterInput!) {
                assetWriter!.add(audioWriterInput!)
            }
            
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
    
    func stopRecording() {
        isRecordingSession = false
        
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        
        assetWriter?.finishWriting { [weak self] in
            DispatchQueue.main.async {
                // Save video to photo library
                if let videoURL = self?.videoURL {
                    UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
                    print("Video saved at: \(videoURL)")
                }
                
                self?.assetWriter = nil
                self?.videoWriterInput = nil
                self?.audioWriterInput = nil
                self?.pixelBufferAdaptor = nil
                self?.startTime = nil
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        
        // Handle video frame
        if mediaType == kCMMediaType_Video {
            if isRecordingSession {
                processVideoFrame(sampleBuffer)
            }
        }
        
        // Handle audio sample
        if mediaType == kCMMediaType_Audio && isRecordingSession {
            if let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData {
                let currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                if startTime == nil {
                    startTime = currentSampleTime
                }
                
                let adjustedTime = CMTimeSubtract(currentSampleTime, startTime ?? .zero)
                audioInput.append(sampleBuffer)
            }
        }
    }
    
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
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
                    context.render(filteredImage, to: newPixelBuffer)
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

@main
struct VideoFilterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
