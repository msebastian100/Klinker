import AVFoundation
import Foundation

/// Kurze Töne, einmal beim Start erzeugt. Kein geladenes Audio.
final class Audio {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var cursor = 0
    private let format: AVAudioFormat
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var available = false
    private var last: [String: TimeInterval] = [:]

    var muted = false {
        didSet {
            let volume: Float = muted ? 0 : 0.85
            for player in players { player.volume = volume }
        }
    }

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        for _ in 0..<5 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.volume = 0.85
            players.append(player)
        }
        bake()
        do {
            try engine.start()
            for player in players { player.play() }
            available = true
        } catch {
            available = false
        }
    }

    func brick(_ pitch: Int) { play("b\(min(6, max(0, pitch)))", gap: 0.028) }
    func crack() { play("crack", gap: 0.04) }
    func paddle() { play("paddle", gap: 0.04) }
    func wall() { play("wall", gap: 0.045) }
    func launch() { play("launch", gap: 0.05) }
    func hurt() { play("hurt", gap: 0.05) }
    func clear() { play("clear", gap: 0.05) }
    func extra() { play("extra", gap: 0.05) }
    func over() { play("over", gap: 0.05) }
    func tick() { play("tick", gap: 0.03) }

    private func play(_ name: String, gap: TimeInterval) {
        guard available, !muted, let buffer = buffers[name] else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let prior = last[name], now - prior < gap { return }
        last[name] = now
        if !engine.isRunning { try? engine.start() }
        let player = players[cursor % players.count]
        cursor += 1
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func bake() {
        let scale: [Double] = [523.25, 587.33, 659.25, 698.46, 783.99, 880, 987.77]
        for (i, freq) in scale.enumerated() {
            buffers["b\(i)"] = tone(freq: freq, dur: 0.11, decay: 16, gain: 0.28)
        }
        buffers["crack"] = tone(freq: 240, dur: 0.07, decay: 28, gain: 0.22)
        buffers["paddle"] = tone(freq: 196, dur: 0.07, decay: 26, gain: 0.32)
        buffers["wall"] = tone(freq: 740, dur: 0.045, decay: 40, gain: 0.16)
        buffers["tick"] = tone(freq: 990, dur: 0.03, decay: 50, gain: 0.12)
        buffers["launch"] = sweep(from: 320, to: 760, dur: 0.12, gain: 0.24)
        buffers["hurt"] = phrase([(440, 0), (294, 0.09)], dur: 0.28, gain: 0.3)
        buffers["clear"] = phrase([(523, 0), (659, 0.08), (784, 0.16), (1046, 0.24)], dur: 0.55, gain: 0.26)
        buffers["extra"] = phrase([(784, 0), (1175, 0.08)], dur: 0.28, gain: 0.26)
        buffers["over"] = phrase([(392, 0), (330, 0.1), (262, 0.2)], dur: 0.5, gain: 0.28)
    }

    private func tone(freq: Double, dur: Double, decay: Double, gain: Double) -> AVAudioPCMBuffer {
        render(dur) { t in
            let p = 2 * Double.pi * freq * t
            let env = exp(-t * decay)
            return (sin(p) * 0.86 + sin(p * 2) * 0.14) * env * gain
        }
    }

    private func sweep(from: Double, to: Double, dur: Double, gain: Double) -> AVAudioPCMBuffer {
        var phase = 0.0
        let sr = format.sampleRate
        return render(dur) { t in
            let f = from + (to - from) * min(1, t / dur)
            phase += 2 * Double.pi * f / sr
            let env = exp(-t * 6) * (1 - t / dur)
            return sin(phase) * env * gain
        }
    }

    private func phrase(_ notes: [(Double, Double)], dur: Double, gain: Double) -> AVAudioPCMBuffer {
        render(dur) { t in
            var sample = 0.0
            for (freq, start) in notes where t >= start {
                let u = t - start
                let p = 2 * Double.pi * freq * u
                sample += sin(p) * exp(-u * 8)
            }
            return sample * gain
        }
    }

    private func render(_ dur: Double, _ body: (Double) -> Double) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * dur)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(count) {
            let t = Double(i) / format.sampleRate
            let s = body(t)
            channel[i] = Float(max(-1, min(1, s)))
        }
        return buffer
    }
}
