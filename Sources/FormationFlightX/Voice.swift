import AVFoundation
import Foundation
import QuartzCore

// Voice between the pilots. The microphone is cut into 20 ms frames of 16 kHz mono, each coded with Opus
// (about 3 KB per second of speech) and sent like any other message; every other pilot's frames are decoded
// and played through their own player, so two people can talk at once.

/// Opus coding of single frames, through the system's audio converter.
final class VoiceCodec {
    static let rate = 16000.0, frame = 320
    static let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    static let opus: AVAudioFormat = {
        var d = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
                                            mFramesPerPacket: UInt32(frame), mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        return AVAudioFormat(streamDescription: &d)!
    }()
    private let converter: AVAudioConverter?
    private let encoding: Bool

    init(encoder: Bool) {
        encoding = encoder
        converter = encoder ? AVAudioConverter(from: VoiceCodec.pcm, to: VoiceCodec.opus) : AVAudioConverter(from: VoiceCodec.opus, to: VoiceCodec.pcm)
        if encoder { converter?.bitRate = 20000 }
    }
    var available: Bool { converter != nil }

    /// One frame of exactly `frame` samples in, the coded packets out (normally one).
    func encode(_ samples: UnsafePointer<Float>) -> [Data] {
        guard encoding, let c = converter, let inb = AVAudioPCMBuffer(pcmFormat: VoiceCodec.pcm, frameCapacity: AVAudioFrameCount(VoiceCodec.frame)) else { return [] }
        inb.frameLength = AVAudioFrameCount(VoiceCodec.frame)
        inb.floatChannelData![0].update(from: samples, count: VoiceCodec.frame)
        let out = AVAudioCompressedBuffer(format: VoiceCodec.opus, packetCapacity: 4, maximumPacketSize: max(c.maximumOutputPacketSize, 1500))
        var fed = false
        var err: NSError?
        _ = c.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return inb
        }
        guard err == nil, out.packetCount > 0, let descs = out.packetDescriptions else { return [] }
        return (0..<Int(out.packetCount)).map { Data(bytes: out.data + Int(descs[$0].mStartOffset), count: Int(descs[$0].mDataByteSize)) }
    }

    /// One coded packet in, a buffer of samples out.
    func decode(_ data: Data) -> AVAudioPCMBuffer? {
        guard !encoding, let c = converter, !data.isEmpty, data.count <= 400 else { return nil }
        let cb = AVAudioCompressedBuffer(format: VoiceCodec.opus, packetCapacity: 1, maximumPacketSize: data.count)
        data.withUnsafeBytes { cb.data.copyMemory(from: $0.baseAddress!, byteCount: data.count) }
        cb.byteLength = UInt32(data.count); cb.packetCount = 1
        cb.packetDescriptions?[0] = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count))
        guard let pb = AVAudioPCMBuffer(pcmFormat: VoiceCodec.pcm, frameCapacity: 960) else { return nil }
        var given = false
        var err: NSError?
        _ = c.convert(to: pb, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return cb
        }
        guard err == nil, pb.frameLength > 0 else { return nil }
        return pb
    }
}

final class VoiceChat {
    enum Mode: Int, CaseIterable {
        case off, pushToTalk, open
        var name: String { ["Off", "Push to talk", "Open mic"][rawValue] }
    }

    /// Set for command-line tests: nothing touches the audio hardware.
    static var offline = false
    /// Set for tests that feed speech in by hand: the microphone is left alone, playback works as usual.
    static var noMicrophone = false

    var mode: Mode = Mode(rawValue: UserDefaults.standard.integer(forKey: "voiceMode")) ?? .off {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "voiceMode"); applyMode() }
    }
    /// How loud the others are, 0...1.5.
    var volume: Float = (UserDefaults.standard.object(forKey: "voiceVolume") as? Float) ?? 1 {
        didSet { UserDefaults.standard.set(volume, forKey: "voiceVolume"); playEngine.mainMixerNode.outputVolume = volume }
    }
    /// Push to talk: held down right now. Written by the game, read on the audio thread.
    var talkHeld = false
    /// Called for every frame of speech to send, on the audio thread.
    var onFrame: ((UInt16, Data) -> Void)?
    /// Why the microphone is not working, if it is not.
    private(set) var micProblem: String?
    /// Loudness at the microphone, 0...1, for the level meter.
    private(set) var micLevel: Float = 0
    /// Speech is going out right now.
    private(set) var sending = false

    private let micEngine = AVAudioEngine(), playEngine = AVAudioEngine()
    private var resampler: AVAudioConverter?
    private let encoder = VoiceCodec(encoder: true)
    private var pending: [Float] = []
    private var seq: UInt16 = 0
    private var hang = 0
    private var capturing = false, playing = false
    private var active = false                  // the network is on: voice may run

    private final class Voice {
        let decoder = VoiceCodec(encoder: false)
        let player = AVAudioPlayerNode()
        var lastSeq: UInt16 = 0, started = false
        var heard = 0.0
        var scheduled: Int64 = 0                // samples handed to the player so far
    }
    private var voices: [UInt32: Voice] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        // a headset plugged in or pulled out: the engines stop and have to be set up again
        for e in [micEngine, playEngine] {
            observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self] _ in
                guard let s = self, s.active else { return }
                if e === s.micEngine { s.stopCapture(); s.applyMode() } else { s.restartPlayback() }
            })
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: On and off

    /// Voice runs while the network does.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on { applyMode() } else {
            stopCapture()
            if playing { playEngine.stop(); playing = false }
            for v in voices.values { playEngine.detach(v.player) }
            voices = [:]
        }
    }

    private func applyMode() {
        guard active, !VoiceChat.offline else { return }
        guard mode != .off else { stopCapture(); micProblem = nil; return }
        guard !VoiceChat.noMicrophone else { return }
        guard encoder.available else { micProblem = "This Mac cannot code speech (no Opus encoder)."; return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] ok in
                DispatchQueue.main.async {
                    guard let s = self else { return }
                    if ok { if s.active && s.mode != .off { s.startCapture() } }
                    else { s.micProblem = "Microphone access was refused. Allow it under System Settings ▸ Privacy & Security ▸ Microphone." }
                }
            }
        default:
            micProblem = "Microphone access is off for FormationFlightX. Allow it under System Settings ▸ Privacy & Security ▸ Microphone."
        }
    }

    private func startCapture() {
        guard !capturing else { return }
        let input = micEngine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0, let rs = AVAudioConverter(from: fmt, to: VoiceCodec.pcm) else {
            micProblem = "No microphone was found."; return
        }
        resampler = rs
        pending = []
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in self?.captured(buf) }
        micEngine.prepare()
        do { try micEngine.start(); capturing = true; micProblem = nil }
        catch { input.removeTap(onBus: 0); micProblem = "The microphone could not be started (\(error.localizedDescription))." }
    }

    private func stopCapture() {
        guard capturing else { return }
        micEngine.inputNode.removeTap(onBus: 0)
        micEngine.stop()
        capturing = false; sending = false; micLevel = 0; hang = 0
    }

    // MARK: Sending (audio thread)

    private func captured(_ buf: AVAudioPCMBuffer) {
        guard let rs = resampler else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * VoiceCodec.rate / buf.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: VoiceCodec.pcm, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        _ = rs.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, out.frameLength > 0, let ch = out.floatChannelData else { return }
        process(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// 16 kHz samples from the microphone (or from a test): cut into frames, and send those that carry speech.
    func process(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        var at = 0
        while pending.count - at >= VoiceCodec.frame {
            pending.withUnsafeBufferPointer { p in
                let f = p.baseAddress! + at
                var sum: Float = 0
                for i in 0..<VoiceCodec.frame { sum += f[i] * f[i] }
                let rms = sqrt(sum / Float(VoiceCodec.frame))
                micLevel += (min(rms * 6, 1) - micLevel) * 0.3
                // push to talk sends while the key is down; an open microphone sends while there is something to hear,
                // and a little longer so that word endings are not clipped
                let open: Bool
                switch mode {
                case .off: open = false
                case .pushToTalk: open = talkHeld
                case .open: open = rms > 0.012
                }
                if open { hang = mode == .open ? 25 : 6 } else if hang > 0 { hang -= 1 }
                sending = open || hang > 0
                if sending {
                    for packet in encoder.encode(f) { seq &+= 1; onFrame?(seq, packet) }
                }
            }
            at += VoiceCodec.frame
        }
        pending.removeFirst(at)
    }

    // MARK: Receiving (main thread)

    private func startPlayback() -> Bool {
        if playing { return true }
        guard !VoiceChat.offline else { return false }
        playEngine.mainMixerNode.outputVolume = volume
        // the engine needs something connected before it will start
        for v in voices.values where v.player.engine == nil { playEngine.attach(v.player); playEngine.connect(v.player, to: playEngine.mainMixerNode, format: VoiceCodec.pcm) }
        playEngine.prepare()
        do { try playEngine.start(); playing = true } catch { return false }
        return true
    }

    private func restartPlayback() {
        playEngine.stop(); playing = false
        for v in voices.values { v.started = false; v.scheduled = 0 }
        _ = startPlayback()
    }

    /// A frame of someone's speech. Returns the decoded samples (for tests); plays them unless offline.
    @discardableResult func receive(from id: UInt32, seq: UInt16, payload: Data) -> AVAudioPCMBuffer? {
        guard active || VoiceChat.offline else { return nil }
        let v: Voice
        if let have = voices[id] { v = have } else {
            guard voices.count < 4 else { return nil }
            v = Voice(); voices[id] = v
            if !VoiceChat.offline {
                playEngine.attach(v.player)
                playEngine.connect(v.player, to: playEngine.mainMixerNode, format: VoiceCodec.pcm)
            }
        }
        // late and repeated frames are dropped; the sequence number wraps round
        let ahead = Int16(truncatingIfNeeded: Int(seq) - Int(v.lastSeq))
        // (after a second of silence anything goes: the sender may have started again from the beginning)
        if v.heard > 0 && CACurrentMediaTime() - v.heard < 1 && ahead <= 0 && ahead > -500 { return nil }
        v.lastSeq = seq
        v.heard = CACurrentMediaTime()
        guard let pcm = v.decoder.decode(payload) else { return nil }
        guard startPlayback() else { return pcm }
        if !v.started { v.player.play(); v.started = true }
        // How much is already queued. Starting from empty, a little silence goes first so that frames arriving
        // unevenly do not leave gaps; with far too much queued (a burst after a stall) the frame is dropped, so
        // the voice never falls behind.
        var played: Int64 = 0
        if let t = v.player.lastRenderTime, t.isSampleTimeValid, let pt = v.player.playerTime(forNodeTime: t) { played = max(pt.sampleTime, 0) }
        let queued = v.scheduled - played
        if queued > Int64(0.4 * VoiceCodec.rate) { return pcm }
        if queued <= 0 {
            let lead = AVAudioFrameCount(0.06 * VoiceCodec.rate)
            if let silence = AVAudioPCMBuffer(pcmFormat: VoiceCodec.pcm, frameCapacity: lead) {
                silence.frameLength = lead
                memset(silence.floatChannelData![0], 0, Int(lead) * MemoryLayout<Float>.size)
                v.player.scheduleBuffer(silence)
                v.scheduled = played + Int64(lead)
            }
        }
        v.player.scheduleBuffer(pcm)
        v.scheduled += Int64(pcm.frameLength)
        return pcm
    }

    /// Whether this pilot has been heard in the last moment.
    func speaking(_ id: UInt32) -> Bool { voices[id].map { CACurrentMediaTime() - $0.heard < 0.35 } ?? false }

    /// Forget the pilots who have left.
    func keep(only ids: Set<UInt32>) {
        for (id, v) in voices where !ids.contains(id) {
            if v.player.engine != nil { v.player.stop(); playEngine.detach(v.player) }
            voices[id] = nil
        }
    }
}
