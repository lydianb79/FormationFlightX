import SwiftUI
import AppKit

// MARK: - Theme

/// Colours from the splash artwork: signal red, warm cream and near-black ink.
enum Theme {
    static let red = Color(red: 0.76, green: 0.13, blue: 0.10)
    static let deepRed = Color(red: 0.52, green: 0.07, blue: 0.05)
    static let cream = Color(red: 0.965, green: 0.93, blue: 0.875)
    static let ink = Color(red: 0.11, green: 0.075, blue: 0.07)
    static let accent = red
    static let panel = ink.opacity(0.95)
    static let glass = ink.opacity(0.74)
    static let card = cream.opacity(0.06)
    static let stroke = cream.opacity(0.15)
    static let dim = cream.opacity(0.66)
    static let faint = cream.opacity(0.42)
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
            .font(.system(size: 13.5, weight: .heavy)).tracking(1.2).textCase(.uppercase)
            .foregroundColor(Theme.cream)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.red.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}
private struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.cream.opacity(0.9))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cream.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

private struct Difficulty: View {
    var level: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle().fill(i <= level ? (level >= 4 ? Theme.red : Theme.cream) : Theme.cream.opacity(0.16)).frame(width: 7, height: 7)
            }
            Text(["", "Beginner", "Easy", "Intermediate", "Advanced", "Expert"][min(max(level, 1), 5)])
                .font(.system(size: 11, weight: .medium)).foregroundColor(Theme.dim).padding(.leading, 4)
        }
    }
}

private struct Tag: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Theme.cream.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.cream.opacity(0.1)))
    }
}

private func specRow(_ k: String, _ v: String) -> some View {
    HStack {
        Text(k).foregroundColor(Theme.dim)
        Spacer()
        Text(v).monospacedDigit().foregroundColor(Theme.cream)
    }
    .font(.system(size: 12.5))
    .padding(.vertical, 5)
    .overlay(Rectangle().fill(Theme.cream.opacity(0.07)).frame(height: 1), alignment: .bottom)
}

/// Preview image on a soft studio backdrop.
private struct Backdrop<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.6, green: 0.55, blue: 0.5), Color(red: 0.17, green: 0.12, blue: 0.11)], center: .init(x: 0.5, y: 0.42), startRadius: 4, endRadius: 260)
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
                Rectangle().fill(Theme.cream.opacity(0.14)).frame(width: 1)
                Rectangle().fill(Theme.cream.opacity(0.14)).frame(height: 1)
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
                Text(value).font(.system(size: 19, weight: .semibold, design: .default)).monospacedDigit().foregroundColor(Theme.cream)
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
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.cream.opacity(0.9))
                .frame(width: 32, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.cream.opacity(0.08)))
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
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.cream).lineLimit(1)
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
                        Chip(icon: "airplane", title: s.aircraft, subtitle: s.mode.isEmpty ? "Wing" : s.mode) { m.overlay = .aircraft }
                        Chip(icon: "map", title: s.site, subtitle: s.time) { m.overlay = .sites }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(s.camera).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.cream.opacity(0.85))
                            Text("\(s.input) · \(s.rates) · \(s.fps) fps").font(.system(size: 10)).monospacedDigit().foregroundColor(Theme.dim)
                        }
                        .padding(.trailing, 4).allowsHitTesting(false)
                        HStack(spacing: 5) {
                            BarButton(icon: "person.3.fill", help: "Formation and pilots") { m.game.cameFromMenu = false; m.overlay = m.overlay == .formation ? .none : .formation }
                            BarButton(icon: "wind", help: "Wind, weather and time of day") { m.game.cameFromMenu = false; m.overlay = m.overlay == .environment ? .none : .environment }
                            BarButton(icon: "gamecontroller", help: "Controller setup") { m.openControllerSetup?() }
                            BarButton(icon: "questionmark", help: "Keyboard controls (H)") { m.game.cameFromMenu = false; m.overlay = m.overlay == .help ? .none : .help }
                            BarButton(icon: "line.3.horizontal", help: "Main menu (Esc)") { m.overlay = .menu }
                        }
                        .padding(4).glass(10)
                    }
                    .padding(.leading, m.fullscreen ? 12 : 84).padding(.trailing, 12).padding(.top, 9)

                    HStack(alignment: .top) {
                        FormationBox(s: s) { m.game.cameFromMenu = false; m.overlay = .formation }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.top, 8)

                    if !s.score.isEmpty {
                        Text(s.score).font(.system(size: 14, weight: .bold, design: .default)).monospacedDigit().foregroundColor(Theme.cream)
                            .padding(.horizontal, 14).padding(.vertical, 6).glass(9).padding(.top, 8).allowsHitTesting(false)
                    }
                    Spacer()
                    // bottom: sticks and telemetry
                    HStack(alignment: .bottom) {
                        StickView(x: s.lx, y: s.ly, label: s.leftLabel)
                        Spacer()
                        VStack(spacing: 7) {
                            if !s.config.isEmpty {
                                Text(s.config).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundColor(Theme.cream)
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
            Group {
                switch m.overlay {
                // the main menu rises into place as the splash flies past the viewer and fades
                case .menu: MainMenu(m: m).transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                case .aircraft: AircraftBrowser(m: m)
                case .sites: SiteBrowser(m: m)
                case .environment: EnvironmentPanel(m: m)
                case .help: HelpView(m: m)
                case .formation: FormationPanel(m: m)
                case .splash: SplashView(m: m).transition(.asymmetric(insertion: .identity, removal: .scale(scale: 1.35).combined(with: .opacity)))
                case .none: EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: m.overlay == .splash)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.red)
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
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { m.overlay = back }
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.uppercased()).font(.system(size: 22, weight: .black)).tracking(0.5).foregroundColor(Theme.cream)
                    Text(subtitle).font(.system(size: 12.5)).foregroundColor(Theme.dim).padding(.leading, 6)
                    Spacer()
                    Button { m.overlay = back } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.cream.opacity(0.8))
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.cream.opacity(0.1)))
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                content
            }
            .frame(maxWidth: width, maxHeight: height)
            .glass(16, fill: Theme.panel)
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            .padding(28)
        }
    }
}

// MARK: - Aircraft browser

struct AircraftBrowser: View {
    @ObservedObject var m: HUDModel
    @AppStorage("aircraftCategory") private var category = "All"
    @State private var search = ""
    @State private var selected = 0

    private static let order = ["Trainers & Sport", "Scale Civil", "Warbirds", "Aerobatic", "Foam 3D", "Wings", "Jets", "Gliders", "Helicopters", "Multirotors"]
    private var all: [AircraftSpec] { AircraftLibrary.all }
    private var shown: [Int] {
        all.indices.filter { i in
            (category == "All" || all[i].category == category)
                && (search.isEmpty || all[i].name.localizedCaseInsensitiveContains(search) || all[i].blurb.localizedCaseInsensitiveContains(search))
        }
    }
    private func fly(_ i: Int) { m.game.selectAircraft(i); m.overlay = .menu }

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
                            .background(RoundedRectangle(cornerRadius: 7).fill(category == c ? Theme.red.opacity(0.85) : Color.clear))
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
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cream.opacity(0.07)))
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10)], spacing: 10) {
                            ForEach(shown, id: \.self) { i in
                                let spec = all[i]
                                VStack(alignment: .leading, spacing: 0) {
                                    Backdrop {
                                        if let img = m.thumbnail(spec) { Image(nsImage: img).resizable().scaledToFit().padding(4) }
                                    }
                                    .frame(height: 98).clipped()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(spec.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.cream).lineLimit(1)
                                        Text(spec.category).font(.system(size: 10.5)).foregroundColor(Theme.dim).lineLimit(1)
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                }
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected == i ? Theme.cream : Theme.stroke, lineWidth: selected == i ? 2 : 1))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { fly(i) }
                                .onTapGesture { selected = i }
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
                    Text(spec.name).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.cream).padding(.top, 14)
                    HStack(spacing: 8) { Tag(text: spec.category); Difficulty(level: spec.difficulty) }.padding(.top, 6)
                    Text(spec.blurb).font(.system(size: 13)).foregroundColor(Theme.cream.opacity(0.82)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
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
    }
}

// MARK: - Site browser

struct SiteBrowser: View {
    @ObservedObject var m: HUDModel
    @State private var selected = 0
    @AppStorage("siteFilter") private var filter = "All"       // stays as it was left, also after a restart
    @State private var search = ""
    private static let categories = ["Fields", "Airfields", "Mountains", "Water", "Desert", "Winter"]
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
            .background(RoundedRectangle(cornerRadius: 7).fill(filter == f ? Theme.red.opacity(0.85) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
    }
    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundColor(Theme.faint).padding(.leading, 10).padding(.top, 12).padding(.bottom, 3)
    }
    private func badge(_ site: SiteSpec) -> some View {
        Text(site.panorama != nil ? "360° PHOTO" : "3D").font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundColor(site.panorama != nil ? Theme.ink : Theme.cream)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(site.panorama != nil ? Theme.cream : Theme.red))
    }

    var body: some View {
        Sheet(m: m, title: "Choose Flying Site", subtitle: "\(all.count) sites", back: m.game.cameFromMenu ? .menu : .none) {
            HStack(spacing: 0) {
                // filters
                VStack(alignment: .leading, spacing: 2) {
                    filterRow("All", icon: "square.grid.2x2")
                    heading("LANDSCAPE")
                    filterRow("Fields", icon: "leaf")
                    filterRow("Airfields", icon: "airplane.departure")
                    filterRow("Mountains", icon: "mountain.2")
                    filterRow("Water", icon: "water.waves")
                    filterRow("Desert", icon: "sun.max")
                    filterRow("Winter", icon: "snowflake")
                    Spacer()
                    Button { m.addPanorama?() } label: { Label("Add Photo…", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                    Button { m.choosePanoramaFolder?() } label: { Label("Photo Folder…", systemImage: "folder").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
                    Text("Any 360° equirectangular photo becomes a site.").font(.system(size: 10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
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
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cream.opacity(0.07)))
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 172, maximum: 230), spacing: 10)], spacing: 10) {
                            ForEach(shown, id: \.self) { i in
                                let site = all[i]
                                VStack(alignment: .leading, spacing: 0) {
                                    ZStack(alignment: .topLeading) {
                                        LinearGradient(colors: [Color(red: 0.25, green: 0.4, blue: 0.6), Color(red: 0.2, green: 0.32, blue: 0.2)], startPoint: .top, endPoint: .bottom)
                                        if let img = m.sitePreview(site) { Image(nsImage: img).resizable().scaledToFill().frame(minWidth: 0, maxWidth: .infinity, minHeight: 104, maxHeight: 104).clipped() }
                                        badge(site).padding(7)
                                    }
                                    .frame(height: 104).clipped()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(site.displayName).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.cream).lineLimit(1)
                                        Text(site.category).font(.system(size: 10.5)).foregroundColor(Theme.dim).lineLimit(1)
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                }
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected == i ? Theme.cream : Theme.stroke, lineWidth: selected == i ? 2 : 1))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { fly(i) }
                                .onTapGesture { selected = i }
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
                    Text(site.displayName).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.cream).padding(.top, 14)
                    HStack(spacing: 8) { Tag(text: site.kindLabel); Tag(text: site.category); Difficulty(level: site.difficulty) }.padding(.top, 6)
                    Text(site.summary).font(.system(size: 13)).foregroundColor(Theme.cream.opacity(0.82)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
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
    private static let hold: Double = 4.0

    var body: some View {
        GeometryReader { g in
            ZStack {
                Theme.red
                if let img = Self.image {
                    // the artwork rushes toward the viewer and settles, then keeps drifting very slowly
                    Image(nsImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(arrived ? 1.0 : 1.22)
                        .blur(radius: arrived ? 0 : 14)
                        .opacity(arrived ? 1 : 0)
                        .scaleEffect(1 + 0.035 * progress)
                        .clipped()
                } else {
                    Text("FORMATION FLIGHT X").font(.system(size: 90, weight: .black)).foregroundColor(Theme.cream)
                        .scaleEffect(arrived ? 1 : 1.3).opacity(arrived ? 1 : 0)
                }
                // a slanted band of light sweeps across, like sun glinting off a wing
                LinearGradient(colors: [.clear, Theme.cream.opacity(0.0), Theme.cream.opacity(0.42), Theme.cream.opacity(0.0), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.55, height: g.size.height * 2.2)
                    .rotationEffect(.degrees(24))
                    .offset(x: sweep ? g.size.width * 1.1 : -g.size.width * 1.1)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                // a soft dark edge that eases off as the picture arrives
                RadialGradient(colors: [.clear, .black.opacity(arrived ? 0.28 : 0.75)], center: .center, startRadius: g.size.height * 0.35, endRadius: g.size.height * 1.05)
                    .allowsHitTesting(false)
                VStack(spacing: 12) {
                    Spacer()
                    Text("PRESS ANY KEY").font(.system(size: 11, weight: .heavy)).tracking(3)
                        .foregroundColor(Theme.cream.opacity(pulse ? 0.95 : 0.4))
                        .opacity(arrived ? 1 : 0)
                    // how long until it moves on by itself
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.cream.opacity(0.18))
                        Capsule().fill(Theme.cream.opacity(0.85)).frame(width: 220 * progress)
                    }
                    .frame(width: 220, height: 3).opacity(arrived ? 1 : 0)
                    .padding(.bottom, 22)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
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
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.5)) { pulse = true }
        withAnimation(.linear(duration: Self.hold)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { if m.overlay == .splash { m.overlay = .menu } }
    }
}

// MARK: - Main menu

private struct CreamButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Theme.ink)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cream.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}
private struct InkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.cream)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(configuration.isPressed ? 0.5 : 0.32)))
    }
}

struct MainMenu: View {
    @ObservedObject var m: HUDModel
    private static let logo: NSImage? = resourceURL("RockFPV.png").flatMap { NSImage(contentsOf: $0) }

    private func tile(_ label: String, _ title: String, _ sub: String, image: NSImage?, studio: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if studio { Backdrop { if let i = image { Image(nsImage: i).resizable().scaledToFit().padding(6) } } }
                    else { Color.black.opacity(0.3); if let i = image { Image(nsImage: i).resizable().scaledToFill() } }
                }
                .frame(width: 272, height: 152).clipped()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.system(size: 9.5, weight: .heavy)).tracking(1.6).foregroundColor(Theme.faint)
                        Text(title).font(.system(size: 14.5, weight: .bold)).foregroundColor(Theme.cream).lineLimit(1)
                        Text(sub).font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(1)
                    }
                    Spacer()
                    Text("CHANGE").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundColor(Theme.cream)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.red))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .frame(width: 272)
            .background(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).focusable(false)
    }

    var body: some View {
        let spec = m.game.aircraft.spec, site = m.game.site
        ZStack {
            Theme.ink.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("FLYING-WING FORMATION TRAINER").font(.system(size: 10.5, weight: .heavy)).tracking(3).foregroundColor(Theme.cream.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("FORMATION FLIGHT").foregroundColor(Theme.cream)
                    Text("X").foregroundColor(Theme.ink)
                }
                .font(.system(size: 50, weight: .black)).tracking(-1.5).padding(.top, 2).padding(.bottom, 16)
                HStack(spacing: 14) {
                    tile("WING", spec.name, String(format: "%.2f m span · %.0f g", spec.span, spec.mass * 1000), image: m.thumbnail(spec), studio: true) { m.game.cameFromMenu = true; m.overlay = .aircraft }
                    tile("FLYING SITE", site.displayName, site.kindLabel, image: m.sitePreview(site), studio: false) { m.game.cameFromMenu = true; m.overlay = .sites }
                }
                Button { m.game.cameFromMenu = true; m.overlay = .formation } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill").font(.system(size: 17, weight: .bold)).foregroundColor(Theme.cream).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FORMATION").font(.system(size: 9.5, weight: .heavy)).tracking(1.6).foregroundColor(Theme.faint)
                            Text("\(m.game.formation.name) · \(Formation.spacingNames[m.game.spacing]) spacing").font(.system(size: 14.5, weight: .bold)).foregroundColor(Theme.cream)
                            Text(m.s.mates.isEmpty ? (m.s.net.isEmpty ? "Flying alone" : m.s.net) : "With " + m.s.mates.map { $0.name }.joined(separator: " and ") + (m.s.net.isEmpty ? "" : " · " + m.s.net))
                                .font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(1)
                        }
                        Spacer()
                        Text("CHANGE").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundColor(Theme.cream)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.red))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain).focusable(false).padding(.top, 14)
                Button { m.game.cameFromMenu = false; m.overlay = .none } label: {
                    HStack(spacing: 10) { Image(systemName: "play.fill"); Text("CLEARED FOR TAKE-OFF").tracking(2) }
                        .font(.system(size: 15, weight: .black)).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(CreamButton()).keyboardShortcut(.defaultAction).padding(.top, 16)
                HStack(spacing: 8) {
                    Button { m.game.cameFromMenu = true; m.overlay = .environment } label: { Label("Weather", systemImage: "wind") }.buttonStyle(InkButton())
                    Button { m.openControllerSetup?() } label: { Label("Controller", systemImage: "gamecontroller") }.buttonStyle(InkButton())
                    Button { m.game.cameFromMenu = true; m.overlay = .help } label: { Label("Controls", systemImage: "keyboard") }.buttonStyle(InkButton())
                    Button { m.game.musicEnabled.toggle(); m.objectWillChange.send() } label: { Label("Music", systemImage: m.game.musicEnabled ? "music.note" : "speaker.slash") }.buttonStyle(InkButton())
                        .help(m.game.musicEnabled ? "Turn the menu music off" : "Turn the menu music on")
                    Spacer()
                    Button { NSApp.terminate(nil) } label: { Text("Quit") }.buttonStyle(InkButton())
                }
                .padding(.top, 12)
                Rectangle().fill(Theme.cream.opacity(0.5)).frame(height: 1.5).padding(.top, 16)
                HStack(spacing: 10) {
                    if let logo = Self.logo { Image(nsImage: logo).resizable().frame(width: 34, height: 34) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CREATED BY").font(.system(size: 8.5, weight: .heavy)).tracking(2).foregroundColor(Theme.cream.opacity(0.8))
                        Text("ROCK FPV").font(.system(size: 15, weight: .black)).foregroundColor(Theme.cream)
                    }
                    Spacer()
                    Text("GRAPHICS").font(.system(size: 9.5, weight: .heavy)).tracking(1.6).foregroundColor(Theme.cream.opacity(0.8))
                    Picker("", selection: Binding(get: { m.game.quality }, set: { m.game.quality = $0; m.objectWillChange.send() })) {
                        ForEach(0..<3, id: \.self) { Text(Game.qualityNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                .padding(.top, 12)
            }
            .padding(28)
            .frame(width: 614)
            .background(
                ZStack {
                    Theme.red
                    Circle().fill(Theme.deepRed.opacity(0.45)).frame(width: 620, height: 620).offset(x: 250, y: -40)
                    Circle().fill(Theme.deepRed.opacity(0.45)).frame(width: 400, height: 400).offset(x: 250, y: -40)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 40, y: 16)
        }
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
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.cream.opacity(0.9))
                Spacer()
                Text(value).font(.system(size: 12.5)).monospacedDigit().foregroundColor(Theme.dim)
            }
            Slider(value: b, in: range).controlSize(.small)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.cream.opacity(0.55)).padding(.top, 3)
    }
    private func level(_ v: Float, _ names: [String]) -> String { names[min(Int(v * Float(names.count)), names.count - 1)] }
    private func pick(_ title: String, _ names: [String], _ sel: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.cream.opacity(0.9))
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
                        Text("Weather").font(.system(size: 17, weight: .bold)).foregroundColor(Theme.cream)
                        Spacer()
                        Button { m.overlay = m.game.cameFromMenu ? .menu : .none } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.cream.opacity(0.8))
                                .frame(width: 24, height: 24).background(Circle().fill(Theme.cream.opacity(0.1)))
                        }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    }
                    Menu {
                        ForEach(Array(Environment.presets.enumerated()), id: \.offset) { i, n in
                            Button(n) { env.apply(preset: i); m.objectWillChange.send() }
                        }
                    } label: { Label("Choose a preset", systemImage: "cloud.sun").frame(maxWidth: .infinity) }
                    .menuStyle(.borderlessButton).padding(.vertical, 5).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.cream.opacity(0.1)))
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
                    ("X", "Throttle cut"), ("Q", "Wheel brakes"), ("Shift", "Full stick deflection"), ("L", "High / low rates"), ("−  =", "Pitch trim: nose down / up"), ("0", "Centre the pitch trim"), ("Space", "Start again with a hand launch")]),
        ("Formation", [("J", "Join up: start in the air behind your slot"), ("U", "Take the lead / hand it back"), ("O", "Next formation (lead only)"), ("I", "Spacing: tight, normal, loose (lead only)"),
                       ("G", "Computer partners on / off"), ("Y", "Smoke"), ("[  ]", "Previous / next wing"), ("Tab", "Wing browser")]),
        ("View and simulation", [("C", "Camera: chase, onboard, pilot"), ("Z", "Zoom mode"), ("V", "Hide / show display"), ("P", "Pause"),
                                 ("T", "Slow motion"), (",  .", "Less / more wind"), ("N", "Next flying site"), ("B", "Balloon Burst challenge"),
                                 ("K", "Autopilot for your own wing"), ("M", "Mute sound"), ("Esc", "Main menu")]),
    ]
    var body: some View {
        Sheet(m: m, title: "Controls", subtitle: "Keyboard", back: m.game.cameFromMenu ? .menu : .none, width: 940, height: 520) {
            HStack(alignment: .top, spacing: 26) {
                ForEach(groups, id: \.0) { g in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(g.0.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.5).foregroundColor(Theme.cream.opacity(0.6)).padding(.bottom, 3)
                        ForEach(g.1, id: \.0) { k in
                            HStack(spacing: 10) {
                                Text(k.0).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundColor(Theme.cream)
                                    .frame(minWidth: 46).padding(.vertical, 3).padding(.horizontal, 5)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.cream.opacity(0.1)))
                                Text(k.1).font(.system(size: 12.5)).foregroundColor(Theme.cream.opacity(0.85))
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
private struct SlotScope: View {
    var e: V3, tol: Float, good: Bool
    var body: some View {
        let size: CGFloat = 92, range = CGFloat(max(tol * 4, 2))
        let col = good ? Color(red: 0.3, green: 0.95, blue: 0.45) : Color(red: 1, green: 0.72, blue: 0.2)
        func clampP(_ v: Float) -> CGFloat { min(max(CGFloat(v) / range, -1), 1) * size / 2 }
        return HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cream.opacity(0.06))
                Rectangle().fill(Theme.cream.opacity(0.18)).frame(width: 1, height: size)
                Rectangle().fill(Theme.cream.opacity(0.18)).frame(width: size, height: 1)
                // the slot, drawn to scale, and this aircraft at the centre
                Circle().stroke(col, lineWidth: 1.6).frame(width: CGFloat(tol) / range * size, height: CGFloat(tol) / range * size)
                    .offset(x: clampP(e.x), y: -clampP(e.z))
                Image(systemName: "triangle.fill").font(.system(size: 9)).foregroundColor(Theme.cream)
            }
            .frame(width: size, height: size).clipped()
            ZStack {
                Capsule().fill(Theme.cream.opacity(0.08)).frame(width: 6, height: size)
                Rectangle().fill(Theme.cream.opacity(0.3)).frame(width: 12, height: 1)
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
                        Text(s.role).font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundColor(Theme.cream)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.red))
                        if !s.formation.isEmpty { Text(s.formation).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.cream) }
                    }
                    ForEach(s.mates) { mt in
                        HStack(spacing: 6) {
                            Text("\(mt.number)").font(.system(size: 10.5, weight: .heavy)).foregroundColor(Theme.ink)
                                .frame(width: 16, height: 16).background(Circle().fill(Theme.cream.opacity(mt.number == 1 ? 1 : 0.7)))
                            Text(mt.name).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.cream).lineLimit(1)
                            Text(mt.detail).font(.system(size: 11)).monospacedDigit()
                                .foregroundColor(mt.good ? Color(red: 0.3, green: 0.95, blue: 0.45) : Theme.dim).lineLimit(1)
                        }
                    }
                    if !s.station.isEmpty {
                        Text(s.station).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                            .foregroundColor(s.onStation ? Color(red: 0.3, green: 0.95, blue: 0.45) : Theme.cream.opacity(0.9))
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
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundColor(Theme.cream.opacity(0.55))
    }
    private func field(_ title: String, _ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.cream.opacity(0.9))
            TextField(prompt, text: text).textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.cream)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.cream.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
        }
    }
    private func person(_ number: Int, _ name: String, _ detail: String, me: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 13, weight: .heavy)).foregroundColor(number == 1 ? Theme.cream : Theme.ink)
                .frame(width: 26, height: 26).background(Circle().fill(number == 1 ? Theme.red : Theme.cream.opacity(0.8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name + (me ? "  (you)" : "")).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.cream)
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
        Sheet(m: m, title: "Formation", subtitle: "Up to three pilots, straight from Mac to Mac", back: g.cameFromMenu ? .menu : .none, width: 900, height: 600) {
            HStack(alignment: .top, spacing: 0) {
                // the shape
                VStack(alignment: .leading, spacing: 8) {
                    heading("FORMATION")
                    ForEach(FormationKind.allCases, id: \.rawValue) { k in
                        Button { if leading { g.formation = k; m.objectWillChange.send() } } label: {
                            HStack(spacing: 10) {
                                FormationGlyph(kind: k).frame(width: 46, height: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k.name).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.cream)
                                    Text(k.blurb).font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(g.formation == k ? Theme.red.opacity(0.85) : Theme.card))
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
                        Text("Formation, spacing, flying site and weather are set by the lead, \(g.name(of: g.leadID)).")
                            .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20).frame(width: 400)
                .disabled(false)
                Rectangle().fill(Theme.stroke).frame(width: 1)
                // the pilots
                VStack(alignment: .leading, spacing: 10) {
                    heading("PILOTS")
                    ForEach(Array(g.order.enumerated()), id: \.element) { k, id in
                        if id == g.net.id { person(k + 1, g.pilotName, g.aircraft.spec.name, me: true) }
                        else if let w = g.wingmen.first(where: { $0.id == id }) {
                            person(k + 1, w.name, w.aircraft.spec.name + (w.ai != nil ? " · flown by the computer" : ""), me: false)
                        }
                    }
                    Button { g.takeLead(); m.objectWillChange.send() } label: {
                        Text(leading && g.leadEpoch > 0 ? "Hand Back the Lead" : "Take the Lead").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButton()).disabled(leading && g.leadEpoch == 0)
                    heading("YOU").padding(.top, 6)
                    HStack(spacing: 10) {
                        field("Pilot name", Binding(get: { g.pilotName }, set: { g.pilotName = String($0.prefix(24)); m.objectWillChange.send() }), "Your name")
                        field("Group", Binding(get: { g.group }, set: { g.group = String($0.prefix(24)); m.objectWillChange.send() }), "Everyone")
                    }
                    Text("Pilots with the same group name fly together. Leave it empty to fly with anyone on the network.")
                        .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    Toggle(isOn: Binding(get: { g.multiplayer }, set: { g.multiplayer = $0; m.objectWillChange.send() })) {
                        Text("Fly with pilots on the local network").font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.cream.opacity(0.9))
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    Toggle(isOn: Binding(get: { g.aiPartners }, set: { g.aiPartners = $0; m.objectWillChange.send() })) {
                        Text("Computer partners while I am alone").font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.cream.opacity(0.9))
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    if !m.s.net.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: g.remotePilots.isEmpty ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill").foregroundColor(Theme.red)
                            Text(m.s.net).font(.system(size: 11.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("No server and no account: the Macs find each other on the same Wi-Fi or cable network, or directly over peer-to-peer Wi-Fi, and exchange positions sixty times a second.")
                        .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Three little wings in the shape of a formation, seen from above with the lead at the top.
private struct FormationGlyph: View {
    var kind: FormationKind
    var body: some View {
        GeometryReader { g in
            let u = min(g.size.width / 5.2, g.size.height / 4.6)
            let pts: [V3] = [V3(0, 0, 0), kind.offset(1), kind.offset(2)]
            let cx = pts.map { $0.x }.reduce(0, +) / 3, cz = pts.map { $0.z }.reduce(0, +) / 3
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "triangle.fill").font(.system(size: u * 0.95))
                        .foregroundColor(i == 0 ? Theme.cream : Theme.cream.opacity(0.6))
                        .position(x: g.size.width / 2 + CGFloat(pts[i].x - cx) * u * 1.15, y: g.size.height / 2 + CGFloat(pts[i].z - cz) * u * 1.15)
                }
            }
        }
    }
}
