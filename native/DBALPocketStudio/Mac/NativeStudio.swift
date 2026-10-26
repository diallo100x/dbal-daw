import SwiftUI
import AppKit
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

@main @MainActor struct DBALNativeApp:App {
    @StateObject private var studio=Studio()
    var body:some Scene {
        WindowGroup {NativeStudioView().environmentObject(studio).preferredColorScheme(.dark)}
            .commands{CommandGroup(replacing:.newItem){Button("New Session"){Task{await studio.newSession()}}.keyboardShortcut("n")}
                CommandGroup(replacing:.appSettings){Button("Audio & MIDI Settings…"){studio.showAudioMIDISettings=true}.keyboardShortcut(",")}
            }
    }
}
@MainActor struct NativeStudioView:View {
    @EnvironmentObject var s:Studio
    @State private var performance=false
    @State private var plugins=false
    @State private var effect=false
    @State private var editingMIDI:UUID?
    @State private var editingAudio:UUID?
    @State private var zoom=28.0
    @State private var remoteCrossfader=false
    @StateObject private var waves=Waveforms()
    @StateObject private var midi=MacMIDIReceiver()
    var body:some View {
        VStack(spacing:0){
            transport.padding(10)
            Divider()
            HSplitView {
                trackList.frame(minWidth:210,idealWidth:240,maxWidth:320)
                VStack(alignment:.leading){
                    timeline
                    inspector.padding(10)
                }.frame(minWidth:500)
            }
            Divider()
            HStack{Text(s.status+" • "+midi.status).font(.caption);Spacer();Text("a product of Diallo Beats Audio Lab").font(.caption2)}.padding(8)
        }.frame(minWidth:1000,minHeight:620)
        .sheet(isPresented:$s.showAudioMIDISettings){MacAudioMIDISettings(midi:midi).environmentObject(s)}
        .sheet(isPresented:Binding(get:{editingMIDI != nil},set:{if !$0{editingMIDI=nil}})){if let id=editingMIDI{MacNoteEditor(trackID:id).environmentObject(s)}}
        .sheet(isPresented:Binding(get:{editingAudio != nil},set:{if !$0{editingAudio=nil}})){if let id=editingAudio{MacAudioEditor(clipID:id,waves:waves).environmentObject(s)}}
        .sheet(isPresented:$performance){PerformancePanel().environmentObject(s).frame(minWidth:800,minHeight:650)}
        .sheet(isPresented:$plugins){MacPluginPicker(effect:effect){ref in plugins=false;s.choosePlugin(ref,effect:effect)}}
        .sheet(isPresented:Binding(get:{s.pluginController != nil},set:{if !$0{s.pluginController=nil}})){
            VStack {HStack{Spacer();Button("Close"){s.pluginController=nil}};if let controller=s.pluginController{MacPluginController(controller:controller)}}.padding().frame(minWidth:600,minHeight:450)
        }
        .alert("Pocket Studio",isPresented:Binding(get:{s.error != nil},set:{if !$0{s.error=nil}})){Button("OK"){s.error=nil}}message:{Text(s.error ?? "")}
        .onAppear{midi.receive=receiveMIDI;midi.release={for key in Array(s.held.keys){s.noteOff(key)}}}
        .onDisappear{midi.close()}
        .onChange(of:s.exportURL){url in if let url=url{saveExport(url)}}
    }
    private var transport:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{
                Text("DBAL DAW • Native Mac").font(.headline)
                Button("Open…"){openProject()};Button("Save"){s.save(capture:true)}.keyboardShortcut("s")
                Menu("Export"){Button("Portable Project"){s.exportProject()};Button("Stereo WAV"){Task{await s.exportMix()}}}
                Button("Audio & MIDI Settings…"){s.showAudioMIDISettings=true}
                Spacer();Button("Restart Audio"){Task{await s.rebuild()}}.disabled(s.busy || s.recording)
            }
            HStack{
                Group {
                Button("Play"){s.play()}.keyboardShortcut(.space,modifiers:[])
                Button("Stop"){s.stop(resetIfStopped:true)}
                Button(s.recording ? "Finish Take":"Record"){Task{await s.toggleRecord()}}
                Button("Count-in: \(s.preRoll)"){s.cycleCountIn()}
                Text("Beat \(s.beat,specifier:"%.2f")").monospacedDigit()
                }
                Stepper("BPM \(Int(s.session.tempo))",value:Binding(get:{s.session.tempo},set:{value in s.change({session in
                    let ratio=value/session.tempo
                    for i in session.tracks.indices{for j in session.tracks[i].clips.indices{session.tracks[i].clips[j].length *= ratio}}
                    session.tempo=value
                },graph:true)}),in:30...300).frame(width:150).disabled(s.recording || s.playing)
                Toggle("Snap",isOn:$s.snap).toggleStyle(.checkbox)
                Picker("Grid",selection:$s.grid){Text("1/4").tag(1.0);Text("1/8").tag(0.5);Text("1/16").tag(0.25);Text("1/32").tag(0.125)}.frame(width:115)
            }.disabled(s.busy)
            HStack{
                Button("Undo"){s.undo()}.disabled(!s.canUndo);Button("Redo"){s.redo()}.disabled(!s.canRedo)
                Toggle("Loop",isOn:Binding(get:{s.session.loop},set:{value in s.change{$0.loop=value}})).toggleStyle(.checkbox)
                Toggle("Click",isOn:$s.metronome).toggleStyle(.checkbox)
                Button(midi.enabled ? "MIDI Input On / Refresh":"Enable MIDI Input"){midi.start()}
                if midi.enabled{Button("MIDI Off"){midi.close()};Toggle("CC16 → tracks 1/2",isOn:$remoteCrossfader).toggleStyle(.checkbox).font(.caption)}
            }.disabled(s.busy)
        }
    }
    private var trackList:some View {
        VStack {
            HStack{Button("+ Audio"){s.addTrack(audio:true)};Button("+ MIDI"){s.addTrack(audio:false)}}.padding(8)
            List(s.session.tracks,selection:Binding(get:{s.selected},set:{id in if let id=id{s.selectTrack(id)}})){track in
                VStack(alignment:.leading){
                    Button(track.name){s.selectTrack(track.id)}.buttonStyle(.plain).foregroundColor(s.selected==track.id ? .cyan:.primary)
                    HStack{
                        Button(s.armed==track.id ? "ARMED":"Arm"){s.armed=s.armed==track.id ? nil:track.id}.disabled(s.recording)
                        Button(track.mute ? "Unmute":"Mute"){editTrack(track.id){$0.mute.toggle()}}
                        Button(track.solo ? "Unsolo":"Solo"){editTrack(track.id){$0.solo.toggle()}}
                    }.font(.caption)
                    if track.isAudio {
                        Button(s.monitoredTrack==track.id ? "● Input Monitor On":"Input Monitor"){Task{await s.setInputMonitoring(s.monitoredTrack==track.id ? nil:track.id)}}.disabled(s.busy || s.recording)
                    }
                    Slider(value:Binding(get:{Double(s.session.tracks.first{$0.id==track.id}?.volume ?? 0.8)},set:{v in if let i=s.session.tracks.firstIndex(where:{$0.id==track.id}){s.session.tracks[i].volume=Float(v);s.audio.updateMixer(s.session)}}),in:0...1.5,onEditingChanged:{if !$0{s.save()}})
                }.padding(.vertical,5).frame(maxWidth:.infinity,alignment:.leading)
                    .contentShape(Rectangle()).simultaneousGesture(TapGesture().onEnded{s.selectTrack(track.id)})
                    .listRowBackground(s.selected==track.id ? Color.cyan.opacity(0.22):Color.clear)
                    .tag(track.id)
            }
        }
    }
    private var timeline:some View {
        ScrollView([.horizontal,.vertical]){
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:0){ForEach(0..<129){beat in Text("\(beat+1)").font(.caption2).frame(width:zoom,alignment:.leading)}}
                    .frame(height:25).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onEnded{v in if !s.playing{s.beat=s.quantize(v.location.x/zoom)}})
                ForEach(s.session.tracks){track in
                    ZStack(alignment:.topLeading){
                        Rectangle().fill(s.selected==track.id ? Color.cyan.opacity(0.16):Color.black.opacity(0.2))
                            .contentShape(Rectangle()).onTapGesture{s.selectTrack(track.id);if !track.isAudio{editingMIDI=track.id}}
                        ForEach(track.clips){clip in
                            ClipTile(clip:clip,trackID:track.id,zoom:zoom,waveform:waves.data[clip.asset],onEdit:{editingAudio=clip.id})
                                .offset(x:clip.start*zoom,y:4)
                                .task(id:clip.asset){await waves.load(clip.asset,root:s.root)}
                                .contextMenu{Button("Split at Cursor"){s.selectClips([clip.id]);s.splitClip()};Button("Duplicate"){s.selectClips([clip.id]);s.duplicateClip()};Button("Delete"){s.selectClips([clip.id]);s.deleteClip()}}
                        }
                        ForEach(track.notes){note in Rectangle().fill(Color.orange).frame(width:max(3,note.duration*zoom),height:5).offset(x:note.beat*zoom,y:CGFloat(10+(127-note.note)%60)).onTapGesture{s.selectTrack(track.id);editingMIDI=track.id}}
                    }.frame(width:timelineWidth,height:82).clipped()
                }
            }.overlay(alignment:.topLeading){Rectangle().fill(Color.red).frame(width:1).offset(x:s.beat*zoom).allowsHitTesting(false)}
        }
    }
    private var timelineWidth:Double {max(129*zoom,(s.session.tracks.flatMap{$0.clips}.map{$0.start+$0.length}.max() ?? 0)*zoom+200)}
    @ViewBuilder private var inspector:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{
                Button("Import Audio…"){importAudio()}
                Button("Sampler / XY"){performance=true}
                Button("AU Instrument…"){effect=false;plugins=true}.disabled(s.selectedIndex.map{s.session.tracks[$0].isAudio} ?? true)
                Button("+ AU Effect…"){effect=true;plugins=true}
                Slider(value:$zoom,in:8...80).frame(width:120)
            }
            if let i=s.selectedIndex {
                Text("Selected: \(s.session.tracks[i].name) · \(s.session.tracks[i].isAudio ? "Audio":"MIDI / Instrument")").font(.headline)
                HStack{
                    if s.session.tracks[i].isAudio {
                        Button(s.monitoredTrack==s.selected ? "Input Monitor On":"Input Monitor Off"){Task{await s.setInputMonitoring(s.monitoredTrack==s.selected ? nil:s.selected)}}
                    }else{Button("Edit MIDI Notes"){editingMIDI=s.selected}}
                    Menu("Instrument: \(s.session.tracks[i].instrument.rawValue)"){
                        ForEach([InstrumentKind.tone,.drums,.sample,.padSampler],id:\.self){kind in Button(kind.rawValue){s.change({$0.tracks[i].instrument=kind;$0.tracks[i].plugin=nil},graph:true)}}
                        Button("Import SF2…"){importInstrument(folder:false)};Button("Import SFZ Folder…"){importInstrument(folder:true)}
                    }.disabled(s.session.tracks[i].isAudio)
                    Button("Instrument UI"){s.showPlugin()}.disabled(s.session.tracks[i].isAudio)
                    ForEach(Array(s.session.tracks[i].effects.enumerated()),id:\.element.id){index,ref in Menu(ref.name){Button("Open UI"){s.showPlugin(effectIndex:index)};Button("Remove"){s.change({$0.tracks[i].effects.remove(at:index)},graph:true)}}}
                }
            }
            if let clip=s.session.tracks.flatMap({$0.clips}).first(where:{$0.id==s.selectedClip}){
                HStack{Text(clip.name);Button("Edit Waveform"){editingAudio=clip.id};Button("Split"){s.splitClip()};Button("Duplicate"){s.duplicateClip()};Button("Fade Curve"){s.cycleFadeCurve(clip.id)};Button("Delete"){s.deleteClip()}}
            }
            Text("Click a track to select it. Click an audio clip or MIDI lane to edit. Audio edges trim; corners fade. Shift-click a fade to change its curve.").font(.caption).foregroundColor(.secondary)
        }.disabled(s.busy || s.recording)
    }
    private func receiveMIDI(_ message:MIDIMessage){
        let kind=message.status&0xF0,channel=Int(message.status&0x0F)
        if kind==0x90 && message.data2>0{s.noteOn(Int(message.data1))}
        else if kind==0x80 || (kind==0x90 && message.data2==0){s.noteOff(Int(message.data1))}
        else if kind==0xB0 && message.data1==7 && channel<s.session.tracks.count {
            s.session.tracks[channel].volume=Float(message.data2)/127;s.audio.updateMixer(s.session)
        }else if kind==0xB0 && message.data1==16 && remoteCrossfader && s.session.tracks.count>=2{
            let position=Double(message.data2)/127
            s.session.tracks[0].volume=Float(cos(position*Double.pi/2));s.session.tracks[1].volume=Float(sin(position*Double.pi/2));s.audio.updateMixer(s.session)
        }else if kind==0xB0 && (message.data1==120 || message.data1==123){
            for key in Array(s.held.keys){s.noteOff(key)};s.audio.runtimes.values.forEach{$0.silence()}
        }else if message.status==0xFA{s.play()}else if message.status==0xFC{s.stop()}
    }
    private func editTrack(_ id:UUID,_ edit:(inout Track)->Void){if let i=s.session.tracks.firstIndex(where:{$0.id==id}){edit(&s.session.tracks[i]);s.audio.updateMixer(s.session);s.save()}}
    private func importAudio(){let panel=NSOpenPanel();panel.allowedContentTypes=[.audio];if panel.runModal() == .OK,let url=panel.url{Task{await s.importAudio(url)}}}
    private func importInstrument(folder:Bool){let panel=NSOpenPanel();panel.canChooseDirectories=folder;panel.canChooseFiles = !folder;if !folder{panel.allowedContentTypes=[UTType(filenameExtension:"sf2") ?? .data]};if panel.runModal() == .OK,let url=panel.url{Task{await s.importInstrument(url,folder:folder)}}}
    private func openProject(){let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;if panel.runModal() == .OK,let url=panel.url{Task{await s.open(url)}}}
    private func saveExport(_ url:URL){let panel=NSSavePanel();panel.nameFieldStringValue=url.lastPathComponent;if panel.runModal() == .OK,let dest=panel.url{do{if dest.pathExtension=="pocketstudio"{try copySafeTree(url,to:dest)}else{try FileManager.default.copyItem(at:url,to:dest)}}catch{s.fail(error)}};s.exportURL=nil}
}
@MainActor struct MacPluginPicker:View {
    let effect:Bool
    let picked:(PluginRef)->Void
    @Environment(\.presentationMode) var presentation
    @State private var plugins:[PluginRef]=[]
    var body:some View {
        VStack{
            HStack{Text(effect ? "AU v2 / AUv3 Effects":"AU v2 / AUv3 Instruments").font(.headline);Spacer();Button("Close"){presentation.wrappedValue.dismiss()}}
            List(plugins){plugin in Button(plugin.name){picked(plugin)}}
            Text("Install Apple Silicon compatible Mac plugins. Missing custom editors use generic parameters. VST hosting is not included.").font(.caption)
        }.padding().frame(width:550,height:450).onAppear{
            let types:[OSType]=effect ? [kAudioUnitType_Effect,kAudioUnitType_MusicEffect]:[kAudioUnitType_MusicDevice]
            plugins=types.flatMap{type in AVAudioUnitComponentManager.shared().components(matching:AudioComponentDescription(componentType:type,componentSubType:0,componentManufacturer:0,componentFlags:0,componentFlagsMask:0)).map{c in let d=c.audioComponentDescription;return PluginRef(name:c.name,type:d.componentType,subtype:d.componentSubType,manufacturer:d.componentManufacturer)}}.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
        }
    }
}
