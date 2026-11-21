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
    var flatHalfX: Float? = nil         // half-width of the levelled ground along the runway, if wider than the runway
    var layout = 0                      // what is built here: 0 nothing, 1-3 race tracks, 4-5 obstacle courses, 6-7 cities
    var cruiseAlt: Float = 38           // height at which the computer lead flies its racetrack: clear of everything built
    var clubhouse = true                // the model club's hut, car park and hedge behind the flight line
    var treeRange: Float = 1300         // trees are scattered this far out from the field
    var patchwork = false               // farmland: the country round about is divided into fields of different crops

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
        // ---- open country
        make("Heather Downs", key: "downs", style: 0, seed: 307, runway: (170, 12, 1), flat: (12, 45), trees: 260, wind: (250, 3, 0.25), mu: 0.06, cloud: 0.4, fog: 0.00012,
             category: "Fields", difficulty: 1,
             info: "A mown strip on open downland, purple with heather, the long ridges rolling away on every side. Nothing to hit and a steady breeze up the slopes: the place to learn to hold a slot.") {
            $0.terrain = 20; $0.palette = 16; $0.treeThreshold = 0.62
        },
        make("Rice Terraces", key: "terraces", style: 0, seed: 331, runway: (140, 11, 2), flat: (12, 34), trees: 420, wind: (150, 2, 0.2), mu: 0.055, cloud: 0.5, fog: 0.00016,
             category: "Fields", difficulty: 3,
             info: "A dirt strip on a level step of a terraced hillside. The paddies climb in green stairs behind you and fall away in front; morning mist hangs in the valley.") {
            $0.terrain = 21; $0.palette = 17; $0.treeKind = 3; $0.defaultTime = 0; $0.flatBlend = 70; $0.extras = 3
        },
        make("Outback Aerodrome", key: "outback", style: 1, seed: 349, runway: (460, 24, 2), flat: (30, 130), trees: 320, wind: (120, 5, 0.25), mu: 0.05, cloud: 0.1, fog: 0.00006,
             category: "Airfields", difficulty: 2,
             info: "A long red-dirt runway with hangars and a tower, alone on a plain of red earth and grey scrub. Room for five wings abreast and a horizon in every direction.") {
            $0.terrain = 30; $0.palette = 26; $0.facility = 1; $0.treeKind = 4; $0.treeClear = SIMD2(80, 60); $0.treeThreshold = 0.56
        },
        make("Karst Valley", key: "karst", style: 0, seed: 367, runway: (150, 12, 1), flat: (12, 40), trees: 1500, wind: (200, 2, 0.3), mu: 0.06, cloud: 0.55, fog: 0.0002,
             category: "Mountains", difficulty: 4,
             info: "A grass strip on a valley floor between limestone towers that stand up out of the jungle like teeth. Thread the formation between them, or climb above the haze and look down.") {
            $0.terrain = 22; $0.palette = 18; $0.treeKind = 7; $0.treeThreshold = 0.4; $0.extras = 3
        },
        make("Caldera", key: "caldera", style: 2, seed: 383, runway: (200, 16, 2), flat: (10, 60), trees: 90, wind: (300, 6, 0.4), mu: 0.055, cloud: 0.35, fog: 0.0001,
             category: "Mountains", difficulty: 3,
             info: "A cinder strip on the floor of an old volcano's crater, ringed by a wall of rock nearly a kilometre away. The wind tumbles over the rim, and the wall is always there when you look up.") {
            $0.terrain = 23; $0.palette = 19; $0.treeKind = 1; $0.extras = 3; $0.flatBlend = 190
        },
        make("Archipelago", key: "archipelago", style: 0, seed: 401, runway: (160, 13, 4), flat: (20, 34), trees: 520, wind: (30, 4, 0.2), mu: 0.06, cloud: 0.3, fog: 0.00009,
             category: "Water", difficulty: 3,
             info: "A sand strip on the largest of a scatter of wooded islands. Between them the sea is shallow and pale; fly from island to island and keep enough height to reach the next.") {
            $0.terrain = 24; $0.palette = 20; $0.treeKind = 3; $0.waterLevel = -2.6; $0.waterColor = V3(0.02, 0.26, 0.32); $0.treeClear = SIMD2(30, 12); $0.keepFrontClear = false; $0.extras = 3; $0.treeThreshold = 0.46; $0.flatBlend = 110
        },
        make("Coral Atoll", key: "atoll", style: 0, seed: 419, runway: (150, 12, 4), flat: (16, 20), trees: 300, wind: (90, 5, 0.15), mu: 0.06, cloud: 0.2, fog: 0.00007,
             category: "Water", difficulty: 4,
             info: "A sand strip on a ring of coral barely sixty metres wide. The lagoon it encloses lies in front of you, the open ocean behind: wherever you come down that is not the ring, you are wet.") {
            $0.terrain = 25; $0.palette = 21; $0.treeKind = 3; $0.waterLevel = -1.0; $0.waterColor = V3(0.02, 0.32, 0.36); $0.treeClear = SIMD2(20, 6); $0.keepFrontClear = false; $0.extras = 3; $0.treeThreshold = 0.4; $0.flatBlend = 55
        },
        make("Badlands", key: "badlands", style: 1, seed: 433, runway: (220, 18, 2), flat: (10, 50), trees: 70, wind: (180, 4, 0.4), mu: 0.05, cloud: 0.15, fog: 0.00007,
             category: "Desert", difficulty: 3,
             info: "A dirt strip on a flat among striped, gullied hills of clay. Dozens of narrow valleys lead off between the ridges; rough air comes off every crest in the afternoon.") {
            $0.terrain = 26; $0.palette = 22; $0.extras = 1
        },
        make("Oasis", key: "oasis", style: 1, seed: 449, runway: (200, 16, 2), flat: (10, 55), trees: 300, wind: (40, 3, 0.25), mu: 0.055, cloud: 0.05, fog: 0.00008,
             category: "Desert", difficulty: 2,
             info: "A strip on a gravel plain beside a spring-fed pool ringed with green, palm groves scattered about and dunes on the skyline. Calm, warm evening air.") {
            $0.terrain = 27; $0.palette = 23; $0.treeKind = 3; $0.waterLevel = -2; $0.waterColor = V3(0.04, 0.2, 0.2); $0.defaultTime = 2; $0.treeThreshold = 0.57; $0.extras = 1
        },
        make("Frozen Lake", key: "icelake", style: 2, seed: 461, runway: (260, 20, 3), flat: (0, 100), trees: 800, wind: (330, 4, 0.2), mu: 0.08, cloud: 0.45, fog: 0.00015,
             category: "Winter", difficulty: 2,
             info: "A strip ploughed on the ice of a frozen lake a kilometre across. Dead flat and wide open, with snowy pine shores all round and high white peaks behind them.") {
            $0.terrain = 28; $0.palette = 24; $0.treeKind = 6; $0.defaultTime = 0; $0.flatBlend = 190; $0.treeThreshold = 0.42; $0.extras = 3
        },
        make("Tundra", key: "tundra", style: 2, seed: 479, runway: (150, 12, 3), flat: (12, 40), trees: 60, wind: (10, 7, 0.45), mu: 0.08, cloud: 0.7, fog: 0.0002,
             category: "Winter", difficulty: 4,
             info: "A packed strip on open tundra, brown grass showing through old snow, black meltwater pools in the hollows. Always windy, usually grey, and nothing taller than a bush for miles.") {
            $0.terrain = 29; $0.palette = 25; $0.treeKind = 1; $0.waterLevel = -3.2; $0.waterColor = V3(0.02, 0.04, 0.06); $0.extras = 3
        },
        // ---- race tracks
        make("Stadium Circuit", key: "stadium", style: 0, seed: 503, runway: (120, 10, 1), flat: (-70, 190), trees: 300, wind: (270, 2, 0.15), mu: 0.06, cloud: 0.3, fog: 0.0001,
             category: "Race Tracks", difficulty: 2,
             info: "Eight gates in a loop on a flat sports ground, grandstands along the far side. All left turns, two of the gates raised: fly through the first gate to start the clock, then through them in order.") {
            $0.terrain = 31; $0.palette = 27; $0.flatHalfX = 230; $0.layout = 1; $0.treeClear = SIMD2(40, 30)
        },
        make("Forest Slalom", key: "slalom", style: 0, seed: 521, runway: (110, 10, 1), flat: (12, 34), trees: 2600, wind: (60, 1, 0.3), mu: 0.06, cloud: 0.4, fog: 0.00013,
             category: "Race Tracks", difficulty: 4,
             info: "Seven gates along a ride cut through tall forest, out to the right and back. The trees stand fifteen metres either side of the line and do not move.") {
            $0.terrain = 32; $0.palette = 29; $0.treeKind = 7; $0.treeThreshold = 0.2; $0.treeClear = SIMD2(22, 4); $0.keepFrontClear = false; $0.extras = 3; $0.layout = 2
        },
        make("Canyon Run", key: "canyonrun", style: 1, seed: 541, runway: (160, 14, 2), flat: (25, 35), trees: 110, wind: (90, 4, 0.45), mu: 0.05, cloud: 0.1, fog: 0.00006,
             category: "Race Tracks", difficulty: 5,
             info: "Seven gates down the floor of a winding sandstone canyon sixty metres deep, then four high gates back along the rim. The canyon is seventy metres wide at the top and less at the bottom.") {
            $0.terrain = 33; $0.palette = 30; $0.flatBlend = 55; $0.layout = 3; $0.cruiseAlt = 60
        },
        // ---- obstacle courses
        make("Pylon Park", key: "pylons", style: 0, seed: 557, runway: (140, 12, 0), flat: (-70, 190), trees: 260, wind: (250, 2, 0.15), mu: 0.035, cloud: 0.35, fog: 0.0001,
             category: "Obstacles", difficulty: 3,
             info: "A flat field set out with things to fly round, through and under: a slalom of pylons, three walls with windows of different sizes, an arch, a limbo bar, a tunnel and two hoops in the sky.") {
            $0.terrain = 31; $0.palette = 27; $0.flatHalfX = 230; $0.layout = 4; $0.treeClear = SIMD2(40, 30); $0.cruiseAlt = 48
        },
        make("Container Yard", key: "containers", style: 0, seed: 571, runway: (220, 18, 0), flat: (-90, 200), trees: 0, wind: (300, 3, 0.3), mu: 0.035, cloud: 0.6, fog: 0.00014,
             category: "Obstacles", difficulty: 4,
             info: "Seven rows of stacked shipping containers with lanes between them just wide enough for a formation in line astern, gaps to dart through, and two gantry cranes to fly under.") {
            $0.terrain = 31; $0.palette = 28; $0.flatHalfX = 290; $0.layout = 5; $0.clubhouse = false; $0.extras = 3; $0.cruiseAlt = 55
        },
        // ---- cities
        make("Downtown", key: "downtown", style: 0, seed: 587, runway: (260, 20, 0), flat: (-80, 360), trees: 240, wind: (270, 3, 0.4), mu: 0.035, cloud: 0.35, fog: 0.00016,
             category: "Cities", difficulty: 5,
             info: "A city centre: towers up to a hundred and twenty metres on a grid of streets twenty-four metres wide, with walkways across the avenues. You stand in a square beside a boulevard; the avenue ahead is your way in.") {
            $0.terrain = 31; $0.palette = 28; $0.flatHalfX = 540; $0.layout = 6; $0.clubhouse = false; $0.extras = 3; $0.cruiseAlt = 140; $0.defaultTime = 2; $0.treeClear = SIMD2(60, 60)
        },
        make("Harbour Town", key: "harbour", style: 0, seed: 601, runway: (200, 16, 0), flat: (40, 150), trees: 200, wind: (0, 5, 0.3), mu: 0.035, cloud: 0.45, fog: 0.00013,
             category: "Cities", difficulty: 4,
             info: "A port: low streets behind the quay, cranes with their booms out over the water, two ships alongside, and a long bridge across the harbour mouth with twenty-six metres of air under its deck.") {
            $0.terrain = 34; $0.palette = 28; $0.flatHalfX = 400; $0.flatBlend = 60; $0.layout = 7; $0.clubhouse = false; $0.extras = 3; $0.cruiseAlt = 95; $0.waterLevel = -1.2; $0.waterColor = V3(0.03, 0.13, 0.19); $0.treeClear = SIMD2(60, 60)
        },
        // ---- second series
        make("Lakeside Loop", key: "lakeside", style: 0, seed: 613, runway: (130, 11, 1), flat: (12, 36), trees: 1100, wind: (230, 3, 0.2), mu: 0.06, cloud: 0.35, fog: 0.00011,
             category: "Race Tracks", difficulty: 3,
             info: "Eight gates round a lake: four on the shore, four standing in the water with three metres of air under them. A jetty, a boathouse and a few boats at anchor; the water is as hard as the ground.") {
            $0.terrain = 36; $0.palette = 31; $0.treeKind = 7; $0.treeThreshold = 0.46; $0.waterLevel = -1.6; $0.waterColor = V3(0.03, 0.2, 0.26); $0.flatBlend = 70; $0.layout = 8; $0.extras = 3; $0.patchwork = true
        },
        make("Wind Farm", key: "windfarm", style: 0, seed: 631, runway: (160, 12, 1), flat: (12, 40), trees: 160, wind: (265, 7, 0.3), mu: 0.06, cloud: 0.45, fog: 0.0001,
             category: "Obstacles", difficulty: 3,
             info: "Seven wind turbines on open upland, a hundred and twenty metres to the blade tips, with a measuring mast held up by wires and a line of pylons leaving the substation. Fly between the towers, under the hubs, round the mast.") {
            $0.terrain = 37; $0.palette = 32; $0.layout = 9; $0.cruiseAlt = 150; $0.treeThreshold = 0.6; $0.extras = 3; $0.patchwork = true
        },
        make("Old Town", key: "oldtown", style: 0, seed: 641, runway: (110, 12, 2), flat: (-40, 250), trees: 420, wind: (250, 2, 0.35), mu: 0.045, cloud: 0.4, fog: 0.00014,
             category: "Cities", difficulty: 5,
             info: "A walled town on a river: steep red roofs over narrow streets, a church with a fifty-metre spire, a gate in the wall to fly through, a low stone bridge and a tall aqueduct with arches wide enough for a wing.") {
            $0.terrain = 38; $0.palette = 33; $0.flatHalfX = 420; $0.flatBlend = 60; $0.layout = 10; $0.extras = 3; $0.cruiseAlt = 90; $0.clubhouse = false
            $0.waterLevel = -2.2; $0.waterColor = V3(0.05, 0.16, 0.14); $0.treeClear = SIMD2(330, 60); $0.treeThreshold = 0.45; $0.patchwork = true
        },
        make("Gravel Works", key: "gravelworks", style: 1, seed: 653, runway: (150, 12, 2), flat: (-40, 150), trees: 520, wind: (240, 3, 0.3), mu: 0.05, cloud: 0.3, fog: 0.00012,
             category: "Industrial", difficulty: 4,
             info: "A working gravel pit: a silo tower with conveyor belts climbing to it from the pit and running out to the stockpiles, screening halls, hoppers on stilts and a tower crane. The belts are high enough to fly under; the pit is twenty metres deep with a pond at the bottom.") {
            $0.terrain = 39; $0.palette = 34; $0.flatHalfX = 200; $0.flatBlend = 60; $0.layout = 11; $0.extras = 3; $0.treeKind = 7; $0.cruiseAlt = 80; $0.clubhouse = false
            $0.waterLevel = -21.5; $0.waterColor = V3(0.07, 0.26, 0.24); $0.treeClear = SIMD2(260, 120); $0.treeThreshold = 0.48
        },
        make("Power Station", key: "powerstation", style: 0, seed: 661, runway: (200, 16, 0), flat: (-60, 260), trees: 260, wind: (290, 4, 0.35), mu: 0.035, cloud: 0.55, fog: 0.00016,
             category: "Industrial", difficulty: 4,
             info: "Two cooling towers a hundred metres high, two striped chimneys half as high again, a boiler house, a coal conveyor and a switchyard with its pylons. Big things, wide gaps: room for a whole formation between the towers.") {
            $0.terrain = 31; $0.palette = 35; $0.flatHalfX = 500; $0.layout = 12; $0.extras = 3; $0.cruiseAlt = 170; $0.clubhouse = false; $0.treeClear = SIMD2(330, 120)
        },
        make("Vineyard Hills", key: "vineyard", style: 0, seed: 673, runway: (150, 12, 1), flat: (12, 38), trees: 260, wind: (200, 2, 0.2), mu: 0.06, cloud: 0.25, fog: 0.00012,
             category: "Fields", difficulty: 2,
             info: "A grass strip among vineyards on rolling hills, the rows of vines combing every slope, a wine estate with its tower on the knoll to the right and cypresses along the road to it. Hardly any wind.") {
            $0.terrain = 40; $0.palette = 36; $0.treeKind = 5; $0.treeThreshold = 0.6; $0.layout = 13; $0.patchwork = true; $0.flatBlend = 120
        },
        make("Seaside Airport", key: "airport", style: 0, seed: 683, runway: (640, 30, 0), flat: (50, 170), trees: 300, wind: (280, 5, 0.25), mu: 0.035, cloud: 0.4, fog: 0.0001,
             category: "Airfields", difficulty: 2,
             info: "A small airport by the sea: 640 metres of asphalt, a glass terminal with three airliners on the apron, a control tower, hangars, a fuel farm and approach lights at both ends. All the room in the world for five abreast.") {
            $0.terrain = 41; $0.palette = 37; $0.flatHalfX = 470; $0.layout = 14; $0.extras = 3; $0.clubhouse = false; $0.cruiseAlt = 60; $0.treeClear = SIMD2(160, 110)
            $0.waterLevel = -3; $0.waterColor = V3(0.03, 0.17, 0.25); $0.patchwork = true
        },
        make("Glacier Valley", key: "glacier", style: 2, seed: 691, runway: (150, 12, 1), flat: (10, 36), trees: 900, wind: (190, 4, 0.35), mu: 0.06, cloud: 0.3, fog: 0.00008,
             category: "Mountains", difficulty: 4,
             info: "A meadow on the floor of a valley with walls seven hundred metres high. A milky green lake lies in front of you, hay barns dot the pasture, and at the head of the valley a glacier comes down between the peaks.") {
            $0.terrain = 42; $0.palette = 38; $0.treeKind = 2; $0.treeThreshold = 0.45; $0.waterLevel = -3.2; $0.waterColor = V3(0.05, 0.34, 0.36); $0.layout = 15; $0.flatBlend = 80
        },
        make("Lighthouse Point", key: "lighthouse", style: 0, seed: 701, runway: (140, 11, 1), flat: (14, 40), trees: 110, wind: (300, 6, 0.3), mu: 0.06, cloud: 0.4, fog: 0.00011,
             category: "Water", difficulty: 3,
             info: "A clifftop meadow above the sea, a striped lighthouse out on the point to the right, stacks of rock standing in the water and a natural arch to fly through. Lift along the cliff edge when the wind is onshore.") {
            $0.terrain = 43; $0.palette = 39; $0.waterLevel = -24; $0.waterColor = V3(0.02, 0.14, 0.22); $0.treeThreshold = 0.6; $0.flatBlend = 60; $0.layout = 16; $0.extras = 3; $0.cruiseAlt = 60
        },
        make("Monument Mesa", key: "monument", style: 1, seed: 709, runway: (220, 18, 2), flat: (10, 55), trees: 140, wind: (150, 4, 0.35), mu: 0.05, cloud: 0.12, fog: 0.00006,
             category: "Desert", difficulty: 3,
             info: "A red plain with flat-topped buttes two hundred metres high standing on the horizon, three needles of rock close by and a natural arch you can take a formation through. Low evening sun and long shadows.") {
            $0.terrain = 44; $0.palette = 40; $0.layout = 17; $0.extras = 1; $0.cruiseAlt = 95; $0.defaultTime = 2; $0.treeKind = 1
        },
        make("Ski Resort", key: "skiresort", style: 2, seed: 719, runway: (160, 14, 3), flat: (15, 40), trees: 5200, wind: (320, 3, 0.3), mu: 0.08, cloud: 0.3, fog: 0.0001,
             category: "Winter", difficulty: 4,
             info: "The valley station of a ski area: the mountain rises in front of you, three pistes come down through snowy forest, and a chairlift climbs beside them with its cable and chairs. Chalets round the strip; the lift cable is solid.") {
            $0.terrain = 45; $0.palette = 41; $0.treeKind = 6; $0.treeThreshold = 0.3; $0.treeRange = 900; $0.layout = 18; $0.flatBlend = 90; $0.cruiseAlt = 50; $0.keepFrontClear = false; $0.treeClear = SIMD2(70, 40)
        },
    ]

    /// Vineyard Hills: the blocks of vines, as centre, size and the angle of the rows.
    static let vineBlocks: [(Float, Float, Float, Float, Float)] = [(-235, -200, 240, 170, 0.2), (40, -340, 260, 140, -0.15), (330, -40, 150, 170, 1.2),
                                                                     (-330, 120, 200, 180, 0.6), (250, 200, 220, 150, -0.4), (-60, 270, 240, 130, 0.1)]
    static func inVines(_ x: Float, _ z: Float) -> Bool {
        for (cx, cz, w, d, ang) in vineBlocks {
            let c = cos(ang), s = sin(ang), dx = x - cx, dz = z - cz
            if abs(dx * c - dz * s) < w / 2 + 2 && abs(dx * s + dz * c) < d / 2 + 2 { return true }
        }
        return false
    }

    /// Ski Resort: where piste `k` runs, as its x at a given z.
    static func pisteX(_ k: Int, _ z: Float) -> Float {
        switch k { case 0: return -170 + 70 * sin(z / 310); case 1: return 30 + 45 * sin(z / 250 + 1); default: return 250 + 60 * sin(z / 340 + 2.4) }
    }
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
    var ground = 1                      // what it is, for wheels and sound: 0 hard, 1 grass, 2 snow or ice, 3 sand, 4 bare earth

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
        // ---- FormationFlightX
        // 16 heather downs
        Palette(a: rgb(0.34, 0.42, 0.19), b: rgb(0.47, 0.30, 0.43), rock: rgb(0.78, 0.76, 0.7), high: rgb(0.4, 0.3, 0.4), highFrom: 60, highTo: 200,
                grassBase: rgb(0.22, 0.28, 0.12), grassTip: rgb(0.56, 0.36, 0.5), grassCount: 34000, bush: rgb(0.46, 0.26, 0.42), bushCount: 260),
        // 17 terraces
        Palette(a: rgb(0.20, 0.46, 0.16), b: rgb(0.50, 0.56, 0.24), rock: rgb(0.36, 0.3, 0.22), high: rgb(0.14, 0.32, 0.14), highFrom: 120, highTo: 300,
                grassBase: rgb(0.14, 0.32, 0.1), grassTip: rgb(0.5, 0.62, 0.22), grassCount: 38000, bush: rgb(0.16, 0.38, 0.14), bushCount: 180, flowers: false),
        // 18 karst jungle
        Palette(a: rgb(0.16, 0.38, 0.14), b: rgb(0.26, 0.46, 0.16), rock: rgb(0.42, 0.43, 0.38), high: rgb(0.2, 0.36, 0.16), highFrom: 60, highTo: 200,
                grassBase: rgb(0.1, 0.28, 0.08), grassTip: rgb(0.3, 0.5, 0.16), bush: rgb(0.12, 0.34, 0.12), bushCount: 260),
        // 19 caldera ash
        Palette(a: rgb(0.42, 0.38, 0.32), b: rgb(0.50, 0.44, 0.34), rock: rgb(0.3, 0.27, 0.25), high: rgb(0.56, 0.36, 0.26), highFrom: 60, highTo: 240,
                grassBase: rgb(0.34, 0.34, 0.2), grassTip: rgb(0.6, 0.56, 0.34), grassCount: 7000, bush: rgb(0.36, 0.38, 0.24), bushCount: 60, flowers: false, dust: rgb(0.5, 0.45, 0.38), ground: 4),
        // 20 islands
        Palette(a: rgb(0.30, 0.48, 0.20), b: rgb(0.50, 0.55, 0.26), rock: rgb(0.5, 0.46, 0.4), high: rgb(0.16, 0.36, 0.14), highFrom: 20, highTo: 50, shore: rgb(0.9, 0.85, 0.7),
                grassBase: rgb(0.16, 0.32, 0.1), grassTip: rgb(0.42, 0.56, 0.22), grassCount: 24000, bush: rgb(0.16, 0.38, 0.14), bushCount: 200, dust: rgb(0.86, 0.8, 0.66)),
        // 21 atoll
        Palette(a: rgb(0.74, 0.68, 0.50), b: rgb(0.46, 0.56, 0.28), rock: rgb(0.6, 0.56, 0.46), high: rgb(0.3, 0.46, 0.2), highFrom: 6, highTo: 14, shore: rgb(0.80, 0.74, 0.56),
                grassBase: rgb(0.3, 0.4, 0.14), grassTip: rgb(0.6, 0.64, 0.3), grassCount: 9000, bush: rgb(0.2, 0.42, 0.16), bushCount: 120, flowers: false, dust: rgb(0.92, 0.88, 0.74), ground: 3),
        // 22 badlands
        Palette(a: rgb(0.66, 0.46, 0.32), b: rgb(0.76, 0.66, 0.52), rock: rgb(0.52, 0.3, 0.25), high: rgb(0.62, 0.4, 0.32), highFrom: 20, highTo: 70,
                grassBase: rgb(0.5, 0.42, 0.26), grassTip: rgb(0.7, 0.62, 0.4), grassCount: 2500, bush: rgb(0.44, 0.44, 0.28), bushCount: 60, flowers: false, dust: rgb(0.82, 0.68, 0.5), ground: 4),
        // 23 oasis gravel
        Palette(a: rgb(0.70, 0.64, 0.52), b: rgb(0.62, 0.55, 0.44), rock: rgb(0.5, 0.42, 0.34), high: rgb(0.84, 0.66, 0.42), highFrom: 12, highTo: 40, shore: rgb(0.3, 0.48, 0.2),
                grassBase: rgb(0.4, 0.4, 0.2), grassTip: rgb(0.66, 0.62, 0.36), grassCount: 5000, bush: rgb(0.3, 0.44, 0.2), bushCount: 90, flowers: false, dust: rgb(0.76, 0.68, 0.54), ground: 4),
        // 24 lake ice
        Palette(a: rgb(0.80, 0.88, 0.95), b: rgb(0.70, 0.82, 0.93), rock: rgb(0.4, 0.41, 0.43), high: rgb(0.97, 0.98, 1.0), highFrom: 4, highTo: 30, snowCaps: true,
                grassBase: rgb(0.5, 0.5, 0.5), grassTip: rgb(0.8, 0.8, 0.8), grassCount: 0, bush: rgb(0.3, 0.3, 0.26), bushCount: 0, flowers: false, dust: rgb(0.95, 0.97, 1.0), ground: 2),
        // 25 tundra
        Palette(a: rgb(0.44, 0.38, 0.24), b: rgb(0.66, 0.66, 0.64), rock: rgb(0.36, 0.35, 0.34), high: rgb(0.9, 0.92, 0.95), highFrom: 40, highTo: 140,
                grassBase: rgb(0.34, 0.28, 0.14), grassTip: rgb(0.66, 0.56, 0.32), grassCount: 22000, bush: rgb(0.36, 0.3, 0.2), bushCount: 160, flowers: false, dust: rgb(0.8, 0.8, 0.78), ground: 2),
        // 26 outback
        Palette(a: rgb(0.72, 0.36, 0.20), b: rgb(0.62, 0.30, 0.18), rock: rgb(0.5, 0.24, 0.16), high: rgb(0.6, 0.3, 0.2), highFrom: 30, highTo: 120,
                grassBase: rgb(0.46, 0.44, 0.3), grassTip: rgb(0.7, 0.68, 0.5), grassCount: 9000, bush: rgb(0.46, 0.5, 0.4), bushCount: 160, flowers: false, dust: rgb(0.78, 0.44, 0.28), ground: 4),
        // 27 sports turf
        Palette(a: rgb(0.22, 0.46, 0.16), b: rgb(0.30, 0.52, 0.18), rock: rgb(0.42, 0.4, 0.37), high: rgb(0.16, 0.3, 0.14), highFrom: 100, highTo: 240,
                grassBase: rgb(0.16, 0.34, 0.1), grassTip: rgb(0.34, 0.54, 0.18), grassCount: 12000, bush: rgb(0.2, 0.38, 0.14), bushCount: 40, flowers: false),
        // 28 concrete
        Palette(a: rgb(0.50, 0.50, 0.49), b: rgb(0.42, 0.42, 0.42), rock: rgb(0.4, 0.4, 0.4), high: rgb(0.22, 0.34, 0.18), highFrom: 30, highTo: 120, shore: rgb(0.4, 0.4, 0.4),
                grassBase: rgb(0.3, 0.3, 0.3), grassTip: rgb(0.4, 0.4, 0.4), grassCount: 0, bush: rgb(0.2, 0.36, 0.14), bushCount: 0, flowers: false, dust: rgb(0.6, 0.6, 0.58), ground: 0),
        // 29 woodland floor
        Palette(a: rgb(0.24, 0.36, 0.14), b: rgb(0.36, 0.40, 0.16), rock: rgb(0.38, 0.37, 0.34), high: rgb(0.12, 0.24, 0.1), highFrom: 60, highTo: 200,
                grassBase: rgb(0.14, 0.26, 0.08), grassTip: rgb(0.36, 0.46, 0.16), bush: rgb(0.16, 0.3, 0.1), bushCount: 240),
        // 30 pale sandstone
        Palette(a: rgb(0.72, 0.58, 0.40), b: rgb(0.64, 0.46, 0.30), rock: rgb(0.7, 0.46, 0.28), high: rgb(0.68, 0.5, 0.34), highFrom: 30, highTo: 120,
                grassBase: rgb(0.5, 0.42, 0.24), grassTip: rgb(0.72, 0.62, 0.4), grassCount: 3000, bush: rgb(0.4, 0.44, 0.26), bushCount: 90, flowers: false, dust: rgb(0.84, 0.7, 0.5), ground: 4),
        // 31 lakeside meadow
        Palette(a: rgb(0.25, 0.40, 0.15), b: rgb(0.36, 0.46, 0.18), rock: rgb(0.42, 0.4, 0.37), high: rgb(0.16, 0.28, 0.13), highFrom: 90, highTo: 240, shore: rgb(0.62, 0.58, 0.46),
                grassBase: rgb(0.15, 0.27, 0.09), grassTip: rgb(0.36, 0.48, 0.18), bush: rgb(0.18, 0.34, 0.12), bushCount: 200),
        // 32 upland pasture
        Palette(a: rgb(0.36, 0.42, 0.19), b: rgb(0.50, 0.48, 0.24), rock: rgb(0.44, 0.42, 0.38), high: rgb(0.3, 0.34, 0.18), highFrom: 90, highTo: 240,
                grassBase: rgb(0.24, 0.28, 0.1), grassTip: rgb(0.56, 0.54, 0.26), grassCount: 30000, bush: rgb(0.3, 0.36, 0.16), bushCount: 120),
        // 33 old town: beaten earth and cobbles, green beyond the walls
        Palette(a: rgb(0.47, 0.44, 0.39), b: rgb(0.40, 0.38, 0.34), rock: rgb(0.42, 0.4, 0.37), high: rgb(0.26, 0.38, 0.16), highFrom: 5, highTo: 26, shore: rgb(0.36, 0.36, 0.3),
                grassBase: rgb(0.2, 0.3, 0.1), grassTip: rgb(0.4, 0.5, 0.2), grassCount: 0, bush: rgb(0.2, 0.36, 0.14), bushCount: 0, flowers: false, dust: rgb(0.6, 0.57, 0.5), ground: 0),
        // 34 gravel works: gravel and sand, green hills beyond
        Palette(a: rgb(0.50, 0.47, 0.39), b: rgb(0.60, 0.55, 0.43), rock: rgb(0.5, 0.48, 0.44), high: rgb(0.27, 0.38, 0.16), highFrom: 7, highTo: 30, shore: rgb(0.5, 0.5, 0.44),
                grassBase: rgb(0.24, 0.3, 0.12), grassTip: rgb(0.5, 0.52, 0.28), grassCount: 3500, bush: rgb(0.24, 0.34, 0.14), bushCount: 60, flowers: false, dust: rgb(0.66, 0.62, 0.55), ground: 4),
        // 35 works ground: worn grass and cinders
        Palette(a: rgb(0.36, 0.40, 0.25), b: rgb(0.44, 0.43, 0.37), rock: rgb(0.4, 0.4, 0.4), high: rgb(0.22, 0.34, 0.16), highFrom: 20, highTo: 100,
                grassBase: rgb(0.2, 0.28, 0.1), grassTip: rgb(0.44, 0.48, 0.22), grassCount: 9000, bush: rgb(0.2, 0.34, 0.14), bushCount: 40, flowers: false, dust: rgb(0.55, 0.54, 0.5)),
        // 36 vineyard country
        Palette(a: rgb(0.34, 0.47, 0.18), b: rgb(0.50, 0.52, 0.24), rock: rgb(0.55, 0.48, 0.38), high: rgb(0.28, 0.4, 0.17), highFrom: 80, highTo: 200,
                grassBase: rgb(0.3, 0.33, 0.12), grassTip: rgb(0.66, 0.62, 0.3), grassCount: 30000, bush: rgb(0.28, 0.38, 0.16), bushCount: 140),
        // 37 airfield grass
        Palette(a: rgb(0.30, 0.42, 0.18), b: rgb(0.42, 0.47, 0.22), rock: rgb(0.44, 0.42, 0.38), high: rgb(0.18, 0.3, 0.14), highFrom: 60, highTo: 200, shore: rgb(0.78, 0.72, 0.56),
                grassBase: rgb(0.2, 0.3, 0.1), grassTip: rgb(0.46, 0.52, 0.22), grassCount: 16000, bush: rgb(0.2, 0.36, 0.14), bushCount: 60, flowers: false),
        // 38 glacier valley
        Palette(a: rgb(0.27, 0.44, 0.17), b: rgb(0.40, 0.50, 0.21), rock: rgb(0.43, 0.42, 0.41), high: rgb(0.94, 0.96, 0.99), highFrom: 430, highTo: 640, snowCaps: true, rockFrom: 150, rockTo: 420, shore: rgb(0.6, 0.6, 0.56),
                grassBase: rgb(0.15, 0.28, 0.1), grassTip: rgb(0.38, 0.5, 0.2), bush: rgb(0.16, 0.3, 0.14)),
        // 39 clifftop turf
        Palette(a: rgb(0.30, 0.44, 0.18), b: rgb(0.44, 0.48, 0.22), rock: rgb(0.40, 0.37, 0.33), high: rgb(0.2, 0.32, 0.15), highFrom: 40, highTo: 140, shore: rgb(0.34, 0.32, 0.29),
                grassBase: rgb(0.2, 0.3, 0.1), grassTip: rgb(0.48, 0.54, 0.24), grassCount: 30000, bush: rgb(0.24, 0.34, 0.14), bushCount: 140, dust: rgb(0.6, 0.56, 0.46)),
        // 40 red mesa country
        Palette(a: rgb(0.70, 0.38, 0.24), b: rgb(0.62, 0.31, 0.19), rock: rgb(0.55, 0.25, 0.15), high: rgb(0.62, 0.3, 0.19), highFrom: 30, highTo: 120,
                grassBase: rgb(0.46, 0.42, 0.26), grassTip: rgb(0.7, 0.64, 0.42), grassCount: 5000, bush: rgb(0.42, 0.46, 0.3), bushCount: 130, flowers: false, dust: rgb(0.78, 0.45, 0.28), ground: 4),
        // 41 ski slopes
        Palette(a: rgb(0.92, 0.94, 0.98), b: rgb(0.85, 0.88, 0.95), rock: rgb(0.38, 0.39, 0.42), high: rgb(0.97, 0.98, 1.0), highFrom: 200, highTo: 500, snowCaps: true,
                grassBase: rgb(0.45, 0.38, 0.22), grassTip: rgb(0.7, 0.62, 0.4), grassCount: 0, bush: rgb(0.3, 0.3, 0.26), bushCount: 20, flowers: false, dust: rgb(0.95, 0.96, 0.98), ground: 2),
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
    /// Level ground with nothing on it, for test flights that need no scenery.
    static let flat: Terrain = {
        var s = SiteSpec.builtIn[0]
        s.terrain = 31; s.treeCount = 0; s.layout = 0; s.waterLevel = nil
        return Terrain(site: s)
    }()
    let n = 385
    let cell: Float = 16
    let half: Float
    var h: [Float]
    let site: SiteSpec
    var trees: [Tree] = []
    var boxes: [SolidBox] = []          // everything built here that a wing can hit
    var gates: [Gate] = []              // race gates, in the order they are flown
    var decor = MeshBuilder()           // what is built here that is only looked at: roofs, cables, lamps, markings

    init(site: SiteSpec) {
        self.site = site
        half = Float(n - 1) * cell / 2
        h = [Float](repeating: 0, count: n * n)
        for j in 0..<n { for i in 0..<n {
            h[j * n + i] = raw(Float(i) * cell - half, Float(j) * cell - half)
        } }
        placeTrees()
        layoutStructures()
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
        // ---- FormationFlightX landscapes
        case 20:    // downland: long smooth ridges
            y = 38 * (fbm(x / 900, z / 900, s) - 0.45) + 15 * sin(x / 260 + 3 * fbm(x / 700, z / 700, s + 2)) * smoothstep(150, 500, r)
            y += smoothstep(1500, 2900, r) * 250 * fbm(x / 1400, z / 1400, s + 3)
        case 21:    // terraced hillside: rising behind the pilots, falling in front, in three-metre steps
            let slope = 80 * smoothstep(60, 900, z) * (0.4 + fbm(x / 500, z / 500, s)) - 46 * smoothstep(40, 700, -z) * (0.3 + fbm(x / 500, z / 500, s + 3))
            let step = floor(slope / 3), frac = slope / 3 - step
            y = (step + smoothstep(0.82, 1, frac)) * 3
            y += smoothstep(1400, 2900, r) * 520 * fbm(x / 1300, z / 1300, s + 5)
        case 22:    // karst: a level valley floor with rock towers standing out of it
            y = 3 * (fbm(x / 300, z / 300, s) - 0.5)
            y += 190 * smoothstep(0.6, 0.71, fbm(x / 170, z / 170, s + 5)) * smoothstep(210, 400, r) * (0.55 + 0.9 * fbm(x / 70, z / 70, s + 8))
            y += smoothstep(1500, 2900, r) * 300 * fbm(x / 1200, z / 1200, s + 3)
        case 23:    // caldera: a crater floor inside a ring wall
            let d = r + 90 * (fbm(x / 500, z / 500, s + 4) - 0.5)
            y = 6 * (fbm(x / 200, z / 200, s) - 0.5) + 290 * exp(-pow((d - 950) / 280, 2)) * (0.75 + 0.5 * fbm(x / 300, z / 300, s + 6))
            y += 60 * smoothstep(1300, 2600, d)
        case 24:    // archipelago: a main island and a scatter of smaller ones in shallow sea
            let main = smoothstep(390, 240, sqrt(x * x * 0.5 + (z - 40) * (z - 40)) + 70 * (fbm(x / 400, z / 400, s + 9) - 0.5))
            let isl = max(main, smoothstep(0.585, 0.66, fbm(x / 430, z / 430, s + 6)) * smoothstep(300, 520, r))
            y = (3 + 34 * fbm(x / 260, z / 260, s) * smoothstep(100, 420, r)) * isl - 9 * (1 - isl) - 12 * (1 - isl) * smoothstep(0.5, 0.35, fbm(x / 600, z / 600, s + 2))
        case 25:    // atoll: a ring of coral round a shallow lagoon, the pilots standing on the ring
            let rr = sqrt(x * x + (z + 330) * (z + 330))
            let d = abs(rr - 330) + 22 * (fbm(x / 160, z / 160, s + 4) - 0.5)
            let land = smoothstep(58, 26, d)
            y = lerp(rr < 330 ? -3.4 : -22 * smoothstep(0, 260, rr - 330) - 3, 2.2 + 2.5 * fbm(x / 90, z / 90, s), land)
        case 26:    // badlands: gullied clay hills
            let rd = 1 - abs(2 * fbm(x / 250, z / 250, s) - 1)
            y = 78 * rd * rd * smoothstep(110, 480, r) + 6 * (fbm(x / 60, z / 60, s + 7) - 0.5) * smoothstep(110, 300, r)
            y += smoothstep(1300, 2600, r) * 200 * smoothstep(0.5, 0.62, fbm(x / 1000, z / 1000, s + 5))
        case 27:    // oasis: gravel plain, a pool to the front left, dunes far off
            y = 2.4 * (fbm(x / 280, z / 280, s) - 0.5)
            let rd = 1 - abs(2 * fbm(x / 420, z / 700, s + 3) - 1)
            y += smoothstep(600, 1700, r) * 55 * rd * rd
            let dp = sqrt((x + 110) * (x + 110) + (z + 170) * (z + 170)) + 30 * (fbm(x / 120, z / 120, s + 9) - 0.5)
            y = lerp(y, -7, smoothstep(105, 50, dp))
        case 28:    // frozen lake: level ice, wooded shores, peaks behind
            let e = smoothstep(430, 900, r + 130 * (fbm(x / 500, z / 500, s + 3) - 0.5))
            let rd = 1 - abs(2 * fbm(x / 1500, z / 1500, s + 11) - 1)
            y = e * (34 + 18 * fbm(x / 300, z / 300, s)) + smoothstep(1000, 2600, r) * 760 * rd * rd
        case 29:    // tundra: low swells, hollows that hold meltwater
            y = 14 * (fbm(x / 520, z / 520, s) - 0.5) + 3 * (fbm(x / 90, z / 90, s + 7) - 0.5)
            y -= 7 * smoothstep(0.62, 0.76, fbm(x / 340, z / 340, s + 8))
            y += smoothstep(1600, 2900, r) * 150 * fbm(x / 1500, z / 1500, s + 3)
        case 30:    // outback plain with far mesas
            y = 3 * (fbm(x / 600, z / 600, s) - 0.5)
            y += smoothstep(1400, 2600, r) * 190 * smoothstep(0.55, 0.65, fbm(x / 900, z / 900, s + 5))
        case 31:    // level ground with hills well away: sports field, yard, city
            y = 1.2 * (fbm(x / 400, z / 400, s) - 0.5)
            y += smoothstep(1500, 2900, r) * 230 * fbm(x / 1400, z / 1400, s + 3)
        case 32:    // gently rolling woodland
            y = 16 * (fbm(x / 500, z / 500, s) - 0.45) + 3 * (fbm(x / 120, z / 120, s + 7) - 0.5)
            y += smoothstep(1300, 2900, r) * 280 * fbm(x / 1400, z / 1400, s + 3)
        case 33:    // mesa with a winding canyon across the front (the race follows it)
            y = 3 * (fbm(x / 250, z / 250, s) - 0.5)
            let c = abs(z - (-170 + 80 * sin(x / 210)))
            y -= 62 * smoothstep(78, 26, c) * smoothstep(780, 640, abs(x)) * (0.9 + 0.2 * fbm(x / 80, z / 80, s + 6))
            y += smoothstep(1100, 2200, r) * 230 * smoothstep(0.5, 0.62, fbm(x / 1100, z / 1100, s + 5))
        case 34:    // harbour: level quay, then the sea; hills inland
            y = 1.5 - 17 * smoothstep(232, 262, -z + 14 * (fbm(x / 300, 0.5, s + 5) - 0.5))
            y += 140 * smoothstep(420, 1500, z) * fbm(x / 700, z / 700, s + 3)
        case 36:    // lakeside: meadow and woods round a lake in front of the pilots
            y = 16 * (fbm(x / 600, z / 600, s) - 0.42) + 3 * (fbm(x / 130, z / 130, s + 7) - 0.5)
            y += smoothstep(1300, 2900, r) * 300 * fbm(x / 1400, z / 1400, s + 3)
            let dl = sqrt(x * x / (185 * 185) + (z + 270) * (z + 270) / (120 * 120)) + 0.14 * (fbm(x / 90, z / 90, s + 9) - 0.5)
            y = lerp(-7, max(y, 0.5), smoothstep(0.88, 1.2, dl))
        case 37:    // upland: broad open swells
            y = 34 * (fbm(x / 760, z / 760, s) - 0.45) + 5 * (fbm(x / 170, z / 170, s + 7) - 0.5)
            y += smoothstep(1500, 2900, r) * 220 * fbm(x / 1400, z / 1400, s + 3)
        case 38:    // old town: level ground, a river across the front, farmland and hills beyond
            y = 1.0 * (fbm(x / 400, z / 400, s) - 0.5)
            let dr = abs(z + 262 - 18 * sin(x / 170))
            y -= 6.5 * smoothstep(34, 16, dr)
            y += smoothstep(700, 2600, r) * 190 * fbm(x / 1100, z / 1100, s + 3)
        case 39:    // gravel works: a level yard, a pit dug in benches to the left
            y = 2 * (fbm(x / 300, z / 300, s) - 0.5)
            y += smoothstep(500, 2200, r) * 150 * fbm(x / 900, z / 900, s + 3)
            let dp = sqrt((x + 400) * (x + 400) + (z + 170) * (z + 170)) + 30 * (fbm(x / 110, z / 110, s + 9) - 0.5)
            let t = clampf((185 - dp) / 135, 0, 1) * 4
            y = lerp(y, y - 6 * (floor(t) + smoothstep(0.7, 1, t - floor(t))), smoothstep(200, 185, dp))
        case 40:    // vineyard hills
            y = 52 * (fbm(x / 520, z / 520, s) - 0.45) + 6 * (fbm(x / 130, z / 130, s + 7) - 0.5)
            y += smoothstep(1500, 2900, r) * 240 * fbm(x / 1300, z / 1300, s + 3)
        case 41:    // airport plain, the sea beyond the far side of the runway
            y = 5 * (fbm(x / 900, z / 900, s) - 0.5) + 170 * smoothstep(700, 2600, z) * fbm(x / 1100, z / 1100, s + 3)
            y -= 22 * smoothstep(430, 620, -z + 60 * (fbm(x / 500, 0.3, s + 5) - 0.5))
        case 42:    // glacier valley: a flat floor between high walls, climbing to the ice at its head
            let side = abs(x - 70 * sin(z / 600))
            y = 6 * (fbm(x / 140, z / 140, s + 7) - 0.5)
            y += 780 * pow(smoothstep(170, 1000, side), 1.15) * (0.55 + 0.9 * fbm(x / 520, z / 520, s))
            y += 0.1 * max(-z - 250, 0) + 380 * smoothstep(900, 2600, -z) * (0.5 + fbm(x / 600, z / 600, s + 4))
            y += 300 * smoothstep(500, 2400, z) * fbm(x / 700, z / 700, s + 3)
            let dl = sqrt((x + 130) * (x + 130) + (z + 250) * (z + 250)) + 26 * (fbm(x / 90, z / 90, s + 9) - 0.5)
            y = lerp(y, -8, smoothstep(105, 55, dl))
        case 43:    // clifftop: turf above the sea, a point of land running out to the right
            let edge = -z - 135 - 150 * exp(-pow((x - 190) / 110, 2)) + 55 * (fbm(x / 260, 0.4, s + 5) - 0.5)    // positive out at sea
            y = 5 * (fbm(x / 240, z / 240, s) - 0.5) + 50 * smoothstep(250, 1300, z) * fbm(x / 600, z / 600, s + 3)
            y = lerp(y, -34 - 10 * smoothstep(20, 400, edge), smoothstep(-8, 14, edge))
        case 44:    // red plain with buttes standing on it
            y = 3 * (fbm(x / 300, z / 300, s) - 0.5)
            for b in [(Float(-700), Float(-420), Float(160), Float(180)), (680, -560, 190, 210), (120, -1050, 140, 160), (-250, -1000, 110, 150),
                      (-900, 300, 220, 190), (850, 250, 170, 180), (-200, 800, 250, 200)] {
                let d = sqrt((x - b.0) * (x - b.0) + (z - b.1) * (z - b.1)) + 34 * (fbm(x / 70, z / 70, s + 6) - 0.5)
                y += b.3 * smoothstep(b.2 + 30, b.2 - 6, d) * (0.92 + 0.16 * fbm(x / 160, z / 160, s + 2)) + 34 * smoothstep(b.2 + 170, b.2 + 20, d)
            }
            y += smoothstep(1300, 2500, r) * 210 * smoothstep(0.52, 0.62, fbm(x / 900, z / 900, s + 5))
        case 45:    // ski mountain: the slope rises in front, ridges either side
            let up = max(-z - 110, 0)
            y = 560 * smoothstep(0, 1700, up) * (0.75 + 0.5 * fbm(x / 700, z / 700, s)) + 16 * (fbm(x / 160, z / 160, s + 7) - 0.5) * smoothstep(0, 300, up)
            y += 300 * smoothstep(500, 2200, abs(x)) * fbm(x / 600, z / 600, s + 3) + 120 * smoothstep(300, 1800, z) * fbm(x / 800, z / 800, s + 5)
        default:    // forest floor
            y = 24 * (fbm(x / 600, z / 600, s) - 0.45) + 4 * (fbm(x / 120, z / 120, s + 7) - 0.5)
            y += smoothstep(1300, 2900, r) * 300 * fbm(x / 1400, z / 1400, s + 3)
        }
        let dx = max(abs(x) - (site.flatHalfX ?? (site.runwayLen / 2 + 25)), 0), dz = max(abs(z - site.flatCenterZ) - site.flatHalfZ, 0)
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
        if pal >= 16 { return [(0.03, 0.85, 0.002), (0.09, 0.6, 0.02), (0.12, 0.3, 0.015), (0.16, 0.45, 0.02), (0.07, 0.55, 0.012)][min(max(site.pal.ground, 0), 4)] }
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
        if pal >= 16 { return site.pal.ground }
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
            let x = rng.range(-site.treeRange, site.treeRange), z = rng.range(-site.treeRange, site.treeRange)
            if site.terrain == 42 && z < -640 && abs(x - 70 * sin(z / 600)) < 330 { continue }                                  // not on the glacier or its moraine
            if site.terrain == 39 && (x + 400) * (x + 400) + (z + 170) * (z + 170) < 250 * 250 { continue }                     // not in the pit
            if site.layout == 13 && SiteSpec.inVines(x, z) { continue }
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
            c = paint(c, x, z, y, v)
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

    /// What people have done to the ground: fields of different crops, flooded paddies, a quarry's bare benches,
    /// groomed pistes, and the ice of a glacier.
    private func paint(_ c0: V4, _ x: Float, _ z: Float, _ y: Float, _ v: Float) -> V4 {
        var c = c0
        let s = site.seed, r = sqrt(x * x + z * z)
        var farmland: Float? = nil
        if site.terrain == 38 {
            // inside the walls the ground is paved; outside it is meadow, and then fields
            let town = (1 - smoothstep(345, 362, abs(x))) * smoothstep(-228, -214, z) * (1 - smoothstep(150, 166, z))
            c = mix(mix(rgb(0.28, 0.42, 0.16), rgb(0.38, 0.47, 0.19), v), c, town)
            farmland = (1 - town) * smoothstep(20, 60, abs(z + 262 - 18 * sin(x / 170)))
        }
        if site.patchwork {
            // plots some 150 m across with wandering edges, each under its own crop
            let u = x + 70 * (fbm(x / 400, z / 400, s + 61) - 0.5), w = z + 70 * (fbm(x / 400, z / 400, s + 67) - 0.5)
            let k = hash2(Int32(floor(u / 170)), Int32(floor(w / 130)), s + 71)
            let crop = k < 0.2 ? rgb(0.62, 0.56, 0.26) : k < 0.4 ? rgb(0.24, 0.42, 0.14) : k < 0.55 ? rgb(0.44, 0.34, 0.22) : k < 0.7 ? rgb(0.4, 0.5, 0.18) : c
            let far = (farmland ?? smoothstep(site.runwayLen / 2 + 150, site.runwayLen / 2 + 420, r)) * smoothstep(110, 40, y) * (1 - smoothstep(0.9, 0.75, normalAt(x, z)))
            c = mix(c, crop, 0.7 * far)
        }
        switch site.terrain {
        case 21:    // terraces: every other step is a flooded paddy, the sky in it
            let step = Int(floor((y + 1.5) / 3))
            if step % 2 != 0 && abs(y) > 2 { c = mix(c, rgb(0.34, 0.44, 0.42), 0.6) }
        case 39:    // the pit: bare gravel and rock
            if y < -2.5 { c = mix(rgb(0.56, 0.53, 0.46), rgb(0.42, 0.41, 0.38), v) }
        case 42:    // the glacier at the head of the valley, grey moraine in front of it
            let side = abs(x - 70 * sin(z / 600))
            let ice = smoothstep(760, 900, -z + 90 * (fbm(x / 200, z / 200, s + 13) - 0.5)) * smoothstep(300, 210, side)
            let crev = fbm(x / 40, z / 150, s + 17)
            c = mix(c, rgb(0.5, 0.5, 0.48), smoothstep(640, 760, -z) * smoothstep(330, 230, side) * (1 - ice))
            c = mix(c, mix(rgb(0.86, 0.92, 0.96), rgb(0.5, 0.74, 0.86), smoothstep(0.55, 0.7, crev)), ice)
        case 40:    // bare earth between the rows of vines
            if SiteSpec.inVines(x, z) { c = mix(rgb(0.62, 0.53, 0.36), rgb(0.54, 0.47, 0.32), v) }
        case 45:    // off the pistes the snow lies blue in the shade of the forest
            var piste: Float = 0
            for k in 0..<3 where z < -90 { piste = max(piste, smoothstep(26, 14, abs(x - SiteSpec.pisteX(k, z)))) }
            c = mix(mix(rgb(0.80, 0.85, 0.93), rgb(0.72, 0.79, 0.90), v), rgb(1, 1, 1), max(piste, smoothstep(-60, -110, -z)))
        default: break
        }
        return c
    }
    private func normalAt(_ x: Float, _ z: Float) -> Float { normal(x, z).y }

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
