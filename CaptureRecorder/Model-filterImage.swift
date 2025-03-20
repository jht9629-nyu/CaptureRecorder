//
//  Model-filer.swift
//  CaptureRecorder
//
//  Created by jht2 on 3/20/25.
//

import SwiftUI
import AVFoundation
//import Photos
import CoreImage.CIFilterBuiltins

enum VideoEffect: String, CaseIterable {
  case normal = "Normal"
  case mono = "Mono"
  case crystallize = "Crystallize"
  case comic = "Comic"
  case bloom = "Bloom"
  case pixellate = "Pixellate"
  case thermal = "Thermal"
  case sepia = "Sepia"
  case vignette = "Vignette"
  var filterName: String? {
    switch self {
    case .normal: return nil
    case .mono: return "CIPhotoEffectMono"
    case .pixellate: return "CIPixellate"
    case .comic: return "CIComicEffect"
    case .bloom: return "CIBloom"
    case .thermal: return "CIFalseColor"
    case .sepia: return "CISepiaTone"
    case .vignette: return "CIVignette"
    case .crystallize: return "CICrystallize"
    }
  }
}

// Apply the filter and preview
//
extension Model {
  func filterImage(_ pixelBuffer: CVPixelBuffer) -> (CIImage,Bool) {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    var filteredImage = ciImage
    var changed = false
    if let filterName = currentEffect.filterName {
      //      print("filterName: \(filterName)")
      if let filter = CIFilter(name: filterName) {
//        print("filterImage filter.inputKeys: \(filter.inputKeys)")
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
        case .thermal:
          filter.setValue(CIColor.red, forKey: "inputColor0")
          //          filter.setValue(CIColor.yellow, forKey: "inputColor1")
          filter.setValue(CIColor.green, forKey: "inputColor1")
        case .bloom:
          // inputRadius
          // inputIntensity
          filter.setValue(2.0, forKey: kCIInputIntensityKey)
          filter.setValue(40.0, forKey: kCIInputRadiusKey)
        case .crystallize:
          // inputRadius
          // inputCenter CIVector
          filter.setValue(40.0, forKey: "inputRadius")
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

// https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html


