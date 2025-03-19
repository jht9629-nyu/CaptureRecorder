//
//  FrameView.swift
//  MovieRecorder
//
//  Created by jht2 on 3/18/25.
//

import SwiftUI

// from: [08-FilterTheWorld](https://github.com/mobilelabclass-itp/08-FilterTheWorld)

struct FrameView: View {
  var image: CGImage?
  private let label = Text("Video feed")
  var body: some View {
    if let image = image {
      GeometryReader { geometry in
        Image(image, scale: 1.0, orientation: .upMirrored, label: label)
          .resizable()
          .scaledToFill()
          .frame(
            width: geometry.size.width,
            height: geometry.size.height,
            alignment: .center)
          .clipped()
      }
    } else {
      EmptyView()
    }
  }
}
