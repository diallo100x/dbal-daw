import SwiftUI
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

@MainActor struct ImportPicker:UIViewControllerRepresentable {
    let types:[UTType]
    let asCopy:Bool
    let picked:(URL)->Void
    func makeCoordinator()->Coordinator{Coordinator(picked)}
    func makeUIViewController(context:Context)->UIDocumentPickerViewController{
        let vc=UIDocumentPickerViewController(forOpeningContentTypes:types,asCopy:asCopy);vc.delegate=context.coordinator;vc.allowsMultipleSelection=false;return vc
    }
    func updateUIViewController(_ uiViewController:UIDocumentPickerViewController,context:Context){}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let picked:(URL)->Void
        init(_ picked:@escaping(URL)->Void){self.picked=picked}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){if let url=urls.first{picked(url)}}
    }
}
@MainActor struct ExportPicker:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {UIDocumentPickerViewController(forExporting:[url],asCopy:true)}
    func updateUIViewController(_ uiViewController:UIDocumentPickerViewController,context:Context){}
}
@MainActor struct ControllerContainer:UIViewControllerRepresentable {
    let controller:UIViewController
    func makeUIViewController(context:Context)->UIViewController{controller}
    func updateUIViewController(_ uiViewController:UIViewController,context:Context){}
}
@MainActor struct PluginPanel:View {
    let controller:UIViewController
    let done:()->Void
    var body:some View{VStack{HStack{Text("Audio Unit Editor");Spacer();Button("Done",action:done)}.padding();ControllerContainer(controller:controller)}}
}
@MainActor struct PluginPicker:View {
    @Environment(\.presentationMode) var presentation
    let effect:Bool
    let picked:(PluginRef)->Void
    var body:some View {
        NavigationView {
            PluginDiscoveryList(effect: effect, picked: picked)
                .navigationTitle(effect ? "Audio Unit Effects" : "Audio Unit Instruments")
                .toolbar { Button("Cancel") { presentation.wrappedValue.dismiss() } }
        }.navigationViewStyle(.stack)
    }
}

@MainActor struct SettingsView:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) var presentation
    @State private var buffer=Flavor.defaultBuffer
    @State private var input=""
    @State private var monitor=false
    var body:some View{
        NavigationView {
            Form {
                Section(header:Text("Recording")) {
                    Picker("Pre-roll",selection:$s.preRoll){Text("Off").tag(0);Text("1 Bar").tag(1);Text("2 Bars").tag(2)}
                    Picker("Buffer frames",selection:$buffer){ForEach([128,256,512,1024],id:\.self){Text("\($0)").tag($0)}}
                    #if !targetEnvironment(macCatalyst)
                    Picker("Input device",selection:$input){Text("System Default").tag("");ForEach(AVAudioSession.sharedInstance().availableInputs ?? [],id:\.uid){Text($0.portName).tag($0.uid)}}
                    #else
                    Text("Mac input device: choose it in System Settings → Sound.")
                    #endif
                    Toggle("Input monitoring (use headphones)",isOn:$monitor)
                    ProgressView(value:Double(min(1,s.inputLevel))).tint(s.inputLevel>=0.98 ? .red : .green)
                    Text("Input meter is active during audio recording. Audio records the current input channels; track inserts are heard on playback.").font(.caption)
                }
                Section(header:Text("Timeline")){
                    Stepper("\(s.session.beatsPerBar) beats per bar",value:Binding(get:{s.session.beatsPerBar},set:{v in s.change{$0.beatsPerBar=v}}),in:1...12)
                    HStack{Text("Loop start (beats)");TextField("Start",value:Binding(get:{s.session.loopStart},set:{v in s.change{$0.loopStart=max(0,min(v,$0.loopEnd-0.25))}}),format:.number).keyboardType(.decimalPad)}
                    HStack{Text("Loop end (beats)");TextField("End",value:Binding(get:{s.session.loopEnd},set:{v in s.change{$0.loopEnd=max($0.loopStart+0.25,v)}}),format:.number).keyboardType(.decimalPad)}
                }
                if let i=s.selectedIndex {
                    Section(header:Text("Selected track")){
                        TextField("Track name",text:Binding(get:{s.session.tracks[i].name},set:{s.session.tracks[i].name=String($0.prefix(80));s.save()}))
                        if s.session.tracks[i].instrument == .sf2 && !s.session.tracks[i].isAudio {
                            Stepper("SF2 program \(s.session.tracks[i].program) (0–127)",value:Binding(get:{s.session.tracks[i].program},set:{v in s.change({$0.tracks[i].program=v},graph:true)}),in:0...127)
                            Stepper("Bank MSB \(s.session.tracks[i].bankMSB)",value:Binding(get:{s.session.tracks[i].bankMSB},set:{v in s.change({$0.tracks[i].bankMSB=v},graph:true)}),in:0...127)
                            Stepper("Bank LSB \(s.session.tracks[i].bankLSB)",value:Binding(get:{s.session.tracks[i].bankLSB},set:{v in s.change({$0.tracks[i].bankLSB=v},graph:true)}),in:0...127)
                        }
                        Button("Delete Selected Track",role:.destructive){let id=s.session.tracks[i].id;s.change({$0.tracks.removeAll{$0.id==id}},graph:true);s.selected=s.session.tracks.first?.id;presentation.wrappedValue.dismiss()}
                    }
                }
                Section(header:Text("Audio engine")){
                    Button("Apply Settings / Restart Audio"){
                        Task {
                            s.stop();s.audio.bufferFrames=buffer;s.audio.selectedInput=input.isEmpty ? nil : input
                            if monitor && !s.microphoneGranted {guard await s.requestMicrophone() else{return}}
                            s.audio.monitorEnabled=monitor;await s.rebuild()
                        }
                    }.disabled(s.recording || s.busy)
                    Text("Legacy uses 16 sampler voices per instrument; Pro uses 48. SFZ loads samples into memory and supports a documented subset. Live MIDI playback uses a control-thread scheduler in v0.1.").font(.caption)
                }
            }.navigationTitle("Studio Settings").toolbar{Button("Done"){presentation.wrappedValue.dismiss()}}
        }.navigationViewStyle(.stack).onAppear{buffer=s.audio.bufferFrames;input=s.audio.selectedInput ?? "";monitor=s.audio.monitorEnabled}
    }
}
@MainActor struct ClipEditor:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) var presentation
    @State private var draft:AudioClip?
    var body:some View{
        NavigationView{
            Form {
                if let c=draft {
                    Text(c.name).font(.headline)
                    field("Timeline start (beats)",key:\.start)
                    field("Source offset (seconds)",key:\.offset)
                    field("Length (beats)",key:\.length)
                    field("Fade in (seconds)",key:\.fadeIn)
                    field("Fade out (seconds)",key:\.fadeOut)
                    Text("Trim the start by increasing source offset and reducing length. Source recordings remain intact.").font(.caption)
                    Button("Apply Edits"){
                        guard let d=draft,let ti=s.selectedIndex,let ci=s.session.tracks[ti].clips.firstIndex(where:{$0.id==d.id}) else{return}
                        guard [d.start,d.offset,d.length,d.fadeIn,d.fadeOut].allSatisfy({$0.isFinite && $0>=0}),d.length>0 else{s.error="Clip positions must be valid positive numbers.";return}
                        do{
                            let f=try AVAudioFile(forReading:safeChild(s.root,d.asset))
                            let duration=Double(f.length)/f.processingFormat.sampleRate
                            guard d.offset+d.length*60/s.session.tempo<=duration+0.01 else{s.error="Trim extends beyond the source audio.";return}
                            s.change({$0.tracks[ti].clips[ci]=d},graph:true);presentation.wrappedValue.dismiss()
                        }catch{s.fail(error)}
                    }
                    Button("Split at Cursor"){s.splitClip();presentation.wrappedValue.dismiss()}
                    Button("Duplicate After Clip"){s.duplicateClip();presentation.wrappedValue.dismiss()}
                    Button("Delete Clip",role:.destructive){s.deleteClip();presentation.wrappedValue.dismiss()}
                }else{Text("Select an audio clip first.")}
            }.navigationTitle("Audio Clip").toolbar{Button("Done"){presentation.wrappedValue.dismiss()}}
        }.navigationViewStyle(.stack).onAppear{if let i=s.selectedIndex{draft=s.session.tracks[i].clips.first{$0.id==s.selectedClip}}}
    }
    func field(_ label:String,key:WritableKeyPath<AudioClip,Double>)->some View{
        HStack{Text(label);Spacer();TextField(label,value:Binding(get:{draft?[keyPath:key] ?? 0},set:{draft?[keyPath:key]=$0}),format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:100)}
    }
}
@MainActor struct NoteEditor:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) var presentation
    @State private var pitch=60
    @State private var length=1.0
    var body:some View{
        NavigationView{
            Form{
                if let id=s.selected { MIDIQuantizeTools(trackID:id) }
                Stepper("MIDI note \(pitch)",value:$pitch,in:0...127)
                Picker("Length",selection:$length){Text("1/16").tag(0.25);Text("1/8").tag(0.5);Text("1/4").tag(1.0);Text("1/2").tag(2.0);Text("Bar").tag(Double(s.session.beatsPerBar))}
                Button("Add Note at Cursor"){
                    guard let i=s.selectedIndex else{return}
                    s.change{$0.tracks[i].notes.append(MIDIEvent(beat:s.quantize(s.beat),duration:length,note:pitch))}
                }
                if let i=s.selectedIndex {
                    ForEach(s.session.tracks[i].notes.sorted{$0.beat<$1.beat}){n in
                        VStack(alignment:.leading){
                            Text("Note \(n.note) • beat \(n.beat,specifier:"%.2f") • length \(n.duration,specifier:"%.2f")").font(.caption)
                            HStack{
                                Button("− Grid"){edit(n,i){$0.beat=max(0,$0.beat-s.grid)}}
                                Button("+ Grid"){edit(n,i){$0.beat+=s.grid}}
                                Button("− Pitch"){edit(n,i){$0.note=max(0,$0.note-1)}}
                                Button("+ Pitch"){edit(n,i){$0.note=min(127,$0.note+1)}}
                                Button("Delete",role:.destructive){s.change{$0.tracks[i].notes.removeAll{$0.id==n.id}}}
                            }.font(.caption).buttonStyle(.borderless)
                        }
                    }
                }
            }.navigationTitle("MIDI Notes").toolbar{Button("Done"){presentation.wrappedValue.dismiss()}}
        }.navigationViewStyle(.stack)
    }
    func edit(_ note:MIDIEvent,_ ti:Int,_ action:(inout MIDIEvent)->Void){
        guard let ni=s.session.tracks[ti].notes.firstIndex(where:{$0.id==note.id}) else{return}
        s.change{action(&$0.tracks[ti].notes[ni])}
    }
}
