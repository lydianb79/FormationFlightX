import Foundation
import AppKit
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
    // push to talk: a keyboard key (key code and what to call it) and a gamepad button; a transmitter switch is a binding
    var talkKey: UInt16? = nil
    var talkKeyName: String? = nil
    var talkPad: Int? = nil
    // launch: the same three ways
    var launchKey: UInt16? = nil
    var launchKeyName: String? = nil
    var launchPad: Int? = nil

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
        ControlAction(id: "talk", title: "Push to talk", states: -1, key: 0),
        ControlAction(id: "launch", title: "Launch (throw the aircraft)", states: 0, key: 0xFFF0),
        ControlAction(id: "rates", title: "Rates: low / high", states: 2, key: 37),
        ControlAction(id: "smoke", title: "Smoke", states: 2, key: 16),
        ControlAction(id: "flaps", title: "Flaps: up / half / full", states: 3, key: 14),
        ControlAction(id: "gear", title: "Landing gear", states: 2, key: 5),
        ControlAction(id: "join", title: "Join up on the lead", states: 0, key: 38),
        ControlAction(id: "lead", title: "Take the lead / hand it back", states: 0, key: 32),
        ControlAction(id: "formation", title: "Next formation", states: 0, key: 31),
        ControlAction(id: "spacing", title: "Next spacing", states: 0, key: 34),
        ControlAction(id: "trimUp", title: "Pitch trim: nose up", states: 0, key: 24),
        ControlAction(id: "trimDown", title: "Pitch trim: nose down", states: 0, key: 27),
        ControlAction(id: "reset", title: "Start again (hand launch)", states: 0, key: 49),
        ControlAction(id: "camera", title: "Camera", states: 0, key: 8),
        ControlAction(id: "zoom", title: "Zoom", states: 0, key: 6),
        ControlAction(id: "lobby", title: "Lobby", states: 0, key: 36),
        ControlAction(id: "demo", title: "Autopilot for your own wing", states: 0, key: 40),
        ControlAction(id: "hud", title: "Hide / show display", states: 0, key: 9),
        ControlAction(id: "mute", title: "Mute sound", states: 0, key: 46),
    ]

    // MARK: Push to talk

    static let padButtons = ["None", "A", "B", "X", "Y", "Left shoulder", "Right shoulder", "Left stick click", "Right stick click", "D-pad up", "D-pad down", "D-pad left", "D-pad right"]
    /// The keyboard key that is held to talk (B unless the pilot chose another).
    var talkKey: UInt16 { settings.talkKey ?? 11 }
    var talkKeyName: String { settings.talkKeyName ?? "B" }
    var talkPad: Int { min(max(settings.talkPad ?? 5, 0), InputManager.padButtons.count - 1) }

    /// Push to talk held on a controller: the assigned switch or button of a USB transmitter, or the chosen gamepad button.
    var talkOnDevice: Bool {
        if hid.connected, let b = settings.bindings?["talk"], value(of: b) > 0.3 { return true }
        return padPressed(talkPad)
    }

    /// Whether the gamepad button with this number in `padButtons` is down.
    func padPressed(_ n: Int) -> Bool {
        guard let gp = GCController.controllers().compactMap({ $0.extendedGamepad }).first else { return false }
        switch n {
        case 1: return gp.buttonA.isPressed
        case 2: return gp.buttonB.isPressed
        case 3: return gp.buttonX.isPressed
        case 4: return gp.buttonY.isPressed
        case 5: return gp.leftShoulder.isPressed
        case 6: return gp.rightShoulder.isPressed
        case 7: return gp.leftThumbstickButton?.isPressed ?? false
        case 8: return gp.rightThumbstickButton?.isPressed ?? false
        case 9: return gp.dpad.up.isPressed
        case 10: return gp.dpad.down.isPressed
        case 11: return gp.dpad.left.isPressed
        case 12: return gp.dpad.right.isPressed
        default: return false
        }
    }

    // MARK: Launch

    /// The key that throws the aircraft (Space unless the pilot chose another), and the gamepad button that does.
    var launchKey: UInt16 { settings.launchKey ?? 49 }
    var launchKeyName: String { settings.launchKeyName ?? "Space" }
    var launchPad: Int { min(max(settings.launchPad ?? 6, 0), InputManager.padButtons.count - 1) }
    /// What to press to launch, on whatever the pilot is flying with.
    var launchHint: String {
        if hid.connected, let b = settings.bindings?["launch"] { return InputManager.label(b) + " or " + launchKeyName }
        if GCController.controllers().contains(where: { $0.extendedGamepad != nil }), launchPad > 0 { return InputManager.padButtons[launchPad] + " or " + launchKeyName }
        return launchKeyName
    }

    /// What to hold to talk, on whatever the pilot is flying with.
    var talkHint: String {
        if hid.connected, let b = settings.bindings?["talk"] { return InputManager.label(b).lowercased() + " or the \(talkKeyName) key" }
        if GCController.controllers().contains(where: { $0.extendedGamepad != nil }), talkPad > 0 { return InputManager.padButtons[talkPad].lowercased() + " or the \(talkKeyName) key" }
        return "the \(talkKeyName) key"
    }

    /// A name for a key, for the setup window.
    static func keyName(_ e: NSEvent) -> String {
        let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 76: "Enter",
                                        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let n = special[e.keyCode] { return n }
        let c = (e.charactersIgnoringModifiers ?? "").uppercased()
        return c.isEmpty || c.unicodeScalars.first!.value < 33 ? "Key \(e.keyCode)" : c
    }

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
    /// The share of a USB axis's range that a stick has to cover to be taken as calibrated on 100% rates. The
    /// transmitter's own rates can't be seen or changed from here, only the shorter travel they leave.
    static let fullTravel: Float = 0.95
    /// The dual rate in effect: always 100% while calibrating, whatever is selected.
    var rateInUse: Float { calibrating || !lowRates ? 1 : lowRateInUse }

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
        return ((1 - k) * v + k * v * v * v) * rateInUse
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

    /// The channels that have not reached full travel in this recording, with the share they did reach.
    var shortTravel: [(channel: Int, travel: Float)] {
        guard calibrating else { return [] }
        return (0..<4).compactMap { i in
            let a = min(max(settings.axis[i], 0), 8), travel = (recMax[a] - recMin[a]) / 2
            return travel < InputManager.fullTravel ? (i, travel) : nil
        }
    }

    /// Closing the setup window: back to the selected rates, the saved calibration untouched.
    func cancelCalibration() { calibrating = false }

    /// Call with the sticks centred. Saves nothing and keeps recording while a channel is short of full travel,
    /// unless the pilot accepts that. Axes that were not moved keep their previous calibration.
    func finishCalibration(acceptShort: Bool = false) {
        guard calibrating, acceptShort || shortTravel.isEmpty else { return }
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
        let full: Float = (keys.contains(56) || keys.contains(60) ? 1 : 0.75) * rateInUse
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
