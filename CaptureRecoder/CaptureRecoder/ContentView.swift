//

import SwiftUI
import AVFoundation
import Photos

struct ContentView: View {
  @StateObject private var model = Model()
//  @State private var selectedEffect: VideoEffect = .normal
  @State private var isRecording = false
//  @State private var showingSavedAlert = false
  
  var body: some View {
    ZStack {
      // Camera preview
//      CameraPreviewView(session: model.session)
//        .edgesIgnoringSafeArea(.all)
      
      FrameView(image: model.previewImage)
        .edgesIgnoringSafeArea(.all)

      VStack {
        Spacer()
        // Effect selector
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 5) {
            ForEach(VideoEffect.allCases, id: \.self) { effect in
              Button(action: {
                model.selectedEffect = effect
                model.changeEffect(to: effect)
              }) {
                Text(effect.rawValue)
                  .padding(8)
                  .background(model.selectedEffect == effect ? Color.blue : Color.gray.opacity(0.7))
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
            model.stopRecording()
          } else {
            model.startRecording()
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
        .padding(.bottom, 5)
      }
    }
    .onAppear {
      model.checkPermissions()
      model.setupSession()
    }
    .alert("Video saved to your photo library", isPresented: $model.showingSavedAlert) {
    }
    .onReceive(model.$videoSaved) { saved in
      if saved {
        model.showingSavedAlert = true
        model.videoSaved = false
      }
    }
  }
}



struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
