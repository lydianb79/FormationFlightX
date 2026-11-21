import SwiftUI
import AppKit

// MARK: - Theme

/// The look of FormationFlightX: evening sky. Deep blue panels, cool white type, a bright sky blue for what can
/// be pressed and amber for what needs attention.
enum Theme {
    static let brand = Color(red: 0.10, green: 0.60, blue: 0.92)
    static let brandDeep = Color(red: 0.04, green: 0.27, blue: 0.52)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let paper = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let ink = Color(red: 0.035, green: 0.07, blue: 0.125)
    static let accent = brand
    static let panel = ink.opacity(0.95)
    static let glass = ink.opacity(0.74)
    static let card = paper.opacity(0.06)
    static let stroke = paper.opacity(0.14)
    static let dim = paper.opacity(0.66)
    static let faint = paper.opacity(0.42)
}

private struct GlassBox: ViewModifier {
    var radius: CGFloat = 12
    var fill = Theme.glass
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}
private extension View {
    func glass(_ radius: CGFloat = 12, fill: Color = Theme.glass) -> some View { modifier(GlassBox(radius: radius, fill: fill)) }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Capsule().fill(LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.78)], startPoint: .top, endPoint: .bottom)).opacity(configuration.isPressed ? 0.75 : 1))
    }
}
private struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.paper.opacity(0.9))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paper.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

private struct Difficulty: View {
    var level: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle().fill(i <= level ? (level >= 4 ? Theme.brand : Theme.paper) : Theme.paper.opacity(0.16)).frame(width: 7, height: 7)
            }
            Text(["", "Beginner", "Easy", "Intermediate", "Advanced", "Expert"][min(max(level, 1), 5)])
                .font(.system(size: 11, weight: .medium)).foregroundColor(Theme.dim).padding(.leading, 4)
        }
    }
}

private struct Tag: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Theme.paper.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.paper.opacity(0.1)))
    }
}

private func specRow(_ k: String, _ v: String) -> some View {
    HStack {
        Text(k).foregroundColor(Theme.dim)
        Spacer()
        Text(v).monospacedDigit().foregroundColor(Theme.paper)
    }
    .font(.system(size: 12.5))
    .padding(.vertical, 5)
    .overlay(Rectangle().fill(Theme.paper.opacity(0.07)).frame(height: 1), alignment: .bottom)
}

/// Preview image on a soft studio backdrop.
private struct Backdrop<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.42, green: 0.58, blue: 0.74), Color(red: 0.06, green: 0.12, blue: 0.21)], center: .init(x: 0.5, y: 0.42), startRadius: 4, endRadius: 260)
            content
        }
    }
}

// MARK: - HUD

private struct StickView: View {
    var x: Float, y: Float, label: String
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Rectangle().fill(Theme.paper.opacity(0.14)).frame(width: 1)
                Rectangle().fill(Theme.paper.opacity(0.14)).frame(height: 1)
                Circle().fill(Theme.accent).frame(width: 12, height: 12)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
                    .offset(x: CGFloat(x) * 34, y: CGFloat(-y) * 34)
            }
            .frame(width: 84, height: 84)
            .glass(10)
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundColor(Theme.faint)
        }
    }
}

private struct Metric: View {
    var label: String, value: String, unit: String
    var body: some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.9).foregroundColor(Theme.faint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 19, weight: .semibold, design: .default)).monospacedDigit().foregroundColor(Theme.paper)
                Text(unit).font(.system(size: 10.5, weight: .medium)).foregroundColor(Theme.dim)
            }
        }
        .frame(minWidth: 78)
    }
}

private struct BarButton: View {
    var icon: String, help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.paper.opacity(0.9))
                .frame(width: 32, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.paper.opacity(0.08)))
        }
        .buttonStyle(.plain).focusable(false).help(help)
    }
}

private struct Chip: View {
    var icon: String, title: String, subtitle: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.paper).lineLimit(1)
                    Text(subtitle).font(.system(size: 10.5)).foregroundColor(Theme.dim).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(Theme.faint)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .glass(9)
        }
        .buttonStyle(.plain).focusable(false)
    }
}

struct HUDView: View {
    @ObservedObject var m: HUDModel

    var body: some View {
        let s = m.s
        ZStack {
            if m.visible && m.overlay != .menu && m.overlay != .splash {
                VStack(spacing: 0) {
                    // top bar
                    HStack(spacing: 8) {
                        Chip(icon: "airplane", title: s.aircraft, subtitle: s.mode.isEmpty ? "Aircraft" : s.mode) { m.overlay = .aircraft }
                        Chip(icon: "map", title: s.site, subtitle: s.time) { m.overlay = .sites }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(s.camera).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.paper.opacity(0.85))
                            Text("\(s.input) · \(s.rates) · \(s.fps) fps").font(.system(size: 10)).monospacedDigit().foregroundColor(Theme.dim)
                        }
                        .padding(.trailing, 4).allowsHitTesting(false)
                        HStack(spacing: 5) {
                            BarButton(icon: s.onboard ? "video.fill" : "airplane", help: s.onboard ? "View from behind the aircraft" : "FPV: view from on board") { m.game.toggleFPV() }
                                .overlay(alignment: .bottom) { Text(s.onboard ? "FPV" : "3RD").font(.system(size: 6.5, weight: .heavy)).foregroundColor(Theme.amber).offset(y: 1).allowsHitTesting(false) }
                            BarButton(icon: s.smoke ? "smoke.fill" : "smoke", help: s.smoke ? "Smoke off" : "Smoke on") { m.game.toggleSmoke() }
                                .overlay(alignment: .bottom) { Text(s.smoke ? "ON" : "OFF").font(.system(size: 6.5, weight: .heavy)).foregroundColor(s.smoke ? Theme.amber : Theme.dim).offset(y: 1).allowsHitTesting(false) }
                            BarButton(icon: s.unread > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right", help: "Lobby: chat and voice (Return)") { m.game.cameFromMenu = false; m.overlay = m.overlay == .lobby ? .none : .lobby }
                            BarButton(icon: "person.3.fill", help: "Options: pilots, hosting and joining") { m.game.cameFromMenu = false; m.overlay = m.overlay == .options ? .none : .options }
                            BarButton(icon: "wind", help: "Wind, weather and time of day") { m.game.cameFromMenu = false; m.overlay = m.overlay == .environment ? .none : .environment }
                            BarButton(icon: "gamecontroller", help: "Controller setup") { m.openControllerSetup?() }
                            BarButton(icon: "questionmark", help: "Keyboard controls (H)") { m.game.cameFromMenu = false; m.overlay = m.overlay == .help ? .none : .help }
                            BarButton(icon: "line.3.horizontal", help: "Main menu (Esc)") { m.overlay = .menu }
                        }
                        .padding(4).glass(10)
                    }
                    .padding(.leading, m.fullscreen ? 12 : 84).padding(.trailing, 12).padding(.top, 9)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            FormationBox(s: s) { m.game.cameFromMenu = false; m.overlay = .formation }
                            // what the others wrote, for a few seconds
                            ForEach(s.chat) { line in
                                (Text(line.system ? "" : line.name + "  ").font(.system(size: 11.5, weight: .bold)) + Text(line.text).font(.system(size: 11.5)))
                                    .foregroundColor(Theme.paper.opacity(line.system ? 0.7 : 1)).lineLimit(2).frame(maxWidth: 320, alignment: .leading)
                                    .padding(.horizontal, 9).padding(.vertical, 5).glass(8)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            MiniMap(s: s).allowsHitTesting(false)
                            TrimGauge(trim: s.trim, noseUp: { m.game.trim(1) }, noseDown: { m.game.trim(-1) })
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)

                    if !s.launchHint.isEmpty {
                        Text(s.launchHint).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(Theme.amber)).padding(.top, 10).allowsHitTesting(false)
                    }
                    if !s.score.isEmpty {
                        Text(s.score).font(.system(size: 14, weight: .bold, design: .default)).monospacedDigit().foregroundColor(Theme.paper)
                            .padding(.horizontal, 14).padding(.vertical, 6).glass(9).padding(.top, 8).allowsHitTesting(false)
                    }
                    Spacer()
                    // bottom: sticks and telemetry
                    HStack(alignment: .bottom) {
                        StickView(x: s.lx, y: s.ly, label: s.leftLabel)
                        Spacer()
                        VStack(spacing: 7) {
                            if !s.config.isEmpty {
                                Text(s.config).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundColor(Theme.paper)
                                    .padding(.horizontal, 12).padding(.vertical, 4).glass(8)
                            }
                            HStack(spacing: 6) {
                                Metric(label: "ALTITUDE", value: String(format: "%.0f", max(s.alt, 0)), unit: "m")
                                Metric(label: "AIRSPEED", value: String(format: "%.0f", s.speed * 3.6), unit: "km/h")
                                Metric(label: "CLIMB", value: String(format: "%+.1f", s.climb), unit: "m/s")
                                Metric(label: "DISTANCE", value: String(format: "%.0f", s.dist), unit: "m")
                                Metric(label: "THROTTLE", value: String(format: "%.0f", s.throttle * 100), unit: "%")
                                Metric(label: "WIND", value: s.wind.components(separatedBy: " ").first ?? "", unit: s.wind.components(separatedBy: " ").dropFirst().joined(separator: " "))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8).glass(12)
                        }
                        Spacer()
                        StickView(x: s.rx, y: s.ry, label: s.rightLabel)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 12).allowsHitTesting(false)
                }
            }
            if !s.message.isEmpty && !m.game.simHeld {
                VStack {
                    Spacer().frame(height: 74)
                    let big = s.message == "CRASHED" || s.message == "PAUSED"
                    Text(s.message)
                        .font(.system(size: big ? 30 : 14, weight: big ? .heavy : .semibold, design: big ? .rounded : .default))
                        .tracking(big ? 3 : 0)
                        .foregroundColor(s.message == "CRASHED" ? Color(red: 1, green: 0.3, blue: 0.25) : .white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .glass(10)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            // The main menu and the two browsers are built once and then shown and hidden: building one from nothing
            // took SwiftUI 60 to 150 ms, every time it was opened or closed.
            if m.menusBuilt {
                kept(MainMenu(m: m), m.overlay == .menu)
                kept(AircraftBrowser(m: m, shownNow: m.overlay == .aircraft), m.overlay == .aircraft)
                kept(SiteBrowser(m: m, shownNow: m.overlay == .sites), m.overlay == .sites)
            }
            Group {
                switch m.overlay {
                case .menu, .aircraft, .sites: EmptyView()
                case .environment: EnvironmentPanel(m: m)
                case .help: HelpView(m: m)
                case .formation: FormationPanel(m: m)
                case .lobby: LobbyView(m: m)
                case .options: OptionsPanel(m: m)
                case .splash: SplashView(m: m).transition(.asymmetric(insertion: .identity, removal: .scale(scale: 1.35).combined(with: .opacity)))
                case .none: EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: m.overlay == .splash)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.brand)
    }

    /// A screen that stays built: hidden, it neither shows, nor takes clicks, nor answers its keyboard shortcuts.
    private func kept<V: View>(_ v: V, _ on: Bool) -> some View {
        v.opacity(on ? 1 : 0).allowsHitTesting(on).disabled(!on).accessibilityHidden(!on)
    }
}

// MARK: - Overlay scaffolding

private struct Sheet<Content: View>: View {
    @ObservedObject var m: HUDModel
    var title: String
    var subtitle: String
    var back: Overlay = .none
    var width: CGFloat = 1120
    var height: CGFloat = 660
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Theme.ink.opacity(0.5).ignoresSafeArea().onTapGesture { m.overlay = back }
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 23, weight: .bold, design: .rounded)).foregroundColor(Theme.paper)
                    Text(subtitle).font(.system(size: 12.5)).foregroundColor(Theme.dim).padding(.leading, 6)
                    Spacer()
                    Button { m.overlay = back } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.paper.opacity(0.8))
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.paper.opacity(0.1)))
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                content
            }
            .frame(maxWidth: width, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.21), Theme.ink], startPoint: .top, endPoint: .bottom)).opacity(0.97))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            .padding(28)
        }
    }
}

// MARK: - Aircraft browser

struct AircraftBrowser: View {
    @ObservedObject var m: HUDModel
    var shownNow: Bool = true
    @AppStorage("aircraftCategory") private var category = "All"
    @State private var search = ""
    @State private var selected = 0

    private static let order = ["FPV Aircrafts", "Trainers & Sport", "Gliders", "Scale Civil", "Warbirds", "Aerobatic", "Foam 3D", "Jets"]
    private var all: [AircraftSpec] { AircraftLibrary.all }
    private var shown: [Int] {
        all.indices.filter { i in
            (category == "All" || all[i].category == category)
                && (search.isEmpty || all[i].name.localizedCaseInsensitiveContains(search) || all[i].blurb.localizedCaseInsensitiveContains(search))
        }
    }
    private func fly(_ i: Int) { m.game.selectAircraft(i); m.overlay = .menu }
    /// A click selects at once; a second click on the same card within the double-click time flies it. (SwiftUI's own
    /// double-tap gesture held every single click back until the double-click time had run out.)
    @State private var lastTap: (index: Int, time: Double) = (-1, 0)
    private func tap(_ i: Int) {
        let now = CACurrentMediaTime()
        if lastTap.index == i && now - lastTap.time < NSEvent.doubleClickInterval { lastTap = (-1, 0); fly(i); return }
        lastTap = (i, now); selected = i
    }

    var body: some View {
        Sheet(m: m, title: "Choose Aircraft", subtitle: "\(all.count) models", back: m.game.cameFromMenu ? .menu : .none) {
            HStack(spacing: 0) {
                // categories
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(["All"] + Self.order, id: \.self) { c in
                        let n = c == "All" ? all.count : all.filter { $0.category == c }.count
                        Button { category = c } label: {
                            HStack {
                                Text(c).font(.system(size: 13, weight: category == c ? .semibold : .regular))
                                Spacer()
                                Text("\(n)").font(.system(size: 11)).monospacedDigit().foregroundColor(Theme.faint)
                            }
                            .foregroundColor(category == c ? .white : Theme.dim)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(category == c ? Theme.brand.opacity(0.85) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusable(false)
                    }
                    Spacer()
                }
                .frame(width: 176).padding(12)
                Rectangle().fill(Theme.stroke).frame(width: 1)

                // grid
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(Theme.faint)
                        TextField("Search aircraft", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.paper.opacity(0.07)))
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10)], spacing: 10) {
                            ForEach(shown, id: \.self) { i in
                                let spec = all[i]
                                VStack(alignment: .leading, spacing: 0) {
                                    Backdrop {
                                        if let img = m.thumbnailSmall(spec) { Image(nsImage: img).resizable().scaledToFit().padding(4) }
                                    }
                                    .frame(height: 98).clipped()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(spec.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.paper).lineLimit(1)
                                        Text(spec.category).font(.system(size: 10.5)).foregroundColor(Theme.dim).lineLimit(1)
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                }
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected == i ? Theme.paper : Theme.stroke, lineWidth: selected == i ? 2 : 1))
                                .contentShape(Rectangle())
                                .onTapGesture { tap(i) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.bottom, 14)
                        if shown.isEmpty { Text("No aircraft match “\(search)”.").font(.system(size: 13)).foregroundColor(Theme.dim).padding(30) }
                    }
                }
                Rectangle().fill(Theme.stroke).frame(width: 1)

                // details
                let spec = all[min(selected, all.count - 1)]
                VStack(alignment: .leading, spacing: 0) {
                    Backdrop {
                        if let img = m.thumbnail(spec) { Image(nsImage: img).resizable().scaledToFit().padding(6) }
                    }
                    .frame(height: 205).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(spec.name).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.paper).padding(.top, 14)
                    HStack(spacing: 8) { Tag(text: spec.category); Difficulty(level: spec.difficulty) }.padding(.top, 6)
                    Text(spec.blurb).font(.system(size: 13)).foregroundColor(Theme.paper.opacity(0.82)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    VStack(spacing: 0) {
                        specRow(spec.sizeLabel, String(format: "%.2f m", spec.span))
                        specRow("Power", spec.powerPlant)
                        specRow("Flying weight", spec.mass < 1 ? String(format: "%.0f g", spec.mass * 1000) : String(format: "%.1f kg", spec.mass))
                        if spec.kind == .airplane {
                            specRow("Construction", spec.construction)
                            specRow("Wing loading", String(format: "%.0f g/dm²", spec.mass / spec.wingArea * 10))
                            specRow("Stall speed", String(format: "%.0f km/h", spec.stallSpeed * 3.6))
                        }
                        if spec.kind != .helicopter { specRow("Thrust to weight", String(format: "%.1f : 1", spec.thrustToWeight)) }
                    }
                    .padding(.top, 12)
                    if !spec.features.isEmpty {
                        HStack(spacing: 5) { ForEach(spec.features.prefix(3), id: \.self) { Tag(text: $0) } }.padding(.top, 10)
                    }
                    Spacer(minLength: 8)
                    Button { fly(selected) } label: { Text("Select").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                }
                .frame(width: 300).padding(16)
            }
        }
        .onAppear { selected = m.game.aircraftIndex }
        .onChange(of: shownNow) { on in if on { selected = m.game.aircraftIndex } }
    }
}

// MARK: - Site browser

struct SiteBrowser: View {
    @ObservedObject var m: HUDModel
    var shownNow: Bool = true
    @State private var selected = 0
    @AppStorage("siteFilter") private var filter = "All"       // stays as it was left, also after a restart
    @State private var search = ""
    private static let categories = ["Race Tracks", "Obstacles", "Cities", "Industrial", "Fields", "Airfields", "Mountains", "Water", "Desert", "Winter"]
    private var all: [SiteSpec] { SiteSpec.all }
    private func matches(_ s: SiteSpec, _ f: String) -> Bool {
        switch f {
        case "All": return true
        case "3D Sites": return s.panorama == nil
        case "Photo Sites": return s.panorama != nil
        default: return s.category == f
        }
    }
    private var shown: [Int] {
        all.indices.filter { i in
            matches(all[i], filter) && (search.isEmpty || all[i].displayName.localizedCaseInsensitiveContains(search) || all[i].summary.localizedCaseInsensitiveContains(search))
        }
    }
    private func fly(_ i: Int) { m.game.chooseSite(i); m.overlay = .menu }
    /// A click selects at once; a second click on the same card within the double-click time flies it. (SwiftUI's own
    /// double-tap gesture held every single click back until the double-click time had run out.)
    @State private var lastTap: (index: Int, time: Double) = (-1, 0)
    private func tap(_ i: Int) {
        let now = CACurrentMediaTime()
        if lastTap.index == i && now - lastTap.time < NSEvent.doubleClickInterval { lastTap = (-1, 0); fly(i); return }
        lastTap = (i, now); selected = i
    }

    private func filterRow(_ f: String, icon: String) -> some View {
        Button { filter = f } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11.5)).frame(width: 16).foregroundColor(filter == f ? .white : Theme.faint)
                Text(f).font(.system(size: 13, weight: filter == f ? .semibold : .regular))
                Spacer()
                Text("\(all.filter { matches($0, f) }.count)").font(.system(size: 11)).monospacedDigit().foregroundColor(Theme.faint)
            }
            .foregroundColor(filter == f ? .white : Theme.dim)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(filter == f ? Theme.brand.opacity(0.85) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
    }
    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundColor(Theme.faint).padding(.leading, 10).padding(.top, 12).padding(.bottom, 3)
    }
    private func badge(_ site: SiteSpec) -> some View {
        Text(site.panorama != nil ? "360° PHOTO" : "3D").font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundColor(site.panorama != nil ? Theme.ink : Theme.paper)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(site.panorama != nil ? Theme.paper : Theme.brand))
    }

    var body: some View {
        Sheet(m: m, title: "Choose Flying Site", subtitle: "\(all.count) sites", back: m.game.cameFromMenu ? .menu : .none) {
            HStack(spacing: 0) {
                // filters
                VStack(alignment: .leading, spacing: 2) {
                    filterRow("All", icon: "square.grid.2x2")
                    heading("LANDSCAPE")
                    filterRow("Race Tracks", icon: "flag.checkered")
                    filterRow("Obstacles", icon: "square.grid.3x3.middle.filled")
                    filterRow("Cities", icon: "building.2")
                    filterRow("Industrial", icon: "gearshape.2")
                    filterRow("Fields", icon: "leaf")
                    filterRow("Airfields", icon: "airplane.departure")
                    filterRow("Mountains", icon: "mountain.2")
                    filterRow("Water", icon: "water.waves")
                    filterRow("Desert", icon: "sun.max")
                    filterRow("Winter", icon: "snowflake")
                    Spacer()
                }
                .frame(width: 176).padding(12)
                Rectangle().fill(Theme.stroke).frame(width: 1)

                // grid
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(Theme.faint)
                        TextField("Search sites", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.paper.opacity(0.07)))
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 172, maximum: 230), spacing: 10)], spacing: 10) {
                            ForEach(shown, id: \.self) { i in
                                let site = all[i]
                                VStack(alignment: .leading, spacing: 0) {
                                    ZStack(alignment: .topLeading) {
                                        LinearGradient(colors: [Color(red: 0.25, green: 0.4, blue: 0.6), Color(red: 0.2, green: 0.32, blue: 0.2)], startPoint: .top, endPoint: .bottom)
                                        if let img = m.sitePreviewSmall(site) { Image(nsImage: img).resizable().scaledToFill().frame(minWidth: 0, maxWidth: .infinity, minHeight: 104, maxHeight: 104).clipped() }
                                        badge(site).padding(7)
                                    }
                                    .frame(height: 104).clipped()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(site.displayName).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.paper).lineLimit(1)
                                        Text(site.category).font(.system(size: 10.5)).foregroundColor(Theme.dim).lineLimit(1)
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                }
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected == i ? Theme.paper : Theme.stroke, lineWidth: selected == i ? 2 : 1))
                                .contentShape(Rectangle())
                                .onTapGesture { tap(i) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.bottom, 14)
                        if shown.isEmpty { Text("No sites match.").font(.system(size: 13)).foregroundColor(Theme.dim).padding(30) }
                    }
                }
                Rectangle().fill(Theme.stroke).frame(width: 1)

                // details
                let site = all[min(selected, all.count - 1)]
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Color.black.opacity(0.3)
                        if let img = m.sitePreview(site) { Image(nsImage: img).resizable().scaledToFill() }
                    }
                    .frame(width: 300, height: 188).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(site.displayName).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.paper).padding(.top, 14)
                    HStack(spacing: 8) { Tag(text: site.kindLabel); Tag(text: site.category); Difficulty(level: site.difficulty) }.padding(.top, 6)
                    Text(site.summary).font(.system(size: 13)).foregroundColor(Theme.paper.opacity(0.82)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    VStack(spacing: 0) {
                        specRow("Surface", site.surfaceLabel)
                        specRow("Typical wind", site.windSpeed < 0.5 ? "Calm" : String(format: "%.0f m/s from %.0f°", site.windSpeed, site.windFrom))
                        specRow("Turbulence", site.turbulence < 0.25 ? "Light" : (site.turbulence < 0.5 ? "Moderate" : "Strong"))
                        specRow("Cameras", site.panorama != nil ? "Pilot" : "Pilot, chase, onboard")
                    }
                    .padding(.top, 12)
                    Spacer(minLength: 8)
                    Button { fly(selected) } label: { Text("Select").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                }
                .frame(width: 300).padding(16)
            }
        }
        .onAppear { selected = m.game.siteIndex }
        .onChange(of: shownNow) { on in if on { selected = m.game.siteIndex } }
    }
}

// MARK: - Splash

/// Full-screen title card shown at launch; any key or click continues.
struct SplashView: View {
    @ObservedObject var m: HUDModel
    @State private var arrived = false      // the artwork has flown in
    @State private var sweep = false        // a band of light crosses the artwork
    @State private var pulse = false
    @State private var progress: CGFloat = 0
    private static let image: NSImage? = resourceURL("Splash.jpg").flatMap { NSImage(contentsOf: $0) }
    private static let logo: NSImage? = resourceURL("RockFPV.png").flatMap { NSImage(contentsOf: $0) }
    @State private var titled = false
    @State private var tagged = false
    @State private var credited = false
    private static let hold: Double = 4.0

    var body: some View {
        GeometryReader { g in
            ZStack {
                Theme.ink
                if let img = Self.image {
                    // the artwork rushes toward the viewer and settles, then keeps drifting very slowly
                    Image(nsImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(arrived ? 1.0 : 1.22)
                        .blur(radius: arrived ? 0 : 14)
                        .opacity(arrived ? 1 : 0)
                        .scaleEffect(1 + 0.035 * progress)
                        .clipped()
                } else {
                    Text("FORMATION FLIGHT X").font(.system(size: 90, weight: .black)).foregroundColor(Theme.paper)
                        .scaleEffect(arrived ? 1 : 1.3).opacity(arrived ? 1 : 0)
                }
                // a slanted band of light sweeps across, like sun glinting off a wing
                LinearGradient(colors: [.clear, Theme.paper.opacity(0.0), Theme.paper.opacity(0.42), Theme.paper.opacity(0.0), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.55, height: g.size.height * 2.2)
                    .rotationEffect(.degrees(24))
                    .offset(x: sweep ? g.size.width * 1.1 : -g.size.width * 1.1)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                // a soft dark edge that eases off as the picture arrives
                RadialGradient(colors: [.clear, .black.opacity(arrived ? 0.28 : 0.75)], center: .center, startRadius: g.size.height * 0.35, endRadius: g.size.height * 1.05)
                    .allowsHitTesting(false)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            // the title comes up from below once the picture has settled, the line under it and the credit after it
            .overlay(alignment: .bottomLeading) {
                let u = g.size.width / 1280
                VStack(alignment: .leading, spacing: 0) {
                    (Text("FormationFlight").foregroundColor(Theme.paper) + Text("X").foregroundColor(Theme.amber))
                        .font(.system(size: 92 * u, weight: .bold, design: .rounded))
                        .shadow(color: .black.opacity(0.45), radius: 14 * u, y: 5 * u)
                        .opacity(titled ? 1 : 0).offset(y: titled ? 0 : 46 * u)
                    Text("Fly together").font(.system(size: 31 * u, weight: .medium, design: .rounded)).foregroundColor(Theme.paper.opacity(0.9))
                        .shadow(color: .black.opacity(0.4), radius: 8 * u, y: 2 * u)
                        .padding(.top, 2 * u).padding(.leading, 5 * u)
                        .opacity(tagged ? 1 : 0).offset(x: tagged ? 0 : -30 * u)
                    HStack(spacing: 14 * u) {
                        if let logo = Self.logo {
                            Image(nsImage: logo).resizable().frame(width: 62 * u, height: 62 * u).clipShape(Circle())
                                .overlay(Circle().stroke(Theme.paper.opacity(0.85), lineWidth: 1.5 * u)).shadow(color: .black.opacity(0.5), radius: 7 * u, y: 2 * u)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Created by").font(.system(size: 14 * u, weight: .medium, design: .rounded)).foregroundColor(Theme.paper.opacity(0.75))
                            Text("Rock FPV").font(.system(size: 28 * u, weight: .bold, design: .rounded)).foregroundColor(Theme.paper)
                        }
                    }
                    .padding(.top, 30 * u).padding(.leading, 4 * u)
                    .opacity(credited ? 1 : 0).offset(y: credited ? 0 : 16 * u)
                }
                .padding(.leading, 74 * u).padding(.bottom, 86 * u)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    Text("PRESS ANY KEY").font(.system(size: 11, weight: .heavy)).tracking(3)
                        .foregroundColor(Theme.paper.opacity(pulse ? 0.95 : 0.4))
                        .opacity(arrived ? 1 : 0)
                    // how long until it moves on by itself
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.paper.opacity(0.18))
                        Capsule().fill(Theme.paper.opacity(0.85)).frame(width: 220 * progress)
                    }
                    .frame(width: 220, height: 3).opacity(arrived ? 1 : 0)
                    .padding(.bottom, 22)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { m.overlay = .menu }
        .onChange(of: m.splashGo) { go in if go { start() } }
        .onAppear { if m.splashGo { start() } }
    }

    private func start() {
        guard !arrived else { return }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1)) { arrived = true }
        withAnimation(.easeInOut(duration: 1.2).delay(0.35)) { sweep = true }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.45)) { titled = true }
        withAnimation(.easeOut(duration: 0.6).delay(0.95)) { tagged = true }
        withAnimation(.easeOut(duration: 0.6).delay(1.3)) { credited = true }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.5)) { pulse = true }
        withAnimation(.linear(duration: Self.hold)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { if m.overlay == .splash { m.overlay = .menu } }
    }
}

// MARK: - Main menu

private struct InkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(Theme.paper.opacity(0.9))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Capsule().fill(Theme.paper.opacity(configuration.isPressed ? 0.2 : 0.09)))
    }
}

struct MainMenu: View {
    @ObservedObject var m: HUDModel
    private static let logo: NSImage? = resourceURL("RockFPV.png").flatMap { NSImage(contentsOf: $0) }

    /// One choice: a picture, what it is, and what is chosen.
    private func row<P: View>(_ label: String, _ title: String, _ sub: String, badge: String? = nil, @ViewBuilder picture: () -> P, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                picture().frame(width: 118, height: 70).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.4).foregroundColor(Theme.brand)
                    Text(title).font(.system(size: 15.5, weight: .semibold, design: .rounded)).foregroundColor(Theme.paper).lineLimit(1)
                    Text(sub).font(.system(size: 11.5)).foregroundColor(Theme.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let b = badge {
                    Text(b).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Theme.amber))
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.faint)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.paper.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
    }
    private func symbol(_ name: String) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.brandDeep, Theme.brand.opacity(0.7)], startPoint: .bottomLeading, endPoint: .topTrailing)
            Image(systemName: name).font(.system(size: 26, weight: .semibold)).foregroundColor(.white.opacity(0.92))
        }
    }

    var body: some View {
        let g = m.game!
        let spec = g.aircraft.spec, site = g.site
        let waiting = g.together && !g.sessionRunning && !g.isHost
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // wordmark
                HStack(spacing: 12) {
                    FormationGlyph(kind: .vic, count: 5, tint: Theme.brand).frame(width: 58, height: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        (Text("FormationFlight").foregroundColor(Theme.paper) + Text("X").foregroundColor(Theme.brand))
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("Fly together").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(Theme.dim)
                    }
                }
                .padding(.bottom, 22)

                VStack(spacing: 9) {
                    row("YOUR AIRCRAFT", spec.name, spec.category + String(format: " · %.2f m · %.0f g", spec.span, spec.mass * 1000),
                        picture: { ZStack { Backdrop { EmptyView() }; if let i = m.thumbnailSmall(spec) { Image(nsImage: i).resizable().scaledToFit().padding(3) } } }) { g.cameFromMenu = true; m.overlay = .aircraft }
                    row("FLYING SITE", site.displayName, g.together && !g.isHost ? "Chosen by the host, \(g.name(of: g.hostID))" : site.kindLabel,
                        picture: { ZStack { Color.black.opacity(0.3); if let i = m.sitePreviewSmall(site) { Image(nsImage: i).resizable().scaledToFill() } } }) { g.cameFromMenu = true; m.overlay = .sites }
                    row("FORMATIONS", g.formation.name, "\(Formation.spacingNames[g.spacing]) spacing" + (g.isLead ? "" : " · called by \(g.name(of: g.leadID))"),
                        picture: { ZStack { LinearGradient(colors: [Theme.brandDeep, Theme.brand.opacity(0.7)], startPoint: .bottomLeading, endPoint: .topTrailing); FormationGlyph(kind: g.formation, count: max(g.order.count, 3)).padding(10) } }) { g.cameFromMenu = true; m.overlay = .formation }
                    row("OPTIONS", m.s.mates.isEmpty ? "Flying alone" : "With " + m.s.mates.map { $0.name }.joined(separator: ", "),
                        g.net.hosting ? "Hosting a session" : (g.net.joined != nil ? "Joined a host" : (g.multiplayer ? "Pilots, your name, hosting and joining" : "Network off")),
                        picture: { symbol("gearshape.2.fill") }) { g.cameFromMenu = true; m.overlay = .options }
                    row("LOBBY", g.together ? (g.sessionRunning ? "Session running" : "Session stopped") : "Meet other pilots",
                        g.together ? "\(g.remotePilots.count + 1) pilots · chat and voice" : (m.s.net.isEmpty ? "Host or join, chat and voice" : m.s.net), badge: m.s.unread > 0 ? "\(m.s.unread)" : nil,
                        picture: { symbol("bubble.left.and.bubble.right.fill") }) { g.cameFromMenu = true; m.overlay = .lobby }
                }

                Spacer(minLength: 16)

                Button { g.takeOff() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: waiting ? "hourglass" : "paperplane.fill")
                        Text(waiting ? "Waiting for the host" : (g.together && g.isHost && !g.sessionRunning ? "Start the session" : "Take off"))
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Capsule().fill(LinearGradient(colors: [Theme.brand, Theme.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .opacity(waiting ? 0.55 : 1)
                }
                .buttonStyle(.plain).focusable(false).keyboardShortcut(.defaultAction)

                HStack(spacing: 6) {
                    Button { g.cameFromMenu = true; m.overlay = .environment } label: { Label("Weather", systemImage: "cloud.sun") }.buttonStyle(InkButton())
                    Button { m.openControllerSetup?() } label: { Label("Controller", systemImage: "gamecontroller") }.buttonStyle(InkButton())
                    Button { g.cameFromMenu = true; m.overlay = .help } label: { Label("Keys", systemImage: "keyboard") }.buttonStyle(InkButton())
                    Button { g.musicEnabled.toggle(); m.objectWillChange.send() } label: { Image(systemName: g.musicEnabled ? "music.note" : "speaker.slash") }.buttonStyle(InkButton())
                        .help(g.musicEnabled ? "Turn the menu music off" : "Turn the menu music on")
                    Spacer(minLength: 0)
                    Button { NSApp.terminate(nil) } label: { Text("Quit") }.buttonStyle(InkButton())
                }
                .padding(.top, 12)

                HStack(spacing: 9) {
                    if let logo = Self.logo { Image(nsImage: logo).resizable().frame(width: 26, height: 26).clipShape(Circle()) }
                    Text("by Rock FPV").font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundColor(Theme.dim)
                    Spacer()
                    Text("Graphics").font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundColor(Theme.dim)
                    Picker("", selection: Binding(get: { g.quality }, set: { g.quality = $0; m.objectWillChange.send() })) {
                        ForEach(0..<3, id: \.self) { Text(Game.qualityNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 24).padding(.top, m.fullscreen ? 30 : 46).padding(.bottom, 22)
            .frame(width: 440).frame(maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(red: 0.06, green: 0.13, blue: 0.23), Theme.ink], startPoint: .top, endPoint: .bottom).opacity(0.94))
            .overlay(Rectangle().fill(Theme.stroke).frame(width: 1), alignment: .trailing)
            // the scene stays in view on the right
            LinearGradient(colors: [Theme.ink.opacity(0.45), Theme.ink.opacity(0.0)], startPoint: .leading, endPoint: .trailing).frame(maxWidth: 260)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Environment panel

struct EnvironmentPanel: View {
    @ObservedObject var m: HUDModel

    private func bind(_ get: @escaping () -> Float, _ set: @escaping (Float) -> Void) -> Binding<Float> {
        Binding(get: get, set: { set($0); m.objectWillChange.send() })
    }
    private func row(_ title: String, _ value: String, _ b: Binding<Float>, _ range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
                Spacer()
                Text(value).font(.system(size: 12.5)).monospacedDigit().foregroundColor(Theme.dim)
            }
            Slider(value: b, in: range).controlSize(.small)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.paper.opacity(0.55)).padding(.top, 3)
    }
    private func level(_ v: Float, _ names: [String]) -> String { names[min(Int(v * Float(names.count)), names.count - 1)] }
    private func pick(_ title: String, _ names: [String], _ sel: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
            Spacer()
            Picker("", selection: sel) { ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) } }
                .pickerStyle(.menu).labelsHidden().fixedSize()
        }
    }

    var body: some View {
        let env = m.game.env
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        ZStack {
        if m.game.cameFromMenu { Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { m.overlay = .menu } }
        HStack {
            Spacer()
            VStack {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Weather").font(.system(size: 17, weight: .bold)).foregroundColor(Theme.paper)
                        Spacer()
                        Button { m.overlay = m.game.cameFromMenu ? .menu : .none } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.paper.opacity(0.8))
                                .frame(width: 24, height: 24).background(Circle().fill(Theme.paper.opacity(0.1)))
                        }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    }
                    if m.game.together && !m.game.isHost {
                        Text("Weather and daylight are set by the host, \(m.game.name(of: m.game.hostID)).").font(.system(size: 11.5)).foregroundColor(Theme.amber).fixedSize(horizontal: false, vertical: true)
                    }
                    Menu {
                        ForEach(Array(Environment.presets.enumerated()), id: \.offset) { i, n in
                            Button(n) { env.apply(preset: i); m.objectWillChange.send() }
                        }
                    } label: { Label("Choose a preset", systemImage: "cloud.sun").frame(maxWidth: .infinity) }
                    .menuStyle(.borderlessButton).padding(.vertical, 5).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.paper.opacity(0.1)))
                    section("WIND")
                    row("Wind speed", String(format: "%.0f m/s  (%.0f km/h)", env.windSpeed, env.windSpeed * 3.6), bind({ env.windSpeed }, { env.windSpeed = $0.rounded() }), 0...15)
                    row("Wind from", String(format: "%@  %.0f°", dirs[Int((env.windFrom + 22.5) / 45) % 8], env.windFrom), bind({ env.windFrom }, { env.windFrom = ($0 / 5).rounded() * 5 }), 0...355)
                    row("Gusts and lulls", level(env.gustiness, ["Steady", "Light", "Moderate", "Strong"]), bind({ env.gustiness }, { env.gustiness = $0 }), 0...1)
                    row("Turbulence", env.turbulence < 0.05 ? "Smooth" : String(format: "%.0f %%", env.turbulence * 100), bind({ env.turbulence }, { env.turbulence = $0 }), 0...1)
                    row("Thermals", !env.thermalsOn || env.thermalStrength < 0.05 ? "Off" : (env.thermalStrength < 0.6 ? "Weak" : (env.thermalStrength < 1.3 ? "Normal" : (env.thermalStrength < 1.75 ? "Strong" : "Booming"))),
                        bind({ env.thermalsOn ? env.thermalStrength : 0 }, { env.thermalStrength = $0; env.thermalsOn = $0 >= 0.05 }), 0...2)
                    section("SKY AND LIGHT")
                    if m.game.site.panorama == nil {
                        row("Cloud cover", level(env.cloud, ["Clear", "Few clouds", "Broken", "Overcast"]), bind({ env.cloud }, { env.cloud = $0 }), 0...1)
                        row("Haze", level(env.haze, ["Crystal clear", "Clear", "Hazy", "Misty"]), bind({ env.haze }, { env.haze = $0 }), 0...1)
                        pick("Time of day", Game.timeNames, Binding(get: { m.game.timeOfDay }, set: { m.game.timeOfDay = $0; m.objectWillChange.send() }))
                    } else {
                        pick("Light", Game.photoLightNames, Binding(get: { m.game.photoLight }, set: { m.game.photoLight = $0; m.objectWillChange.send() }))
                        Text("A photo site keeps the sky and sun of its photograph; the light can be graded toward evening or dusk.")
                            .font(.system(size: 10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    Button { m.game.env.configure(m.game.site); m.objectWillChange.send() } label: { Text("Reset to Site Default").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                }
                .padding(18)
                .frame(width: 320)
                .glass(14, fill: Theme.panel)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                Spacer()
            }
            .padding(.top, 54).padding(.trailing, 12)
        }
        }
    }
}

// MARK: - Help

struct HelpView: View {
    @ObservedObject var m: HUDModel
    private let groups: [(String, [(String, String)])] = [
        ("Flying", [("← →", "Aileron (roll)"), ("↑ ↓", "Elevator — ↓ pulls up"), ("A  D", "Rudder (yaw)"), ("W  S", "Throttle / collective"),
                    ("X", "Throttle cut"), ("Q", "Wheel brakes"), ("Shift", "Full stick deflection"), ("L", "High / low rates"), ("−  =", "Pitch trim: nose down / up"), ("0", "Centre the pitch trim"), ("Space", "Launch from the hand / take it back")]),
        ("Formation", [("J", "Join up: start in the air behind your slot"), ("U", "Take the lead / hand it back"), ("O", "Next formation (lead only)"), ("I", "Spacing: tight, normal, loose (lead only)"),
                       ("Y", "Smoke"), ("E", "Flaps"), ("G", "Landing gear"), ("[  ]", "Previous / next wing"), ("Tab", "Wing browser")]),
        ("View and simulation", [("C", "Camera: chase, onboard, pilot"), ("Z", "Zoom mode"), ("V", "Hide / show display"), ("P", "Pause"),
                                 ("T", "Slow motion"), (",  .", "Less / more wind"), ("N", "Next flying site"),
                                 ("K", "Autopilot for your own wing"), ("Return", "Lobby: chat and voice"), ("B", "Hold to talk (can be changed in Controller Setup)"), ("M", "Mute sound"), ("Esc", "Main menu")]),
    ]
    var body: some View {
        Sheet(m: m, title: "Controls", subtitle: "Keyboard", back: m.game.cameFromMenu ? .menu : .none, width: 940, height: 520) {
            HStack(alignment: .top, spacing: 26) {
                ForEach(groups, id: \.0) { g in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(g.0.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.5).foregroundColor(Theme.paper.opacity(0.6)).padding(.bottom, 3)
                        ForEach(g.1, id: \.0) { k in
                            HStack(spacing: 10) {
                                Text(k.0).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundColor(Theme.paper)
                                    .frame(minWidth: 46).padding(.vertical, 3).padding(.horizontal, 5)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.paper.opacity(0.1)))
                                Text(k.1).font(.system(size: 12.5)).foregroundColor(Theme.paper.opacity(0.85))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            Spacer(minLength: 0)
            Text("Gamepads and USB RC transmitters are detected automatically. Calibration, stick mode, rates and expo are in Controller Setup (⌘,).")
                .font(.system(size: 11.5)).foregroundColor(Theme.dim).padding(.horizontal, 24).padding(.bottom, 18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


// MARK: - Formation

/// Top view of where the slot is relative to this pilot's aircraft, with a bar for the height difference.
/// Pitch trim, laid out as the elevator trim on a transmitter: up the scale (stick forward) is nose down, down the
/// scale is nose up. The arrow above trims nose down, the one below nose up, and the marker goes the same way.
private struct TrimGauge: View {
    var trim: Int
    var noseUp: () -> Void, noseDown: () -> Void
    var body: some View {
        let h: CGFloat = 96, f = CGFloat(trim) / CGFloat(Game.trimMax)
        func arrow(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 12, weight: .heavy)).foregroundColor(Theme.paper)
                    .frame(width: 34, height: 24).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.paper.opacity(0.12)))
            }
            .buttonStyle(.plain).focusable(false).help(help)
        }
        return HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("PITCH TRIM").font(.system(size: 8.5, weight: .heavy)).tracking(0.8).foregroundColor(Theme.dim)
                Text(trim == 0 ? "centre" : String(format: "%+d", trim)).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundColor(Theme.paper)
                Text(trim == 0 ? " " : (trim > 0 ? "nose up" : "nose down")).font(.system(size: 9, weight: .medium)).foregroundColor(Theme.dim)
            }
            VStack(spacing: 5) {
                arrow("chevron.up", "Trim nose down (−)", noseDown)
                ZStack {
                    Capsule().fill(Theme.paper.opacity(0.1)).frame(width: 6, height: h)
                    ForEach(-2...2, id: \.self) { k in Rectangle().fill(Theme.paper.opacity(k == 0 ? 0.55 : 0.25)).frame(width: k == 0 ? 16 : 10, height: 1).offset(y: -CGFloat(k) * h / 4) }
                    Capsule().fill(trim == 0 ? Theme.paper : Theme.amber).frame(width: 20, height: 5).offset(y: f * h / 2)
                }
                .frame(width: 34, height: h)
                arrow("chevron.down", "Trim nose up (=)", noseUp)
            }
        }
        .padding(8).glass(12)
    }
}

/// The map in the corner of the display: this aircraft at the centre pointing up, everyone else round it to scale.
/// A real pilot carries a name; a computer partner is a plain grey arrow. The lead has a ring.
private struct MiniMap: View {
    var s: HUDState
    var body: some View {
        let size: CGFloat = 168, half = size / 2 - 9, range = CGFloat(max(s.mapRange, 1))
        // where something `p` metres away goes; beyond the edge it is held on the rim
        func place(_ p: SIMD2<Float>) -> (CGSize, Bool) {
            let d = CGFloat((p.x * p.x + p.y * p.y).squareRoot()), k = d > range ? range / d : 1
            return (CGSize(width: CGFloat(p.x) * k / range * half, height: -CGFloat(p.y) * k / range * half), d > range)
        }
        let amber = Theme.amber, grey = Theme.paper.opacity(0.6)
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.black.opacity(0.28))
                Circle().stroke(Theme.paper.opacity(0.22), lineWidth: 1)
                Circle().stroke(Theme.paper.opacity(0.12), lineWidth: 1).frame(width: half, height: half)
                Rectangle().fill(Theme.paper.opacity(0.1)).frame(width: 1, height: half * 2)
                Rectangle().fill(Theme.paper.opacity(0.1)).frame(width: half * 2, height: 1)
                Text("N").font(.system(size: 9, weight: .heavy)).foregroundColor(Theme.paper.opacity(0.7))
                    .offset(x: sin(CGFloat(s.mapNorth)) * (half + 2), y: -cos(CGFloat(s.mapNorth)) * (half + 2))
                // where the pilots stand
                let (hp, hFar) = place(s.mapHome)
                Image(systemName: "house.fill").font(.system(size: 9)).foregroundColor(Theme.paper.opacity(hFar ? 0.45 : 0.8)).offset(hp)
                ForEach(s.blips) { b in
                    let (o, off) = place(b.p), real = !b.name.isEmpty, col = b.crashed ? Color.red.opacity(0.8) : (real ? amber : grey)
                    ZStack {
                        if b.lead { Circle().stroke(col, lineWidth: 1.2).frame(width: 17, height: 17) }
                        if b.talking { Circle().fill(amber.opacity(0.3)).frame(width: 22, height: 22) }
                        Image(systemName: "location.north.fill").font(.system(size: real ? 11 : 9)).foregroundColor(col).rotationEffect(.radians(Double(b.heading)))
                    }
                    .opacity(off ? 0.55 : 1).offset(o)
                    if real {
                        // the name, and how far above or below
                        Text(b.name + (abs(b.dAlt) >= 2 ? String(format: " %+.0f", b.dAlt) : ""))
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white).lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .offset(x: o.width, y: o.height + (o.height > half - 22 ? -14 : 14))
                    } else if abs(b.dAlt) >= 3 && !off {
                        Text(String(format: "%+.0f", b.dAlt)).font(.system(size: 8, weight: .semibold)).foregroundColor(grey).offset(x: o.width + 13, y: o.height)
                    }
                }
                Image(systemName: "location.north.fill").font(.system(size: 12)).foregroundColor(Theme.brand)
            }
            .frame(width: size, height: size)
            HStack(spacing: 6) {
                if !s.mapNote.isEmpty { Text(s.mapNote).font(.system(size: 10, weight: .bold)).monospacedDigit().foregroundColor(Theme.paper) }
                Text(String(format: "edge %.0f m", s.mapRange)).font(.system(size: 9, weight: .semibold)).monospacedDigit().foregroundColor(Theme.dim)
            }
        }
        .padding(7).glass(12)
    }
}

private struct SlotScope: View {
    var e: V3, tol: Float, good: Bool
    var body: some View {
        let size: CGFloat = 92, range = CGFloat(max(tol * 4, 2))
        let col = good ? Color(red: 0.3, green: 0.95, blue: 0.45) : Color(red: 1, green: 0.72, blue: 0.2)
        func clampP(_ v: Float) -> CGFloat { min(max(CGFloat(v) / range, -1), 1) * size / 2 }
        return HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paper.opacity(0.06))
                Rectangle().fill(Theme.paper.opacity(0.18)).frame(width: 1, height: size)
                Rectangle().fill(Theme.paper.opacity(0.18)).frame(width: size, height: 1)
                // the slot, drawn to scale, and this aircraft at the centre
                Circle().stroke(col, lineWidth: 1.6).frame(width: CGFloat(tol) / range * size, height: CGFloat(tol) / range * size)
                    .offset(x: clampP(e.x), y: -clampP(e.z))
                Image(systemName: "triangle.fill").font(.system(size: 9)).foregroundColor(Theme.paper)
            }
            .frame(width: size, height: size).clipped()
            ZStack {
                Capsule().fill(Theme.paper.opacity(0.08)).frame(width: 6, height: size)
                Rectangle().fill(Theme.paper.opacity(0.3)).frame(width: 12, height: 1)
                Capsule().fill(col).frame(width: 12, height: 4).offset(y: -clampP(e.y))
            }
            .frame(width: 12, height: size)
        }
    }
}

private struct FormationBox: View {
    var s: HUDState
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(s.role).font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundColor(Theme.paper)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.brand))
                        if !s.formation.isEmpty { Text(s.formation).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.paper) }
                    }
                    ForEach(s.mates) { mt in
                        HStack(spacing: 6) {
                            Text("\(mt.number)").font(.system(size: 10.5, weight: .heavy)).foregroundColor(Theme.ink)
                                .frame(width: 16, height: 16).background(Circle().fill(Theme.paper.opacity(mt.number == 1 ? 1 : 0.7)))
                            Text(mt.name).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.paper).lineLimit(1)
                            if mt.talking { Image(systemName: "waveform").font(.system(size: 10, weight: .bold)).foregroundColor(Color(red: 0.3, green: 0.95, blue: 0.45)) }
                            Text(mt.detail).font(.system(size: 11)).monospacedDigit()
                                .foregroundColor(mt.good ? Color(red: 0.3, green: 0.95, blue: 0.45) : Theme.dim).lineLimit(1)
                        }
                    }
                    if !s.station.isEmpty {
                        Text(s.station).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                            .foregroundColor(s.onStation ? Color(red: 0.3, green: 0.95, blue: 0.45) : Theme.paper.opacity(0.9))
                    }
                    if !s.mic.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: s.micLive ? "mic.fill" : "mic").font(.system(size: 10, weight: .bold))
                            Text(s.mic).font(.system(size: 10.5, weight: s.micLive ? .heavy : .medium))
                        }
                        .foregroundColor(s.micLive ? Theme.brand : Theme.dim)
                        .padding(.horizontal, s.micLive ? 7 : 0).padding(.vertical, s.micLive ? 2 : 0)
                        .background(Capsule().fill(s.micLive ? Theme.paper : Color.clear))
                    }
                    if !s.net.isEmpty { Text(s.net).font(.system(size: 10)).foregroundColor(Theme.faint).lineLimit(2).frame(maxWidth: 260, alignment: .leading) }
                }
                if let e = s.slot { SlotScope(e: e, tol: s.slotTol, good: s.onStation) }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .glass(10)
        }
        .buttonStyle(.plain).focusable(false)
    }
}

/// Who flies, in what shape, and how the pilots find each other.
struct FormationPanel: View {
    @ObservedObject var m: HUDModel

    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.paper.opacity(0.55))
    }
    private func field(_ title: String, _ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
            TextField(prompt, text: text).textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.paper)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.paper.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
        }
    }
    private func person(_ number: Int, _ name: String, _ detail: String, me: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 13, weight: .heavy)).foregroundColor(number == 1 ? Theme.paper : Theme.ink)
                .frame(width: 26, height: 26).background(Circle().fill(number == 1 ? Theme.brand : Theme.paper.opacity(0.8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name + (me ? "  (you)" : "")).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.paper)
                Text(detail).font(.system(size: 11)).foregroundColor(Theme.dim)
            }
            Spacer()
            Text(number == 1 ? "LEAD" : "WING").font(.system(size: 9.5, weight: .heavy)).tracking(1.2).foregroundColor(Theme.faint)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
    }

    var body: some View {
        let g = m.game!
        let leading = g.isLead
        Sheet(m: m, title: "Formations", subtitle: leading ? "The shape the formation flies, and how close" : "Called by the lead, \(g.name(of: g.leadID))", back: g.cameFromMenu ? .menu : .none, width: 520, height: 600) {
            HStack(alignment: .top, spacing: 0) {
                // the shape
                VStack(alignment: .leading, spacing: 8) {
                    heading("FORMATION")
                    ForEach(FormationKind.allCases, id: \.rawValue) { k in
                        Button { if leading { g.formation = k; m.objectWillChange.send() } } label: {
                            HStack(spacing: 10) {
                                FormationGlyph(kind: k, count: max(g.order.count, 3)).frame(width: 46, height: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k.name).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.paper)
                                    Text(k.blurb).font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(g.formation == k ? Theme.brand.opacity(0.85) : Theme.card))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusable(false)
                    }
                    heading("SPACING").padding(.top, 6)
                    Picker("", selection: Binding(get: { g.spacing }, set: { if leading { g.spacing = $0 }; m.objectWillChange.send() })) {
                        ForEach(Formation.spacingNames.indices, id: \.self) { Text(Formation.spacingNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(String(format: "%.1f m between neighbours (%.1f wingspans of the lead's wing)", g.spacingMetres, Formation.spacingSpans[g.spacing]))
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                    if !leading {
                        Text("Formation and spacing are called by the lead, \(g.name(of: g.leadID)).")
                            .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Everything about flying with others that is not the formation itself: who is there, who leads, your
/// name, and how the pilots find each other.
struct OptionsPanel: View {
    @ObservedObject var m: HUDModel

    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.paper.opacity(0.55))
    }
    private func field(_ title: String, _ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
            TextField(prompt, text: text).textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.paper)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.paper.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
        }
    }
    private func person(_ number: Int, _ name: String, _ detail: String, me: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 13, weight: .heavy)).foregroundColor(number == 1 ? Theme.paper : Theme.ink)
                .frame(width: 26, height: 26).background(Circle().fill(number == 1 ? Theme.brand : Theme.paper.opacity(0.8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name + (me ? "  (you)" : "")).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.paper)
                Text(detail).font(.system(size: 11)).foregroundColor(Theme.dim)
            }
            Spacer()
            Text(number == 1 ? "LEAD" : "WING").font(.system(size: 9.5, weight: .heavy)).tracking(1.2).foregroundColor(Theme.faint)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
    }

    var body: some View {
        let g = m.game!
        let leading = g.isLead
        Sheet(m: m, title: "Options", subtitle: "Up to five pilots, on your network or over the internet, with no server", back: g.cameFromMenu ? .menu : .none, width: 560, height: 720) {
            // (the panel scrolls, so its title and close button stay in view however tall the window is)
            ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // the pilots
                VStack(alignment: .leading, spacing: 10) {
                    heading("PILOTS")
                    ForEach(Array(g.order.enumerated()), id: \.element) { k, id in
                        if id == g.net.id { person(k + 1, g.pilotName, g.aircraft.spec.name, me: true) }
                        else if let w = g.wingmen.first(where: { $0.id == id }) {
                            person(k + 1, w.name, w.aircraft.spec.name + (w.ai != nil ? " · flown by the computer" : ""), me: false)
                        }
                    }
                    if g.remotePilots.isEmpty && g.aiPartners {
                        // alone: how many the computer flies, and where you fly among them
                        Text("Computer pilots").font(.system(size: 11.5, weight: .medium)).foregroundColor(Theme.dim).padding(.top, 4)
                        Picker("", selection: Binding(get: { g.aiCount }, set: { g.aiCount = $0; g.updateRoster(); m.objectWillChange.send() })) {
                            ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Text("Your place").font(.system(size: 11.5, weight: .medium)).foregroundColor(Theme.dim).padding(.top, 2)
                        Picker("", selection: Binding(get: { g.order.firstIndex(of: g.net.id) ?? 0 }, set: { g.setPlace($0); m.objectWillChange.send() })) {
                            ForEach(0...g.aiCount, id: \.self) { Text($0 == 0 ? "Lead" : "No. \($0 + 1)").tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Text("Number 1 leads. Put yourself in front to lead the computer pilots, or behind to follow one of them.")
                            .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button { g.takeLead(); m.objectWillChange.send() } label: {
                            Text(leading && g.leadEpoch > 0 ? "Hand Back the Lead" : "Take the Lead").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(QuietButton()).disabled(leading && g.leadEpoch == 0)
                    }
                    heading("YOU").padding(.top, 6)
                    HStack(spacing: 10) {
                        field("Pilot name", Binding(get: { g.pilotName }, set: { g.pilotName = String($0.prefix(24)); m.objectWillChange.send() }), "Your name")
                        field("Group", Binding(get: { g.group }, set: { g.group = String($0.prefix(24)); m.objectWillChange.send() }), "Everyone")
                    }
                    Text("Pilots with the same group name fly together. Leave it empty to fly with anyone.")
                        .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    Toggle(isOn: Binding(get: { g.multiplayer }, set: { g.multiplayer = $0; m.objectWillChange.send() })) {
                        Text("Fly with other pilots").font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    Toggle(isOn: Binding(get: { g.aiPartners }, set: { g.aiPartners = $0; m.objectWillChange.send() })) {
                        Text("Computer partners while I am alone").font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    if !m.s.net.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: g.remotePilots.isEmpty ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill").foregroundColor(Theme.brand)
                            Text(m.s.net).font(.system(size: 11.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if g.multiplayer {
                        heading("OVER THE INTERNET").padding(.top, 6)
                        Toggle(isOn: Binding(get: { g.net.hosting }, set: { g.net.setHosting($0); m.objectWillChange.send() })) {
                            Text("Host a session (others connect to me)").font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9))
                        }
                        .toggleStyle(.switch).controlSize(.small)
                        if g.net.hosting {
                            HostAddress(m: m)
                        } else {
                            HStack(alignment: .bottom, spacing: 8) {
                                field("Or join a host", Binding(get: { g.hostAddress }, set: { g.hostAddress = String($0.prefix(80)); m.objectWillChange.send() }), "address:47800")
                                Button(g.net.joined == nil ? "Connect" : "Disconnect") {
                                    if g.net.joined == nil { g.net.join(g.hostAddress) } else { g.net.leave() }
                                    m.objectWillChange.send()
                                }
                                .buttonStyle(QuietButton()).disabled(g.net.joined == nil && (g.hostAddress.trimmingCharacters(in: .whitespaces).isEmpty || g.pilotName.trimmingCharacters(in: .whitespaces).isEmpty))
                            }
                            if g.net.joined == nil && g.pilotName.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("Enter your pilot name above before you connect.").font(.system(size: 11)).foregroundColor(Theme.amber)
                            }
                            if let j = g.net.joined {
                                Text(j.answering ? "Connected to \(j.target)." : "No answer from \(j.target) yet. The host has to switch on hosting, and the address must be the one their app shows.")
                                    .font(.system(size: 11)).foregroundColor(j.answering ? Theme.paper.opacity(0.85) : Theme.dim).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
    }
}

/// Little wings in the shape of a formation, seen from above with the lead at the top.
struct FormationGlyph: View {
    var kind: FormationKind
    var count = 3
    var tint = Theme.paper
    var body: some View {
        GeometryReader { g in
            let n = min(max(count, 2), Formation.maxPilots)
            let pts: [V3] = [V3(0, 0, 0)] + (1..<n).map { kind.offset($0) }
            let xs = pts.map { $0.x }, zs = pts.map { $0.z }
            let w = max(xs.max()! - xs.min()!, 0.01), h = max(zs.max()! - zs.min()!, 0.01)
            let u = min(g.size.width / CGFloat(w + 1.3), g.size.height / CGFloat(h + 1.3))
            let cx = (xs.max()! + xs.min()!) / 2, cz = (zs.max()! + zs.min()!) / 2
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    Image(systemName: "triangle.fill").font(.system(size: max(u * 0.72, 5)))
                        .foregroundColor(i == 0 ? tint : tint.opacity(0.6))
                        .position(x: g.size.width / 2 + CGFloat(pts[i].x - cx) * u, y: g.size.height / 2 + CGFloat(pts[i].z - cz) * u)
                }
            }
        }
    }
}

// MARK: - Lobby

/// Where the pilots meet before and between flights: who is there, chat, and the microphone.
struct LobbyView: View {
    @ObservedObject var m: HUDModel
    @State private var draft = ""
    @FocusState private var typing: Bool
    private static let green = Color(red: 0.3, green: 0.95, blue: 0.45)

    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.paper.opacity(0.55))
    }
    private func person(_ number: Int, _ name: String, _ where_: String, talking: Bool, me: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 13, weight: .heavy)).foregroundColor(number == 1 ? Theme.paper : Theme.ink)
                .frame(width: 26, height: 26).background(Circle().fill(number == 1 ? Theme.brand : Theme.paper.opacity(0.8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name + (me ? "  (you)" : "")).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.paper).lineLimit(1)
                Text((number == 1 ? "Lead · " : "") + where_).font(.system(size: 11)).foregroundColor(Theme.dim)
            }
            Spacer(minLength: 0)
            if talking { Image(systemName: "waveform").font(.system(size: 14, weight: .bold)).foregroundColor(Self.green) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
    }
    private func send() { m.game.sendChat(draft); draft = ""; typing = true }

    var body: some View {
        let g = m.game!
        let v = g.voice
        let others = g.remotePilots
        Sheet(m: m, title: "Lobby", subtitle: others.isEmpty ? (m.s.net.isEmpty ? "Nobody else is here" : m.s.net) : "\(others.count + 1) pilots",
              back: g.cameFromMenu ? .menu : .none, width: 1000, height: 720) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    heading("YOUR PILOT NAME")
                    TextField("Your name", text: Binding(get: { g.pilotName }, set: { g.pilotName = String($0.prefix(24)); m.objectWillChange.send() }))
                        .textFieldStyle(.plain).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.paper)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.paper.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(g.pilotName.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.amber : Theme.stroke, lineWidth: 1))
                    heading("PILOTS").padding(.top, 6)
                    ForEach(Array(g.order.enumerated()), id: \.element) { k, id in
                        if id == g.net.id { person(k + 1, g.pilotName.isEmpty ? "(no name)" : g.pilotName, (g.together && g.isHost ? "Host · " : "") + "In the lobby", talking: v.sending, me: true) }
                        else if let w = others.first(where: { $0.id == id }) {
                            person(k + 1, w.name, (id == g.hostID ? "Host · " : "") + w.aircraft.spec.name + " · " + Game.placeNames[Int(min(w.hello.place, 2))].lowercased(), talking: v.speaking(id), me: false)
                        }
                    }
                    if others.isEmpty {
                        Text("Other pilots appear here when they are on your network, or when you host or join a formation over the internet.")
                            .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                        Button { m.overlay = .options } label: { Text("Host or Join…").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                    }
                    heading("VOICE").padding(.top, 8)
                    Picker("", selection: Binding(get: { v.mode.rawValue }, set: { v.mode = VoiceChat.Mode(rawValue: $0) ?? .off; m.objectWillChange.send() })) {
                        ForEach(VoiceChat.Mode.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if !g.net.running {
                        Text("Voice needs the network: switch on “Fly with other pilots” in Options.")
                            .font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    } else if let p = v.micProblem {
                        Text(p).font(.system(size: 11)).foregroundColor(Theme.paper.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    } else if v.mode != .off {
                        HStack(spacing: 8) {
                            Image(systemName: v.sending ? "mic.fill" : "mic").foregroundColor(v.sending ? Self.green : Theme.dim).frame(width: 16)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.paper.opacity(0.1))
                                    Capsule().fill(v.sending ? Self.green : Theme.paper.opacity(0.45)).frame(width: geo.size.width * CGFloat(min(v.micLevel, 1)))
                                }
                            }
                            .frame(height: 6)
                        }
                        if v.mode == .pushToTalk {
                            Text(g.lobbyTalk ? "TALKING" : "HOLD TO TALK").font(.system(size: 12.5, weight: .heavy)).tracking(1.2)
                                .foregroundColor(g.lobbyTalk ? Theme.ink : Theme.paper).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(g.lobbyTalk ? Self.green : Theme.brand))
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { _ in if !g.lobbyTalk { g.lobbyTalk = true; m.objectWillChange.send() } }
                                    .onEnded { _ in g.lobbyTalk = false; m.objectWillChange.send() })
                            HStack(spacing: 6) {
                                Text("Anywhere: hold \(g.input.talkHint).").font(.system(size: 11)).foregroundColor(Theme.faint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        } else {
                            Text("The microphone sends whenever you speak. Wear headphones, or the others will hear themselves through your speakers.")
                                .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2").foregroundColor(Theme.dim).frame(width: 16)
                        Slider(value: Binding(get: { v.volume }, set: { v.volume = $0; m.objectWillChange.send() }), in: 0...1.5).controlSize(.small)
                    }
                    .help("How loud the other pilots are")
                    Spacer(minLength: 0)
                    // the session
                    if g.together {
                        heading("SESSION")
                        HStack(spacing: 7) {
                            Circle().fill(g.sessionRunning ? Self.green : Theme.amber).frame(width: 8, height: 8)
                            Text(g.sessionRunning ? "Running" : "Stopped").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.paper)
                            Text(g.isHost ? "· you are the host" : "· host: \(g.name(of: g.hostID))").font(.system(size: 11.5)).foregroundColor(Theme.dim).lineLimit(1)
                        }
                    }
                    let locked = g.together && g.sessionRunning && !g.isHost
                    HStack(spacing: 7) {
                        Button { g.fromLobby(.aircraft) } label: { Label("Wing", systemImage: "airplane").frame(maxWidth: .infinity) }.buttonStyle(QuietButton()).disabled(locked)
                        if !g.together || g.isHost {
                            Button { g.fromLobby(.sites) } label: { Label("Site", systemImage: "map").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                            Button { g.fromLobby(.environment) } label: { Label("Weather", systemImage: "cloud.sun").lineLimit(1).fixedSize().frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                        }
                    }
                    Text(g.aircraft.spec.name + " · " + g.site.displayName + " · " + Game.timeNames[g.timeOfDay]).font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(1)
                    if locked {
                        Text("You can change your wing when the host stops the session.").font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    if g.net.hosting, let a = g.net.publicAddress {
                        HStack(spacing: 6) {
                            Image(systemName: g.net.portOpened ? "globe" : "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundColor(g.net.portOpened ? Theme.brand : Theme.amber)
                            Text(a).font(.system(size: 11.5)).foregroundColor(Theme.paper.opacity(0.9)).textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(a, forType: .string) }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.brand)
                        }
                        .help(g.net.portOpened ? "Your public address: give it to the other pilots" : "Your public address. The router has not opened the port: see the Formation panel")
                    }
                    if g.together && g.isHost {
                        HStack(spacing: 7) {
                            Button { g.startSession() } label: { Text(g.sessionRunning ? "Restart" : "Start Session").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
                                .help(g.sessionRunning ? "Everyone goes back to the launch point" : "Everyone takes off")
                            if g.sessionRunning {
                                Button { g.stopSession() } label: { Text("Stop").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                                    .help("Everyone comes back to the lobby; wings, site and weather can be changed")
                            }
                        }
                        if g.sessionRunning { Button { g.takeOff() } label: { Text("Back to Flying").frame(maxWidth: .infinity) }.buttonStyle(QuietButton()) }
                    } else if g.together {
                        Button { g.takeOff() } label: { Text(g.sessionRunning ? "Fly" : "Waiting for the host to start…").frame(maxWidth: .infinity) }
                            .buttonStyle(PrimaryButton()).disabled(!g.sessionRunning).opacity(g.sessionRunning ? 1 : 0.5)
                    } else {
                        Button { g.takeOff() } label: { Text("Take Off").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
                    }
                }
                .padding(20).frame(width: 360)
                Rectangle().fill(Theme.stroke).frame(width: 1)
                // chat
                VStack(spacing: 0) {
                    ChatLog(lines: g.chat)
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    HStack(spacing: 8) {
                        TextField(others.isEmpty ? "Nobody is here to read it yet" : "Write to the other pilots", text: $draft)
                            .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.paper).focused($typing)
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.paper.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 1))
                            .onSubmit { send() }
                            .onChange(of: draft) { t in if t.count > NetCodec.maxChat { draft = String(t.prefix(NetCodec.maxChat)) } }
                        Button("Send") { send() }.buttonStyle(PrimaryButton()).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { typing = true }
        }
    }
}


/// The chat so far, newest at the bottom. A view of its own that takes the lines as a value, so that it is
/// redrawn exactly when they change.
private struct ChatLog: View {
    var lines: [ChatLine]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    if lines.isEmpty {
                        Text("Nothing has been said yet.").font(.system(size: 12.5)).foregroundColor(Theme.faint).padding(.top, 6)
                    }
                    ForEach(lines) { line in
                        if line.system {
                            Text(line.text).font(.system(size: 11.5)).foregroundColor(Theme.faint).frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            HStack {
                                if line.mine { Spacer(minLength: 60) }
                                VStack(alignment: .leading, spacing: 2) {
                                    if !line.mine { Text(line.name).font(.system(size: 10.5, weight: .heavy)).foregroundColor(Theme.paper.opacity(0.7)) }
                                    Text(line.text).font(.system(size: 13.5)).foregroundColor(Theme.paper).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(line.mine ? Theme.brand.opacity(0.85) : Theme.paper.opacity(0.09)))
                                if !line.mine { Spacer(minLength: 60) }
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(18)
            }
            .onChange(of: lines.last?.id) { _ in DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}


/// What a host gives the other pilots: the public address, and whether the router lets them in.
private struct HostAddress: View {
    @ObservedObject var m: HUDModel
    var body: some View {
        let net = m.game.net
        VStack(alignment: .leading, spacing: 5) {
            if let a = net.publicAddress {
                Text("YOUR PUBLIC ADDRESS").font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.paper.opacity(0.55))
                HStack(spacing: 8) {
                    Text(a).font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.paper.opacity(0.9)).textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.7)
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(a, forType: .string) }.buttonStyle(QuietButton())
                    Spacer(minLength: 0)
                }
                if net.portOpened {
                    Label("The router has opened the port. Give this address to the other pilots.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                } else {
                    Label((net.hostingProblem ?? "The router has not opened the port yet.") + " Until UDP port \(String(net.port)) is forwarded to this Mac\(net.localAddress.map { " (\($0))" } ?? "") in the router, pilots elsewhere cannot get through.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundColor(Theme.amber).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(net.findingAddress ? "Finding your public address…" : "Your public address could not be found (no internet connection?).")
                    .font(.system(size: 11.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            if let l = net.localAddress {
                Text("Pilots on your own network find you by themselves; if they do not, they can join \(l):\(String(net.port)).")
                    .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Text(net.guestCount == 0 ? "Nobody has connected yet." : "\(net.guestCount) connected from outside.").font(.system(size: 11)).foregroundColor(Theme.dim)
        }
    }
}
