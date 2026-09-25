// Records one application's audio output to a WAV file with ScreenCaptureKit
// (needs Screen Recording permission). Used to compare the original's sounds in an
// emulator with the port's.
//
//   swiftc -O Tools/record_app_audio.swift -o build/record_app_audio
//   build/record_app_audio <app name> <seconds> <out.wav>
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    var file: AVAudioFile?
    let url: URL
    init(url: URL) { self.url = url }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let fmtDesc = sb.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)?.pointee,
              let format = AVAudioFormat(streamDescription: [asbd]) else { return }
        let frames = AVAudioFrameCount(sb.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(frames),
                                                           into: buffer.mutableAudioBufferList) == noErr else { return }
        if file == nil {
            file = try? AVAudioFile(forWriting: url, settings: format.settings,
                                    commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
        }
        try? file?.write(from: buffer)
    }
}

let args = CommandLine.arguments
guard args.count == 4, let seconds = Double(args[2]) else {
    print("usage: record_app_audio <app name> <seconds> <out.wav>")
    exit(1)
}

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
guard let app = content.applications.first(where: { $0.applicationName == args[1] }),
      let display = content.displays.first else {
    print("app '\(args[1])' not found; running: \(content.applications.map(\.applicationName).sorted())")
    exit(1)
}
let config = SCStreamConfiguration()
config.capturesAudio = true
config.sampleRate = 48_000
config.channelCount = 1
config.width = 2
config.height = 2
config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
let recorder = Recorder(url: URL(fileURLWithPath: args[3]))
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio"))
try await stream.startCapture()
print("recording \(args[1]) for \(Int(seconds)) s…")
try await Task.sleep(for: .seconds(seconds))
try await stream.stopCapture()
recorder.file = nil
print("wrote \(args[3])")
