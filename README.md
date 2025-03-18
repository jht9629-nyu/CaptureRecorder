#  MovieRecorder

## video-recorder-with-effects-1.swift

- Movie recorded successfully
- reduced effect to 3
-
- fail: effects not applied
- fail: during effect, buttons shoved off screen
- fail: effect preview affects layout

>> https://chatgpt.com/c/67da0189-fe58-8002-8790-e60a12121373
fix orientation of context.createCGImage

## filtered-video-recorder-app.swift

In AVFoundation AVCaptureSession AVCaptureFileOutputRecordingDelegate correctly apply filters to sample in captureOutput
privide a swiftui app example of this

nothing recorded

## video-recorder-with-effects-2.swift

Crash on record

## video-recorder-with-effects-3.swift

Crash - no video preview

## Details

- https://claude.ai/chat/a6a7974f-915e-461a-b566-635b2ff08929

swiftui code to record movie with video effect applied to each frame


code gives the following error: "Initializer for conditional binding must have Optional type, not 'CIImage'" on line "let ciImage = CIImage(cvPixelBuffer: pixelBuffer) else { return }"

This app has crashed because it attempted to access privacy-sensitive data without a usage description. The app's Info.plist must contain an NSCameraUsageDescription key with a string value explaining to the user how the app uses this data.

This app has crashed because it attempted to access privacy-sensitive data without a usage description.  The app's Info.plist must contain an NSPhotoLibraryUsageDescription key with a string value explaining to the user how the app uses this data.

This app has crashed because it attempted to access privacy-sensitive data without a usage description.  The app's Info.plist must contain an NSMicrophoneUsageDescription key with a string value explaining to the user how the app uses this data.


>> Compiles

>> Crash on record:

Thread 1: "*** -[AVCaptureMovieFileOutput startRecordingToOutputFileURL:recordingDelegate:] No active/enabled connections"

>> Filters not applied

Initializer for conditional binding must have Optional type, not 'CIImage'

    guard let ciImage = CIImage(cvPixelBuffer: pixelBuffer) else {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
      return
    }

>> New crash

*** Terminating app due to uncaught exception 'NSGenericException', reason: '*** -[AVCaptureSession startRunning] startRunning may not be called between calls to beginConfiguration and commitConfiguration'



