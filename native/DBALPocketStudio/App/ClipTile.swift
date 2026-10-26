import SwiftUI

@MainActor struct ClipTile: View {
    @EnvironmentObject var s: Studio
    let clip:AudioClip
    let trackID:UUID
    let zoom:Double
    let waveform:WaveformData?
    var height:CGFloat=72
    var onEdit:(()->Void)?=nil
    @State private var draft:AudioClip?
    private var shown:AudioClip {draft ?? clip}
    var body: some View {
        VStack(alignment:.leading,spacing:2) {
            Text(shown.name).font(.system(size:10,weight:.semibold)).lineLimit(1)
            Canvas { context,size in
                guard let data=waveform,!data.peaks.isEmpty,data.duration>0 else{return}
                var path=Path()
                for x in stride(from:0.0,to:size.width,by:2) {
                    let time=shown.offset+x/max(1,size.width)*shown.length*60/s.session.tempo
                    let index=min(data.peaks.count-1,max(0,Int(time/data.duration*Double(data.peaks.count))))
                    let h=CGFloat(data.peaks[index])*size.height*0.48
                    path.move(to:CGPoint(x:x,y:size.height/2-h));path.addLine(to:CGPoint(x:x,y:size.height/2+h))
                }
                context.stroke(path,with:.color(.white.opacity(0.8)),lineWidth:1)
            }
        }.padding(4).frame(width:max(28,shown.length*zoom),height:height).background(s.selectedClips.contains(clip.id) ? Color.teal : Color.blue.opacity(0.6)).cornerRadius(5)
            .overlay {
                if s.selectedClips.contains(clip.id) {
                    FadeDrawing(fadeIn:shown.fadeIn,fadeOut:shown.fadeOut,duration:shown.length*60/s.session.tempo,curve:shown.fadeCurve ?? .linear)
                    WaveformHandles(fadeInWidth:shown.fadeIn*s.session.tempo/60*zoom,fadeOutWidth:shown.fadeOut*s.session.tempo/60*zoom,edit:handle,curve:{s.cycleFadeCurve(clip.id)})
                }
            }
            .offset(x:(shown.start-clip.start)*zoom)
            .overlay(RoundedRectangle(cornerRadius:5).stroke(s.selectedClips.contains(clip.id) ? Color.cyan : Color.clear,lineWidth:2))
            .offset(x:s.selectedClips.contains(clip.id) ? s.clipMovePreview*zoom : 0)
            .gesture(DragGesture(minimumDistance:3).onChanged { value in
                guard !s.selectionMode,!s.recording,!s.busy else{return}
                if !s.selectedClips.contains(clip.id){s.selectClips([clip.id],primary:clip.id)}
                let earliest=ClipEdits.placements(in:s.session,ids:s.selectedClips).map{$0.clip.start}.min() ?? clip.start
                s.clipMovePreview=max(-earliest,s.quantize(clip.start+Double(value.translation.width)/zoom)-clip.start)
            }.onEnded { _ in
                guard !s.selectionMode,!s.recording,!s.busy else{s.clipMovePreview=0;return}
                s.moveSelection(delta:s.clipMovePreview)
            })
            .onTapGesture {s.selectClips([clip.id],primary:clip.id);onEdit?()}
    }
    private func handle(_ mode:WaveHandle,_ pixels:Double,_ finished:Bool,_ cancelled:Bool) {
        guard !s.recording,!s.busy else{return}
        if cancelled{draft=nil;return}
        var edited=clip
        let seconds=pixels/zoom*60/s.session.tempo
        switch mode {
        case .trimLeft,.trimRight:
            edited=PerformanceMath.trimmed(clip,left:mode == .trimLeft,delta:pixels/zoom,tempo:s.session.tempo,sourceDuration:waveform?.duration ?? clip.offset+clip.length*60/s.session.tempo,grid:s.snap ? s.grid:nil)
        case .fadeIn:edited.fadeIn=min(clip.length*60/s.session.tempo,max(0,clip.fadeIn+seconds))
        case .fadeOut:edited.fadeOut=min(clip.length*60/s.session.tempo,max(0,clip.fadeOut-seconds))
        }
        if finished{draft=nil;s.commitClip(edited)}else{draft=edited}
    }

}
