import Foundation

/// Emulation of the Macintosh Plus Sound Driver's free-form and four-tone
/// synthesizers (Inside Macintosh II-221). Sounds are written asynchronously
/// like PBWrite to refNum -4; `isDone` mirrors "ioResult < 1".
///
/// The driver produces 8-bit unsigned samples (128 = silence) at the Mac's
/// 22,254.54 Hz sound rate; `render` resamples that to the host's output rate.
public final class SoundDriver: @unchecked Sendable {
    public static let nativeRate = 22_254.545_454
    public static let samplesPerTick = nativeRate / 60

    /// FFSynthRec: `count` is a Fixed playback rate (1.0 = one byte per sample).
    public struct FreeForm: Sendable {
        public var count: Int
        public var waveBytes: [UInt8]
        public init(count: Int, waveBytes: [UInt8]) {
            self.count = count
            self.waveBytes = waveBytes
        }
    }

    /// FTSoundRec: four voices, each a Fixed `rate` stepping through a 256-byte wave.
    public struct FourTone: Sendable {
        public var duration: Int          // ticks
        public var rates: [Int]           // Fixed, 4 voices
        public var phases: [Int]          // starting byte offsets into the wave
        public var waves: [[UInt8]]       // 4 × 256 bytes
        public init(duration: Int, rates: [Int], phases: [Int], waves: [[UInt8]]) {
            self.duration = duration
            self.rates = rates
            self.phases = phases
            self.waves = waves
        }
    }

    private enum Mode { case idle, freeForm, fourTone }

    private let lock = NSLock()
    // Synth state lives in plain stored properties so the audio thread never allocates.
    private var mode = Mode.idle
    private var ffWave: [UInt8] = []
    private var ffLength = 0
    private var ffPos = 0
    private var ffStep = 0
    private var ftWaves: [[UInt8]] = []
    private var ftRates = [0, 0, 0, 0]
    private var ftPhase = [0, 0, 0, 0]
    private var ftRemaining = 0
    private var current: Double = 128    // last native sample
    private var nativeClock: Double = 0
    private var lowpass: Double = 0
    private var dcIn: Double = 0
    private var dcOut: Double = 0

    /// Output gain applied after centering; the Plus speaker was not loud.
    public var volume: Double = 0.35

    public init() {}

    /// PBWrite with a free-form record whose ioReqCount was `reqCount` bytes
    /// (the 6-byte mode/count header is included in the request count).
    public func write(_ ff: FreeForm, reqCount: Int) {
        lock.withLock {
            ffWave = ff.waveBytes
            ffLength = min(ff.waveBytes.count, max(0, reqCount - 6))
            ffPos = 0
            ffStep = ff.count
            mode = .freeForm
        }
    }

    public func write(_ ft: FourTone) {
        lock.withLock {
            ftWaves = ft.waves
            for v in 0..<4 {
                ftRates[v] = ft.rates[v]
                ftPhase[v] = ft.phases[v] << 16
            }
            ftRemaining = Int((Double(ft.duration) * SoundDriver.samplesPerTick).rounded())
            mode = .fourTone
        }
    }

    /// PBKillIO: stop whatever is playing.
    public func kill() {
        lock.withLock { mode = .idle }
    }

    /// True once the last write has finished (ioResult < 1).
    public var isDone: Bool {
        lock.withLock { mode == .idle }
    }

    /// Advances the synthesizer one native sample (lock held).
    private func step() -> Double {
        switch mode {
        case .idle:
            return 128
        case .freeForm:
            let i = ffPos >> 16
            guard i < ffLength else { mode = .idle; return 128 }
            ffPos += ffStep
            return Double(ffWave[i])
        case .fourTone:
            guard ftRemaining > 0 else { mode = .idle; return 128 }
            var sum = 0
            for v in 0..<4 {
                sum += Int(ftWaves[v][(ftPhase[v] >> 16) & 0xFF])
                ftPhase[v] &+= ftRates[v]
            }
            ftRemaining -= 1
            return Double(sum) / 4
        }
    }

    /// Fills `frames` mono Float samples at `outputRate`.
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, outputRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        let ratio = SoundDriver.nativeRate / outputRate
        // One-pole low-pass (~7 kHz) approximates the Plus's output filter.
        let alpha = 1 - exp(-2 * Double.pi * 7000 / outputRate)
        for f in 0..<frames {
            nativeClock += ratio
            while nativeClock >= 1 {
                current = step()
                nativeClock -= 1
            }
            let centered = (current - 128) / 128
            lowpass += alpha * (centered - lowpass)
            // DC blocker: the speaker is AC-coupled, and the copter noise sits well below 128.
            let y = lowpass - dcIn + 0.995 * dcOut
            dcIn = lowpass
            dcOut = y
            out[f] = Float(y * volume)
        }
    }
}

/// FixRatio(numer, denom) as a 16.16 Fixed.
public func FixRatio(_ numer: Int, _ denom: Int) -> Int { (numer << 16) / denom }
