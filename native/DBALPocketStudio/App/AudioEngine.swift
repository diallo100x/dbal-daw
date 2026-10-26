import AVFoundation
import AudioToolbox
#if os(iOS)
import UIKit
#endif
import Darwin

struct Flavor {
    #if POCKET_PRO
    #if NATIVE_MAC
    static let name = "Native Mac"
    #else
    static let name = "Pro"
    #endif
    static let voices = 48
    static let sampleBudget = 256 * 1024 * 1024
    static let defaultBuffer = 256
    #else
    static let name = "Legacy"
    static let voices = 16
    static let sampleBudget = 64 * 1024 * 1024
    static let defaultBuffer = 512
    #endif
}
extension PluginRef {
    var description: AudioComponentDescription {
        AudioComponentDescription(componentType: type, componentSubType: subtype, componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }
}
final class TrackRuntime {
    let mixer = AVAudioMixerNode()
    var players: [UUID: AVAudioPlayerNode] = [:]
    var units: [AVAudioUnit] = []
    var instrument: AVAudioUnit?
    var sample: SampleVoice?
    var xyUnit: PocketFXUnit?
    var pitchUnit: AVAudioUnitTimePitch?
    func midi(_ note: Int, _ velocity: Int) {
        if let s = sample { s.midi(note, velocity); return }
        guard let instrument=instrument else{return}
        guard let block=instrument.auAudioUnit.scheduleMIDIEventBlock else{
            #if os(macOS)
            MusicDeviceMIDIEvent(instrument.audioUnit,velocity>0 ? 0x90:0x80,UInt32(clamping:note),UInt32(clamping:velocity),0)
            #endif
            return
        }
        var bytes: [UInt8] = [velocity > 0 ? 0x90 : 0x80, UInt8(clamping: note), UInt8(clamping: velocity)]
        bytes.withUnsafeMutableBufferPointer { p in block(AUEventSampleTimeImmediate, 0, 3, p.baseAddress!) }
    }
    func silence() {
        sample?.silence()
        if sample == nil { for n in 0..<128 { midi(n, 0) } }
    }
}
struct ScheduledNote { let seconds: Double; let track: UUID; let note: Int; let velocity: Int }
final class RecordingGate {
    let handle: OpaquePointer
    init() throws { guard let h = pc_create() else { throw PocketError.message("Recording queue allocation failed.") }; handle = h }
    deinit { pc_destroy(handle) }
}
final class HostClock {
    let handle = ph_create()!
    deinit { ph_destroy(handle) }
}
final class PocketAudio {
    private let hostClock = HostClock()
    func setTransport(_ session: PocketSession, beat: Double, playing: Bool, recording: Bool = false, offline: Bool = false, seconds: Double? = nil) {
        ph_set(hostClock.handle, session.tempo, Int32(session.beatsPerBar), beat, seconds ?? AVAudioTime.seconds(forHostTime: mach_absolute_time()), playing ? 1 : 0, session.loop ? 1 : 0, recording ? 1 : 0, session.loopStart, session.loopEnd, offline ? 1 : 0)
    }
    let engine = AVAudioEngine()
    var runtimes: [UUID: TrackRuntime] = [:]
    var warnings: [String] = []
    let monitor = AVAudioMixerNode()
    private var monitorAttached = false
    private var recordingFile: AVAudioFile?
    private let writer = DispatchQueue(label: "audio.recording.writer")
    private var recordingStartHost: UInt64?
    private var recordingError: Error?
    private var captureTarget: UUID?
    private var captureURL: URL?
    private var recordingActive = false
    private var recordCounter: RecordingGate?
    private var captureGeneration: Int = 0
    private var click: SampleVoice?
    var selectedInput: String?
    var bufferFrames = Flavor.defaultBuffer
    var monitorEnabled = false
    var inputLevel: Float = 0
    var onInputLevel: ((Float)->Void)?
    private var interruptionObserver: NSObjectProtocol?
    var onInterruption: (()->Void)?
    static let xyDescription=AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:0x70786678,componentManufacturer:0x4442414C,componentFlags:0,componentFlagsMask:0)
    private static let registerXY:Void = { AUAudioUnit.registerSubclass(PocketFXUnit.self,as:xyDescription,name:"DBAL: XY Effects",version:1) }()
    init() {
        _ = Self.registerXY
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in self?.onInterruption?() }
        #endif
    }
    deinit { if let o = interruptionObserver { NotificationCenter.default.removeObserver(o) } }
    func configureSession() throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(Double(bufferFrames)/44100)
        try session.setActive(true)
        if let uid = selectedInput, let port = session.availableInputs?.first(where: { $0.uid == uid }) { try session.setPreferredInput(port) }
        #endif
    }
    func destroyGraph() {
        engine.stop()
        for runtime in runtimes.values { runtime.silence() }
        for node in engine.attachedNodes where !(node is AVAudioInputNode) && !(node is AVAudioOutputNode) && node !== engine.mainMixerNode { engine.detach(node) }
        runtimes.removeAll(); click = nil; monitorAttached = false
    }
    func rebuild(_ session: PocketSession, root: URL, microphoneGranted: Bool) async throws {
        destroyGraph(); warnings = []
        try configureSession()
        // Pre-render edits away from the UI/audio threads before starting the graph.
        try await Task.detached(priority: .userInitiated) { [self] in
            for track in session.tracks { for clip in track.clips { _ = try processedClip(clip, root: root, tempo: session.tempo) } }
        }.value
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        guard rate > 0, let stereo = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw PocketError.message("No audio output is available.") }
        for track in session.tracks {
            let rt = TrackRuntime(); runtimes[track.id] = rt
            engine.attach(rt.mixer)
            if track.isAudio {
                for clip in track.clips {
                    let p = AVAudioPlayerNode(); rt.players[clip.id] = p; engine.attach(p)
                    let file = try AVAudioFile(forReading: safeChild(root, clip.asset))
                    try connect(p, to: rt.mixer, format: file.processingFormat)
                }
            } else {
                do {
                    switch track.instrument {
                    case .tone, .drums, .sfz:
                        let s = try SampleVoice(rate: rate, voices: Flavor.voices)
                        if track.instrument != .tone {
                            let url: URL
                            if track.instrument == .drums {
                                guard let kit = Bundle.main.url(forResource: "StarterKit", withExtension: "sfz", subdirectory: "StarterKit") else { throw PocketError.message("Starter kit is missing from the app bundle.") }; url = kit
                            } else {
                                guard let asset = track.instrumentAsset else { throw PocketError.message("Import an SFZ instrument.") }; url = try safeChild(root, asset)
                            }
                            warnings += try await Task.detached(priority: .userInitiated) { try s.load(url, memoryLimit: Flavor.sampleBudget) }.value
                        }
                        rt.sample = s; engine.attach(s.node); try connect(s.node, to: rt.mixer, format: stereo)
                    case .sample,.padSampler:
                        let state=track.sampler ?? SamplerState()
                        let sampler=try SampleVoice(rate:rate,voices:Flavor.voices)
                        try await Task.detached(priority:.userInitiated){try sampler.loadSampler(state,pads:track.instrument == .padSampler,root:root,memoryLimit:Flavor.sampleBudget)}.value
                        rt.sample=sampler;engine.attach(sampler.node);try connect(sampler.node,to:rt.mixer,format:stereo)
                    case .sf2:
                        guard let asset = track.instrumentAsset else { throw PocketError.message("Import an SF2 instrument.") }
                        let sampler = AVAudioUnitSampler(); engine.attach(sampler)
                        try sampler.loadSoundBankInstrument(at: safeChild(root, asset), program: UInt8(track.program), bankMSB: UInt8(track.bankMSB), bankLSB: UInt8(track.bankLSB))
                        rt.instrument = sampler
                        try connect(sampler, to: rt.mixer, format: nil)
                    case .auv3:
                        guard let ref = track.plugin else { throw PocketError.message("Select an AUv3 instrument.") }
                        let au = try await instantiate(ref, root: root)
                        #if !os(macOS)
                        guard au.auAudioUnit.scheduleMIDIEventBlock != nil else { throw PocketError.message("Selected Audio Unit does not accept MIDI notes.") }
                        #endif
                        engine.attach(au); try connect(au, to: rt.mixer, format: nil);rt.instrument = au
                    }
                } catch { warnings.append("\(track.name): \(error.localizedDescription)") }
            }
            var tail: AVAudioNode = rt.mixer
            if let state=track.xyFX,state.enabled {
                let unit:AVAudioUnit=try await withCheckedThrowingContinuation{continuation in
                    AVAudioUnit.instantiate(with:Self.xyDescription,options:[]){unit,error in
                        if let unit=unit{continuation.resume(returning:unit)}else{continuation.resume(throwing:error ?? PocketError.message("XY effect unavailable."))}
                    }
                }
                guard let fx=unit.auAudioUnit as? PocketFXUnit else{throw PocketError.message("XY Audio Unit registration failed.")}
                fx.clock=hostClock;fx.apply(state);rt.xyUnit=fx
                engine.attach(unit);try connect(tail,to:unit,format:stereo);tail=unit
                let pitch=AVAudioUnitTimePitch();rt.pitchUnit=pitch;pitch.bypass=state.mode != .pitch;engine.attach(pitch)
                try connect(tail,to:pitch,format:stereo);tail=pitch
            }
            for ref in track.effects {
                do {
                    let unit = try await instantiate(ref, root: root)
                    guard unit.numberOfInputs>0,unit.numberOfOutputs>0 else{throw PocketError.message("\(ref.name) cannot be used as an insert: it needs an audio input and output bus.")}
                    engine.attach(unit)
                    do{try connect(tail,to:unit,format:nil)}catch{engine.detach(unit);throw error}
                    rt.units.append(unit);tail=unit
                } catch { warnings.append("\(track.name) / \(ref.name): \(error.localizedDescription)") }
            }
            try connect(tail, to: engine.mainMixerNode, format: nil)
        }
        let c = try SampleVoice(rate: rate, voices: 4); click = c
        engine.attach(c.node); try connect(c.node, to: engine.mainMixerNode, format: stereo)
        if microphoneGranted && monitorEnabled {
            let format = engine.inputNode.outputFormat(forBus: 0)
            if format.channelCount > 0 && format.sampleRate > 0 {
                engine.attach(monitor); monitorAttached = true
                try connect(engine.inputNode, to: monitor, format: format)
                try connect(monitor, to: engine.mainMixerNode, format: nil)
                monitor.outputVolume = 0.6
            }
        }
        updateMixer(session)
        if let message=DBALPrepareAndStartAudioEngine(engine){throw PocketError.message(message)}
        updateFX(session)
    }
    private func connect(_ source:AVAudioNode,to destination:AVAudioNode,format:AVAudioFormat?)throws {
        if let message=DBALConnectAudioNodes(engine,source,destination,format){throw PocketError.message(message)}
    }
    func instantiate(_ ref: PluginRef, root: URL) async throws -> AVAudioUnit {
        let unit: AVAudioUnit = try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: ref.description, options: []) { unit, error in
                if let unit = unit { continuation.resume(returning: unit) }
                else { continuation.resume(throwing: error ?? PocketError.message("Audio Unit unavailable: \(ref.name)")) }
            }
        }
        let clock = hostClock
        let hostRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        unit.auAudioUnit.musicalContextBlock = { tempo, numerator, denominator, beat, offset, downbeat in
            let info = ph_get(clock.handle, AVAudioTime.seconds(forHostTime: mach_absolute_time()))
            tempo?.pointee = info.tempo; numerator?.pointee = Double(info.meter); denominator?.pointee = 4
            beat?.pointee = info.beat; downbeat?.pointee = floor(info.beat/Double(info.meter))*Double(info.meter)
            offset?.pointee = Int((ceil(info.beat)-info.beat)*60/info.tempo*hostRate)
            return true
        }
        unit.auAudioUnit.transportStateBlock = { flags, sample, cycleStart, cycleEnd in
            let info = ph_get(clock.handle, AVAudioTime.seconds(forHostTime: mach_absolute_time()))
            var state: AUHostTransportStateFlags = []
            if info.playing != 0 { state.insert(.moving) }; if info.cycling != 0 { state.insert(.cycling) }; if info.recording != 0 { state.insert(.recording) }
            flags?.pointee = state; sample?.pointee = info.beat*60/info.tempo*hostRate
            cycleStart?.pointee = info.loopStart; cycleEnd?.pointee = info.loopEnd
            return true
        }
        if let path = ref.state {
            let data = try Data(contentsOf: safeChild(root, path))
            let state = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = state as? [String:Any] else { throw PocketError.message("Invalid Audio Unit state.") }
            unit.auAudioUnit.fullState = dictionary
        }
        return unit
    }
    func updateFX(_ session:PocketSession) {
        for track in session.tracks {
            guard let state=track.xyFX,let rt=runtimes[track.id] else{continue}
            rt.xyUnit?.apply(state)
            let semitones=state.snap ? ((state.x*24)-12).rounded() : state.x*24-12
            rt.pitchUnit?.bypass=state.mode != .pitch
            rt.pitchUnit?.pitch=Float(semitones*100+(state.snap ? 0 : (state.y-0.5)*100))
        }
    }
    func updateMixer(_ session: PocketSession) {
        let solo = session.tracks.contains { $0.solo }
        for track in session.tracks {
            runtimes[track.id]?.mixer.outputVolume = track.mute || (solo && !track.solo) ? 0 : track.volume
            runtimes[track.id]?.mixer.pan = track.pan
        }
    }
    func captureStates(_ session: inout PocketSession, root: URL) throws {
        for i in session.tracks.indices {
            guard let runtime = runtimes[session.tracks[i].id] else { continue }
            if let unit = runtime.instrument, session.tracks[i].plugin != nil {
                let pluginID = session.tracks[i].plugin!.id
                let savedState = try writeState(unit, root: root, id: pluginID)
                session.tracks[i].plugin?.state = savedState
            }
            for j in session.tracks[i].effects.indices {
                let ref = session.tracks[i].effects[j]
                // Match by component rather than array index after an unavailable unit.
                let matches = runtime.units.filter { $0.audioComponentDescription.componentSubType == ref.subtype && $0.audioComponentDescription.componentManufacturer == ref.manufacturer && $0.audioComponentDescription.componentType == ref.type }
                let occurrence = session.tracks[i].effects[..<j].filter { $0.type == ref.type && $0.subtype == ref.subtype && $0.manufacturer == ref.manufacturer }.count
                if occurrence < matches.count { session.tracks[i].effects[j].state = try writeState(matches[occurrence], root: root, id: ref.id) }
            }
        }
    }
    private func writeState(_ unit: AVAudioUnit, root: URL, id: UUID) throws -> String? {
        guard let state = unit.auAudioUnit.fullStateForDocument ?? unit.auAudioUnit.fullState else { return nil }
        let relative = "Assets/\(id.uuidString).plist"
        let data = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
        try data.write(to: safeChild(root, relative), options: .atomic); return relative
    }
    func stopPlayers() { for rt in runtimes.values { rt.players.values.forEach { $0.stop() }; rt.silence() }; click?.silence() }
    func send(track: UUID, note: Int, velocity: Int) { runtimes[track]?.midi(note, velocity) }
    func tickClick(accent: Bool) {
        click?.midi(accent ? 96 : 88, 90)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.025) { [weak self] in self?.click?.silence() }
    }
    func scheduleAudio(_ session: PocketSession, root: URL, from beat: Double, host: UInt64) throws {
        let secPerBeat = 60/session.tempo
        for track in session.tracks where track.isAudio {
            for clip in track.clips {
                guard clip.start+clip.length > beat, let p = runtimes[track.id]?.players[clip.id] else { continue }
                let fileURL = try processedClip(clip, root: root, tempo: session.tempo)
                let f = try AVAudioFile(forReading: fileURL)
                let skip = max(0,beat-clip.start)*secPerBeat
                let start = AVAudioFramePosition(skip*f.processingFormat.sampleRate)
                guard start < f.length else { continue }
                let when = host + AVAudioTime.hostTime(forSeconds: max(0,clip.start-beat)*secPerBeat)
                p.scheduleSegment(f, startingFrame: start, frameCount: AVAudioFrameCount(min(Int64(UInt32.max), f.length-start)), at: AVAudioTime(hostTime: when))
                p.play()
            }
        }
    }
    // Chunked offline clip processing keeps long vocal files out of RAM.
    func processedClip(_ c: AudioClip, root: URL, tempo: Double) throws -> URL {
        let original = try safeChild(root, c.asset)
        let fm = FileManager.default
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let signature = "\(c.id)-\(c.offset)-\(c.length)-\(tempo)-\(c.fadeIn)-\(c.fadeOut)-\(c.gain)-\((c.fadeCurve ?? .linear).rawValue)"
        let target = cache.appendingPathComponent(signature).appendingPathExtension("caf")
        if fm.fileExists(atPath: target.path) { return target }
        let input = try AVAudioFile(forReading: original)
        let rate = input.processingFormat.sampleRate
        let offset = AVAudioFramePosition(c.offset*rate)
        let length = min(input.length-offset, AVAudioFramePosition(c.length*60/tempo*rate))
        guard offset >= 0, length > 0 else { throw PocketError.message("Clip is outside its source file.") }
        input.framePosition = offset
        let output = try AVAudioFile(forWriting: target, settings: input.processingFormat.settings)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192) else { throw PocketError.message("Audio buffer allocation failed.") }
        var done: Int64 = 0
        do {
            while done < length {
                try input.read(into: pcm, frameCount: AVAudioFrameCount(min(8192,length-done)))
                guard pcm.frameLength > 0, let channels = pcm.floatChannelData else { break }
                for f in 0..<Int(pcm.frameLength) {
                    let time = Double(done+Int64(f))/rate
                    let remaining = Double(length-done-Int64(f)-1)/rate
                    let envelope=min(1,c.fadeIn>0 ? time/c.fadeIn : 1,c.fadeOut>0 ? remaining/c.fadeOut : 1)
                    let gain=c.gain*Float((c.fadeCurve ?? .linear).gain(envelope))
                    for ch in 0..<Int(pcm.format.channelCount) { channels[ch][f] *= gain }
                }
                try output.write(from: pcm); done += Int64(pcm.frameLength)
            }
        } catch { try? fm.removeItem(at: target); throw error }
        return target
    }
    func startRecording(to url: URL, track: UUID) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw PocketError.message("No microphone/input is available.") }
        recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingStartHost = nil; recordingError = nil; captureTarget = track; captureURL = url
        captureGeneration += 1; let generation = captureGeneration
        let gate = try RecordingGate()
        recordCounter = gate
        recordingActive = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self, pc_claim(gate.handle) == 1 else { return }
            // Own the buffer before returning from the tap. File IO is serialized off the render thread.
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength), let src = buffer.floatChannelData, let dst = copy.floatChannelData else { pc_release(gate.handle); return }
            copy.frameLength = buffer.frameLength
            for c in 0..<Int(buffer.format.channelCount) { memcpy(dst[c], src[c], Int(buffer.frameLength)*MemoryLayout<Float>.size) }
            let host = time.hostTime
            self.writer.async {
                defer { pc_release(gate.handle) }
                guard self.captureGeneration == generation else { return }
                if self.recordingStartHost == nil { self.recordingStartHost = host }
                do { try self.recordingFile?.write(from: copy) } catch { self.recordingError = error }
            }
            var peak: Float = 0
            for i in stride(from: 0, to: Int(buffer.frameLength), by: 16) { peak = max(peak,abs(src[0][i])) }
            let level = peak
            DispatchQueue.main.async { self.onInputLevel?(level) }
        }
    }
    func finishRecording() throws -> (UUID, URL, UInt64)? {
        guard recordingActive else { return nil }
        engine.pause()
        engine.inputNode.removeTap(onBus: 0); recordingActive = false
        var result: (UUID,URL,UInt64)?; var failure: Error?
        writer.sync {
            recordingFile = nil
            if let id = captureTarget, let url = captureURL, let host = recordingStartHost { result = (id,url,host) }
            failure = recordingError
        }
        if let gate = recordCounter {
            if pc_overflowed(gate.handle) == 1 { failure = PocketError.message("Storage could not keep up with recording. The take may contain gaps; use a faster/local drive and a larger buffer.") }
            recordCounter = nil
        }
        if let error = failure { throw error }
        return result
    }
    func exportMix(_ session: PocketSession, root: URL, to output: URL) async throws {
        // A separate engine restores plugins so the live graph is never placed in offline mode.
        let offline = PocketAudio()
        try await offline.rebuild(session, root: root, microphoneGranted: false)
        for track in session.tracks {
            guard let rt = offline.runtimes[track.id], rt.units.count == track.effects.count,
                  (track.isAudio || (rt.instrument != nil || rt.sample != nil)),
                  track.xyFX?.enabled != true || (rt.xyUnit != nil && rt.pitchUnit != nil) else {
                throw PocketError.message("Cannot export while a required instrument/effect is unavailable. Check the status message and installed plugins.")
            }
        }
        offline.engine.stop()
        let rate = offline.engine.outputNode.inputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw PocketError.message("Export format unavailable.") }
        try offline.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        try offline.engine.start()
        defer { offline.stopPlayers(); offline.engine.stop(); offline.engine.disableManualRenderingMode() }
        let endBeat = session.tracks.flatMap { $0.clips.map { $0.start+$0.length } + $0.notes.map { $0.beat+$0.duration } }.max() ?? 0
        guard endBeat > 0 else { throw PocketError.message("Session is empty.") }
        let events = makeNoteSchedule(session, from: 0)
        var eventIndex = 0
        // In manual rendering mode schedule segments in sample time, not host time.
        for t in session.tracks where t.isAudio {
            for c in t.clips {
                guard let p = offline.runtimes[t.id]?.players[c.id] else { continue }
                let f = try AVAudioFile(forReading: offline.processedClip(c, root: root, tempo: session.tempo))
                p.scheduleFile(f, at: AVAudioTime(sampleTime: AVAudioFramePosition(c.start*60/session.tempo*rate), atRate: rate), completionHandler: nil)
                p.play()
            }
        }
        let out = try AVAudioFile(forWriting: output, settings: [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:rate,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:24,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false])
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else { throw PocketError.message("Export buffer allocation failed.") }
        let total = Int64((endBeat*60/session.tempo+2)*rate)
        var rendered: Int64 = 0, retries = 0
        while rendered < total {
            while eventIndex < events.count && Int64(events[eventIndex].seconds*rate) <= rendered {
                let e = events[eventIndex]; offline.send(track: e.track, note: e.note, velocity: e.velocity); eventIndex += 1
            }
            let next = eventIndex < events.count ? Int64(events[eventIndex].seconds*rate) : total
            let frames = AVAudioFrameCount(max(1,min(1024,total-rendered,max(1,next-rendered))))
            offline.setTransport(session, beat: Double(rendered)/rate*session.tempo/60, playing: true, offline: true)
            let status = try offline.engine.renderOffline(frames, to: pcm)
            if status == .success { try out.write(from: pcm); rendered += Int64(pcm.frameLength); retries = 0 }
            else { retries += 1; if retries > 100 { throw PocketError.message("A plugin could not render offline. Render that track to audio or remove it before exporting.") } }
            // Keep the UI responsive between render blocks.
            if rendered % 44100 < 1024 { await Task.yield() }
        }
    }
}
func makeNoteSchedule(_ session: PocketSession, from beat: Double) -> [ScheduledNote] {
    var events: [ScheduledNote] = []
    for track in session.tracks where !track.isAudio {
        for note in track.notes where note.beat+note.duration > beat {
            events.append(ScheduledNote(seconds: max(0,note.beat-beat)*60/session.tempo, track: track.id, note: note.note, velocity: note.velocity))
            events.append(ScheduledNote(seconds: (note.beat+note.duration-beat)*60/session.tempo, track: track.id, note: note.note, velocity: 0))
        }
    }
    return events.sorted { $0.seconds == $1.seconds ? $0.velocity < $1.velocity : $0.seconds < $1.seconds }
}
