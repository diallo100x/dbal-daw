import CoreAudioKit
#if os(macOS)
import AppKit
typealias UIViewController = NSViewController
#else
import UIKit
#endif
import SwiftUI
import Darwin
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class Studio: ObservableObject {
    @Published var session = PocketSession()
    @Published var selected: UUID?
    @Published var selectedClip: UUID?
    @Published var selectedClips = Set<UUID>()
    @Published var selectionMode = true
    @Published var selectionAdds = false
    @Published var clipMovePreview = 0.0
    @Published var showSelectionMenu = false
    @Published var clipboard: [ClipPlacement] = []
    @Published var beat: Double = 0
    @Published var playing = false
    @Published var recording = false
    @Published var busy = false
    @Published var status = "Starting audio…"
    @Published var error: String?
    @Published var snap = true
    @Published var grid: Double = 0.25
    @Published var metronome = false
    @Published var preRoll = 0 {
        didSet { UserDefaults.standard.set(preRoll, forKey: "countInBars") }
    }
    @Published var armed: UUID?
    @Published var inputLevel: Float = 0
    @Published var showPads = false
    @Published var octave = 4
    @Published var pluginController: UIViewController?
    @Published var exportURL: URL?
    @Published var microphoneGranted = false
    let audio = PocketAudio()
    var root: URL
    private var timer: Timer?
    var startSeconds = 0.0
    private var startBeat = 0.0
    private var schedule: [ScheduledNote] = []
    private var eventIndex = 0
    private var lastClick = -1
    private var lastUIUpdate = 0.0
    private var undoStack: [PocketSession] = []
    private var redoStack: [PocketSession] = []
    var held: [Int:(UUID,Double)] = [:]
    var soundingNotes:[Int:Int]=[:]
    @Published var repeaterEnabled=false
    @Published var repeatBeats=0.25
    @Published var midiSnap=true
    @Published var midiPitchMatrix=true
    @Published var midiX=0.5
    @Published var midiY=0.75
    @Published var midiRoot=60
    var repeatHeld:[Int:RepeatHold]=[:]
    var pendingNoteOffs:[PendingNoteOff]=[]
    var performanceTimer:Timer?
    private var pendingRecordHost: UInt64?
    private var takeStartBeat = 0.0
    private var observers: [NSObjectProtocol] = []
    var selectedIndex: Int? { session.tracks.firstIndex { $0.id == selected } }
    var sessionsFolder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Sessions", isDirectory: true) }
    var nowSeconds: Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }
    var currentBeat: Double { playing ? max(startBeat,startBeat+(nowSeconds-startSeconds)*session.tempo/60) : beat }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    init() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Sessions/\(UUID().uuidString).pocketstudio", isDirectory: true)
        if let path = UserDefaults.standard.string(forKey: "lastSession"), fm.fileExists(atPath: path) {
            do {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                let loaded = try JSONDecoder().decode(PocketSession.self, from: Data(contentsOf: url.appendingPathComponent("Session.json")))
                try validate(loaded, root: url); root = url; session = loaded
            } catch { status = "Previous session could not be opened. A new session was created." }
        }
        try? fm.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        selected = session.tracks.first?.id
        preRoll = min(2,max(0,UserDefaults.standard.integer(forKey: "countInBars")))
        audio.onInputLevel = { [weak self] value in self?.inputLevel = value }
        audio.onInterruption = { [weak self] in self?.stop(); self?.status = "Audio interrupted. Tap Restart Audio when the route is ready." }
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.status = "Audio route changed. Tap Restart Audio before continuing." }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.save() } })
        #else
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.willResignActiveNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.save()}})
        #endif
        Task { await rebuild() }
    }
    func fail(_ e: Error) { error = e.localizedDescription; status = "Action failed" }
    func checkpoint() { undoStack.append(session); if undoStack.count > 30 { undoStack.removeFirst() }; redoStack.removeAll(); objectWillChange.send() }
    func change(_ block: (inout PocketSession)->Void, graph: Bool = false) {
        guard !busy, !recording else { return }
        stop(); save(capture: true); checkpoint(); block(&session); reconcileSelection(); save()
        if graph { Task { await rebuild() } } else { audio.updateMixer(session) }
    }
    func undo() { guard !recording, !busy, let previous = undoStack.popLast() else { return }; stop(); redoStack.append(session); session = previous; reconcileSelection(); save(); Task { await rebuild() } }
    func redo() { guard !recording, !busy, let next = redoStack.popLast() else { return }; stop(); undoStack.append(session); session = next; reconcileSelection(); save(); Task { await rebuild() } }
    func save(capture: Bool = false) {
        do {
            if capture { try audio.captureStates(&session, root: root) }
            try validate(session, root: root)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(session).write(to: root.appendingPathComponent("Session.json"), options: .atomic)
            UserDefaults.standard.set(root.path, forKey: "lastSession")
        } catch { fail(error) }
    }
    func rebuild() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try await audio.rebuild(session, root: root, microphoneGranted: microphoneGranted)
            audio.setTransport(session, beat: beat, playing: playing, recording: recording)
            status = audio.warnings.isEmpty ? "Ready • \(Flavor.name) • \(Int(audio.engine.outputNode.inputFormat(forBus: 0).sampleRate)) Hz" : audio.warnings.joined(separator: "\n")
        } catch { fail(error) }
    }
    func requestMicrophone() async -> Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        #else
        let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        #endif
        microphoneGranted = granted
        if !granted { error = "Microphone access is off. Enable it in Settings to record vocals." }
        return granted
    }
    func quantize(_ value: Double) -> Double { max(0,snap ? (value/grid).rounded()*grid : value) }
    func addTrack(audio isAudio: Bool) {
        #if POCKET_PRO
        let limit = 32
        #else
        let limit = 8
        #endif
        guard session.tracks.count < limit else { error = "\(Flavor.name) allows \(limit) tracks in this build."; return }
        let track = Track(name: isAudio ? "Audio \(session.tracks.count+1)" : "Instrument \(session.tracks.count+1)", isAudio: isAudio)
        change({ $0.tracks.append(track) }, graph: true); selected = track.id
    }
    func play() {
        guard !busy, !playing else { return }
        if !audio.engine.isRunning { error = "Restart Audio before playing."; return }
        if session.loop && beat >= session.loopEnd { beat = session.loopStart }
        do { try begin(from: beat) } catch { fail(error) }
    }
    private func begin(from position: Double, delay: Double = 0) throws {
        audio.stopPlayers()
        startBeat = position; startSeconds = nowSeconds + 0.08 + delay
        try audio.scheduleAudio(session, root: root, from: position, host: AVAudioTime.hostTime(forSeconds: startSeconds))
        schedule = makeNoteSchedule(session, from: position); eventIndex = 0; lastClick = delay > 0 ? Int(floor(-delay*session.tempo/60))-1 : Int(floor(position))-1
        audio.setTransport(session, beat: position, playing: true, recording: recording, seconds: startSeconds)
        playing = true; beat = position
        timer?.invalidate()
        timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.transportTick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func transportTick() {
        guard playing else { return }
        let elapsed = nowSeconds-startSeconds
        if let host = pendingRecordHost, mach_absolute_time() >= host {
            pendingRecordHost = nil
            do { try beginAudioTake() } catch { stop(); fail(error); return }
        }
        if elapsed < 0 {
            let count = Int(floor(elapsed*session.tempo/60))
            if count > lastClick { lastClick = count; audio.tickClick(accent: count % session.beatsPerBar == 0) }
            return
        }
        let position = startBeat + elapsed*session.tempo/60
        audio.setTransport(session, beat: position, playing: true, recording: recording)
        if nowSeconds-lastUIUpdate >= 1.0/30 { beat = position; lastUIUpdate = nowSeconds }
        while eventIndex < schedule.count && schedule[eventIndex].seconds <= elapsed {
            let e = schedule[eventIndex]; audio.send(track: e.track, note: e.note, velocity: e.velocity); eventIndex += 1
        }
        let whole = Int(floor(position))
        if whole > lastClick { lastClick = whole; if metronome { audio.tickClick(accent: whole % session.beatsPerBar == 0) } }
        if session.loop && !recording && position >= session.loopEnd {
            do { try begin(from: session.loopStart) } catch { stop(); fail(error) }
        }
    }
    func stop(resetIfStopped: Bool = false) {
        let wasPlaying = playing
        if playing { beat = currentBeat }
        timer?.invalidate(); timer = nil; pendingRecordHost = nil
        if recording { finishTake() }
        playing = false
        audio.setTransport(session, beat: beat, playing: false)
        for (note,entry) in held { audio.send(track: entry.0, note: soundingNotes[note] ?? note, velocity: 0) }; held.removeAll()
        audio.stopPlayers();soundingNotes.removeAll();cancelRepeater()
        if !wasPlaying && resetIfStopped { beat = 0 }
    }
    func toggleRecord() async {
        if recording { stop(); return }
        guard !busy, let id = armed, let track = session.tracks.first(where: { $0.id == id }) else { error = "Arm an audio or instrument track first."; return }
        if track.isAudio && !microphoneGranted {
            guard await requestMicrophone() else { return }
            await rebuild()
        }
        stop(); checkpoint(); recording = true
        takeStartBeat = beat
        let countSeconds = Double(preRoll*session.beatsPerBar)*60/session.tempo
        do {
            try begin(from: takeStartBeat, delay: countSeconds)
            if track.isAudio { pendingRecordHost = AVAudioTime.hostTime(forSeconds: startSeconds) }
        } catch { recording = false; fail(error) }
    }
    private func beginAudioTake() throws {
        guard let id = armed, session.tracks.first(where: { $0.id == id })?.isAudio == true else { return }
        let url = root.appendingPathComponent("Assets/Take-\(UUID().uuidString).caf")
        try audio.startRecording(to: url, track: id)
        status = "Recording • Tap Stop to finish"
    }
    private func finishTake() {
        for (note, entry) in held {
            audio.send(track: entry.0, note: soundingNotes[note] ?? note, velocity: 0)
            if let i = session.tracks.firstIndex(where: { $0.id == entry.0 }) {
                session.tracks[i].notes.append(MIDIEvent(beat: max(takeStartBeat,entry.1), duration: max(0.03125,beat-entry.1), note: soundingNotes[note] ?? note))
            }
        }
        held.removeAll()
        do {
            if let (id,url,host) = try audio.finishRecording(), let i = session.tracks.firstIndex(where: { $0.id == id }) {
                let f = try AVAudioFile(forReading: url)
                let actual = startBeat + (AVAudioTime.seconds(forHostTime: host)-startSeconds)*session.tempo/60
                let clip = AudioClip(asset: "Assets/"+url.lastPathComponent, start: max(0,actual), length: Double(f.length)/f.processingFormat.sampleRate*session.tempo/60, name: "Vocal Take")
                if clip.length > 0 { session.tracks[i].clips.append(clip); selectClips([clip.id]) }
            }
        } catch { fail(error) }
        recording = false; save(capture: true); status = "Take saved"
        // New player nodes are needed only after audio recording.
        Task { await rebuild() }
    }
    func importAudio(_ url: URL) async {
        guard !busy, !recording, let i = selectedIndex, session.tracks[i].isAudio else { error = "Select an audio track before importing audio."; return }
        stop(); save(capture: true)
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try AVAudioFile(forReading: url)
            let relative = "Assets/\(UUID().uuidString).\(url.pathExtension)"
            try FileManager.default.copyItem(at: url, to: safeChild(root, relative))
            checkpoint()
            session.tracks[i].clips.append(AudioClip(asset: relative, start: quantize(beat), length: Double(file.length)/file.processingFormat.sampleRate*session.tempo/60, name: url.deletingPathExtension().lastPathComponent))
            if let id = session.tracks[i].clips.last?.id { selectClips([id]) }; save(); await rebuild()
        } catch { fail(error) }
    }
    func importInstrument(_ url: URL, folder: Bool) async {
        guard !busy, !recording, let i = selectedIndex, !session.tracks[i].isAudio else { error = "Select an instrument track first."; return }
        stop(); save(capture: true)
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let fm = FileManager.default
            let id = UUID().uuidString
            let relative: String
            let kind: InstrumentKind
            if folder {
                let target = root.appendingPathComponent("Assets/\(id)", isDirectory: true)
                try copySafeTree(url, to: target)
                let files = try fm.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "sfz" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                guard files.count == 1, let sfz = files.first else { try? fm.removeItem(at: target); throw PocketError.message("Choose a folder containing exactly one SFZ definition at its top level, plus its samples.") }
                relative = "Assets/\(id)/\(sfz.lastPathComponent)"; kind = .sfz
            } else {
                guard url.pathExtension.lowercased() == "sf2" else { throw PocketError.message("Select an SF2 file. For SFZ, import its complete folder.") }
                relative = "Assets/\(id).sf2"; kind = .sf2
                try fm.copyItem(at: url, to: safeChild(root, relative))
            }
            checkpoint(); session.tracks[i].instrument = kind; session.tracks[i].instrumentAsset = relative; session.tracks[i].plugin = nil
            save(); await rebuild()
        } catch { fail(error) }
    }
    func newSession() async {
        guard !recording, !busy else { return }; stop(); save(capture: true)
        session = PocketSession(); root = sessionsFolder.appendingPathComponent("\(session.id).pocketstudio", isDirectory: true)
        do { try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true) } catch { fail(error); return }
        selected = session.tracks.first?.id; clearClipSelection(); clipboard=[]; undoStack=[];redoStack=[];beat=0;save();await rebuild()
    }
    func open(_ url: URL) async {
        guard !recording, !busy else { return }; stop(); save(capture: true)
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let incoming = try JSONDecoder().decode(PocketSession.self, from: Data(contentsOf: url.appendingPathComponent("Session.json")))
            try validate(incoming, root: url)
            let target = sessionsFolder.appendingPathComponent("\(UUID().uuidString).pocketstudio", isDirectory: true)
            try copySafeTree(url, to: target)
            save(capture: true); session = incoming; root = target
            selected=session.tracks.first?.id; clearClipSelection();clipboard=[];undoStack=[];redoStack=[];beat=0;save();await rebuild()
        } catch { fail(error) }
    }
    func choosePlugin(_ ref: PluginRef, effect: Bool) {
        guard let i = selectedIndex else { return }
        if !effect && session.tracks[i].isAudio { error = "Select an instrument track for an AUv3 instrument."; return }
        change({ s in
            if effect { s.tracks[i].effects.append(ref) }
            else { s.tracks[i].plugin=ref; s.tracks[i].instrument = .auv3 }
        }, graph: true)
    }
    func showPlugin(effectIndex: Int? = nil) {
        guard let id = selected, let rt = audio.runtimes[id] else { return }
        let unit: AVAudioUnit?
        if let index = effectIndex, let ti = selectedIndex {
            let ref = session.tracks[ti].effects[index]
            unit = rt.units.first { $0.audioComponentDescription.componentSubType == ref.subtype && $0.audioComponentDescription.componentManufacturer == ref.manufacturer }
        } else { unit = rt.instrument }
        guard let au = unit else { error = "Plugin is unavailable. Its saved settings remain in the session."; return }
        au.auAudioUnit.requestViewController { [weak self] controller in DispatchQueue.main.async {
            if let controller = controller { self?.pluginController=controller }
            else {
                #if os(macOS)
                self?.pluginController=NSHostingController(rootView:MacParameterEditor(unit:au))
                #else
                self?.error="This Audio Unit does not provide a custom editor."
                #endif
            }
        } }
    }
    func exportProject() {
        guard !busy, !recording else { return }; stop(); save(capture: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(session.name.replacingOccurrences(of: "/", with: "-"))").appendingPathExtension("pocketstudio")
        do { try copySafeTree(root, to: url, excludingCache: true); exportURL=url } catch { fail(error) }
    }
    func exportMix() async {
        guard !busy, !recording else { return }; stop(); save(capture: true); busy=true;defer{busy=false;Task { await rebuild() }}
        status="Rendering stereo WAV…"
        audio.destroyGraph()
        do {
            let target=FileManager.default.temporaryDirectory.appendingPathComponent("Pocket-Mix-\(UUID().uuidString).wav")
            try await audio.exportMix(session, root: root, to: target)
            exportURL=target;status="Mix exported"
        } catch { fail(error) }
    }
    func cycleCountIn() { guard !recording, !busy else { return }; preRoll = (preRoll+1)%3 }
    func clearClipSelection() { selectedClips=[]; selectedClip=nil; clipMovePreview=0; showSelectionMenu=false }
    func selectClips(_ ids: Set<UUID>, primary: UUID? = nil) {
        selectedClips = ids.intersection(Set(session.tracks.flatMap { $0.clips.map(\.id) }))
        let ordered = session.tracks.flatMap { $0.clips.map(\.id) }
        selectedClip = primary.flatMap { selectedClips.contains($0) ? $0 : nil } ?? ordered.first { selectedClips.contains($0) }
        if let id = selectedClip, let track = session.tracks.first(where: { $0.clips.contains { $0.id == id } }) { selected = track.id }
    }
    func reconcileSelection() { selectClips(selectedClips, primary: selectedClip) }
    func copySelection() {
        guard !recording, !busy else { return }
        clipboard = ClipEdits.placements(in: session, ids: selectedClips)
        showSelectionMenu=false; status="Copied \(clipboard.count) clips"
    }
    func cutSelection() {
        guard !recording, !busy, !selectedClips.isEmpty else { return }
        copySelection(); deleteClip()
    }
    func pasteSelection() {
        guard !recording, !busy, !clipboard.isEmpty else { return }
        let items=clipboard, position=quantize(beat)
        guard items.allSatisfy({ item in session.tracks.contains { $0.id == item.trackID && $0.isAudio } }) else {
            error="A copied clip's original track was removed. Undo that track deletion before pasting.";return
        }
        var newIDs=Set<UUID>()
        change({ newIDs=ClipEdits.paste(in:&$0,items:items,at:position) },graph:true)
        selectClips(newIDs);showSelectionMenu=false
    }
    func splitClip() {
        guard !recording, !busy else { return }
        let ids=selectedClips, point=quantize(beat)
        guard ClipEdits.placements(in:session,ids:ids).contains(where: {point>$0.clip.start && point<$0.clip.start+$0.clip.length}) else {
            error="Place the cursor inside at least one selected clip.";return
        }
        var newIDs=ids
        change({ newIDs=ClipEdits.split(in:&$0,ids:ids,at:point) },graph:true)
        selectClips(newIDs);showSelectionMenu=false
    }
    func duplicateClip() {
        guard !recording, !busy, !selectedClips.isEmpty else { return }
        let ids=selectedClips;var newIDs=Set<UUID>()
        change({ newIDs=ClipEdits.duplicate(in:&$0,ids:ids) },graph:true)
        selectClips(newIDs);showSelectionMenu=false
    }
    func deleteClip() {
        guard !recording, !busy, !selectedClips.isEmpty else { return }
        let ids=selectedClips
        change({ClipEdits.remove(in:&$0,ids:ids)},graph:true);clearClipSelection()
    }
    func moveSelection(delta:Double) {
        guard !recording, !busy, delta != 0 else { clipMovePreview=0;return }
        let ids=selectedClips;clipMovePreview=0
        change({ClipEdits.move(in:&$0,ids:ids,delta:delta)})
    }
    func setSelectionFades(_ seconds:Double) {
        guard !recording, !busy, !selectedClips.isEmpty else {return}
        let ids=selectedClips
        change({ClipEdits.fades(in:&$0,ids:ids,seconds:seconds)},graph:true);showSelectionMenu=false
    }

}
func copySafeTree(_ source: URL, to target: URL, excludingCache: Bool = true) throws {
    let fm=FileManager.default
    guard let entries=fm.enumerator(at:source,includingPropertiesForKeys:[.isSymbolicLinkKey,.isDirectoryKey,.fileSizeKey],options:[.skipsHiddenFiles]) else { throw PocketError.message("Could not read project folder.") }
    try fm.createDirectory(at:target,withIntermediateDirectories:true)
    var bytes=0
    do {
        for case let url as URL in entries {
            let values=try url.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.fileSizeKey])
            guard values.isSymbolicLink != true else { throw PocketError.message("Symbolic links are not supported in portable projects.") }
            let relative=String(url.path.dropFirst(source.path.count+1))
            if excludingCache && (relative=="Cache" || relative.hasPrefix("Cache/")) { if values.isDirectory==true { entries.skipDescendants() };continue }
            let dest=try safeChild(target,relative)
            if values.isDirectory==true { try fm.createDirectory(at:dest,withIntermediateDirectories:true) }
            else { bytes+=values.fileSize ?? 0;guard bytes<2_000_000_000 else {throw PocketError.message("Portable folder exceeds 2 GB.")};try fm.copyItem(at:url,to:dest) }
        }
    } catch { try? fm.removeItem(at:target);throw error }
}
