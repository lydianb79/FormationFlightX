import simd
import Foundation
import SwiftUI
import AppKit

struct HUDState {
    var aircraft = "", site = "", blurb = ""
    var alt: Float = 0, speed: Float = 0, dist: Float = 0, climb: Float = 0, throttle: Float = 0
    var wind = "", message = "", camera = "", mode = "", input = "", score = "", time = ""
    var lx: Float = 0, ly: Float = 0, rx: Float = 0, ry: Float = 0
    var leftLabel = "THR / RUD", rightLabel = "ELE / AIL", rates = "", config = ""
    var fps = 0
    // formation
    var role = "", formation = "", station = "", net = ""
    var mates: [Mate] = []
    var chat: [ChatLine] = []       // the latest lines, shown for a few seconds in flight
    var talking: [String] = []      // who is speaking
    var mic = ""                    // what the microphone is doing
    var micLive = false
    var unread = 0
    var slot: V3? = nil             // own slot error in metres: x right, y up, z ahead; nil when leading or without a lead
    var slotTol: Float = 1
    var onStation = false
}

/// One line of the formation list in the display.
struct Mate: Identifiable { var id: UInt32; var number: Int; var name: String; var detail: String; var good: Bool; var talking = false }

/// A line in the lobby's chat: something a pilot wrote, or a note from the app (someone joined, someone left).
struct ChatLine: Identifiable { var id: Int; var name: String; var text: String; var mine = false; var system = false; var time = 0.0 }

enum Overlay {
    case none, menu, aircraft, sites, environment, help, splash, formation, lobby, options
    /// The simulation is frozen while these are open.
    var pausesSim: Bool { self == .menu || self == .aircraft || self == .sites || self == .splash || self == .formation || self == .lobby || self == .options }
}

final class HUDModel: ObservableObject {
    @Published var s = HUDState()
    @Published var visible = true
    @Published var overlay = Overlay.none
    @Published var fullscreen = false
    /// Set once the window is in place (full screen reached), so the splash animation starts on a still picture.
    @Published var splashGo = false
    unowned var game: Game!
    var thumbnailer: ((AircraftSpec) -> NSImage?)?      // provided by the renderer
    var addPanorama: (() -> Void)?
    var choosePanoramaFolder: (() -> Void)?
    var openControllerSetup: (() -> Void)?
    private var thumbs: [String: NSImage] = [:]
    private var sitePreviews: [String: NSImage] = [:]

    func thumbnail(_ spec: AircraftSpec) -> NSImage? {
        if let t = thumbs[spec.name] { return t }
        guard let img = thumbnailer?(spec) else { return nil }
        thumbs[spec.name] = img
        return img
    }

    private var previewsPending = Set<String>()
    /// Forget the photo-site previews held in memory (the photo folder changed) and prepare them again.
    func clearSitePreviews() { sitePreviews = [:]; warmSitePreviews() }
    private static let previewQueue = DispatchQueue(label: "formationflightx.previews", qos: .userInitiated)

    /// Where the small preview of a photo site is kept, so the big photograph is decoded once, not on every launch.
    /// The name changes with the photo's size, date and rotation, which makes a stale preview impossible.
    private static func previewCache(_ site: SiteSpec, _ url: URL) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("FormationFlightX/Previews") else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let at = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (at?[.size] as? NSNumber)?.intValue ?? 0, date = Int((at?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        return dir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(size)-\(date)-\(Int(site.north.rounded())).jpg")
    }

    /// The view straight ahead, cut from the middle of the panorama.
    private static func makePreview(_ site: SiteSpec, _ url: URL) -> CGImage? {
        guard let full = Panoramas.image(url, maxSize: 2048) else { return nil }
        let w = full.width, h = full.height
        let shift = Int(Float(w) * site.north / 360)
        let cx = ((w / 2 + shift) % w + w) % w
        let cw = w / 4, ch = Int(Float(cw) * 0.625)
        let x0 = min(max(cx - cw / 2, 0), w - cw)
        return full.cropping(to: CGRect(x: x0, y: h / 2 - Int(Float(ch) * 0.62), width: cw, height: ch))
    }

    /// Preview picture of a site. A photo site's preview comes from a small cached file; if there is none yet it is
    /// made in the background and the list fills in when it is ready, so opening the list never waits.
    func sitePreview(_ site: SiteSpec) -> NSImage? {
        if let t = sitePreviews[site.name] { return t }
        var img: NSImage?
        if let url = site.panorama {
            let cache = HUDModel.previewCache(site, url)
            if let c = cache, let cached = NSImage(contentsOf: c) { img = cached }
            else if previewsPending.insert(site.name).inserted {
                HUDModel.previewQueue.async { [weak self] in
                    guard let c = HUDModel.makePreview(site, url) else { return }
                    let made = NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height))
                    if let out = cache, let data = NSBitmapImageRep(cgImage: c).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) { try? data.write(to: out) }
                    DispatchQueue.main.async { self?.sitePreviews[site.name] = made; self?.objectWillChange.send() }
                }
            }
        } else if let url = resourceURL("Previews/site_\(site.key).jpg") {
            img = NSImage(contentsOf: url)
        }
        if let i = img { sitePreviews[site.name] = i }
        return img
    }

    /// Get every photo site's preview ready ahead of time.
    func warmSitePreviews() { for site in SiteSpec.all where site.panorama != nil { _ = sitePreview(site) } }
}

/// Locate a bundled resource, both inside the .app and when run from the source folder.
func resourceURL(_ rel: String) -> URL? {
    let fm = FileManager.default
    var roots: [URL] = []
    if let r = Bundle.main.resourceURL { roots.append(r) }
    roots.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources"))
    roots.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources"))
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    for _ in 0..<4 { roots.append(dir.appendingPathComponent("Resources")); dir = dir.deletingLastPathComponent() }
    for r in roots {
        let u = r.appendingPathComponent(rel)
        if fm.fileExists(atPath: u.path) { return u }
    }
    return nil
}

struct Balloon { var pos: V3; var color: V4; var alive = true }

/// A part that has broken off in a crash and tumbles on its own.
struct Debris { var part: Int; var pos: V3; var q: simd_quatf; var vel: V3; var omega: V3; var offset: V3 }

/// Smoke / dust puff, drawn as a camera-facing quad.
struct Particle { var pos: V3; var vel: V3; var age: Float; var life: Float; var size: Float; var color: V4; var fall: Float = 0 }      // fall > 0: a leaf, which drops and flutters

struct Lighting { var sunDir: V3; var sun: V3; var ambient: V3; var zenith: V3; var horizon: V3 }

final class Game {
    static let cameraNames = ["Pilot (line of sight)", "Chase", "Onboard"]
    static let zoomNames = ["Auto zoom", "Keep ground in view", "Fixed"]
    static let timeNames = ["Dawn", "Morning", "Midday", "Afternoon", "Evening", "Dusk"]
    /// Photo sites cannot move the sun, but the light can be graded toward evening or dusk.
    static let photoLightNames = ["As photographed", "Golden evening", "Dusk"]
    static let photoTints: [V3] = [V3(1, 1, 1), V3(1.0, 0.8, 0.6) * 0.88, V3(0.45, 0.5, 0.78) * 0.5]
    var photoLight = 0
    /// A site's own time of day (0 morning, 1 midday, 2 evening) as an index into `timeNames`.
    static func time(forSite t: Int) -> Int { [1, 2, 4][min(max(t, 0), 2)] }

    var siteIndex = 0, aircraftIndex = 0
    var site: SiteSpec
    var terrain: Terrain
    let env = Environment()
    var aircraft: Aircraft
    let input = InputManager()
    let sound = SoundEngine()
    let hud = HUDModel()

    var paused = false
    var timeScale: Float = 1
    var cameraMode = 1, zoomMode = 1, flightMode = 0, timeOfDay = 2
    var rotorSpeed = 1                  // helicopters: 0 low, 1 normal, 2 high head speed
    static let rotorNames = ["Low (80%)", "Normal (90%)", "High (100%)"]
    var autopilotOn = false
    var autopilot = Autopilot()
    var ownPilot = FormationPilot()         // the autopilot for this pilot's own wing (K)
    var controls = Controls()
    var siteVersion = 0, aircraftVersion = 0
    var panoLight: Lighting?
    /// Where the current photo site's picture holds something and where it is open sky; made in the background.
    var panoMask: PanoMask?
    private var maskToken = 0
    private func loadMask() {
        panoMask = nil; maskToken += 1
        guard let url = site.panorama else { return }
        let token = maskToken
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let m = PanoMask(url: url)
            DispatchQueue.main.async { if let s = self, s.maskToken == token { s.panoMask = m } }
        }
    }

    var eye = V3(0, 1.7, 14), target = V3(0, 1, 0), upVec = V3(0, 1, 0)
    var fov: Float = 50 * deg
    private var camTarget = V3.zero
    private var camSnap = true

    // MARK: Formation
    let net = FormationNet()
    /// Everyone else in the formation: pilots on the network, or computer-flown partners when flying alone.
    var wingmen: [Wingman] = []
    var formation: FormationKind = FormationKind(rawValue: UserDefaults.standard.integer(forKey: "formation")) ?? .vic { didSet { UserDefaults.standard.set(formation.rawValue, forKey: "formation") } }
    var spacing: Int = (UserDefaults.standard.object(forKey: "spacing") as? Int) ?? 1 { didSet { UserDefaults.standard.set(spacing, forKey: "spacing") } }
    /// Computer-flown partners fill the formation while no other pilot is connected.
    var aiPartners: Bool = !UserDefaults.standard.bool(forKey: "aiOff") { didSet { UserDefaults.standard.set(!aiPartners, forKey: "aiOff") } }
    var multiplayer: Bool = !UserDefaults.standard.bool(forKey: "netOff") { didSet { UserDefaults.standard.set(!multiplayer, forKey: "netOff"); if netAllowed { multiplayer ? net.start() : net.stop() } } }
    /// Off for command-line test runs, so they neither advertise nor search.
    var netAllowed = false { didSet { if netAllowed && multiplayer { net.start() } else { net.stop() } } }
    var pilotName: String = UserDefaults.standard.string(forKey: "pilotName") ?? "Pilot \(Int.random(in: 10...99))" { didSet { UserDefaults.standard.set(pilotName, forKey: "pilotName") } }
    /// Only pilots with the same group name fly together, so two groups can share one network.
    var group: String = UserDefaults.standard.string(forKey: "group") ?? "" { didSet { UserDefaults.standard.set(group, forKey: "group") } }
    /// The online host last joined, kept for next time.
    var hostAddress: String = UserDefaults.standard.string(forKey: "hostAddress") ?? "" { didSet { UserDefaults.standard.set(hostAddress, forKey: "hostAddress") } }
    // lobby: chat and voice
    let voice = VoiceChat()
    var chat: [ChatLine] = []
    var chatCount = 0, unreadChat = 0
    var chatSeq = UInt32.random(in: 1...1_000_000)
    var chatOut: [(data: Data, left: Int, next: Double)] = []      // lines still being repeated
    var chatSeen = Set<UInt64>()
    var lobbyTalk = false               // the lobby's hold-to-talk button is down
    // the session, run by the host: while it is stopped everyone waits in the lobby
    var sessionRunning = false
    var sessionCount: UInt32 = 0        // starts and restarts so far, as the host counts them
    var sessionSeen: UInt32 = 0         // the last start this pilot acted on
    // racing through gates
    var raceNext = 0, raceLaps = 0, raceRunning = false
    var raceTime: Float = 0, raceBest: Float? = nil
    var racePrev = V3.zero
    var gateMarker: (pos: V3, dir: V3, w: Float, h: Float)? = nil
    var launchGrace: Float = 0          // seconds after a launch during which wings pass through each other
    var lobbyReturn = false             // a browser opened from the lobby goes back to it
    var leadEpoch: UInt32 = 0
    var order: [UInt32] = []            // the formation: lead first, then numbers 2 and 3
    var slotMarker: (pos: V3, fwd: V3, radius: Float, good: Bool)? = nil
    var sendAcc: Float = 0, helloAcc: Float = 1
    var stationTime: Float = 0, flownTime: Float = 0
    var slotError: V3? = nil, slotTol: Float = 1
    var wingSmokeAcc: Float = 0

    var balloons: [Balloon] = []
    var debris: [Debris] = []
    var particles: [Particle] = []
    var showObstacles = false
    /// When off, the battery drains with use and the motor fades as it empties.
    var unlimitedBattery: Bool = UserDefaults.standard.bool(forKey: "unlimitedBattery") { didSet { UserDefaults.standard.set(unlimitedBattery, forKey: "unlimitedBattery") } }
    private var warnedBattery = false
    /// Graphics quality: 0 low (reduced resolution, no ambient occlusion), 1 medium, 2 high (full resolution)
    var quality: Int = (UserDefaults.standard.object(forKey: "quality") as? Int) ?? 2 { didSet { UserDefaults.standard.set(quality, forKey: "quality") } }
    static let qualityNames = ["Low", "Medium", "High"]
    var renderScale: Float = 1, gpuMs: Float = 0       // reported by the renderer
    var advanceMs: [Float] = []
    static let noInterp = CommandLine.arguments.contains("--no-interp")
    /// Menu music on or off (remembered).
    var musicEnabled = !UserDefaults.standard.bool(forKey: "musicOff") { didSet { UserDefaults.standard.set(!musicEnabled, forKey: "musicOff") } }
    var cameFromMenu = false        // browsers and panels return to the main menu when opened from it
    /// The flight is held: a menu or browser is open, or a panel that was opened from the main menu.
    var simHeld: Bool { hud.overlay.pausesSim || ((cameFromMenu || lobbyReturn) && (hud.overlay == .environment || hud.overlay == .help)) }
    var fixedView: (eye: V3, target: V3)? = nil     // debug: absolute camera, heights above the pilot's ground
    var closeup: V3? = nil          // debug: fixed camera offset from the aircraft, in wingspans
    var flapSetting: Float = 0
    var gearUp = false, smokeOn = false, hold = false
    private var wasCrashed = false, smokeAcc: Float = 0
    private var rng = LCG(7)
    var challenge = false
    private var score = 0, challengeTime: Float = 0
    var acc: Float = 0
    private var crashTimer: Float = 0, hudTimer: Float = 0
    var message = "", messageTimer: Float = 0
    private var frames = 0, fpsTime: Float = 0, fps = 0
    private var lastY: Float = 0, climb: Float = 0

    init(site si: Int = 0, aircraft ai: Int = 0) {
        siteIndex = min(max(si, 0), SiteSpec.all.count - 1)
        aircraftIndex = min(max(ai, 0), AircraftLibrary.all.count - 1)
        site = SiteSpec.all[siteIndex]
        terrain = Terrain(site: site)
        env.configure(site)
        env.obstacles = terrain.windObstacles
        panoLight = site.panorama != nil ? Panoramas.analyze(site) : nil
        timeOfDay = Game.time(forSite: site.defaultTime)
        aircraft = Aircraft(AircraftLibrary.all[aircraftIndex])
        flightMode = min(aircraft.spec.defaultMode, max(aircraft.spec.modes.count - 1, 0))
        newSession()
        resetAircraft()
        hud.game = self
        loadMask()
        DispatchQueue.main.async { [weak self] in self?.hud.warmSitePreviews() }
    }

    var lighting: Lighting {
        if var p = panoLight {
            // a graded photo lights the model to match: dimmer, and warmer or bluer
            let t = Game.photoTints[photoLight]
            if photoLight > 0 { p.sun *= t * (photoLight == 2 ? 0.35 : 0.9); p.ambient *= t; p.zenith *= t; p.horizon *= t }
            return p
        }
        switch timeOfDay {
        case 0: return Lighting(sunDir: normalize(V3(0.9, 0.11, 0.4)), sun: V3(1, 0.62, 0.42) * 2.3, ambient: V3(0.4, 0.4, 0.52) * 0.75,
                                zenith: V3(0.13, 0.2, 0.44), horizon: V3(0.85, 0.6, 0.5))
        case 1: return Lighting(sunDir: normalize(V3(0.8, 0.3, 0.5)), sun: V3(1, 0.85, 0.65) * 2.8, ambient: V3(0.36, 0.42, 0.55) * 0.5,
                                zenith: V3(0.16, 0.3, 0.6), horizon: V3(0.7, 0.66, 0.6))
        case 3: return Lighting(sunDir: normalize(V3(-0.62, 0.5, 0.5)), sun: V3(1, 0.91, 0.76) * 3.1, ambient: V3(0.35, 0.44, 0.6) * 0.6,
                                zenith: V3(0.1, 0.24, 0.58), horizon: V3(0.58, 0.66, 0.8))
        case 4: return Lighting(sunDir: normalize(V3(-0.85, 0.2, 0.45)), sun: V3(1, 0.58, 0.3) * 3.4, ambient: V3(0.4, 0.38, 0.5) * 0.7,
                                zenith: V3(0.1, 0.17, 0.4), horizon: V3(0.8, 0.5, 0.32))
        case 5: return Lighting(sunDir: normalize(V3(-0.92, 0.07, 0.4)), sun: V3(1, 0.45, 0.3) * 1.3, ambient: V3(0.3, 0.33, 0.52) * 0.6,
                                zenith: V3(0.05, 0.08, 0.22), horizon: V3(0.62, 0.36, 0.3))
        default: return Lighting(sunDir: normalize(V3(-0.35, 0.8, 0.5)), sun: V3(1, 0.96, 0.88) * 3.2, ambient: V3(0.34, 0.45, 0.62) * 0.62,
                                 zenith: V3(0.09, 0.24, 0.6), horizon: V3(0.5, 0.65, 0.84))
        }
    }

    // MARK: Commands

    func say(_ m: String, _ t: Float = 2.5) { message = m; messageTimer = t }

    /// A new aircraft: its own rates, and always the low ones to begin with.
    // MARK: Pitch trim

    /// Pitch trim in clicks, as on a transmitter: each click moves the elevator neutral a little. Kept per aircraft.
    private(set) var pitchTrim = 0
    static let trimStep: Float = 0.012, trimMax = 30
    func trim(_ clicks: Int) {
        let t = clicks == 0 ? 0 : min(max(pitchTrim + clicks, -Game.trimMax), Game.trimMax)
        if t == pitchTrim && clicks != 0 { say(String(format: "Pitch trim at its limit (%+d)", t)); return }
        pitchTrim = t
        var all = UserDefaults.standard.dictionary(forKey: "pitchTrim") as? [String: Int] ?? [:]
        all[aircraft.spec.name] = t == 0 ? nil : t
        UserDefaults.standard.set(all, forKey: "pitchTrim")
        say(t == 0 ? "Pitch trim centred" : String(format: "Pitch trim %+d (%@)", t, t > 0 ? "nose up" : "nose down"))
    }

    private func newSession() {
        pitchTrim = (UserDefaults.standard.dictionary(forKey: "pitchTrim") as? [String: Int])?[aircraft.spec.name] ?? 0
        input.aircraftLowRate = aircraft.spec.lowRate; input.aircraftExpo = aircraft.spec.expo
        input.lowRates = true
        rotorSpeed = 1
    }

    func resetAircraft() {
        let spec = aircraft.spec
        if spec.hasFloats, let p = terrain.waterStart(windFrom: env.windFrom) {
            // floatplanes start on the water, pointing into the wind
            aircraft.reset(pos: p + V3(0, aircraft.restHeight - 0.05, 0), heading: -env.windFrom * deg)
        } else if site.panorama != nil {
            // photo sites: each has its own start point and take-off direction
            let k: Float = spec.kind == .airplane ? 1 : 0.6
            let hd = -site.startHeading * deg
            if spec.handLaunch { aircraft.reset(pos: V3(2, 1.9, -3), heading: hd, speed: clampf(spec.stallSpeed * 1.7, 4, 9)) }
            else { aircraft.reset(pos: V3(site.startX * k, terrain.height(site.startX * k, site.startZ * k) + aircraft.restHeight + 0.02, site.startZ * k), heading: hd) }
        } else if spec.handLaunch {
            // pilots stand side by side, in formation order
            aircraft.reset(pos: terrain.pilotPos + V3(2 + 3 * Float(max(order.firstIndex(of: net.id) ?? 0, 0)), 1.9, -3), heading: 0, speed: clampf(spec.stallSpeed * 1.7, 4, 9))
        } else {
            let x: Float = spec.kind == .airplane ? -min(site.runwayLen / 2 - 20, 45) : -5
            let z: Float = site.startZ + (spec.kind == .airplane ? 0 : -1)
            aircraft.reset(pos: V3(x, terrain.height(x, z) + aircraft.restHeight + 0.02, z), heading: -.pi / 2)
        }
        input.resetThrottle(spec.kind, launch: spec.handLaunch)
        touchQuiet = 0.6            // settling onto its wheels is not a touchdown
        crashTimer = 0
        autopilot = Autopilot(); ownPilot = FormationPilot()
        camSnap = true
        debris = []; wasCrashed = false; warnedBattery = false
        flapSetting = 0; gearUp = false; hold = false
        lastY = aircraft.pos.y; climb = 0
        stationTime = 0; flownTime = 0
        launchGrace = 6
        resetRace()
    }

    func selectAircraft(_ i: Int) {
        guard i >= 0 && i < AircraftLibrary.all.count else { return }
        if together && sessionRunning && !isHost && i != aircraftIndex {
            say("Wings can be changed when the host stops the session", 3); return
        }
        aircraftIndex = i
        aircraft = Aircraft(AircraftLibrary.all[i])
        flightMode = min(aircraft.spec.defaultMode, max(aircraft.spec.modes.count - 1, 0))
        newSession()
        aircraftVersion += 1
        resetAircraft()
        UserDefaults.standard.set(aircraft.spec.name, forKey: "lastAircraft")
        say(aircraft.spec.name + " — " + aircraft.spec.blurb, 4)
    }

    func selectSite(_ i: Int) {
        guard i >= 0 && i < SiteSpec.all.count else { return }
        siteIndex = i
        site = SiteSpec.all[i]
        terrain = Terrain(site: site)
        env.configure(site)
        env.obstacles = terrain.windObstacles
        panoLight = site.panorama != nil ? Panoramas.analyze(site) : nil
        loadMask()
        if site.panorama != nil { cameraMode = 0 } else { timeOfDay = Game.time(forSite: site.defaultTime) }
        siteVersion += 1
        if challenge { spawnBalloons() }
        raceBest = nil
        resetAircraft()
        for w in wingmen where w.ai != nil { place(w) }
        helloAcc = 1
        UserDefaults.standard.set(site.name, forKey: "lastSite")
        say(site.name, 3)
    }

    /// Align a photo site: rotate it, shift its horizon, or change the camera height. Saved next to the image.
    func adjustPanorama(north: Float = 0, horizon: Float = 0, eye: Float = 0) {
        guard site.panorama != nil else { say("Only for photo sites"); return }
        site.north = (site.north + north).truncatingRemainder(dividingBy: 360)
        site.horizon = clampf(site.horizon + horizon, -20, 20)
        site.eyeHeight = clampf(site.eyeHeight + eye, 0.3, 30)
        SiteSpec.all[siteIndex] = site
        Panoramas.save(site)
        if site.slope != 0, north != 0 { terrain = Terrain(site: site); env.obstacles = terrain.windObstacles }
        panoLight = Panoramas.analyze(site)
        say(String(format: "Rotation %.0f°  ·  horizon %+.1f°  ·  eye height %.1f m", site.north, site.horizon, site.eyeHeight))
    }

    func toggleChallenge() {
        challenge.toggle()
        if challenge { spawnBalloons(); say("Balloon Burst — pop all 10 balloons!", 4) } else { balloons = []; say("Challenge off") }
    }

    private func spawnBalloons() {
        var rng = LCG(UInt64(Date().timeIntervalSince1970))
        let cols = [rgb(0.95, 0.15, 0.15), rgb(0.98, 0.8, 0.1), rgb(0.15, 0.45, 0.95), rgb(0.2, 0.8, 0.3), rgb(0.9, 0.3, 0.8)]
        balloons = (0..<10).map { i in
            let x = rng.range(-130, 130), z = rng.range(-170, -25)
            return Balloon(pos: V3(x, terrain.height(x, z) + rng.range(6, 38), z), color: cols[i % cols.count])
        }
        score = 0; challengeTime = 0
    }

    func keyDown(_ k: UInt16) {
        switch k {
        case 49, 15: resetAircraft()
        case 35: paused.toggle()
        case 8:
            if site.panorama != nil { cameraMode = 0; say("Photo sites use the pilot camera only") }
            else { cameraMode = (cameraMode + 1) % 3; camSnap = true; say("Camera: " + Game.cameraNames[cameraMode]) }
        case 6: zoomMode = (zoomMode + 1) % 3; say("Zoom: " + Game.zoomNames[zoomMode])
        case 4: cameFromMenu = false; hud.overlay = hud.overlay == .help ? .none : .help
        case 9: hud.visible.toggle()
        case 17: timeScale = timeScale == 1 ? 0.5 : (timeScale == 0.5 ? 0.25 : 1); say(String(format: "Simulation speed %.0f%%", timeScale * 100))
        case 14:
            if aircraft.spec.hasFlaps { flapSetting = flapSetting >= 1 ? 0 : flapSetting + 0.5; say(["Flaps up", "Flaps half", "Flaps full"][Int(flapSetting * 2)]) }
            else { say("This aircraft has no flaps") }
        case 5: aiPartners.toggle(); say(aiPartners ? "Computer partners fly with you when you are alone" : "Computer partners off")
        case 38: _ = joinUp(quiet: false)
        case 31: nextFormation()
        case 32: takeLead()
        case 34: nextSpacing()
        case 16: smokeOn.toggle(); say(smokeOn ? "Smoke on" : "Smoke off")
        case 37: input.lowRates.toggle(); say(input.lowRates ? String(format: "Low rates (%.0f%%)", input.lowRateInUse * 100) : "High rates")
        case 24: trim(1)
        case 27: trim(-1)
        case 29: trim(0)
        case 46: sound.muted.toggle(); say(sound.muted ? "Sound off" : "Sound on")
        case 45: chooseSite((siteIndex + 1) % SiteSpec.all.count)
        case 36: cameFromMenu = false; hud.overlay = .lobby
        case 40: autopilotOn.toggle(); ownPilot = FormationPilot(); say(autopilotOn ? (isLead ? "Autopilot leading the racetrack" : "Autopilot holding your slot") : "You have control")
        case 3:
            let n = aircraft.spec.modes.count
            if n > 1 { flightMode = (flightMode + 1) % n; say("Flight mode: " + aircraft.spec.modes[flightMode]) }
        case 43: env.windSpeed = max(0, env.windSpeed - 1); say(String(format: "Wind %.0f m/s", env.windSpeed))
        case 47: env.windSpeed = min(20, env.windSpeed + 1); say(String(format: "Wind %.0f m/s", env.windSpeed))
        case 18, 19, 20, 21, 23, 22, 26, 28, 25:
            selectAircraft([18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8][k]!)
        case 30: selectAircraft((aircraftIndex + 1) % AircraftLibrary.all.count)
        case 33: selectAircraft((aircraftIndex + AircraftLibrary.all.count - 1) % AircraftLibrary.all.count)
        default: break
        }
    }

    // MARK: Switches and buttons

    private var bindLast: [String: Int] = [:]
    private var siteAmbience: Ambience { if ambienceFor != site.name { ambienceFor = site.name; ambienceCache = Ambience.of(site) }; return ambienceCache }
    private var ambienceFor = "", ambienceCache = Ambience()
    private var touchQuiet: Float = 0           // a short gap between touchdown sounds

    /// Act on the controller switches and buttons the pilot has assigned. A switch sets its state when it is
    /// moved; a button steps through the states, or triggers the action, each time it is pressed.
    private func applyBindings() {
        guard input.hid.connected, let binds = input.settings.bindings else { return }
        for a in InputManager.actions where a.states >= 0 {
            guard let b = binds[a.id] else { bindLast[a.id] = nil; continue }
            let v = input.value(of: b)
            let positional = a.states >= 2 && (b.axis || b.follow)
            let pos: Int
            if !positional { pos = v > 0.3 ? 1 : 0 }
            else if a.states == 2 { pos = v > 0 ? 1 : 0 }
            else { pos = b.axis ? (v < -0.33 ? 0 : (v > 0.33 ? 2 : 1)) : (v > 0 ? 2 : 0) }
            let last = bindLast[a.id]
            bindLast[a.id] = pos
            guard let l = last, l != pos else { continue }
            if !positional { if pos == 1 { keyDown(a.key) }; continue }
            let spec = aircraft.spec
            switch a.id {
            case "rates": input.lowRates = pos == 0; say(input.lowRates ? String(format: "Low rates (%.0f%%)", input.lowRateInUse * 100) : "High rates")
            case "mode": if spec.modes.count > 1 { flightMode = min(pos, spec.modes.count - 1); say("Flight mode: " + spec.modes[flightMode]) }
            case "rotor": if spec.kind == .helicopter { rotorSpeed = pos; say("Rotor speed: " + Game.rotorNames[rotorSpeed]) }
            case "hold": if spec.kind == .helicopter { hold = pos == 1; say(hold ? "Throttle hold — autorotate!" : "Engine engaged") }
            case "flaps": if spec.hasFlaps { flapSetting = Float(pos) * 0.5; say(["Flaps up", "Flaps half", "Flaps full"][pos]) }
            case "gear": if spec.hasRetracts { gearUp = pos == 1; say(gearUp ? "Gear up" : "Gear down") }
            case "smoke": smokeOn = pos == 1; say(smokeOn ? "Smoke on" : "Smoke off")
            default: break
            }
        }
    }

    // MARK: Frame

    func frame(dt realDt: Float) {
        let dt = min(realDt, 0.05)
        frames += 1; fpsTime += realDt
        if fpsTime >= 0.5 { fps = Int(Float(frames) / fpsTime + 0.5); frames = 0; fpsTime = 0 }

        applyBindings()
        updateRoster()
        if autopilotOn && !aircraft.crashed {
            controls = flyMyPart(dt: dt)
            _ = input.poll(dt: dt, kind: aircraft.spec.kind)
        } else {
            controls = input.poll(dt: dt, kind: aircraft.spec.kind)
            controls.mode = flightMode
            controls.rotorSpeed = rotorSpeed
        }
        if !autopilotOn { controls.elevator = clampf(controls.elevator + Float(pitchTrim) * Game.trimStep, -1, 1) }
        // on a hillside the model is held until the throttle is opened, so it does not roll away
        if site.slope != 0, site.panorama != nil, aircraft.onGround, controls.throttle < 0.06, length(aircraft.vel) < 2 { controls.brake = 1 }
        controls.flaps = flapSetting; controls.gearUp = gearUp; controls.hold = hold
        aircraft.unlimitedBattery = unlimitedBattery || autopilotOn
        if aircraft.spec.kind == .airplane && aircraft.battery < 0.15 && !warnedBattery { warnedBattery = true; say(aircraft.spec.burnsFuel ? "Fuel low — land soon" : "Battery low — land soon", 4) }

        if !paused && !simHeld {
            let h: Float = 0.001
            acc += dt * timeScale
            while acc >= h {
                env.advance(dt: h, at: aircraft.pos, airspeed: aircraft.airspeed, terrain: terrain)
                aircraft.step(dt: h, c: controls, terrain: terrain, wind: env.wind(at: aircraft.pos, terrain: terrain), rollMu: site.rollMu)
                for w in wingmen where w.ai != nil {
                    w.aircraft.step(dt: h, c: w.controls, terrain: terrain, wind: env.wind(at: w.aircraft.pos, terrain: terrain), rollMu: site.rollMu)
                }
                acc -= h
            }
            touchQuiet -= dt
            if aircraft.touchImpact > 0.3 && !aircraft.crashed && touchQuiet <= 0 {
                let slide = length(V3(aircraft.vel.x, 0, aircraft.vel.z))
                sound.touch(aircraft.touchImpact / 2.5, ground: aircraft.touchWater ? 5 : terrain.groundKind(aircraft.pos.x, aircraft.pos.z),
                            wheel: aircraft.touchWheel, slide: slide, mass: aircraft.spec.mass, pan: sound.state.pan)
                touchQuiet = 0.12
            }
            aircraft.touchImpact = 0
            let sdt = dt * timeScale
            if sdt > 0 { climb += ((aircraft.pos.y - lastY) / sdt - climb) * min(1, dt * 4); lastY = aircraft.pos.y }
            postStep(sdt)
        }
        let before = aircraft.renderPos
        aircraft.updateRenderPose(ahead: paused || simHeld || aircraft.crashed || Game.noInterp ? 0 : acc)
        // --perf: how much simulated time this frame's picture advanced by
        let sp = length(aircraft.vel)
        if sp > 3 { advanceMs.append(length(aircraft.renderPos - before) / sp * 1000) }
        updateFormation(dt: dt, realDt: realDt)
        updateCamera(dt)
        updateSound()
        messageTimer -= dt
        hudTimer -= dt
        if hudTimer <= 0 { hudTimer = 0.08; updateHUD() }
    }

    private func postStep(_ dt: Float) {
        let p = aircraft.pos
        if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite || !terrain.contains(p) || p.y > 3000 {
            say("Out of range — aircraft reset"); resetAircraft(); return
        }
        if !aircraft.crashed {
            for t in terrain.trees {
                let dx = p.x - t.p.x, dz = p.z - t.p.z
                if abs(dx) < 6 && abs(dz) < 6 && dx * dx + dz * dz < pow(t.h * 0.3, 2) && p.y < t.p.y + t.h && p.y > t.p.y {
                    hitFoliage(at: p, color: V3(site.pal.bush.x, site.pal.bush.y, site.pal.bush.z), woody: true)
                    aircraft.crashed = true; aircraft.crashImpact = length(aircraft.vel); aircraft.vel *= 0.25
                    break
                }
            }
        }
        if !aircraft.crashed {
            let eyePos = terrain.pilotPos + V3(0, site.eyeHeight, 0)
            for o in site.obstacles {
                let c = Panoramas.position(o, north: site.north)
                let dx = p.x - c.x, dz = p.z - c.y
                let above = p.y - terrain.height(c.x, c.y)
                if o.height > 3, let mask = panoMask {
                    // The stand-in shape only says how far away the tree is. What is solid is decided by the picture:
                    // the model hits where it is in front of the tree as the pilot sees it. Gaps between crowns, the
                    // sky beside a pointed top and the air above a hedge are open, and a top that reaches higher
                    // than the stand-in is still solid.
                    let r = o.radius * 0.75
                    guard above >= 0, above <= o.height * 1.6, dx * dx + dz * dz < r * r else { continue }
                    if !mask.isSolid(p - eyePos, north: site.north, horizon: site.horizon) { continue }
                } else {
                    let rs = Panoramas.solidRadius(o, at: above)
                    guard rs > 0 && dx * dx + dz * dz < rs * rs else { continue }
                }
                let col = panoMask?.color(p - eyePos, north: site.north, horizon: site.horizon) ?? V3(0.25, 0.35, 0.15)
                hitFoliage(at: p, color: col, woody: o.height > 3)
                aircraft.crashed = true; aircraft.crashImpact = length(aircraft.vel); aircraft.vel *= 0.2
                break
            }
        }
        if !aircraft.crashed && terrain.strikes(p, reach: 0.3 * aircraft.spec.span) {
            // flown into something built: a gate post, a wall, a tower
            aircraft.crashed = true; aircraft.crashImpact = length(aircraft.vel); aircraft.vel *= 0.1
        }
        updateRace(dt: dt)
        if terrain.overWater(aircraft.pos) {
            // ditched: the model stops and floats
            if !aircraft.crashed { aircraft.crashed = true; aircraft.crashImpact = max(length(aircraft.vel) * 0.6, 4); say("Splash!") }
            aircraft.pos.y = max(aircraft.pos.y, (site.waterLevel ?? 0) - 0.06)
            aircraft.vel = V3(aircraft.vel.x * 0.92, max(aircraft.vel.y, 0), aircraft.vel.z * 0.92)
            aircraft.omega *= 0.9
        }
        if aircraft.crashed && !wasCrashed { breakUp() }
        wasCrashed = aircraft.crashed
        updateEffects(dt)
        if aircraft.crashed {
            crashTimer += dt
            if crashTimer > 3.5 { if !joinUp(quiet: true) { resetAircraft() } }
        }
        if challenge {
            if score < balloons.count { challengeTime += dt }
            let r = 0.7 + aircraft.spec.span * 0.4
            for i in balloons.indices where balloons[i].alive {
                balloons[i].pos.y += sin(env.time * 1.3 + Float(i)) * 0.15 * dt
                if distance(balloons[i].pos, p) < r {
                    balloons[i].alive = false; score += 1
                    if score == balloons.count { say(String(format: "All balloons popped in %.1f s!  (B for a new round)", challengeTime), 6) }
                    else { say("Pop!  \(score)/\(balloons.count)", 1.2) }
                }
            }
        }
    }

    /// Called once when the aircraft crashes: parts break off, dust flies, and there is a thud.
    /// The model flies into a tree, hedge or other photographed object: branches crack, and leaves and twigs in the
    /// colour of whatever it hit burst out and flutter down.
    private func hitFoliage(at p: V3, color: V3, woody: Bool) {
        let speed = length(aircraft.vel)
        let sev = clampf(speed / 14, 0.3, 1)
        sound.branches(sev, woody: woody, pan: sound.state.pan)
        guard woody else { return }
        let dirv = speed > 0.5 ? aircraft.vel / speed : V3(0, 0, -1)
        // torn leaves show their pale undersides and catch the light: lighter than the tree they came from
        let color = simd_clamp(color * 1.1 + V3(0.07, 0.1, 0.03), V3(repeating: 0.06), V3(repeating: 0.8))
        for _ in 0..<Int(60 + 70 * sev) {
            let shade = rng.range(0.65, 1.25)
            let c = simd_clamp(color * shade + V3(rng.range(-0.04, 0.04), rng.range(-0.03, 0.05), rng.range(-0.03, 0.02)), V3(repeating: 0.02), V3(repeating: 1))
            let size = rng.range(0.05, 0.12) * max(aircraft.spec.span, 0.6)
            particles.append(Particle(pos: p + V3(rng.range(-0.4, 0.4), rng.range(-0.3, 0.3), rng.range(-0.4, 0.4)) * max(aircraft.spec.span, 0.6),
                                      vel: dirv * speed * rng.range(0.05, 0.45) + V3(rng.range(-3, 3), rng.range(-1, 3.5), rng.range(-3, 3)) * sev,
                                      age: 0, life: rng.range(1.6, 3.6), size: size, color: V4(c.x, c.y, c.z, 0.95), fall: rng.range(1.2, 3.2)))
        }
        // a puff of torn foliage that hangs for a moment, so the hit shows from far away
        for _ in 0..<8 {
            particles.append(Particle(pos: p + V3(rng.range(-0.3, 0.3), rng.range(-0.2, 0.2), rng.range(-0.3, 0.3)), vel: dirv * speed * 0.12 + V3(rng.range(-1, 1), rng.range(0, 1), rng.range(-1, 1)),
                                      age: 0, life: rng.range(0.9, 1.7), size: rng.range(0.14, 0.24) * max(aircraft.spec.span, 0.6), color: V4(color.x, color.y, color.z, 0.26)))
        }
    }

    private func breakUp() {
        let ac = aircraft
        let sev = clampf(ac.crashImpact / 10, 0.25, 1)
        for (i, part) in ac.spec.parts.enumerated() where i > 0 {
            var animated = true
            if case .fixed = part.anim { animated = false }
            guard (animated || part.detach) && part.blur != 2 else { continue }
            if rng.next() > 0.3 + 0.7 * sev { continue }
            let origin = animated ? part.pivot : part.center
            let v = ac.vel * 0.6 + ac.q.act(cross(ac.omega, origin)) + V3(rng.range(-2.5, 2.5), rng.range(1, 4.5), rng.range(-2.5, 2.5)) * sev
            debris.append(Debris(part: i, pos: ac.pos + ac.q.act(origin), q: ac.q, vel: v,
                                 omega: V3(rng.range(-9, 9), rng.range(-9, 9), rng.range(-9, 9)), offset: animated ? .zero : -part.center))
            ac.detached.insert(i)
        }
        let ground = V3(ac.pos.x, max(terrain.height(ac.pos.x, ac.pos.z), site.waterLevel ?? -1e9) + 0.1, ac.pos.z)
        let wet = site.waterLevel.map { terrain.height(ac.pos.x, ac.pos.z) < $0 } ?? false
        sound.crash(sev, water: wet, pan: sound.state.pan)
        let dust: V4 = wet ? rgb(0.9, 0.95, 1.0) : site.pal.dust
        for _ in 0..<Int(10 + 22 * sev) {
            particles.append(Particle(pos: ground + V3(rng.range(-0.3, 0.3), 0, rng.range(-0.3, 0.3)),
                                      vel: V3(rng.range(-2.5, 2.5), rng.range(0.5, 3), rng.range(-2.5, 2.5)) * sev + ac.vel * 0.15,
                                      age: 0, life: rng.range(1.2, 2.4), size: rng.range(0.1, 0.22), color: V4(dust.x, dust.y, dust.z, 0.32)))
        }
    }

    private func updateEffects(_ dt: Float) {
        // tumbling wreckage
        for i in debris.indices {
            var d = debris[i]
            d.vel.y -= gravity * dt
            d.vel *= 1 - min(0.6 * dt, 1)
            d.pos += d.vel * dt
            let g = max(terrain.height(d.pos.x, d.pos.z), site.waterLevel ?? -1e9) + 0.03
            if d.pos.y < g {
                d.pos.y = g
                d.vel = V3(d.vel.x * 0.55, abs(d.vel.y) * 0.3, d.vel.z * 0.55)
                d.omega *= 0.5
                if length(d.vel) < 0.4 { d.vel = .zero; d.omega = .zero }
            }
            let w = length(d.omega)
            if w > 0.01 { d.q = simd_normalize(d.q * simd_quatf(angle: w * dt, axis: d.omega / w)) }
            debris[i] = d
        }
        // smoke trail
        if smokeOn && !aircraft.crashed && aircraft.power > 0.08 {
            smokeAcc += dt * 70
            let wind = env.windVec
            while smokeAcc >= 1 {
                smokeAcc -= 1
                let p = aircraft.pos + aircraft.q.act(aircraft.spec.smokePos) - aircraft.vel * (rng.next() * dt)
                particles.append(Particle(pos: p, vel: wind * 0.8 + aircraft.vel * 0.08 + V3(rng.range(-0.4, 0.4), rng.range(-0.2, 0.5), rng.range(-0.4, 0.4)),
                                          age: 0, life: rng.range(3.5, 5), size: rng.range(0.12, 0.2), color: V4(0.96, 0.96, 0.97, 0.5)))
            }
        }
        for i in particles.indices {
            particles[i].age += dt
            if particles[i].fall > 0 {
                // a leaf: falls, soon at its own slow pace, and sideslips to and fro on the way down
                particles[i].vel.y -= gravity * 0.5 * dt
                particles[i].vel *= 1 - min(2.2 * dt, 1)
                particles[i].vel.y = max(particles[i].vel.y, -particles[i].fall)
                let ph = particles[i].age * 7 + particles[i].size * 400
                particles[i].vel.x += sin(ph) * 2.2 * dt; particles[i].vel.z += cos(ph * 0.8) * 2.2 * dt
                if particles[i].pos.y < terrain.height(particles[i].pos.x, particles[i].pos.z) + 0.02 { particles[i].vel = .zero }
            }
            particles[i].vel *= 1 - min(0.8 * dt, 1)
            particles[i].pos += particles[i].vel * dt
        }
        particles.removeAll { $0.age >= $0.life }
        if particles.count > 900 { particles.removeFirst(particles.count - 900) }
    }

    func snapCamera() { camSnap = true }
    func lastYReset() { lastY = aircraft.pos.y; climb = 0 }

    private func updateCamera(_ dt: Float) {
        let p = aircraft.renderPos, spec = aircraft.spec
        let rq = aircraft.renderQ
        switch cameraMode {
        case 0:
            eye = terrain.pilotPos + V3(0, site.panorama != nil ? site.eyeHeight : 1.7, 0)
            if camSnap { camTarget = p }
            camTarget += (p - camTarget) * min(1, dt * 14)
            let d = max(distance(eye, p), 1)
            let auto = 2 * atan(spec.span * 7 / (2 * d))
            var want: Float
            switch zoomMode {
            case 0: want = clampf(auto, 4 * deg, 55 * deg)
            case 1:
                let el = asin(clampf((p.y - eye.y) / d, -1, 1))
                want = clampf(max(auto, 2 * (el + 3 * deg) * 1.08), 4 * deg, 105 * deg)
            default: want = 50 * deg
            }
            fov = camSnap ? want : fov + (want - fov) * min(1, dt * 3.5)
            target = camTarget; upVec = V3(0, 1, 0)
        case 1:
            var back = rq.act(V3(0, 0, 1)); back.y = 0
            back = length(back) > 0.05 ? normalize(back) : V3(0, 0, 1)
            var want = p + back * (spec.span * 2.2 + 1.5) + V3(0, spec.span * 0.5 + 0.4, 0)
            want.y = max(want.y, terrain.height(want.x, want.z) + 0.4)
            eye = camSnap ? want : eye + (want - eye) * min(1, dt * 5)
            target = p; upVec = V3(0, 1, 0); fov = 60 * deg
        default:
            eye = p + rq.act(spec.eyeOffset)
            target = eye + rq.act(V3(0, 0, -1)); upVec = rq.act(V3(0, 1, 0)); fov = 85 * deg
        }
        if let c = closeup {
            eye = p + c * max(spec.span, 0.6); target = p; upVec = V3(0, 1, 0); fov = 32 * deg
        }
        if let v = fixedView {
            let g = terrain.pilotPos.y
            eye = v.eye + V3(0, g, 0); target = v.target + V3(0, g, 0); upVec = V3(0, 1, 0); fov = 58 * deg
        }
        camSnap = false
    }

    private func updateSound() {
        let spec = aircraft.spec
        let rel = aircraft.pos - eye
        let d = max(length(rel), 0.5)
        let onboard = cameraMode == 2
        var st = SoundState()
        st.doppler = cameraMode == 0 ? 343 / (343 + dot(aircraft.vel, rel / d)) : 1
        let lv = aircraft.power
        switch spec.kind {
        case .helicopter:
            st.engine = 4
            st.shaftHz = spec.soundBase / 2 * aircraft.levels[0]
            st.blades = Float(max(spec.blades, 2))
            st.power = clampf(abs(2 * controls.throttle - 1) * 0.8 + 0.15, 0, 1)
            st.running = aircraft.levels[0] > 0.05 ? min(aircraft.levels[0], 1) : 0
        case .multirotor:
            st.engine = 5
            st.shaftHz = spec.soundBase
            st.power = lv; st.running = lv > 0.01 ? 1 : 0
            st.motors = SIMD4(aircraft.levels[0], aircraft.levels[1], aircraft.levels[2], aircraft.levels[3])
        case .airplane:
            st.engine = spec.engineSound
            st.blades = Float(spec.blades); st.cylinders = Float(spec.cylinders); st.radial = spec.radial
            // piston and turbine engines idle; electric motors stop
            let idles = spec.engineSound != 0 && !aircraft.crashed
            let rpm = idles ? max(lv, 0.24) : lv
            st.shaftHz = spec.soundBase / Float(max(spec.blades, 1)) * (0.25 + 0.75 * rpm)
            // the propeller takes seconds to spin down, but the motor goes quiet the moment the throttle is closed
            st.power = lv * clampf(0.3 + 1.4 * aircraft.engineLoad, 0, 1)
            st.running = idles ? 1 : (lv > 0.01 ? 1 : 0)
        }
        if aircraft.crashed { st.running = 0; st.power = 0 }       // a wrecked model is silent
        st.shaftHz *= st.doppler
        // distance: inverse-distance loudness, and the air soaks up the highs
        let size = max(spec.span, 0.6)
        st.gain = onboard ? 0.8 : min(1, (3 + 2.5 * size) / (d + 2))
        st.muffle = onboard ? 0 : clampf(d / 320, 0, 1)
        var fwd = target - eye; fwd.y = 0
        if length(fwd) > 0.001 && !onboard {
            fwd = normalize(fwd)
            let right = V3(-fwd.z, 0, fwd.x)
            st.pan = clampf(dot(rel / d, right) * 1.6, -1, 1)
        }
        if !onboard {
            // the path by way of the ground is a little longer than the direct one
            let ear = max(eye.y - terrain.height(eye.x, eye.z), 0.3), src = max(aircraft.pos.y - terrain.height(aircraft.pos.x, aircraft.pos.z), 0.05)
            let flat = max(length(V3(rel.x, 0, rel.z)), 0.5)
            let direct = sqrt(flat * flat + (src - ear) * (src - ear)), bounced = sqrt(flat * flat + (src + ear) * (src + ear))
            st.reflect = (bounced - direct) / 343
            st.reflectGain = 0.4 * direct / bounced * (site.waterLevel != nil ? 1.2 : 1)
        }
        st.airspeed = aircraft.airspeed
        st.groundRoll = aircraft.onGround && !aircraft.crashed ? length(V3(aircraft.vel.x, 0, aircraft.vel.z)) : 0
        st.windSpeed = env.windSpeed
        st.ambience = site.panorama != nil ? siteAmbience : siteAmbience.at(time: timeOfDay)
        st.paused = paused || simHeld
        sound.musicOn = simHeld && musicEnabled
        sound.state = st
    }

    private func updateHUD() {
        var s = HUDState()
        let spec = aircraft.spec
        s.aircraft = spec.name; s.site = site.name; s.blurb = spec.blurb
        s.alt = aircraft.pos.y - terrain.height(aircraft.pos.x, aircraft.pos.z) - aircraft.restHeight
        s.speed = aircraft.airspeed
        s.dist = distance(aircraft.pos, terrain.pilotPos)
        s.climb = climb
        s.throttle = controls.throttle
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        s.wind = env.windSpeed < 0.1 ? "Calm" : String(format: "%@ %.0f m/s", dirs[Int((env.windFrom + 22.5) / 45) % 8], env.windSpeed)
        s.camera = Game.cameraNames[cameraMode] + (cameraMode == 0 ? " · " + Game.zoomNames[zoomMode] : "")
        s.mode = spec.modes.count > 1 ? spec.modes[flightMode] : ""
        s.input = autopilotOn ? "Demo pilot" : input.source
        s.time = (site.panorama != nil ? (photoLight == 0 ? "Photo site" : Game.photoLightNames[photoLight]) : Game.timeNames[timeOfDay]) + (timeScale < 1 ? String(format: " · %.0f%% speed", timeScale * 100) : "")
        if challenge { s.score = String(format: "Balloons %d/%d   %.1f s", score, balloons.count, challengeTime) }
        else if !terrain.gates.isEmpty { s.score = raceStatus }
        if aircraft.crashed { s.message = "CRASHED" }
        else if paused { s.message = "PAUSED" }
        else if messageTimer > 0 { s.message = message }
        let tY = controls.throttle * 2 - 1, eY = -controls.elevator
        switch input.settings.stickMode {
        case 1: s.lx = controls.rudder; s.ly = eY; s.rx = controls.aileron; s.ry = tY; s.leftLabel = "ELE / RUD"; s.rightLabel = "THR / AIL"
        case 3: s.lx = controls.aileron; s.ly = eY; s.rx = controls.rudder; s.ry = tY; s.leftLabel = "ELE / AIL"; s.rightLabel = "THR / RUD"
        case 4: s.lx = controls.aileron; s.ly = tY; s.rx = controls.rudder; s.ry = eY; s.leftLabel = "THR / AIL"; s.rightLabel = "ELE / RUD"
        default: s.lx = controls.rudder; s.ly = tY; s.rx = controls.aileron; s.ry = eY
        }
        s.rates = input.lowRates ? String(format: "Low %.0f%%", input.lowRateInUse * 100) : "High"
        if pitchTrim != 0 { s.rates += String(format: " rates · Trim %+d", pitchTrim) } else { s.rates += " rates" }
        var cfg: [String] = []
        if spec.hasFlaps { cfg.append(["Flaps up", "Flaps ½", "Flaps full"][Int(flapSetting * 2)]) }
        if spec.hasRetracts { cfg.append(gearUp ? "Gear up" : "Gear down") }
        if spec.kind == .airplane && !unlimitedBattery { cfg.append(String(format: spec.burnsFuel ? "Fuel %.0f%%" : "Battery %.0f%%", aircraft.battery * 100)) }
        if spec.kind == .airplane && aircraft.wingStall > 0.35 && !aircraft.onGround { cfg.append("STALL") }
        if spec.kind == .helicopter && aircraft.vortexRing > 0.3 { cfg.append("VORTEX RING") }
        if controls.brake > 0.5 && aircraft.onGround { cfg.append("Brakes") }
        if spec.kind == .helicopter { cfg.append(String(format: "Rotor %.0f%%%@", aircraft.levels[0] * 100, hold ? " HOLD" : "")) }
        if smokeOn { cfg.append("Smoke") }
        s.config = cfg.joined(separator: " · ")
        s.fps = fps
        fillFormationHUD(&s)
        hud.s = s
    }
}

