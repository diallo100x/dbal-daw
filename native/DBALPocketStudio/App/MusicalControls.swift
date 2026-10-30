import SwiftUI

@MainActor struct PianoKeys: View {
    @EnvironmentObject var s:Studio
    @AppStorage("performanceLayoutLocked") private var locked=true
    @AppStorage("performanceKeyWidth") private var storedWidth=46.0
    @AppStorage("performanceFirstWhite") private var firstWhite=35.0
    @State private var panStart:Double?
    @State private var resizeStart:Double?
    @State private var pinchStart:Double?
    private var keyWidth:Double{PerformanceLayout.keyWidth(storedWidth)}
    private let blackPositions=[1:1,3:2,6:4,8:5,10:6]
    var body: some View {
        GeometryReader { geo in
            let viewport=Double(geo.size.width)
            let start=PerformanceLayout.firstWhite(firstWhite,width:keyWidth,viewport:viewport)
            VStack(spacing:4) {
                HStack {
                    Button("− Oct"){shift(-7,viewport:viewport)}.disabled(locked)
                    Button("+ Oct"){shift(7,viewport:viewport)}.disabled(locked)
                    Button("Fit 2 octaves"){
                        s.releasePerformanceTouches()
                        storedWidth=PerformanceLayout.keyWidth(viewport/14)
                        firstWhite=PerformanceLayout.firstWhite(firstWhite,width:keyWidth,viewport:viewport)
                    }.disabled(locked)
                    Spacer()
                    if !locked {
                        Text("↔ Resize keys").font(.caption.bold()).padding(5).background(Color.cyan.opacity(0.15)).cornerRadius(4)
                            .gesture(DragGesture(minimumDistance:1).onChanged{v in
                                if resizeStart==nil{resizeStart=keyWidth}
                                storedWidth=PerformanceLayout.keyWidth((resizeStart ?? keyWidth)+Double(v.translation.width)/3)
                                firstWhite=PerformanceLayout.firstWhite(firstWhite,width:keyWidth,viewport:viewport)
                            }.onEnded{_ in resizeStart=nil})
                    }
                }.font(.caption)
                GeometryReader { keys in
                    ZStack(alignment:.topLeading) {
                        ForEach(Array(PerformanceLayout.whiteNotes.enumerated()),id:\.element) { index,note in
                            PerformanceTouch(note:note,color:.white,label:note%12==0 ? "C\(note/12-1)":"")
                                .frame(width:keyWidth-1,height:keys.size.height)
                                .offset(x:(Double(index)-start)*keyWidth)
                        }
                        ForEach((0...127).filter{blackPositions[$0%12] != nil},id:\.self) { note in
                            let position=Double(note/12*7+(blackPositions[note%12] ?? 0))
                            PerformanceTouch(note:note,color:.black,label:"")
                                .frame(width:keyWidth*0.62,height:keys.size.height*0.62)
                                .offset(x:(position-start)*keyWidth-keyWidth*0.31)
                        }
                    }.frame(width:keys.size.width,height:keys.size.height,alignment:.topLeading).allowsHitTesting(locked)
                    if !locked {
                        Color.cyan.opacity(0.04).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance:1).onChanged{v in
                                if panStart==nil{panStart=firstWhite}
                                firstWhite=PerformanceLayout.firstWhite((panStart ?? firstWhite)-Double(v.translation.width)/keyWidth,width:keyWidth,viewport:viewport)
                            }.onEnded{_ in panStart=nil})
                            .simultaneousGesture(MagnificationGesture().onChanged{value in
                                if pinchStart==nil{pinchStart=keyWidth}
                                storedWidth=PerformanceLayout.keyWidth((pinchStart ?? keyWidth)*Double(value))
                                firstWhite=PerformanceLayout.firstWhite(firstWhite,width:keyWidth,viewport:viewport)
                            }.onEnded{_ in pinchStart=nil})
                    }
                }.clipped()
                if !locked{Text("Layout editing: drag to move the keyboard range; pinch or drag Resize keys to change key width. Lock to play.").font(.caption2)}
            }
        }.padding(.horizontal,8)
    }
    private func shift(_ whites:Double,viewport:Double){
        s.releasePerformanceTouches()
        firstWhite=PerformanceLayout.firstWhite(firstWhite+whites,width:keyWidth,viewport:viewport)
    }
}

@MainActor struct PerformanceTouch:View {
    @EnvironmentObject var s:Studio
    let note:Int
    let color:Color
    let label:String
    @State private var down=false
    var body:some View {
        RoundedRectangle(cornerRadius:4).fill(down ? Color.cyan:color)
            .overlay(alignment:.bottom){Text(label).font(.caption2.bold()).foregroundColor(color == .white ? .black:.white).padding(4)}
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged{_ in
                if !down{down=true;s.noteOn(note)}
            }.onEnded{_ in release()})
            .onDisappear{release()}
            .accessibilityLabel(label.isEmpty ? "MIDI note \(note)":label)
    }
    private func release(){if down{down=false;s.noteOff(note)}}
}

@MainActor struct DrumPads:View {
    @EnvironmentObject var s:Studio
    let notes=[36,38,42,46,41,45,49,51]
    let names=["KICK","SNARE","CLOSED HH","OPEN HH","LOW TOM","HIGH TOM","CRASH","RIDE"]
    private func padNote(_ i:Int)->Int{s.selectedIndex.map{s.session.tracks[$0].instrument == .padSampler ? SamplerState.note(i,bank:s.samplerBank):notes[i]} ?? notes[i]}
    private func label(_ i:Int)->String {
        s.selectedIndex.flatMap{s.session.tracks[$0].instrument == .padSampler ? s.session.tracks[$0].sampler?.slot(i)?.name:nil} ??
            (s.samplerBank==0 && (s.selectedIndex.flatMap{s.session.tracks[$0].sampler?.useStarterPads} ?? true) ? names[i]:"Empty \(i+1)")
    }
    var body:some View {
        GeometryReader { geo in
            VStack(spacing:2) {
                SamplerBankBar()
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:5) {
                    ForEach(0..<8) { i in
                        PerformanceTouch(note:padNote(i),color:Color.orange.opacity(0.7),label:label(i))
                            .id(padNote(i))
                            .frame(height:max(24,(geo.size.height-58)/2))
                    }
                }.padding(8)
            }
        }
    }
}
