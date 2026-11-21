import Foundation
import simd
import CoreGraphics
import ImageIO

/// A photographed object (tree, building) approximated as an upright cylinder you can crash into.
/// The bearing is measured in the photo: 0° is the image centre, positive to the right.
struct PanoObstacle: Codable {
    var bearing: Float
    var distance: Float
    var radius: Float
    var height: Float
}

/// Optional sidecar file "<image name>.json" next to a panorama.
struct PanoMeta: Codable {
    var name: String?
    var north: Float?        // degrees the photo is rotated about the vertical axis
    var horizon: Float?      // degrees the photo's horizon sits above the image centre line
    var eyeHeight: Float?    // camera height above the ground when the photo was taken (m)
    var slope: Float?        // the ground is a hillside this steep (degrees) ...
    var uphill: Float?       // ... rising toward this bearing in the photo
    var windFrom: Float?
    var windSpeed: Float?
    var startX: Float?       // where aircraft start, metres right of / in front of (negative) the camera
    var startZ: Float?
    var startHeading: Float? // compass degrees after rotation: 0 = away from the camera, 90 = to the right
    var obstacles: [PanoObstacle]?
    var category: String?    // Fields, Mountains, Desert, Water, Winter, Airfields
    var info: String?
    var difficulty: Int?
}

/// Photo sites: a 360° equirectangular photograph is the whole scenery. The aircraft flies
/// over an invisible flat ground plane that only receives its shadow.
enum Panoramas {
    static let extensions = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]

    static var userDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FlightCore/Panoramas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A folder of the user's own choosing that is searched for panoramas as well (Flying Site ▸ Choose Panoramas Folder…).
    static var customDir: URL? {
        get {
            guard let p = UserDefaults.standard.string(forKey: "panoramaFolder"), !p.isEmpty else { return nil }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue ? URL(fileURLWithPath: p, isDirectory: true) : nil
        }
        set { UserDefaults.standard.set(newValue?.path ?? "", forKey: "panoramaFolder") }
    }
    /// Where new photos go and what "Show Panoramas Folder" opens.
    static var activeDir: URL { customDir ?? userDir }

    static func site(for url: URL) -> SiteSpec {
        let pretty = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        var s = SiteSpec(name: pretty.capitalized, style: 0, seed: 1, runwayLen: 100, runwayWid: 0, runwayType: 3, flatCenterZ: 0, flatHalfZ: 100,
                         treeCount: 0, windFrom: 90, windSpeed: 1, turbulence: 0.2, rollMu: 0.05, cloud: 0, fog: 0)
        s.panorama = url
        s.key = url.deletingPathExtension().lastPathComponent.lowercased()
        s.startZ = -14
        var meta = presets[url.deletingPathExtension().lastPathComponent.lowercased()]
        if let d = try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json")),
           var m = try? JSONDecoder().decode(PanoMeta.self, from: d) {
            m.category = m.category ?? meta?.category; m.info = m.info ?? meta?.info; m.difficulty = m.difficulty ?? meta?.difficulty
            meta = m
        }
        if let m = meta {
            if let n = m.name { s.name = n }
            s.north = m.north ?? 0; s.horizon = m.horizon ?? 0; s.eyeHeight = m.eyeHeight ?? 1.7
            s.slope = m.slope ?? 0; s.uphill = m.uphill ?? 0
            s.windFrom = m.windFrom ?? s.windFrom; s.windSpeed = m.windSpeed ?? s.windSpeed
            s.startX = m.startX ?? s.startX; s.startZ = m.startZ ?? s.startZ; s.startHeading = m.startHeading ?? s.startHeading
            s.obstacles = m.obstacles ?? []
            s.category = m.category ?? s.category; s.info = m.info ?? ""; s.difficulty = m.difficulty ?? s.difficulty
        }
        s.name = "📷 " + s.name
        return s
    }

    static func discover() -> [SiteSpec] {
        var dirs = [customDir, userDir].compactMap { $0 } + [URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Panoramas")]
        // a chosen folder may hold the photos one level down, as an unzipped download does
        if let c = customDir, let subs = try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            dirs.insert(contentsOf: subs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.path < $1.path }, at: 1)
        }
        dirs.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Panoramas"))
        var seen = Set<String>(), out: [SiteSpec] = []
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where extensions.contains(f.pathExtension.lowercased()) {
                if seen.insert(f.lastPathComponent.lowercased()).inserted { out.append(site(for: f)) }      // the same photo in two folders is one site
            }
        }
        return out
    }

    static func save(_ s: SiteSpec) {
        guard let url = s.panorama else { return }
        let name = s.name.hasPrefix("📷 ") ? String(s.name.dropFirst(2)) : s.name
        let m = PanoMeta(name: name, north: s.north, horizon: s.horizon, eyeHeight: s.eyeHeight, slope: s.slope == 0 ? nil : s.slope, uphill: s.slope == 0 ? nil : s.uphill, windFrom: s.windFrom, windSpeed: s.windSpeed,
                         startX: s.startX, startZ: s.startZ, startHeading: s.startHeading, obstacles: s.obstacles.isEmpty ? nil : s.obstacles,
                         category: s.category, info: s.info.isEmpty ? nil : s.info, difficulty: s.difficulty)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(m) { try? d.write(to: url.deletingPathExtension().appendingPathExtension("json")) }
    }

    /// World position (x, z) of an obstacle for the site's current rotation.
    static func position(_ o: PanoObstacle, north: Float) -> SIMD2<Float> {
        let a = (o.bearing - north) * deg
        return SIMD2(sin(a), -cos(a)) * o.distance
    }

    private static func ring(_ from: Float, _ to: Float, _ n: Int, _ d: Float, _ r: Float, _ h: Float) -> [PanoObstacle] {
        (0..<n).map { PanoObstacle(bearing: from + (to - from) * (Float($0) + 0.5) / Float(n), distance: d, radius: r, height: h) }
    }

    /// Hand-tuned settings for the Poly Haven panoramas suggested in the README, keyed by file name.
    /// Distances are estimated from the photos, so treat the obstacles as approximate.
    static let presets: [String: PanoMeta] = [
        "alps_field": meta("Alps Field", north: 0, wind: (270, 2), start: (-22, -24, 90), category: "Mountains", difficulty: 2,
                           info: "Mown grass in a broad alpine valley with wooded mountains all around. Open in every direction and usually calm."),
        "belfast_open_field": meta("Belfast Open Field", north: 20, wind: (90, 3), start: (-18, -20, 90), category: "Fields", difficulty: 2,
                                   info: "Rough grass on a hillside under an overcast sky. A clump of trees stands to the left and a wire fence crosses the field ahead.",
            obstacles: ring(-128, -64, 4, 60, 9, 28) + ring(-165, -130, 2, 90, 12, 16) + [PanoObstacle(bearing: 49, distance: 100, radius: 5, height: 13), PanoObstacle(bearing: 72, distance: 110, radius: 12, height: 17)]),
        "derelict_airfield_01": meta("Derelict Airfield — Runway", north: -90, wind: (270, 2), start: (12, -4, 270), category: "Airfields", difficulty: 2,
                                     info: "The cracked asphalt runway of an abandoned airfield, running left to right in front of you, with a meadow beyond and trees at the far end.",
            obstacles: ring(-28, 18, 3, 50, 9, 14) + [PanoObstacle(bearing: -146, distance: 27, radius: 6, height: 7.5), PanoObstacle(bearing: -90, distance: 70, radius: 8, height: 12)]),
        "derelict_airfield_02": meta("Derelict Airfield — Apron", north: -100, wind: (0, 1), start: (-8, -12, 90), category: "Airfields", difficulty: 4,
                                     info: "A concrete apron hemmed in by poplars and overgrown buildings. Sheltered and calm, but tight: good for helicopters and slow flyers.",
                                     obstacles: [PanoObstacle(bearing: -52, distance: 30, radius: 5, height: 13)] + ring(-35, 35, 3, 48, 10, 15) + ring(40, 122, 4, 42, 8, 8)
                                         + ring(-173, -135, 3, 36, 3, 24) + ring(126, 178, 4, 36, 3, 27)),
        "dry_cracked_lake": meta("Dry Cracked Lake", north: 100, wind: (0, 2), start: (-5, -9, 15), category: "Desert", difficulty: 3,
                                 info: "The cracked bed of a dried-out lake ringed by a bank and thorn trees. Flat and hard underfoot; take off toward the far shore.",
                                 obstacles: ring(-86, 36, 5, 40, 9, 14) + [PanoObstacle(bearing: -167, distance: 60, radius: 8, height: 10), PanoObstacle(bearing: 171, distance: 60, radius: 6, height: 10)]),
        "autumn_field": meta("Autumn Field", north: -60, wind: (300, 3), start: (-15, -18, 90), category: "Fields", difficulty: 1,
                             info: "Tall autumn grass under a clear sky, with nothing but a single bush between you and the horizon. Wide open and forgiving.",
            obstacles: [PanoObstacle(bearing: 71, distance: 24, radius: 5, height: 6.5)]),
        "dry_hay_field": meta("Dry Hay Field", north: 140, wind: (250, 3), start: (-15, -18, 90), category: "Fields", difficulty: 2,
                              info: "A mown hay field under towering summer clouds, wide open ahead. A tall hedge runs along the left edge and old fruit trees stand close behind you.",
            obstacles: ring(20, 105, 5, 45, 7, 11) + [PanoObstacle(bearing: -116, distance: 25, radius: 4, height: 10), PanoObstacle(bearing: -97, distance: 11, radius: 2.5, height: 6), PanoObstacle(bearing: -6, distance: 25, radius: 4, height: 6)]),
        "farm_field": meta("Farm Field", north: 0, wind: (180, 2), start: (-4, -10, 0), category: "Fields", difficulty: 2,
                           info: "Freshly planted rows of dark earth running straight away from you to distant hills. Take off along the furrows.",
            obstacles: [PanoObstacle(bearing: 37, distance: 60, radius: 4, height: 9)]),
        "hochsal_field": meta("Hochsal Field", north: 0, wind: (90, 2), start: (-12, -22, 90), category: "Fields", difficulty: 2,
                              info: "A farm track curving through bright green pasture on a hilltop, with low evening sun and a far view across the valley.",
            obstacles: [PanoObstacle(bearing: 49.5, distance: 42, radius: 2.5, height: 10)]),
        "limpopo_golf_course": meta("Limpopo Golf Course", north: -30, wind: (60, 2), start: (-6, -7, 50), category: "Water", difficulty: 3,
                                    info: "A golf-course lawn on the bank of a still pond under streaked cirrus. Take off across the water; thorn trees crowd the lawn behind you and to the left.",
            obstacles: [PanoObstacle(bearing: -167, distance: 15, radius: 4.5, height: 7.2), PanoObstacle(bearing: -155, distance: 28, radius: 3, height: 6), PanoObstacle(bearing: -143, distance: 25, radius: 3, height: 7.5), PanoObstacle(bearing: -129, distance: 9, radius: 1.2, height: 3), PanoObstacle(bearing: -117, distance: 10, radius: 1.2, height: 3.2), PanoObstacle(bearing: -96, distance: 12, radius: 1.9, height: 3.8), PanoObstacle(bearing: -75, distance: 22, radius: 2.9, height: 5.8), PanoObstacle(bearing: -31, distance: 6.2, radius: 0.5, height: 0.6), PanoObstacle(bearing: 123, distance: 8.8, radius: 0.5, height: 0.8), PanoObstacle(bearing: 141, distance: 50, radius: 4, height: 4)]),
        "snow_field": meta("Snow Field", north: 0, wind: (20, 4), start: (-15, -18, 90), category: "Winter", difficulty: 3,
                           info: "A featureless snow-covered plain under a heavy grey sky. Nothing to hit, and almost nothing to judge height or distance by."),
        "suburban_football_field": meta("Suburban Football Field", north: 0, wind: (240, 3), start: (-18, -16, 90), category: "Fields", difficulty: 2,
                                        info: "A village football pitch on a grey day, with houses along one side. Short, even grass and painted lines to line up on.",
            obstacles: [PanoObstacle(bearing: 172, distance: 14, radius: 1.5, height: 2.4), PanoObstacle(bearing: 180, distance: 14, radius: 1.5, height: 2.4), PanoObstacle(bearing: -174, distance: 14.5, radius: 1.5, height: 2.4), PanoObstacle(bearing: -7.5, distance: 32, radius: 3.5, height: 2.4)] + ring(-170, -60, 6, 75, 8, 9)),
        "wildflower_field": meta("Wildflower Field", north: -57, wind: (0, 1), start: (0, -8, 0), category: "Fields", difficulty: 2,
                                 info: "A grassy track between wildflower strips at dusk, with fruit trees scattered around. Take off along the track.",
            obstacles: [PanoObstacle(bearing: -165, distance: 40, radius: 7, height: 13), PanoObstacle(bearing: -141, distance: 45, radius: 5, height: 10), PanoObstacle(bearing: 90, distance: 26, radius: 4, height: 9), PanoObstacle(bearing: 113, distance: 28, radius: 5, height: 8), PanoObstacle(bearing: 157, distance: 11.5, radius: 2.5, height: 4.5), PanoObstacle(bearing: 53, distance: 70, radius: 6, height: 8)]),
        "rural_asphalt_road": meta("Rural Asphalt Road", north: -8, wind: (200, 3), start: (0, -7, 0), category: "Fields", difficulty: 3,
                                   info: "A quiet tarmac lane between meadows under a bright summer sky. Take off straight down the road; a row of trees stands to the right and scrub to the left.",
            obstacles: ring(45, 100, 4, 85, 8, 14) + ring(-125, -65, 4, 70, 6, 6) + ring(105, 140, 3, 60, 8, 14) + ring(155, 180, 2, 70, 8, 12) + ring(-180, -128, 4, 70, 8, 12)),
        "goegap_road": meta("Goegap Road", north: -13, wind: (40, 2), start: (0, -6, 0), category: "Desert", difficulty: 2,
                            info: "An empty road through a flowering semi-desert, with bare rock hills on both sides and the sun low ahead. The road is the runway; everything beside it is sand and scrub."),
        "grasslands_sunset": meta("Grasslands Sunset", north: 0, wind: (300, 2), start: (-18, -20, 90), category: "Fields", difficulty: 1,
                                  info: "A huge, level pasture at sunset under a sky full of pink cloud. Nothing nearer than the distant tree line: as open and forgiving as a field can be.",
            obstacles: ring(-128, -62, 4, 160, 14, 14)),
        "snowy_hillside_02": meta("Snowy Hillside", north: 0, wind: (270, 3), start: (-15, -18, 310), category: "Winter", difficulty: 2,
                                  info: "A snow-dusted hillside under a heavy grey sky, with a village in the valley below. The slope is steep: take off across it. One bare tree stands to the right.",
            obstacles: [PanoObstacle(bearing: 48, distance: 28, radius: 5, height: 17)] + ring(140, 165, 2, 40, 6, 8), slope: (8, -140)),
        "poolbeg": meta("Poolbeg Dunes", north: 0, wind: (0, 5), start: (-12, -16, 90), category: "Water", difficulty: 2,
                        info: "Marram-grass dunes behind a wide bay, with striped power-station chimneys on the skyline to the left. A steady breeze comes in off the sea in front of you.",
            obstacles: ring(146, 180, 3, 55, 8, 15)),
        "horn-koppe_spring": meta("Horn-Koppe Meadow", north: 0, wind: (240, 2), start: (-18, -20, 90), category: "Fields", difficulty: 1,
                                  info: "A vast mountain meadow in spring with wooded ridges far away on the horizon. Nothing to hit in any direction: an ideal place for a first flight."),
        "dreifaltigkeitsberg": meta("Dreifaltigkeitsberg", north: 36, wind: (200, 2), start: (0, -7, 0), category: "Fields", difficulty: 2,
                                    info: "A mown track across a hilltop meadow on a cloudless summer day, with woods along the far edge. Take off along the track.",
            obstacles: ring(62, 180, 7, 45, 9, 16) + ring(-180, -150, 2, 70, 10, 16) + ring(22, 60, 3, 100, 10, 16), slope: (3, -150)),
        "immenstadter_horn": meta("Immenstädter Horn", north: 120, wind: (250, 4), start: (-4, -8, 335), category: "Mountains", difficulty: 3,
                                  info: "A rough alpine pasture high on a ridge, ringed by spruce. The ground drops into a gully in front of you, with the valley and the next range beyond: launch out over the drop.",
            obstacles: [PanoObstacle(bearing: -150, distance: 16, radius: 5, height: 22), PanoObstacle(bearing: -165, distance: 22, radius: 4, height: 18)] + ring(-125, -70, 3, 70, 8, 18) + ring(-45, 15, 5, 35, 5, 22) + ring(127, 162, 3, 35, 4, 13), slope: (3.5, -85)),
        "hausdorf_meadow": meta("Hausdorf Meadow", north: 30, wind: (220, 2), start: (-15, -18, 70), category: "Mountains", difficulty: 2,
                                info: "A broad upland meadow sloping gently down to a village, below wooded hills under a mackerel sky. Bare trees close in on the left; everywhere else it is open.",
            obstacles: ring(-150, -60, 5, 45, 8, 18) + ring(-60, -38, 2, 60, 6, 12), slope: (4, -170)),
        "lago_disola": meta("Lago d'Isola", north: 80, wind: (180, 3), start: (-8, -14, 90), category: "Mountains", difficulty: 4,
                            info: "The rocky shore of a frozen reservoir in a high alpine valley, snow peaks at its head. Fly out over the ice; pines stand right behind your shoulder.",
            obstacles: ring(-130, 10, 7, 18, 5, 20), eye: 4),
        "camdeboo_road": meta("Camdeboo Pass", north: -64, wind: (90, 3), start: (0, -7, 0), category: "Mountains", difficulty: 4,
                              info: "A dirt road climbing between scrub-covered banks toward a gap in the mountains, in the last low sun. Narrow: take off straight up the road.",
            obstacles: [PanoObstacle(bearing: -118, distance: 13, radius: 5, height: 6), PanoObstacle(bearing: -92, distance: 22, radius: 4, height: 5)] + ring(95, 180, 4, 12, 4, 6) + ring(-180, -140, 2, 10, 4, 6), slope: (4, -64)),
        "golden_gate_hills": meta("Golden Gate Highlands", north: -85, wind: (240, 3), start: (-10, -14, 90), category: "Mountains", difficulty: 2,
                                  info: "A level sandstone plateau patched with tussock grass, high in the mountains, with a flat-topped massif across a green valley behind you. Wide open, with nothing to hit."),
        "evening_meadow": meta("Evening Meadow", north: -80, wind: (270, 2), start: (-15, -12, 90), category: "Fields", difficulty: 1,
                               info: "Lush long grass beside a ripening cornfield under a soft cloudy sky. Bushes dot the field edge and an orchard stands behind you; ahead it is wide open.",
            obstacles: ring(0, 135, 6, 45, 8, 12) + ring(-180, -145, 2, 25, 4, 5) + ring(-51, -21, 3, 32, 4, 6) + [PanoObstacle(bearing: -95, distance: 27, radius: 5, height: 6), PanoObstacle(bearing: -6, distance: 30, radius: 7, height: 13)]),
        "steinbach_field": meta("Steinbach Field", north: -35, wind: (240, 2), start: (-15, -18, 90), category: "Fields", difficulty: 1,
                                info: "A freshly mown field at dusk with tramlines running straight away from you and woods on the far side. A tall stand of pines is close behind you.",
            obstacles: ring(-110, -60, 3, 140, 15, 18) + ring(50, 160, 7, 48, 9, 22) + ring(0, 48, 3, 150, 15, 18) + ring(-48, 0, 3, 160, 15, 18)),
        "stierberg_sunrise": meta("Stierberg Sunrise", north: 10, wind: (60, 2), start: (-15, -18, 25), category: "Winter", difficulty: 3,
                                  info: "Crusted snow on a hillside at sunrise, crossed by ski tracks. The field falls away in front of you to frosted woods; spruce stand close behind on the uphill side.",
            obstacles: ring(-150, 0, 9, 55, 9, 15) + ring(62, 165, 7, 32, 5, 13), slope: (5, 140)),
        "countrytrax_midday": meta("Countrytrax Paddock", north: 20, wind: (300, 2), start: (-12, -16, 90), category: "Fields", difficulty: 2,
                                   info: "A flat, sun-baked paddock of short dry grass under a high sun. Gum trees and a wall run along the left; the rest is open and level.",
            obstacles: ring(-133, -20, 6, 65, 10, 14) + [PanoObstacle(bearing: 24, distance: 33, radius: 4, height: 11), PanoObstacle(bearing: 80, distance: 34, radius: 8, height: 13)] + ring(98, 120, 2, 45, 5, 3.5)),
        "spaichingen_hill": meta("Spaichingen Hill", north: -12, wind: (250, 3), start: (12, -20, 297), category: "Mountains", difficulty: 2,
                                 info: "A sloping hay meadow on a hilltop, looking down on a village and across to a long wooded escarpment. A clump of tall trees stands to the left.",
            obstacles: ring(-131, -78, 3, 32, 6, 20), slope: (5.5, -165)),
    ]

    /// Distances read off a photo are uncertain, and too near is the costly mistake: the model then crashes in what
    /// looks like open air. An obstacle keeps its place and size in the picture but is moved out along the line of
    /// sight, more the farther away it was judged to be, and never so far that a tree would have to be a giant.
    /// Small things of known size (goals, bins, fence posts) stay where they are.
    static func farther(_ o: PanoObstacle, eye: Float) -> PanoObstacle {
        guard o.height > 3 else { return o }
        var f = 1.15 + 0.55 * clampf((o.distance - 15) / 35, 0, 1)
        if o.height > 6 { f = min(f, max(26 / o.height, 1)) }
        return PanoObstacle(bearing: o.bearing, distance: o.distance * f, radius: o.radius * f, height: eye + (o.height - eye) * f)
    }

    /// The part of an obstacle that is solid at a given height above its base: the dense core of a tree, narrowing
    /// toward the top. The airy edge of the crown and the space beside a pointed top are open.
    static func solidRadius(_ o: PanoObstacle, at y: Float) -> Float {
        guard y >= 0, y <= o.height else { return 0 }
        let core = o.radius * (o.height > 3 ? 0.75 : 1)
        let t = y / o.height
        return o.height > 6 && t > 0.55 ? core * (1 - 0.7 * (t - 0.55) / 0.45) : core
    }

    private static func meta(_ name: String, north: Float, wind: (Float, Float), start: (Float, Float, Float), category: String, difficulty: Int, info: String,
                             obstacles: [PanoObstacle]? = nil, eye: Float = 1.6, slope: (Float, Float)? = nil) -> PanoMeta {
        PanoMeta(name: name, north: north, horizon: 0, eyeHeight: eye, slope: slope?.0, uphill: slope?.1, windFrom: wind.0, windSpeed: wind.1, startX: start.0, startZ: start.1, startHeading: start.2,
                 obstacles: obstacles?.map { farther($0, eye: eye) }, category: category, info: info, difficulty: difficulty)
    }

    static func image(_ url: URL, maxSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSize]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// How much fine detail a panorama really holds, from 0 (soft: an enlarged or heavily compressed photo) to 1
    /// (pin sharp). Compares the contrast between neighbouring pixels with the contrast four pixels apart in a
    /// band around the horizon, where the trees, grass and buildings are.
    static func detail(_ px: [UInt8], width w: Int, height h: Int) -> Float {
        var g1: Float = 0, g4: Float = 0
        func lum(_ x: Int, _ y: Int) -> Float { let i = (y * w + x) * 4; return 0.3 * Float(px[i]) + 0.6 * Float(px[i + 1]) + 0.1 * Float(px[i + 2]) }
        var y = Int(Float(h) * 0.44)
        while y < Int(Float(h) * 0.6) {
            var x = 0
            while x < w - 5 { let a = lum(x, y); g1 += abs(lum(x + 1, y) - a); g4 += abs(lum(x + 4, y) - a); x += 3 }
            y += 7
        }
        return g4 > 0 ? g1 / g4 : 0.5
    }

    /// Estimate sun direction and ambient light from the photo so the model is lit to match
    /// and its ground shadow falls the right way.
    static func analyze(_ s: SiteSpec) -> Lighting {
        var light = Lighting(sunDir: normalize(V3(-0.35, 0.8, 0.5)), sun: V3(1, 0.97, 0.9) * 2.6, ambient: V3(0.4, 0.45, 0.55) * 0.7,
                             zenith: V3(0.3, 0.4, 0.6), horizon: V3(0.6, 0.65, 0.7))
        guard let url = s.panorama, let img = image(url, maxSize: 512) else { return light }
        let W = 64, H = 32
        var px = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return light }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        var sum = V3.zero, best: Float = -1, bx = 0, by = 0, lumSum: Float = 0
        for y in 0..<(H / 2) { for x in 0..<W {
            let i = (y * W + x) * 4
            let c = V3(pow(Float(px[i]) / 255, 2.2), pow(Float(px[i + 1]) / 255, 2.2), pow(Float(px[i + 2]) / 255, 2.2))
            let lum = dot(c, V3(0.2126, 0.7152, 0.0722))
            sum += c; lumSum += lum
            if lum > best { best = lum; bx = x; by = y }
        } }
        let n = Float(W * H / 2)
        let avg = sum / n, avgLum = max(lumSum / n, 0.01)
        let az = ((Float(bx) + 0.5) / Float(W) - 0.5 - s.north / 360) * 2 * .pi
        let el = max((0.5 - (Float(by) + 0.5) / Float(H)) * .pi - s.horizon * deg, 14 * deg)
        light.sunDir = normalize(V3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)))
        let sunny = best / avgLum > 2
        light.sun = V3(1, 0.97, 0.9) * (sunny ? 2.8 : 1.3)
        let amb = avg / avgLum * (sunny ? 0.42 : 0.75)
        light.ambient = simd_clamp(amb, V3(repeating: 0.15), V3(repeating: 1.2))
        light.zenith = avg; light.horizon = avg
        return light
    }
}

/// Which directions of a panorama hold something and which are open sky. A photographed tree or building is only
/// in the way where it can actually be seen: the model hits an obstacle when, from where the pilot stands, it is
/// in front of the object in the picture, not merely inside the rough shape that stands in for it.
final class PanoMask {
    let w = 1440, h = 720
    private(set) var solid: [Bool]
    private var px: [UInt8]

    init?(url: URL) {
        guard let img = Panoramas.image(url, maxSize: 2048) else { return nil }
        px = [UInt8](repeating: 0, count: w * h * 4)
        solid = [Bool](repeating: true, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        findSky()
    }

    private func findSky() {
        let w = self.w, h = self.h
        func lum(_ i: Int) -> Int { (Int(px[i * 4]) * 3 + Int(px[i * 4 + 1]) * 6 + Int(px[i * 4 + 2])) / 10 }
        // how busy each pixel is: sky is smooth, foliage and masonry are not
        var busy = [Int](repeating: 0, count: w * h)
        let limit = h * 62 / 100                               // the sky cannot reach far below the horizon
        for y in 1..<limit { for x in 0..<w {
            let i = y * w + x, l = lum(i)
            let xl = y * w + (x + w - 1) % w, xr = y * w + (x + 1) % w
            busy[i] = max(abs(l - lum(xl)), abs(l - lum(xr)), abs(l - lum(i - w)), abs(l - lum(i + w)))
        } }
        // sky: everything reachable from the top of the picture through smooth, gradual changes of colour
        var sky = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for x in 0..<w { sky[x] = true; stack.append(x) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w, l = lum(i)
            for (nx, ny) in [((x + 1) % w, y), ((x + w - 1) % w, y), (x, y + 1), (x, y - 1)] where ny >= 0 && ny < limit {
                let j = ny * w + nx
                if sky[j] || busy[j] > 9 { continue }
                let dr = abs(Int(px[j * 4]) - Int(px[i * 4])), db = abs(Int(px[j * 4 + 2]) - Int(px[i * 4 + 2]))
                if abs(lum(j) - l) > 7 || dr > 10 || db > 10 { continue }
                sky[j] = true; stack.append(j)
            }
        }
        // objects: whatever is not sky and is joined to the ground. Hard-edged clouds, wires and birds hang free
        // in the sky and do not count.
        var grounded = [Bool](repeating: false, count: w * h)
        for i in (limit - 1) * w..<w * h { grounded[i] = true }
        for x in 0..<w { stack.append((limit - 1) * w + x) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let ny = y + dy, nx = (x + dx + w) % w
                if ny < 0 || ny >= limit { continue }
                let j = ny * w + nx
                if grounded[j] || sky[j] { continue }
                grounded[j] = true; stack.append(j)
            } }
        }
        solid = grounded
    }

    private func pixel(_ dir: V3, north: Float, horizon: Float) -> (x: Int, y: Int) {
        let d = normalize(dir)
        var u = atan2(d.x, -d.z) / (2 * .pi) + 0.5 + north / 360
        u -= floor(u)
        let v = 0.5 - (asin(clampf(d.y, -1, 1)) + horizon * deg) / .pi
        return (min(Int(u * Float(w)), w - 1), min(max(Int(v * Float(h)), 0), h - 1))
    }

    /// Is there something in the photo in this direction (as seen from the camera)? A little generous, so thin
    /// branches count.
    func isSolid(_ dir: V3, north: Float, horizon: Float) -> Bool {
        let p = pixel(dir, north: north, horizon: horizon)
        var n = 0
        for dy in -1...1 { for dx in -1...1 {
            let y = min(max(p.y + dy, 0), h - 1), x = (p.x + dx + w) % w
            if solid[y * w + x] { n += 1 }
        } }
        return n >= 3
    }

    /// The photo's colour in this direction (linear-ish 0...1), for effects that should match what was hit.
    func color(_ dir: V3, north: Float, horizon: Float) -> V3 {
        let p = pixel(dir, north: north, horizon: horizon), i = (p.y * w + p.x) * 4
        return V3(Float(px[i]), Float(px[i + 1]), Float(px[i + 2])) / 255
    }
}
