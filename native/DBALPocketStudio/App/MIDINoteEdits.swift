import Foundation

enum MIDINoteEdits {
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
