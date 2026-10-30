import Foundation

enum MIDIQuantizeMode: String, CaseIterable {
    case starts = "Note starts", lengths = "Note lengths", both = "Starts + lengths"
}

enum MIDINoteEdits {
    static func quantized(_ note: MIDIEvent, grid: Double, mode: MIDIQuantizeMode) -> MIDIEvent {
        guard grid.isFinite, grid > 0 else { return note }
        var result = note
        if mode != .lengths { result.beat = snapped(note.beat, grid: grid) }
        if mode != .starts { result.duration = max(grid, snapped(note.duration, grid: grid)) }
        return result
    }
    static func recorded(start: Double, end: Double, note: Int, velocity: Int = 100,
                         grid: Double?) -> MIDIEvent {
        // Quantize onset only; preserve played gate length and immediate monitoring.
        MIDIEvent(beat: snapped(start, grid: grid),
            duration: max(0.03125, end - start), note: note, velocity: velocity)
    }

    static func snapped(_ beat:Double,grid:Double?)->Double {
        guard beat.isFinite else{return 0}
        guard let grid=grid,grid.isFinite,grid>0 else{return max(0,beat)}
        return max(0,(beat/grid).rounded()*grid)
    }
    static func moved(_ note:MIDIEvent,beats:Double,pitches:Int,grid:Double?)->MIDIEvent {
        var result=note;result.beat=snapped(note.beat+beats,grid:grid);result.note=min(127,max(0,note.note+min(127,max(-127,pitches))));return result
    }
    static func resized(_ note:MIDIEvent,beats:Double,grid:Double?)->MIDIEvent {
        let minimum=(grid?.isFinite==true && (grid ?? 0)>0) ? grid!:0.03125
        var result=note;result.duration=max(minimum,snapped(note.duration+beats,grid:grid));return result
    }
}
