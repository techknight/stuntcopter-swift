import CStuntCopterWin
import ClassicToolbox

/// Called on the waveOut feeder thread; the Sound Driver's render is thread-safe.
private let renderCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Float>?, Int32) -> Void = {
    context, out, frames in
    guard let context, let out else { return }
    let driver = Unmanaged<SoundDriver>.fromOpaque(context).takeUnretainedValue()
    driver.render(into: out, frames: Int(frames), outputRate: 44_100)
}

/// Pulls samples from the emulated Sound Driver into the default output device.
final class AudioOutput {
    private var handle: OpaquePointer?
    private let driver: Unmanaged<SoundDriver>

    init(driver: SoundDriver) {
        self.driver = Unmanaged.passRetained(driver)
        handle = sc_audio_start(renderCallback, self.driver.toOpaque())
    }

    func stop() {
        sc_audio_stop(handle)
        handle = nil
        driver.release()
    }
}
