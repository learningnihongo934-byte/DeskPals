import AVFoundation
import Foundation

/// Little synthesized sound effects. Pets don't talk out loud; they use speech bubbles.
final class Sound {
    static let shared = Sound()

    enum Effect: String { case boing, munch, pop, coin, purr, splash, thunder, whoosh, ding, impact, roar, chime }

    private let d = UserDefaults.standard
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var started = false
    private var effects: [Effect: AVAudioPCMBuffer] = [:]

    var effectsOn: Bool {
        get { d.object(forKey: "sound.effects") as? Bool ?? true }
        set { d.set(newValue, forKey: "sound.effects") }
    }
    var volume: Float {
        get { d.object(forKey: "sound.volume") as? Float ?? 0.45 }
        set { d.set(newValue, forKey: "sound.volume"); engine.mainMixerNode.outputVolume = newValue }
    }

    private func start() -> Bool {
        if started { return engine.isRunning }
        started = true
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = volume
        do { try engine.start() } catch { NSLog("DeskPals: audio off: \(error)") }
        return engine.isRunning
    }

    func play(_ e: Effect, pitch: Double = 1) {
        guard effectsOn, volume > 0, start() else { return }
        let buf = effects[e] ?? {
            let b = synth(e)
            effects[e] = b
            return b
        }()
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        p.rate = Float(pitch)
        p.play()
    }

    // MARK: - Synthesis

    private func buffer(_ seconds: Double, _ sample: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let out = b.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Double(i) / format.sampleRate
            out[i] = Float(sample(t, t / seconds))
        }
        return b
    }

    private func synth(_ e: Effect) -> AVAudioPCMBuffer {
        switch e {
        case .boing:
            return buffer(0.25) { t, k in
                let f = 220 + 500 * k + 30 * sin(t * 60)
                return sin(2 * .pi * f * t) * (1 - k) * 0.35
            }
        case .pop:
            return buffer(0.07) { t, k in sin(2 * .pi * (900 - 600 * k) * t) * (1 - k) * 0.4 }
        case .munch:
            return buffer(0.3) { _, k in
                let burst = sin(k * .pi * 3).magnitude > 0.6 ? 1.0 : 0.0
                return Double.random(in: -1...1) * burst * (1 - k) * 0.18
            }
        case .coin:
            return buffer(0.25) { t, k in
                let f = k < 0.3 ? 988.0 : 1319.0
                return (sin(2 * .pi * f * t) > 0 ? 1 : -1) * (1 - k) * 0.12
            }
        case .purr:
            return buffer(0.7) { t, k in Double.random(in: -1...1) * (0.5 + 0.5 * sin(2 * .pi * 26 * t)) * sin(k * .pi) * 0.12 }
        case .splash:
            var last = 0.0
            return buffer(0.4) { _, k in
                last = last * 0.7 + Double.random(in: -1...1) * 0.3
                return last * pow(1 - k, 2) * 0.6
            }
        case .thunder:
            var last = 0.0
            return buffer(1.6) { _, k in
                last = last * 0.97 + Double.random(in: -1...1) * 0.03
                return last * (k < 0.05 ? k * 20 : pow(1 - k, 1.5)) * 3
            }
        case .whoosh:
            var last = 0.0
            return buffer(0.35) { _, k in
                last = last * 0.85 + Double.random(in: -1...1) * 0.15
                return last * sin(k * .pi) * 0.6
            }
        case .ding:
            return buffer(0.4) { t, k in sin(2 * .pi * 1568 * t) * pow(1 - k, 2) * 0.25 }
        case .impact:
            var last = 0.0
            return buffer(0.45) { t, k in
                last = last * 0.8 + Double.random(in: -1...1) * 0.2
                return (last * 2 + sin(2 * .pi * (90 - 50 * k) * t)) * pow(1 - k, 2) * 0.5
            }
        case .roar:
            var last = 0.0
            return buffer(1.2) { t, k in
                last = last * 0.9 + Double.random(in: -1...1) * 0.1
                let growl = sin(2 * .pi * (70 + 20 * sin(t * 30)) * t)
                return (growl * 0.6 + last * 3) * sin(k * .pi) * 0.45
            }
        case .chime:
            return buffer(1.0) { t, k in
                (sin(2 * .pi * 880 * t) + 0.6 * sin(2 * .pi * 1320 * t) + 0.4 * sin(2 * .pi * 1760 * t)) * pow(1 - k, 1.5) * 0.12
            }
        }
    }
}
