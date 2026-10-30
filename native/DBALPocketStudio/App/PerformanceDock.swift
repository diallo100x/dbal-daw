import SwiftUI

@MainActor struct PerformanceDock:View {
    @EnvironmentObject var s:Studio
    @AppStorage("performanceDockHeight") private var savedHeight=280.0
    @AppStorage("performanceLayoutLocked") private var locked=true
    @State private var resizeStart:Double?
    var maximumHeight:Double=460
    private var height:Double{PerformanceLayout.height(savedHeight,maximum:maximumHeight)}
    private var instrumentSelected:Bool{s.selectedIndex.map{!s.session.tracks[$0].isAudio} ?? false}
    var body:some View {
        VStack(spacing:4) {
            HStack {
                Spacer()
                Capsule().fill(Color.gray).frame(width:65,height:5)
                Text("Drag up to enlarge pads / keyboard").font(.caption2)
                Spacer()
            }.frame(height:22).frame(maxWidth:.infinity).background(Color.white.opacity(0.06)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:2).onChanged{v in
                    if resizeStart==nil{s.releasePerformanceTouches();resizeStart=height}
                    savedHeight=PerformanceLayout.height((resizeStart ?? height)-Double(v.translation.height),maximum:maximumHeight)
                }.onEnded{_ in resizeStart=nil})
                .accessibilityLabel("Resize pads and keyboard panel")
                .accessibilityAdjustableAction{direction in
                    switch direction {
                    case .increment:savedHeight=PerformanceLayout.height(height+30,maximum:maximumHeight)
                    case .decrement:savedHeight=PerformanceLayout.height(height-30,maximum:maximumHeight)
                    @unknown default:break
                    }
                }
            HStack(alignment:.top,spacing:12) {
                VStack(spacing:6) {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack {
                            Button("Undo"){s.undo()}.disabled(!s.canUndo || s.recording || s.busy)
                            Button("Redo"){s.redo()}.disabled(!s.canRedo || s.recording || s.busy)
                            Button(s.showPads ? "Show Keyboard":"Show Pads"){s.releasePerformanceTouches();s.showPads.toggle()}
                            Toggle(isOn:$locked){Label(locked ? "Locked":"Unlocked",systemImage:locked ? "lock.fill":"lock.open")}.fixedSize()
                        }.font(.caption)
                    }
                    if s.showPads{DrumPads()}else{PianoKeys()}
                }
                CompactRepeaterMatrix().frame(width:210)
            }.padding(.horizontal,8)
        }.padding(.bottom,6).frame(height:height).background(Color(white:0.1))
            .onChange(of:locked){_ in s.releasePerformanceTouches()}
            .onChange(of:s.repeaterEnabled){_ in s.releasePerformanceTouches()}
            .onChange(of:s.midiMatrixMode){mode in
                s.releasePerformanceTouches();s.midiY=mode == .timingPitch ? 0.5:0.75
            }
            .onChange(of:instrumentSelected){_ in s.releasePerformanceTouches()}
            .onDisappear{s.releasePerformanceTouches()}
    }
}

@MainActor struct CompactRepeaterMatrix:View {
    @EnvironmentObject var s:Studio
    private var instrumentSelected:Bool{s.selectedIndex.map{!s.session.tracks[$0].isAudio} ?? false}
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            Toggle("Note repeater",isOn:$s.repeaterEnabled).font(.caption.bold())
            Picker("Y axis",selection:$s.midiMatrixMode) {
                Text("Y: Velocity").tag(MIDIMatrixMode.timingVelocity)
                Text("Y: Pitch").tag(MIDIMatrixMode.timingPitch)
                if s.midiMatrixMode == .pitchVelocity{Text("Pitch / Velocity").tag(MIDIMatrixMode.pitchVelocity)}
            }.pickerStyle(.menu).font(.caption)
            XYMatrix(title:s.midiMatrixMode == .pitchVelocity ? "X: Pitch • Y: Velocity":"X: Timing • Y: \(s.midiMatrixMode == .timingPitch ? "Pitch":"Velocity")",
                x:s.midiX,y:s.midiY,snap:$s.midiSnap,
                stepsX:s.midiMatrixMode == .pitchVelocity ? 24:6,
                stepsY:s.midiMatrixMode == .timingPitch ? 24:8,matrixHeight:100,
                onBegin:{},onPoint:{x,y in s.updateMIDIMatrix(x:x,y:y,triggerRoot:false)},onEnd:{})
            Text("\(s.effectiveRepeatBeats,specifier:"%.3g") beats • \(s.midiPitchOffset) st • vel \(s.midiVelocity)").font(.caption2)
            Text("Hold a key or pad; move XY to shape repeats.").font(.caption2).foregroundColor(.secondary)
        }.disabled(!instrumentSelected || s.busy)
    }
}
