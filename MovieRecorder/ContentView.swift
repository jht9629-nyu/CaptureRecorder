//

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
      
      // Filtered image overlay
      //      if let previewImage = cameraViewModel.previewImage {
      //        Image(uiImage: previewImage)
      //          .resizable()
      //          .aspectRatio(contentMode: .fill)
      //          .edgesIgnoringSafeArea(.all)
      //      }
      
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
    .alert("Video saved to your photo library", isPresented: $showingSavedAlert) {
//      Alert(title: Text("Success"),
//            message: Text("Video saved to your photo library"))
    }
//    .alert(isPresented: $showingSavedAlert) {
//      Alert(title: Text("Success"),
//            message: Text("Video saved to your photo library"))
//    }
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


struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
