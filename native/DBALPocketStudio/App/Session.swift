import Foundation

struct MIDIEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var beat: Double
    var duration: Double
    var note: Int
    var velocity: Int = 100
}
struct AudioClip: Codable, Identifiable, Equatable {
    var id = UUID()
    var asset: String
    var start: Double
    var offset: Double = 0 // Seconds in source; timeline positions are beats.
    var length: Double // Beats; changing tempo changes spacing, not audio speed.
    var fadeIn: Double = 0 // Seconds
    var fadeOut: Double = 0
    var gain: Float = 1
    var name: String
    var fadeCurve: FadeCurve?
}
struct PluginRef: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var type: UInt32
    var subtype: UInt32
    var manufacturer: UInt32
    var state: String?
}
enum InstrumentKind: String, Codable, CaseIterable {
    case tone = "Starter Keys", drums = "Starter Drums", sf2 = "SF2", sfz = "SFZ", auv3 = "AUv3", sample = "Sampler Keys", padSampler = "Sampler Pads"
}
struct Track: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var isAudio = true
    var instrument: InstrumentKind = .tone
    var instrumentAsset: String?
    var program: Int = 0
    var bankMSB: Int = 121
    var bankLSB: Int = 0
    var plugin: PluginRef?
    var effects: [PluginRef] = []
    var sampler: SamplerState?
    var xyFX: FXState?
    var clips: [AudioClip] = []
    var notes: [MIDIEvent] = []
    var volume: Float = 0.8
    var pan: Float = 0
    var mute = false
    var solo = false
}
struct PocketSession: Codable, Equatable {
    var schema = 1
    var id = UUID()
    var name = "Untitled Session"
    var tempo: Double = 90
    var beatsPerBar: Int = 4
    var loop = false
    var loopStart: Double = 0
    var loopEnd: Double = 16
    var tracks = [Track(name: "Beat / Audio"), Track(name: "Vocals"), Track(name: "Keys", isAudio: false)]
}
enum PocketError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
func safeChild(_ root: URL, _ relative: String) throws -> URL {
    guard !relative.hasPrefix("/"), !relative.contains(":") else { throw PocketError.message("Absolute asset paths are not supported.") }
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    let child = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
    guard child.path.hasPrefix(base.path + "/") else { throw PocketError.message("Asset path leaves its project folder.") }
    return child
}
func validate(_ session: PocketSession, root: URL) throws {
    guard session.schema == 1, session.tempo.isFinite, (30...300).contains(session.tempo),
          (1...12).contains(session.beatsPerBar), session.loopStart.isFinite, session.loopEnd.isFinite,
          session.loopStart >= 0, session.loopEnd > session.loopStart, session.tracks.count <= 64,
          Set(session.tracks.map(\.id)).count == session.tracks.count else { throw PocketError.message("Unsupported or invalid session.") }
    for t in session.tracks {
        guard t.volume.isFinite, (0...2).contains(t.volume), t.pan.isFinite, (-1...1).contains(t.pan),
              (0...127).contains(t.program), (0...127).contains(t.bankMSB), (0...127).contains(t.bankLSB), t.effects.count <= 8 else { throw PocketError.message("Invalid track settings.") }
        if let fx=t.xyFX { guard fx.x.isFinite,fx.y.isFinite,(0...1).contains(fx.x),(0...1).contains(fx.y) else {throw PocketError.message("Invalid XY settings.")} }
        if let sampler=t.sampler {
            guard sampler.pads.count==8,(sampler.bank ?? 0)>=0,(sampler.bank ?? 0)<6,sampler.extraBanks==nil || (sampler.extraBanks!.count==5 && sampler.extraBanks!.allSatisfy{$0.count==8}) else {throw PocketError.message("Sampler needs eight pads.")}
            for slot in ([sampler.keyboard].compactMap{$0}+sampler.pads.compactMap{$0}+(sampler.extraBanks ?? []).flatMap{$0}.compactMap{$0}) {
                _ = try safeChild(root,slot.asset)
                guard (slot.stretch ?? 1).isFinite,(0.25...4).contains(slot.stretch ?? 1),(slot.pitch ?? 0).isFinite,(-24...24).contains(slot.pitch ?? 0) else {throw PocketError.message("Invalid sample stretch/pitch.")}
                guard [slot.start,slot.end,slot.fadeIn,slot.fadeOut].allSatisfy({$0.isFinite && $0>=0}),slot.end>slot.start,(0...127).contains(slot.root) else {throw PocketError.message("Invalid sampler region.")}
            }
        }
        if let asset = t.instrumentAsset { _ = try safeChild(root, asset) }
        for p in ([t.plugin].compactMap { $0 } + t.effects) { if let s = p.state { _ = try safeChild(root, s) } }
        for c in t.clips {
            _ = try safeChild(root, c.asset)
            guard [c.start,c.offset,c.length,c.fadeIn,c.fadeOut].allSatisfy({ $0.isFinite && $0 >= 0 }), c.length > 0, c.gain.isFinite, (0...4).contains(c.gain) else { throw PocketError.message("Invalid audio clip.") }
        }
        for n in t.notes {
            guard n.beat.isFinite, n.beat >= 0, n.duration.isFinite, n.duration > 0, (0...127).contains(n.note), (1...127).contains(n.velocity) else { throw PocketError.message("Invalid MIDI note.") }
        }
    }
}
