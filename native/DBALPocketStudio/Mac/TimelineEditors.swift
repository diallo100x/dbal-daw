import SwiftUI
import AVFoundation

@MainActor struct MacAudioEditor:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) private var presentation
    let clipID:UUID
    @ObservedObject var waves:Waveforms
    @State private var zoom=70.0
    @State private var draft:AudioClip?
    private var current:AudioClip?{s.session.tracks.flatMap{$0.clips}.first{$0.id==clipID}}
    private var trackID:UUID?{s.session.tracks.first{$0.clips.contains{$0.id==clipID}}?.id}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Text("Waveform Editor").font(.title2);Spacer();Button("Undo"){s.undo()}.disabled(!s.canUndo);Button("Redo"){s.redo()}.disabled(!s.canRedo);Button("Done"){presentation.wrappedValue.dismiss()}}
            if let clip=current,let id=trackID {
                Text(clip.name).font(.headline)
                ScrollView(.horizontal){ClipTile(clip:clip,trackID:id,zoom:zoom,waveform:waves.data[clip.asset],height:200).environmentObject(s).padding(10)}.frame(height:230)
                HStack{Text("Zoom");Slider(value:$zoom,in:15...300)}
                Text("Drag either cyan edge to crop without changing the source file. Drag an upper or lower corner for fade-in/out. Shift-click a fade to change its curve. Undo restores earlier edits.").font(.caption)
                HStack{field("Start beat",key:\.start);field("Source offset (s)",key:\.offset);field("Length (beats)",key:\.length)}
                HStack{field("Fade in (s)",key:\.fadeIn);field("Fade out (s)",key:\.fadeOut);Button("Apply values"){apply()}}
                HStack{Button("Split at cursor"){s.selectClips([clipID],primary:clipID);s.splitClip();presentation.wrappedValue.dismiss()};Button("Duplicate"){s.selectClips([clipID],primary:clipID);s.duplicateClip()};Button("Delete clip",role:.destructive){s.selectClips([clipID],primary:clipID);s.deleteClip();presentation.wrappedValue.dismiss()}}
            }else{Text("This clip is no longer in the session.")}
        }.padding(20).frame(width:850).onAppear{draft=current;s.selectClips([clipID],primary:clipID)}.onChange(of:current){draft=$0}
    }
    private func field(_ title:String,key:WritableKeyPath<AudioClip,Double>)->some View {
        VStack(alignment:.leading){Text(title).font(.caption);TextField(title,value:Binding(get:{draft?[keyPath:key] ?? 0},set:{draft?[keyPath:key]=$0}),format:.number).frame(width:160)}
    }
    private func apply(){
        guard let clip=draft else{return}
        guard [clip.start,clip.offset,clip.length,clip.fadeIn,clip.fadeOut].allSatisfy({$0.isFinite && $0>=0}),clip.length>0 else{s.error="Enter valid nonnegative positions and a positive length.";return}
        do {
            let file=try AVAudioFile(forReading:safeChild(s.root,clip.asset))
            let duration=Double(file.length)/file.processingFormat.sampleRate
            guard clip.offset+clip.length*60/s.session.tempo<=duration+0.01 else{s.error="Crop extends beyond the original audio.";return}
            s.commitClip(clip)
        }catch{s.fail(error)}
    }
}

@MainActor struct MacNoteEditor:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) private var presentation
    let trackID:UUID
    @State private var selected:UUID?
    @State private var scale=50.0
    @State private var moving:UUID?
    @State private var drag=CGSize.zero
    @State private var resizing:UUID?
    @State private var resized:Double?
    private let rowHeight=18.0
    private var track:Track?{s.session.tracks.first{$0.id==trackID}}
    private var selectedNote:MIDIEvent?{track?.notes.first{$0.id==selected}}
    private var width:Double{max(16*scale,((track?.notes.map{$0.beat+$0.duration}.max() ?? 0)+4)*scale)}
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text("MIDI Notes · \(track?.name ?? "Track")").font(.title2);Spacer();Button("Undo"){s.undo()}.disabled(!s.canUndo);Button("Redo"){s.redo()}.disabled(!s.canRedo);Button("Done"){presentation.wrappedValue.dismiss()}}
            HStack{Toggle("Snap",isOn:$s.snap);Picker("Grid",selection:$s.grid){Text("1/4").tag(1.0);Text("1/8").tag(0.5);Text("1/16").tag(0.25);Text("1/32").tag(0.125)}.frame(width:140);Text("Zoom");Slider(value:$scale,in:25...120).frame(width:150)}
            ScrollViewReader{reader in ScrollView([.horizontal,.vertical]){
                VStack(spacing:0){
                    HStack(spacing:0){Color.clear.frame(width:50);ForEach(0..<Int(width/scale),id:\.self){beat in Text("\(beat+1)").font(.caption2).frame(width:scale,alignment:.leading)}}
                    ForEach(Array((0...127).reversed()),id:\.self){pitch in row(pitch).id(pitch)}
                }
            }.frame(height:380).onAppear{reader.scrollTo(selectedNote?.note ?? track?.notes.first?.note ?? 60,anchor:.center)}}
            if let n=selectedNote {
                HStack{
                    Stepper("Note \(n.note)",value:Binding(get:{n.note},set:{v in edit(n){$0.note=v}}),in:0...127)
                    numeric("Beat",value:n.beat){v in edit(n){$0.beat=v}}
                    numeric("Length",value:n.duration){v in edit(n){$0.duration=v}}
                    Stepper("Velocity \(n.velocity)",value:Binding(get:{n.velocity},set:{v in edit(n){$0.velocity=v}}),in:1...127)
                    Button("Delete",role:.destructive){s.change{session in if let i=session.tracks.firstIndex(where:{$0.id==trackID}){session.tracks[i].notes.removeAll{$0.id==n.id}}};selected=nil}
                }
            }
            Text("Click empty grid space to add a note. Click a note to edit it; drag its body to move pitch/time, or drag its right edge to change length. Edits stop playback and support Undo/Redo.").font(.caption)
        }.padding(20).frame(width:1000)
    }
    private func numeric(_ title:String,value:Double,set:@escaping(Double)->Void)->some View{HStack{Text(title);TextField(title,value:Binding(get:{value},set:set),format:.number).frame(width:75)}}
    private func edit(_ note:MIDIEvent,_ action:(inout MIDIEvent)->Void){s.editMIDINote(track:trackID,note:note.id,edit:action)}
    private func row(_ pitch:Int)->some View {
        HStack(spacing:0){
            Text("\(pitch)").font(.caption2).frame(width:50,height:rowHeight)
            ZStack(alignment:.topLeading){
                Rectangle().fill([1,3,6,8,10].contains(pitch%12) ? Color.white.opacity(0.04):Color.white.opacity(0.10))
                    .gesture(DragGesture(minimumDistance:0).onEnded{v in guard !s.busy,!s.recording,abs(v.translation.width)<3,abs(v.translation.height)<3,let ti=s.session.tracks.firstIndex(where:{$0.id==trackID && !$0.isAudio}) else{return};let note=MIDIEvent(beat:MIDINoteEdits.snapped(v.location.x/scale,grid:s.snap ? s.grid:nil),duration:max(0.25,s.grid),note:pitch);s.change{$0.tracks[ti].notes.append(note)};selected=note.id})
                Path{p in for beat in 0...Int(width/scale){let x=Double(beat)*scale;p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:rowHeight))}}.stroke(Color.gray.opacity(0.3),lineWidth:1).allowsHitTesting(false)
                ForEach(track?.notes.filter{$0.note==pitch} ?? []){n in
                    Rectangle().fill(selected==n.id ? Color.cyan:Color.orange)
                        .frame(width:max(8,(resizing==n.id ? resized ?? n.duration:n.duration)*scale),height:rowHeight-2)
                        .overlay(alignment:.trailing){Rectangle().fill(Color.white.opacity(0.7)).frame(width:7).gesture(DragGesture(minimumDistance:1).onChanged{v in selected=n.id;resizing=n.id;resized=MIDINoteEdits.resized(n,beats:v.translation.width/scale,grid:s.snap ? s.grid:nil).duration}.onEnded{v in let value=MIDINoteEdits.resized(n,beats:v.translation.width/scale,grid:s.snap ? s.grid:nil);edit(n){$0.duration=value.duration};resizing=nil;resized=nil})}
                        .offset(x:n.beat*scale+(moving==n.id ? drag.width:0),y:moving==n.id ? drag.height:0).zIndex(moving==n.id ? 2:1)
                        .onTapGesture{selected=n.id}
                        .gesture(DragGesture(minimumDistance:3).onChanged{v in selected=n.id;moving=n.id;drag=v.translation}.onEnded{v in let value=MIDINoteEdits.moved(n,beats:v.translation.width/scale,pitches:Int((-v.translation.height/rowHeight).rounded()),grid:s.snap ? s.grid:nil);edit(n){$0.beat=value.beat;$0.note=value.note};moving=nil;drag = .zero})
                }
            }.frame(width:width,height:rowHeight)
        }
    }
}
