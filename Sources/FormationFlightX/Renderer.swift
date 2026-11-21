import MetalKit
import simd
import AppKit

struct FrameUniforms {
    var viewProj = M4.identity, invViewProj = M4.identity, shadow0 = M4.identity, shadow1 = M4.identity
    var camPos = V4.zero, sunDir = V4.zero, sunColor = V4.zero, zenith = V4.zero, horizon = V4.zero, runway = V4.zero, ambient = V4.zero
    var post = V4(0, 1, 0.85, 0.3), screen = V4(0, 0, 4096, 1)
    var pano = V4.zero
}
struct DrawUniforms { var model = M4.identity; var tint = V4(1, 1, 1, 1); var params = V4.zero }

struct DrawItem { var mesh: GPUMesh; var model: M4; var tint = V4(1, 1, 1, 1); var material: Float = 0; var spec: Float = 0; var wind = SIMD2<Float>(0, 0) }

struct GPUChunk { var mesh: GPUMesh; var center: V3; var radius: Float }

/// Everything the GPU needs to draw a 3D site. Built off the main thread when the site changes: buffers can be made
/// on any thread, and the landscape and its meshes are plain data.
final class SiteGPU {
    var terrain: GPUMesh?, scenery: GPUMesh?, treeShadows: GPUMesh?, water: GPUMesh?
    var vegetation: [GPUChunk] = [], grass: [GPUChunk] = []
    init(_ device: MTLDevice, _ t: Terrain) {
        terrain = GPUMesh(device, t.buildMesh())
        var scenery = t.buildScenery()
        t.buildStructureMesh(into: &scenery)
        self.scenery = GPUMesh(device, scenery)
        func upload(_ b: MeshBuilder, _ cell: Float) -> [GPUChunk] {
            chunked(b, cell: cell).compactMap { c in GPUMesh(device, c.mesh).map { GPUChunk(mesh: $0, center: c.center, radius: c.radius) } }
        }
        vegetation = upload(t.buildVegetation(), 150)
        grass = upload(t.buildGrass(), 30)
        treeShadows = GPUMesh(device, t.buildTreeShadows())
        water = GPUMesh(device, t.buildWater())
    }
}

/// Forward renderer with an HDR post-processing chain (see Shaders.swift for the frame layout).
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let game: Game

    // pipelines
    private var scenePSO: MTLRenderPipelineState!        // HDR, 4x MSAA
    private var sceneLDR: MTLRenderPipelineState!        // straight to 8-bit, for thumbnails
    private var skyPSO: MTLRenderPipelineState!
    private var skyBlitPSO: MTLRenderPipelineState!
    private var panoPSO: MTLRenderPipelineState!
    private var shadowPSO: MTLRenderPipelineState!
    private var aoPSO: MTLRenderPipelineState!
    private var aoBlurPSO: MTLRenderPipelineState!
    private var bloomPrePSO: MTLRenderPipelineState!
    private var bloomDownPSO: MTLRenderPipelineState!
    private var compositePSO: MTLRenderPipelineState!
    private var depthMain: MTLDepthStencilState!
    private var depthOff: MTLDepthStencilState!
    private var depthRead: MTLDepthStencilState!
    private var depthShadow: MTLDepthStencilState!
    private var shadowSampler: MTLSamplerState!
    private var pointSampler: MTLSamplerState!
    private var linearSampler: MTLSamplerState!
    private var panoSampler: MTLSamplerState!

    // render targets
    private var shadowTex: [MTLTexture] = []
    private let shadow1Size = 4096
    private var hdrMS: MTLTexture?, depthMS: MTLTexture?, hdr: MTLTexture?, depth: MTLTexture?
    private var aoTex: MTLTexture?, aoBlur: MTLTexture?, white: MTLTexture?, skyTex: MTLTexture?
    private var dynScale: Float = 1          // automatic resolution scale, lowered when the GPU falls behind
    private var gpuMs: Float = 8, frameMs: Float = 16.7
    private var timeDebt: Double = 0
    // pacing statistics for --perf: frame intervals and CPU time per frame over the last second
    var statIntervals: [Float] = [], statCpu: [Float] = [], statPresented: [Float] = []
    private var lastPresented: CFTimeInterval = 0
    private var missed: Float = 0            // recent fraction of frames that reached the screen late
    private var lastScaleChange = CACurrentMediaTime()
    private var bloom: [MTLTexture] = []
    private var targetSize = (0, 0)

    // scene
    private var panoTex: MTLTexture?
    private var panoDetail: Float = 1           // 0 soft photograph ... 1 pin sharp
    private var lastDetail: Float = 0.7
    private var catcherMesh: GPUMesh?
    private var terrainMesh: GPUMesh?
    private var sceneryMesh: GPUMesh?
    private var vegetation: [GPUChunk] = []
    private var grass: [GPUChunk] = []
    private var treeShadowMesh: GPUMesh?
    private var waterMesh: GPUMesh?
    private var windsockMesh: GPUMesh?
    private var balloonMesh: GPUMesh?
    private var partMeshes: [GPUMesh?] = []
    private var fleetMeshes: [String: [GPUMesh?]] = [:]         // the other pilots' models, by aircraft name
    private var slotMesh: GPUMesh?
    private var panelMesh: GPUMesh?         // a unit square, for lighting up the next race gate
    private var siteVersion = -1, aircraftVersion = -1
    private var shadow1Key = -1
    private var lastTime = CACurrentMediaTime()

    // screenshot support (used for automated verification)
    var shotPath: String?
    var shotAfter: Double = 2
    private var startTime = CACurrentMediaTime()

    private let hdrFormat = MTLPixelFormat.rgba16Float
    // profiling switches for the command line
    static let debugScale: Float? = { let a = CommandLine.arguments; if let i = a.firstIndex(of: "--scale"), i + 1 < a.count { return Float(a[i + 1]) }; return nil }()
    static let debugOff = Set(CommandLine.arguments.filter { $0.hasPrefix("--no-") }.map { String($0.dropFirst(5)) })
    private let bloomFormat = MTLPixelFormat.rg11b10Float

    init?(view: MTKView, game: Game) {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else { return nil }
        device = dev; queue = q; self.game = game
        super.init()
        view.device = dev
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid          // the scene has its own depth target; the drawable only receives the composite
        view.sampleCount = 1
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 120
        do { try build(view) } catch { NSLog("Metal setup failed: \(error)"); return nil }
        balloonMesh = { var b = MeshBuilder(); b.ellipsoid(center: .zero, radii: V3(0.6, 0.72, 0.6), color: rgb(1, 1, 1), seg: 12, rings: 8)
            b.cylinder(from: V3(0, -0.7, 0), to: V3(0, -0.82, 0), r0: 0.03, r1: 0.07, seg: 6, color: rgb(1, 1, 1)); return GPUMesh(dev, b) }()
        windsockMesh = GPUMesh(dev, buildWindsock())
        panelMesh = { var b = MeshBuilder(); b.quad(V3(-0.5, -0.5, 0), V3(0.5, -0.5, 0), V3(0.5, 0.5, 0), V3(-0.5, 0.5, 0), rgb(1, 1, 1)); return GPUMesh(dev, b) }()
        slotMesh = {
            // a ring facing along the flight path, one unit in radius, with four ticks pointing at its centre
            var b = MeshBuilder()
            let n = 48, white = rgb(1, 1, 1)
            func p(_ a: Float, _ r: Float) -> V3 { V3(cos(a) * r, sin(a) * r, 0) }
            for k in 0..<n {
                let a0 = Float(k) / Float(n) * 2 * .pi, a1 = Float(k + 1) / Float(n) * 2 * .pi
                b.quad(p(a0, 0.94), p(a0, 1.0), p(a1, 1.0), p(a1, 0.94), white)
            }
            for k in 0..<4 {
                let a = Float(k) * .pi / 2, w: Float = 0.025
                b.quad(p(a - w, 1.0), p(a + w, 1.0), p(a + w * 1.4, 0.72), p(a - w * 1.4, 0.72), white)
            }
            return GPUMesh(dev, b)
        }()
        game.hud.thumbnailer = { [unowned self] spec in self.thumbnail(for: spec) }
        let siteDevice = device
        game.siteBuilder = { t in SiteGPU(siteDevice, t) }
    }

    private func build(_ view: MTKView) throws {
        let lib = try device.makeLibrary(source: shaderSource, options: nil)
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float3; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float4; vd.attributes[2].offset = 24; vd.attributes[2].bufferIndex = 0
        vd.layouts[0].stride = 40

        func scene(_ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let sd = MTLRenderPipelineDescriptor()
            sd.vertexFunction = lib.makeFunction(name: "sceneVS"); sd.fragmentFunction = lib.makeFunction(name: "sceneFS")
            sd.vertexDescriptor = vd
            sd.colorAttachments[0].pixelFormat = format
            sd.depthAttachmentPixelFormat = .depth32Float
            sd.rasterSampleCount = 4
            sd.colorAttachments[0].isBlendingEnabled = true
            sd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            sd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            sd.colorAttachments[0].sourceAlphaBlendFactor = .one
            sd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: sd)
        }
        scenePSO = try scene(hdrFormat)
        sceneLDR = try scene(.bgra8Unorm_srgb)

        func fullscreen(_ fragment: String, _ format: MTLPixelFormat, samples: Int = 1, depth: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "skyVS"); d.fragmentFunction = lib.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            d.rasterSampleCount = samples
            if depth { d.depthAttachmentPixelFormat = .depth32Float }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        skyPSO = try fullscreen("skyFS", bloomFormat)
        skyBlitPSO = try fullscreen("skyBlitFS", hdrFormat, samples: 4, depth: true)
        panoPSO = try fullscreen("panoFS", hdrFormat, samples: 4, depth: true)
        aoPSO = try fullscreen("aoFS", .r8Unorm)
        aoBlurPSO = try fullscreen("aoBlurFS", .r8Unorm)
        bloomPrePSO = try fullscreen("bloomPreFS", bloomFormat)
        bloomDownPSO = try fullscreen("bloomDownFS", bloomFormat)
        compositePSO = try fullscreen("compositeFS", view.colorPixelFormat)

        let hd = MTLRenderPipelineDescriptor()
        hd.vertexFunction = lib.makeFunction(name: "shadowVS")
        hd.vertexDescriptor = vd
        hd.depthAttachmentPixelFormat = .depth32Float
        shadowPSO = try device.makeRenderPipelineState(descriptor: hd)

        func depthState(_ f: MTLCompareFunction, _ write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = f; d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        depthMain = depthState(.greaterEqual, true)       // reverse-Z
        depthOff = depthState(.always, false)
        depthRead = depthState(.greaterEqual, false)
        depthShadow = depthState(.lessEqual, true)

        let smp = MTLSamplerDescriptor()
        smp.minFilter = .linear; smp.magFilter = .linear; smp.compareFunction = .lessEqual
        smp.sAddressMode = .clampToEdge; smp.tAddressMode = .clampToEdge
        shadowSampler = device.makeSamplerState(descriptor: smp)
        let ps = MTLSamplerDescriptor()
        ps.minFilter = .nearest; ps.magFilter = .nearest; ps.sAddressMode = .clampToEdge; ps.tAddressMode = .clampToEdge
        pointSampler = device.makeSamplerState(descriptor: ps)
        let ls = MTLSamplerDescriptor()
        ls.minFilter = .linear; ls.magFilter = .linear; ls.sAddressMode = .clampToEdge; ls.tAddressMode = .clampToEdge
        linearSampler = device.makeSamplerState(descriptor: ls)
        let pd = MTLSamplerDescriptor()
        pd.minFilter = .linear; pd.magFilter = .linear; pd.mipFilter = .linear; pd.maxAnisotropy = 8
        pd.sAddressMode = .repeat; pd.tAddressMode = .clampToEdge
        panoSampler = device.makeSamplerState(descriptor: pd)

        func shadowMap(_ size: Int) -> MTLTexture {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: size, height: size, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
            return device.makeTexture(descriptor: td)!
        }
        shadowTex = [shadowMap(2048), shadowMap(shadow1Size)]

        let wd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
        white = device.makeTexture(descriptor: wd)
        var one: UInt8 = 255
        white?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &one, bytesPerRow: 1)

        var cm = MeshBuilder()
        cm.quad(V3(-600, 0, 600), V3(600, 0, 600), V3(600, 0, -600), V3(-600, 0, -600), rgb(1, 1, 1))
        catcherMesh = GPUMesh(device, cm)
    }

    /// (Re)create the off-screen targets for a render size.
    private func makeTargets(_ w: Int, _ h: Int) {
        guard targetSize != (w, h) else { return }
        targetSize = (w, h)
        func tex(_ format: MTLPixelFormat, _ w: Int, _ h: Int, samples: Int = 1) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(w, 1), height: max(h, 1), mipmapped: false)
            if samples > 1 { d.textureType = .type2DMultisample; d.sampleCount = samples; d.usage = .renderTarget }
            else { d.usage = [.renderTarget, .shaderRead] }
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        hdrMS = tex(hdrFormat, w, h, samples: 4)
        depthMS = tex(.depth32Float, w, h, samples: 4)
        hdr = tex(hdrFormat, w, h)
        depth = tex(.depth32Float, w, h)
        aoTex = tex(.r8Unorm, w / 2, h / 2)
        aoBlur = tex(.r8Unorm, w / 2, h / 2)
        skyTex = tex(bloomFormat, w / 2, h / 2)
        bloom = (1...5).compactMap { tex(bloomFormat, w >> $0, h >> $0) }
    }

    private func syncMeshes() {
        let t0 = CACurrentMediaTime(), sv = siteVersion, av = aircraftVersion
        defer { let d = (CACurrentMediaTime() - t0) * 1000; if Game.timing && (sv != siteVersion || av != aircraftVersion) { print(String(format: "TIMING renderer rebuild %.0f ms (site %@, aircraft %@)", d, sv != siteVersion ? "yes" : "no", av != aircraftVersion ? "yes" : "no")); fflush(stdout) } }
        if siteVersion != game.siteVersion {
            siteVersion = game.siteVersion
            shadow1Key = -1
            panoTex = nil
            if let url = game.site.panorama {
                terrainMesh = nil; sceneryMesh = nil; vegetation = []; grass = []; treeShadowMesh = nil; waterMesh = nil
                if let img = Panoramas.image(url, maxSize: 8192) { panoTex = makeTexture(img); panoDetail = clampf((lastDetail - 0.4) / 0.35, 0, 1) }
                if panoTex == nil { game.say("Could not load panorama image", 6) }
            } else {
                // built in the background with the landscape when the site was chosen; otherwise (the first site) now
                let g = (game.preparedSite as? SiteGPU) ?? SiteGPU(device, game.terrain)
                game.preparedSite = nil
                terrainMesh = g.terrain; sceneryMesh = g.scenery; vegetation = g.vegetation; grass = g.grass
                treeShadowMesh = g.treeShadows; waterMesh = g.water
            }
        }
        if aircraftVersion != game.aircraftVersion {
            aircraftVersion = game.aircraftVersion
            partMeshes = game.aircraft.spec.parts.map { GPUMesh(device, $0.mesh) }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func drawItems(_ enc: MTLRenderCommandEncoder, _ items: [DrawItem], fragment: Bool) {
        for it in items {
            var du = DrawUniforms(model: it.model, tint: it.tint, params: V4(it.material, it.spec, it.wind.x, it.wind.y))
            enc.setVertexBytes(&du, length: MemoryLayout<DrawUniforms>.stride, index: 2)
            if fragment { enc.setFragmentBytes(&du, length: MemoryLayout<DrawUniforms>.stride, index: 2) }
            enc.setVertexBuffer(it.mesh.buffer, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: it.mesh.count)
        }
    }

    /// One full-screen post-processing pass into `target`.
    private func post(_ cb: MTLCommandBuffer, _ pso: MTLRenderPipelineState, to target: MTLTexture, _ textures: [MTLTexture?], _ fu: inout FrameUniforms) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pso)
        enc.setFragmentBytes(&fu, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
        enc.setFragmentSamplerState(linearSampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        frameMs += (Float(now - lastTime) * 1000 - frameMs) * 0.08
        statIntervals.append(Float(now - lastTime) * 1000)
        defer { statCpu.append(Float(CACurrentMediaTime() - now) * 1000) }
        // Frames reach the screen exactly one refresh apart, but this callback's timing wobbles by up to a
        // millisecond. Step the simulation by whole refresh periods so motion is even, and keep a running
        // account of the difference so simulated time never drifts from real time.
        let raw = now - lastTime
        let period = 1 / Double(max(view.window?.screen?.maximumFramesPerSecond ?? 60, 30))
        let k = (raw / period).rounded()
        var step = raw
        if k >= 1 && k <= 4 && abs(raw - k * period) < 0.3 * period && !Game.noInterp {
            step = k * period
            timeDebt += raw - step
            if abs(timeDebt) > period { step += timeDebt; timeDebt = 0 }       // long-term correction
        } else {
            timeDebt = 0
        }
        game.frame(dt: Float(step))
        lastTime = now
        syncMeshes()
        guard let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        let quality = game.quality
        // resolution follows the GPU load, up to a ceiling set by the quality level
        let ceiling: Float = [0.7, 0.85, 1.0][min(max(quality, 0), 2)]
        // drop resolution when frames are being missed; raise it again only with clear GPU headroom
        if now - lastScaleChange > 0.8 && now - startTime > 3 && (game.hud.overlay == .none || game.showcaseActive) {
            // judged by frames that actually reached the screen late, not by callback timing
            if missed > 0.04 && dynScale > 0.5 { dynScale -= missed > 0.25 ? 0.1 : 0.05; lastScaleChange = now; missed *= 0.5 }
            // the GPU timer cannot show headroom under vsync, so after a steady spell just try the next step up
            else if missed < 0.004 && dynScale < 1 && now - lastScaleChange > 8 { dynScale += 0.05; lastScaleChange = now }
        }
        dynScale = min(max(dynScale, 0.5), 1)
        var scale = min(dynScale, ceiling)
        if let fixed = Renderer.debugScale { scale = fixed }
        game.renderScale = scale
        let dw = drawable.texture.width, dh = drawable.texture.height
        let rw = max(Int(Float(dw) * scale), 16), rh = max(Int(Float(dh) * scale), 16)
        makeTargets(rw, rh)
        guard let hdrMS = hdrMS, let depthMS = depthMS, let hdr = hdr, let depth = depth, let skyTex = skyTex, bloom.count == 5 else { return }

        // ---- uniforms
        let ac = game.aircraft
        let light = game.lighting
        let L = light.sunDir
        func lightVP(_ center: V3, _ size: Float) -> M4 {
            let up: V3 = abs(L.y) > 0.95 ? V3(0, 0, 1) : V3(0, 1, 0)
            return M4.ortho(halfSize: size, near: 1, far: 1500) * M4.lookAt(eye: center + L * 700, target: center, up: up)
        }
        let pano = game.site.panorama != nil
        // the fine shadow map follows this pilot's aircraft and widens to take in the others flying close by
        var s0Half = max(ac.spec.span * 0.9, 1.2)
        for w in game.wingmen where w.present(now) {
            let d = distance(w.aircraft.renderPos, ac.renderPos) + w.aircraft.spec.span * 0.7
            if d < 14 { s0Half = max(s0Half, d) }
        }
        let proj = M4.perspective(fovY: game.fov, aspect: Float(dw) / Float(max(dh, 1)), near: 20000, far: 0.08)   // reverse-Z
        let viewM = M4.lookAt(eye: game.eye, target: game.target, up: game.upVec)
        var fu = FrameUniforms()
        fu.viewProj = proj * viewM
        fu.invViewProj = fu.viewProj.inverse
        fu.shadow0 = lightVP(ac.renderPos, s0Half)
        fu.shadow1 = lightVP(V3(0, 0, game.site.flatCenterZ), 300)
        fu.camPos = V4(game.eye.x, game.eye.y, game.eye.z, game.env.time)
        fu.sunDir = V4(L.x, L.y, L.z, Float(game.site.runwayType))
        fu.sunColor = V4(light.sun.x, light.sun.y, light.sun.z, pano ? 0 : game.env.fog)
        fu.zenith = V4(light.zenith.x, light.zenith.y, light.zenith.z, game.site.north / 360)
        fu.horizon = V4(light.horizon.x, light.horizon.y, light.horizon.z, game.site.horizon * deg)
        fu.runway = V4(game.site.runwayLen / 2, game.site.runwayWid / 2, Float(game.site.style), game.env.cloud)
        fu.ambient = V4(light.ambient.x, light.ambient.y, light.ambient.z, 0)
        fu.post = V4(0, 1, quality > 0 ? 0.85 : 0, pano ? 0.12 : 0.32)
        fu.screen = V4(1 / Float(rw), 1 / Float(rh), Float(shadow1Size), s0Half)
        let tint = Game.photoTints[game.photoLight]
        fu.pano = V4(tint.x, tint.y, tint.z, game.photoLight > 0 ? 1 : 0)      // photographs are shown as they are unless the light is graded
        if !pano {
            // 3D sites have no photograph to grade: the slot says what bare ground here is paved with (0 nothing, 1 concrete slabs, 2 cobbles)
            let pal = game.site.palette
            fu.pano = V4(pal == 28 ? 1 : (pal == 33 ? 2 : 0), 0, 0, 0)
        }

        // frustum side planes, for culling grass and trees
        let m = fu.viewProj
        func row(_ i: Int) -> V4 { V4(m.columns.0[i], m.columns.1[i], m.columns.2[i], m.columns.3[i]) }
        let planes = [row(3) + row(0), row(3) - row(0), row(3) + row(1), row(3) - row(1)].map { p -> V4 in p / length(V3(p.x, p.y, p.z)) }
        func visible(_ c: GPUChunk, maxDist: Float) -> Bool {
            if distance(c.center, game.eye) - c.radius > maxDist { return false }
            for p in planes where p.x * c.center.x + p.y * c.center.y + p.z * c.center.z + p.w < -c.radius { return false }
            return true
        }

        // ---- draw lists
        var acItems: [DrawItem] = []
        var acBlend: [DrawItem] = []       // translucent prop / rotor discs
        func add(_ ac: Aircraft, _ meshes: [GPUMesh?]) {
            let base = M4.translation(ac.renderPos) * M4(ac.renderQ)
            for (i, part) in ac.spec.parts.enumerated() {
                guard i < meshes.count, let mesh = meshes[i], !ac.detached.contains(i) else { continue }
                var local = M4.identity
                switch part.anim {
                case .fixed: break
                case .spin(let k): local = M4.translation(part.pivot) * M4.rotation(ac.spin[k], part.axis)
                case .hinge(let ch, let maxA): local = M4.translation(part.pivot) * M4.rotation(ac.animValue(ch) * maxA, part.axis)
                }
                if part.blur != 0, case .spin(let k) = part.anim {
                    let lv = ac.spec.kind == .helicopter ? ac.levels[0] : ac.levels[min(k, ac.levels.count - 1)]
                    if part.blur == 1 { if lv > 0.3 { continue } }                   // blades vanish into the disc
                    else {
                        let a = smoothstep(0.12, 0.45, lv)
                        if a > 0.01 { acBlend.append(DrawItem(mesh: mesh, model: base * local, tint: V4(1, 1, 1, a), material: 4)) }
                        continue
                    }
                }
                acItems.append(DrawItem(mesh: mesh, model: base * local, spec: 1))
            }
        }
        add(ac, partMeshes)
        // the rest of the formation
        let wallNow = CACurrentMediaTime()
        for w in game.wingmen where w.present(wallNow) {
            let name = w.aircraft.spec.name
            if fleetMeshes[name] == nil { fleetMeshes[name] = w.aircraft.spec.parts.map { GPUMesh(device, $0.mesh) } }
            add(w.aircraft, fleetMeshes[name]!)
        }
        for w in game.showFlight {                   // the flight shown behind the menus
            let name = w.aircraft.spec.name
            if fleetMeshes[name] == nil { fleetMeshes[name] = w.aircraft.spec.parts.map { GPUMesh(device, $0.mesh) } }
            add(w.aircraft, fleetMeshes[name]!)
        }
        if let gm = game.gateMarker, let mesh = panelMesh {
            // the gate to fly through next glows, brighter as the clock runs
            let f = gm.dir, r = cross(f, V3(0, 1, 0))
            let rot = M4(columns: (V4(r.x, r.y, r.z, 0), V4(0, 1, 0, 0), V4(-f.x, -f.y, -f.z, 0), V4(0, 0, 0, 1)))
            let pulse = 0.2 + 0.08 * sin(game.env.time * 4)
            acBlend.append(DrawItem(mesh: mesh, model: M4.translation(gm.pos) * rot * M4(diagonal: V4(gm.w, gm.h, 1, 1)), tint: V4(1, 0.78, 0.2, pulse), material: 4))
        }
        if let sm = game.slotMarker, let mesh = slotMesh, !game.aircraft.crashed {
            // where this pilot belongs: amber while off station, green when in the slot
            let f = sm.fwd, r = cross(f, V3(0, 1, 0))
            let rot = M4(columns: (V4(r.x, r.y, r.z, 0), V4(0, 1, 0, 0), V4(-f.x, -f.y, -f.z, 0), V4(0, 0, 0, 1)))
            let sc = M4(diagonal: V4(sm.radius, sm.radius, sm.radius, 1))
            acBlend.append(DrawItem(mesh: mesh, model: M4.translation(sm.pos) * rot * sc, tint: sm.good ? V4(0.25, 1, 0.4, 0.75) : V4(1, 0.72, 0.15, 0.6), material: 4))
        }
        if let mesh = slotMesh, game.showFlight.isEmpty {
            // the other aircraft are small and soon far away: each carries a ring that keeps its size on the screen.
            // Pale for a computer pilot, amber for a real one, doubled for the lead.
            let fwd = normalize(game.target - game.eye), right = normalize(cross(fwd, game.upVec)), up2 = cross(right, fwd)
            let rot = M4(columns: (V4(right.x, right.y, right.z, 0), V4(up2.x, up2.y, up2.z, 0), V4(-fwd.x, -fwd.y, -fwd.z, 0), V4(0, 0, 0, 1)))
            for w in game.wingmen where w.present(wallNow) && !w.aircraft.crashed {
                let p = w.aircraft.renderPos, d = distance(p, game.eye)
                let a = smoothstep(18, 45, d) * 0.8
                guard a > 0.02 else { continue }
                let r = max(d * 0.012 * tan(game.fov / 2) / 0.577, w.aircraft.spec.span * 0.7)
                let tint = w.ai == nil ? V4(1, 0.72, 0.2, a) : V4(0.8, 0.92, 1, a * 0.85)
                for k in 0..<(w.id == game.leadID ? 2 : 1) {
                    let rr = r * (k == 0 ? 1 : 1.4)
                    acBlend.append(DrawItem(mesh: mesh, model: M4.translation(p) * rot * M4(diagonal: V4(rr, rr, rr, 1)), tint: tint, material: 4))
                }
            }
        }
        for d in game.debris {
            guard d.part < partMeshes.count, let mesh = partMeshes[d.part] else { continue }
            acItems.append(DrawItem(mesh: mesh, model: M4.translation(d.pos) * M4(d.q) * M4.translation(d.offset), spec: 1))
        }
        let wv = game.env.windVec
        let wind2 = SIMD2<Float>(wv.x, wv.z) + SIMD2<Float>(0.6, 0.3)
        var world: [DrawItem] = []
        if let mesh = sceneryMesh { world.append(DrawItem(mesh: mesh, model: .identity, spec: 1)) }
        if let mesh = windsockMesh, !pano {
            let sp = game.env.windSpeed
            let yaw = sp > 0.05 ? atan2(wv.x, wv.z) : 0
            let droop = (1 - clampf(sp / 7, 0, 1)) * 78 * deg + sin(game.env.time * 5) * 0.04 * min(sp, 3)
            world.append(DrawItem(mesh: mesh, model: M4.translation(game.terrain.windsockBase + V3(0, 4.8, 0)) * M4.rotation(yaw, V3(0, 1, 0)) * M4.rotation(droop, V3(1, 0, 0))))
        }
        if let mesh = balloonMesh {
            for b in game.balloons where b.alive { world.append(DrawItem(mesh: mesh, model: M4.translation(b.pos), tint: b.color, spec: 0.8)) }
        }
        for c in vegetation where !Renderer.debugOff.contains("veg") && visible(c, maxDist: 5000) { world.append(DrawItem(mesh: c.mesh, model: .identity, material: 5, wind: wind2)) }
        let grassItems = Renderer.debugOff.contains("grass") ? [] : grass.filter { visible($0, maxDist: 140) }.map { DrawItem(mesh: $0.mesh, model: .identity, material: 6, wind: wind2) }

        // ---- shadow maps: 0 = tight around the aircraft (every frame), 1 = the airfield (static, redrawn when it changes)
        func shadowPass(_ index: Int, _ items: [DrawItem]) {
            let sp = MTLRenderPassDescriptor()
            sp.depthAttachment.texture = shadowTex[index]
            sp.depthAttachment.loadAction = .clear; sp.depthAttachment.clearDepth = 1; sp.depthAttachment.storeAction = .store
            guard let enc = cb.makeRenderCommandEncoder(descriptor: sp) else { return }
            enc.setRenderPipelineState(shadowPSO)
            enc.setDepthStencilState(depthShadow)
            enc.setCullMode(.none)
            enc.setDepthBias(0, slopeScale: 2.0, clamp: 0)
            var vp = index == 0 ? fu.shadow0 : fu.shadow1
            enc.setVertexBytes(&vp, length: 64, index: 1)
            drawItems(enc, items, fragment: false)
            enc.endEncoding()
        }
        shadowPass(0, acItems)
        let key = game.siteVersion * 8 + game.timeOfDay
        if shadow1Key != key {
            shadow1Key = key
            var casters: [DrawItem] = []
            if let mesh = sceneryMesh { casters.append(DrawItem(mesh: mesh, model: .identity)) }
            for c in vegetation where abs(c.center.x) < 300 + c.radius && abs(c.center.z - game.site.flatCenterZ) < 300 + c.radius {
                casters.append(DrawItem(mesh: c.mesh, model: .identity))
            }
            shadowPass(1, casters)
        }

        if panoTex == nil { post(cb, skyPSO, to: skyTex, [], &fu) }

        // ---- scene into the multisampled HDR target
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = hdrMS
        rpd.colorAttachments[0].resolveTexture = hdr
        rpd.colorAttachments[0].loadAction = .dontCare               // the sky pass covers every pixel
        rpd.colorAttachments[0].storeAction = .multisampleResolve
        rpd.depthAttachment.texture = depthMS
        rpd.depthAttachment.resolveTexture = depth
        rpd.depthAttachment.loadAction = .clear; rpd.depthAttachment.clearDepth = 0
        rpd.depthAttachment.storeAction = .multisampleResolve
        rpd.depthAttachment.depthResolveFilter = .max
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setCullMode(.none)
            enc.setVertexBytes(&fu, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentBytes(&fu, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            if let pt = panoTex {
                enc.setRenderPipelineState(panoPSO)
                enc.setFragmentTexture(pt, index: 0)
                enc.setFragmentSamplerState(panoSampler, index: 1)
            } else {
                enc.setRenderPipelineState(skyBlitPSO)
                enc.setFragmentTexture(skyTex, index: 0)
                enc.setFragmentSamplerState(linearSampler, index: 1)
            }
            enc.setDepthStencilState(depthOff)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            enc.setRenderPipelineState(scenePSO)
            enc.setDepthStencilState(depthMain)
            enc.setFragmentTexture(shadowTex[0], index: 0)
            enc.setFragmentTexture(shadowTex[1], index: 1)
            enc.setFragmentSamplerState(shadowSampler, index: 0)
            enc.setFragmentSamplerState(pointSampler, index: 1)
            if let t = terrainMesh, !Renderer.debugOff.contains("terrain") { drawItems(enc, [DrawItem(mesh: t, model: .identity, material: 1)], fragment: true) }
            if pano, let c = catcherMesh {
                // the shadow catcher lies on the photo's ground, which may be a hillside
                let g = game.site.groundGradient
                let tilt = M4(columns: (V4(1, g.x, 0, 0), V4(0, 1, 0, 0), V4(0, g.y, 1, 0), V4(0, 0, 0, 1)))
                drawItems(enc, [DrawItem(mesh: c, model: tilt, material: 2)], fragment: true)
            }
            drawItems(enc, world, fragment: true)
            drawItems(enc, grassItems, fragment: true)
            drawItems(enc, acItems, fragment: true)
            // translucent things last, depth-tested but not written
            enc.setDepthStencilState(depthRead)
            if let wm = waterMesh { drawItems(enc, [DrawItem(mesh: wm, model: .identity, material: 7)], fragment: true) }
            if let ts = treeShadowMesh { drawItems(enc, [DrawItem(mesh: ts, model: .identity, material: 4)], fragment: true) }
            drawItems(enc, acBlend, fragment: true)
            if game.showObstacles, pano {
                var ob = MeshBuilder()
                // the invisible ground: rings every doubling of distance, to check it against the photo
                for r: Float in [5, 10, 20, 40, 80, 160, 320] {
                    let w = r * 0.012, n = 96
                    func pt(_ a: Float, _ d: Float) -> V3 { V3(sin(a) * d, game.terrain.height(sin(a) * d, cos(a) * d) + 0.02, cos(a) * d) }
                    for k in 0..<n {
                        let a0 = Float(k) / Float(n) * 2 * .pi, a1 = Float(k + 1) / Float(n) * 2 * .pi
                        ob.quad(pt(a0, r - w), pt(a0, r + w), pt(a1, r + w), pt(a1, r - w), V4(0.1, 0.9, 1, 0.8))
                    }
                }
                for (i, o) in game.site.obstacles.enumerated() {
                    let c = Panoramas.position(o, north: game.site.north)
                    let col: V4 = i % 2 == 0 ? V4(1, 0.2, 0.2, 0.35) : V4(1, 0.6, 0.1, 0.35)
                    let gy = game.terrain.height(c.x, c.y)
                    // drawn as what is solid: the core, narrowing toward the top of a tree
                    let r0 = Panoramas.solidRadius(o, at: 0), mid = o.height * 0.55
                    ob.cylinder(from: V3(c.x, gy, c.y), to: V3(c.x, gy + mid, c.y), r0: r0, r1: r0, seg: 20, color: col)
                    ob.cylinder(from: V3(c.x, gy + mid, c.y), to: V3(c.x, gy + o.height, c.y), r0: r0, r1: Panoramas.solidRadius(o, at: o.height), seg: 20, color: col)
                }
                if let om = GPUMesh(device, ob) { drawItems(enc, [DrawItem(mesh: om, model: .identity, material: 4)], fragment: true) }
            }
            if let tm = trailMesh() { drawItems(enc, [DrawItem(mesh: tm, model: .identity, material: 3)], fragment: true) }
            if let pm = particleMesh() { drawItems(enc, [DrawItem(mesh: pm, model: .identity, material: 3)], fragment: true) }
            enc.endEncoding()
        }

        // ---- post-processing
        var ao: MTLTexture? = white
        if quality > 0, !Renderer.debugOff.contains("ao"), let aoTex = aoTex, let aoBlur = aoBlur {
            post(cb, aoPSO, to: aoTex, [depth], &fu)
            post(cb, aoBlurPSO, to: aoBlur, [aoTex], &fu)
            ao = aoBlur
        }
        post(cb, bloomPrePSO, to: bloom[0], [hdr], &fu)
        for i in 1..<5 { post(cb, bloomDownPSO, to: bloom[i], [bloom[i - 1]], &fu) }

        // ---- composite to the screen
        let out = MTLRenderPassDescriptor()
        out.colorAttachments[0].texture = drawable.texture
        out.colorAttachments[0].loadAction = .dontCare
        out.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: out) {
            enc.setRenderPipelineState(compositePSO)
            enc.setFragmentBytes(&fu, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            for (i, t) in [hdr, ao, bloom[1], bloom[2], bloom[3], bloom[4]].enumerated() { enc.setFragmentTexture(t, index: i) }
            enc.setFragmentSamplerState(linearSampler, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        var capture: MTLTexture?
        if let _ = shotPath, now - startTime >= shotAfter {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: drawable.texture.pixelFormat, width: dw, height: dh, mipmapped: false)
            d.storageMode = .shared
            if let tex = device.makeTexture(descriptor: d), let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: drawable.texture, to: tex)
                blit.endEncoding()
                capture = tex
            }
        }
        cb.addCompletedHandler { [weak self] b in
            let ms = Float((b.gpuEndTime - b.gpuStartTime) * 1000)
            DispatchQueue.main.async { if let s = self, ms > 0 { s.gpuMs += (ms - s.gpuMs) * 0.15; s.game.gpuMs = s.gpuMs } }
        }
        drawable.addPresentedHandler { [weak self] d in
            let t = d.presentedTime
            DispatchQueue.main.async {
                guard let s = self, t > 0 else { return }
                if s.lastPresented > 0 {
                    let ms = Float(t - s.lastPresented) * 1000
                    s.statPresented.append(ms)
                    let period = 1000 / Float(max(NSScreen.main?.maximumFramesPerSecond ?? 60, 30))
                    s.missed += ((ms > period * 1.5 ? 1 : 0) - s.missed) * 0.03
                }
                s.lastPresented = t
            }
        }
        cb.present(drawable)
        cb.commit()
        if let tex = capture, let path = shotPath {
            cb.waitUntilCompleted()
            savePNG(tex, path)
            exit(0)
        }
    }

    /// Studio-style preview of an aircraft on a transparent background, for the selection screens.
    func thumbnail(for spec: AircraftSpec, width w: Int = 840, height h: Int = 520, from view: V3 = V3(-0.8, 0.42, -0.95)) -> NSImage? {
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: w, height: h, mipmapped: false)
        cd.textureType = .type2DMultisample; cd.sampleCount = 4; cd.usage = .renderTarget; cd.storageMode = .private
        let rd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: w, height: h, mipmapped: false)
        rd.usage = [.renderTarget, .shaderRead]; rd.storageMode = .shared
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.textureType = .type2DMultisample; dd.sampleCount = 4; dd.usage = .renderTarget; dd.storageMode = .private
        guard let color = device.makeTexture(descriptor: cd), let resolve = device.makeTexture(descriptor: rd), let depth = device.makeTexture(descriptor: dd),
              let cb = queue.makeCommandBuffer() else { return nil }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = color; rpd.colorAttachments[0].resolveTexture = resolve
        rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd.colorAttachments[0].storeAction = .multisampleResolve
        rpd.depthAttachment.texture = depth; rpd.depthAttachment.loadAction = .clear; rpd.depthAttachment.clearDepth = 0; rpd.depthAttachment.storeAction = .dontCare
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return nil }

        // frame the model from its contact points and span
        let ys = spec.contacts.map { $0.pos.y }, zs = spec.contacts.map { $0.pos.z }
        let minY = ys.min() ?? -0.1, maxY = ys.max() ?? 0.1, minZ = zs.min() ?? -0.5, maxZ = zs.max() ?? 0.5
        let center = V3(0, (minY + maxY) / 2, (minZ + maxZ) / 2)
        let radius = 0.5 * max(spec.span, maxZ - minZ) * 0.84
        let fov: Float = 26 * deg
        let dir = normalize(view)
        let eye = center + dir * (radius / tan(fov / 2) * 1.02)
        var fu = FrameUniforms()
        fu.viewProj = M4.perspective(fovY: fov, aspect: Float(w) / Float(h), near: 200, far: 0.02) * M4.lookAt(eye: eye, target: center, up: abs(dir.y) > 0.95 ? V3(0, 0, -1) : V3(0, 1, 0))
        fu.invViewProj = fu.viewProj.inverse
        fu.shadow0 = M4(diagonal: V4(0, 0, 0, 0)); fu.shadow1 = fu.shadow0          // no shadow maps: everything lit
        fu.camPos = V4(eye.x, eye.y, eye.z, 0)
        let L = normalize(V3(-0.45, 0.8, -0.35))
        fu.sunDir = V4(L.x, L.y, L.z, 0)
        fu.sunColor = V4(3.0, 2.9, 2.75, 0)
        fu.zenith = V4(0.35, 0.45, 0.65, 0); fu.horizon = V4(0.75, 0.8, 0.86, 0)
        fu.ambient = V4(0.3, 0.33, 0.38, 0)
        fu.post = V4(1, 1, 0, 0)                    // tone-map in the scene shader: there is no post chain here
        enc.setCullMode(.none)
        enc.setVertexBytes(&fu, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentBytes(&fu, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setRenderPipelineState(sceneLDR)
        enc.setDepthStencilState(depthMain)
        enc.setFragmentTexture(shadowTex[0], index: 0); enc.setFragmentTexture(shadowTex[1], index: 1)
        enc.setFragmentSamplerState(shadowSampler, index: 0)
        enc.setFragmentSamplerState(pointSampler, index: 1)
        var items: [DrawItem] = []
        for part in spec.parts where part.blur != 2 {
            guard let mesh = GPUMesh(device, part.mesh) else { continue }
            var local = M4.identity
            if case .fixed = part.anim {} else { local = M4.translation(part.pivot) }
            items.append(DrawItem(mesh: mesh, model: local, spec: 1))
        }
        drawItems(enc, items, fragment: true)
        // soft contact shadow on an invisible floor
        var sm = MeshBuilder()
        let up = V3(0, 1, 0), n = 28
        for j in 0..<n {
            let a0 = Float(j) / Float(n) * 2 * .pi, a1 = Float(j + 1) / Float(n) * 2 * .pi
            let c = V3(0, minY, center.z)
            sm.v(c, up, V4(0, 0, 0, 0.5))
            sm.v(c + V3(cos(a0) * spec.span * 0.55, 0, sin(a0) * (maxZ - minZ) * 0.6), up, V4(0, 0, 0, 0))
            sm.v(c + V3(cos(a1) * spec.span * 0.55, 0, sin(a1) * (maxZ - minZ) * 0.6), up, V4(0, 0, 0, 0))
        }
        if let mesh = GPUMesh(device, sm) {
            enc.setDepthStencilState(depthRead)
            drawItems(enc, [DrawItem(mesh: mesh, model: .identity, material: 4)], fragment: true)
        }
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        resolve.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info), let img = ctx.makeImage() else { return nil }
        return NSImage(cgImage: img, size: NSSize(width: w, height: h))
    }

    /// Camera-facing quads for all smoke and dust particles, oldest first.
    /// Smoke trails: each a pair of crossed ribbons through its points, soft at the edges, wider and fainter with age.
    private func trailMesh() -> GPUMesh? {
        guard !game.trails.isEmpty else { return nil }
        var b = MeshBuilder()
        let up = V3(0, 1, 0), life = Game.trailLife
        for t in game.trails.values where t.count >= 2 {
            // the two edges of each ribbon at every point, then the quads between neighbours
            var edge: [(V3, V3, V3, V3, V4)] = []
            edge.reserveCapacity(t.count)
            for i in t.indices {
                let a = t[max(i - 1, 0)].gap && i > 0 ? t[i].pos : t[max(i - (t[i].gap ? 0 : 1), 0)].pos
                let c = t[min(i + 1, t.count - 1)].pos
                var dir = c - a
                dir = length(dir) > 1e-4 ? normalize(dir) : V3(0, 0, 1)
                var s1 = cross(dir, up)
                s1 = length(s1) > 0.05 ? normalize(s1) : V3(1, 0, 0)
                let s2 = cross(s1, dir), p = t[i]
                let w = (0.05 + 0.24 * sqrt(p.age)) * p.wide
                let fade = 1 - p.age / life
                let alpha = 0.42 * min(1, p.age * 7 + 0.25) * fade * sqrt(fade)
                edge.append((p.pos - s1 * w, p.pos + s1 * w, p.pos - s2 * w, p.pos + s2 * w, V4(0.96, 0.96, 0.97, alpha)))
            }
            for i in 1..<t.count where !t[i].gap {
                let p = edge[i - 1], q = edge[i]
                for (a0, a1, b0, b1) in [(p.0, p.1, q.0, q.1), (p.2, p.3, q.2, q.3)] {
                    b.v(a0, V3(-1, 0, 0), p.4); b.v(a1, V3(1, 0, 0), p.4); b.v(b1, V3(1, 0, 0), q.4)
                    b.v(a0, V3(-1, 0, 0), p.4); b.v(b1, V3(1, 0, 0), q.4); b.v(b0, V3(-1, 0, 0), q.4)
                }
            }
        }
        return GPUMesh(device, b)
    }

    private func particleMesh() -> GPUMesh? {
        guard !game.particles.isEmpty else { return nil }
        let fwd = normalize(game.target - game.eye)
        let right = normalize(cross(fwd, game.upVec)), up = cross(right, fwd)
        var b = MeshBuilder()
        b.data.reserveCapacity(game.particles.count * 60)
        let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, -1), (1, 1), (-1, 1)]
        for p in game.particles {
            let t = p.age / p.life
            let leaf = p.fall > 0
            let size = leaf ? p.size : p.size * (1 + 7 * t)        // smoke and dust spread; a leaf stays a leaf
            var c = p.color
            c.w *= leaf ? (1 - t * t * t) : (1 - t) * min(1, p.age * 12)
            for (u, v) in corners { b.v(p.pos + (right * u + up * v) * size, V3(u, v, 0), c) }
        }
        return GPUMesh(device, b)
    }

    /// Upload an image as an sRGB texture with a full mip chain.
    private func makeTexture(_ img: CGImage) -> MTLTexture? {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        if w >= 2048 { lastDetail = Panoramas.detail(px, width: w, height: h) }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: w, height: h, mipmapped: true)
        d.usage = [.shaderRead, .renderTarget]
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: px, bytesPerRow: w * 4)
        if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: tex); blit.endEncoding(); cb.commit()
        }
        return tex
    }

    private func savePNG(_ tex: MTLTexture, _ path: String) {
        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
              let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
