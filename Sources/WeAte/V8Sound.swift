//
//  V8Sound.swift
//  WeAte
//
//  Created by Aarav Gupta on 14/11/26.
//  https://github.com/atpugvaraa
//  https://x.com/atpugvaraa
//

import AVFoundation
import Synchronization

/// Plays the synthesised V8. The engine model pushes rpm + load in, the audio thread pulls them out.
@MainActor
final class V8Sound {
    static let shared = V8Sound()

    let volume: Float = 0.5

    private let audio = AVAudioEngine()
    private var voice: V8Voice?

    func start() {
        guard voice == nil else { return }
        let sampleRate = audio.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            print("V8: no audio output")
            return
        }

        let voice = V8Voice(sampleRate: Float(sampleRate), volume: volume)
        // @Sendable matters: a closure written inside a @MainActor class is main-actor isolated
        // by default, and Swift traps when the audio thread calls it. This runs on the audio thread.
        let node = AVAudioSourceNode(format: format) { @Sendable _, _, frames, buffers in
            voice.render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(buffers))
            return noErr
        }
        audio.attach(node)
        audio.connect(node, to: audio.mainMixerNode, format: format)

        do {
            try audio.start()
            self.voice = voice
        } catch {
            print("V8: audio engine failed to start:", error)
        }
    }

    func update(rpm: Float, load: Float) {
        voice?.rpm.store(rpm.bitPattern, ordering: .relaxed)
        voice?.load.store(load.bitPattern, ordering: .relaxed)
    }
}

/// Cross-plane V8, built from the crank up:
/// - one cylinder fires every 90° of crank, in the order 1-8-4-3-6-5-7-2
/// - odd cylinders exhaust into the left pipe, even into the right
/// - so each pipe gets its 4 bangs unevenly spaced: L R R L R L L R -> that lopsided rhythm is the burble
///
/// Everything in here runs on the real-time audio thread: no allocations, no locks, no prints.
/// ponytail: @unchecked because only render() touches the vars, and only the audio thread calls it.
final class V8Voice: @unchecked Sendable {
    // Written by the main thread, read by the audio thread. Floats stored as their bit patterns.
    let rpm = Atomic<UInt32>(Float(900).bitPattern)
    let load = Atomic<UInt32>(0)

    let firingOrder = [1, 8, 4, 3, 6, 5, 7, 2]
    let overrunPopChance: Float = 0.08    // chance per firing of a "brap" when off throttle at high revs

    private let sampleRate: Float
    private let volume: Float
    private let leftBank: [Bool]           // per firing slot: does this cylinder exhaust left?

    private var crank: Float = 0           // degrees since the last firing
    private var slot = 0                   // position in the firing order
    private var left: Pipe
    private var right: Pipe
    private var seed: UInt32 = 0x9E3779B9

    init(sampleRate: Float, volume: Float) {
        self.sampleRate = sampleRate
        self.volume = volume
        self.leftBank = firingOrder.map { $0 % 2 == 1 }
        // Slightly different pipe tones so the two banks don't blend into one
        self.left = Pipe(tone: 95, sampleRate: sampleRate)
        self.right = Pipe(tone: 108, sampleRate: sampleRate)
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let rpm = Float(bitPattern: self.rpm.load(ordering: .relaxed))
        let load = Float(bitPattern: self.load.load(ordering: .relaxed))
        let degreesPerSample = rpm / 60 * 360 / sampleRate

        guard let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        for i in 0..<frames {
            crank += degreesPerSample
            if crank >= 90 {
                crank -= 90
                fire(rpm: rpm, load: load)
            }

            let noise = random() * 2 - 1
            let outL = left.next(noise: noise)
            let outR = right.next(noise: noise)
            // A bit of each pipe in the other ear, so it's not hard-panned
            l[i] = tanh((outL + 0.35 * outR) * volume)
            r[i] = tanh((outR + 0.35 * outL) * volume)
        }
    }

    private func fire(rpm: Float, load: Float) {
        let punch = 0.35 + 0.65 * load            // off throttle = soft thuds, on throttle = bark
        let jitter = 0.85 + 0.3 * random()         // no two combustions are identical
        if leftBank[slot] {
            left.fire(punch * jitter)
        } else {
            right.fire(punch * jitter)
        }
        slot = (slot + 1) % firingOrder.count

        // Unburnt fuel going off in the hot exhaust when you lift at high revs
        if load == 0 && rpm > 3000 && random() < overrunPopChance {
            if random() < 0.5 { left.fire(1.6) } else { right.fire(1.6) }
        }
    }

    /// xorshift: cheap, allocation-free randomness in 0..<1 for the audio thread
    private func random() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max)
    }
}

/// One exhaust pipe: each bang is a short noisy burst that rings a low resonance (the pipe's tone).
struct Pipe {
    let a1: Float, a2: Float      // resonator coefficients
    var gain: Float = 1           // set in init so one full bang peaks at `loudness`
    let decay: Float              // how fast a bang dies out

    var envelope: Float = 0
    var y1: Float = 0, y2: Float = 0

    init(tone: Float, sampleRate: Float, loudness: Float = 0.6) {
        let bandwidth: Float = 60
        let r = exp(-Float.pi * bandwidth / sampleRate)
        let w = 2 * Float.pi * tone / sampleRate
        a1 = 2 * r * cos(w)
        a2 = -r * r
        decay = exp(-1 / (0.004 * sampleRate))   // ~4 ms bang

        // A resonator this narrow amplifies thousands of times, so measure one bang and scale it.
        // Runs once on the main thread, never on the audio thread.
        var probe = self
        probe.fire(1)
        var peak: Float = 0
        for _ in 0..<Int(sampleRate / 10) {
            peak = max(peak, abs(probe.next(noise: 0)))
        }
        gain = loudness / peak
    }

    mutating func fire(_ amount: Float) {
        envelope = max(envelope, amount)
    }

    mutating func next(noise: Float) -> Float {
        let burst = envelope * (0.7 + 0.3 * noise)
        envelope *= decay
        let y = burst + a1 * y1 + a2 * y2
        y2 = y1
        y1 = y
        return y * gain + burst * 0.25    // body of the pipe + the sharp bark
    }
}
