import AVFoundation

/// Ratchet click synthesized in code (port of gearClick() in app.js): a short filtered noise
/// burst for the tooth plus a tiny falling metallic knock. No sound files.
@MainActor
final class GearClick {
    static let shared = GearClick()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [AVAudioPCMBuffer] = []
    private var started = false

    private func setup() {
        guard !started else { return }
        let rate = 44100.0
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        player.volume = 0.18   // quiet: the haptic is the main feedback
        // A few variations, like real teeth
        for i in 0..<4 {
            let n = Int(rate * 0.014)
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
            buf.frameLength = AVAudioFrameCount(n)
            let d = buf.floatChannelData![0]
            let center = 3000 + Double(i) * 170
            var phase = 0.0, knockPhase = 0.0
            for k in 0..<n {
                let t = Double(k) / Double(n)
                let env = pow(1 - t, 6)
                let noise = Double.random(in: -1...1) * env
                phase += 2 * .pi * center / rate
                let tooth = noise * (0.5 + 0.5 * sin(phase))          // crude band-pass colouring
                let f = 1700 - 1000 * min(1, t * 1.7)                  // falling knock
                knockPhase += 2 * .pi * f / rate
                let knock = (sin(knockPhase) > 0 ? 1.0 : -1.0) * 0.05 * pow(1 - t, 3)
                d[k] = Float((tooth * 0.55 + knock).clamped(-1, 1))
            }
            buffers.append(buf)
        }
        try? engine.start()
        player.play()
        started = true
    }

    func click() {
        setup()
        guard started, engine.isRunning, let b = buffers.randomElement() else { return }
        player.scheduleBuffer(b, at: nil, options: [], completionHandler: nil)
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}
