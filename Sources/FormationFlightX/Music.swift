import Foundation

/// The menu music: an uplifting, unhurried piece in D major, synthesized like every other sound in FlightCore.
/// A warm pad carries the chords, a plucked arpeggio with a ping-pong echo runs over it, bass and soft drums come
/// in after the opening bars, and a simple melody sings over the second half of each sixteen-bar round.
final class MusicSynth {
    private let sr: Float = 44100
    private let stepLen: Int                 // samples in a sixteenth note
    private var n = 0, step = 0
    private var seed: UInt32 = 0x2468ace1

    // harmony: one chord per bar, sixteen bars. Pad voicing, bass root (MIDI notes).
    private static let D: ([Float], Float) = ([50, 57, 62, 66], 38), A: ([Float], Float) = ([52, 57, 61, 64], 33)
    private static let Bm: ([Float], Float) = ([54, 59, 62, 66], 35), G: ([Float], Float) = ([55, 59, 62, 67], 31)
    private static let bars = [D, D, A, A, Bm, Bm, G, G, G, A, Bm, Bm, G, A, D, A]
    private static let arpPattern = [0, 1, 2, 3, 4, 3, 2, 1, 0, 2, 1, 3, 2, 4, 3, 1]
    /// The melody over bars 8 to 15: (bar, sixteenth, note, length in sixteenths)
    private static let melody: [(Int, Int, Float, Int)] = [
        (8, 0, 71, 6), (8, 6, 69, 2), (8, 8, 67, 8), (9, 0, 69, 6), (9, 6, 71, 2), (9, 8, 73, 8),
        (10, 0, 74, 6), (10, 6, 73, 2), (10, 8, 71, 4), (10, 12, 69, 4), (11, 0, 66, 12), (11, 12, 69, 4),
        (12, 0, 71, 6), (12, 6, 74, 2), (12, 8, 76, 8), (13, 0, 76, 4), (13, 4, 74, 4), (13, 8, 73, 4), (13, 12, 69, 4),
        (14, 0, 74, 14), (15, 0, 73, 8), (15, 8, 76, 7)]

    // pad
    private var padF = [Float](repeating: 0, count: 4), padA = [Float](repeating: 0, count: 4), padB = [Float](repeating: 0.5, count: 4)
    private var padEnv: Float = 0, padTarget: Float = 1, padL1: Float = 0, padL2: Float = 0, padR1: Float = 0, padR2: Float = 0, lfo: Float = 0
    // bass
    private var bassF: Float = 0, bassP: Float = 0, bassEnv: Float = 0, bassLP: Float = 0
    // arpeggio and its echo
    private var arpF: Float = 0, arpP: Float = 0, arpEnv: Float = 0, arpLP: Float = 0, arpPan: Float = 0.4
    private let delayLen: Int
    private let dl: UnsafeMutablePointer<Float>, dr: UnsafeMutablePointer<Float>
    private var dpos = 0
    // melody
    private var leadF: Float = 0, leadP: Float = 0, leadEnv: Float = 0, leadLeft = 0, vib: Float = 0
    // drums
    private var kickT: Float = 9, kickP: Float = 0, snareT: Float = 9, snLP: Float = 0, snLP2: Float = 0, hatT: Float = 9, hatAmp: Float = 0, hatLP: Float = 0
    // reverb: four combs and two all-passes per side
    private static let combLen = [1557, 1617, 1491, 1422], apLenL = [225, 556], apLenR = [248, 579]
    private var comb: [UnsafeMutablePointer<Float>] = [], combPos = [0, 0, 0, 0], combLP = [Float](repeating: 0, count: 4)
    private var apL: [UnsafeMutablePointer<Float>] = [], apR: [UnsafeMutablePointer<Float>] = [], apPosL = [0, 0], apPosR = [0, 0]

    init() {
        stepLen = Int(sr * 60 / 104 / 4)
        delayLen = stepLen * 3
        func buf(_ c: Int) -> UnsafeMutablePointer<Float> { let p = UnsafeMutablePointer<Float>.allocate(capacity: c); p.initialize(repeating: 0, count: c); return p }
        dl = buf(delayLen); dr = buf(delayLen)
        comb = MusicSynth.combLen.map(buf); apL = MusicSynth.apLenL.map(buf); apR = MusicSynth.apLenR.map(buf)
    }

    @inline(__always) private func hz(_ midi: Float) -> Float { 440 * powf(2, (midi - 69) / 12) }
    @inline(__always) private func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: seed)) * (1.0 / 2147483648.0) }
    /// A sawtooth without the harsh aliasing of a naive one.
    @inline(__always) private func saw(_ p: Float, _ dt: Float) -> Float {
        var v = 2 * p - 1
        if p < dt { let t = p / dt; v -= t + t - t * t - 1 } else if p > 1 - dt { let t = (p - 1) / dt; v -= t * t + t + t + 1 }
        return v
    }

    private func onStep() {
        let s16 = step % 16, bar = (step / 16) % 16, total = step / 16
        let chord = MusicSynth.bars[bar]
        for i in 0..<4 { padF[i] = hz(chord.0[i]) }
        // the pad breathes out just before the harmony moves on
        let next = MusicSynth.bars[((step + 1) / 16) % 16]
        padTarget = next.1 != chord.1 ? 0.3 : 1
        // bass: steady eighths on the root, with a lift at the end of the bar
        if total >= 4 && s16 % 2 == 0 { bassF = hz(chord.1 + (s16 == 14 ? 12 : (s16 == 10 ? 7 : 0))); bassEnv = 1 }
        // arpeggio: the chord's notes, up and back over two octaves
        let tones = chord.0.map { $0 + 12 } + [chord.0[0] + 24]
        arpF = hz(tones[MusicSynth.arpPattern[s16]]); arpEnv = total < 2 ? 0.6 : 1; arpPan = -arpPan
        if total >= 4 {
            if s16 % 4 == 0 { kickT = 0; kickP = 0 }
            if s16 == 4 || s16 == 12 { snareT = 0 }
            hatT = 0; hatAmp = s16 % 4 == 2 ? 1 : 0.35
        }
        if total >= 8 || bar >= 8 {
            for m in MusicSynth.melody where m.0 == bar && m.1 == s16 { leadF = hz(m.2); leadLeft = m.3 * stepLen - stepLen / 3 }
        }
    }

    /// The next stereo sample.
    func next() -> (Float, Float) {
        if n == 0 { onStep() }
        n += 1; if n >= stepLen { n = 0; step += 1 }
        let dt = 1 / sr, twoPi = 2 * Float.pi

        // ---- pad: detuned saws, one of each pair to either side, through a slowly opening filter
        padEnv += (padTarget - padEnv) * (padTarget > padEnv ? 0.00009 : 0.0006)
        lfo += dt * 0.07; if lfo > 1 { lfo -= 1 }
        var pl: Float = 0, pr: Float = 0
        for i in 0..<4 {
            let fa = padF[i] * 1.0035 * dt, fb = padF[i] * 0.9965 * dt
            padA[i] += fa; if padA[i] >= 1 { padA[i] -= 1 }
            padB[i] += fb; if padB[i] >= 1 { padB[i] -= 1 }
            pl += saw(padA[i], fa); pr += saw(padB[i], fb)
        }
        let cut = 1 - expf(-twoPi * (850 + 450 * sinf(twoPi * lfo)) * dt)
        padL1 += (pl - padL1) * cut; padL2 += (padL1 - padL2) * cut
        padR1 += (pr - padR1) * cut; padR2 += (padR1 - padR2) * cut
        let padL = padL2 * 0.075 * padEnv, padR = padR2 * 0.075 * padEnv

        // ---- drums
        kickT += dt; snareT += dt; hatT += dt
        var kick: Float = 0
        let kickEnv = kickT < 0.6 ? expf(-kickT * 8.5) : 0
        if kickEnv > 0.001 { kickP += (46 + 115 * expf(-kickT * 42)) * dt; kick = sinf(twoPi * kickP) * kickEnv * 0.5 }
        let w = noise()
        snLP += (w - snLP) * 0.5; snLP2 += (snLP - snLP2) * 0.09
        let snare = snareT < 0.4 ? (snLP - snLP2) * expf(-snareT * 17) * 0.2 : 0
        hatLP += (w - hatLP) * 0.55
        let hat = hatT < 0.12 ? (w - hatLP) * expf(-hatT * 85) * 0.055 * hatAmp : 0
        let duck = 1 - 0.3 * kickEnv                    // the pad and bass make room for the kick

        // ---- bass
        bassEnv *= 0.99989
        let bf = bassF * dt
        bassP += bf; if bassP >= 1 { bassP -= 1 }
        bassLP += (saw(bassP, bf) - bassLP) * 0.06
        let bass = (sinf(twoPi * bassP) * 0.8 + bassLP * 0.5) * bassEnv * 0.3

        // ---- arpeggio: a pluck whose brightness dies away with its loudness
        arpEnv *= 0.99985
        let af = arpF * dt
        arpP += af; if arpP >= 1 { arpP -= 1 }
        arpLP += (saw(arpP, af) - arpLP) * (0.05 + 0.4 * arpEnv)
        let arp = arpLP * arpEnv * 0.11
        // ping-pong echo, three sixteenths long
        let eL = dl[dpos], eR = dr[dpos]
        dl[dpos] = arp + eR * 0.45; dr[dpos] = eL * 0.45
        dpos += 1; if dpos >= delayLen { dpos = 0 }

        // ---- melody: a soft, slightly breathy voice with vibrato
        var lead: Float = 0
        if leadLeft > 0 { leadLeft -= 1; leadEnv += (1 - leadEnv) * 0.0012 } else { leadEnv *= 0.9996 }
        if leadEnv > 0.001 {
            vib += dt * 5.2; if vib > 1 { vib -= 1 }
            leadP += leadF * (1 + 0.004 * sinf(twoPi * vib) * leadEnv) * dt; if leadP >= 1 { leadP -= 1 }
            lead = (sinf(twoPi * leadP) + 0.28 * sinf(2 * twoPi * leadP) + 0.1 * sinf(3 * twoPi * leadP)) * leadEnv * 0.13
        }

        // ---- reverb
        let send = (padL + padR) * 0.25 + arp * 0.5 + lead * 0.7 + snare * 0.5 + (eL + eR) * 0.2
        var rv: Float = 0
        for i in 0..<4 {
            let b = comb[i], p = combPos[i], y = b[p]
            combLP[i] += (y - combLP[i]) * 0.35
            b[p] = send + combLP[i] * 0.83
            combPos[i] = p + 1 == MusicSynth.combLen[i] ? 0 : p + 1
            rv += y
        }
        var rl = rv * 0.25, rr = rv * 0.25
        for i in 0..<2 {
            let b = apL[i], p = apPosL[i], y = b[p]; b[p] = rl + y * 0.5; rl = y - rl * 0.5
            apPosL[i] = p + 1 == MusicSynth.apLenL[i] ? 0 : p + 1
            let c = apR[i], q = apPosR[i], z = c[q]; c[q] = rr + z * 0.5; rr = z - rr * 0.5
            apPosR[i] = q + 1 == MusicSynth.apLenR[i] ? 0 : q + 1
        }

        let centre = bass * duck + kick + snare + lead
        let L = padL * duck + centre + arp * (1 - arpPan) + hat * 0.8 + eL * 0.5 + rl * 0.32
        let R = padR * duck + centre + arp * (1 + arpPan) + hat * 1.2 + eR * 0.5 + rr * 0.32
        return (L * 0.55, R * 0.55)
    }
}
