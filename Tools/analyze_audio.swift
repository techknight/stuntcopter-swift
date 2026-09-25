// Finds tonal (four-tone/sawtooth) stretches and silences in a recording, and prints a
// 5 ms loudness envelope around a given time.
//
//   swift Tools/analyze_audio.swift <file.wav>                 → tonal segments
//   swift Tools/analyze_audio.swift <file.wav> <start s> <len s> → 5 ms envelope + pitch
import Accelerate
import AVFoundation
import Foundation

let a = CommandLine.arguments
let file = try AVAudioFile(forReading: URL(fileURLWithPath: a[1]))
let sr = file.processingFormat.sampleRate
let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buf)
let x = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))

func rms(_ s: ArraySlice<Float>) -> Float {
    var r: Float = 0
    s.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress!, 1, &r, vDSP_Length($0.count)) }
    return r
}

/// Spectral flatness (geometric/arithmetic mean of the power spectrum) of 2048 samples.
let n = 2048
let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
func spectrum(_ s: ArraySlice<Float>) -> [Float] {
    var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    let input = Array(s.prefix(n)) + [Float](repeating: 0, count: max(0, n - s.count))
    var w = [Float](repeating: 0, count: n)
    vDSP_vmul(input, 1, window, 1, &w, 1, vDSP_Length(n))
    var oRe = [Float](repeating: 0, count: n), oIm = [Float](repeating: 0, count: n)
    vDSP_DFT_Execute(setup, w, im, &oRe, &oIm)
    _ = re
    return (0..<(n / 2)).map { oRe[$0] * oRe[$0] + oIm[$0] * oIm[$0] + 1e-12 }
}
func flatness(_ p: [Float]) -> Float {
    let band = p[2..<400]   // ~47 Hz – 9.4 kHz at 48 kHz
    let logMean = band.map { log($0) }.reduce(0, +) / Float(band.count)
    return exp(logMean) / (band.reduce(0, +) / Float(band.count))
}

if a.count == 2 {
    let hop = Int(sr * 0.02)
    var inTonal = false, start = 0.0
    var i = 0
    while i + n < x.count {
        let loud = rms(x[i..<(i + hop)])
        let tonal = loud > 0.01 && flatness(spectrum(x[i..<(i + n)])) < 0.02
        let t = Double(i) / sr
        if tonal && !inTonal { start = t; inTonal = true }
        if !tonal && inTonal {
            if t - start > 0.05 { print(String(format: "tonal %7.2f – %7.2f s (%.2f s)", start, t, t - start)) }
            inTonal = false
        }
        i += hop
    }
} else {
    let t0 = Double(a[2])!, len = Double(a[3])!
    let hop = Int(sr * 0.005)
    var i = Int(t0 * sr)
    let end = min(x.count - n, Int((t0 + len) * sr))
    while i < end {
        let loud = rms(x[i..<(i + hop)])
        let p = spectrum(x[i..<(i + n)])
        let peak = (2..<200).max { p[$0] < p[$1] }!
        let bar = String(repeating: "#", count: min(60, Int(loud * 300)))
        print(String(format: "%7.3f %.4f peak %5.0f Hz %@", Double(i) / sr, loud, Double(peak) * sr / Double(n), bar))
        i += hop
    }
}
