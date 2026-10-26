import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct ClipPlacement {
    var trackID: UUID
    var clip: AudioClip
}
// Pure session edits shared by the gesture UI and undoable actions.
enum ClipEdits {
    static func placements(in session: PocketSession, ids: Set<UUID>) -> [ClipPlacement] {
        session.tracks.filter { $0.isAudio }.flatMap { t in
            t.clips.filter { ids.contains($0.id) }.map { ClipPlacement(trackID: t.id, clip: $0) }
        }
    }
    static func hitBoxes(in session: PocketSession, zoom: Double) -> [(UUID, CGRect)] {
        var boxes:[(UUID,CGRect)]=[]
        for (row,track) in session.tracks.enumerated() where track.isAudio {
            for clip in track.clips {
                let rect=CGRect(x:clip.start*zoom,y:Double(row)*85+5,width:max(28,clip.length*zoom),height:72)
                boxes.append((clip.id,rect))
            }
        }
        return boxes
    }
    static func hits(in session: PocketSession, from start: CGPoint, to end: CGPoint, zoom: Double) -> Set<UUID> {
        let rect = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: max(1,abs(end.x-start.x)), height: max(1,abs(end.y-start.y)))
        return Set(hitBoxes(in: session, zoom: zoom).filter { $0.1.intersects(rect) }.map { $0.0 })
    }
    static func hit(in session: PocketSession, at point: CGPoint, zoom: Double) -> UUID? {
        // Later clips paint on top of earlier clips when they overlap.
        hitBoxes(in: session, zoom: zoom).last { $0.1.contains(point) }?.0
    }
    static func remove(in session: inout PocketSession, ids: Set<UUID>) {
        for i in session.tracks.indices { session.tracks[i].clips.removeAll { ids.contains($0.id) } }
    }
    @discardableResult static func duplicate(in session: inout PocketSession, ids: Set<UUID>) -> Set<UUID> {
        let source = placements(in: session, ids: ids)
        guard let begin = source.map({ $0.clip.start }).min(), let end = source.map({ $0.clip.start+$0.clip.length }).max() else { return [] }
        return paste(in: &session, items: source, at: end, origin: begin)
    }
    // Keep the copied clips' original tracks and relative gaps/offsets.
    @discardableResult static func paste(in session: inout PocketSession, items: [ClipPlacement], at beat: Double, origin: Double? = nil) -> Set<UUID> {
        guard let first = origin ?? items.map({ $0.clip.start }).min() else { return [] }
        var added = Set<UUID>()
        for item in items {
            guard let i = session.tracks.firstIndex(where: { $0.id == item.trackID && $0.isAudio }) else { continue }
            var c = item.clip; c.id = UUID(); c.start = max(0,beat)+c.start-first
            session.tracks[i].clips.append(c); added.insert(c.id)
        }
        return added
    }
    @discardableResult static func split(in session: inout PocketSession, ids: Set<UUID>, at beat: Double) -> Set<UUID> {
        var selected = ids
        for ti in session.tracks.indices where session.tracks[ti].isAudio {
            var result: [AudioClip] = []
            for clip in session.tracks[ti].clips {
                guard ids.contains(clip.id), beat > clip.start, beat < clip.start+clip.length else { result.append(clip); continue }
                var left = clip, right = clip
                left.length = beat-clip.start; left.fadeOut = 0
                right.id = UUID(); right.offset += (beat-clip.start)*60/session.tempo
                right.start = beat; right.length = clip.start+clip.length-beat; right.fadeIn = 0
                result += [left,right]; selected.insert(right.id)
            }
            session.tracks[ti].clips = result
        }
        return selected
    }
    static func move(in session: inout PocketSession, ids: Set<UUID>, delta: Double) {
        let earliest = placements(in: session, ids: ids).map { $0.clip.start }.min() ?? 0
        let allowed = max(-earliest,delta)
        for ti in session.tracks.indices {
            for ci in session.tracks[ti].clips.indices where ids.contains(session.tracks[ti].clips[ci].id) {
                session.tracks[ti].clips[ci].start += allowed
            }
        }
    }
    static func fades(in session: inout PocketSession, ids: Set<UUID>, seconds: Double) {
        for ti in session.tracks.indices {
            for ci in session.tracks[ti].clips.indices where ids.contains(session.tracks[ti].clips[ci].id) {
                let duration = session.tracks[ti].clips[ci].length*60/session.tempo
                let fade = min(max(0,seconds),duration/2)
                session.tracks[ti].clips[ci].fadeIn = fade
                session.tracks[ti].clips[ci].fadeOut = fade
            }
        }
    }
}
