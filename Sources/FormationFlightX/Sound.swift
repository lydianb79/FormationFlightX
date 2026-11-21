import Foundation
import AVFoundation

/// What the game tells the synthesizer each frame. Plain values, written on the main thread and read by the audio thread.
struct SoundState {
    var engine = 0              // 0 electric, 1 piston, 2 ducted fan / jet, 3 turboprop, 4 helicopter, 5 multirotor
    var shaftHz: Float = 0      // propeller or rotor revolutions per second, Doppler-shifted
    var blades: Float = 2
    var cylinders: Float = 4
    var radial = false
    var power: Float = 0        // 0...1 how hard the motor is working
    var running: Float = 0      // 0 stopped ... 1 running (engines idle, electric motors stop)
    var motors = SIMD4<Float>(0, 0, 0, 0)   // multirotor: per-motor speed 0...1
    var doppler: Float = 1
    var gain: Float = 0         // distance attenuation 0...1
    var muffle: Float = 0       // 0 close ... 1 far: high frequencies are absorbed by the air
    var pan: Float = 0          // -1 left ... 1 right
    var airspeed: Float = 0
    var groundRoll: Float = 0   // rolling speed while on the ground, m/s
    var windSpeed: Float = 0    // ambient wind at the pilot, m/s
    var ambience = Ambience()   // what can be heard at the pilot's position besides the aircraft
    var reflect: Float = 0      // extra travel time of the sound that bounces off the ground on its way to the pilot (s)
    var reflectGain: Float = 0  // strength of that reflection, 0 = none
    var paused = false
}

/// The background sounds of a place, each 0 (absent) ... 1 (plenty).
struct Ambience {
    var birds: Float = 0        // songbirds
    var cuckoo: Float = 0
    var crows: Float = 0
    var gulls: Float = 0
    var frogs: Float = 0
    var crickets: Float = 0     // chirping, strongest in the evening
    var cicadas: Float = 0      // the steady buzz of a hot day
    var bells: Float = 0        // cowbells on a mountain pasture
    var surf: Float = 0         // sea swell breaking
    var lapping: Float = 0      // small waves on a lake shore
    var stream: Float = 0       // running water
    var leaves: Float = 0       // trees in the wind
    var grass: Float = 0        // long dry grass in the wind
    var sand: Float = 0         // blown sand
    var howl: Float = 0         // wind whistling over ridges and rock
    var town: Float = 0         // distant traffic

    /// The ambience of a flying site, from its landscape or, for a photo, from the kind of place it shows.
    static func of(_ site: SiteSpec) -> Ambience {
        var a = Ambience()
        let key = site.panorama?.deletingPathExtension().lastPathComponent.lowercased() ?? site.key
        switch key {
        // 3D sites
        case "meadow": a.birds = 1; a.cuckoo = 0.6; a.leaves = 0.4; a.crickets = 0.3
        case "desert": a.sand = 0.6; a.howl = 0.2; a.crickets = 0.15
        case "alpine": a.bells = 0.8; a.stream = 0.5; a.howl = 0.4; a.birds = 0.3
        case "coast": a.surf = 1; a.gulls = 0.8; a.grass = 0.3
        case "lake": a.lapping = 0.8; a.birds = 0.7; a.frogs = 0.25; a.leaves = 0.3
        case "snow": a.crows = 0.6; a.howl = 0.3
        case "canyon": a.howl = 0.7; a.sand = 0.3; a.crows = 0.3
        case "savanna": a.cicadas = 0.8; a.crickets = 0.5; a.birds = 0.3; a.grass = 0.5
        case "island": a.surf = 0.9; a.gulls = 0.3; a.cicadas = 0.4; a.leaves = 0.4
        case "moor": a.howl = 0.8; a.grass = 0.6; a.crows = 0.3
        case "airport": a.town = 0.7; a.birds = 0.3
        case "tuscany": a.cicadas = 0.9; a.crickets = 0.4; a.birds = 0.4
        case "forest": a.leaves = 1; a.birds = 1; a.cuckoo = 0.8; a.stream = 0.2
        case "fjord": a.stream = 0.8; a.lapping = 0.6; a.gulls = 0.4
        case "lava": a.howl = 0.6; a.sand = 0.2
        case "salt": a.sand = 0.5; a.howl = 0.3
        case "autumn": a.leaves = 0.9; a.crows = 0.6; a.birds = 0.3
        case "marsh": a.frogs = 1; a.crickets = 0.5; a.birds = 0.5; a.lapping = 0.3; a.grass = 0.4
        case "dunes": a.sand = 1; a.howl = 0.4
        case "cliffs": a.surf = 1; a.gulls = 1; a.howl = 0.4; a.grass = 0.4
        // photo sites
        case "alps_field": a.bells = 0.7; a.birds = 0.6; a.crickets = 0.3
        case "belfast_open_field": a.birds = 0.5; a.grass = 0.5; a.crows = 0.3
        case "derelict_airfield_01", "derelict_airfield_02": a.birds = 0.6; a.leaves = 0.5; a.crows = 0.2
        case "dry_cracked_lake": a.cicadas = 0.6; a.crickets = 0.4; a.birds = 0.2
        case "autumn_field": a.grass = 0.7; a.crows = 0.4; a.crickets = 0.3
        case "dry_hay_field": a.crickets = 0.8; a.birds = 0.5; a.grass = 0.4
        case "farm_field": a.birds = 0.6; a.crows = 0.3
        case "hochsal_field": a.birds = 0.8; a.crickets = 0.5; a.bells = 0.3
        case "limpopo_golf_course": a.birds = 0.8; a.frogs = 0.4; a.cicadas = 0.4; a.lapping = 0.3
        case "snow_field": a.howl = 0.4; a.crows = 0.3
        case "suburban_football_field": a.town = 0.7; a.birds = 0.5
        case "wildflower_field": a.birds = 0.9; a.crickets = 0.5; a.cuckoo = 0.4
        case "rural_asphalt_road": a.birds = 0.6; a.leaves = 0.4; a.town = 0.25
        case "goegap_road": a.cicadas = 0.5; a.sand = 0.3; a.birds = 0.2
        case "grasslands_sunset": a.crickets = 0.9; a.grass = 0.5
        case "snowy_hillside_02": a.crows = 0.4; a.howl = 0.3
        case "poolbeg": a.surf = 0.7; a.gulls = 0.7; a.grass = 0.5
        case "horn-koppe_spring": a.birds = 0.9; a.cuckoo = 0.7; a.leaves = 0.4
        case "dreifaltigkeitsberg": a.birds = 0.8; a.leaves = 0.5; a.crickets = 0.3
        case "immenstadter_horn": a.bells = 0.9; a.howl = 0.4; a.birds = 0.4; a.grass = 0.5; a.leaves = 0.3
        case "hausdorf_meadow": a.birds = 0.6; a.crows = 0.4; a.bells = 0.3; a.leaves = 0.3
        case "lago_disola": a.howl = 0.6; a.crows = 0.3; a.leaves = 0.3
        case "camdeboo_road": a.cicadas = 0.5; a.crickets = 0.6; a.birds = 0.3; a.howl = 0.2
        case "golden_gate_hills": a.howl = 0.35; a.grass = 0.6; a.birds = 0.3; a.crickets = 0.3
        case "evening_meadow": a.crickets = 0.8; a.birds = 0.6; a.grass = 0.6
        case "steinbach_field": a.crickets = 0.7; a.birds = 0.5; a.leaves = 0.3
        case "stierberg_sunrise": a.crows = 0.5; a.howl = 0.3
        case "countrytrax_midday": a.cicadas = 0.6; a.birds = 0.5; a.grass = 0.3
        case "spaichingen_hill": a.birds = 0.8; a.crickets = 0.4; a.grass = 0.5; a.town = 0.15
        default:
            // a photo the pilot added, or a site without a soundscape of its own: go by what kind of place it is
            switch site.category {
            case "Mountains": a.bells = 0.5; a.howl = 0.4; a.birds = 0.4
            case "Desert": a.cicadas = 0.5; a.sand = 0.4
            case "Water": a.lapping = 0.6; a.birds = 0.6
            case "Winter": a.crows = 0.4; a.howl = 0.3
            case "Airfields": a.town = 0.5; a.birds = 0.4
            default: a.birds = 0.8; a.crickets = 0.3; a.leaves = 0.3
            }
        }
        return a
    }

    /// Mornings belong to the birds, evenings to the crickets and frogs. `time` 0 morning, 1 midday, 2 evening.
    func at(time: Int) -> Ambience {
        var a = self
        if time <= 1 { a.birds = min(a.birds * 1.4, 1); a.cuckoo = min(a.cuckoo * 1.3, 1); a.cicadas *= 0.3; a.crickets *= 0.5 }
        if time >= 4 { a.birds *= 0.5; a.cuckoo *= 0.3; a.cicadas *= 0.5; a.crickets = min(a.crickets * 1.6, 1); a.frogs = min(a.frogs * 1.5, 1); a.gulls *= 0.6 }
        return a
    }
}

/// One animal calling now and then: a few notes, a pause, a few more.
private struct Voice {
    var wait: Float = 1.5, rep = 0, age: Float = 1, dur: Float = 0.1, gap: Float = 0.2
    var f0: Float = 1000, f1: Float = 1000, vol: Float = 0, pan: Float = 0, ph: Float = 0
}

/// Procedural stereo sound: engine, propeller, rotor, airframe, ground roll, crashes and ambience.
final class SoundEngine {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    var state = SoundState()
    var muted = false
    /// Menu music: plays while `musicOn`, fading in and out; it carries on from where it left off.
    var musicOn = false
    let music = MusicSynth()
    private var sMusic: Float = 0
    let sampleRate: Float = 44100

    // smoothed parameters
    private var sHz: Float = 0, sPower: Float = 0, sRun: Float = 0, sGain: Float = 0, sMuffle: Float = 0, sPan: Float = 0
    private var sAir: Float = 0, sRoll: Float = 0, sWind: Float = 0, sMaster: Float = 0
    private var sMotor = SIMD4<Float>(0, 0, 0, 0)
    // oscillators
    private var pBlade: Float = 0, pShaft: Float = 0, pFire: Float = 0, pWhine: Float = 0, pTail: Float = 0
    private var pMotor = SIMD4<Float>(0, 0.31, 0.57, 0.83)
    private var seed: UInt32 = 0x1234567
    // filters (state-variable: low, band)
    private var propLo: Float = 0, propBd: Float = 0
    private var jetLo: Float = 0, jetBd: Float = 0
    private var airLo: Float = 0, airBd: Float = 0
    private var windLoL: Float = 0, windBdL: Float = 0, windLoR: Float = 0, windBdR: Float = 0
    private var exhaust: Float = 0, rumble: Float = 0, roar: Float = 0, muffL: Float = 0, muffR: Float = 0, wave: Float = 0
    private var lfo1: Float = 0, lfo2: Float = 0.4, lfo3: Float = 0.7
    // engine detail: slow pitch flutter, exhaust resonance, duct howl, per-motor warble, ground reflection
    private var flutter: Float = 0, lope: Float = 1, lopePrev: Float = 0
    private var cyl = 0, exh2: Float = 0, exhDC: Float = 0, raspLo: Float = 0, raspBd: Float = 0
    private var exLo: Float = 0, exBd: Float = 0, fanLo: Float = 0, fanBd: Float = 0, lowLo: Float = 0, lowBd: Float = 0
    private var warble = SIMD4<Float>(0, 0, 0, 0)
    private var sReflect: Float = 0, sReflectGain: Float = 0
    private var echo = [Float](repeating: 0, count: 4096), echoPos = 0
    private var pWhine2: Float = 0, pGear: Float = 0
    // one-shots
    private var crashEnv: Float = 0, crashTone: Float = 0, crashPhase: Float = 0, crackle: Float = 0, splashEnv: Float = 0, splashLo: Float = 0
    private var crashPan: Float = 0
    // flying into a tree: the swish of leaves, twigs snapping one after another; or a knock on something hard
    private var leafEnv: Float = 0, leafLo: Float = 0, leafBd: Float = 0, leafPan: Float = 0, twigs: Float = 0, twigTimer: Float = 0
    private var snapEnv: Float = 0, snapLo: Float = 0, snapBd: Float = 0, snapHz: Float = 900, knockEnv: Float = 0, knockPhase: Float = 0
    // touchdown: a thump from the airframe plus the noise of whatever it landed on
    private var thumpEnv: Float = 0, thumpDecay: Float = 0.999, thumpHz: Float = 90, thumpPhase: Float = 0
    private var touchEnv: Float = 0, touchAmp: Float = 1, touchDecay: Float = 0.999, touchFc: Float = 2000, touchQ: Float = 1, touchSweep: Float = 0
    private var touchLo: Float = 0, touchBd: Float = 0, touchGrit: Float = 0, touchPan: Float = 0
    // ambience
    private var voices = [Voice](repeating: Voice(), count: 7)     // songbird, second songbird, cuckoo, crow, gull, frog, cowbell
    private var lapLo: Float = 0, lapBd: Float = 0, lap1: Float = 0, lap2: Float = 0.3
    private var crk1: Float = 0, crk2: Float = 0, crkT: Float = 0
    private var cicLo: Float = 0, cicBd: Float = 0, cicP: Float = 0
    private var strLo: Float = 0, strBd: Float = 0, strWalk: Float = 0, strLo2: Float = 0
    private var leafLoL: Float = 0, leafBdL: Float = 0, leafLoR: Float = 0, leafBdR: Float = 0
    private var grassLo: Float = 0, sandLo: Float = 0
    private var howlLo: Float = 0, howlBd: Float = 0, howlLo2: Float = 0, howlBd2: Float = 0
    private var townLo: Float = 0, townCarLo: Float = 0, townCarBd: Float = 0, townP: Float = 0.6

    static var offline = false      // tests render the sound themselves
    private(set) var touchCount = 0
    private var statLoadMax: Float = 0, statLoadSum: Float = 0, statCalls = 0, statFrames = 0, statGapMax: Float = 0, statLast: UInt64 = 0
    /// Load of the audio thread since the last call, for --perf.
    func stats() -> String {
        let out = engine.outputNode.outputFormat(forBus: 0)
        let s = String(format: "audio: %d frames per callback, device %.0f Hz, load avg %.0f%% max %.0f%%, longest gap %.1f ms, %d callbacks",
                       statFrames, out.sampleRate, statCalls > 0 ? statLoadSum / Float(statCalls) * 100 : 0, statLoadMax * 100, statGapMax, statCalls)
        statLoadMax = 0; statLoadSum = 0; statCalls = 0; statGapMax = 0
        return s
    }

    init(start: Bool = true) {
        guard start, !SoundEngine.offline, let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2) else { return }
        let n = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 2, let l = bufs[0].mData, let r = bufs[1].mData else { return noErr }
            let t0 = DispatchTime.now().uptimeNanoseconds
            self.render(left: l.assumingMemoryBound(to: Float.self), right: r.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            // how much of the time it has does the synthesizer use, and are callbacks arriving on time
            let t1 = DispatchTime.now().uptimeNanoseconds
            let load = Float(t1 - t0) / (Float(frameCount) / self.sampleRate * 1e9)
            self.statLoadMax = max(self.statLoadMax, load); self.statLoadSum += load; self.statCalls += 1; self.statFrames = Int(frameCount)
            if self.statLast != 0 { self.statGapMax = max(self.statGapMax, Float(t0 - self.statLast) / 1e6) }
            self.statLast = t0
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
    }

    /// The model flies into branches (`woody`) or knocks against something hard such as a goal post.
    func branches(_ strength: Float, woody: Bool, pan: Float = 0) {
        let s = 0.4 + 0.6 * min(max(strength, 0), 1)
        leafPan = pan
        if woody { leafEnv = max(leafEnv, s); twigs = s; twigTimer = 0 }
        else { knockEnv = max(knockEnv, s); knockPhase = 0 }
    }

    /// Impact: `strength` 0...1; `water` makes it a splash.
    func crash(_ strength: Float, water: Bool = false, pan: Float = 0) {
        let s = 0.35 + 0.65 * min(max(strength, 0), 1)
        crashPan = pan
        if water { splashEnv = max(splashEnv, s) } else { crashEnv = max(crashEnv, s); crashTone = s; crackle = s }
    }

    /// The aircraft touches down. `strength` 0...1 from the speed into the ground; `ground` 0 asphalt, 1 grass, 2 snow,
    /// 3 sand, 4 bare earth, 5 water; `wheel` whether a tyre or the airframe touched; `slide` speed along the ground.
    func touch(_ strength: Float, ground: Int, wheel: Bool, slide: Float, mass: Float, pan: Float = 0) {
        touchCount += 1
        let s = 0.25 + 0.75 * min(max(strength, 0), 1)
        touchPan = pan
        if ground == 5 { splashEnv = max(splashEnv, 0.12 + 0.3 * s); return }
        func decay(_ seconds: Float) -> Float { exp(-1 / (seconds * sampleRate)) }
        let size = min(max(powf(1.5 / max(mass, 0.03), 0.22), 0.6), 1.9)       // small models tick, big ones thud
        let skid = min(slide / 12, 1)
        var thump: (hz: Float, amp: Float, t: Float), fc: Float, q: Float, amp: Float, t: Float, grit: Float = 0
        touchSweep = 0
        switch ground {
        case 0:
            thump = (wheel ? 105 : 190, wheel ? 0.55 : 0.8, 0.035)
            if wheel { fc = 1500 + 500 * skid; q = 0.22; amp = 0.5 * skid; t = 0.07 + 0.08 * skid; touchSweep = 0.3 }   // tyre chirp
            else { fc = 2600; q = 0.9; amp = 0.35 + 0.5 * skid; t = 0.1 + 0.15 * skid; grit = 0.5 }                     // scrape
        case 2: thump = (70, 0.35, 0.05); fc = 1300; q = 0.8; amp = 0.75; t = 0.16; grit = 0.9                            // crunch
        case 3: thump = (62, 0.5, 0.06); fc = 4200; q = 1.2; amp = 0.5 + 0.3 * skid; t = 0.2                             // hiss
        case 4: thump = (95, 0.7, 0.04); fc = 850; q = 0.9; amp = 0.55; t = 0.09 + 0.1 * skid; grit = 0.6                // gritty thud
        default: thump = (80, 0.55, 0.05); fc = 3300; q = 1.3; amp = 0.55 + 0.25 * skid; t = 0.12 + 0.1 * skid           // rustle
        }
        thumpHz = thump.hz * size; thumpDecay = decay(thump.t); thumpEnv = max(thumpEnv, thump.amp * s)
        touchFc = fc * (0.8 + 0.2 * size); touchQ = q; touchDecay = decay(t)
        touchAmp = max(amp * s, 0.001); touchEnv = max(touchEnv, touchAmp); touchGrit = max(touchGrit, grit * s)
    }

    /// Advance one calling animal by a sample and add it to the mix.
    /// `kind`: 0 songbird, 1 cuckoo, 2 crow, 3 gull, 4 frog, 5 cowbell. `amount` sets how often it calls.
    @inline(__always) private func call(_ i: Int, _ kind: Int, _ amount: Float, _ dt: Float, _ L: inout Float, _ R: inout Float) {
        if amount <= 0 && voices[i].rep == 0 { return }
        var v = voices[i]
        defer { voices[i] = v }
        v.wait -= dt
        if v.wait <= 0 && v.rep == 0 && amount > 0 {
            let r0 = abs(noise()), r1 = abs(noise()), r2 = abs(noise()), r3 = abs(noise())
            let often = 1 / max(amount, 0.2)
            v.pan = noise() * 0.9; v.age = 0; v.ph = 0
            switch kind {
            case 1: v.rep = 2 * (1 + Int(r0 * 4)); v.f0 = 640 + r1 * 60; v.f1 = v.f0; v.dur = 0.17; v.gap = 0.3; v.vol = 0.006 + r2 * 0.01; v.wait = (10 + r3 * 22) * often
            case 2: v.rep = 2 + Int(r0 * 3); v.f0 = 500 + r1 * 150; v.f1 = v.f0 * 0.84; v.dur = 0.2 + r2 * 0.1; v.gap = v.dur + 0.14; v.vol = 0.007 + r3 * 0.012; v.wait = (6 + r3 * 18) * often
            case 3: v.rep = 3 + Int(r0 * 5); v.f0 = 1450 + r1 * 500; v.f1 = v.f0 * 0.68; v.dur = 0.16 + r2 * 0.14; v.gap = v.dur * 1.25; v.vol = 0.006 + r3 * 0.014; v.wait = (4 + r2 * 11) * often
            case 4: v.rep = 4 + Int(r0 * 9); v.f0 = 360 + r1 * 380; v.f1 = v.f0 * 1.12; v.dur = 0.07 + r2 * 0.06; v.gap = v.dur * 1.7; v.vol = 0.006 + r3 * 0.012; v.wait = (1 + r2 * 4) * often
            case 5: v.rep = 1 + Int(r0 * 4); v.f0 = 620 + r1 * 520; v.f1 = v.f0; v.dur = 0.4; v.gap = 0.42 + r2 * 0.6; v.vol = 0.005 + r3 * 0.01; v.wait = (2.5 + r2 * 8) * often
            default: v.rep = 2 + Int(r0 * 5); v.f0 = 2400 + r1 * 2600; v.f1 = v.f0 * (0.75 + r2 * 0.7); v.dur = 0.05 + r3 * 0.09; v.gap = v.dur * (1.5 + r0); v.vol = 0.012 + r1 * 0.02; v.wait = (2.5 + r2 * 7) * often
            }
        }
        guard v.rep > 0 else { return }
        let twoPi = 2 * Float.pi
        v.age += dt
        if v.age < v.dur {
            let t = v.age / v.dur
            v.ph += (v.f0 + (v.f1 - v.f0) * t) / sampleRate
            if v.ph > 1 { v.ph -= 1 }
            let w = twoPi * v.ph, env = sin(Float.pi * t)
            var s: Float
            switch kind {
            case 2: s = (sin(w) + 0.7 * sin(2 * w) + 0.6 * sin(3 * w) + 0.45 * sin(4 * w) + 0.3 * sin(5 * w)) * (0.55 + 0.45 * noise()) * 0.5 * env   // hoarse
            case 3: s = (sin(w) + 0.5 * sin(2 * w) + 0.3 * sin(3 * w)) * 0.6 * sqrt(env)                                                          // wailing
            case 4: let pulse = 0.5 + 0.5 * sin(twoPi * v.age * 68); s = (sin(w) + 0.5 * sin(2 * w)) * pulse * pulse * 0.8 * env                   // croak
            case 5: s = (sin(twoPi * v.f0 * v.age) + 0.6 * sin(twoPi * v.f0 * 2.76 * v.age) + 0.35 * sin(twoPi * v.f0 * 5.4 * v.age)) * exp(-v.age * 11) * min(v.age * 400, 1)
            default: s = sin(w) * env
            }
            s *= v.vol
            L += s * (1 - v.pan) * 0.5; R += s * (1 + v.pan) * 0.5
        } else if v.age > v.gap {
            v.age = 0; v.rep -= 1; v.ph = 0
            if kind == 1 { v.f0 *= v.rep % 2 == 1 ? 0.8 : 1.25; v.f1 = v.f0 }       // "cu-ckoo": the second note a third lower
        }
    }

    @inline(__always) private func noise() -> Float {
        seed = seed &* 1664525 &+ 1013904223
        return Float(Int32(bitPattern: seed)) * (1.0 / 2147483648.0)
    }
    /// A stack of harmonics on one phase: `tilt` near 1 is buzzy, higher is rounder.
    @inline(__always) private func stack(_ p: Float, _ n: Int, _ tilt: Float) -> Float {
        var s: Float = 0
        let w = 2 * Float.pi * p
        let a = min(max(tilt - 1, 0), 1)                   // blend between 1/k and 1/k squared: no powers in the audio loop
        for k in 1...n { let fk = Float(k); s += sin(fk * w + fk * fk * 0.37) * ((1 - a) / fk + a / (fk * fk)) }
        return s
    }
    @inline(__always) private func wrap(_ p: inout Float, _ hz: Float) {
        p += hz / sampleRate
        if p >= 1 { p -= floor(p) }
    }
    /// State-variable band-pass; returns the band output.
    @inline(__always) private func bandpass(_ x: Float, _ fc: Float, _ q: Float, _ lo: inout Float, _ bd: inout Float) -> Float {
        let f = 2 * sin(Float.pi * min(fc, 7000) / sampleRate)
        lo += f * bd
        let hi = x - lo - q * bd
        bd += f * hi
        return bd
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) {
        let st = state
        let twoPi = 2 * Float.pi
        let k: Float = 0.0012                      // parameter smoothing per sample (~20 ms)
        let masterTarget: Float = (muted || st.paused) ? 0 : 1
        let dt = 1 / sampleRate
        for i in 0..<count {
            sHz += (st.shaftHz - sHz) * k; sPower += (st.power - sPower) * k; sRun += (st.running - sRun) * k * 0.5
            sGain += (st.gain - sGain) * k; sMuffle += (st.muffle - sMuffle) * k; sPan += (st.pan - sPan) * k
            sAir += (st.airspeed - sAir) * k; sRoll += (st.groundRoll - sRoll) * k; sWind += (st.windSpeed - sWind) * k * 0.2
            sMotor += (st.motors - sMotor) * k
            sMaster += (masterTarget - sMaster) * k
            let n0 = noise(), n1 = noise()
            let hz = max(sHz, 0.5)
            var eng: Float = 0

            // every motor hunts a little in speed: turbulence on the blades, the speed controller, the load
            flutter += (n1 * 0.012 - flutter) * 0.0015
            let fl = 1 + flutter
            switch st.engine {
            case 0:     // electric motor and propeller
                wrap(&pBlade, hz * st.blades * fl); wrap(&pWhine, hz * 7 * fl); wrap(&pWhine2, hz * 14.07 * fl)
                // the propeller: a buzz that gets brighter and harsher as it is loaded
                let prop = stack(pBlade, 7, 1.75 - 0.75 * sPower) * 0.2 * (0.3 + 0.7 * sPower)
                // air torn by each passing blade
                let beat = 0.5 + 0.5 * cos(twoPi * pBlade)
                let tear = bandpass(n0, 700 + 2900 * sPower, 0.8, &propLo, &propBd) * (0.25 + 0.75 * beat * beat) * 0.42 * sPower * (0.4 + 0.6 * sPower)
                // the motor itself: magnet whine and its overtone, strongest when it is working
                let whine = (sin(twoPi * pWhine) * 0.03 + sin(twoPi * pWhine2) * 0.016) * (0.35 + 0.65 * sPower)
                // nothing is perfectly balanced: a low hum at the speed of the shaft itself
                wrap(&pShaft, hz * fl)
                let hum = (sin(twoPi * pShaft) * 0.05 + sin(2 * twoPi * pShaft + 1.1) * 0.022) * (0.25 + 0.75 * sPower)
                eng = (prop + tear + whine + hum) * sRun
            case 1:     // piston engine: exhaust pulses, mechanical rumble, propeller
                let fire = hz * st.cylinders * 0.5
                let before = pFire
                wrap(&pFire, fire * fl); wrap(&pBlade, hz * st.blades * fl); wrap(&pShaft, hz * 0.5)
                if pFire < before {
                    // every cylinder has a strength of its own, the same each time round: that repeating pattern is
                    // what makes an engine sound like an engine and not a buzzer. A little chance on top, most at idle.
                    cyl = (cyl + 1) % max(Int(st.cylinders), 1)
                    let own = 1 + (st.radial ? 0.26 : 0.15) * sin(Float(cyl) * 2.4 + 0.7)
                    lope = own * (1 + (0.16 - 0.1 * sPower) * n0)
                }
                // one firing: the pressure rises fast but not instantly, then dies away
                let pulse = (1 - exp(-pFire * 55)) * exp(-pFire * (4.5 + 3.5 * sPower)) * 1.2 * lope
                // the silencer: two low-pass stages that open up with the throttle, so idle is a soft putter and
                // full power is hard-edged
                let open = 0.09 + 0.3 * sPower
                exhaust += (pulse - exhaust) * open; exh2 += (exhaust - exh2) * open
                exhDC += (exh2 - exhDC) * 0.0006
                let note = exh2 - exhDC
                // the pipe rings, and under load the exhaust rasps
                let bark = bandpass(pulse - 0.15, 150 + 1.7 * fire, 0.5, &exLo, &exBd) * 0.42
                let rasp = bandpass(pulse * (0.6 + 0.4 * n0), 1000 + 1700 * sPower, 0.7, &raspLo, &raspBd) * 0.2 * sPower
                rumble += (n1 * pulse - rumble) * 0.05
                let prop = stack(pBlade, 5, 1.7 - 0.5 * sPower) * 0.09 * (0.3 + 0.7 * sPower)
                let beat = 0.5 + 0.5 * cos(twoPi * pBlade)
                let wash = bandpass(n0, 400 + 1800 * sPower, 1.0, &propLo, &propBd) * (0.4 + 0.6 * beat) * 0.26 * sPower * sPower
                // an idling engine is far quieter than one at full throttle
                eng = (note * (0.95 + 0.35 * sPower) + bark * (0.4 + 0.6 * sPower) + rasp + rumble * (0.5 + 1.0 * sPower) + prop + wash) * (0.22 + 0.78 * sPower) * sRun
            case 2, 3:  // ducted fan / jet (2) and turboprop (3)
                let fan = st.engine == 2
                wrap(&pWhine, hz * (fan ? 11 : 28) * fl); wrap(&pWhine2, hz * (fan ? 11.09 : 41) * fl); wrap(&pBlade, hz * st.blades * fl)
                // fan or compressor tone, with a second one close by that beats against it
                var whine = (sin(twoPi * pWhine) + 0.3 * sin(2 * twoPi * pWhine + 0.7) + 0.55 * sin(twoPi * pWhine2)) * (fan ? 0.05 : 0.028) * (0.4 + 0.6 * sPower)
                whine *= 1 + 0.25 * n1
                // the rush of air: a high hiss, a deep roar, and the duct howling at a pitch that follows the revs
                let hiss = bandpass(n0, 1500 + 3200 * sPower, 0.6, &jetLo, &jetBd) * (fan ? 0.36 : 0.14) * (0.2 + 0.8 * sPower)
                roar += (n1 - roar) * 0.02
                let low = bandpass(n1, 110 + 190 * sPower, 0.5, &lowLo, &lowBd) * (fan ? 0.5 : 0.2) * sPower * sPower
                let howl = bandpass(n0, 320 + 22 * hz, 0.12, &fanLo, &fanBd) * (fan ? 0.11 : 0.03) * (0.3 + 0.7 * sPower)
                var s = whine + hiss + low + howl + roar * (fan ? 1.3 : 0.7) * (0.2 + 0.8 * sPower * sPower)
                if !fan {
                    let beat = 0.5 + 0.5 * cos(twoPi * pBlade)
                    s += stack(pBlade, 6, 1.5 - 0.4 * sPower) * 0.17 * (0.3 + 0.7 * sPower) * (0.85 + 0.15 * beat)
                }
                eng = s * sRun
            case 4:     // helicopter: blade slap, rotor wash, tail rotor, gear and motor whine
                let nb = max(st.blades, 2)
                wrap(&pBlade, hz * nb * fl); wrap(&pTail, hz * 9.3 * fl); wrap(&pWhine, hz * 33 * fl); wrap(&pGear, hz * 11.6 * fl)
                // each blade passing: a soft thump always, a hard slap when the rotor is loaded
                let sl = max(sin(twoPi * pBlade), 0)
                let slap = sl * sl * sl * sl * sl * sl
                let thump = stack(pBlade, 3, 1.4) * 0.16
                let wash = bandpass(n0, 300 + 600 * sPower, 0.8, &propLo, &propBd)
                let hissy = bandpass(n1, 1800 + 1500 * sPower, 0.9, &jetLo, &jetBd) * 0.1 * (0.3 + 0.7 * slap)
                let tail = stack(pTail, 4, 1.3) * 0.045
                let gears = sin(twoPi * pGear) * 0.022 + sin(twoPi * pWhine) * 0.026 * (0.5 + 0.5 * sPower)
                eng = (slap * (0.25 + 0.65 * sPower) + thump * (0.5 + 0.5 * sPower) + wash * (0.25 + 0.55 * sPower) * (0.3 + 0.7 * slap) + hissy + tail + gears) * sRun
            default:    // multirotor: each motor has its own voice, and they beat against one another
                var s: Float = 0
                var loud: Float = 0
                for m in 0..<4 {
                    let lv = sMotor[m]
                    if lv < 0.01 { continue }
                    // the flight controller is forever correcting, so no motor holds a steady note
                    warble[m] += (noise() * 0.02 - warble[m]) * 0.004
                    pMotor[m] += hz * (0.1 + 0.9 * lv) * (1 + warble[m]) * st.doppler / sampleRate
                    if pMotor[m] >= 1 { pMotor[m] -= 1 }
                    let a = lv * (0.3 + 0.7 * lv)
                    s += stack(pMotor[m], 6, 1.5 - 0.5 * lv) * a * 0.075
                    loud += a
                }
                let beat = 0.5 + 0.5 * cos(twoPi * pMotor[0])
                let wash = bandpass(n0, 1100 + 3000 * sPower, 0.8, &propLo, &propBd) * (0.5 + 0.5 * beat) * 0.07 * loud
                eng = s * (1 + 0.08 * n1) + wash
            }

            // airframe: the hiss of air over the model, and tyres on the ground
            let air = bandpass(n1, 350 + 60 * sAir, 0.6, &airLo, &airBd) * min(sAir * sAir / 2200, 0.5)
            var src = (eng + air) * sGain
            // sound also reaches the pilot by bouncing off the ground, a moment later: the two add up and cancel
            // at different pitches as the aircraft moves, which is what gives a fly-past its sweeping, hollow tone
            sReflect += (st.reflect - sReflect) * 0.0006; sReflectGain += (st.reflectGain - sReflectGain) * k
            echo[echoPos] = src
            let back = min(sReflect * sampleRate, 4000)
            let i0 = Int(back), fr = back - Float(i0)
            let e0 = echo[(echoPos - i0 + 4096) & 4095], e1 = echo[(echoPos - i0 - 1 + 4096) & 4095]
            src += (e0 + (e1 - e0) * fr) * sReflectGain
            echoPos = (echoPos + 1) & 4095

            // distance: air absorbs the highs
            let cut = 0.9 - 0.82 * sMuffle
            let pl = (1 - sPan) * 0.5, pr = (1 + sPan) * 0.5
            muffL += (src * pl.squareRoot() - muffL) * cut
            muffR += (src * pr.squareRoot() - muffR) * cut
            var L = muffL * 1.25, R = muffR * 1.25

            // ground roll (low, close to the aircraft)
            if sRoll > 0.05 {
                let g = min(sRoll / 12, 1) * sGain
                rumbleRoll += (n0 - rumbleRoll) * 0.015
                L += rumbleRoll * 2.2 * g * pl.squareRoot(); R += rumbleRoll * 2.2 * g * pr.squareRoot()
            }

            // ---- ambience at the pilot's position
            lfo1 += dt * 0.11; if lfo1 > 1 { lfo1 -= 1 }
            lfo2 += dt * 0.047; if lfo2 > 1 { lfo2 -= 1 }
            lfo3 += dt * 0.19; if lfo3 > 1 { lfo3 -= 1 }
            let gust = 0.55 + 0.3 * sin(twoPi * lfo1) + 0.15 * sin(twoPi * lfo3)
            let wAmt = min(0.012 + sWind * 0.011, 0.14) * gust
            let wf = 260 + 70 * sWind + 140 * sin(twoPi * lfo2)
            L += bandpass(n0, wf, 0.5, &windLoL, &windBdL) * wAmt
            R += bandpass(n1, wf * 1.07, 0.5, &windLoR, &windBdR) * wAmt
            let am = st.ambience
            if am.surf > 0 {
                // surf: slow swells of filtered noise
                let swell = max(sin(twoPi * lfo1), 0)
                wave += (n0 - wave) * 0.06
                let w = wave * (0.05 + 0.22 * swell * swell) * am.surf
                L += w; R += w * 0.8 + (n1 - wave) * 0.004 * swell * am.surf
            }
            if am.lapping > 0 {
                // small waves on a shore: quick, uneven washes
                lap1 += dt * 0.37; if lap1 > 1 { lap1 -= 1 }
                lap2 += dt * 0.53; if lap2 > 1 { lap2 -= 1 }
                let wash = max(sin(twoPi * lap1), 0) * (0.5 + 0.5 * sin(twoPi * lap2))
                let w = bandpass(n0, 650 + 500 * wash, 0.9, &lapLo, &lapBd) * (0.006 + 0.03 * wash * wash) * am.lapping
                L += w * 0.8; R += w
            }
            if am.stream > 0 {
                // running water: a bright rush whose pitch burbles about
                strWalk += (n1 - strWalk) * 0.0015
                strLo2 += (n0 - strLo2) * 0.35
                let w = (bandpass(n0, 1700 + 9000 * strWalk, 0.7, &strLo, &strBd) * 0.016 + (n0 - strLo2) * 0.004) * am.stream
                L += w; R += w * 0.7
            }
            if am.leaves > 0 {
                // trees: a broad hush that swells with every gust
                let amt = am.leaves * (0.003 + 0.004 * min(sWind, 12)) * gust
                L += bandpass(n0, 2300 + 500 * gust, 1.3, &leafLoL, &leafBdL) * amt
                R += bandpass(n1, 2700 + 500 * gust, 1.3, &leafLoR, &leafBdR) * amt
            }
            if am.grass > 0 || am.sand > 0 {
                // dry grass and blown sand: thin hiss, only there when the wind is
                grassLo += (n0 - grassLo) * 0.45; sandLo += (n1 - sandLo) * 0.7
                let w = min(sWind, 14)
                let g = (n0 - grassLo) * am.grass * (0.001 + 0.0022 * w) * gust
                let sd = (n1 - sandLo) * am.sand * 0.0016 * w * gust * gust
                L += g + sd * 0.8; R += g * 0.8 + sd
            }
            if am.howl > 0 {
                // wind finding an edge: two wandering whistles, silent in calm air
                let amt = am.howl * 0.0011 * min(sWind, 14) * gust * gust
                L += bandpass(n0, 430 + 150 * sin(twoPi * lfo2) + 60 * sin(twoPi * lfo3), 0.07, &howlLo, &howlBd) * amt
                R += bandpass(n1, 610 + 190 * sin(twoPi * lfo1) + 50 * sin(twoPi * lfo3), 0.07, &howlLo2, &howlBd2) * amt
            }
            if am.town > 0 {
                // a road somewhere: steady low rumble, and now and then a car going by
                townLo += (n0 - townLo) * 0.012
                townP += dt * 0.043; if townP > 1 { townP -= 1 }
                let car = max(sin(twoPi * townP), 0)
                let c4 = car * car * car * car
                let w = (townLo * 0.2 + bandpass(n1, 380 + 260 * car, 0.8, &townCarLo, &townCarBd) * 0.02 * c4) * am.town
                L += w * (1.1 - 0.5 * car); R += w * (0.6 + 0.5 * car)
            }
            if am.crickets > 0 {
                // crickets: two of them, each a short trill of pulses, never quite in step
                crkT += dt; if crkT > 60 { crkT -= 60 }
                wrap(&crk1, 4300); wrap(&crk2, 4750)
                let c1 = crkT * 2.1 - floor(crkT * 2.1), c2 = crkT * 1.7 + 0.4 - floor(crkT * 1.7 + 0.4)
                let p1 = c1 < 0.32 ? max(sin(twoPi * crkT * 29), 0) : 0, p2 = c2 < 0.4 ? max(sin(twoPi * crkT * 24), 0) : 0
                let a1 = sin(twoPi * crk1) * p1 * p1 * 0.007 * am.crickets, a2 = sin(twoPi * crk2) * p2 * p2 * 0.005 * am.crickets
                L += a1 + a2 * 0.3; R += a1 * 0.3 + a2
            }
            if am.cicadas > 0 {
                // cicadas: a rasping buzz that rises and falls over many seconds
                wrap(&cicP, 118)
                let rasp = cicP < 0.5 ? cicP * 2 : 0.15
                let swell = 0.35 + 0.65 * max(sin(twoPi * lfo2 * 2), 0)
                let w = bandpass(n0, 5600 + 500 * sin(twoPi * lfo3), 0.35, &cicLo, &cicBd) * rasp * swell * 0.01 * am.cicadas
                L += w; R += w * 0.75
            }
            let levels = (am.birds, am.birds > 0.6 ? am.birds - 0.5 : 0, am.cuckoo, am.crows, am.gulls, am.frogs, am.bells)
            call(0, 0, levels.0, dt, &L, &R); call(1, 0, levels.1, dt, &L, &R); call(2, 1, levels.2, dt, &L, &R); call(3, 2, levels.3, dt, &L, &R)
            call(4, 3, levels.4, dt, &L, &R); call(5, 4, levels.5, dt, &L, &R); call(6, 5, levels.6, dt, &L, &R)

            // ---- one-shots
            if crashEnv > 0.0005 || crashTone > 0.0005 {
                wrap(&crashPhase, 58)
                crashEnv *= 0.99982; crashTone *= 0.9997; crackle *= 0.99993
                splashLo += (n0 - splashLo) * 0.05
                var c = splashLo * 3.0 * crashEnv * crashEnv + sin(twoPi * crashPhase) * 0.5 * crashTone * crashTone
                // debris: sparse clicks that thin out
                if abs(n1) > 0.9985 - 0.0012 * crackle { c += n0 * 0.5 * crackle }
                c *= max(sGain, 0.25)
                L += c * (1 - crashPan) * 0.6; R += c * (1 + crashPan) * 0.6
            }
            if thumpEnv > 0.0005 || touchEnv > 0.0005 || touchGrit > 0.002 {
                thumpEnv *= thumpDecay; touchEnv *= touchDecay; touchGrit *= 0.9997
                wrap(&thumpPhase, thumpHz * (0.75 + 0.25 * min(thumpEnv * 2, 1)))
                var t = sin(twoPi * thumpPhase) * thumpEnv
                t += bandpass(n0, touchFc * (1 - touchSweep * (1 - touchEnv / touchAmp)), touchQ, &touchLo, &touchBd) * touchEnv
                if abs(n1) > 0.996 - 0.012 * touchGrit { t += n0 * 0.3 * touchGrit }
                t *= max(sGain, 0.3)
                L += t * (1 - touchPan) * 0.6; R += t * (1 + touchPan) * 0.6
            }
            if leafEnv > 0.0005 || twigs > 0.004 || snapEnv > 0.0005 || knockEnv > 0.0005 {
                leafEnv *= 0.99988; twigs *= 0.99991; snapEnv *= 0.9965; knockEnv *= 0.9988
                // leaves: a bright swish that dies away in half a second
                var t = bandpass(n0, 3800 + 1500 * leafEnv, 0.9, &leafLo, &leafBd) * leafEnv * leafEnv * 0.9
                // twigs: sharp dry snaps, close together at first, then fewer
                twigTimer -= dt
                if twigs > 0.03 && twigTimer <= 0 {
                    snapEnv = twigs * (0.5 + 0.5 * abs(n1)); snapHz = 700 + 1600 * abs(n0)
                    twigTimer = (0.012 + 0.07 * abs(n1)) / max(twigs, 0.15)
                }
                t += bandpass(n1, snapHz, 0.35, &snapLo, &snapBd) * snapEnv * 0.55
                // a hard knock: a short ring
                wrap(&knockPhase, 420)
                t += (sin(twoPi * knockPhase) + 0.5 * sin(twoPi * knockPhase * 2.7)) * knockEnv * knockEnv * 0.5
                t *= max(sGain, 0.3)
                L += t * (1 - leafPan) * 0.6; R += t * (1 + leafPan) * 0.6
            }
            if splashEnv > 0.0005 {
                splashEnv *= 0.99992
                let hissy = n0 - splashLo
                splashLo += (n0 - splashLo) * 0.2
                let c = (hissy * 0.25 + splashLo * 0.5) * splashEnv * max(sGain, 0.25)
                L += c * (1 - crashPan) * 0.6; R += c * (1 + crashPan) * 0.6
            }

            // soft limiter
            L *= sMaster * 0.9; R *= sMaster * 0.9
            // menu music, over the top of the (silent, while a menu is open) flight sound
            let musicTarget: Float = musicOn && !muted ? 1 : 0
            sMusic += (musicTarget - sMusic) * (musicTarget > sMusic ? 0.00006 : 0.00004)
            if sMusic > 0.0004 { let m = music.next(); L += m.0 * sMusic; R += m.1 * sMusic }
            left[i] = L / (1 + abs(L)) * 1.6
            right[i] = R / (1 + abs(R)) * 1.6
        }
    }
    private var rumbleRoll: Float = 0
}

/// Render a scripted fly-past of each engine type to a WAV file (used to check the synthesizer without speakers).
/// Loudness of each site's ambience on its own, with no aircraft: 20 seconds at the site's usual wind.
func printAmbienceLevels() {
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 512), r = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    defer { l.deallocate(); r.deallocate() }
    for site in SiteSpec.all {
        let s = SoundEngine(start: false)
        var st = SoundState(); st.ambience = Ambience.of(site); st.windSpeed = site.windSpeed
        s.state = st
        var peak: Float = 0, sumSq: Double = 0, n = 0, bad = false
        for blk in 0..<(Int(s.sampleRate) * 20 / 512) {
            s.render(left: l, right: r, count: 512)
            if blk < 40 { continue }                        // let the levels settle
            for i in 0..<512 { if !l[i].isFinite || !r[i].isFinite { bad = true }; peak = max(peak, abs(l[i]), abs(r[i])); sumSq += Double(l[i] * l[i] + r[i] * r[i]); n += 2 }
        }
        let a = st.ambience
        let parts = [("birds", a.birds), ("cuckoo", a.cuckoo), ("crows", a.crows), ("gulls", a.gulls), ("frogs", a.frogs), ("crickets", a.crickets), ("cicadas", a.cicadas), ("bells", a.bells),
                     ("surf", a.surf), ("lapping", a.lapping), ("stream", a.stream), ("leaves", a.leaves), ("grass", a.grass), ("sand", a.sand), ("howl", a.howl), ("town", a.town)]
        print(String(format: "AMBIENCE %@ wind %2.0f  peak %.3f rms %.4f %@  %@", site.displayName.padding(toLength: 28, withPad: " ", startingAt: 0), site.windSpeed, peak, sqrt(sumSq / Double(n)),
                     bad ? "NON-FINITE" : "ok", parts.filter { $0.1 > 0 }.map { $0.0 }.joined(separator: ", ")))
    }
}

func writeSoundTest(to path: String) {
    let s = SoundEngine(start: false)
    let sr = Int(s.sampleRate)
    var pcm: [Int16] = []
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 512), r = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    defer { l.deallocate(); r.deallocate() }
    let names = ["electric", "piston", "jet", "turboprop", "helicopter", "multirotor"]
    for kind in 0..<6 {
        var peak: Float = 0, sumSq: Double = 0, n = 0, bad = false
        let total = sr * 6 / 512
        for blk in 0..<total {
            let t = Float(blk) / Float(total)                // 0...1 through the pass
            var st = SoundState()
            st.engine = kind
            st.blades = kind == 3 ? 3 : 2; st.cylinders = 9; st.radial = true
            let thr = t < 0.15 ? t / 0.15 * 0.5 : (t < 0.7 ? 0.5 + 0.5 * sin((t - 0.15) * 9) * 0.6 + 0.2 : max(0, (1 - t) / 0.3) * 0.6)
            st.power = min(max(thr, 0), 1); st.running = kind == 1 || kind == 4 ? 1 : (thr > 0.02 ? 1 : 0)
            let x = (t - 0.5) * 2                              // passes left to right
            st.doppler = 1 - 0.06 * x
            let base: Float = [70, 45, 300, 38, 33, 180][kind]
            st.shaftHz = base * (kind == 4 ? 1 : 0.25 + 0.75 * st.power) * st.doppler
            st.motors = SIMD4(st.power, st.power * 0.9, st.power * 1.05, st.power * 0.95)
            st.gain = 1 / (1 + 6 * x * x); st.muffle = min(abs(x) * 0.8, 1); st.pan = x
            st.airspeed = 8 + 14 * st.power; st.windSpeed = 3; st.ambience = Ambience.of(SiteSpec.all[kind * 3 % SiteSpec.all.count])
            s.state = st
            if blk == total * 9 / 10 { s.crash(0.8, water: kind % 2 == 1, pan: 0.5) }
            if blk == total / 4 { s.branches(0.8, woody: kind % 2 == 0, pan: 0.2) }
            if blk == total / 2 { s.touch(0.6, ground: kind, wheel: kind != 4, slide: 9, mass: 1.5, pan: -0.3) }
            s.render(left: l, right: r, count: 512)
            for i in 0..<512 {
                if !l[i].isFinite || !r[i].isFinite { bad = true }
                peak = max(peak, abs(l[i]), abs(r[i])); sumSq += Double(l[i] * l[i] + r[i] * r[i]); n += 2
                pcm.append(Int16(max(-1, min(1, l[i])) * 32000)); pcm.append(Int16(max(-1, min(1, r[i])) * 32000))
            }
        }
        print(String(format: "SOUND %@: peak %.2f rms %.3f %@", names[kind], peak, sqrt(sumSq / Double(n)), bad ? "NON-FINITE SAMPLES" : "ok"))
    }
    writeWav(pcm, sampleRate: sr, to: path)
}

func writeWav(_ pcm: [Int16], sampleRate sr: Int, to path: String) {
    var d = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
    let bytes = UInt32(pcm.count * 2)
    d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
    u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr * 4)); u16(4); u16(16)
    d.append("data".data(using: .ascii)!); u32(bytes)
    pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
    try? d.write(to: URL(fileURLWithPath: path))
}
