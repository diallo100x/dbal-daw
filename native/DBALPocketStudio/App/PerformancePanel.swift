import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor struct PerformancePanel:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) var presentation
    var body:some View {
        NavigationView {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Menu("Track: \(s.selectedIndex.map{s.session.tracks[$0].name} ?? "None")") {
                        ForEach(s.session.tracks){track in Button(track.name){s.noteOff(-1);s.selected=track.id}}
                    }
                    if let i=s.selectedIndex,!s.session.tracks[i].isAudio {
                        SimpleSamplerEditor()
                        PerformanceDock()
                        Text("Pads send GM drum notes. Use Sampler Pads or Starter Drums for a drum kit; Sampler Keys maps its sample over the keyboard.").font(.caption).foregroundColor(.secondary)
                    }
                    MIDIControls()
                    Divider()
                    FXControls()
                }.padding()
            }.navigationTitle("Sampler & Performance")
                .toolbar{Button("Done"){s.noteOff(-1);presentation.wrappedValue.dismiss()}}
        }.pocketNavigationStyle().onDisappear{s.noteOff(-1)}
    }
}
@MainActor struct MIDIControls:View {
    @EnvironmentObject var s:Studio
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("MIDI PERFORMANCE").font(.headline)
            HStack {
                Toggle("Note repeater",isOn:$s.repeaterEnabled)
                Picker("Matrix axes",selection:$s.midiMatrixMode){ForEach(MIDIMatrixMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
            }.font(.caption)
            HStack {
                Stepper("Root MIDI \(s.midiRoot)",value:$s.midiRoot,in:0...127)
                Picker("Repeat",selection:$s.repeatBeats){Text("1/4").tag(1.0);Text("1/8").tag(0.5);Text("1/16").tag(0.25);Text("1/32").tag(0.125);Text("1/64").tag(0.0625)}
            }.font(.caption)
            XYMatrix(title:"MIDI • \(s.midiMatrixMode.rawValue)",x:s.midiX,y:s.midiY,snap:$s.midiSnap,stepsX:s.midiMatrixMode == .pitchVelocity ? 24:6,stepsY:s.midiMatrixMode == .timingPitch ? 24:8,onBegin:{},onPoint:{x,y in s.updateMIDIMatrix(x:x,y:y)},onEnd:{s.noteOff(-1)})
            Text("Generates MIDI notes for the selected instrument track. Arm it and record to capture notes. Repeater also applies to held piano keys and pads. \(s.midiPitchOffset) semitones • velocity \(s.midiVelocity)").font(.caption)
        }.disabled(s.selectedIndex.map{s.session.tracks[$0].isAudio} ?? true)
    }
}
@MainActor struct FXControls:View {
    @EnvironmentObject var s:Studio
    private var state:FXState{s.selectedIndex.flatMap{s.session.tracks[$0].xyFX} ?? FXState()}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("AUDIO XY EFFECTS").font(.headline)
            Toggle("Enable on selected track",isOn:Binding(get:{state.enabled},set:{var fx=state;fx.enabled=$0;s.setFX(fx,rebuild:true)})).disabled(s.recording || s.busy)
            Picker("Effect",selection:Binding(get:{state.mode},set:{var fx=state;fx.mode=$0;s.setFX(fx,rebuild:true)})) {
                ForEach(XYEffect.allCases,id:\.self){Text($0.rawValue).tag($0)}
            }.pickerStyle(.menu).disabled(s.recording || s.busy)
            XYMatrix(title:"AUDIO • \(state.mode.rawValue)",x:state.x,y:state.y,snap:Binding(get:{state.snap},set:{var fx=state;fx.snap=$0;s.setFX(fx,rebuild:false);s.save()}),stepsX:state.mode == .pitch ? 24:6,onBegin:{s.checkpoint()},onPoint:{x,y in var fx=state;fx.x=x;fx.y=y;s.setFX(fx,rebuild:false)},onEnd:{s.save()})
                .disabled(!state.enabled || s.busy)
            Text(state.mode == .pitch ? "X: −12…+12 semitones • Y: fine pitch when Snap is off." : state.mode == .filter ? "X: cutoff frequency • Y: wet mix." : "X: tempo-synced division (bar to 1/64 note) • Y: wet mix. Repeater captures a slice before repeating it.").font(.caption)
            Text("FX are applied to selected-track playback, not printed into raw microphone recordings. XY positions save with the project; gesture automation is not recorded.").font(.caption).foregroundColor(.secondary)
        }
    }
}
@MainActor struct XYMatrix:View {
    let title:String
    let x:Double
    let y:Double
    @Binding var snap:Bool
    var stepsX:Int=8
    var stepsY:Int=8
    var matrixHeight:Double=180
    let onBegin:()->Void
    let onPoint:(Double,Double)->Void
    let onEnd:()->Void
    @State private var down=false
    var body:some View {
        VStack(spacing:6) {
            HStack {
                Text(title).font(.caption.bold());Spacer()
                Button{snap.toggle()}label:{HStack(spacing:4){Image(systemName:snap ? "checkmark.square":"square");Text("Snap")}}
                    .font(.caption).accessibilityLabel("Snap matrix to grid").accessibilityValue(snap ? "On":"Off")
            }
            GeometryReader{geo in
                ZStack {
                    Color(white:0.08)
                    Canvas{context,size in
                        for i in 0...stepsX {
                            var p=Path();p.move(to:CGPoint(x:size.width*CGFloat(i)/CGFloat(stepsX),y:0));p.addLine(to:CGPoint(x:size.width*CGFloat(i)/CGFloat(stepsX),y:size.height));context.stroke(p,with:.color(.cyan.opacity(0.18)),lineWidth:1)
                        }
                        for j in 0...stepsY {
                            var p=Path();p.move(to:CGPoint(x:0,y:size.height*CGFloat(j)/CGFloat(stepsY)));p.addLine(to:CGPoint(x:size.width,y:size.height*CGFloat(j)/CGFloat(stepsY)));context.stroke(p,with:.color(.cyan.opacity(0.18)),lineWidth:1)
                        }
                    }
                    Circle().fill(Color.cyan).frame(width:16,height:16).position(x:geo.size.width*x,y:geo.size.height*(1-y))
                }.cornerRadius(8).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in
                    if !down{down=true;onBegin()}
                    var a=min(1,max(0,Double(v.location.x/geo.size.width))),b=min(1,max(0,1-Double(v.location.y/geo.size.height)))
                    if snap{a=(a*Double(stepsX)).rounded()/Double(stepsX);b=(b*Double(stepsY)).rounded()/Double(stepsY)}
                    onPoint(a,b)
                }.onEnded{_ in down=false;onEnd()})
            }.frame(height:matrixHeight)
        }.onDisappear{if down{down=false;onEnd()}}
    }
}
@MainActor struct SimpleSamplerEditor:View {
    @EnvironmentObject var s:Studio
    @State private var pad = -1
    @State private var draft:SampleSlot?
    @State private var gestureBase:SampleSlot?
    @State private var importing=false
    @State private var sliceCount=8
    @State private var transientChop=false
    @State private var slices:[SampleSlot]=[]
    @StateObject private var waves=Waveforms()
    private var source:SampleSlot? {
        guard let i=s.selectedIndex,let sampler=s.session.tracks[i].sampler else{return nil}
        return pad<0 ? sampler.keyboard:sampler.slot(pad)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("SIMPLE SAMPLER").font(.headline)
            SamplerBankBar()
            Picker("Sample slot",selection:$pad){Text("Keyboard").tag(-1);ForEach(0..<8){Text("Pad \($0+1)").tag($0)}}.pickerStyle(.menu)
            HStack {
                Button("Import Sample…"){importing=true}
                if let slot=draft {
                    Button("Apply Crop / Fades"){s.saveSample(slot,pad:pad<0 ? nil:pad)}
                    Button("Play Applied"){if let id=s.selected{s.audio.send(track:id,note:pad<0 ? slot.root:SamplerState.note(pad,bank:s.samplerBank),velocity:100)}}
                    Button("Stop"){if let id=s.selected{s.audio.runtimes[id]?.silence()}}
                }
            }.font(.caption).disabled(s.busy || s.recording)
            if let slot=draft {
                Text(slot.name).font(.caption.bold())
                sampleWave(slot)
                SampleStretchControls(slot:Binding(get:{draft ?? slot},set:{draft=$0;slices=[]}),tempo:s.session.tempo)
                HStack {
                    Stepper("Slices: \(sliceCount)",value:$sliceCount,in:1...8)
                    Toggle("Transients",isOn:$transientChop)
                    Button("Preview Chop"){
                        let data=waves.data[slot.asset]
                        slices=SliceMath.slices(slot,count:sliceCount,peaks:data?.peaks ?? [],duration:data?.duration ?? slot.end,transients:transientChop)
                    }.disabled(waves.data[slot.asset]==nil)
                    Button("Populate Bank \(SamplerState.bankNames[s.samplerBank])"){s.populateSlices(slices);slices=[]}.disabled(slices.isEmpty || s.busy || s.recording)
                }.font(.caption)
                if !slices.isEmpty {Text(slices.map{String(format:"%.3f–%.3f",$0.start,$0.end)}.joined(separator:" | ")).font(.caption2)}
                HStack {
                    Text("\(slot.start,specifier:"%.3f")–\(slot.end,specifier:"%.3f") s").font(.caption)
                    Button("Curve: \(slot.curve.rawValue)"){draft?.curve=slot.curve.next}
                    Button("Full File"){if let duration=waves.data[slot.asset]?.duration{draft?.start=0;draft?.end=duration}}
                }.font(.caption)
                HStack {
                    Stepper("Root \(slot.root)",value:Binding(get:{draft?.root ?? 60},set:{draft?.root=$0}),in:0...127)
                    Toggle("Loop",isOn:Binding(get:{draft?.loop ?? false},set:{draft?.loop=$0;if $0{draft?.oneShot=false}}))
                    Toggle("One-shot",isOn:Binding(get:{draft?.oneShot ?? false},set:{draft?.oneShot=$0;if $0{draft?.loop=false}}))
                }.font(.caption)
            }else{Text("Import a sample for this slot. Existing audio files stay intact when you crop or fade.").font(.caption)}
        }
        .sheet(isPresented:$importing){ImportPicker(types:[.audio],asCopy:false){url in importing=false;Task{await s.importSample(url,pad:pad<0 ? nil:pad);draft=source}}}
        .onAppear{draft=source}
        .onChange(of:pad){_ in draft=source;gestureBase=nil;slices=[]}
        .onChange(of:s.samplerBank){_ in draft=source;gestureBase=nil;slices=[]}
        .onChange(of:sliceCount){_ in slices=[]}
        .onChange(of:transientChop){_ in slices=[]}
        .onChange(of:source){value in draft=value}
        .task(id:draft?.asset){if let slot=draft{await waves.load(slot.asset,root:s.root)}}
    }
    private func sampleWave(_ slot:SampleSlot)->some View {
        GeometryReader{geo in
            Canvas{context,size in
                guard let data=waves.data[slot.asset],data.duration>0,!data.peaks.isEmpty else{return}
                var path=Path()
                for x in stride(from:0.0,to:Double(size.width),by:2) {
                    let time=slot.start+x/Double(size.width)*(slot.end-slot.start)
                    let index=min(data.peaks.count-1,max(0,Int(time/data.duration*Double(data.peaks.count))))
                    let h=Double(data.peaks[index])*Double(size.height)*0.48
                    path.move(to:CGPoint(x:x,y:Double(size.height)/2-h));path.addLine(to:CGPoint(x:x,y:Double(size.height)/2+h))
                };context.stroke(path,with:.color(.cyan),lineWidth:1)
                for slice in slices.dropFirst(){
                    let x=(slice.start-slot.start)/(slot.end-slot.start)*Double(size.width)
                    var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height));context.stroke(line,with:.color(.yellow),lineWidth:2)
                }
            }.background(Color(white:0.08))
                .overlay(FadeDrawing(fadeIn:slot.fadeIn,fadeOut:slot.fadeOut,duration:slot.end-slot.start,curve:slot.curve))
                .overlay(WaveformHandles(fadeInWidth:slot.fadeIn/(slot.end-slot.start)*Double(geo.size.width),fadeOutWidth:slot.fadeOut/(slot.end-slot.start)*Double(geo.size.width),edit:{mode,delta,finished,cancelled in
                    if gestureBase==nil{gestureBase=slot}
                    guard let base=gestureBase else{return}
                    if cancelled{draft=base;gestureBase=nil;return}
                    var value=base;let seconds=delta/Double(geo.size.width)*(base.end-base.start)
                    switch mode {
                    case .trimLeft:value.start=max(0,min(base.end-0.002,base.start+seconds))
                    case .trimRight:value.end=min(waves.data[slot.asset]?.duration ?? base.end,max(base.start+0.002,base.end+seconds))
                    case .fadeIn:value.fadeIn=max(0,min((base.end-base.start)/2,base.fadeIn+seconds))
                    case .fadeOut:value.fadeOut=max(0,min((base.end-base.start)/2,base.fadeOut-seconds))
                    }
                    value.fadeIn=min(value.fadeIn,(value.end-value.start)/2);value.fadeOut=min(value.fadeOut,(value.end-value.start)/2)
                    slices=[];draft=value;if finished{gestureBase=nil}
                },curve:{draft?.curve=slot.curve.next}))
        }.frame(height:145).disabled(s.busy || s.recording)
    }
}

extension View {
    @ViewBuilder func pocketNavigationStyle()->some View {
        #if os(macOS)
        self
        #else
        self.navigationViewStyle(.stack)
        #endif
    }
}
