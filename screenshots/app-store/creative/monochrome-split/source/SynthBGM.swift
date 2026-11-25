import Foundation

// MARK: - Moro App Store BGM Studio v2 (48 kHz Stereo, 80 BPM, Sample-Accurate Infinite Loop)
// Acoustic polish from v1 feedback:
//   1. ZERO low-end eardrum thump ("耳膜嗡一下"):
//      - No sub-80Hz bass pitch-drops or hard downbeat slams
//      - Silky 85ms acoustic bass swell in warm 98-175 Hz cello/guitar register
//      - 2-pole Butterworth 72 Hz High-Pass Filter on master bus (circularly warmed up!)
//      - Gentle humanized roll across chord tones so bar boundaries glide like silk
//   2. Seamless Tail -> Head Infinite Loop:
//      - Continuous voice-led melody & guitar arpeggio crossing 12.0s->0.0s and 15.0s->0.0s
//      - NO artificial fade-to-zero dip at loop boundary (true mathematically periodic waveform!)
//      - Circularly wrapped stereo hall reverb & mastering filters
//
// Finalist Candidates:
//   a1 (a1-morning-acoustic) : Pure Morning Acoustic (F Major — Nylon Guitar + Felt Piano + Silk Pad)
//   a2 (a2-acoustic-rhodes)  : Fusion A×C (F Major — Nylon Guitar + Velvety Rhodes + Soft Marimba Shimmer)
//   c2 (c2-warm-rhodes)      : Clean Warm Rhodes & Marimba (Eb Major — zero thump, smooth infinite loop)

let SR: Double = 48000.0
let TWO_PI: Double = 2.0 * Double.pi

@inline(__always) func midiToHz(_ midi: Double) -> Double {
    440.0 * pow(2.0, (midi - 69.0) / 12.0)
}

struct SeededRNG {
    var state: UInt64
    init(_ seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func nextDouble() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let val = state &* 2685821657736338717
        return Double(val >> 11) / Double(1 << 53)
    }
    mutating func nextSigned() -> Double { nextDouble() * 2.0 - 1.0 }
}

final class StereoTrack {
    let n: Int
    var l: [Double]
    var r: [Double]

    init(durationSeconds: Double) {
        self.n = Int((durationSeconds * SR).rounded())
        self.l = [Double](repeating: 0.0, count: n)
        self.r = [Double](repeating: 0.0, count: n)
    }

    @inline(__always) func panGains(_ pan: Double) -> (Double, Double) {
        let angle = (min(max(pan, -1.0), 1.0) + 1.0) * Double.pi * 0.25
        return (cos(angle), sin(angle))
    }

    // MARK: 1. Physical-Modeled Nylon Acoustic Guitar (Karplus-Strong w/ Warm Fingertip Attack)
    func addNylonPluck(
        startS: Double, midi: Double, durS: Double, vel: Double,
        pan: Double = 0.0, brightness: Double = 0.48, seed: UInt64 = 42
    ) {
        let freq = midiToHz(midi)
        let exactDelay = SR / freq
        let delayInt = max(2, Int(floor(exactDelay)))
        let frac = exactDelay - Double(delayInt)
        let apCoeff = (1.0 - frac) / (1.0 + frac)

        var ring = [Double](repeating: 0.0, count: delayInt)
        var rng = SeededRNG(seed ^ UInt64(midi * 1000.0) ^ UInt64(abs(startS) * 10000.0))

        var lp1 = 0.0, lp2 = 0.0
        let exciteAlpha = min(0.46, max(0.08, (freq * (1.9 + 2.5 * brightness)) / SR * TWO_PI * 0.34))
        var mean = 0.0
        for i in 0..<delayInt {
            let raw = rng.nextSigned()
            lp1 += exciteAlpha * (raw - lp1)
            lp2 += exciteAlpha * (lp1 - lp2)
            let pos = sin(Double.pi * Double(i) / Double(delayInt))
            let val = lp2 * (0.45 + 0.55 * pos)
            ring[i] = val
            mean += val
        }
        mean /= Double(delayInt)
        var rms = 0.0
        for i in 0..<delayInt { ring[i] -= mean; rms += ring[i] * ring[i] }
        let norm = 1.0 / max(sqrt(rms / Double(delayInt)), 1e-6)
        for i in 0..<delayInt { ring[i] *= norm * 0.28 }

        let decayPerCycle = pow(0.0025, 1.0 / max(10.0, freq * (durS + 1.0)))
        let damp = min(0.9986, max(0.974, decayPerCycle))
        let filtBlend = 0.46 + 0.20 * (1.0 - brightness)

        let totalSamples = Int(((durS + 1.45) * SR).rounded())
        let startI = Int((startS * SR).rounded())
        let (gl, gr) = panGains(pan)
        let amp = vel * 0.39

        var idx = 0
        var prevOut = 0.0, apPrevIn = 0.0, apPrevOut = 0.0
        var bodyLP = 0.0

        for k in 0..<totalSamples {
            let t = Double(k) / SR
            let cur = ring[idx]
            let prev = ring[(idx - 1 + delayInt) % delayInt]

            let filtered = (cur * (1.0 - filtBlend) + prev * filtBlend) * damp
            let apOut = apCoeff * (filtered - apPrevOut) + apPrevIn
            apPrevIn = filtered
            apPrevOut = apOut
            ring[idx] = apOut

            idx += 1
            if idx >= delayInt { idx = 0 }

            let att = t < 0.010 ? (0.5 - 0.5 * cos(Double.pi * t / 0.010)) : 1.0
            let rel = t > durS ? exp(-(t - durS) * 2.8) : 1.0

            bodyLP += 0.14 * (apOut - bodyLP)
            let sample = (apOut * 0.66 + bodyLP * 0.42 + prevOut * 0.08) * att * rel * amp
            prevOut = apOut

            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += sample * gl
            r[outIdx] += sample * gr
        }
    }

    // MARK: 2. Expressive Intimate Felt Piano (Soft Wool Hammer, Zero Sub Thump)
    func addFeltPiano(
        startS: Double, midi: Double, durS: Double, vel: Double,
        pan: Double = 0.0, warmth: Double = 0.70
    ) {
        let f0 = midiToHz(midi)
        let startI = Int((startS * SR).rounded())
        let totalSamples = Int(((durS + 2.0) * SR).rounded())
        let (gl, gr) = panGains(pan)

        let amp = vel * 0.27
        let inharmB = 0.00016
        let detune = 1.00046

        let hAmps: [Double] = [
            1.00,
            0.35 * (1.16 - warmth * 0.46),
            0.14 * (1.16 - warmth * 0.56),
            0.055 * (1.16 - warmth * 0.66),
            0.020 * (1.16 - warmth * 0.76),
            0.007 * (1.16 - warmth * 0.82),
        ]
        var freqs = [Double](repeating: 0.0, count: hAmps.count)
        var decayRates = [Double](repeating: 0.0, count: hAmps.count)
        for h in 0..<hAmps.count {
            let k = Double(h + 1)
            freqs[h] = k * f0 * sqrt(1.0 + inharmB * k * k)
            decayRates[h] = 0.68 * pow(k, 1.30) + (midi > 72 ? 0.20 : 0.0)
        }

        let attackTime = 0.018 + (1.0 - min(1.0, vel)) * 0.014
        let f1b = f0 * detune
        // Long sustained melody notes hold like a real grand piano with damper pedal down!
        let holdDecay = durS > 1.7 ? 0.26 : 0.48
        let fundDecay = durS > 1.7 ? 0.38 : decayRates[0]

        for k in 0..<totalSamples {
            let t = Double(k) / SR
            let att = t < attackTime ? (0.5 - 0.5 * cos(Double.pi * t / attackTime)) : 1.0
            let noteEnv = t < durS ? exp(-t * holdDecay) : exp(-durS * holdDecay) * exp(-(t - durS) * 2.2)

            let u1 = sin(TWO_PI * freqs[0] * t)
            let u2 = sin(TWO_PI * f1b * t + 0.55)
            let fundEnv = exp(-t * fundDecay)
            var sumL = (u1 * 0.72 + u2 * 0.36) * fundEnv
            var sumR = (u1 * 0.36 + u2 * 0.72) * fundEnv

            for h in 1..<hAmps.count {
                let fh = freqs[h]
                if fh > 8500.0 { break }
                let part = sin(TWO_PI * fh * t + Double(h) * 0.35) * hAmps[h] * exp(-t * decayRates[h])
                sumL += part
                sumR += part
            }

            let env = att * noteEnv * amp
            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += sumL * env * gl
            r[outIdx] += sumR * env * gr
        }
    }

    // MARK: 3. Velvety Warm Rhodes Electric Piano (Silky Soft Attack — Zero Eardrum Bump!)
    func addWarmRhodes(
        startS: Double, midi: Double, durS: Double, vel: Double,
        pan: Double = 0.0, tremoloDepth: Double = 0.20
    ) {
        let f0 = midiToHz(midi)
        let startI = Int((startS * SR).rounded())
        let totalSamples = Int(((durS + 1.8) * SR).rounded())
        let (gl, gr) = panGains(pan)
        let amp = vel * 0.22

        let tineRatio = 7.0
        let fmIndex0 = 0.26 * vel

        for k in 0..<totalSamples {
            let t = Double(k) / SR
            // Soft 28ms velvet onset -> lush floating bloom instead of percussive bump!
            let att = t < 0.028 ? (0.5 - 0.5 * cos(Double.pi * t / 0.028)) : 1.0
            let env = t < durS ? exp(-t * 0.55) : exp(-durS * 0.55) * exp(-(t - durS) * 3.0)

            let tineEnv = exp(-t * 15.0)
            let mod = sin(TWO_PI * (f0 * tineRatio) * t) * fmIndex0 * tineEnv
            let body = sin(TWO_PI * f0 * t + mod)
                + 0.22 * sin(TWO_PI * f0 * 2.0 * t) * exp(-t * 2.5)
                + 0.05 * sin(TWO_PI * f0 * 3.0 * t) * exp(-t * 5.0)

            let globalT = startS + t
            let trem = sin(TWO_PI * 2.6667 * globalT) * tremoloDepth
            let tL = 1.0 - trem * 0.5
            let tR = 1.0 + trem * 0.5

            let sample = body * att * env * amp
            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += sample * gl * tL
            r[outIdx] += sample * gr * tR
        }
    }

    // MARK: 4. Soft Rosewood Marimba (Removed Low Sub-Octave Mallet Thump!)
    func addWoodenMarimba(
        startS: Double, midi: Double, durS: Double, vel: Double, pan: Double = 0.0
    ) {
        let f0 = midiToHz(midi)
        let startI = Int((startS * SR).rounded())
        let totalSamples = Int(((min(durS + 0.9, 1.4)) * SR).rounded())
        let (gl, gr) = panGains(pan)
        let amp = vel * 0.24

        let f2 = f0 * 3.985
        for k in 0..<totalSamples {
            let t = Double(k) / SR
            // Soft yarn-mallet onset (12ms) -> buttery wood chime with ZERO thump!
            let att = t < 0.012 ? (0.5 - 0.5 * cos(Double.pi * t / 0.012)) : 1.0
            let fund = sin(TWO_PI * f0 * t) * exp(-t * 3.8)
            let over = (f2 < 7200.0 ? sin(TWO_PI * f2 * t) * 0.13 * exp(-t * 22.0) : 0.0)
            let sample = (fund + over) * att * amp
            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += sample * gl
            r[outIdx] += sample * gr
        }
    }

    // MARK: 5. Silk Strings / Cello Chamber Pad (Ultra-Smooth Overlapping Crossfade)
    func addSilkPad(startS: Double, midi: Double, durS: Double, amp: Double, pan: Double = 0.0) {
        let f0 = midiToHz(midi)
        let startI = Int((startS * SR).rounded())
        let attackS = 0.85
        let releaseS = 1.25
        let totalSamples = Int(((durS + releaseS) * SR).rounded())
        let (gl, gr) = panGains(pan)

        let ratios: [Double] = [0.9965, 0.9990, 1.0012, 1.0038]
        let pansL: [Double] = [0.82, 0.58, 0.42, 0.18]
        let pansR: [Double] = [0.18, 0.42, 0.58, 0.82]
        var phases = [0.0, 1.3, 2.7, 4.1]

        var lpL1 = 0.0, lpL2 = 0.0, lpR1 = 0.0, lpR2 = 0.0
        let cutoff = min(820.0, max(320.0, f0 * 2.4))
        let alpha = min(0.23, (TWO_PI * cutoff) / SR)

        for k in 0..<totalSamples {
            let t = Double(k) / SR
            let att = t < attackS ? (0.5 - 0.5 * cos(Double.pi * t / attackS)) : 1.0
            let rel = t > durS ? (0.5 + 0.5 * cos(Double.pi * min(1.0, (t - durS) / releaseS))) : 1.0
            let vib = 1.0 + sin(TWO_PI * 4.5 * t) * min(1.0, t / 0.9) * 0.0020

            var vL = 0.0, vR = 0.0
            for i in 0..<4 {
                phases[i] += TWO_PI * f0 * ratios[i] * vib / SR
                let p = phases[i]
                let s = sin(p) + 0.38 * sin(2.0 * p) + 0.15 * sin(3.0 * p)
                vL += s * pansL[i]
                vR += s * pansR[i]
            }
            lpL1 += alpha * (vL - lpL1); lpL2 += alpha * (lpL1 - lpL2)
            lpR1 += alpha * (vR - lpR1); lpR2 += alpha * (lpR1 - lpR2)

            let env = att * rel * amp * 0.22
            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += lpL2 * env * gl
            r[outIdx] += lpR2 * env * gr
        }
    }

    // MARK: 6. Velvet Cello-Style Acoustic Bass (Silky 85ms Swell, ZERO Pitch-Drop Thump!)
    func addVelvetBass(startS: Double, midi: Double, durS: Double, vel: Double) {
        // Keep bass warmly above ~98 Hz (G2 = 43) so it NEVER pressurizes eardrums!
        let safeMidi = midi < 43.0 ? midi + 12.0 : midi
        let f0 = midiToHz(safeMidi)
        let startI = Int((startS * SR).rounded())
        let totalSamples = Int(((durS + 0.9) * SR).rounded())
        let amp = vel * 0.18 // restrained, pillow-warm foundation

        for k in 0..<totalSamples {
            let t = Double(k) / SR
            // 85ms half-cosine silk swell -> zero transient slam on bar downbeats!
            let att = t < 0.085 ? (0.5 - 0.5 * cos(Double.pi * t / 0.085)) : 1.0
            let rel = t < durS ? exp(-t * 0.72) : exp(-durS * 0.72) * exp(-(t - durS) * 3.4)
            let h2D = exp(-t * 2.8)
            let val = sin(TWO_PI * f0 * t) + 0.34 * sin(TWO_PI * 2.0 * f0 * t) * h2D + 0.10 * sin(TWO_PI * 3.0 * f0 * t) * h2D * h2D
            let sample = val * att * rel * amp
            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += sample
            r[outIdx] += sample
        }
    }

    // MARK: 7. Feather-Soft Organic Brush Sway
    func addSoftBrush(startS: Double, amp: Double, pan: Double = 0.0, seed: UInt64 = 101) {
        let startI = Int((startS * SR).rounded())
        let totalSamples = Int((0.080 * SR).rounded())
        let (gl, gr) = panGains(pan)
        var rng = SeededRNG(seed ^ UInt64(abs(startS) * 10000.0))
        var lp = 0.0, hp = 0.0
        for k in 0..<totalSamples {
            let t = Double(k) / SR
            let env = (t < 0.015 ? t / 0.015 : 1.0) * exp(-t * 48.0)
            let noise = rng.nextSigned()
            lp += 0.12 * (noise - lp)
            hp += 0.04 * (lp - hp)
            let sample = (lp - hp) * env * amp
            let outIdx = ((startI + k) % n + n) % n
            l[outIdx] += sample * gl
            r[outIdx] += sample * gr
        }
    }

    // MARK: Circular Studio Cedar-Hall Reverb (100% Seamless Across Loop Seam)
    func applyStudioReverb(wet: Double = 0.35) {
        var sendL = [Double](repeating: 0.0, count: n)
        var sendR = [Double](repeating: 0.0, count: n)
        var fL = 0.0, fR = 0.0
        let alpha = 0.25
        for i in (n - 4096)..<n {
            fL += alpha * (l[i] - fL)
            fR += alpha * (r[i] - fR)
        }
        for i in 0..<n {
            fL += alpha * (l[i] - fL)
            fR += alpha * (r[i] - fR)
            sendL[i] = fL
            sendR[i] = fR
        }

        let taps: [(Int, Double, Double)] = [
            (Int(0.023 * SR), 0.25, 0.10),
            (Int(0.041 * SR), 0.11, 0.23),
            (Int(0.067 * SR), 0.19, 0.13),
            (Int(0.097 * SR), 0.12, 0.18),
            (Int(0.137 * SR), 0.15, 0.09),
            (Int(0.181 * SR), 0.08, 0.14),
            (Int(0.239 * SR), 0.11, 0.07),
            (Int(0.311 * SR), 0.06, 0.10),
            (Int(0.409 * SR), 0.07, 0.05),
            (Int(0.521 * SR), 0.04, 0.06),
            (Int(0.653 * SR), 0.04, 0.03),
            (Int(0.811 * SR), 0.03, 0.04),
        ]

        var revL = [Double](repeating: 0.0, count: n)
        var revR = [Double](repeating: 0.0, count: n)
        for (delay, gl, gr) in taps {
            for i in 0..<n {
                let src = (i - delay + n) % n
                revL[i] += sendL[src] * gl + sendR[src] * (gr * 0.45)
                revR[i] += sendR[src] * gr + sendL[src] * (gl * 0.45)
            }
        }

        var smL = 0.0, smR = 0.0
        for i in (n - 2048)..<n {
            smL += 0.34 * (revL[i] - smL)
            smR += 0.34 * (revR[i] - smR)
        }
        for i in 0..<n {
            smL += 0.34 * (revL[i] - smL)
            smR += 0.34 * (revR[i] - smR)
            l[i] += smL * wet
            r[i] += smR * wet
        }
    }

    // MARK: Circular 2-Pole Butterworth 72 Hz High-Pass Filter (Eliminates ALL Eardrum Sub Pressure!)
    func applyCircularHighPass(cutoffHz: Double = 72.0) {
        let w0 = TWO_PI * cutoffHz / SR
        let cosW = cos(w0)
        let alpha = sin(w0) / sqrt(2.0) // Butterworth Q = 0.7071
        let a0 = 1.0 + alpha
        let b0 = ((1.0 + cosW) * 0.5) / a0
        let b1 = -(1.0 + cosW) / a0
        let b2 = ((1.0 + cosW) * 0.5) / a0
        let a1 = (-2.0 * cosW) / a0
        let a2 = (1.0 - alpha) / a0

        func filterChannel(_ buf: inout [Double]) {
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            // Warm up over final 1.0s of loop so state at sample 0 matches sample n-1 EXACTLY!
            let warmStart = max(0, n - Int(SR))
            for i in warmStart..<n {
                let x0 = buf[i]
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x0; y2 = y1; y1 = y0
            }
            var out = [Double](repeating: 0.0, count: n)
            for i in 0..<n {
                let x0 = buf[i]
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x0; y2 = y1; y1 = y0
                out[i] = y0
            }
            buf = out
        }
        filterChannel(&l)
        filterChannel(&r)
    }

    // MARK: Zero-Seam Mastering & 16-bit Stereo WAV Writer (NO Fade-to-Zero Dip!)
    func writeSeamlessWAV(to path: String, targetPeak: Double = 0.72) {
        // 1. Clean 72 Hz HPF -> zero eardrum pressure thump!
        applyCircularHighPass(cutoffHz: 72.0)

        // 2. Silky circular top-end polish + gentle warmth
        var lpL = 0.0, lpR = 0.0
        for i in (n - 2048)..<n {
            lpL += 0.54 * (l[i] - lpL)
            lpR += 0.54 * (r[i] - lpR)
        }
        for i in 0..<n {
            lpL += 0.54 * (l[i] - lpL)
            lpR += 0.54 * (r[i] - lpR)
            l[i] = tanh((l[i] * 0.36 + lpL * 0.64) * 0.88)
            r[i] = tanh((r[i] * 0.36 + lpR * 0.64) * 0.88)
        }

        // 3. Peak normalize cleanly while preserving true sample-accurate periodic seam!
        var peak = 1e-6
        for i in 0..<n { peak = max(peak, max(abs(l[i]), abs(r[i]))) }
        let scale = targetPeak / peak

        var pcm = [Int16](repeating: 0, count: n * 2)
        for i in 0..<n {
            pcm[2 * i]     = Int16(clamping: Int((l[i] * scale * 32767.0).rounded()))
            pcm[2 * i + 1] = Int16(clamping: Int((r[i] * scale * 32767.0).rounded()))
        }

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let dataSize = UInt32(pcm.count * 2)
        var wav = Data(capacity: 44 + Int(dataSize))
        func appendStr(_ s: String) { wav.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }

        appendStr("RIFF"); appendU32(36 + dataSize); appendStr("WAVE")
        appendStr("fmt "); appendU32(16); appendU16(1); appendU16(2)
        appendU32(48000); appendU32(48000 * 4); appendU16(4); appendU16(16)
        appendStr("data"); appendU32(dataSize)
        pcm.withUnsafeBytes { wav.append($0.bindMemory(to: UInt8.self)) }
        try! wav.write(to: url)
    }
}

// MARK: - Continuous Voice-Led Guitar Fingerpicking (Seamless Across Every Barline!)

func addSeamlessGuitarBar(_ track: StereoTrack, t0: Double, notes: [Double], panBase: Double, seed: UInt64) {
    let step = 0.375 // 8th note at 80 BPM
    // Smooth even dynamics — NO harsh accent spike on beat 1!
    let humanize: [Double] = [0.004, 0.008, -0.003, 0.006, 0.002, 0.009, -0.003, 0.005]
    let vels: [Double]     = [0.64,  0.54,   0.60,  0.52,  0.64,  0.54,   0.60,  0.56]
    for i in 0..<8 {
        let note = notes[i % notes.count]
        track.addNylonPluck(
            startS: t0 + Double(i) * step + humanize[i],
            midi: note, durS: 1.55, vel: vels[i],
            pan: panBase + (i % 2 == 0 ? -0.15 : 0.15),
            brightness: 0.45, seed: seed + UInt64(i * 19)
        )
    }
}

// =========================================================================
// CANDIDATE A1 — 晨光木吉他 · 无缝循环精修版 (F Major · 80 BPM)
// True infinite harmonic loop: tail melody glides F4 -> G4 ⟶ Bar 1 A4 seamlessly!
// Zero bass bump, zero click/pickup chime — pure flowing sunlit acoustic river.
// =========================================================================

func renderA1MorningAcoustic(dur: Double, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct Bar {
        let t0: Double; let bass1: Double; let bass2: Double
        let pad: [Double]; let arp: [Double]; let chord: [Double]
        let melody: [(Double, Double, Double, Double)]
    }

    // Notice how EVERY bar's final two guitar notes & final melody notes voice-lead stepwise into the NEXT bar
    // AND how the final bar's melody (G4 -> F4 -> G4) flows straight across 12.0s/15.0s -> 0.0s into Bar 1's A4!
    let bars: [Bar] = isFiveBar ? [
        // Bar 1 (0s, Light Hero): Fmaj9
        Bar(t0: 0.0, bass1: 48, bass2: 45, // warm C3 -> A2 cello bass (zero low sub rumble!)
            pad: [53, 60, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            chord: [57, 60, 64],
            melody: [(0.00, 69, 1.4, 0.80), (1.50, 67, 0.7, 0.68), (2.25, 65, 0.8, 0.72), (3.00, 69, 0.6, 0.76), (3.50, 72, 0.9, 0.80)]),
        // Bar 2 (3s, Light Glide): Am7(11)
        Bar(t0: 3.0, bass1: 45, bass2: 48,
            pad: [52, 57, 60, 67],
            arp: [52, 57, 60, 64, 67, 64, 60, 62], // ends on D4 -> flows into Bbmaj9!
            chord: [55, 60, 64],
            melody: [(0.00, 76, 1.3, 0.82), (1.375, 74, 0.7, 0.74), (2.125, 72, 0.9, 0.76), (3.00, 74, 0.6, 0.74), (3.50, 72, 0.8, 0.74)]),
        // Bar 3 (6s, Dark Swap!): Bbmaj9 — warm nocturnal harmonic color
        Bar(t0: 6.0, bass1: 46, bass2: 50,
            pad: [53, 58, 62, 69],
            arp: [50, 53, 58, 62, 65, 62, 58, 60], // ends on C4 -> flows into Dm9!
            chord: [58, 62, 65],
            melody: [(0.00, 74, 1.3, 0.82), (1.375, 72, 0.7, 0.74), (2.125, 69, 1.0, 0.76), (3.125, 67, 0.9, 0.72)]),
        // Bar 4 (9s, Dark Glide): Dm9
        Bar(t0: 9.0, bass1: 50, bass2: 45,
            pad: [50, 57, 60, 64],
            arp: [50, 57, 60, 64, 65, 64, 60, 58], // ends on Bb3 -> flows into Gm9/C9!
            chord: [57, 60, 64],
            melody: [(0.00, 72, 1.2, 0.80), (1.25, 69, 0.8, 0.74), (2.00, 67, 0.9, 0.72), (2.875, 65, 0.6, 0.70), (3.375, 67, 0.8, 0.74)]),
        // Bar 5 (12s, Light Return!): C9sus4 -> Cadd9 — seamless tail bridge (F4 -> G4 ⟶ Bar 1 A4!)
        Bar(t0: 12.0, bass1: 48, bass2: 48,
            pad: [55, 60, 62, 67],
            arp: [48, 55, 60, 62, 64, 62, 64, 67], // ends E4 -> G4 ⟶ resolves right onto Fmaj9!
            chord: [55, 60, 62],
            melody: [(0.00, 69, 1.0, 0.78), (1.00, 70, 0.7, 0.74), (1.75, 72, 0.8, 0.78), (2.50, 69, 0.6, 0.72), (3.00, 65, 0.55, 0.70), (3.50, 67, 0.7, 0.74)]),
    ] : [
        // Bar 1 (0s, Timeline): Fmaj9
        Bar(t0: 0.0, bass1: 48, bass2: 45,
            pad: [53, 60, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60], // ends on C4 -> steps smoothly to Dm9!
            chord: [57, 60, 64],
            melody: [(0.00, 69, 1.35, 0.80), (1.50, 67, 0.6, 0.68), (2.00, 65, 0.85, 0.72), (2.75, 67, 0.55, 0.72), (3.25, 69, 0.55, 0.76), (3.625, 72, 0.7, 0.80)]),
        // Bar 2 (3s, Threads): Dm9
        Bar(t0: 3.0, bass1: 50, bass2: 45,
            pad: [50, 57, 64, 65],
            arp: [50, 57, 60, 64, 65, 64, 60, 58], // ends on Bb3 -> steps smoothly to Bbmaj9!
            chord: [57, 60, 64],
            melody: [(0.00, 74, 1.25, 0.82), (1.25, 72, 0.7, 0.74), (2.00, 69, 0.95, 0.76), (2.75, 67, 0.55, 0.68), (3.25, 65, 0.55, 0.70), (3.625, 67, 0.65, 0.74)]),
        // Bar 3 (6s, Notifications): Bbmaj9
        Bar(t0: 6.0, bass1: 46, bass2: 50,
            pad: [53, 58, 62, 69],
            arp: [50, 53, 58, 62, 65, 62, 60, 58], // ends C4 -> Bb3 -> steps to C9sus4!
            chord: [58, 62, 65],
            melody: [(0.00, 69, 0.95, 0.78), (1.00, 70, 0.7, 0.74), (1.75, 72, 0.85, 0.80), (2.50, 74, 0.8, 0.82), (3.25, 77, 0.95, 0.82)]),
        // Bar 4 (9s, Dark Mode): C9sus4 -> Cadd9 — seamless tail->head bridge (E5->D5->C5->A4->F4->G4 ⟶ Bar 1 A4!)
        Bar(t0: 9.0, bass1: 48, bass2: 48,
            pad: [55, 60, 62, 67],
            arp: [48, 55, 60, 62, 64, 62, 64, 67], // ends E4 -> G4 ⟶ resolves like silk into Bar 1 Fmaj9!
            chord: [55, 60, 62],
            melody: [(0.00, 76, 1.1, 0.82), (1.125, 74, 0.65, 0.74), (1.875, 72, 0.8, 0.76), (2.625, 69, 0.55, 0.72), (3.125, 65, 0.50, 0.70), (3.5625, 67, 0.60, 0.75)]),
    ]

    for (idx, b) in bars.enumerated() {
        // Silky velvet bass enters slightly softened (+14ms after beat 1) so nothing slams the eardrum!
        track.addVelvetBass(startS: b.t0 + 0.014, midi: b.bass1, durS: 1.45, vel: 0.56)
        track.addVelvetBass(startS: b.t0 + 1.514, midi: b.bass2, durS: 1.35, vel: 0.44)

        // Lush overlapping cello/string silk pad (starts -0.20s early to crossfade seamlessly across barlines!)
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.22, midi: note, durS: 2.95, amp: 0.135, pan: p)
        }

        // Flowing continuous fingerpicked nylon guitar (zero stop/start feel!)
        addSeamlessGuitarBar(track, t0: b.t0, notes: b.arp, panBase: -0.22, seed: UInt64(210 + idx * 97))

        // Whispered rolled piano chord cushion (staggered gently after beat 1)
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(startS: b.t0 + 0.018 + Double(j) * 0.028, midi: note, durS: 2.55, vel: 0.25, pan: -0.30 + Double(j) * 0.16, warmth: 0.88)
        }

        // Singing felt-piano melody gliding seamlessly from Bar 1 -> 4 -> 1!
        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.20, vel: vel, pan: 0.14 + sin(Double(idx * 5 + mIdx)) * 0.10, warmth: 0.66)
        }

        track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.028, pan: -0.18, seed: UInt64(50 + idx))
        track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.032, pan: 0.18, seed: UInt64(80 + idx))
    }

    track.applyStudioReverb(wet: 0.36)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE A2 — 晨光木吉他 × Rhodes 微光 (A+C 融合无缝循环版 · F Major · 80 BPM)
// Best of BOTH worlds: A's flowing sunlit nylon guitar + C's velvety warm Rhodes
// + delicate rosewood marimba melody sparkles! Zero thump, infinite smooth loop.
// =========================================================================

func renderA2AcousticRhodesFusion(dur: Double, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct Bar {
        let t0: Double; let bass1: Double; let bass2: Double
        let rhodes: [Double]; let pad: [Double]; let arp: [Double]
        let melody: [(Double, Double, Double, Double)]
    }

    let bars: [Bar] = isFiveBar ? [
        Bar(t0: 0.0, bass1: 48, bass2: 45, rhodes: [53, 57, 60, 64, 67], pad: [57, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            melody: [(0.00, 69, 1.3, 0.76), (1.50, 67, 0.7, 0.66), (2.25, 65, 0.8, 0.70), (3.00, 69, 0.6, 0.74), (3.50, 72, 0.8, 0.78)]),
        Bar(t0: 3.0, bass1: 45, bass2: 48, rhodes: [52, 57, 60, 64, 67], pad: [57, 60, 67],
            arp: [52, 57, 60, 64, 67, 64, 60, 62],
            melody: [(0.00, 76, 1.2, 0.78), (1.375, 74, 0.7, 0.72), (2.125, 72, 0.9, 0.74), (3.00, 74, 0.6, 0.72), (3.50, 72, 0.7, 0.72)]),
        Bar(t0: 6.0, bass1: 46, bass2: 50, rhodes: [53, 58, 62, 65, 69], pad: [58, 62, 69],
            arp: [50, 53, 58, 62, 65, 62, 58, 60],
            melody: [(0.00, 74, 1.2, 0.80), (1.375, 72, 0.7, 0.72), (2.125, 69, 1.0, 0.74), (3.125, 67, 0.8, 0.70)]),
        Bar(t0: 9.0, bass1: 50, bass2: 45, rhodes: [50, 57, 60, 64, 65], pad: [57, 60, 64],
            arp: [50, 57, 60, 64, 65, 64, 60, 58],
            melody: [(0.00, 72, 1.1, 0.78), (1.25, 69, 0.8, 0.72), (2.00, 67, 0.85, 0.70), (2.875, 65, 0.6, 0.68), (3.375, 67, 0.75, 0.72)]),
        Bar(t0: 12.0, bass1: 48, bass2: 48, rhodes: [55, 58, 60, 62, 67], pad: [55, 60, 67],
            arp: [48, 55, 60, 62, 64, 62, 64, 67],
            melody: [(0.00, 69, 0.95, 0.76), (1.00, 70, 0.7, 0.72), (1.75, 72, 0.8, 0.76), (2.50, 69, 0.6, 0.70), (3.00, 65, 0.55, 0.68), (3.50, 67, 0.65, 0.74)]),
    ] : [
        Bar(t0: 0.0, bass1: 48, bass2: 45, rhodes: [53, 57, 60, 64, 67], pad: [57, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            melody: [(0.00, 69, 1.3, 0.78), (1.50, 67, 0.6, 0.68), (2.00, 65, 0.85, 0.72), (2.75, 67, 0.55, 0.72), (3.25, 69, 0.55, 0.76), (3.625, 72, 0.7, 0.78)]),
        Bar(t0: 3.0, bass1: 50, bass2: 45, rhodes: [50, 57, 60, 64, 65], pad: [57, 60, 64],
            arp: [50, 57, 60, 64, 65, 64, 60, 58],
            melody: [(0.00, 74, 1.2, 0.80), (1.25, 72, 0.7, 0.72), (2.00, 69, 0.95, 0.74), (2.75, 67, 0.55, 0.68), (3.25, 65, 0.55, 0.70), (3.625, 67, 0.65, 0.74)]),
        Bar(t0: 6.0, bass1: 46, bass2: 50, rhodes: [53, 58, 62, 65, 69], pad: [58, 62, 69],
            arp: [50, 53, 58, 62, 65, 62, 60, 58],
            melody: [(0.00, 69, 0.95, 0.76), (1.00, 70, 0.7, 0.72), (1.75, 72, 0.85, 0.78), (2.50, 74, 0.8, 0.80), (3.25, 77, 0.95, 0.80)]),
        Bar(t0: 9.0, bass1: 48, bass2: 48, rhodes: [55, 58, 60, 62, 67], pad: [55, 60, 67],
            arp: [48, 55, 60, 62, 64, 62, 64, 67],
            melody: [(0.00, 76, 1.1, 0.80), (1.125, 74, 0.65, 0.72), (1.875, 72, 0.8, 0.74), (2.625, 69, 0.55, 0.70), (3.125, 65, 0.50, 0.68), (3.5625, 67, 0.60, 0.74)]),
    ]

    for (idx, b) in bars.enumerated() {
        track.addVelvetBass(startS: b.t0 + 0.016, midi: b.bass1, durS: 1.50, vel: 0.52)
        track.addVelvetBass(startS: b.t0 + 1.516, midi: b.bass2, durS: 1.35, vel: 0.42)

        // Velvety warm Rhodes chord rolled softly like sunshine (no bump!)
        for (j, note) in b.rhodes.enumerated() {
            let p = -0.34 + 0.68 * (Double(j) / Double(max(1, b.rhodes.count - 1)))
            track.addWarmRhodes(startS: b.t0 + 0.012 + Double(j) * 0.030, midi: note, durS: 2.65, vel: 0.42, pan: p, tremoloDepth: 0.22)
        }

        // Light silk string warmth crossfading gently across barlines
        for (j, note) in b.pad.enumerated() {
            track.addSilkPad(startS: b.t0 - 0.22, midi: note, durS: 2.95, amp: 0.105, pan: -0.38 + Double(j) * 0.38)
        }

        // Flowing nylon acoustic guitar fingerpicking (A's natural organic soul!)
        addSeamlessGuitarBar(track, t0: b.t0, notes: b.arp, panBase: -0.24, seed: UInt64(520 + idx * 83))

        // Hybrid melody: Warm Felt Piano + gentle Rosewood Marimba harmonic sparkle!
        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let pan = 0.16 + sin(Double(idx * 4 + mIdx)) * 0.12
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.18, vel: vel * 0.76, pan: pan, warmth: 0.68)
            track.addWoodenMarimba(startS: mt + 0.006, midi: midi, durS: 0.75, vel: vel * 0.48, pan: -pan * 0.65)
        }

        track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.026, pan: -0.20, seed: UInt64(150 + idx))
        track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.030, pan: 0.20, seed: UInt64(180 + idx))
    }

    track.applyStudioReverb(wet: 0.35)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE C2 — 暖调电钢与木琴 · 去嗡鸣无缝循环版 (Eb Major · 80 BPM)
// Candidate C's joyful Rhodes + Marimba vibe with ALL sub-bass thump removed
// and seamless melodic turnaround right back into Bar 1!
// =========================================================================

func renderC2WarmRhodesClean(dur: Double, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct Bar {
        let t0: Double; let bass1: Double; let bass2: Double
        let rhodes: [Double]; let pad: [Double]
        let marimba: [(Double, Double, Double)]
    }

    // Eb Major — all bass in warm 104-155 Hz range (zero sub-80Hz eardrum pressure!)
    // Final bar ends on Eb5 -> F5 ⟶ glides straight into Bar 1 G5!
    let bars: [Bar] = isFiveBar ? [
        Bar(t0: 0.0, bass1: 51, bass2: 46, rhodes: [55, 58, 62, 65, 67], pad: [58, 63, 67],
            marimba: [(0.00, 79, 0.76), (0.75, 77, 0.64), (1.50, 75, 0.72), (2.00, 70, 0.62), (2.50, 72, 0.68), (3.00, 75, 0.72), (3.50, 77, 0.70)]),
        Bar(t0: 3.0, bass1: 43, bass2: 50, rhodes: [55, 58, 62, 65, 69], pad: [55, 62, 65],
            marimba: [(0.00, 79, 0.78), (1.00, 82, 0.76), (1.75, 79, 0.68), (2.50, 77, 0.66), (3.25, 75, 0.70)]),
        Bar(t0: 6.0, bass1: 44, bass2: 51, rhodes: [55, 56, 60, 63, 67], pad: [56, 60, 67],
            marimba: [(0.00, 79, 0.78), (0.75, 77, 0.66), (1.50, 75, 0.72), (2.25, 72, 0.68), (3.00, 75, 0.72), (3.50, 79, 0.74)]),
        Bar(t0: 9.0, bass1: 48, bass2: 43, rhodes: [55, 58, 60, 62, 67], pad: [55, 60, 63],
            marimba: [(0.00, 82, 0.78), (0.75, 79, 0.70), (1.50, 77, 0.68), (2.25, 75, 0.70), (3.00, 72, 0.66), (3.50, 75, 0.70)]),
        Bar(t0: 12.0, bass1: 46, bass2: 46, rhodes: [53, 56, 60, 63, 67], pad: [58, 63, 65],
            marimba: [(0.00, 77, 0.76), (0.75, 79, 0.72), (1.50, 82, 0.76), (2.25, 79, 0.70), (3.00, 75, 0.68), (3.50, 77, 0.72)]),
    ] : [
        // Bar 1 (0s): Ebmaj9
        Bar(t0: 0.0, bass1: 51, bass2: 46, rhodes: [55, 58, 62, 65, 67], pad: [58, 63, 67],
            marimba: [(0.00, 79, 0.78), (0.75, 77, 0.66), (1.50, 75, 0.74), (2.00, 70, 0.62), (2.50, 72, 0.68), (3.00, 75, 0.74), (3.50, 77, 0.70)]),
        // Bar 2 (3s): Cm9
        Bar(t0: 3.0, bass1: 48, bass2: 43, rhodes: [55, 58, 60, 62, 67], pad: [55, 60, 63],
            marimba: [(0.00, 79, 0.78), (0.75, 82, 0.78), (1.50, 79, 0.70), (2.25, 77, 0.68), (3.00, 75, 0.70), (3.50, 72, 0.66)]),
        // Bar 3 (6s): Abmaj9
        Bar(t0: 6.0, bass1: 44, bass2: 51, rhodes: [55, 56, 60, 63, 67], pad: [56, 60, 67],
            marimba: [(0.00, 75, 0.74), (0.75, 77, 0.70), (1.50, 79, 0.78), (2.25, 82, 0.78), (3.00, 84, 0.78), (3.50, 82, 0.70)]),
        // Bar 4 (9s): Bb13sus4 — smooth turnaround Eb5 -> F5 ⟶ Bar 1 G5!
        Bar(t0: 9.0, bass1: 46, bass2: 46, rhodes: [53, 56, 60, 63, 67], pad: [58, 63, 65],
            marimba: [(0.00, 79, 0.78), (0.75, 77, 0.70), (1.50, 75, 0.72), (2.25, 77, 0.68), (3.00, 75, 0.68), (3.50, 77, 0.74)]),
    ]

    for (idx, b) in bars.enumerated() {
        track.addVelvetBass(startS: b.t0 + 0.018, midi: b.bass1, durS: 1.60, vel: 0.50)
        track.addVelvetBass(startS: b.t0 + 1.890, midi: b.bass2, durS: 1.15, vel: 0.40)

        // Smooth balanced Rhodes comping across beat 1 and beat 3 (eliminates downbeat energy surge!)
        for (j, note) in b.rhodes.enumerated() {
            let p = -0.36 + 0.72 * (Double(j) / Double(max(1, b.rhodes.count - 1)))
            let v1 = j == 0 ? 0.26 : 0.34
            track.addWarmRhodes(startS: b.t0 + 0.015 + Double(j) * 0.040, midi: note, durS: 1.75, vel: v1, pan: p, tremoloDepth: 0.20)
            if j >= 1 {
                track.addWarmRhodes(startS: b.t0 + 1.50 + Double(j - 1) * 0.036, midi: note, durS: 1.55, vel: 0.31, pan: -p * 0.7, tremoloDepth: 0.20)
            }
        }

        for (j, note) in b.pad.enumerated() {
            track.addSilkPad(startS: b.t0 - 0.22, midi: note, durS: 2.95, amp: 0.115, pan: -0.35 + Double(j) * 0.35)
        }

        for (mIdx, (beatOff, midi, vel)) in b.marimba.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let pan = (mIdx % 2 == 0) ? 0.20 : -0.16
            track.addWoodenMarimba(startS: mt, midi: midi, durS: 0.85, vel: vel, pan: pan)
            if mIdx == 0 || mIdx == 2 {
                track.addFeltPiano(startS: mt + 0.008, midi: midi, durS: 1.1, vel: vel * 0.36, pan: -pan * 0.5, warmth: 0.72)
            }
        }

        for (sOff, a, p) in [(0.75, 0.028, -0.22), (1.50, 0.020, 0.12), (2.25, 0.032, 0.22), (2.625, 0.018, -0.14)] {
            track.addSoftBrush(startS: b.t0 + sOff, amp: a, pan: p, seed: UInt64(300 + idx * 19 + Int(sOff * 100)))
        }
    }

    track.applyStudioReverb(wet: 0.34)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE AB1 & AB2 — 晨光木吉他 · 呼吸感精修版 (F Major · 80 BPM)
// User-directed phrasing arc (one cohesive through-composed melody, NOT 2 repeated halves):
//   Bar 1 (起): Fresh sunlit opening (A4 - G4 F4 - A4 C5)
//   Bar 2 (承·喘息延长): Spacious 2-note singing sustain (D5 ————— A4 ——————) + airy guitar rest!
//   Bar 3 (转·自然平稳): Calm mid-register step-down (G4 ———— F4 ——— G4 A4), NO forced high climb!
//   Bar 4 (合·微扬轻落回环): Gentle warm lift then soft settle (C5 — Bb4 — A4 — G4 ——) ⟶ Bar 1 A4!
// =========================================================================

func addBreathingGuitarBar(
    _ track: StereoTrack,
    t0: Double,
    notes: [Double],
    activeMask: [Bool], // false = let strings ring & breathe!
    panBase: Double,
    velScale: Double,
    seed: UInt64
) {
    let step = 0.375
    let humanize: [Double] = [0.004, 0.010, -0.004, 0.007, 0.002, 0.011, -0.003, 0.006]
    let vels: [Double]     = [0.62,  0.50,   0.56,  0.46,  0.60,  0.48,   0.52,  0.44]
    for i in 0..<8 {
        guard activeMask[i] else { continue }
        let note = notes[i % notes.count]
        // Notes followed by a rest ring slightly longer for lush acoustic sustain!
        let nextRest = (i + 1 < 8 && !activeMask[i + 1])
        track.addNylonPluck(
            startS: t0 + Double(i) * step + humanize[i],
            midi: note,
            durS: nextRest ? 2.10 : 1.55,
            vel: vels[i] * velScale,
            pan: panBase + (i % 2 == 0 ? -0.15 : 0.15),
            brightness: 0.44,
            seed: seed + UInt64(i * 23)
        )
    }
}

func renderABMorningBreath(dur: Double, rhodesGlow: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct BreathBar {
        let t0: Double
        let bass1: Double
        let bass2: Double? // nil = let bass breathe peacefully without pulsing!
        let pad: [Double]
        let arp: [Double]
        let mask: [Bool]
        let guitarVel: Double
        let chord: [Double]
        let rhodes: [Double]
        let rhodesVel: Double
        let melody: [(Double, Double, Double, Double)] // (beatOff, midi, durBeats, vel)
        let brush: Bool
    }

    let bars: [BreathBar] = isFiveBar ? [
        // HEADER 15s (5 Bars):
        // Bar 1 (0–3s, Light Hero): Fresh sunlit opening
        BreathBar(
            t0: 0.0, bass1: 48, bass2: 45,
            pad: [53, 60, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            mask: [true, true, true, true, true, true, true, false],
            guitarVel: 1.00,
            chord: [57, 60, 64],
            rhodes: [57, 60, 64, 67], rhodesVel: 0.18,
            melody: [
                (0.00, 69, 1.35, 0.80), // A4
                (1.50, 67, 0.65, 0.68), // G4
                (2.125, 65, 0.85, 0.72), // F4
                (3.00, 69, 0.55, 0.75), // A4
                (3.50, 72, 0.85, 0.78)  // C5 -> lifts gently into Bar 2 exhale!
            ],
            brush: true
        ),
        // Bar 2 (3–6s, Light Glide): Extended, relaxed 2-note exhale!
        BreathBar(
            t0: 3.0, bass1: 45, bass2: nil,
            pad: [52, 57, 60, 67],
            arp: [52, 57, 60, 64, 67, 64, 60, 57],
            mask: [true, true, true, false, true, false, true, false],
            guitarVel: 0.86,
            chord: [55, 60, 64],
            rhodes: [55, 60, 64, 67], rhodesVel: 0.22,
            melody: [
                (0.00, 74, 1.90, 0.82), // D5 (long, floating breath!)
                (2.00, 69, 2.15, 0.74)  // A4 (peaceful sustained relaxation!)
            ],
            brush: false
        ),
        // Bar 3 (6–9s, Dark Swap): Calm, natural mid-register step-down (NO forced climb!)
        BreathBar(
            t0: 6.0, bass1: 46, bass2: nil,
            pad: [53, 58, 62, 65],
            arp: [50, 53, 58, 62, 65, 62, 58, 53],
            mask: [true, true, true, false, true, true, false, false],
            guitarVel: 0.84,
            chord: [58, 62, 65],
            rhodes: [53, 58, 62, 65], rhodesVel: 0.30,
            melody: [
                (0.00, 67, 1.60, 0.75), // G4 (natural calm step down from A4)
                (1.75, 65, 1.30, 0.70), // F4 (serene stillness)
                (3.125, 67, 0.90, 0.72) // G4 (soft breath into Bar 4)
            ],
            brush: false
        ),
        // Bar 4 (9–12s, Dark Glide): Gentle warm lantern glow (C5 -> A4 -> G4)
        BreathBar(
            t0: 9.0, bass1: 50, bass2: 45,
            pad: [50, 57, 60, 64],
            arp: [50, 57, 60, 64, 65, 64, 60, 57],
            mask: [true, true, true, true, true, false, true, false],
            guitarVel: 0.92,
            chord: [57, 60, 64],
            rhodes: [57, 60, 64, 67], rhodesVel: 0.32,
            melody: [
                (0.00, 72, 1.35, 0.80), // C5 (warm evening lift)
                (1.50, 69, 1.35, 0.74), // A4
                (2.875, 67, 1.15, 0.70) // G4
            ],
            brush: true
        ),
        // Bar 5 (12–15s, Light Return): Tender slight rise (Bb4->C5) then gentle descent (A4->G4) -> Bar 1 A4!
        BreathBar(
            t0: 12.0, bass1: 48, bass2: nil,
            pad: [55, 58, 60, 67],
            arp: [48, 55, 58, 62, 64, 62, 60, 55],
            mask: [true, true, true, true, true, true, false, false],
            guitarVel: 0.88,
            chord: [55, 60, 62],
            rhodes: [55, 58, 62, 67], rhodesVel: 0.26,
            melody: [
                (0.00, 70, 0.95, 0.76), // Bb4 (sweet turnaround color)
                (1.00, 72, 0.95, 0.78), // C5 (gentle crest)
                (2.00, 69, 0.90, 0.72), // A4 (settling down...)
                (2.875, 67, 1.25, 0.68) // G4 (warm soft sigh ⟶ glides seamlessly into Bar 1 A4!)
            ],
            brush: false
        ),
    ] : [
        // SEARCH 12s (4 Pages × 3.0s):
        // Page 1 · Bar 1 (0–3s, Fmaj9 — 起 · 清新令人耳目一新的开头)
        BreathBar(
            t0: 0.0, bass1: 48, bass2: 45,
            pad: [53, 60, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            mask: [true, true, true, true, true, true, true, false],
            guitarVel: 1.00,
            chord: [57, 60, 64],
            rhodes: [57, 60, 64, 67], rhodesVel: 0.18,
            melody: [
                (0.00, 69, 1.35, 0.80), // A4 (bright warm hello)
                (1.50, 67, 0.65, 0.68), // G4
                (2.125, 65, 0.85, 0.72), // F4
                (3.00, 69, 0.55, 0.75), // A4
                (3.50, 72, 0.85, 0.78)  // C5 -> glides into Page 2!
            ],
            brush: true
        ),
        // Page 2 · Bar 2 (3–6s, Dm9 — 承 · 延长留白，给耳朵舒展喘息！)
        BreathBar(
            t0: 3.0, bass1: 50, bass2: nil,
            pad: [50, 57, 60, 65],
            arp: [50, 57, 60, 64, 65, 64, 60, 57],
            mask: [true, true, true, false, true, false, true, false], // spacious open sustain!
            guitarVel: 0.85,
            chord: [57, 60, 64],
            rhodes: [53, 57, 60, 64], rhodesVel: 0.22,
            melody: [
                (0.00, 74, 1.90, 0.82), // D5 (sustained calm bloom)
                (2.00, 69, 2.15, 0.73)  // A4 (long, unhurried exhale across beats 3 & 4!)
            ],
            brush: false
        ),
        // Page 3 · Bar 3 (6–9s, Bbmaj7 — 转 · 不刻意拉高，安静自然过渡！)
        BreathBar(
            t0: 6.0, bass1: 46, bass2: nil,
            pad: [53, 58, 62, 65],
            arp: [50, 53, 58, 62, 65, 62, 58, 53],
            mask: [true, true, true, false, true, true, false, false],
            guitarVel: 0.84,
            chord: [58, 62, 65],
            rhodes: [53, 58, 62, 65], rhodesVel: 0.30,
            melody: [
                (0.00, 67, 1.55, 0.74), // G4 (soft natural step down from Bar 2's A4)
                (1.75, 65, 1.20, 0.70), // F4 (calm stillness)
                (3.00, 67, 0.55, 0.70), // G4
                (3.50, 69, 0.65, 0.74)  // A4 (gentle organic bridge into Page 4)
            ],
            brush: false
        ),
        // Page 4 · Bar 4 (9–12s, Gm9 -> C9sus4 — 合 · 温柔微扬随后落下，自然衔开头循环！)
        BreathBar(
            t0: 9.0, bass1: 48, bass2: nil,
            pad: [55, 58, 60, 67],
            arp: [48, 55, 58, 62, 64, 62, 60, 55],
            mask: [true, true, true, true, true, true, false, false], // leaves final beat airy!
            guitarVel: 0.88,
            chord: [55, 60, 62],
            rhodes: [55, 58, 62, 67], rhodesVel: 0.28,
            melody: [
                (0.00, 72, 1.05, 0.80), // C5 (gentle warm rise for Page 4)
                (1.125, 70, 0.75, 0.74), // Bb4 (unique tender descending inflection)
                (1.875, 69, 0.90, 0.72), // A4 (relaxing downward...)
                (2.875, 67, 1.25, 0.68)  // G4 (soft resting breath ⟶ flows straight back into Bar 1 A4!)
            ],
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        track.addVelvetBass(startS: b.t0 + 0.016, midi: b.bass1, durS: b.bass2 == nil ? 2.45 : 1.45, vel: 0.52)
        if let b2 = b.bass2 {
            track.addVelvetBass(startS: b.t0 + 1.516, midi: b2, durS: 1.35, vel: 0.40)
        }

        // Seamless overlapping silk pad
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.25, midi: note, durS: 3.00, amp: 0.130, pan: p)
        }

        // Breathing nylon acoustic guitar
        addBreathingGuitarBar(
            track, t0: b.t0, notes: b.arp, activeMask: b.mask,
            panBase: -0.22, velScale: b.guitarVel, seed: UInt64(810 + idx * 97)
        )

        // Tender left-hand piano or velvety Rhodes micro-glow!
        if rhodesGlow {
            for (j, note) in b.rhodes.enumerated() {
                let p = -0.34 + 0.68 * (Double(j) / Double(max(1, b.rhodes.count - 1)))
                track.addWarmRhodes(
                    startS: b.t0 + 0.020 + Double(j) * 0.036,
                    midi: note, durS: 2.60, vel: b.rhodesVel, pan: p, tremoloDepth: 0.18
                )
            }
        } else {
            for (j, note) in b.chord.enumerated() {
                track.addFeltPiano(
                    startS: b.t0 + 0.020 + Double(j) * 0.032,
                    midi: note, durS: 2.65, vel: 0.24, pan: -0.28 + Double(j) * 0.16, warmth: 0.88
                )
            }
        }

        // Expressive, unhurried singing felt-piano melody
        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.10
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.35, vel: vel, pan: p, warmth: 0.64)
            // Subtle warm marimba whisper on Bar 4's gentle lantern glow if rhodesGlow is enabled
            if rhodesGlow && idx == (bars.count - 1) && mIdx <= 1 {
                track.addWoodenMarimba(startS: mt + 0.008, midi: midi, durS: 0.90, vel: vel * 0.34, pan: -0.18)
            }
        }

        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.024, pan: -0.18, seed: UInt64(60 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.026, pan: 0.18, seed: UInt64(90 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.38)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V4 (ab3 & ab4) — 方案 A 呼吸精修 v4 (F Major · 80 BPM)
// Fixes BOTH subtle phrasing flaws identified in v3:
//   1. Bar 2 peak D5 NO LONGER hangs for 2 beats -> touches D5 softly (1.0 beat) and
//      immediately melts stepwise down through C5 (beat 1.0) onto restful A4 (beat 1.5)!
//   2. ZERO dead stall entering Bar 3 -> Bar 2 whispers a gentle G4 breath at beat 3.5,
//      landing squarely on consonant, grounded F4 (5th of Bbmaj7!) on Bar 3 beat 1,
//      with unbroken warm guitar stream flowing smoothly across every barline!
//   3. Bar 4 rises warmly (C5 -> Bb4) then exhales gently downward (A4 -> G4) right into Bar 1 A4.
//
//   ab3 (v4-stream) : 流泉版 — Warm balanced nylon guitar stream + singing felt piano
//   ab4 (v4-pillow) : 轻柔版 — Softer, silkier piano-led serenity with gentler guitar cushion
// =========================================================================

func renderV4BreathStream(dur: Double, pillowMode: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V4Bar {
        let t0: Double
        let bass1: Double
        let bass2: Double
        let pad: [Double]
        let arp: [Double]
        let mask: [Bool]
        let guitarVel: Double
        let chord: [Double]
        let melody: [(Double, Double, Double, Double)] // (beatOff, midi, durBeats, vel)
        let brush: Bool
    }

    let bars: [V4Bar] = isFiveBar ? [
        // HEADER 15s (5 Bars × 3.0s):
        // Bar 1 (0–3s, Fmaj9 — 起 · 清新耳目一新)
        V4Bar(
            t0: 0.0, bass1: 48, bass2: 45,
            pad: [53, 60, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            mask: [true, true, true, true, true, true, true, true],
            guitarVel: 0.96,
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.30, 0.80), // A4
                (1.50, 67, 0.55, 0.68), // G4
                (2.00, 65, 0.90, 0.72), // F4
                (3.00, 69, 0.50, 0.74), // A4
                (3.50, 72, 0.55, 0.78)  // C5 -> lifts softly into Bar 2
            ],
            brush: true
        ),
        // Bar 2 (3–6s, Am7 — 承 · 轻触 D5 立刻顺滑落回 A4 真正放松，末拍轻气口引向第 3 段)
        V4Bar(
            t0: 3.0, bass1: 45, bass2: 48,
            pad: [52, 57, 60, 67],
            arp: [52, 57, 60, 64, 67, 64, 60, 57],
            mask: [true, true, true, false, true, true, true, true], // skips only mid-bar beat 2.5, flows seamlessly into Bar 3!
            guitarVel: 0.84,
            chord: [55, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78), // D5 (light graceful crest — NEVER hangs!)
                (1.00, 72, 0.50, 0.68), // C5 (gentle melting step down)
                (1.50, 69, 1.85, 0.74), // A4 (warm restful landing & peaceful breath!)
                (3.50, 67, 0.55, 0.58)  // G4 (whisper breath leading smoothly into Bar 3 F4!)
            ],
            brush: false
        ),
        // Bar 3 (6–9s, Bbmaj7 — 转 · 稳落 F4 自然舒缓切深色，零悬空零憋气)
        V4Bar(
            t0: 6.0, bass1: 46, bass2: 50,
            pad: [53, 58, 62, 65],
            arp: [50, 53, 58, 62, 65, 62, 58, 53],
            mask: [true, true, true, false, true, true, true, true],
            guitarVel: 0.82,
            chord: [58, 62, 65],
            melody: [
                (0.00, 65, 1.40, 0.75), // F4 (100% grounded 5th of Bbmaj7 — pure calm!)
                (1.50, 67, 0.75, 0.68), // G4 (gentle ripple)
                (2.25, 69, 1.15, 0.72), // A4 (warm serene smile)
                (3.50, 67, 0.55, 0.60)  // G4 (soft breath into Bar 4)
            ],
            brush: false
        ),
        // Bar 4 (9–12s, Dm9 — 续 · 夜色柔光微起)
        V4Bar(
            t0: 9.0, bass1: 50, bass2: 45,
            pad: [50, 57, 60, 64],
            arp: [50, 57, 60, 64, 65, 64, 60, 58],
            mask: [true, true, true, true, true, true, true, true],
            guitarVel: 0.88,
            chord: [57, 60, 64],
            melody: [
                (0.00, 65, 1.15, 0.74), // F4
                (1.25, 69, 1.10, 0.76), // A4
                (2.50, 72, 0.95, 0.78), // C5 (gentle warm lantern glow)
                (3.50, 70, 0.55, 0.68)  // Bb4
            ],
            brush: true
        ),
        // Bar 5 (12–15s, C9sus4 — 合 · 轻柔落定 G4，自然流回 Bar 1 A4 循环)
        V4Bar(
            t0: 12.0, bass1: 48, bass2: 48,
            pad: [55, 58, 60, 67],
            arp: [48, 55, 58, 62, 64, 62, 64, 67], // ends E4 -> G4 ⟶ resolves right onto Bar 1 Fmaj9!
            mask: [true, true, true, false, true, true, true, true],
            guitarVel: 0.84,
            chord: [55, 60, 62],
            melody: [
                (0.00, 69, 1.00, 0.76), // A4
                (1.125, 70, 0.65, 0.72), // Bb4 (subtle warm inflection)
                (1.875, 69, 0.75, 0.70), // A4
                (2.625, 67, 1.35, 0.66)  // G4 (soft serene landing ⟶ Bar 1 A4!)
            ],
            brush: false
        ),
    ] : [
        // SEARCH 12s (4 Pages × 3.0s):
        // Page 1 · Bar 1 (0–3s, Fmaj9 — 起 · 清新耳目一新)
        V4Bar(
            t0: 0.0, bass1: 48, bass2: 45,
            pad: [53, 60, 64, 69],
            arp: [53, 60, 64, 67, 69, 67, 64, 60],
            mask: [true, true, true, true, true, true, true, true],
            guitarVel: 0.96,
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.30, 0.80), // A4 (fresh sunlit hello)
                (1.50, 67, 0.55, 0.68), // G4
                (2.00, 65, 0.90, 0.72), // F4
                (3.00, 69, 0.50, 0.74), // A4
                (3.50, 72, 0.55, 0.78)  // C5 -> glides naturally into Page 2 crest!
            ],
            brush: true
        ),
        // Page 2 · Bar 2 (3–6s, Dm9 — 承 · 轻触 D5 立刻顺滑落回 A4 舒展喘息，末拍轻气口承接第 3 页!)
        V4Bar(
            t0: 3.0, bass1: 50, bass2: 45,
            pad: [50, 57, 60, 65],
            arp: [50, 57, 60, 64, 65, 64, 60, 58], // flows seamlessly toward Bbmaj7!
            mask: [true, true, true, false, true, true, true, true], // skips only 1 inner step -> breathable yet NEVER stalls!
            guitarVel: 0.84,
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.79), // D5 (light crest for only 0.75s — zero hanging!)
                (1.00, 72, 0.50, 0.69), // C5 (silky melting step down)
                (1.50, 69, 1.85, 0.74), // A4 (true warm exhale & relaxed sustain!)
                (3.50, 67, 0.55, 0.58)  // G4 (soft whisper breath right across barline!)
            ],
            brush: false
        ),
        // Page 3 · Bar 3 (6–9s, Bbmaj7 — 转 · 稳稳落进 F4 如流水般舒缓，不拉高、不憋气!)
        V4Bar(
            t0: 6.0, bass1: 46, bass2: 50,
            pad: [53, 58, 62, 65],
            arp: [50, 53, 58, 62, 65, 62, 58, 55], // ends G3 -> flows smoothly into C9sus4!
            mask: [true, true, true, false, true, true, true, true],
            guitarVel: 0.82,
            chord: [58, 62, 65],
            melody: [
                (0.00, 65, 1.40, 0.75), // F4 (completely consonant, grounded warm peace!)
                (1.50, 67, 0.75, 0.68), // G4 (gentle breeze)
                (2.25, 69, 1.05, 0.72), // A4 (calm open smile)
                (3.375, 70, 0.60, 0.64) // Bb4 (silky organic pickup into Page 4!)
            ],
            brush: false
        ),
        // Page 4 · Bar 4 (9–12s, C9sus4 -> Cadd9 — 合 · 温柔微扬 C5 随后缓落 A4->G4，无缝流回 Bar 1 A4!)
        V4Bar(
            t0: 9.0, bass1: 48, bass2: 48,
            pad: [55, 58, 60, 67],
            arp: [48, 55, 58, 62, 64, 62, 64, 67], // ends E4 -> G4 ⟶ resolves like velvet onto Bar 1 Fmaj9!
            mask: [true, true, true, false, true, true, true, true],
            guitarVel: 0.85,
            chord: [55, 60, 62],
            melody: [
                (0.00, 72, 0.95, 0.79), // C5 (warm evening lift — gentle, never shrill!)
                (1.00, 70, 0.65, 0.72), // Bb4 (tender unique descending color)
                (1.75, 69, 0.80, 0.70), // A4 (softly settling down...)
                (2.625, 67, 1.35, 0.66) // G4 (peaceful warm breath ⟶ melts straight into Bar 1 A4!)
            ],
            brush: false
        ),
    ]

    let guitarScale = pillowMode ? 0.68 : 0.96
    let padScale = pillowMode ? 1.18 : 1.00

    for (idx, b) in bars.enumerated() {
        track.addVelvetBass(startS: b.t0 + 0.016, midi: b.bass1, durS: 1.55, vel: 0.48)
        track.addVelvetBass(startS: b.t0 + 1.516, midi: b.bass2, durS: 1.45, vel: 0.36)

        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.28, midi: note, durS: 3.05, amp: 0.130 * padScale, pan: p)
        }

        addBreathingGuitarBar(
            track, t0: b.t0, notes: b.arp, activeMask: b.mask,
            panBase: -0.22, velScale: b.guitarVel * guitarScale, seed: UInt64(940 + idx * 97)
        )

        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.022 + Double(j) * 0.032,
                midi: note, durS: 2.65, vel: pillowMode ? 0.28 : 0.22,
                pan: -0.28 + Double(j) * 0.16, warmth: 0.88
            )
        }

        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.10
            track.addFeltPiano(
                startS: mt, midi: midi, durS: durB * 0.75 + 0.38,
                vel: vel * (pillowMode ? 1.04 : 1.00), pan: p, warmth: pillowMode ? 0.68 : 0.62
            )
        }

        if b.brush && !pillowMode {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.022, pan: -0.18, seed: UInt64(70 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.024, pan: 0.18, seed: UInt64(95 + idx))
        }
    }

    track.applyStudioReverb(wet: pillowMode ? 0.41 : 0.37)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V5 (v5-spacious) — 乐理重构终极版 (F Major · 80 BPM)
// True Conservatory Phrasing: Active-Antecedent (Bars 1-2) -> Grounded Half-Time Consequent (Bars 3-4)
// Solfège (F=1 Do, G=2 Re, A=3 Mi, Bb=4 Fa, C=5 Sol, D=6 La):
//   Bar 1 (Fmaj9, 8th-note buoyant):  3 — 2 1 · 3 5        (清新开场: 噔— 噔噔 噔噔)
//   Bar 2 (Dm9, immediate release):   6 · 5 3 — 2          (轻触高点 6 立刻柔落 5-3-2，吉他末两拍放慢成四分音符)
//   Bar 3 (Bbmaj7, HALF-TIME SPACE!): 1 ———— · 3 ————      (深暖低音 Bb2 拉下重心，吉他切半速四分流水，噔~~~ 噔~~~ 彻底放松!)
//   Bar 4 (Gm7->C9sus4, calm sigh):   4 ———— · 3 — · 2 ——  (克制微抬 4 缓落 3→2，柔和呼吸流回 Bar 1 的 3 无缝循环!)
// =========================================================================

func addCustomGuitarSteps(
    _ track: StereoTrack,
    t0: Double,
    steps: [(Double, Double, Double, Double)], // (beatOffset, midi, durS, vel)
    panBase: Double,
    seed: UInt64
) {
    for (idx, (beatOff, midi, durS, vel)) in steps.enumerated() {
        let jitter = (idx % 2 == 0) ? 0.004 : 0.009
        let pan = panBase + (idx % 2 == 0 ? -0.15 : 0.15)
        track.addNylonPluck(
            startS: t0 + beatOff * 0.75 + jitter,
            midi: midi,
            durS: durS,
            vel: vel,
            pan: pan,
            brightness: 0.44,
            seed: seed + UInt64(idx * 31)
        )
    }
}

func renderV5SpaciousCycle(dur: Double, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V5Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)] // (beatOff, midi, durS, vel) — allows warm stepwise descending bass!
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)] // explicit rhythmic density (8ths in Bar 1 -> quarters in Bar 3!)
        let chord: [Double]
        let melody: [(Double, Double, Double, Double)]
        let brush: Bool
    }

    let bars: [V5Bar] = isFiveBar ? [
        // HEADER 15s (5 Bars × 3.0s):
        // Bar 1 (0–3s, Fmaj9): 3 — 2 1 · 3 5 (8th-note sunlit opening, airy bass F3->E3)
        V5Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.50, 0.44), (2.0, 52, 1.45, 0.40)], // stepwise F3 -> E3!
            pad: [53, 60, 64, 69], padAmp: 0.115,
            guitar: [
                (0.0, 53, 1.5, 0.58), (0.5, 60, 1.5, 0.48), (1.0, 64, 1.5, 0.54), (1.5, 67, 1.5, 0.46),
                (2.0, 69, 1.5, 0.56), (2.5, 67, 1.5, 0.46), (3.0, 64, 1.5, 0.52), (3.5, 60, 1.5, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82), // 3 (A4)
                (1.50, 67, 0.50, 0.70), // 2 (G4)
                (2.00, 65, 0.85, 0.74), // 1 (F4)
                (3.00, 69, 0.48, 0.76), // 3 (A4)
                (3.50, 72, 0.55, 0.80), // 5 (C5) -> lifts into Bar 2
            ],
            brush: true
        ),
        // Bar 2 (3–6s, Am7/Dm): 6 · 5 3 — 2 (gentle peak -> releases down; guitar decelerates to quarter notes in beats 3-4!)
        V5Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.55, 0.48), (2.0, 48, 1.55, 0.46)], // stepwise D3 -> C3!
            pad: [52, 57, 60, 64], padAmp: 0.125,
            guitar: [
                (0.0, 50, 1.6, 0.52), (0.5, 57, 1.6, 0.44), (1.0, 60, 1.6, 0.48), (1.5, 64, 1.8, 0.42),
                (2.0, 60, 2.1, 0.48), (3.0, 57, 2.2, 0.44), // decelerates smoothly into half-time!
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.78, 0.79), // 6 (D5) light crest
                (0.875, 72, 0.52, 0.66), // 5 (C5) soft glide
                (1.50, 69, 0.80, 0.68), // 3 (A4) soft melt
                (2.375, 67, 1.55, 0.66), // 2 (G4) descending calmly toward ground
            ],
            brush: false
        ),
        // Bar 3 (6–9s, Bbmaj7 — Dark Swap): GROUNDED Bb2 BASS + HALF-TIME SPACIOUS "噔~~~ 噔~~~" (1 ———— · 3 ————)
        V5Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.95, 0.62)], // warm deep Bb2 (116.5Hz) pulls gravity gently down to earth!
            pad: [46, 53, 58, 62], padAmp: 0.145,
            guitar: [
                (0.0, 46, 2.4, 0.50), (1.0, 53, 2.3, 0.44), (2.0, 58, 2.4, 0.48), (3.0, 62, 2.3, 0.44),
            ], // lush half-time quarter-note ripples — slow, spacious, NEVER empty!
            chord: [53, 58, 62],
            melody: [
                (0.00, 65, 2.00, 0.78), // 1 (F4 — pure grounded Tonic Do!! 噔~~~)
                (2.00, 69, 2.05, 0.76), // 3 (A4 — warm luminous Maj7 sky!! 噔~~~)
            ],
            brush: false
        ),
        // Bar 4 (9–12s, Dm9 — Dark Glide): Continues spacious calm (2 ———— · 1 ————)
        V5Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.95, 0.54)], // deep warm A2 (110Hz) smooth half-step down from Bb2!
            pad: [50, 57, 60, 64], padAmp: 0.140,
            guitar: [
                (0.0, 50, 2.3, 0.48), (1.0, 57, 2.2, 0.42), (2.0, 60, 2.3, 0.46), (3.0, 57, 2.2, 0.42),
            ],
            chord: [53, 57, 60],
            melody: [
                (0.00, 67, 1.95, 0.74), // 2 (G4 — peaceful nocturnal breeze)
                (2.00, 65, 1.95, 0.72), // 1 (F4 — serene resting stillness)
            ],
            brush: false
        ),
        // Bar 5 (12–15s, Gm7 -> C9sus4 — Light Return): Gentle warm lift 4 -> 3 -> 2 -> melts into Bar 1's 3!
        V5Bar(
            t0: 12.0,
            bassNotes: [(0.0, 43, 1.60, 0.52), (2.0, 48, 1.55, 0.50)], // warm G2 -> C3 authentic cadence!
            pad: [50, 55, 58, 64], padAmp: 0.130,
            guitar: [
                (0.0, 50, 2.1, 0.48), (1.0, 55, 2.0, 0.44), (2.0, 58, 2.0, 0.46),
                (3.0, 60, 1.6, 0.44), (3.5, 64, 1.6, 0.46), // gently wakes back into Bar 1's 8th-note motion!
            ],
            chord: [55, 58, 62],
            melody: [
                (0.00, 70, 1.45, 0.76), // 4 (Bb4 — gentle sunset bloom, never shrill!)
                (1.50, 69, 1.00, 0.72), // 3 (A4 — softly coming down)
                (2.625, 67, 1.40, 0.68), // 2 (G4 — warm sigh ⟶ glides seamlessly into Bar 1 A4!)
            ],
            brush: false
        ),
    ] : [
        // SEARCH 12s (4 Pages × 3.0s):
        // Page 1 · Bar 1 (0–3s, Fmaj9 — 起 · 清新耳目一新): 3 — 2 1 · 3 5
        V5Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.50, 0.44), (2.0, 52, 1.45, 0.40)], // buoyant stepwise F3 -> E3
            pad: [53, 60, 64, 69], padAmp: 0.115,
            guitar: [
                (0.0, 53, 1.5, 0.58), (0.5, 60, 1.5, 0.48), (1.0, 64, 1.5, 0.54), (1.5, 67, 1.5, 0.46),
                (2.0, 69, 1.5, 0.56), (2.5, 67, 1.5, 0.46), (3.0, 64, 1.5, 0.52), (3.5, 60, 1.5, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82), // 3 (A4)
                (1.50, 67, 0.50, 0.70), // 2 (G4)
                (2.00, 65, 0.85, 0.74), // 1 (F4)
                (3.00, 69, 0.48, 0.76), // 3 (A4)
                (3.50, 72, 0.55, 0.80), // 5 (C5) ->切第二页
            ],
            brush: true
        ),
        // Page 2 · Bar 2 (3–6s, Dm9 — 承 · 高点起落，柔和下沉，后两拍吉他自然放慢!): 6 · 5 3 — 2
        V5Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.55, 0.48), (2.0, 48, 1.55, 0.46)], // stepwise descending D3 -> C3
            pad: [50, 57, 60, 64], padAmp: 0.125,
            guitar: [
                (0.0, 50, 1.6, 0.52), (0.5, 57, 1.6, 0.44), (1.0, 60, 1.6, 0.48), (1.5, 64, 1.8, 0.42),
                (2.0, 60, 2.1, 0.48), (3.0, 57, 2.2, 0.44), // graceful transition from 8ths -> quarters!
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.78, 0.79), // 6 (D5) light crest
                (0.875, 72, 0.52, 0.65), // 5 (C5) whisper drop
                (1.50, 69, 0.80, 0.68), // 3 (A4) gentle exhale
                (2.375, 67, 1.55, 0.66), // 2 (G4) smoothly descends toward Page 3's Do!
            ],
            brush: false
        ),
        // Page 3 · Bar 3 (6–9s, Bbmaj7 — 转 · 低音 Bb2 拉下来 + 吉他切半速，宽阔舒缓「噔~~~ 噔~~~」!)
        V5Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.95, 0.62)], // warm deep Bb2 (116.5Hz) grounds the whole piece!
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.4, 0.50), (1.0, 53, 2.3, 0.44), (2.0, 58, 2.4, 0.48), (3.0, 62, 2.3, 0.44),
            ], // spacious quarter-note waves — slower rhythm, rich sustain, ZERO empty gaps!
            chord: [53, 58, 62],
            melody: [
                (0.00, 65, 2.00, 0.78), // 1 (F4 — Tonic Do! Complete grounding & relief! 噔~~~)
                (2.00, 69, 2.05, 0.76), // 3 (A4 — Warm luminous Maj7! Open sky! 噔~~~)
            ],
            brush: false
        ),
        // Page 4 · Bar 4 (9–12s, Gm7 -> C9sus4 — 合 · 同样舒缓不杂乱，3 音温柔微扬轻落，丝滑回开头!)
        V5Bar(
            t0: 9.0,
            bassNotes: [(0.0, 43, 1.60, 0.52), (2.0, 48, 1.55, 0.50)], // warm G2 -> C3 smooth cadence home!
            pad: [50, 55, 58, 64], padAmp: 0.132,
            guitar: [
                (0.0, 50, 2.1, 0.48), (1.0, 55, 2.0, 0.44), (2.0, 58, 2.0, 0.46),
                (3.0, 60, 1.6, 0.44), (3.5, 64, 1.6, 0.46), // gentle 8th-note pickup wakes smoothly into Bar 1!
            ],
            chord: [55, 58, 62],
            melody: [
                (0.00, 70, 1.45, 0.76), // 4 (Bb4 — gentle warm glow, never high or busy!)
                (1.50, 69, 1.00, 0.72), // 3 (A4 — serene step down)
                (2.625, 67, 1.40, 0.68), // 2 (G4 — peaceful breath ⟶ melts straight into Bar 1 A4!)
            ],
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }

        // Overlapping warm chamber silk pad (thickens slightly on Bar 3 so half-time feels lush, NEVER hollow!)
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.30, midi: note, durS: 3.10, amp: b.padAmp, pan: p)
        }

        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1100 + idx * 89))

        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.036,
                midi: note, durS: 2.70, vel: 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.88
            )
        }

        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.45, vel: vel, pan: p, warmth: 0.64)
        }

        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.020, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.022, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.40)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V6 (v6a & v6b) — 方案 A 终极舒缓循环版 (F Major · 80 BPM)
// Surgical fixes from v5 feedback:
//   1. Bar 2 trimmed from 4 notes -> 3 clean unhurried notes: 6(D5) · 5(C5) · 3(A4~~~~)
//      (ZERO extra dense 4th note! Guitar also drops extra 1.5 pluck for silky deceleration)
//   2. Bar 3 & Bar 4 now share ONE unified, serene, half-time spacious atmosphere:
//      - Bar 3 (Bbmaj7, sustained Bb2): 1(F4)~~~~ · 3(A4)~~~~
//      - Bar 4 (SINGLE chord C9sus4, sustained C3 — no mid-bar chord/mood jump!):
//          v6a (渐静舒落): 2(G4)~~~~ · 1(F4)~~~~  (pure tranquil descent -> sus4 glow into Bar 1 A4!)
//          v6b (悠扬回环): 4(Bb4)~~~~ · 2(G4)~~~~ (gentle echo of Bar 3 rise -> long calm exhale into Bar 1 A4!)
//   3. Zero abrupt tail cutoff: Beat 3 final half-note (t=10.5s) & Beat 4 soft guitar note (t=11.25s)
//      ring smoothly WITH long gentle sustain RIGHT ACROSS 12.0s->0.0s (no jarring 11.625s wake-up pluck!).
// =========================================================================

func renderV6SereneCycle(dur: Double, bar4Lift: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V6Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double)] // (beatOff, midi, durBeats, vel)
        let brush: Bool
    }

    let bars: [V6Bar] = isFiveBar ? [
        // HEADER 15s (5 Bars × 3.0s):
        // Bar 1 (0–3s, Fmaj9): 3 — 2 1 · 3 5 (fresh sunlit opening)
        V6Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.115,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82), // 3 (A4)
                (1.50, 67, 0.50, 0.70), // 2 (G4)
                (2.00, 65, 0.85, 0.74), // 1 (F4)
                (3.00, 69, 0.48, 0.76), // 3 (A4)
                (3.50, 72, 0.55, 0.80), // 5 (C5)
            ],
            brush: true
        ),
        // Bar 2 (3–6s, Am7): CLEAN 3 NOTES (6 · 5 · 3~~~~) — ZERO extra busy note!
        V6Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.60, 0.46), (2.0, 48, 1.65, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.128,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.2, 0.44), (3.0, 60, 2.3, 0.42), // effortless glide into quarter-note space!
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78), // 6 (D5) light crest
                (1.00, 72, 0.95, 0.67), // 5 (C5) unhurried soft drop
                (2.00, 69, 2.20, 0.70), // 3 (A4~~~~) long peaceful breath down toward Bar 3!
            ],
            brush: false
        ),
        // Bar 3 (6–9s, Bbmaj7 — Dark Swap): Grounded Bb2 + Spacious "1~~~~ · 3~~~~"
        V6Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)], // continuous warm cello breath!
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [
                (0.00, 65, 2.15, 0.77), // 1 (F4~~~~)
                (2.00, 69, 2.20, 0.75), // 3 (A4~~~~)
            ],
            brush: false
        ),
        // Bar 4 (9–12s, Dm9 — Dark Glide): Continues tranquil half-time "2~~~~ · 1~~~~"
        V6Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.52), (2.0, 45, 2.2, 0.42)],
            pad: [50, 57, 60, 64], padAmp: 0.152,
            guitar: [
                (0.0, 50, 2.6, 0.46), (1.0, 57, 2.5, 0.42), (2.0, 60, 2.6, 0.46), (3.0, 57, 2.6, 0.44),
            ],
            chord: [53, 57, 60],
            melody: [
                (0.00, 67, 2.15, 0.73), // 2 (G4~~~~)
                (2.00, 65, 2.20, 0.70), // 1 (F4~~~~)
            ],
            brush: false
        ),
        // Bar 5 (12–15s, C9sus4 — SINGLE serene chord, rich continuous sustain across 15.0s->0.0s!)
        V6Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)], // rich warm C3 never dies before seam!
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.48), (3.0, 64, 2.8, 0.48),
            ], // beat 4 rings warmly RIGHT ACROSS 15.0s->0.0s!
            chord: [55, 60, 62],
            melody: bar4Lift ? [
                (0.00, 70, 2.10, 0.74), // 4 (Bb4~~~~) gentle warm echo
                (2.00, 67, 2.80, 0.72), // 2 (G4~~~~~~) lush pedal-sustained tail into Bar 1 A4!
            ] : [
                (0.00, 69, 2.10, 0.73), // 3 (A4~~~~)
                (2.00, 67, 2.80, 0.72), // 2 (G4~~~~~~) ultra-calm unbroken exhale into Bar 1 A4!
            ],
            brush: false
        ),
    ] : [
        // SEARCH 12s (4 Pages × 3.0s):
        // Page 1 · Bar 1 (0–3s, Fmaj9 — 起 · 清新开场): 3 — 2 1 · 3 5
        V6Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82), // 3 (A4)
                (1.50, 67, 0.50, 0.70), // 2 (G4)
                (2.00, 65, 0.85, 0.74), // 1 (F4)
                (3.00, 69, 0.48, 0.76), // 3 (A4)
                (3.50, 72, 0.55, 0.80), // 5 (C5) -> 切第2页
            ],
            brush: true
        ),
        // Page 2 · Bar 2 (3–6s, Dm9 — 承 · 极简 3 音顺滑减速，彻底去掉多余密集音!): 6 · 5 · 3~~~~
        V6Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78), // 6 (D5) light crest
                (1.00, 72, 0.95, 0.67), // 5 (C5) gentle unhurried step
                (2.00, 69, 2.30, 0.72), // 3 (A4~~~~) serene half-note rest into Page 3!
            ],
            brush: false
        ),
        // Page 3 · Bar 3 (6–9s, Bbmaj7 — 转 · 沉稳低音 Bb2 + 半速宽音「1~~~~ · 3~~~~」!)
        V6Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [
                (0.00, 65, 2.15, 0.77), // 1 (F4~~~~) grounded Do!
                (2.00, 69, 2.20, 0.75), // 3 (A4~~~~) gentle open lift into Page 4!
            ],
            brush: false
        ),
        // Page 4 · Bar 4 (9–12s, SINGLE chord C9sus4 — 延续第 3 页同样舒缓宽阔氛围，尾音满韵贯通循环点!)
        V6Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)], // sustained warm C3 never drops out!
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.48), (3.0, 64, 2.8, 0.48),
            ],
            chord: [55, 60, 62],
            melody: bar4Lift ? [
                (0.00, 70, 2.10, 0.74), // 4 (Bb4~~~~) soft glowing response to Page 3's 3(A4)
                (2.00, 67, 2.80, 0.72), // 2 (G4~~~~~~) lush pedal-sustained tail into Bar 1 A4!
            ] : [
                (0.00, 67, 2.10, 0.74), // 2 (G4~~~~) pure gentle descent from Page 3's 3(A4)
                (2.00, 65, 2.80, 0.73), // 1 (F4~~~~~~) lush Tonic Do sus4 tail melting into Bar 1 A4!
            ],
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }

        // Extra-long lush pad crossfade (-0.55s lead, 3.45s hold) -> ZERO tail energy dip before 12.0s->0.0s!
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }

        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1300 + idx * 97))

        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.88
            )
        }

        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            // Generous natural piano sustain (+0.65s tail) so final half-note NEVER cuts off abruptly!
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: 0.65)
        }

        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V6A-FINAL (v6a1 & v6a2) — 方案 A 最终精修（微调第 2 段倒数第二音 + 第 4 段连续「噔噔」收尾）
//   1. Bar 2: 6(D5, 0.875b) -> 5(C5, 1.375b — stretched noticeably longer!) -> 3(A4, 1.85b)
//   2. Bar 4 (same serene C9sus4 half-time space, NO abrupt end):
//        v6a1 (极简双音收尾): 2(G4, 2.25b) -> 1(F4, 0.75b) -> 2(G4, 1.15b) ⟶ Bar 1 3(A4)!
//        v6a2 (柔韵回环收尾): 2(G4, 1.85b) -> 1(F4, 0.70b) -> 7(E4, 0.60b) -> 2(G4, 0.95b) ⟶ Bar 1 3(A4)!
// =========================================================================

func renderV6AFinal(dur: Double, richTurn: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V6Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double)]
        let brush: Bool
    }

    let bar2Melody: [(Double, Double, Double, Double)] = [
        (0.00,  74, 0.85, 0.78), // 6 (D5) light crest
        (0.875, 72, 1.38, 0.69), // 5 (C5 — 倒数第二个音加长到 1.38 拍，温柔舒展！)
        (2.25,  69, 1.95, 0.71), // 3 (A4~~~) warm landing into Bar 3!
    ]

    let bar4ClosingSearch: [(Double, Double, Double, Double)] = richTurn ? [
        (0.00,  67, 1.85, 0.74), // 2 (G4~~~~) serene continuation of Bar 3
        (1.875, 65, 0.70, 0.68), // 1 (F4) gentle grounding
        (2.625, 64, 0.58, 0.63), // 7 (E4) tender sigh
        (3.25,  67, 1.15, 0.68), // 2 (G4 — flows smoothly across 12.0s->0.0s into A4!)
    ] : [
        (0.00,  67, 2.25, 0.74), // 2 (G4~~~~~) serene spacious continuation of Bar 3
        (2.375, 65, 0.78, 0.67), // 1 (F4 — 第一个轻柔「噔」)
        (3.125, 67, 1.25, 0.69), // 2 (G4 — 第二个连贯「噔」绵延滑进开头 A4!)
    ]

    let bar5ClosingHeader: [(Double, Double, Double, Double)] = richTurn ? [
        (0.00,  69, 1.85, 0.73), // 3 (A4~~~~)
        (1.875, 65, 0.70, 0.67), // 1 (F4)
        (2.625, 64, 0.58, 0.62), // 7 (E4)
        (3.25,  67, 1.15, 0.68), // 2 (G4 ⟶ Bar 1 A4)
    ] : [
        (0.00,  69, 2.25, 0.73), // 3 (A4~~~~~)
        (2.375, 65, 0.78, 0.66), // 1 (F4 — 轻柔「噔」)
        (3.125, 67, 1.25, 0.68), // 2 (G4 — 连贯「噔」滑进开头 A4!)
    ]

    let bars: [V6Bar] = isFiveBar ? [
        V6Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82), (1.50, 67, 0.50, 0.70), (2.00, 65, 0.85, 0.74),
                (3.00, 69, 0.48, 0.76), (3.50, 72, 0.55, 0.80),
            ],
            brush: true
        ),
        V6Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.1, 0.46),
                (2.25, 64, 2.3, 0.45), (3.125, 60, 2.4, 0.43),
            ],
            chord: [57, 60, 64],
            melody: bar2Melody,
            brush: false
        ),
        V6Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.77), (2.00, 69, 2.20, 0.75)],
            brush: false
        ),
        V6Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.52), (2.0, 45, 2.2, 0.42)],
            pad: [50, 57, 60, 64], padAmp: 0.152,
            guitar: [
                (0.0, 50, 2.6, 0.46), (1.0, 57, 2.5, 0.42), (2.0, 60, 2.6, 0.46), (3.0, 57, 2.6, 0.44),
            ],
            chord: [53, 57, 60],
            melody: [(0.00, 67, 2.15, 0.73), (2.00, 65, 2.20, 0.70)],
            brush: false
        ),
        V6Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)],
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.47),
                (3.0, 64, 2.5, 0.46), (3.5, 67, 2.5, 0.44),
            ],
            chord: [55, 60, 62],
            melody: bar5ClosingHeader,
            brush: false
        ),
    ] : [
        V6Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82), (1.50, 67, 0.50, 0.70), (2.00, 65, 0.85, 0.74),
                (3.00, 69, 0.48, 0.76), (3.50, 72, 0.55, 0.80),
            ],
            brush: true
        ),
        V6Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.1, 0.46),
                (2.25, 64, 2.3, 0.45), (3.125, 60, 2.4, 0.43),
            ],
            chord: [57, 60, 64],
            melody: bar2Melody,
            brush: false
        ),
        V6Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.77), (2.00, 69, 2.20, 0.75)],
            brush: false
        ),
        V6Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)],
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.47),
                (3.0, 64, 2.5, 0.46), (3.5, 67, 2.5, 0.44),
            ],
            chord: [55, 60, 62],
            melody: bar4ClosingSearch,
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1420 + idx * 97))
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.88
            )
        }
        for (mIdx, (beatOff, midi, durB, vel)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: 0.65)
        }
        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V7 (v7a & v7b) — 基于原版 v6A 精准精修
//   - Bars 1, 2, 3 100% 保留原版 v6A 的时值与音高（零改动节奏，绝无跳动感）
//   - ONLY Bar 4 (Header Bar 5) splits the final 2-beat note cleanly on exact natural quarter beats:
//       Beat 1-2 (0.00): G4~~~~ (exact v6A)
//       Beat 3   (2.00): F4     (1 beat — 自然的第一个「噔」)
//       Beat 4   (3.00): G4     (1 beat + pedal tail — 自然的第二个「噔」，无缝流回开头 A4!)
//   - v7a: 原版 v6A 第 2 段尾音力度 (vel 0.72)
//   - v7b: 第 2 段最后的「噔」(Bar 2 beat 2.00 A4) 略微加重更饱满 (vel 0.85, warmth 0.54)
// =========================================================================

func renderV7Exact(dur: Double, accentBar2End: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V7Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double, Double)] // (beatOff, midi, durBeats, vel, warmth)
        let brush: Bool
    }

    let b2EndVel: Double = accentBar2End ? 0.85 : 0.72
    let b2EndWarmth: Double = accentBar2End ? 0.54 : 0.65

    let bars: [V7Bar] = isFiveBar ? [
        // HEADER 15s (5 Bars) — Exact v6A Bars 1–4 + split final 2-beat note in Bar 5
        V7Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V7Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, b2EndVel, b2EndWarmth), // Exact v6A beat 2.00 (optionally accented!)
            ],
            brush: false
        ),
        V7Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [
                (0.00, 65, 2.15, 0.77, 0.65),
                (2.00, 69, 2.20, 0.75, 0.65),
            ],
            brush: false
        ),
        V7Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.52), (2.0, 45, 2.2, 0.42)],
            pad: [50, 57, 60, 64], padAmp: 0.152,
            guitar: [
                (0.0, 50, 2.6, 0.46), (1.0, 57, 2.5, 0.42), (2.0, 60, 2.6, 0.46), (3.0, 57, 2.6, 0.44),
            ],
            chord: [53, 57, 60],
            melody: [
                (0.00, 67, 2.15, 0.73, 0.65),
                (2.00, 65, 2.20, 0.70, 0.65),
            ],
            brush: false
        ),
        V7Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)],
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.48), (3.0, 64, 2.8, 0.48),
            ],
            chord: [55, 60, 62],
            melody: [
                (0.00, 69, 2.05, 0.73, 0.65), // Exact v6A beat 1–2 (A4~~~~)
                (2.00, 65, 1.15, 0.71, 0.65), // Beat 3: F4 (自然 1 拍「噔」)
                (3.00, 67, 1.65, 0.69, 0.65), // Beat 4: G4 (自然 1 拍「噔」+ 踏板延音滑进开头 A4!)
            ],
            brush: false
        ),
    ] : [
        // SEARCH 12s (4 Bars) — Exact v6A Bars 1–3 + Bar 4 final 2-beat note split cleanly to Beat 3 + Beat 4
        V7Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V7Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, b2EndVel, b2EndWarmth), // Exact v6A beat 2.00 (v7b slightly firmer!)
            ],
            brush: false
        ),
        V7Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [
                (0.00, 65, 2.15, 0.77, 0.65),
                (2.00, 69, 2.20, 0.75, 0.65),
            ],
            brush: false
        ),
        V7Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)],
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.48), (3.0, 64, 2.8, 0.48),
            ],
            chord: [55, 60, 62],
            melody: [
                (0.00, 67, 2.05, 0.74, 0.65), // Exact v6A beat 1–2 (G4~~~~)
                (2.00, 65, 1.15, 0.72, 0.65), // Beat 3: F4 (稳稳落在第 3 拍的自然「噔」)
                (3.00, 67, 1.65, 0.69, 0.65), // Beat 4: G4 (稳稳落在第 4 拍的自然「噔」+ 踏板余韵滑入开头 A4!)
            ],
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1300 + idx * 97))
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.88
            )
        }
        for (mIdx, (beatOff, midi, durB, vel, warmth)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: warmth)
        }
        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V8 (v8a / v8b / v8c) — v7A & v7B 提前明亮收尾升级版
//   - Bars 1–3: 100% exact v6A/v7A (v8b & v8c apply gentle Bar 2 final A4 accent)
//   - Bar 4 (Header Bar 5):
//       1. Last two notes pulled 0.5 beat EARLIER -> beat 1.50 & beat 2.50!
//          So 2nd-to-last enters promptly, and final note blooms generously for 1.5 full beats (1.125s + pedal)!
//       2. Harmony upgraded from veiled C9sus4 -> sunlit radiant Cadd9 (Major 3rd E4 glowing in pad & guitar!)
//       3. Final note uses crisp bright felt tone (warmth 0.36) + subtle shimmering guitar high note!
//       - v8a: v7A Bar 2 + bright Cadd9 ending (G4 -> F4 -> bright G4)
//       - v8b: v7B Bar 2 (accented end) + bright Cadd9 ending (G4 -> F4 -> bright G4)
//       - v8c: v7B Bar 2 + sunlit rising C5 ending (G4 -> A4 -> radiant C5 -> loops cleanly into Fmaj9 A4!)
// =========================================================================

func renderV8BrightEnd(dur: Double, accentBar2End: Bool, sunlitC5: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V8Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let guitarBright: Double
        let chord: [Double]
        let melody: [(Double, Double, Double, Double, Double)] // (beatOff, midi, durBeats, vel, warmth)
        let brush: Bool
    }

    let b2EndVel: Double = accentBar2End ? 0.85 : 0.72
    let b2EndWarmth: Double = accentBar2End ? 0.54 : 0.65

    // Last bar melody: enters earlier (1.50 & 2.50!) with 1.5 full beats of bright sunlit sustain!
    let searchLastMelody: [(Double, Double, Double, Double, Double)] = sunlitC5 ? [
        (0.00, 67, 1.55, 0.74, 0.62), // G4 (1.5 beats)
        (1.50, 69, 1.05, 0.73, 0.50), // A4 (enters promptly at beat 2.5!)
        (2.50, 72, 2.10, 0.80, 0.34), // C5 (RADIANT bright sunlit 1.5-beat bloom -> glides cleanly to Bar 1 A4!)
    ] : [
        (0.00, 67, 1.55, 0.74, 0.62), // G4 (1.5 beats)
        (1.50, 65, 1.05, 0.72, 0.52), // F4 (enters promptly at beat 2.5!)
        (2.50, 67, 2.10, 0.78, 0.36), // G4 (BRIGHT clear Cadd9 bloom for 1.5 full beats -> glides into Bar 1 A4!)
    ]

    let headerLastMelody: [(Double, Double, Double, Double, Double)] = sunlitC5 ? [
        (0.00, 67, 1.55, 0.73, 0.62), // G4
        (1.50, 69, 1.05, 0.73, 0.50), // A4
        (2.50, 72, 2.10, 0.79, 0.34), // C5 (bright dawn return!)
    ] : [
        (0.00, 69, 1.55, 0.73, 0.62), // A4
        (1.50, 65, 1.05, 0.71, 0.52), // F4
        (2.50, 67, 2.10, 0.77, 0.36), // G4 (bright sunlit bloom!)
    ]

    // Bright Cadd9 guitar bloom aligned with 1.50 & 2.50!
    let brightLastGuitar: [(Double, Double, Double, Double)] = [
        (0.0, 48, 2.5, 0.45),
        (1.0, 55, 2.4, 0.43),
        (1.5, 60, 2.4, 0.44), // warm C4 supporting beat 1.50
        (2.5, 64, 2.8, 0.50), // radiant Major 3rd E4 opening right on the bright final note!
        (3.25, 72, 2.5, 0.36), // delicate high C5 sunlit bell sparkle floating across loop seam!
    ]

    let bars: [V8Bar] = isFiveBar ? [
        V8Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            guitarBright: 0.44,
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V8Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            guitarBright: 0.44,
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, b2EndVel, b2EndWarmth),
            ],
            brush: false
        ),
        V8Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            guitarBright: 0.44,
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.77, 0.65), (2.00, 69, 2.20, 0.75, 0.65)],
            brush: false
        ),
        V8Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.52), (2.0, 45, 2.2, 0.42)],
            pad: [50, 57, 60, 64], padAmp: 0.152,
            guitar: [
                (0.0, 50, 2.6, 0.46), (1.0, 57, 2.5, 0.42), (2.0, 60, 2.6, 0.46), (3.0, 57, 2.6, 0.44),
            ],
            guitarBright: 0.44,
            chord: [53, 57, 60],
            melody: [(0.00, 67, 2.15, 0.73, 0.65), (2.00, 65, 2.20, 0.70, 0.65)],
            brush: false
        ),
        // Bar 5 (12–15s): Radiant sunlit Cadd9 (Major 3rd E4 + bright bell glow!)
        V8Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.5, 48, 2.2, 0.44)],
            pad: [48, 55, 60, 64], padAmp: 0.155, // Cadd9 with radiant E4!
            guitar: brightLastGuitar,
            guitarBright: 0.58,
            chord: [55, 60, 64], // Major 3rd E4 lifts cloudiness into sunshine!
            melody: headerLastMelody,
            brush: false
        ),
    ] : [
        V8Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            guitarBright: 0.44,
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V8Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            guitarBright: 0.44,
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, b2EndVel, b2EndWarmth),
            ],
            brush: false
        ),
        V8Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            guitarBright: 0.44,
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.77, 0.65), (2.00, 69, 2.20, 0.75, 0.65)],
            brush: false
        ),
        // Bar 4 (9–12s): Radiant sunlit Cadd9 with earlier 1.50 / 2.50 closing!
        V8Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.5, 48, 2.2, 0.44)],
            pad: [48, 55, 60, 64], padAmp: 0.155, // Cadd9 with radiant Major 3rd E4!
            guitar: brightLastGuitar,
            guitarBright: 0.58,
            chord: [55, 60, 64],
            melody: searchLastMelody,
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        for (gIdx, (beatOff, midi, durS, vel)) in b.guitar.enumerated() {
            let jitter = (gIdx % 2 == 0) ? 0.004 : 0.009
            let pan = -0.22 + (gIdx % 2 == 0 ? -0.15 : 0.15)
            track.addNylonPluck(
                startS: b.t0 + beatOff * 0.75 + jitter,
                midi: midi, durS: durS, vel: vel, pan: pan,
                brightness: b.guitarBright, seed: UInt64(1300 + idx * 97 + gIdx * 31)
            )
        }
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: 0.21, pan: -0.28 + Double(j) * 0.16, warmth: idx == bars.count - 1 ? 0.72 : 0.88
            )
        }
        for (mIdx, (beatOff, midi, durB, vel, warmth)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: warmth)
        }
        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V9 (v9a / v9b / v9c) — 回归温润原色（去明亮）+ 倒数第二音略延展
//   - Restores exact warm calm v6A/v7 C9sus4 harmony, warm 0.65 piano tone, warm 0.44 guitar (ZERO bright Cadd9/C5 bell!)
//   - v9a: Exact v7A Bar 2 + Bar 4 (0.00 G4 | 1.25 F4 [1.25b, longer!] | 2.50 G4 [unchanged!])
//   - v9b: Exact v7B Bar 2 (accented end) + Bar 4 (0.00 G4 | 1.25 F4 [1.25b, longer!] | 2.50 G4 [unchanged!])
//   - v9c: Exact v7B Bar 2 + Bar 4 (0.00 G4 [1.50b] | 1.50 F4 [1.25b, longer!] | 2.75 G4 [1.25b + lush tail])
// =========================================================================

func renderV9WarmFinal(dur: Double, accentBar2End: Bool, keep150Start: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V9Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double, Double)]
        let brush: Bool
    }

    let b2EndVel: Double = accentBar2End ? 0.85 : 0.72
    let b2EndWarmth: Double = accentBar2End ? 0.54 : 0.65

    // Exact warm mellow piano tone (0.65) — NO bright harshness!
    let searchLastMelody: [(Double, Double, Double, Double, Double)] = keep150Start ? [
        (0.00, 67, 1.55, 0.74, 0.65), // G4 (0.00 -> 1.50)
        (1.50, 65, 1.40, 0.72, 0.65), // F4 (1.50 -> 2.75: 1.25 beats, gently extended!)
        (2.75, 67, 1.95, 0.70, 0.65), // G4 (2.75 -> 4.00 + full pedal sustain!)
    ] : [
        (0.00, 67, 1.30, 0.74, 0.65), // G4 (0.00 -> 1.25)
        (1.25, 65, 1.45, 0.72, 0.65), // F4 (1.25 -> 2.50: 1.25 beats, slightly longer!)
        (2.50, 67, 2.15, 0.70, 0.65), // G4 (EXACT 2.50 position unchanged + warm pedal tail!)
    ]

    let headerLastMelody: [(Double, Double, Double, Double, Double)] = keep150Start ? [
        (0.00, 69, 1.55, 0.73, 0.65), // A4
        (1.50, 65, 1.40, 0.71, 0.65), // F4 (1.25 beats)
        (2.75, 67, 1.95, 0.69, 0.65), // G4
    ] : [
        (0.00, 69, 1.30, 0.73, 0.65), // A4
        (1.25, 65, 1.45, 0.71, 0.65), // F4 (1.25 beats)
        (2.50, 67, 2.15, 0.69, 0.65), // G4 (EXACT 2.50 position unchanged!)
    ]

    let bars: [V9Bar] = isFiveBar ? [
        V9Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V9Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, b2EndVel, b2EndWarmth),
            ],
            brush: false
        ),
        V9Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.77, 0.65), (2.00, 69, 2.20, 0.75, 0.65)],
            brush: false
        ),
        V9Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.52), (2.0, 45, 2.2, 0.42)],
            pad: [50, 57, 60, 64], padAmp: 0.152,
            guitar: [
                (0.0, 50, 2.6, 0.46), (1.0, 57, 2.5, 0.42), (2.0, 60, 2.6, 0.46), (3.0, 57, 2.6, 0.44),
            ],
            chord: [53, 57, 60],
            melody: [(0.00, 67, 2.15, 0.73, 0.65), (2.00, 65, 2.20, 0.70, 0.65)],
            brush: false
        ),
        // Bar 5: Restored warm calm C9sus4 (exact v6A/v7 warmth, zero brightness boost!)
        V9Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)],
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.48), (3.0, 64, 2.8, 0.48),
            ],
            chord: [55, 60, 62],
            melody: headerLastMelody,
            brush: false
        ),
    ] : [
        V9Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V9Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, b2EndVel, b2EndWarmth),
            ],
            brush: false
        ),
        V9Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.56), (2.0, 46, 2.2, 0.44)],
            pad: [46, 53, 58, 62], padAmp: 0.155,
            guitar: [
                (0.0, 46, 2.6, 0.48), (1.0, 53, 2.5, 0.44), (2.0, 58, 2.6, 0.48), (3.0, 62, 2.6, 0.45),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.77, 0.65), (2.00, 69, 2.20, 0.75, 0.65)],
            brush: false
        ),
        // Bar 4: Restored warm calm C9sus4 (exact v6A/v7 warmth, zero bright Cadd9/C5 bell!)
        V9Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.50), (2.0, 48, 2.4, 0.44)],
            pad: [48, 55, 60, 62], padAmp: 0.155,
            guitar: [
                (0.0, 48, 2.6, 0.46), (1.0, 55, 2.5, 0.44), (2.0, 60, 2.6, 0.48), (3.0, 64, 2.8, 0.48),
            ],
            chord: [55, 60, 62],
            melody: searchLastMelody,
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1300 + idx * 97))
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.88
            )
        }
        for (mIdx, (beatOff, midi, durB, vel, warmth)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: warmth)
        }
        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V10 (v10a / v10b / v10c) — 基于 v9B 最终精修
//   1. Bar 3 opening accent softened cleanly:
//      - bass1 vel: 0.56 -> 0.44; melody F4 vel: 0.77 -> 0.67 (warmth 0.72); guitar beat 0 vel: 0.48 -> 0.40
//   2. Bar 4 (Header Bar 5) removes bright high E4 (64) guitar chime -> warm G3 (55),
//      plus warmer mellow piano tone (warmth 0.78) & softer dynamics on final 2 notes:
//      - v10a (原音高压柔降暗): 0.00 G4 -> 1.25 F4 -> 2.50 G4 (warmer/softer/lower accompaniment, no high lift)
//      - v10b (尾音顺势下行 E4): 0.00 G4 -> 1.25 F4 -> 2.50 E4 (2 -> 1 -> 7 gentle low calm cadence)
//      - v10c (尾音更低落定 D4): 0.00 G4 -> 1.25 F4 -> 2.50 D4 (2 -> 1 -> low 6 warm grounded pentatonic sigh)
// =========================================================================

func renderV10Final(dur: Double, lastNoteMidi: Double, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V10Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double, Double)]
        let brush: Bool
    }

    // Mellow, soft, lowered-timbre final 2 notes (warmth 0.78, gentle vel, zero high lift!)
    let searchLastMelody: [(Double, Double, Double, Double, Double)] = [
        (0.00, 67,           1.30, 0.72, 0.70), // G4
        (1.25, 65,           1.45, 0.65, 0.78), // F4 (softer & warmer)
        (2.50, lastNoteMidi, 2.20, 0.62, 0.80), // Final note: warm, lower, calm exhale!
    ]

    let headerLastMelody: [(Double, Double, Double, Double, Double)] = [
        (0.00, 69,           1.30, 0.71, 0.70), // A4
        (1.25, 65,           1.45, 0.64, 0.78), // F4
        (2.50, lastNoteMidi, 2.20, 0.61, 0.80), // Final note: warm, lower, calm exhale!
    ]

    // Lower, warmer closing guitar voicing (ends softly on G3=55 instead of bright E4=64!)
    let warmLastGuitar: [(Double, Double, Double, Double)] = [
        (0.0, 48, 2.6, 0.43), (1.0, 55, 2.5, 0.40), (2.0, 60, 2.6, 0.41), (3.0, 55, 2.8, 0.39),
    ]

    let bars: [V10Bar] = isFiveBar ? [
        V10Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V10Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, 0.85, 0.54), // Exact v9B accented Bar 2 end!
            ],
            brush: false
        ),
        // Bar 3: Softened opening accent (bass 0.56->0.44, F4 0.77->0.67, guitar 0.48->0.40)
        V10Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.44), (2.0, 46, 2.2, 0.40)],
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.6, 0.40), (1.0, 53, 2.5, 0.42), (2.0, 58, 2.6, 0.46), (3.0, 62, 2.6, 0.44),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.67, 0.73), (2.00, 69, 2.20, 0.74, 0.66)],
            brush: false
        ),
        V10Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.46), (2.0, 45, 2.2, 0.40)],
            pad: [50, 57, 60, 64], padAmp: 0.148,
            guitar: [
                (0.0, 50, 2.6, 0.44), (1.0, 57, 2.5, 0.41), (2.0, 60, 2.6, 0.44), (3.0, 57, 2.6, 0.42),
            ],
            chord: [53, 57, 60],
            melody: [(0.00, 67, 2.15, 0.71, 0.68), (2.00, 65, 2.20, 0.68, 0.70)],
            brush: false
        ),
        V10Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.46), (2.0, 48, 2.4, 0.42)],
            pad: [48, 55, 58, 60], padAmp: 0.150, // lower warmer pad ceiling (removed high 62)
            guitar: warmLastGuitar,
            chord: [53, 55, 60],
            melody: headerLastMelody,
            brush: false
        ),
    ] : [
        V10Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V10Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, 0.85, 0.54), // Exact v9B accented Bar 2 end!
            ],
            brush: false
        ),
        // Page 3: Softened opening accent — lands gently like silk!
        V10Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.44), (2.0, 46, 2.2, 0.40)],
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.6, 0.40), (1.0, 53, 2.5, 0.42), (2.0, 58, 2.6, 0.46), (3.0, 62, 2.6, 0.44),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.67, 0.73), (2.00, 69, 2.20, 0.74, 0.66)],
            brush: false
        ),
        // Page 4: Warm lowered timbre, softer & lower ending!
        V10Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.46), (2.0, 48, 2.4, 0.42)],
            pad: [48, 55, 58, 60], padAmp: 0.150,
            guitar: warmLastGuitar,
            chord: [53, 55, 60],
            melody: searchLastMelody,
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1300 + idx * 97))
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: idx == 2 ? 0.17 : 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.90
            )
        }
        for (mIdx, (beatOff, midi, durB, vel, warmth)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: warmth)
        }
        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V11 (v11a / v11b / v11c) — 精准位于 v10A (G4) 与 v10B (E4) 之间的「中间值」
//   - Bars 1–3: 100% exact v10B (user confirmed best!)
//   - Bar 4 (Header Bar 5) three musical middle-grounds between G4(67) and E4(64):
//       v11a (正中落主音 F4): G4(0.00) -> E4(1.25) -> F4(2.50)  [65 = exact midpoint & Tonic Do!]
//       v11b (双轻触主音 F4): G4(0.00) -> F4(1.25) -> soft F4(2.50) [Sakamoto calm double-breath on Do!]
//       v11c (Fmaj7 托起 E4): G4(0.00) -> F4(1.25) -> E4(2.50) with warm Fmaj7 (A3/C4) pad so E4 floats warmly!
// =========================================================================

func renderV11Midpoint(dur: Double, style: String, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V11Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double, Double)]
        let brush: Bool
    }

    let searchLastMelody: [(Double, Double, Double, Double, Double)]
    let headerLastMelody: [(Double, Double, Double, Double, Double)]
    let lastPad: [Double]
    let lastChord: [Double]
    let lastGuitar: [(Double, Double, Double, Double)]

    switch style {
    case "v11a":
        // Exact midpoint F4 (65): G4 -> E4 -> F4 (2 -> 7 -> 1 home!)
        searchLastMelody = [
            (0.00, 67, 1.30, 0.72, 0.70), // G4
            (1.25, 64, 1.40, 0.65, 0.76), // E4 (soft gentle breath)
            (2.50, 65, 2.25, 0.66, 0.76), // F4 (exact midpoint Tonic Do — calm, centered, home!)
        ]
        headerLastMelody = [
            (0.00, 69, 1.30, 0.71, 0.70), // A4
            (1.25, 64, 1.40, 0.64, 0.76), // E4
            (2.50, 65, 2.25, 0.65, 0.76), // F4
        ]
        lastPad = [48, 55, 57, 60]    // C - G - A - C (warm C6 -> Fmaj9 bridge, zero Bb clash!)
        lastChord = [53, 57, 60]      // warm F - A - C cushion
        lastGuitar = [(0.0, 48, 2.6, 0.43), (1.0, 55, 2.5, 0.40), (2.0, 57, 2.6, 0.41), (3.0, 60, 2.8, 0.39)]
    case "v11b":
        // Calm double-breath on F4 (65): G4 -> F4 -> softer echoing F4 (zero jump up, zero drop down!)
        searchLastMelody = [
            (0.00, 67, 1.30, 0.72, 0.70), // G4
            (1.25, 65, 1.35, 0.68, 0.74), // F4 (first warm landing on Do)
            (2.50, 65, 2.25, 0.59, 0.80), // F4 (tender whisper echo on Do -> melts into Bar 1 A4!)
        ]
        headerLastMelody = [
            (0.00, 69, 1.30, 0.71, 0.70), // A4
            (1.25, 65, 1.35, 0.67, 0.74), // F4
            (2.50, 65, 2.25, 0.58, 0.80), // F4
        ]
        lastPad = [48, 53, 57, 60]    // F/C warm open inversion
        lastChord = [53, 57, 60]
        lastGuitar = [(0.0, 48, 2.6, 0.43), (1.0, 55, 2.5, 0.40), (2.0, 60, 2.6, 0.41), (3.0, 57, 2.8, 0.39)]
    default: // "v11c"
        // Exact v10B melody (G4 -> F4 -> E4) cradled by warm Fmaj7 (A3/C4) so E4 floats warmly instead of drooping!
        searchLastMelody = [
            (0.00, 67, 1.30, 0.72, 0.70), // G4
            (1.25, 65, 1.45, 0.66, 0.76), // F4
            (2.50, 64, 2.25, 0.64, 0.74), // E4 floating serenely on Fmaj7!
        ]
        headerLastMelody = [
            (0.00, 69, 1.30, 0.71, 0.70), // A4
            (1.25, 65, 1.45, 0.65, 0.76), // F4
            (2.50, 64, 2.25, 0.63, 0.74), // E4
        ]
        lastPad = [48, 53, 57, 60]    // Fmaj7/C (no Bb clash against E4 -> luminous floating calm!)
        lastChord = [53, 57, 60]
        lastGuitar = [(0.0, 48, 2.6, 0.43), (1.0, 53, 2.5, 0.40), (2.0, 57, 2.6, 0.41), (3.0, 60, 2.8, 0.39)]
    }

    let bars: [V11Bar] = isFiveBar ? [
        V11Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V11Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, 0.85, 0.54),
            ],
            brush: false
        ),
        V11Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.44), (2.0, 46, 2.2, 0.40)],
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.6, 0.40), (1.0, 53, 2.5, 0.42), (2.0, 58, 2.6, 0.46), (3.0, 62, 2.6, 0.44),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.67, 0.73), (2.00, 69, 2.20, 0.74, 0.66)],
            brush: false
        ),
        V11Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.46), (2.0, 45, 2.2, 0.40)],
            pad: [50, 57, 60, 64], padAmp: 0.148,
            guitar: [
                (0.0, 50, 2.6, 0.44), (1.0, 57, 2.5, 0.41), (2.0, 60, 2.6, 0.44), (3.0, 57, 2.6, 0.42),
            ],
            chord: [53, 57, 60],
            melody: [(0.00, 67, 2.15, 0.71, 0.68), (2.00, 65, 2.20, 0.68, 0.70)],
            brush: false
        ),
        V11Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.46), (2.0, 48, 2.4, 0.42)],
            pad: lastPad, padAmp: 0.150,
            guitar: lastGuitar,
            chord: lastChord,
            melody: headerLastMelody,
            brush: false
        ),
    ] : [
        V11Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true
        ),
        V11Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, 0.85, 0.54),
            ],
            brush: false
        ),
        V11Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.44), (2.0, 46, 2.2, 0.40)],
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.6, 0.40), (1.0, 53, 2.5, 0.42), (2.0, 58, 2.6, 0.46), (3.0, 62, 2.6, 0.44),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.67, 0.73), (2.00, 69, 2.20, 0.74, 0.66)],
            brush: false
        ),
        V11Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.46), (2.0, 48, 2.4, 0.42)],
            pad: lastPad, padAmp: 0.150,
            guitar: lastGuitar,
            chord: lastChord,
            melody: searchLastMelody,
            brush: false
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1300 + idx * 97))
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: idx == 2 ? 0.17 : 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.90
            )
        }
        for (mIdx, (beatOff, midi, durB, vel, warmth)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: warmth)
        }
        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.42)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// =========================================================================
// CANDIDATE V12 (v12a / v12b) — 平静追忆终版（基于 v11A / v11B + 末尾闷重回声落音）
//   - Bars 1–3: 100% locked v10B/v11
//   - Bar 4 (Header Bar 5) Final Note (beat 2.50, F4):
//       1. Same exact felt-piano timbre (NO instrument switch!) with deeper wool warmth (0.86)
//          & firmer weight (vel 0.82) + subtle deep octave shadow F3 (53, vel 0.42, warmth 0.94)
//          -> genuine muffled weighted felt-piano gravity ("闷重")!
//       2. Delicate stereo room echo of the exact same F4 (+0.375s & +0.75s, soft fading reflections)
//          -> tender nostalgic lingering echo ("回声一点")!
//       3. Bittersweet-yet-peaceful Dm9/Fmaj7 warm harmonic color underneath ("一丝哀伤但不难过的追忆感").
//       - v12a: based on v11A (G4 -> E4 -> 闷重回声 F4)
//       - v12b: based on v11B (G4 -> F4 -> 闷重回声 F4)
// =========================================================================

func renderV12Nostalgia(dur: Double, useV11B: Bool, to path: String) {
    let track = StereoTrack(durationSeconds: dur)
    let isFiveBar = dur > 13.0

    struct V12Bar {
        let t0: Double
        let bassNotes: [(Double, Double, Double, Double)]
        let pad: [Double]
        let padAmp: Double
        let guitar: [(Double, Double, Double, Double)]
        let chord: [Double]
        let melody: [(Double, Double, Double, Double, Double)]
        let brush: Bool
        let nostalgiaTail: Bool
    }

    let midNote: Double = useV11B ? 65 : 64 // v12b: F4 (v11B), v12a: E4 (v11A)

    let searchLastMelody: [(Double, Double, Double, Double, Double)] = [
        (0.00, 67,      1.30, 0.72, 0.70), // G4
        (1.25, midNote, 1.35, 0.65, 0.76), // E4 (v12a) or F4 (v12b)
        (2.50, 65,      2.55, 0.82, 0.86), // F4: weighted, deeper wool-muffled felt accent ("闷重" — same piano!)
    ]

    let headerLastMelody: [(Double, Double, Double, Double, Double)] = [
        (0.00, 69,      1.30, 0.71, 0.70), // A4
        (1.25, midNote, 1.35, 0.64, 0.76), // E4 or F4
        (2.50, 65,      2.55, 0.81, 0.86), // F4: weighted muffled felt accent
    ]

    // Subtle bittersweet-yet-warm nostalgic harmony (Fmaj7/Dm9 glow: C3 - F3 - A3 - C4)
    let lastPad: [Double] = [48, 53, 57, 60]
    let lastChord: [Double] = [50, 53, 57] // gentle D3-F3-A3 touch of warm nostalgia!
    let lastGuitar: [(Double, Double, Double, Double)] = [
        (0.0, 48, 2.6, 0.42), (1.0, 55, 2.5, 0.39), (2.0, 57, 2.6, 0.40), (3.0, 60, 2.8, 0.36),
    ]

    let bars: [V12Bar] = isFiveBar ? [
        V12Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true, nostalgiaTail: false
        ),
        V12Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [52, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, 0.85, 0.54),
            ],
            brush: false, nostalgiaTail: false
        ),
        V12Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.44), (2.0, 46, 2.2, 0.40)],
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.6, 0.40), (1.0, 53, 2.5, 0.42), (2.0, 58, 2.6, 0.46), (3.0, 62, 2.6, 0.44),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.67, 0.73), (2.00, 69, 2.20, 0.74, 0.66)],
            brush: false, nostalgiaTail: false
        ),
        V12Bar(
            t0: 9.0,
            bassNotes: [(0.0, 45, 2.2, 0.46), (2.0, 45, 2.2, 0.40)],
            pad: [50, 57, 60, 64], padAmp: 0.148,
            guitar: [
                (0.0, 50, 2.6, 0.44), (1.0, 57, 2.5, 0.41), (2.0, 60, 2.6, 0.44), (3.0, 57, 2.6, 0.42),
            ],
            chord: [53, 57, 60],
            melody: [(0.00, 67, 2.15, 0.71, 0.68), (2.00, 65, 2.20, 0.68, 0.70)],
            brush: false, nostalgiaTail: false
        ),
        V12Bar(
            t0: 12.0,
            bassNotes: [(0.0, 48, 2.2, 0.45), (2.5, 45, 2.4, 0.46)], // subtle A2/D-warm shadow supporting final muffled F4!
            pad: lastPad, padAmp: 0.152,
            guitar: lastGuitar,
            chord: lastChord,
            melody: headerLastMelody,
            brush: false, nostalgiaTail: true
        ),
    ] : [
        V12Bar(
            t0: 0.0,
            bassNotes: [(0.0, 53, 1.55, 0.44), (2.0, 52, 1.50, 0.40)],
            pad: [53, 60, 64, 69], padAmp: 0.125,
            guitar: [
                (0.0, 53, 1.5, 0.56), (0.5, 60, 1.5, 0.46), (1.0, 64, 1.5, 0.52), (1.5, 67, 1.5, 0.44),
                (2.0, 69, 1.5, 0.54), (2.5, 67, 1.5, 0.44), (3.0, 64, 1.6, 0.50), (3.5, 60, 1.6, 0.42),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 69, 1.25, 0.82, 0.65), (1.50, 67, 0.50, 0.70, 0.65), (2.00, 65, 0.85, 0.74, 0.65),
                (3.00, 69, 0.48, 0.76, 0.65), (3.50, 72, 0.55, 0.80, 0.65),
            ],
            brush: true, nostalgiaTail: false
        ),
        V12Bar(
            t0: 3.0,
            bassNotes: [(0.0, 50, 1.65, 0.46), (2.0, 48, 1.80, 0.44)],
            pad: [50, 57, 60, 64], padAmp: 0.138,
            guitar: [
                (0.0, 50, 1.8, 0.50), (0.5, 57, 1.8, 0.42), (1.0, 60, 2.0, 0.46),
                (2.0, 64, 2.3, 0.46), (3.0, 60, 2.4, 0.44),
            ],
            chord: [57, 60, 64],
            melody: [
                (0.00, 74, 0.95, 0.78, 0.65),
                (1.00, 72, 0.95, 0.67, 0.65),
                (2.00, 69, 2.30, 0.85, 0.54),
            ],
            brush: false, nostalgiaTail: false
        ),
        V12Bar(
            t0: 6.0,
            bassNotes: [(0.0, 46, 2.2, 0.44), (2.0, 46, 2.2, 0.40)],
            pad: [46, 53, 58, 62], padAmp: 0.148,
            guitar: [
                (0.0, 46, 2.6, 0.40), (1.0, 53, 2.5, 0.42), (2.0, 58, 2.6, 0.46), (3.0, 62, 2.6, 0.44),
            ],
            chord: [53, 58, 62],
            melody: [(0.00, 65, 2.15, 0.67, 0.73), (2.00, 69, 2.20, 0.74, 0.66)],
            brush: false, nostalgiaTail: false
        ),
        V12Bar(
            t0: 9.0,
            bassNotes: [(0.0, 48, 2.2, 0.45), (2.5, 45, 2.4, 0.46)], // subtle warm A2 low resonance on final beat 2.5!
            pad: lastPad, padAmp: 0.152,
            guitar: lastGuitar,
            chord: lastChord,
            melody: searchLastMelody,
            brush: false, nostalgiaTail: true
        ),
    ]

    for (idx, b) in bars.enumerated() {
        for (beatOff, midi, durS, vel) in b.bassNotes {
            track.addVelvetBass(startS: b.t0 + beatOff * 0.75 + 0.016, midi: midi, durS: durS, vel: vel)
        }
        for (j, note) in b.pad.enumerated() {
            let p = -0.45 + 0.90 * (Double(j) / Double(max(1, b.pad.count - 1)))
            track.addSilkPad(startS: b.t0 - 0.55, midi: note, durS: 3.45, amp: b.padAmp, pan: p)
        }
        addCustomGuitarSteps(track, t0: b.t0, steps: b.guitar, panBase: -0.22, seed: UInt64(1300 + idx * 97))
        for (j, note) in b.chord.enumerated() {
            track.addFeltPiano(
                startS: b.t0 + 0.024 + Double(j) * 0.038,
                midi: note, durS: 2.85, vel: idx == 2 ? 0.17 : 0.21, pan: -0.28 + Double(j) * 0.16, warmth: 0.90
            )
        }
        for (mIdx, (beatOff, midi, durB, vel, warmth)) in b.melody.enumerated() {
            let mt = b.t0 + beatOff * 0.75
            let p = 0.14 + sin(Double(idx * 4 + mIdx)) * 0.09
            track.addFeltPiano(startS: mt, midi: midi, durS: durB * 0.75 + 0.65, vel: vel, pan: p, warmth: warmth)
        }

        // Signature "闷重 + 回声" felt-piano nostalgic accent right on final beat 2.50!
        if b.nostalgiaTail {
            let hitT = b.t0 + 2.50 * 0.75
            // 1. Deep wool-muffled octave shadow (F3 = 53, exact same piano voice!) for warm grounded weight
            track.addFeltPiano(startS: hitT - 0.012, midi: 53, durS: 2.60, vel: 0.44, pan: -0.10, warmth: 0.95)
            // 2. Natural stereo room echo reflections of F4 (exact same piano voice echoing gently across seam!)
            track.addFeltPiano(startS: hitT + 0.375, midi: 65, durS: 1.90, vel: 0.29, pan: -0.26, warmth: 0.92)
            track.addFeltPiano(startS: hitT + 0.750, midi: 65, durS: 1.50, vel: 0.16, pan:  0.22, warmth: 0.95)
            track.addFeltPiano(startS: hitT + 0.385, midi: 53, durS: 1.80, vel: 0.15, pan:  0.14, warmth: 0.96)
        }

        if b.brush {
            track.addSoftBrush(startS: b.t0 + 0.75, amp: 0.018, pan: -0.18, seed: UInt64(75 + idx))
            track.addSoftBrush(startS: b.t0 + 2.25, amp: 0.020, pan: 0.18, seed: UInt64(99 + idx))
        }
    }

    track.applyStudioReverb(wet: 0.44)
    track.writeSeamlessWAV(to: path, targetPeak: 0.72)
}

// MARK: - CLI Entry Point

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "all"
let outDir = args.count > 2 ? args[2] : "/tmp/moro-monochrome-split-work/audio"

switch mode {
case "v12a":
    renderV12Nostalgia(dur: 15.0, useV11B: false, to: "\(outDir)/header-bgm-15s.wav")
    renderV12Nostalgia(dur: 12.0, useV11B: false, to: "\(outDir)/search-bgm-12s.wav")
case "v12b":
    renderV12Nostalgia(dur: 15.0, useV11B: true, to: "\(outDir)/header-bgm-15s.wav")
    renderV12Nostalgia(dur: 12.0, useV11B: true, to: "\(outDir)/search-bgm-12s.wav")
case "v12-audition":
    renderV12Nostalgia(dur: 15.0, useV11B: false, to: "\(outDir)/v12a-nostalgia-15s.wav")
    renderV12Nostalgia(dur: 12.0, useV11B: false, to: "\(outDir)/v12a-nostalgia-12s.wav")
    renderV12Nostalgia(dur: 15.0, useV11B: true, to: "\(outDir)/v12b-nostalgia-echo-15s.wav")
    renderV12Nostalgia(dur: 12.0, useV11B: true, to: "\(outDir)/v12b-nostalgia-echo-12s.wav")
    print("Synthesized v12 nostalgic muffled-echo final BGM (v12a & v12b × 15s & 12s) -> \(outDir)")
default:
    renderV12Nostalgia(dur: 15.0, useV11B: false, to: "\(outDir)/v12a-nostalgia-15s.wav")
    renderV12Nostalgia(dur: 12.0, useV11B: false, to: "\(outDir)/v12a-nostalgia-12s.wav")
    print("Synthesized default v12a BGM -> \(outDir)")
}
