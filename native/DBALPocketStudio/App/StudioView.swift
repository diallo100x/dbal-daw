import SwiftUI
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

@main @MainActor struct PocketStudioApp: App {
    @StateObject private var studio = Studio()
    var body: some Scene { WindowGroup { StudioView().environmentObject(studio).preferredColorScheme(.dark) } }
}
private enum ImportAction: String, Identifiable { case audio, sf2, sfzFolder, project; var id:String{rawValue} }
@MainActor struct StudioView: View {
    @EnvironmentObject var s: Studio
    @State private var importAction: ImportAction?
    @State private var pluginEffect: Bool?
    @State private var settings = false
    @State private var editor = false
    @State private var noteEditor = false
    @State private var noteList = false
    @State private var waveEditor = false
    @State private var performance = false
    @State private var remote = false
    @State private var zoom = 28.0
    @StateObject private var waveforms = Waveforms()
    var body: some View {
        VStack(spacing: 0) {
            header
            transport.padding(8).background(Color(white:0.12))
            ScrollView(.horizontal,showsIndicators:false) { HStack {
                Menu("Session") {
                    Button("New Session") { Task { await s.newSession() } }
                    Button("Open Project Folder…") { importAction = .project }
                    Button("Save + Plugin Settings") { s.save(capture:true) }
                    Button("Export Portable Project…") { s.exportProject() }
                    Button("Export Stereo WAV…") { Task { await s.exportMix() } }
                }
                Menu("Edit") {
                    Button("MIDI Timeline Editor…") { noteEditor=true }.disabled(s.selectedIndex.map{s.session.tracks[$0].isAudio} ?? true)
                    Button("MIDI Note List…") { noteList=true }.disabled(s.selectedIndex.map{s.session.tracks[$0].isAudio} ?? true)
                    Button("Detailed Waveform Editor…") { waveEditor=true }.disabled(s.selectedClip == nil)
                    Button("Audio Clip Properties…") { editor=true }.disabled(s.selectedClip == nil)
                    Button("Quantize MIDI Track") { if let id=s.selected{s.quantizeNotes(track:id)} }.disabled(s.selectedIndex.map{s.session.tracks[$0].isAudio} ?? true)
                    Toggle("Input Quantize",isOn:$s.inputQuantize)
                }
                Menu("+ Track") { Button("Audio / Vocals") { s.addTrack(audio:true) }; Button("Instrument / MIDI") { s.addTrack(audio:false) } }
                Button("Import Audio") { importAction = .audio }
                Spacer()
                Button("Remote"){remote=true}
                Button("Sampler / XY") { performance=true }
                Button("Settings") { settings = true }
            }.font(.caption).padding(8) }.disabled(s.busy || s.recording)
            TimelineView(zoom:zoom,waveforms:waveforms).environmentObject(s)
            ScrollView(.horizontal,showsIndicators:false) { HStack {
                Text("Zoom").font(.caption)
                Slider(value:$zoom,in:12...80).frame(maxWidth:160)
                Picker("Drag tool",selection:$s.selectionMode) { Text("Select").tag(true);Text("Move").tag(false) }.pickerStyle(.segmented).frame(width:130)
                Toggle("Add",isOn:$s.selectionAdds).fixedSize().font(.caption)
                Menu("Edit \(s.selectedClips.count) Clips") { SelectionCommands() }.font(.caption)
                Button("Clip Editor") { editor = true }.disabled(s.selectedClips.count != 1)
                Button("MIDI Editor") { noteEditor = true }.disabled(s.selectedIndex.map { s.session.tracks[$0].isAudio } ?? true)
                Spacer()
                Button(s.showPads ? "Piano" : "Pads") { s.showPads.toggle() }
            }.padding(8) }.background(Color(white:0.1))
            trackStrip
            if s.showPads { DrumPads().frame(height:140) } else { PianoKeys().frame(height:120) }
            HStack {
                Text(s.status).font(.caption2).lineLimit(3).textSelection(.enabled)
                Spacer()
                Text("a product of Diallo Beats Audio Lab").font(.system(size:9)).foregroundColor(.secondary)
            }.padding(8)
        }
        .background(Color(white:0.065))
        .disabled(s.busy)
        .overlay { if s.busy { VStack { ProgressView(); Text(s.status).font(.caption) }.padding(24).background(Color(white:0.15)).cornerRadius(12) } }
        .fullScreenCover(isPresented:$remote){RemotePanel().environmentObject(s)}
        .sheet(item:$importAction) { action in
            ImportPicker(types: action == .audio ? [.audio] : action == .sf2 ? [.data] : [.folder,.package], asCopy:false) { url in
                importAction=nil
                Task {
                    switch action {
                    case .audio: await s.importAudio(url)
                    case .sf2: await s.importInstrument(url,folder:false)
                    case .sfzFolder: await s.importInstrument(url,folder:true)
                    case .project: await s.open(url)
                    }
                }
            }
        }
        .sheet(isPresented:Binding(get:{pluginEffect != nil},set:{if !$0{pluginEffect=nil}})) {
            PluginPicker(effect:pluginEffect ?? false) { ref in s.choosePlugin(ref,effect:pluginEffect ?? false);pluginEffect=nil }
        }
        .sheet(isPresented:$performance) { PerformancePanel().environmentObject(s) }
        .sheet(isPresented:$settings) { SettingsView().environmentObject(s) }
        .sheet(isPresented:$editor) { ClipEditor().environmentObject(s) }
        .sheet(isPresented:$noteList) { NoteEditor().environmentObject(s) }
        .fullScreenCover(isPresented:$noteEditor) { if let id=s.selected{MIDITimelineEditor(trackID:id).environmentObject(s)} }
        .fullScreenCover(isPresented:$waveEditor) { if let id=s.selectedClip{AudioTimelineEditor(clipID:id,waves:waveforms).environmentObject(s)} }
        .sheet(isPresented:Binding(get:{s.pluginController != nil},set:{if !$0{s.pluginController=nil;s.save(capture:true)}})) {
            if let vc=s.pluginController { PluginPanel(controller:vc) { s.pluginController=nil;s.save(capture:true) } }
        }
        .sheet(isPresented:Binding(get:{s.exportURL != nil},set:{if !$0{s.exportURL=nil}})) {
            if let url=s.exportURL { ExportPicker(url:url) }
        }
        .onOpenURL { url in Task { await s.open(url) } }
        .alert("Pocket Studio",isPresented:Binding(get:{s.error != nil},set:{if !$0{s.error=nil}})) { Button("OK",role:.cancel){s.error=nil} } message:{Text(s.error ?? "")}
    }
    private var header: some View {
        HStack {
            VStack(alignment:.leading,spacing:2) {
                Text("DBAL POCKET STUDIO").font(.system(size:18,weight:.heavy,design:.rounded)).foregroundColor(.cyan)
                Text("\(Flavor.name) • Native iPad / Mac • v0.1.6").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            TextField("Session name",text:Binding(get:{s.session.name},set:{s.session.name=String($0.prefix(80));s.save()})).textFieldStyle(.roundedBorder).frame(maxWidth:240)
        }.padding(10)
    }
    private var transport: some View {
        VStack(alignment:.leading,spacing:10) {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:12) {
                    Button { s.play() } label:{Label("Play",systemImage:"play.fill")}.foregroundColor(.green).disabled(s.playing)
                    Button { s.stop(resetIfStopped:true) } label:{Label("Stop",systemImage:"stop.fill")}
                    Button { Task { await s.toggleRecord() } } label:{Label(s.recording ? "Finish" : "Record",systemImage:"record.circle")}.foregroundColor(.red)
                    Button { s.cycleCountIn() } label:{Label(s.preRoll == 0 ? "Count-in: Off" : "Count-in: \(s.preRoll) Bar\(s.preRoll == 1 ? "" : "s")",systemImage:"timer")}
                        .foregroundColor(s.preRoll > 0 ? .orange : .secondary).disabled(s.recording)
                        .accessibilityHint("Cycles count-in off, one bar, two bars. Count-in ticks are audible even when Click is off.")
                    Text(String(format:"%03d : %04.1f",Int(s.beat)/s.session.beatsPerBar+1,s.beat.truncatingRemainder(dividingBy:Double(s.session.beatsPerBar))+1)).monospacedDigit().frame(width:112)
                Stepper("\(Int(s.session.tempo)) BPM",value:Binding(get:{Int(s.session.tempo)},set:{new in
                    s.change({ session in
                        let ratio=Double(new)/session.tempo
                        for i in session.tracks.indices { for j in session.tracks[i].clips.indices { session.tracks[i].clips[j].length *= ratio } }
                        session.tempo=Double(new)
                    }, graph: true)
                }),in:30...300).frame(width:170).disabled(s.recording || s.playing)
                }.font(.caption)
            }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:14) {
                    Toggle("Snap",isOn:$s.snap).fixedSize()
                    Toggle("Input Quantize",isOn:$s.inputQuantize).fixedSize().disabled(s.recording)
                    Picker("Grid",selection:$s.grid) { Text("1/4").tag(1.0);Text("1/8").tag(0.5);Text("1/16").tag(0.25);Text("1/32").tag(0.125) }.pickerStyle(.menu).frame(width:85)
                    Button { s.undo() } label:{Image(systemName:"arrow.uturn.backward").frame(width:32,height:32)}
                        .disabled(!s.canUndo || s.recording).accessibilityLabel("Undo")
                    Button { s.redo() } label:{Image(systemName:"arrow.uturn.forward").frame(width:32,height:32)}
                        .disabled(!s.canRedo || s.recording).accessibilityLabel("Redo")
                    Toggle("Loop",isOn:Binding(get:{s.session.loop},set:{v in s.change{$0.loop=v}})).fixedSize().disabled(s.recording)
                    Toggle("Click",isOn:$s.metronome).fixedSize()
                }.font(.caption)
            }
        }
    }
    @ViewBuilder private var trackStrip: some View {
        if let i=s.selectedIndex {
            let t=s.session.tracks[i]
            ScrollView(.horizontal,showsIndicators:false) {
                HStack {
                    Text(t.name).font(.caption.bold())
                    if !t.isAudio {
                        Menu(t.instrument.rawValue) {
                            Button("Starter Keys") { s.change({$0.tracks[i].instrument = .tone;$0.tracks[i].plugin=nil},graph:true) }
                            Button("Starter Drum Kit") { s.change({$0.tracks[i].instrument = .drums;$0.tracks[i].plugin=nil},graph:true);s.showPads=true }
                            Button("Simple Sampler / Waveform Editor…") { performance=true }
                            Button("Sampler Keys") { s.change({$0.tracks[i].instrument = .sample},graph:true) }
                            Button("Sampler Pads") { s.change({$0.tracks[i].instrument = .padSampler},graph:true);s.showPads=true }
                            Button("Import SF2…") { importAction = .sf2 }
                            Button("Import SFZ Folder…") { importAction = .sfzFolder }
                            Button("Load AUv3 Instrument…") { pluginEffect=false }
                        }.disabled(s.recording || s.playing)
                        if t.instrument == .auv3 { Button("Instrument UI") { s.showPlugin() } }
                    }
                    Button("+ AU Effect") { pluginEffect=true }.disabled(s.recording || s.playing)
                    ForEach(Array(t.effects.enumerated()),id:\.element.id) { index,ref in
                        Menu(ref.name) {
                            Button("Open Editor") { s.showPlugin(effectIndex:index) }
                            Button("Remove",role:.destructive) { s.change({$0.tracks[i].effects.remove(at:index)},graph:true) }
                        }
                    }
                    Text("Vol").font(.caption2)
                    Slider(value:Binding(get:{Double(s.session.tracks[i].volume)},set:{s.session.tracks[i].volume=Float($0);s.audio.updateMixer(s.session)}),in:0...1.5,onEditingChanged:{if !$0{s.save()}}).frame(width:110)
                    Text("Pan").font(.caption2)
                    Slider(value:Binding(get:{Double(s.session.tracks[i].pan)},set:{s.session.tracks[i].pan=Float($0);s.audio.updateMixer(s.session)}),in:-1...1,onEditingChanged:{if !$0{s.save()}}).frame(width:90)
                }.padding(8).font(.caption)
            }
        }
    }
}
@MainActor struct TimelineView: View {
    @EnvironmentObject var s: Studio
    let zoom:Double
    @ObservedObject var waveforms: Waveforms
    @State private var selectionBase=Set<UUID>()
    @State private var selectionBeforeGesture=Set<UUID>()
    @State private var menuPoint=CGPoint(x:20,y:20)
    var total:Double { max(64,(s.session.tracks.flatMap{$0.clips.map{$0.start+$0.length}+$0.notes.map{$0.beat+$0.duration}}.max() ?? 0)+16,s.beat+16) }
    var body:some View {
        ScrollView([.horizontal,.vertical]) {
            HStack(alignment:.top,spacing:0) {
                VStack(spacing:1) {
                    Text("TRACKS").font(.caption.bold()).frame(width:150,height:32)
                    ForEach(s.session.tracks){track in TimelineTrackHeader(track:track)}
                }
                ZStack(alignment:.topLeading) {
                    VStack(spacing:1) {
                        TimelineRuler(zoom:zoom,total:total)
                        ForEach(s.session.tracks){track in
                            TimelineTrackLane(track:track,zoom:zoom,total:total,waveforms:waveforms)
                        }
                    }
                    if s.selectionMode && !s.session.tracks.isEmpty {
                        ClipSelectionSurface(enabled:!s.busy && !s.recording,edges:handleRegions,fadedAreas:fadeRegions,onTap:tap,onSelection:marquee)
                            .frame(width:total*zoom,height:Double(s.session.tracks.count)*85)
                            .offset(y:33)
                    }
                    Color.clear.frame(width:1,height:1)
                        .offset(x:menuPoint.x,y:menuPoint.y+33)
                        .popover(isPresented:$s.showSelectionMenu,arrowEdge:.top) {
                            VStack(alignment:.leading,spacing:14) {
                                Text("\(s.selectedClips.count) audio clips selected").font(.headline)
                                SelectionCommands()
                            }.padding(18).frame(width:280).buttonStyle(.borderless)
                        }
                }.frame(width:total*zoom,height:33+Double(s.session.tracks.count)*85,alignment:.topLeading)
            }
        }.frame(minHeight:180)
    }
    private var handleRegions:[CGRect] {
        ClipEdits.hitBoxes(in:s.session,zoom:zoom).filter{s.selectedClips.contains($0.0)}.flatMap { _,rect in
            [CGRect(x:rect.minX,y:rect.minY,width:18,height:rect.height),CGRect(x:rect.maxX-18,y:rect.minY,width:18,height:rect.height)]
        }
    }
    private var fadeRegions:[CGRect] {
        var regions:[CGRect]=[]
        for (row,track) in s.session.tracks.enumerated() {
            for c in track.clips where s.selectedClips.contains(c.id) {
                let px=s.session.tempo/60*zoom
                regions.append(CGRect(x:c.start*zoom,y:Double(row)*85+5,width:c.fadeIn*px,height:72))
                regions.append(CGRect(x:(c.start+c.length)*zoom-c.fadeOut*px,y:Double(row)*85+5,width:c.fadeOut*px,height:72))
            }
        };return regions
    }
    private func tap(_ point:CGPoint) {
        guard !s.recording,!s.busy else{return};s.showSelectionMenu=false
        if let id=ClipEdits.hit(in:s.session,at:point,zoom:zoom) {
            if s.selectionAdds {
                var ids=s.selectedClips
                if ids.contains(id){ids.remove(id)}else{ids.insert(id)}
                s.selectClips(ids,primary:id)
            }else{s.selectClips([id],primary:id)}
        }else{
            if !s.selectionAdds{s.clearClipSelection()}
            let row=Int(floor(point.y/85))
            if s.session.tracks.indices.contains(row){s.selected=s.session.tracks[row].id}
        }
    }
    private func marquee(_ begin:CGPoint,_ end:CGPoint,_ phase:MarqueePhase) {
        guard !s.recording,!s.busy else{return}
        switch phase {
        case .began:
            selectionBeforeGesture=s.selectedClips
            selectionBase=s.selectionAdds ? s.selectedClips : []
            s.showSelectionMenu=false
        case .cancelled:
            s.selectClips(selectionBeforeGesture);return
        default:break
        }
        let hits=ClipEdits.hits(in:s.session,from:begin,to:end,zoom:zoom)
        s.selectClips(selectionBase.union(hits))
        if case .ended=phase {
            menuPoint=CGPoint(x:max(1,min(end.x,total*zoom-1)),y:max(1,min(end.y,Double(s.session.tracks.count)*85-1)))
            s.showSelectionMenu = !s.selectedClips.isEmpty
        }
    }
}
@MainActor struct TimelineRuler:View {
    @EnvironmentObject var s:Studio
    let zoom:Double
    let total:Double
    var body:some View {
        ZStack(alignment:.topLeading) {
            Color(white:0.16)
            ForEach(0...Int(total/Double(s.session.beatsPerBar)),id:\.self){bar in
                Text("\(bar+1)").font(.caption2).position(x:Double(bar*s.session.beatsPerBar)*zoom+10,y:10)
            }
            Rectangle().fill(Color.orange.opacity(0.5)).frame(width:(s.session.loopEnd-s.session.loopStart)*zoom,height:5).offset(x:s.session.loopStart*zoom,y:27)
        }.frame(width:total*zoom,height:32).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onEnded{value in
                guard !s.recording else{return};s.stop();s.beat=s.quantize(Double(value.location.x)/zoom)
            })
    }
}
@MainActor struct TimelineTrackHeader:View {
    @EnvironmentObject var s:Studio
    let track:Track
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Button(track.name){s.selected=track.id;s.clearClipSelection()}.foregroundColor(s.selected==track.id ? .cyan : .white).lineLimit(1)
            HStack(spacing:10) {
                Button("R"){if !s.recording{s.armed=s.armed==track.id ? nil : track.id;s.selected=track.id}}.foregroundColor(s.armed==track.id ? .red : .gray)
                Button("M"){if let i=s.session.tracks.firstIndex(where:{$0.id==track.id}){s.session.tracks[i].mute.toggle();s.audio.updateMixer(s.session);s.save()}}.foregroundColor(track.mute ? .orange : .gray)
                Button("S"){if let i=s.session.tracks.firstIndex(where:{$0.id==track.id}){s.session.tracks[i].solo.toggle();s.audio.updateMixer(s.session);s.save()}}.foregroundColor(track.solo ? .yellow : .gray)
                Text(track.isAudio ? "AUDIO" : "MIDI").font(.system(size:8))
            }
        }.font(.caption.bold()).padding(.horizontal,8).frame(width:150,height:84,alignment:.leading).background(Color(white:s.selected==track.id ? 0.18 : 0.12))
    }
}
@MainActor struct TimelineTrackLane:View {
    @EnvironmentObject var s:Studio
    let track:Track
    let zoom:Double
    let total:Double
    @ObservedObject var waveforms:Waveforms
    var body:some View {
        ZStack(alignment:.topLeading) {
            Canvas{context,size in
                for b in 0...Int(total) {
                    var line=Path();line.move(to:CGPoint(x:Double(b)*zoom,y:0));line.addLine(to:CGPoint(x:Double(b)*zoom,y:size.height))
                    context.stroke(line,with:.color(Color.white.opacity(b%s.session.beatsPerBar==0 ? 0.18 : 0.06)),lineWidth:1)
                }
            }
            ForEach(track.clips){c in
                ClipTile(clip:c,trackID:track.id,zoom:zoom,waveform:waveforms.data[c.asset])
                    .offset(x:c.start*zoom,y:5)
                    .task(id:c.asset){await waveforms.load(c.asset,root:s.root)}
            }
            ForEach(track.notes){n in
                RoundedRectangle(cornerRadius:2).fill(Color.purple).frame(width:max(3,n.duration*zoom),height:6).offset(x:n.beat*zoom,y:Double(12+(127-n.note)%48))
            }
            Rectangle().fill(Color.yellow).frame(width:2,height:84).offset(x:s.beat*zoom).allowsHitTesting(false)
        }.frame(width:total*zoom,height:84).background(Color(white:0.085)).contentShape(Rectangle())
            .onTapGesture{s.selected=track.id}
    }
}
