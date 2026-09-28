import AVFoundation
import ClassicToolbox

/// Pulls samples from the emulated Sound Driver into the system audio output.
final class AudioOutput {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?

    init(driver: SoundDriver) {
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let rate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            driver.render(into: data, frames: Int(frameCount), outputRate: rate)
            for b in buffers.dropFirst() {   // duplicate mono into any extra buffers
                b.mData?.copyMemory(from: data, byteCount: Int(frameCount) * MemoryLayout<Float>.size)
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
    }

    func start() {
        do {
            try engine.start()
        } catch {
            NSLog("StuntCopter: audio unavailable: \(error)")
        }
    }

    func stop() { engine.stop() }
}
