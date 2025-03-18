#  MovieRecorder

- https://claude.ai/chat/a6a7974f-915e-461a-b566-635b2ff08929

swiftui code to record movie with video effect applied to each frame


code gives the following error: "Initializer for conditional binding must have Optional type, not 'CIImage'" on line "let ciImage = CIImage(cvPixelBuffer: pixelBuffer) else { return }"

This app has crashed because it attempted to access privacy-sensitive data without a usage description. The app's Info.plist must contain an NSCameraUsageDescription key with a string value explaining to the user how the app uses this data.

This app has crashed because it attempted to access privacy-sensitive data without a usage description.  The app's Info.plist must contain an NSPhotoLibraryUsageDescription key with a string value explaining to the user how the app uses this data.

This app has crashed because it attempted to access privacy-sensitive data without a usage description.  The app's Info.plist must contain an NSMicrophoneUsageDescription key with a string value explaining to the user how the app uses this data.


>> Compiles

>> Crash on record:

Thread 1: "*** -[AVCaptureMovieFileOutput startRecordingToOutputFileURL:recordingDelegate:] No active/enabled connections"


