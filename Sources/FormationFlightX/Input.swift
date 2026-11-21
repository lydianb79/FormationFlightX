import Foundation
import GameController
import IOKit
import IOKit.hid
import AVFoundation

/// Raw USB joystick access. RC transmitters and simulator dongles show up as generic HID
/// joysticks, which the GameController framework ignores, so they are read through IOKit.
final class HIDJoystick {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var axes = [Float](repeating: 0, count: 9)
    var buttons = [Bool](repeating: false, count: 32)
    /// Devices that identify as joysticks or multi-axis controllers, and those that identify as gamepads.
    /// Many RC transmitters (DJI, some EdgeTX modes) report as gamepads, like console controllers do.
    private(set) var joysticks: [IOHIDDevice] = []
    private(set) var gamepads: [IOHIDDevice] = []
    var name = ""

    private static func product(_ d: IOHIDDevice) -> String { (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "USB Controller" }
    private static func isGamepad(_ d: IOHIDDevice) -> Bool { (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int) == kHIDUsage_GD_GamePad }

    private func store(_ el: IOHIDElement, _ raw: Int) {
        if IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_Button) {
            let b = Int(IOHIDElementGetUsage(el)) - 1
            if b >= 0 && b < buttons.count { buttons[b] = raw != 0 }
            return
        }
        guard IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_GenericDesktop) else { return }
        let idx = Int(IOHIDElementGetUsage(el)) - kHIDUsage_GD_X
        guard idx >= 0 && idx < 9 else { return }
        let lo = Float(IOHIDElementGetLogicalMin(el)), hi = Float(IOHIDElementGetLogicalMax(el))
        guard hi > lo else { return }
        axes[idx] = clampf((Float(raw) - lo) / (hi - lo) * 2 - 1, -1, 1)
    }

    /// Read where the sticks are right now; change reports only arrive once something moves.
    private func readCurrent(_ d: IOHIDDevice) {
        for el in (IOHIDDeviceCopyMatchingElements(d, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? [] {
            let page = IOHIDElementGetUsagePage(el)
            guard page == UInt32(kHIDPage_GenericDesktop) || page == UInt32(kHIDPage_Button) else { continue }
            var ref: Unmanaged<IOHIDValue>?
            let ok = withUnsafeMutablePointer(to: &ref) { p in
                p.withMemoryRebound(to: Unmanaged<IOHIDValue>.self, capacity: 1) { IOHIDDeviceGetValue(d, el, $0) == kIOReturnSuccess }
            }
            if ok, let v = ref?.takeUnretainedValue() { store(el, IOHIDValueGetIntegerValue(v)) }
        }
    }

    init() {
        let match: [[String: Any]] = [kHIDUsage_GD_Joystick, kHIDUsage_GD_GamePad, kHIDUsage_GD_MultiAxisController].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            let me = Unmanaged<HIDJoystick>.fromOpaque(ctx!).takeUnretainedValue()
            if HIDJoystick.isGamepad(device) { me.gamepads.append(device) } else { me.joysticks.append(device) }
            me.name = HIDJoystick.product(device)
            me.readCurrent(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            let me = Unmanaged<HIDJoystick>.fromOpaque(ctx!).takeUnretainedValue()
            me.joysticks.removeAll { $0 == device }
            me.gamepads.removeAll { $0 == device }
            if let d = me.joysticks.last ?? me.gamepads.last { me.name = HIDJoystick.product(d) }
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            let me = Unmanaged<HIDJoystick>.fromOpaque(ctx!).takeUnretainedValue()
            me.store(IOHIDValueGetElement(value), IOHIDValueGetIntegerValue(value))
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// A transmitter is in use. Gamepad-class devices count only when the system has not already
    /// turned them into a standard game controller (Xbox, PlayStation and similar), which is handled separately.
    var connected: Bool {
        if !joysticks.isEmpty { return true }
        return !gamepads.isEmpty && !GCController.controllers().contains { $0.extendedGamepad != nil }
    }
}

/// A switch or button on the controller assigned to an action.
struct ControlBinding: Codable, Equatable {
    var axis: Bool              // true: a switch that reports as an axis; false: a button
    var index: Int
    var follow = false          // buttons only: true = a latching switch whose position sets the state, false = each press steps on
}

/// Controller settings, saved in user defaults. Channel order: aileron, elevator, throttle, rudder.
struct InputSettings: Codable {
    var axis = [0, 1, 2, 3]
    var invert = [false, true, false, false]
    // per USB axis calibration (raw values are -1...1 from the device's reported range)
    var calMin = [Float](repeating: -1, count: 9)
    var calMid = [Float](repeating: 0, count: 9)
    var calMax = [Float](repeating: 1, count: 9)
    var stickMode = 2                       // 1-4, for gamepads and the on-screen stick display
    var lowRate: Float = 0.6                // control throw on low rates
    var expo: [Float] = [0.25, 0.25, 0.2]   // aileron, elevator, rudder
    var deadband: Float = 0.03
    var multiPitchReverse: Bool? = nil      // reverse the pitch stick on multirotors only
    var ownRates: Bool? = nil               // true: use the low rate and expo above for every aircraft instead of each aircraft's own
    var bindings: [String: ControlBinding]? = nil       // actions assigned to switches and buttons

    static let axisNames = ["X", "Y", "Z", "Rx", "Ry", "Rz", "Slider", "Dial", "Wheel"]
    static let channelNames = ["Aileron", "Elevator", "Throttle", "Rudder"]
    static let modeNames = ["Mode 1  (left: elevator + rudder, right: throttle + aileron)",
                            "Mode 2  (left: throttle + rudder, right: elevator + aileron)",
                            "Mode 3  (left: elevator + aileron, right: throttle + rudder)",
                            "Mode 4  (left: throttle + aileron, right: elevator + rudder)"]

    var valid: Bool {
        axis.count == 4 && invert.count == 4 && calMin.count == 9 && calMid.count == 9 && calMax.count == 9 && expo.count == 3 && (1...4).contains(stickMode)
    }
}

/// Something the pilot can do from the keyboard that can also be put on a controller switch or button.
/// `states`: 0 = happens once per press; 2 or 3 = a setting with that many positions; -1 = held down.
struct ControlAction {
    let id: String, title: String, states: Int, key: UInt16
}

final class InputManager {
    static let actions: [ControlAction] = [
        ControlAction(id: "rates", title: "Rates: low / high", states: 2, key: 37),
        ControlAction(id: "mode", title: "Flight mode", states: 2, key: 3),
        ControlAction(id: "rotor", title: "Rotor speed (helicopters)", states: 3, key: 34),
        ControlAction(id: "hold", title: "Throttle hold (helicopters)", states: 2, key: 32),
        ControlAction(id: "flaps", title: "Flaps: up / half / full", states: 3, key: 14),
        ControlAction(id: "gear", title: "Landing gear", states: 2, key: 5),
        ControlAction(id: "smoke", title: "Smoke", states: 2, key: 16),
        ControlAction(id: "trimUp", title: "Pitch trim: nose up", states: 0, key: 24),
        ControlAction(id: "trimDown", title: "Pitch trim: nose down", states: 0, key: 27),
        ControlAction(id: "brake", title: "Wheel brakes", states: -1, key: 12),
        ControlAction(id: "reset", title: "Reset aircraft", states: 0, key: 49),
        ControlAction(id: "camera", title: "Camera", states: 0, key: 8),
        ControlAction(id: "zoom", title: "Zoom", states: 0, key: 6),
        ControlAction(id: "pause", title: "Pause", states: 0, key: 35),
        ControlAction(id: "slow", title: "Slow motion", states: 0, key: 17),
        ControlAction(id: "next", title: "Next aircraft", states: 0, key: 30),
        ControlAction(id: "prev", title: "Previous aircraft", states: 0, key: 33),
        ControlAction(id: "site", title: "Next flying site", states: 0, key: 45),
        ControlAction(id: "demo", title: "Demo pilot", states: 0, key: 40),
        ControlAction(id: "balloons", title: "Balloon challenge", states: 0, key: 11),
        ControlAction(id: "windDown", title: "Less wind", states: 0, key: 43),
        ControlAction(id: "windUp", title: "More wind", states: 0, key: 47),
        ControlAction(id: "hud", title: "Hide / show display", states: 0, key: 9),
        ControlAction(id: "mute", title: "Mute sound", states: 0, key: 46),
    ]
    /// Where an assigned switch or button is: -1...1 for an axis, -1 or 1 for a button.
    func value(of b: ControlBinding) -> Float {
        if b.axis { return b.index >= 0 && b.index < hid.axes.count ? hid.axes[b.index] : 0 }
        return b.index >= 0 && b.index < hid.buttons.count && hid.buttons[b.index] ? 1 : -1
    }
    static func label(_ b: ControlBinding?) -> String {
        guard let b = b else { return "not assigned" }
        return b.axis ? "Switch on axis " + InputSettings.axisNames[min(max(b.index, 0), 8)] : "Button \(b.index + 1)"
    }
    var keys = Set<UInt16>()
    let hid = HIDJoystick()
    var settings = InputSettings() { didSet { if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "inputSettings") } } }
    var lowRates = true
    /// Low rate and expo recommended for the aircraft being flown; used unless the pilot has chosen their own.
    var aircraftLowRate: Float = 0.6, aircraftExpo: Float = 0.3
    var lowRateInUse: Float { settings.ownRates == true ? settings.lowRate : aircraftLowRate }
    private var kb = V3.zero
    var kbThrottle: Float = 0
    var source = "Keyboard"

    // calibration recording
    private(set) var calibrating = false
    private var recMin = [Float](repeating: 0, count: 9), recMax = [Float](repeating: 0, count: 9)

    init() {
        if let d = UserDefaults.standard.data(forKey: "inputSettings"), let m = try? JSONDecoder().decode(InputSettings.self, from: d), m.valid {
            settings = m
        }
    }

    func resetThrottle(_ kind: AircraftKind, launch: Bool) { kbThrottle = kind == .helicopter ? 0.5 : (launch ? 0.75 : 0) }

    private func down(_ k: UInt16) -> Float { keys.contains(k) ? 1 : 0 }

    /// Deadband, expo and dual rate for a centred channel (0 aileron, 1 elevator, 2 rudder).
    private func shape(_ x: Float, _ i: Int) -> Float {
        let db = clampf(settings.deadband, 0, 0.3)
        let m = abs(x)
        if m <= db { return 0 }
        let v = (x < 0 ? -1 : 1) * min((m - db) / (1 - db), 1)
        let k = clampf(settings.ownRates == true ? settings.expo[i] : aircraftExpo, 0, 1)
        return ((1 - k) * v + k * v * v * v) * (lowRates ? lowRateInUse : 1)
    }

    /// Calibrated value of a USB axis: centred channels map min/centre/max to -1/0/+1, throttle maps min/max to -1/+1.
    private func calibrated(_ a: Int, centred: Bool) -> Float {
        let v = hid.axes[a], lo = settings.calMin[a], mid = settings.calMid[a], hi = settings.calMax[a]
        if centred {
            if v >= mid { return hi - mid > 0.05 ? clampf((v - mid) / (hi - mid), 0, 1) : 0 }
            return mid - lo > 0.05 ? clampf((v - mid) / (mid - lo), -1, 0) : 0
        }
        return hi - lo > 0.05 ? clampf((v - lo) / (hi - lo) * 2 - 1, -1, 1) : 0
    }

    /// Calibrated transmitter channel (0 aileron, 1 elevator, 2 throttle, 3 rudder), before expo and rates.
    func channel(_ i: Int) -> Float {
        let v = calibrated(min(max(settings.axis[i], 0), 8), centred: i != 2)
        return settings.invert[i] ? -v : v
    }

    func startCalibration() {
        recMin = hid.axes; recMax = hid.axes
        calibrating = true
    }

    /// Call with the sticks centred. Axes that were not moved keep their previous calibration.
    func finishCalibration() {
        guard calibrating else { return }
        calibrating = false
        var s = settings
        for a in 0..<9 where recMax[a] - recMin[a] > 0.5 {
            s.calMin[a] = recMin[a]; s.calMax[a] = recMax[a]
            s.calMid[a] = clampf(hid.axes[a], recMin[a] + 0.1, recMax[a] - 0.1)
        }
        settings = s
    }

    func resetCalibration() {
        calibrating = false
        var s = settings
        s.calMin = [Float](repeating: -1, count: 9); s.calMid = [Float](repeating: 0, count: 9); s.calMax = [Float](repeating: 1, count: 9)
        settings = s
    }

    func poll(dt: Float, kind: AircraftKind) -> Controls {
        var c = Controls()
        if calibrating { for a in 0..<9 { recMin[a] = min(recMin[a], hid.axes[a]); recMax[a] = max(recMax[a], hid.axes[a]) } }

        // keyboard: arrows = elevator / aileron, A/D = rudder, W/S = throttle
        let full: Float = (keys.contains(56) || keys.contains(60) ? 1 : 0.75) * (lowRates ? lowRateInUse : 1)
        let tgt = V3(down(124) - down(123), down(125) - down(126), down(2) - down(0)) * full
        for i in 0..<3 {
            let rate: Float = tgt[i] == 0 ? 7 : 4.5
            kb[i] += clampf(tgt[i] - kb[i], -rate * dt, rate * dt)
        }
        kbThrottle = clampf(kbThrottle + (down(13) - down(1)) * 0.7 * dt, 0, 1)
        if keys.contains(7) { kbThrottle = kind == .helicopter ? 0.5 : 0 }

        var dev = V3.zero       // aileron, elevator, rudder
        var thr = kbThrottle
        if hid.connected {
            source = hid.name
            dev = V3(shape(channel(0), 0), shape(channel(1), 1), shape(channel(3), 2))
            thr = (channel(2) + 1) / 2
        } else if let gp = GCController.controllers().compactMap({ $0.extendedGamepad }).first {
            source = gp.controller?.vendorName ?? "Gamepad"
            let lx = gp.leftThumbstick.xAxis.value, ly = gp.leftThumbstick.yAxis.value
            let rx = gp.rightThumbstick.xAxis.value, ry = gp.rightThumbstick.yAxis.value
            var a: Float, e: Float, r: Float, t: Float
            switch settings.stickMode {
            case 1: e = -ly; r = lx; t = ry; a = rx
            case 3: e = -ly; a = lx; t = ry; r = rx
            case 4: t = ly; a = lx; e = -ry; r = rx
            default: t = ly; r = lx; e = -ry; a = rx
            }
            dev = V3(shape(a, 0), shape(e, 1), shape(r, 2))
            // sprung throttle stick: airplanes use the upper half (or the right trigger), rotorcraft the full travel
            thr = kind == .airplane ? max(max(t, 0), gp.rightTrigger.value) : (t + 1) / 2
            c.brake = gp.leftTrigger.value
        } else {
            source = "Keyboard"
        }
        c.aileron = clampf(dev.x + kb.x, -1, 1)
        c.elevator = clampf(dev.y + kb.y, -1, 1)
        if kind == .multirotor && settings.multiPitchReverse == true { c.elevator = -c.elevator }
        c.rudder = clampf(dev.z + kb.z, -1, 1)
        c.throttle = clampf(thr, 0, 1)
        c.brake = max(c.brake, down(12))          // Q
        if hid.connected, let b = settings.bindings?["brake"], value(of: b) > 0.3 { c.brake = 1 }
        return c
    }
}
