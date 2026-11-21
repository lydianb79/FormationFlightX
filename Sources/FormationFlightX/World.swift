import simd
import Foundation

struct SiteSpec {
    var name: String
    var style: Int              // 0 meadow, 1 desert, 2 alpine
    var seed: Int32
    var runwayLen: Float
    var runwayWid: Float
    var runwayType: Int         // 0 asphalt, 1 mown grass, 2 dirt
    var flatCenterZ: Float
    var flatHalfZ: Float
    var treeCount: Int
    var windFrom: Float
    var windSpeed: Float
    var turbulence: Float
    var rollMu: Float
    var cloud: Float
    var fog: Float
    var panorama: URL? = nil    // photo site: equirectangular 360° image
    var north: Float = 0
    var horizon: Float = 0
    var eyeHeight: Float = 1.7
    var slope: Float = 0                // photo site on a hillside: steepness of the ground in degrees ...
    var uphill: Float = 0               // ... and the direction it rises in, as a bearing in the photo
    /// Height gained per metre along world x and z on a sloping photo site.
    var groundGradient: SIMD2<Float> {
        guard panorama != nil, slope != 0 else { return .zero }
        let a = (uphill - north) * deg
        return SIMD2(sin(a), -cos(a)) * tan(slope * deg)
    }
    var startZ: Float = 0
    var startX: Float = -30
    var startHeading: Float = 90        // compass degrees: 0 = away from the pilot, 90 = to the right
    var obstacles: [PanoObstacle] = []
    // presentation
    var key = ""                        // preview image name
    var category = "Fields"             // Fields, Mountains, Desert, Water, Winter, Airfields
    var info = ""
    var difficulty = 2                  // 1 easy ... 5 demanding
    // landscape
    var terrain = -1                    // height function; -1 = the one belonging to `style`
    var palette = -1                    // ground colours; -1 = by style
    var treeKind = -1                   // -1 by style, 0 deciduous, 1 scrub and cactus, 2 conifer, 3 palm, 4 acacia, 5 cypress and olive, 6 snowy conifer, 7 mixed forest, 8 autumn woods
    var treeThreshold: Float = 0.5      // lower = denser tree cover
    var treeClear = SIMD2<Float>(55, 35)   // tree-free margin beyond the runway ends and the field sides
    var keepFrontClear = true           // keep the area in front of the pilot free of trees
    var waterLevel: Float? = nil
    var waterColor = V3(0.05, 0.16, 0.2)
    var facility = 0                    // 0 club field, 1 airport with hangars and tower
    var extras = -1                     // surroundings: -1 by style, 0 farm, 1 desert camp, 2 alpine, 3 none
    var defaultTime = 1                 // 0 morning, 1 midday, 2 evening
    var flatBlend: Float? = nil         // distance over which the levelled field merges into the landscape

    /// 3D sites only: every pilot in a formation has to be in the same place, which a photo cannot give.
    static var all: [SiteSpec] = builtIn

    private static func make(_ name: String, key: String, style: Int, seed: Int32, runway: (len: Float, wid: Float, type: Int), flat: (center: Float, half: Float),
                             trees: Int, wind: (from: Float, speed: Float, turb: Float), mu: Float, cloud: Float, fog: Float,
                             category: String, difficulty: Int, info: String, _ edit: (inout SiteSpec) -> Void = { _ in }) -> SiteSpec {
        var s = SiteSpec(name: name, style: style, seed: seed, runwayLen: runway.len, runwayWid: runway.wid, runwayType: runway.type,
                         flatCenterZ: flat.center, flatHalfZ: flat.half, treeCount: trees, windFrom: wind.from, windSpeed: wind.speed, turbulence: wind.turb,
                         rollMu: mu, cloud: cloud, fog: fog)
        s.key = key; s.category = category; s.difficulty = difficulty; s.info = info
        edit(&s)
        return s
    }

    static let builtIn: [SiteSpec] = [
        make("Meadow Field", key: "meadow", style: 0, seed: 11, runway: (180, 12, 0), flat: (12, 45), trees: 800, wind: (90, 2, 0.3), mu: 0.035, cloud: 0.45, fog: 0.00011,
             category: "Fields", difficulty: 1,
             info: "A club field among rolling green hills: asphalt runway, clubhouse, pits and long grass around the mown strip. Light wind along the runway makes it the easiest place to learn."),
        make("Dry Lake", key: "desert", style: 1, seed: 29, runway: (300, 24, 2), flat: (0, 120), trees: 260, wind: (110, 4, 0.2), mu: 0.05, cloud: 0.15, fog: 0.00007,
             category: "Desert", difficulty: 2,
             info: "A wide dirt strip on a desert playa with mesas on the horizon. Plenty of room and nothing to hit, but expect a steady breeze and little to judge distance by."),
        make("Alpine Ridge", key: "alpine", style: 2, seed: 47, runway: (110, 10, 1), flat: (15, 25), trees: 700, wind: (0, 6, 0.35), mu: 0.07, cloud: 0.55, fog: 0.00009,
             category: "Mountains", difficulty: 4,
             info: "A grass strip on an alpine ridge. Wind blowing up the slope in front of you gives strong lift for soaring; turbulence and the drop-off make landings demanding."),
        make("Coastal Strip", key: "coast", style: 0, seed: 61, runway: (200, 14, 0), flat: (20, 40), trees: 420, wind: (0, 5, 0.25), mu: 0.035, cloud: 0.35, fog: 0.00012,
             category: "Water", difficulty: 2,
             info: "An asphalt strip behind the dunes. The beach and open sea start about a hundred metres in front of you, with a steady onshore breeze. Anything that comes down past the shoreline is lost.") {
            $0.terrain = 3; $0.palette = 3; $0.waterLevel = -1.6; $0.flatHalfZ = 34; $0.flatCenterZ = 24; $0.waterColor = V3(0.03, 0.17, 0.24); $0.treeThreshold = 0.56
        },
        make("Lakeside", key: "lake", style: 0, seed: 73, runway: (150, 12, 1), flat: (12, 42), trees: 900, wind: (250, 2, 0.2), mu: 0.06, cloud: 0.3, fog: 0.0001,
             category: "Water", difficulty: 2,
             info: "A mown grass strip beside a wooded lake. Calm air most days and a clear approach from both ends; the lake to the front right is the only real hazard.") {
            $0.terrain = 4; $0.waterLevel = -2.5; $0.flatHalfZ = 30; $0.waterColor = V3(0.04, 0.13, 0.12); $0.treeKind = 7
        },
        make("Winter Field", key: "snow", style: 2, seed: 83, runway: (160, 14, 3), flat: (12, 45), trees: 650, wind: (40, 3, 0.2), mu: 0.09, cloud: 0.5, fog: 0.00016,
             category: "Winter", difficulty: 3,
             info: "A packed-snow strip in a white valley under high peaks. Soft snow slows the take-off run, and the flat light makes it hard to judge height over the ground.") {
            $0.terrain = 5; $0.palette = 4; $0.treeKind = 6; $0.defaultTime = 0
        },
        make("Red Canyon", key: "canyon", style: 1, seed: 97, runway: (220, 18, 2), flat: (20, 40), trees: 200, wind: (200, 5, 0.45), mu: 0.05, cloud: 0.1, fog: 0.00006,
             category: "Desert", difficulty: 4,
             info: "A dirt strip on a mesa top. A canyon a hundred and forty metres deep opens a short way in front of the pilot line: spectacular to fly through, with rotor and gusts off the rim.") {
            $0.terrain = 6; $0.palette = 5
        },
        make("Savanna", key: "savanna", style: 1, seed: 113, runway: (260, 20, 2), flat: (0, 90), trees: 240, wind: (70, 3, 0.3), mu: 0.055, cloud: 0.25, fog: 0.00009,
             category: "Desert", difficulty: 2,
             info: "Golden grassland dotted with flat-topped acacias. A long, wide dirt strip, warm light and strong afternoon thermals: ideal for gliders.") {
            $0.terrain = 7; $0.palette = 6; $0.treeKind = 4; $0.treeThreshold = 0.58; $0.defaultTime = 2
        },
        make("Tropical Island", key: "island", style: 0, seed: 131, runway: (170, 14, 4), flat: (30, 40), trees: 520, wind: (320, 4, 0.2), mu: 0.06, cloud: 0.3, fog: 0.00008,
             category: "Water", difficulty: 3,
             info: "A sand strip on a small palm-fringed island. Turquoise shallows surround you on three sides, so keep some height in hand whenever you are out over the lagoon.") {
            $0.terrain = 8; $0.palette = 7; $0.treeKind = 3; $0.waterLevel = -0.9; $0.flatHalfZ = 26; $0.flatCenterZ = 16; $0.treeClear = SIMD2(30, 12); $0.keepFrontClear = false; $0.waterColor = V3(0.02, 0.3, 0.33); $0.extras = 3; $0.treeThreshold = 0.45
        },
        make("Highland Moor", key: "moor", style: 2, seed: 149, runway: (130, 12, 1), flat: (12, 40), trees: 60, wind: (280, 8, 0.5), mu: 0.07, cloud: 0.85, fog: 0.00022,
             category: "Mountains", difficulty: 4,
             info: "Open, treeless moorland with dark lochs in the hollows. It is almost always windy and overcast here: good practice for crosswind landings and for flying in poor contrast.") {
            $0.terrain = 9; $0.palette = 8; $0.waterLevel = -7; $0.waterColor = V3(0.03, 0.06, 0.08); $0.treeKind = 1
        },
        make("Regional Airport", key: "airport", style: 0, seed: 163, runway: (520, 26, 0), flat: (30, 130), trees: 500, wind: (95, 4, 0.2), mu: 0.03, cloud: 0.4, fog: 0.00012,
             category: "Airfields", difficulty: 2,
             info: "A full-size 520-metre asphalt runway with hangars, apron and control tower. Room for the fastest jets and the longest landing rolls.") {
            $0.terrain = 10; $0.facility = 1; $0.treeClear = SIMD2(80, 60)
        },
        make("Tuscan Hills", key: "tuscany", style: 0, seed: 181, runway: (150, 12, 1), flat: (12, 42), trees: 700, wind: (180, 2, 0.25), mu: 0.06, cloud: 0.25, fog: 0.00013,
             category: "Fields", difficulty: 2,
             info: "A grass strip among dry golden hills lined with cypress and olive trees. Evening light and gentle slope lift over the ridges on either side.") {
            $0.terrain = 11; $0.palette = 9; $0.treeKind = 5; $0.defaultTime = 2
        },
        make("Forest Clearing", key: "forest", style: 0, seed: 199, runway: (120, 10, 1), flat: (12, 40), trees: 2400, wind: (60, 1, 0.3), mu: 0.06, cloud: 0.4, fog: 0.00012,
             category: "Fields", difficulty: 5,
             info: "A short grass strip cut into tall forest. Sheltered from the wind, but the trees stand close on every side: steep approaches and no room for a wide circuit.") {
            $0.terrain = 12; $0.palette = 10; $0.treeKind = 7; $0.treeThreshold = 0.22; $0.treeClear = SIMD2(22, 2); $0.keepFrontClear = false; $0.extras = 3
        },
        make("Fjord", key: "fjord", style: 2, seed: 211, runway: (130, 11, 1), flat: (14, 30), trees: 900, wind: (270, 4, 0.35), mu: 0.06, cloud: 0.5, fog: 0.00012,
             category: "Water", difficulty: 4,
             info: "A grass strip on a narrow shelf above a deep fjord. Dark water starts a short way in front of you and rock walls climb hundreds of metres on both shores; the wind funnels along the water.") {
            $0.terrain = 13; $0.waterLevel = -9; $0.waterColor = V3(0.02, 0.09, 0.12); $0.treeKind = 2; $0.flatBlend = 90; $0.treeThreshold = 0.42
        },
        make("Lava Fields", key: "lava", style: 1, seed: 223, runway: (200, 16, 2), flat: (10, 60), trees: 120, wind: (140, 5, 0.35), mu: 0.055, cloud: 0.6, fog: 0.00013,
             category: "Mountains", difficulty: 3,
             info: "A cinder strip on a black lava plain patched with moss, under a volcano and a row of cinder cones. Dark ground and a grey sky make a bright model easy to see and a dark one vanish.") {
            $0.terrain = 14; $0.palette = 11; $0.extras = 3
        },
        make("Salt Flats", key: "salt", style: 1, seed: 239, runway: (400, 30, 0), flat: (0, 150), trees: 0, wind: (60, 5, 0.15), mu: 0.04, cloud: 0.1, fog: 0.00005,
             category: "Desert", difficulty: 2,
             info: "A black-topped strip on a dead-flat white salt pan that runs to mountains on the horizon. Unlimited room for speed runs, a steady breeze, and glare that hides how high you are.") {
            $0.terrain = 15; $0.palette = 12; $0.extras = 1
        },
        make("Autumn Valley", key: "autumn", style: 0, seed: 251, runway: (160, 12, 1), flat: (12, 42), trees: 2800, wind: (240, 2, 0.25), mu: 0.06, cloud: 0.35, fog: 0.00014,
             category: "Fields", difficulty: 2,
             info: "A mown strip on the floor of a wooded valley in full autumn colour. Low evening sun, light wind along the valley and gentle lift off the slopes on either side.") {
            $0.terrain = 16; $0.palette = 13; $0.treeKind = 8; $0.defaultTime = 2; $0.treeThreshold = 0.3
        },
        make("Wetlands", key: "marsh", style: 0, seed: 263, runway: (140, 12, 1), flat: (12, 34), trees: 260, wind: (300, 3, 0.2), mu: 0.065, cloud: 0.55, fog: 0.00018,
             category: "Water", difficulty: 3,
             info: "A grass strip on a dry rise in a reed marsh laced with channels and pools. Flat and open, with soft morning haze; land short or long and you are in the water.") {
            $0.terrain = 17; $0.palette = 14; $0.waterLevel = -1.1; $0.waterColor = V3(0.05, 0.1, 0.07); $0.defaultTime = 0; $0.treeThreshold = 0.6; $0.extras = 3; $0.flatBlend = 110
        },
        make("Sand Sea", key: "dunes", style: 1, seed: 277, runway: (240, 20, 4), flat: (0, 70), trees: 0, wind: (0, 6, 0.4), mu: 0.07, cloud: 0.05, fog: 0.00008,
             category: "Desert", difficulty: 3,
             info: "A packed-sand strip in a hollow between great dunes. The wind climbing the dune faces gives strong slope lift along the crests and rough air in their lee.") {
            $0.terrain = 18; $0.palette = 15; $0.extras = 1; $0.defaultTime = 2
        },
        make("Sea Cliffs", key: "cliffs", style: 0, seed: 293, runway: (150, 12, 1), flat: (22, 34), trees: 180, wind: (0, 7, 0.3), mu: 0.06, cloud: 0.45, fog: 0.00011,
             category: "Water", difficulty: 4,
             info: "A grass strip on a clifftop seventy metres above the sea. The onshore wind is forced up the cliff face just in front of you: superb slope soaring, and a long way down if you sink below the edge.") {
            $0.terrain = 19; $0.palette = 3; $0.waterLevel = -72; $0.waterColor = V3(0.03, 0.15, 0.22); $0.flatBlend = 62; $0.treeThreshold = 0.6; $0.treeKind = 1
        },
    ]
}

/// Ground, grass and bush colours for a landscape.
struct Palette {
    var a: V4, b: V4                    // ground, mixed by a noise pattern
    var rock: V4
    var high: V4                        // colour at altitude (forest, bare rock, snow)
    var highFrom: Float, highTo: Float
    var snowCaps = false                // `high` is snow: lies on top of rock, less on steep faces
    var rockFrom: Float = 1e6, rockTo: Float = 2e6
    var shore = rgb(0.76, 0.7, 0.55)
    var grassBase: V4, grassTip: V4
    var grassCount = 36000
    var bush: V4
    var bushCount = 160
    var flowers = true
    var dust = rgb(0.5, 0.42, 0.32)

    static let all: [Palette] = [
        // 0 meadow
        Palette(a: rgb(0.24, 0.40, 0.13), b: rgb(0.38, 0.50, 0.17), rock: rgb(0.42, 0.40, 0.37), high: rgb(0.15, 0.27, 0.13), highFrom: 120, highTo: 260,
                grassBase: rgb(0.15, 0.28, 0.09), grassTip: rgb(0.36, 0.5, 0.18), bush: rgb(0.2, 0.36, 0.12)),
        // 1 desert
        Palette(a: rgb(0.80, 0.70, 0.52), b: rgb(0.72, 0.60, 0.42), rock: rgb(0.45, 0.28, 0.2), high: rgb(0.62, 0.36, 0.24), highFrom: 15, highTo: 60,
                grassBase: rgb(0.5, 0.42, 0.26), grassTip: rgb(0.74, 0.66, 0.44), grassCount: 6000, bush: rgb(0.42, 0.42, 0.25), bushCount: 90, flowers: false, dust: rgb(0.75, 0.62, 0.45)),
        // 2 alpine
        Palette(a: rgb(0.27, 0.43, 0.16), b: rgb(0.40, 0.50, 0.20), rock: rgb(0.45, 0.44, 0.43), high: rgb(0.93, 0.95, 0.98), highFrom: 560, highTo: 760, snowCaps: true, rockFrom: 260, rockTo: 520,
                grassBase: rgb(0.15, 0.27, 0.1), grassTip: rgb(0.36, 0.48, 0.2), bush: rgb(0.16, 0.3, 0.14)),
        // 3 coast
        Palette(a: rgb(0.30, 0.42, 0.16), b: rgb(0.46, 0.50, 0.22), rock: rgb(0.5, 0.47, 0.42), high: rgb(0.2, 0.32, 0.15), highFrom: 40, highTo: 120, shore: rgb(0.82, 0.76, 0.6),
                grassBase: rgb(0.2, 0.3, 0.1), grassTip: rgb(0.5, 0.55, 0.26), grassCount: 30000, bush: rgb(0.22, 0.34, 0.14), dust: rgb(0.7, 0.64, 0.5)),
        // 4 snow
        Palette(a: rgb(0.93, 0.95, 0.98), b: rgb(0.86, 0.89, 0.95), rock: rgb(0.4, 0.41, 0.43), high: rgb(0.97, 0.98, 1.0), highFrom: 100, highTo: 400, snowCaps: true,
                grassBase: rgb(0.45, 0.38, 0.22), grassTip: rgb(0.7, 0.62, 0.4), grassCount: 2500, bush: rgb(0.3, 0.3, 0.26), bushCount: 40, flowers: false, dust: rgb(0.95, 0.96, 0.98)),
        // 5 red canyon
        Palette(a: rgb(0.72, 0.45, 0.3), b: rgb(0.62, 0.36, 0.24), rock: rgb(0.5, 0.24, 0.16), high: rgb(0.66, 0.34, 0.2), highFrom: 30, highTo: 120,
                grassBase: rgb(0.5, 0.4, 0.24), grassTip: rgb(0.72, 0.62, 0.4), grassCount: 4000, bush: rgb(0.4, 0.42, 0.26), bushCount: 110, flowers: false, dust: rgb(0.75, 0.48, 0.33)),
        // 6 savanna
        Palette(a: rgb(0.70, 0.60, 0.30), b: rgb(0.58, 0.52, 0.26), rock: rgb(0.5, 0.42, 0.34), high: rgb(0.45, 0.42, 0.24), highFrom: 60, highTo: 160,
                grassBase: rgb(0.45, 0.38, 0.16), grassTip: rgb(0.82, 0.72, 0.4), grassCount: 34000, bush: rgb(0.38, 0.4, 0.2), bushCount: 120, flowers: false, dust: rgb(0.72, 0.6, 0.4)),
        // 7 tropical
        Palette(a: rgb(0.20, 0.44, 0.14), b: rgb(0.32, 0.54, 0.18), rock: rgb(0.45, 0.42, 0.38), high: rgb(0.12, 0.32, 0.12), highFrom: 25, highTo: 60, shore: rgb(0.92, 0.88, 0.74),
                grassBase: rgb(0.12, 0.3, 0.08), grassTip: rgb(0.34, 0.56, 0.18), grassCount: 26000, bush: rgb(0.14, 0.38, 0.12), bushCount: 220, dust: rgb(0.85, 0.8, 0.65)),
        // 8 moor
        Palette(a: rgb(0.34, 0.36, 0.18), b: rgb(0.42, 0.33, 0.24), rock: rgb(0.36, 0.35, 0.34), high: rgb(0.4, 0.3, 0.3), highFrom: 30, highTo: 90, shore: rgb(0.3, 0.27, 0.2),
                grassBase: rgb(0.24, 0.24, 0.1), grassTip: rgb(0.52, 0.46, 0.24), grassCount: 34000, bush: rgb(0.36, 0.26, 0.3), bushCount: 200, flowers: false),
        // 9 tuscan
        Palette(a: rgb(0.62, 0.56, 0.28), b: rgb(0.46, 0.50, 0.22), rock: rgb(0.55, 0.48, 0.38), high: rgb(0.36, 0.42, 0.2), highFrom: 60, highTo: 160,
                grassBase: rgb(0.34, 0.34, 0.12), grassTip: rgb(0.72, 0.66, 0.34), grassCount: 32000, bush: rgb(0.3, 0.36, 0.18)),
        // 10 forest
        Palette(a: rgb(0.18, 0.34, 0.11), b: rgb(0.28, 0.42, 0.14), rock: rgb(0.38, 0.37, 0.34), high: rgb(0.1, 0.22, 0.1), highFrom: 60, highTo: 200,
                grassBase: rgb(0.12, 0.25, 0.08), grassTip: rgb(0.3, 0.46, 0.16), bush: rgb(0.14, 0.3, 0.1), bushCount: 240),
        // 11 lava field
        Palette(a: rgb(0.10, 0.10, 0.10), b: rgb(0.19, 0.18, 0.16), rock: rgb(0.16, 0.13, 0.12), high: rgb(0.34, 0.15, 0.1), highFrom: 90, highTo: 420,
                grassBase: rgb(0.2, 0.27, 0.1), grassTip: rgb(0.42, 0.5, 0.2), grassCount: 9000, bush: rgb(0.3, 0.38, 0.18), bushCount: 70, flowers: false, dust: rgb(0.25, 0.23, 0.22)),
        // 12 salt pan
        Palette(a: rgb(0.90, 0.90, 0.87), b: rgb(0.80, 0.80, 0.77), rock: rgb(0.5, 0.42, 0.36), high: rgb(0.52, 0.42, 0.36), highFrom: 25, highTo: 160,
                grassBase: rgb(0.6, 0.58, 0.5), grassTip: rgb(0.8, 0.78, 0.7), grassCount: 0, bush: rgb(0.5, 0.5, 0.4), bushCount: 0, flowers: false, dust: rgb(0.92, 0.92, 0.9)),
        // 13 autumn
        Palette(a: rgb(0.33, 0.42, 0.15), b: rgb(0.50, 0.47, 0.18), rock: rgb(0.42, 0.4, 0.36), high: rgb(0.40, 0.36, 0.14), highFrom: 60, highTo: 200,
                grassBase: rgb(0.26, 0.28, 0.09), grassTip: rgb(0.6, 0.52, 0.22), bush: rgb(0.52, 0.26, 0.1), bushCount: 200, flowers: false),
        // 14 marsh
        Palette(a: rgb(0.30, 0.40, 0.15), b: rgb(0.46, 0.46, 0.20), rock: rgb(0.36, 0.34, 0.3), high: rgb(0.2, 0.32, 0.14), highFrom: 40, highTo: 140, shore: rgb(0.27, 0.25, 0.17),
                grassBase: rgb(0.22, 0.3, 0.1), grassTip: rgb(0.64, 0.62, 0.3), grassCount: 42000, bush: rgb(0.34, 0.4, 0.16), bushCount: 260, flowers: false),
        // 15 dune sand
        Palette(a: rgb(0.86, 0.62, 0.36), b: rgb(0.80, 0.55, 0.30), rock: rgb(0.74, 0.5, 0.28), high: rgb(0.84, 0.6, 0.34), highFrom: 200, highTo: 400,
                grassBase: rgb(0.5, 0.42, 0.24), grassTip: rgb(0.7, 0.6, 0.36), grassCount: 0, bush: rgb(0.42, 0.42, 0.25), bushCount: 12, flowers: false, dust: rgb(0.86, 0.66, 0.42)),
    ]
}

extension SiteSpec {
    var pal: Palette { Palette.all[min(max(palette >= 0 ? palette : style, 0), Palette.all.count - 1)] }
    var trees: Int { treeKind >= 0 ? treeKind : [0, 1, 2][min(max(style, 0), 2)] }
    var surroundings: Int { extras >= 0 ? extras : min(max(style, 0), 2) }
    var kindLabel: String { panorama != nil ? "360° photo site" : "3D site" }
    var displayName: String { name.replacingOccurrences(of: "📷 ", with: "") }
    var surfaceLabel: String {
        if panorama != nil { return "As photographed" }
        return ["Asphalt runway", "Mown grass strip", "Dirt strip", "Packed snow strip", "Sand strip"][min(max(runwayType, 0), 4)] + String(format: ", %.0f × %.0f m", runwayLen, runwayWid)
    }
    var summary: String {
        if !info.isEmpty { return info }
        return "A real location photographed in 360°. You fly over the pictured ground from the spot where the camera stood. Pilot camera only."
            + (obstacles.isEmpty ? "" : " Trees and buildings near the camera are solid.")
    }
}

struct Tree { var p: V3; var h: Float }

final class Terrain {
    let n = 257
    let cell: Float = 24
    let half: Float
    var h: [Float]
    let site: SiteSpec
    var trees: [Tree] = []

    init(site: SiteSpec) {
        self.site = site
        half = Float(n - 1) * cell / 2
        h = [Float](repeating: 0, count: n * n)
        for j in 0..<n { for i in 0..<n {
            h[j * n + i] = raw(Float(i) * cell - half, Float(j) * cell - half)
        } }
        placeTrees()
    }

    private func raw(_ x: Float, _ z: Float) -> Float {
        if site.panorama != nil { let g = site.groundGradient; return g.x * x + g.y * z }
        let r = sqrt(x * x + z * z), s = site.seed
        var y: Float
        switch site.terrain >= 0 ? site.terrain : site.style {
        case 0:
            y = 45 * (fbm(x / 800, z / 800, s) - 0.45) + 6 * (fbm(x / 150, z / 150, s + 7) - 0.5)
            y += smoothstep(1300, 2900, r) * 420 * fbm(x / 1400, z / 1400, s + 3)
        case 1:
            y = 1.5 * (fbm(x / 300, z / 300, s) - 0.5)
            y += smoothstep(1200, 2200, r) * 260 * smoothstep(0.5, 0.62, fbm(x / 1100, z / 1100, s + 5))
            y += smoothstep(1500, 3000, r) * 120 * fbm(x / 600, z / 600, s + 9)
        case 2:
            y = -260 * smoothstep(40, 650, -z) + 60 * smoothstep(80, 600, z)
            y += 25 * (fbm(x / 300, z / 300, s) - 0.5) * smoothstep(60, 300, r)
            let rd = 1 - abs(2 * fbm(x / 1600, z / 1600, s + 11) - 1)
            y += smoothstep(900, 2600, r) * 900 * rd * rd
        case 3:     // coast: dunes, then beach and sea to the north; hills inland
            y = 5 * (fbm(x / 240, z / 240, s) - 0.5) + 70 * smoothstep(150, 1100, z) * fbm(x / 700, z / 700, s + 3)
            y -= 2.5 * smoothstep(40, 75, -z) + 40 * smoothstep(75, 420, -z + 40 * (fbm(x / 400, 0.3, s + 5) - 0.5))
        case 4:     // rolling meadow with a lake basin to the front right
            y = 34 * (fbm(x / 700, z / 700, s) - 0.42) + 5 * (fbm(x / 140, z / 140, s + 7) - 0.5)
            y += smoothstep(1300, 2900, r) * 380 * fbm(x / 1400, z / 1400, s + 3)
            let dl = sqrt((x - 120) * (x - 120) + (z + 250) * (z + 250)) + 60 * (fbm(x / 260, z / 260, s + 9) - 0.5)
            y = lerp(y, -16, smoothstep(230, 120, dl))
        case 5:     // snowy valley floor under high peaks
            y = 22 * (fbm(x / 600, z / 600, s) - 0.45) + 4 * (fbm(x / 130, z / 130, s + 7) - 0.5)
            let rd = 1 - abs(2 * fbm(x / 1500, z / 1500, s + 11) - 1)
            y += smoothstep(650, 2400, r) * 820 * rd * rd
        case 6:     // mesa cut by a winding canyon
            y = 4 * (fbm(x / 250, z / 250, s) - 0.5)
            let c = abs(z + 215 + 70 * sin(x / 240) + 50 * (fbm(x / 300, 1.7, s + 4) - 0.5))
            y -= 145 * smoothstep(150, 40, c) * (0.85 + 0.3 * fbm(x / 90, z / 90, s + 6))
            y += smoothstep(1000, 2100, r) * 240 * smoothstep(0.5, 0.62, fbm(x / 1100, z / 1100, s + 5))
        case 7:     // savanna plain with distant kopjes
            y = 9 * (fbm(x / 500, z / 500, s) - 0.5)
            y += smoothstep(900, 2300, r) * 170 * smoothstep(0.52, 0.7, fbm(x / 700, z / 700, s + 5))
        case 8:     // island: low hills falling to a lagoon
            let c = sqrt(x * x * 0.6 + (z - 150) * (z - 150)) + 90 * (fbm(x / 450, z / 450, s + 9) - 0.5)
            let isl = smoothstep(400, 235, c)
            y = (4 + 42 * fbm(x / 330, z / 330, s) * smoothstep(120, 500, z)) * isl - 26 * (1 - isl)
        case 9:     // moor: broad hills, hollows hold water
            y = 78 * (fbm(x / 650, z / 650, s) - 0.5) + 12 * (fbm(x / 150, z / 150, s + 7) - 0.5)
            y += smoothstep(1400, 2800, r) * 260 * fbm(x / 1200, z / 1200, s + 3)
        case 10:    // broad plain around the airport
            y = 8 * (fbm(x / 900, z / 900, s) - 0.5)
            y += smoothstep(1500, 2900, r) * 300 * fbm(x / 1400, z / 1400, s + 3)
        case 11:    // close-set rolling hills
            y = 62 * (fbm(x / 420, z / 420, s) - 0.46) + 7 * (fbm(x / 120, z / 120, s + 7) - 0.5)
            y += smoothstep(1400, 2900, r) * 300 * fbm(x / 1300, z / 1300, s + 3)
        case 13:    // fjord: a shelf above deep water between rock walls
            let mid = -z - 340 + 70 * (fbm(x / 520, 0.7, s + 5) - 0.5)          // distance from the middle of the water
            y = 8 * (fbm(x / 240, z / 240, s) - 0.5)
            y += 600 * smoothstep(225, 1000, abs(mid)) * (0.35 + 1.3 * fbm(x / 600, z / 600, s + 3))
            y -= 55 * smoothstep(255, 170, abs(mid))
        case 14:    // lava plain, cinder cones and a volcano
            y = 5 * (fbm(x / 110, z / 110, s) - 0.5) + 9 * (fbm(x / 420, z / 420, s + 2) - 0.5)
            y += smoothstep(450, 1300, r) * 230 * smoothstep(0.6, 0.78, fbm(x / 520, z / 520, s + 5))
            let dv = sqrt((x - 900) * (x - 900) + (z + 2100) * (z + 2100))
            y += 950 * max(0, 1 - dv / 1700) * max(0, 1 - dv / 1700) - 160 * smoothstep(260, 60, dv)
        case 15:    // salt pan with ranges on the horizon
            y = 0.25 * (fbm(x / 200, z / 200, s) - 0.5)
            let rd = 1 - abs(2 * fbm(x / 1500, z / 1500, s + 11) - 1)
            y += smoothstep(1700, 3000, r) * 620 * rd * rd
        case 16:    // valley running left to right between wooded slopes
            let side = abs(z - 20 + 60 * (fbm(x / 600, 0.3, s + 4) - 0.5))
            y = 5 * (fbm(x / 150, z / 150, s + 7) - 0.5) + 250 * smoothstep(130, 1000, side) * (0.5 + fbm(x / 700, z / 700, s))
            y += smoothstep(1500, 2900, r) * 260 * fbm(x / 1300, z / 1300, s + 3)
        case 17:    // marsh: a plain a little above the water, cut by channels and pools
            y = 3.2 * (fbm(x / 230, z / 230, s) - 0.42)
            y -= 3.5 * smoothstep(0.035, 0.0, abs(fbm(x / 420, z / 420, s + 4) - 0.5))
            y -= 3 * smoothstep(0.7, 0.8, fbm(x / 300, z / 300, s + 8))
            y += smoothstep(1500, 2900, r) * 160 * fbm(x / 1400, z / 1400, s + 3)
        case 18:    // dune field
            let wob = 140 * (fbm(x / 700, z / 700, s + 2) - 0.5)
            let rd = 1 - abs(2 * fbm((x + wob) / 330, (z + 0.6 * wob) / 620, s) - 1)
            y = (8 + 62 * smoothstep(120, 900, r)) * rd * rd + 16 * (fbm(x / 900, z / 900, s + 5) - 0.5)
        case 19:    // clifftop above the sea
            let edge = -z - 78 + 26 * (fbm(x / 210, 0.4, s + 5) - 0.5)          // positive beyond the cliff edge
            y = 9 * (fbm(x / 260, z / 260, s) - 0.5) + 55 * smoothstep(200, 1200, z) * fbm(x / 600, z / 600, s + 3)
            y -= 74 * smoothstep(-4, 22, edge) + 30 * smoothstep(22, 400, edge)
        default:    // forest floor
            y = 24 * (fbm(x / 600, z / 600, s) - 0.45) + 4 * (fbm(x / 120, z / 120, s + 7) - 0.5)
            y += smoothstep(1300, 2900, r) * 300 * fbm(x / 1400, z / 1400, s + 3)
        }
        let dx = max(abs(x) - (site.runwayLen / 2 + 25), 0), dz = max(abs(z - site.flatCenterZ) - site.flatHalfZ, 0)
        return y * smoothstep(34, site.flatBlend ?? (site.style == 2 ? 110 : 190), sqrt(dx * dx + dz * dz))
    }

    func height(_ x: Float, _ z: Float) -> Float {
        let gx = clampf((x + half) / cell, 0, Float(n - 1) - 0.001), gz = clampf((z + half) / cell, 0, Float(n - 1) - 0.001)
        let i = Int(gx), j = Int(gz)
        let fx = gx - Float(i), fz = gz - Float(j)
        let h00 = h[j * n + i], h10 = h[j * n + i + 1], h01 = h[(j + 1) * n + i], h11 = h[(j + 1) * n + i + 1]
        if fx + fz < 1 { return h00 + fx * (h10 - h00) + fz * (h01 - h00) }
        return h11 + (1 - fx) * (h01 - h11) + (1 - fz) * (h10 - h11)
    }

    func normal(_ x: Float, _ z: Float) -> V3 {
        let e: Float = 1.5
        return normalize(V3(height(x - e, z) - height(x + e, z), 2 * e, height(x, z - e) - height(x, z + e)))
    }

    /// What the wheels are on: rolling resistance, sideways grip, and bump height.
    func surface(_ x: Float, _ z: Float) -> (roll: Float, grip: Float, rough: Float) {
        if site.panorama != nil { return (0.05, 0.7, 0.004) }
        if abs(x) < site.runwayLen / 2 && abs(z) < site.runwayWid / 2 {
            switch site.runwayType {
            case 0: return (0.02, 0.9, 0)            // asphalt
            case 1: return (0.05, 0.65, 0.006)       // mown grass
            case 3: return (0.07, 0.3, 0.005)        // packed snow
            case 4: return (0.09, 0.5, 0.008)        // sand
            default: return (0.045, 0.6, 0.006)      // dirt
            }
        }
        let pal = site.palette >= 0 ? site.palette : site.style
        if pal == 4 { return (0.14, 0.3, 0.02) }                 // soft snow
        if pal == 1 || pal == 5 || pal == 11 || pal == 12 { return (0.07, 0.55, 0.012) }   // desert, lava, salt
        if pal == 15 { return (0.16, 0.45, 0.02) }               // loose sand
        return (0.09, 0.6, 0.02)                                 // long grass
    }

    /// What the ground is made of, for the sound of touching it: 0 asphalt or concrete, 1 grass, 2 snow, 3 sand, 4 bare earth.
    func groundKind(_ x: Float, _ z: Float) -> Int {
        if let url = site.panorama {
            let f = url.deletingPathExtension().lastPathComponent.lowercased()
            if f.contains("asphalt") || f.contains("airfield") || f.contains("parking") || f.contains("tarmac") { return 0 }
            if f.contains("snow") || f.contains("lago_disola") || site.category == "Winter" { return 2 }
            if f.contains("golden_gate") || f.contains("camdeboo") { return 4 }
            if f.contains("poolbeg") || f.contains("beach") || f.contains("dune") || f.contains("sand") { return 3 }
            if f.contains("cracked") || f.contains("farm_field") || f.contains("road") || site.category == "Desert" { return 4 }
            return 1
        }
        if abs(x) < site.runwayLen / 2 && abs(z) < site.runwayWid / 2 {
            switch site.runwayType { case 0: return 0; case 1: return 1; case 3: return 2; case 4: return 3; default: return 4 }
        }
        let pal = site.palette >= 0 ? site.palette : site.style
        if pal == 4 { return 2 }
        if pal == 15 { return 3 }
        if pal == 1 || pal == 5 || pal == 11 || pal == 12 { return 4 }
        return 1
    }

    /// A place to start a floatplane: the nearest open water with room to take off into the wind.
    func waterStart(windFrom: Float) -> V3? {
        guard let wl = site.waterLevel else { return nil }
        let a = windFrom * deg
        let dir = V3(sin(a), 0, -cos(a))                // take-off direction: into the wind
        func wet(_ p: V3) -> Bool { wl - height(p.x, p.z) > 0.8 }
        var r: Float = 50
        while r <= 520 {
            for k in 0..<24 {
                // search outward, starting in front of the pilot
                let ang = Float(k % 2 == 0 ? k / 2 : -(k + 1) / 2) * (Float.pi / 12)
                let p = V3(sin(ang) * r, wl, pilotPos.z - cos(ang) * r)
                if wet(p) && wet(p + dir * 60) && wet(p + dir * 130) && wet(p - dir * 15) { return p }
            }
            r += 25
        }
        return nil
    }

    /// Things that leave a wake in the wind: trees near the field and buildings.
    var windObstacles: [WindObstacle] {
        var o = trees.filter { abs($0.p.x) < 500 && abs($0.p.z) < 500 }.map { WindObstacle(p: $0.p, h: $0.h, r: $0.h * 0.3) }
        guard site.panorama == nil else { return [] }
        let hw = site.runwayWid / 2
        o.append(WindObstacle(p: V3(-48, height(-48, hw + 34), hw + 34), h: 4.5, r: 6))
        if site.facility == 1 {
            for x in [Float(62), 118, 174] { o.append(WindObstacle(p: V3(x, 0, hw + 106), h: 11.5, r: 20)) }
            o.append(WindObstacle(p: V3(18, 0, hw + 96), h: 22, r: 5))
        }
        return o
    }

    func contains(_ p: V3) -> Bool { abs(p.x) < half - 50 && abs(p.z) < half - 50 }

    private func placeTrees() {
        var rng = LCG(UInt64(site.seed))
        var tries = 0
        let kind = site.trees
        while trees.count < site.treeCount && tries < site.treeCount * 40 {
            tries += 1
            let x = rng.range(-1300, 1300), z = rng.range(-1300, 1300)
            let dx = max(abs(x) - (site.runwayLen / 2 + site.treeClear.x), 0), dz = max(abs(z - site.flatCenterZ) - (site.flatHalfZ + site.treeClear.y), 0)
            if dx * dx + dz * dz < 100 { continue }
            if site.keepFrontClear && z < 0 && z > -230 && abs(x) < 320 { continue }         // keep the flying area in front of the pilot open
            if fbm(x / 260, z / 260, site.seed + 21) < (kind == 1 ? max(site.treeThreshold, 0.56) : site.treeThreshold) { continue }
            let y = height(x, z)
            if normal(x, z).y < 0.85 || (site.style == 2 && y > 180) { continue }
            if let wl = site.waterLevel, y < wl + 0.8 { continue }
            let h: Float
            switch kind {
            case 1: h = rng.range(1.2, 3)
            case 3: h = rng.range(7, 12)
            case 4: h = rng.range(5, 8)
            case 5: h = rng.range(5, 14)
            case 7: h = rng.range(11, 20)
            default: h = rng.range(7, 15)
            }
            trees.append(Tree(p: V3(x, y, z), h: h))
        }
    }

    // MARK: Meshes

    func buildMesh() -> MeshBuilder {
        var b = MeshBuilder()
        b.data.reserveCapacity((n - 1) * (n - 1) * 60)
        var cols = [V4](repeating: .zero, count: n * n)
        var nrms = [V3](repeating: .zero, count: n * n)
        let s = site.seed
        let pal = site.pal
        for j in 0..<n { for i in 0..<n {
            let x = Float(i) * cell - half, z = Float(j) * cell - half
            let y = h[j * n + i]
            let hl = h[j * n + max(i - 1, 0)], hr = h[j * n + min(i + 1, n - 1)]
            let hd = h[max(j - 1, 0) * n + i], hu = h[min(j + 1, n - 1) * n + i]
            let nr = normalize(V3(hl - hr, 2 * cell, hd - hu))
            nrms[j * n + i] = nr
            let v = fbm(x / 110, z / 110, s + 31)
            let steep = smoothstep(0.86, 0.7, nr.y)
            var c = mix(pal.a, pal.b, v)
            if pal.snowCaps {
                c = mix(c, pal.rock, max(steep, smoothstep(pal.rockFrom, pal.rockTo, y)))
                c = mix(c, pal.high, smoothstep(pal.highFrom, pal.highTo, y + 160 * v) * (1 - steep * 0.6))
            } else {
                c = mix(c, pal.high, smoothstep(pal.highFrom, pal.highTo, y))
                c = mix(c, pal.rock, steep)
            }
            if let wl = site.waterLevel {
                // beach at the waterline, darker bed below it
                c = mix(pal.shore, c, smoothstep(0.4, 2.2, y - wl))
                if y < wl { c = mix(pal.shore, V4(pal.shore.x * 0.45, pal.shore.y * 0.5, pal.shore.z * 0.5, 1), smoothstep(0, 7, wl - y)) }
            }
            cols[j * n + i] = c
        } }
        for j in 0..<(n - 1) { for i in 0..<(n - 1) {
            func emit(_ ii: Int, _ jj: Int) {
                let k = jj * n + ii
                b.v(V3(Float(ii) * cell - half, h[k], Float(jj) * cell - half), nrms[k], cols[k])
            }
            emit(i, j); emit(i, j + 1); emit(i + 1, j)
            emit(i + 1, j); emit(i, j + 1); emit(i + 1, j + 1)
        } }
        return b
    }

    /// Water surface: one quad per terrain cell that dips below the water level. Vertex colour and
    /// opacity deepen with depth, so shallows look pale and clear.
    func buildWater() -> MeshBuilder {
        var b = MeshBuilder()
        guard let wl = site.waterLevel else { return b }
        let up = V3(0, 1, 0)
        let deep = V4(site.waterColor.x, site.waterColor.y, site.waterColor.z, 1)
        let shallow = V4(min(deep.x * 1.5 + 0.12, 1), min(deep.y * 1.3 + 0.2, 1), min(deep.z * 1.2 + 0.18, 1), 1)
        func vert(_ i: Int, _ j: Int) {
            let d = wl - h[j * n + i]
            let t = smoothstep(0, 5, d)
            var c = mix(shallow, deep, t)
            c.w = clampf(0.3 + d * 0.22, 0.25, 0.95)
            b.v(V3(Float(i) * cell - half, wl, Float(j) * cell - half), up, c)
        }
        for j in 0..<(n - 1) { for i in 0..<(n - 1) {
            let lo = min(min(h[j * n + i], h[j * n + i + 1]), min(h[(j + 1) * n + i], h[(j + 1) * n + i + 1]))
            if lo > wl + 0.2 { continue }
            vert(i, j); vert(i, j + 1); vert(i + 1, j)
            vert(i + 1, j); vert(i, j + 1); vert(i + 1, j + 1)
        } }
        return b
    }

    func overWater(_ p: V3) -> Bool {
        guard let wl = site.waterLevel else { return false }
        return p.y < wl + 0.05 && height(p.x, p.z) < wl
    }

    var windsockBase: V3 { V3(32, height(32, -site.runwayWid / 2 - 9), -site.runwayWid / 2 - 9) }
    var pilotPos: V3 { site.panorama != nil ? .zero : V3(0, height(0, site.runwayWid / 2 + 7), site.runwayWid / 2 + 7) }
}

func buildWindsock() -> MeshBuilder {
    var b = MeshBuilder()
    let n = 6
    for i in 0..<n {
        let z0 = Float(i) * 0.4, z1 = z0 + 0.4
        let r0 = 0.36 - 0.035 * Float(i), r1 = r0 - 0.035
        func ring(_ z: Float, _ r: Float) -> [V3] { (0..<10).map { j in let a = Float(j) / 10 * 2 * .pi; return V3(cos(a) * r, sin(a) * r, z) } }
        b.loft([ring(z0, r0), ring(z1, r1)], color: i % 2 == 0 ? rgb(0.95, 0.35, 0.05) : rgb(0.96, 0.96, 0.96), caps: false)
    }
    return b
}

struct Thermal { var c: SIMD2<Float>; var r: Float; var s: Float; var age: Float; var life: Float }
struct WindObstacle { var p: V3; var h: Float; var r: Float }

/// The air: mean wind with a boundary-layer profile, turbulence, wakes behind obstacles,
/// slope lift, and thermals that drift with the wind and come and go.
final class Environment {
    var windSpeed: Float = 2            // at 10 m above the ground
    var windFrom: Float = 90
    var turbulence: Float = 0.3
    var thermalsOn = true
    var thermalStrength: Float = 1      // 0 none ... 2 booming
    var gustiness: Float = 0.25         // 0 steady wind ... 1 strong lulls, gusts and shifts in direction
    var cloud: Float = 0.3              // cloud cover 0...1 (3D sites)
    var haze: Float = 0.2               // 0 crystal clear ... 1 thick mist (3D sites)
    private var lull: Float = 0, veer: Float = 0
    var time: Float = 0
    var thermals: [Thermal] = []
    var obstacles: [WindObstacle] = []
    private var rng = LCG(4242)
    private var gust = V3.zero          // along-wind, cross-wind, vertical
    private var wakeDeficit: Float = 0, wakeTurb: Float = 0, wakeTimer: Float = 0

    func configure(_ site: SiteSpec) {
        windSpeed = site.windSpeed; windFrom = site.windFrom; turbulence = site.turbulence
        thermalStrength = 1; thermalsOn = true; gustiness = min(0.15 + 0.6 * site.turbulence, 1)
        cloud = site.cloud; haze = Environment.haze(forFog: site.fog); lull = 0; veer = 0
        rng = LCG(UInt64(site.seed) + 5)
        thermals = (0..<6).map { _ in newThermal(aged: true) }
        gust = .zero; wakeDeficit = 0; wakeTurb = 0
    }

    private func newThermal(aged: Bool) -> Thermal {
        let life = rng.range(120, 300)
        return Thermal(c: SIMD2(rng.range(-420, 420), rng.range(-460, 80)), r: rng.range(30, 70), s: rng.range(1.4, 3.6),
                       age: aged ? rng.range(0, life) : 0, life: life)
    }

    /// Fog density for the renderer from the haze setting, and back.
    var fog: Float { 0.00004 * pow(40, haze) }
    static func haze(forFog f: Float) -> Float { clampf(log(max(f, 0.00004) / 0.00004) / log(40), 0, 1) }

    /// The wind right now: the set speed and direction with the current lull or gust and shift applied.
    var windVec: V3 { let t = (windFrom + veer) * deg; return V3(-sin(t), 0, cos(t)) * (windSpeed * max(1 + lull, 0)) }

    /// Named weather to start from.
    static let presets = ["Calm", "Light breeze", "Breezy", "Gusty", "Stormy"]
    func apply(preset i: Int) {
        let v: [(Float, Float, Float, Float, Float, Float)] = [   // wind, turbulence, gustiness, thermals, cloud, haze
            (0, 0.05, 0, 0.6, 0.1, 0.15), (2, 0.2, 0.2, 1, 0.25, 0.2), (5, 0.4, 0.4, 1.2, 0.4, 0.2), (8, 0.75, 0.85, 1, 0.6, 0.3), (13, 1, 1, 0.3, 0.95, 0.55)]
        let p = v[min(max(i, 0), v.count - 1)]
        windSpeed = p.0; turbulence = p.1; gustiness = p.2; thermalStrength = p.3; thermalsOn = p.3 > 0; cloud = p.4; haze = p.5
    }

    /// Advance the weather by one step around an aircraft at `p` flying at `airspeed`.
    func advance(dt: Float, at p: V3, airspeed: Float, terrain: Terrain) {
        time += dt
        // the wind is never steady: it lulls and gusts over several seconds and swings a little in direction
        if gustiness > 0 && windSpeed > 0.2 {
            let a: Float = 1 / 4.5, k = sqrt(2 * a * dt)
            lull += -lull * a * dt + gustiness * 0.42 * k * (rng.next() + rng.next() + rng.next() - 1.5) * 2
            veer += -veer * a * 0.6 * dt + gustiness * 22 * sqrt(2 * a * 0.6 * dt) * (rng.next() + rng.next() + rng.next() - 1.5) * 2
            lull = clampf(lull, -0.85, 1.2); veer = clampf(veer, -60, 60)
        } else { lull = 0; veer = 0 }
        let base = windVec
        let agl = max(p.y - terrain.height(p.x, p.z), 0)
        // thermals drift downwind, build, fade and are replaced
        for i in thermals.indices {
            thermals[i].age += dt
            thermals[i].c += SIMD2(base.x, base.z) * (0.6 * dt)
            if thermals[i].age > thermals[i].life || abs(thermals[i].c.x) > 650 || abs(thermals[i].c.y) > 650 { thermals[i] = newThermal(aged: false) }
        }
        // wake behind trees and buildings: slower, rougher air downwind of them (refreshed 50 times a second)
        wakeTimer -= dt
        if wakeTimer <= 0 {
            wakeTimer = 0.02
            var deficit: Float = 0, turb: Float = 0
            let speedNow = length(base)
            if speedNow > 0.3 {
                let dir = base / speedNow
                for o in obstacles {
                    let rx = p.x - o.p.x, rz = p.z - o.p.z
                    let along = rx * dir.x + rz * dir.z
                    if along < 0 || along > 12 * o.h || p.y - o.p.y > 1.4 * o.h { continue }
                    let lat = abs(rx * dir.z - rz * dir.x), width = o.r + 0.15 * along
                    if lat > width { continue }
                    let k = (1 - along / (12 * o.h)) * (1 - lat / width)
                    deficit = max(deficit, 0.7 * k); turb = max(turb, k)
                }
                // rotor in the lee of a slope
                let n = terrain.normal(p.x, p.z)
                let lee = -(base.x * -n.x + base.z * -n.z) / n.y / speedNow
                if lee > 0.05 { turb = max(turb, min(lee * 2.5, 1) * exp(-agl / 40)) }
            }
            wakeDeficit += (deficit - wakeDeficit) * 0.2; wakeTurb += (turb - wakeTurb) * 0.2
        }
        // turbulence: random gusts with a length scale that grows with height, so the air is choppy near
        // the ground and has long slow swells higher up
        if turbulence > 0 {
            let sigma = turbulence * (0.25 + 0.18 * windSpeed) + wakeTurb * windSpeed * 0.35
            let a = max(airspeed, 3) / clampf(agl, 8, 120)
            let k = sqrt(2 * a * dt)
            func noise() -> Float { (rng.next() + rng.next() + rng.next() - 1.5) * 2 }        // roughly unit variance
            gust.x += -gust.x * a * dt + sigma * k * noise()
            gust.y += -gust.y * a * dt + sigma * 0.8 * k * noise()
            gust.z += -gust.z * a * dt + sigma * 0.6 * min(1, agl / 10 + 0.3) * k * noise()
        } else {
            gust = .zero
        }
    }

    func wind(at p: V3, terrain: Terrain) -> V3 {
        let agl = max(p.y - terrain.height(p.x, p.z), 0)
        let base = windVec
        // boundary layer: the wind speed is given at 10 m and falls off logarithmically toward the ground
        let shear = clampf(log((agl + 0.1 + 0.05) / 0.05) / log(10.05 / 0.05), 0, 1.6)
        var w = base * (shear * (1 - wakeDeficit))
        let speedNow = length(base)
        let dir = speedNow > 0.01 ? base / speedNow : V3(1, 0, 0)
        w += dir * gust.x + V3(-dir.z, 0, dir.x) * gust.y + V3(0, gust.z, 0)
        if windSpeed > 0.1 {
            let n = terrain.normal(p.x, p.z)
            w.y += (base.x * -n.x + base.z * -n.z) / n.y * exp(-agl / 60) * 0.9
        }
        if thermalsOn && thermalStrength > 0 {
            let top = (1 - smoothstep(350, 500, agl)) * min(1, agl / 40)
            for th in thermals {
                // the column leans downwind as it rises; a ring of sinking air surrounds the core
                let dx = p.x - th.c.x - base.x * agl / 3, dz = p.z - th.c.y - base.z * agl / 3
                let d2 = dx * dx + dz * dz, r = th.r * (1 + agl / 400)
                if d2 > 9 * 6.25 * r * r { continue }
                let env = pow(max(sin(.pi * th.age / th.life), 0), 0.6)
                w.y += th.s * thermalStrength * env * top * (exp(-d2 / (r * r)) - 0.22 * exp(-d2 / (6.25 * r * r)))
            }
        }
        return w
    }
}

/// Simple demo pilot, also used for headless testing of the flight models.
struct Autopilot {
    var wp = 0
    var t: Float = 0
    static let circuit: [SIMD2<Float>] = [SIMD2(150, -80), SIMD2(150, -230), SIMD2(-150, -230), SIMD2(-150, -80)]

    mutating func update(_ ac: Aircraft, terrain: Terrain, dt: Float) -> Controls {
        t += dt
        var c = Controls()
        let agl = ac.pos.y - terrain.height(ac.pos.x, ac.pos.z)
        switch ac.spec.kind {
        case .airplane:
            let target = Autopilot.circuit[wp]
            let to = V3(target.x - ac.pos.x, 0, target.y - ac.pos.z)
            if length(to) < 45 { wp = (wp + 1) % Autopilot.circuit.count }
            // by the direction of travel, not the nose: tailless wings wag their noses
            var fh = V3(ac.vel.x, 0, ac.vel.z)
            if length(fh) < 3 { fh = ac.forward; fh.y = 0 }
            fh = length(fh) > 0.01 ? normalize(fh) : V3(0, 0, -1)
            let d = normalize(to)
            let herr = atan2(-cross(fh, d).y, dot(fh, d))
            let climbing = agl < 6
            let rollT = climbing ? 0 : clampf(herr * 1.2, -0.65, 0.65)
            let altT: Float = 40
            let vs = ac.spec.stallSpeed
            let pitchT = climbing ? (ac.airspeed > vs * 1.15 ? 0.16 : 0.03) : clampf(0.02 * (altT - agl), -0.18, 0.28)
            c.aileron = clampf(2.5 * (rollT - ac.roll) + 0.25 * ac.omega.z, -1, 1)
            c.elevator = clampf(3 * (pitchT - ac.pitch) - 0.3 * ac.omega.x + 0.25 * abs(ac.roll), -1, 1)
            c.rudder = ac.onGround ? clampf(1.5 * herr * 0, -1, 1) : clampf(0.3 * (rollT - ac.roll), -0.5, 0.5)
            c.throttle = climbing ? 1 : clampf(0.6 + 0.08 * (clampf(vs * 1.8, 5, 24) - ac.airspeed) + 0.02 * (altT - agl), 0.2, 1)
        case .multirotor, .helicopter:
            let ang = t * 0.25
            let tp = V3(30 * sin(ang), 0, -45 + 20 * cos(ang))
            let alt: Float = min(12, 2 + t * 2)
            var vd = (tp - ac.pos) * 0.6; vd.y = 0
            if length(vd) > 7 { vd *= 7 / length(vd) }
            var ad = (vd - ac.vel) * 1.5; ad.y = 0
            if length(ad) > 5 { ad *= 5 / length(ad) }
            let vy = clampf(alt - agl, -2, 3)
            if ac.spec.kind == .multirotor {
                var fh = ac.forward; fh.y = 0; fh = normalize(fh)
                let hr = cross(fh, V3(0, 1, 0))
                let m = ac.spec.multi!
                c.elevator = clampf(-atan(dot(ad, fh) / gravity) / m.maxAngle, -1, 1)
                c.aileron = clampf(atan(dot(ad, hr) / gravity) / m.maxAngle, -1, 1)
                c.throttle = clampf(ac.spec.hoverThrottle + 0.1 * (vy - ac.vel.y), 0.02, 1)
            } else {
                let h = ac.spec.heli!
                let tgt = normalize(V3(ad.x, gravity, ad.z))
                let eb = simd_float3x3(ac.q).transpose * cross(ac.up, tgt)
                c.elevator = clampf(eb.x * 6 / h.maxRate, -1, 1)
                c.aileron = clampf(-eb.z * 6 / h.maxRate, -1, 1)
                c.throttle = clampf(0.67 + 0.1 * (vy - ac.vel.y), 0, 1)
                c.mode = 1          // the demo pilot flies helicopters in acro
            }
        }
        return c
    }
}
