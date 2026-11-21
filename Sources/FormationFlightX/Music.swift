import Foundation

/// The menu music of FormationFlightX: a calm evening piece in A minor, in a rolling twelve-eight at 76 beats a
/// minute, synthesized like every other sound in the app. An electric piano plays the chords, a round bass and
/// brushed percussion join after the opening bars, and a glassy bell picks out a melody with an echo over the
/// second half of each sixteen-bar round.
final class MusicSynth {
    private let sr: Float = 44100
    private let stepLen: Int                 // samples in one triplet eighth: twelve to the bar
    private var n = 0, step = 0
    private var seed: UInt32 = 0x1357bdf9

    // harmony: one chord per bar, sixteen bars. Piano voicing and bass note (MIDI).
    private static let F: ([Float], Float) = ([53, 57, 60, 64], 41), G: ([Float], Float) = ([55, 59, 62, 64], 43)
    private static let Em: ([Float], Float) = ([52, 55, 59, 62], 40), Am: ([Float], Float) = ([57, 60, 64, 67], 45)
    private static let Dm: ([Float], Float) = ([53, 57, 60, 65], 38), C: ([Float], Float) = ([55, 59, 60, 64], 36)
    private static let bars = [F, G, Em, Am, F, G, Am, Am, Dm, G, C, Am, F, G, Am, G]
    /// The bell: (bar, step, note). A short answer in bars 4 to 7, the tune itself in bars 8 to 15.
    private static let melody: [(Int, Int, Float)] = [
        (4, 6, 76), (4, 9, 72), (5, 6, 74), (5, 9, 71), (6, 6, 72), (6, 9, 76), (7, 0, 81),
        (8, 0, 81), (8, 3, 77), (8, 6, 74), (8, 9, 76), (9, 0, 79), (9, 4, 74), (9, 6, 71), (9, 9, 74),
        (10, 0, 76), (10, 3, 79), (10, 6, 84), (10, 10, 83), (11, 0, 81), (11, 6, 76), (11, 9, 72),
        (12, 0, 72), (12, 3, 76), (12, 6, 81), (12, 9, 79), (13, 0, 79), (13, 3, 74), (13, 6, 79), (13, 9, 83),
        (14, 0, 84), (14, 4, 81), (14, 6, 76), (14, 9, 72), (15, 0, 74), (15, 6, 71), (15, 9, 74)]

    // electric piano: four notes, each a sine bent by another sine that dies away faster than the note
    private var epF = [Float](repeating: 0, count: 4), epP = [Float](repeating: 0, count: 4), epM = [Float](repeating: 0, count: 4)
    private var epEnv = [Float](repeating: 0, count: 4), epIdx = [Float](repeating: 0, count: 4)
    private var trem: Float = 0
    // a quiet held chord underneath, so the piano's notes never die into silence
    private var bedF = [Float](repeating: 0, count: 4), bedP = [Float](repeating: 0, count: 4), bedEnv: Float = 0
    // bass
    private var bassF: Float = 0, bassP: Float = 0, bassEnv: Float = 0, bassGlide: Float = 0
    // bell: two voices, so a note can ring on under the next, and an echo
    private var bellF = [Float](repeating: 0, count: 2), bellP = [Float](repeating: 0, count: 2), bellM = [Float](repeating: 0, count: 2)
    private var bellEnv = [Float](repeating: 0, count: 2), bellNext = 0
    private let delayLen: Int
    private let dl: UnsafeMutablePointer<Float>, dr: UnsafeMutablePointer<Float>
    private var dpos = 0
    // percussion
    private var kickT: Float = 9, kickP: Float = 0, rimT: Float = 9, rimP: Float = 0, shakeT: Float = 9, shakeAmp: Float = 0, shakeLP: Float = 0, shakePan: Float = 0.3
    // reverb: four combs and two all-passes per side
    private static let combLen = [1687, 1601, 2053, 2251], apLenL = [347, 113], apLenR = [370, 127]
    private var comb: [UnsafeMutablePointer<Float>] = [], combPos = [0, 0, 0, 0], combLP = [Float](repeating: 0, count: 4)
    private var apL: [UnsafeMutablePointer<Float>] = [], apR: [UnsafeMutablePointer<Float>] = [], apPosL = [0, 0], apPosR = [0, 0]

    init() {
        stepLen = Int(sr * 60 / 76 / 3)
        delayLen = stepLen * 4
        func buf(_ c: Int) -> UnsafeMutablePointer<Float> { let p = UnsafeMutablePointer<Float>.allocate(capacity: c); p.initialize(repeating: 0, count: c); return p }
        dl = buf(delayLen); dr = buf(delayLen)
        comb = MusicSynth.combLen.map(buf); apL = MusicSynth.apLenL.map(buf); apR = MusicSynth.apLenR.map(buf)
    }

    @inline(__always) private func hz(_ midi: Float) -> Float { 440 * powf(2, (midi - 69) / 12) }
    @inline(__always) private func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: seed)) * (1.0 / 2147483648.0) }

    private func strike(_ chord: [Float], _ level: Float) {
        for i in 0..<4 { epF[i] = hz(chord[i]); epEnv[i] = level * (i == 3 ? 1 : 0.85); epIdx[i] = 1.6 * level }
    }

    private func onStep() {
        let s12 = step % 12, bar = (step / 12) % 16, total = step / 12
        let chord = MusicSynth.bars[bar]
        // piano: the chord on the first beat, a lighter touch off the third, and the top two notes rocking in between
        if s12 == 0 { strike(chord.0, 1); for i in 0..<4 { bedF[i] = hz(chord.0[i] + (i < 2 ? 0 : 12)) } }
        if s12 == 7 { strike(chord.0, 0.55) }
        if s12 == 4 || s12 == 10 { epEnv[3] = max(epEnv[3], 0.5); epIdx[3] = 0.9; epEnv[2] = max(epEnv[2], 0.35) }
        // bass: the root, its fifth half-way, and a step up into the next bar
        if total >= 4 {
            if s12 == 0 { bassF = hz(chord.1); bassEnv = 1 }
            if s12 == 6 { bassF = hz(chord.1 + 7); bassEnv = 0.7 }
            if s12 == 10 { bassF = hz(chord.1 + 12); bassEnv = 0.55 }
        }
        // percussion: a shaker on every step, leaning on the beats; later a soft kick and a rim click
        if total >= 4 { shakeT = 0; shakeAmp = s12 % 3 == 0 ? 1 : (s12 % 3 == 2 ? 0.55 : 0.3); shakePan = -shakePan }
        if total >= 8 {
            if s12 == 0 || s12 == 7 { kickT = 0; kickP = 0 }
            if s12 == 3 || s12 == 9 { rimT = 0; rimP = 0 }
        }
        if total >= 8 || bar >= 8 {
            for m in MusicSynth.melody where m.0 == bar && m.1 == s12 {
                bellNext = 1 - bellNext
                bellF[bellNext] = hz(m.2); bellEnv[bellNext] = 1
            }
        }
    }

    /// The next stereo sample.
    func next() -> (Float, Float) {
        if n == 0 { onStep() }
        n += 1; if n >= stepLen { n = 0; step += 1 }
        let dt = 1 / sr, twoPi = 2 * Float.pi

        // ---- electric piano, swaying gently from side to side
        trem += dt * 0.9; if trem > 1 { trem -= 1 }
        let sway = 0.35 * sinf(twoPi * trem)
        var ep: Float = 0
        for i in 0..<4 where epEnv[i] > 0.0005 {
            epEnv[i] *= 0.999972; epIdx[i] *= 0.99988
            epP[i] += epF[i] * dt; if epP[i] >= 1 { epP[i] -= 1 }
            epM[i] += epF[i] * dt; if epM[i] >= 1 { epM[i] -= 1 }
            ep += sinf(twoPi * epP[i] + epIdx[i] * sinf(twoPi * epM[i])) * epEnv[i]
        }
        ep *= 0.085
        // ---- the bed: plain soft tones, rising slowly once the piece is under way
        bedEnv += (1 - bedEnv) * 0.000004
        var bed: Float = 0
        for i in 0..<4 { bedP[i] += bedF[i] * dt; if bedP[i] >= 1 { bedP[i] -= 1 }; bed += sinf(twoPi * bedP[i]) }
        bed *= 0.018 * bedEnv

        // ---- percussion
        kickT += dt; rimT += dt; shakeT += dt
        var kick: Float = 0
        let kickEnv = kickT < 0.5 ? expf(-kickT * 11) : 0
        if kickEnv > 0.001 { kickP += (52 + 70 * expf(-kickT * 55)) * dt; kick = sinf(twoPi * kickP) * kickEnv * 0.42 }
        var rim: Float = 0
        if rimT < 0.08 { rimP += 1750 * dt; rim = sinf(twoPi * rimP) * expf(-rimT * 90) * 0.1 }
        let w = noise()
        shakeLP += (w - shakeLP) * 0.35
        let shake = shakeT < 0.09 ? (w - shakeLP) * (1 - expf(-shakeT * 900)) * expf(-shakeT * 55) * 0.05 * shakeAmp : 0

        // ---- bass: round, sliding a little into each note
        bassEnv *= 0.99992
        bassGlide += (bassF - bassGlide) * 0.004
        bassP += bassGlide * dt; if bassP >= 1 { bassP -= 1 }
        let bass = (sinf(twoPi * bassP) + 0.22 * sinf(2 * twoPi * bassP)) * bassEnv * 0.3 * (1 - 0.25 * kickEnv)

        // ---- bell: a glassy tone that rings on, with an echo a beat and a third behind
        var bell: Float = 0
        for i in 0..<2 where bellEnv[i] > 0.0005 {
            bellEnv[i] *= 0.99994
            bellP[i] += bellF[i] * dt; if bellP[i] >= 1 { bellP[i] -= 1 }
            bellM[i] += bellF[i] * 3.5 * dt; if bellM[i] >= 1 { bellM[i] -= 1 }
            let e = bellEnv[i]
            bell += sinf(twoPi * bellP[i] + 1.9 * e * e * sinf(twoPi * bellM[i])) * e
        }
        bell *= 0.1
        let eL = dl[dpos], eR = dr[dpos]
        dl[dpos] = bell + eR * 0.4; dr[dpos] = eL * 0.4
        dpos += 1; if dpos >= delayLen { dpos = 0 }

        // ---- reverb
        let send = ep * 0.55 + bed * 0.8 + bell * 0.8 + rim * 0.6 + shake * 0.3 + (eL + eR) * 0.25
        var rv: Float = 0
        for i in 0..<4 {
            let b = comb[i], p = combPos[i], y = b[p]
            combLP[i] += (y - combLP[i]) * 0.3
            b[p] = send + combLP[i] * 0.86
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

        let centre = bass + kick + rim * 0.8 + bell * 0.75
        let L = ep * (1 - sway) + bed + centre + shake * (1 - shakePan) + eL * 0.55 + rl * 0.4
        let R = ep * (1 + sway) + bed + centre + shake * (1 + shakePan) + eR * 0.55 + rr * 0.4
        return (L * 0.6, R * 0.6)
    }
}
