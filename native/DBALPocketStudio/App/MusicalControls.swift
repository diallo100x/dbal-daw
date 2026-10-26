import SwiftUI

@MainActor struct PianoKeys: View {
    @EnvironmentObject var s:Studio
    let white=[0,2,4,5,7,9,11,12,14,16,17,19,21,23]
    let black:[(Int,Double)]=[(1,1),(3,2),(6,4),(8,5),(10,6),(13,8),(15,9),(18,11),(20,12),(22,13)]
    var body: some View {
        HStack(spacing:4) {
            VStack { Button("− Oct") {s.octave=max(0,s.octave-1)};Text("C\(s.octave)").font(.caption);Button("+ Oct") {s.octave=min(7,s.octave+1)} }.font(.caption).frame(width:60)
            GeometryReader { geo in
                let w=geo.size.width/14
                ZStack(alignment:.topLeading) {
                    HStack(spacing:1) { ForEach(white,id:\.self) { n in key(n,color:.white,width:w-1,height:geo.size.height) } }
                    ForEach(black,id:\.0) { n,pos in key(n,color:.black,width:w*0.62,height:geo.size.height*0.62).offset(x:w*pos-w*0.31) }
                }
            }
        }.padding(.horizontal,8)
    }
    private func key(_ n:Int,color:Color,width:Double,height:Double)->some View {
        RoundedRectangle(cornerRadius:3).fill(color).frame(width:width,height:height)
            .gesture(DragGesture(minimumDistance:0).onChanged{_ in s.noteOn((s.octave+1)*12+n)}.onEnded{_ in s.noteOff((s.octave+1)*12+n)})
    }
}
@MainActor struct DrumPads:View {
    @EnvironmentObject var s:Studio
    let notes=[36,38,42,46,41,45,49,51]
    private func padNote(_ i:Int)->Int{s.selectedIndex.map{s.session.tracks[$0].instrument == .padSampler ? SamplerState.note(i,bank:s.samplerBank):notes[i]} ?? notes[i]}
    let names=["KICK","SNARE","CLOSED HH","OPEN HH","LOW TOM","HIGH TOM","CRASH","RIDE"]
    var body:some View {
        VStack(spacing:2) {
        SamplerBankBar()
        LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:5) {
            ForEach(0..<8) { i in RoundedRectangle(cornerRadius:6).fill(Color.orange.opacity(0.7)).overlay(Text(s.selectedIndex.flatMap{s.session.tracks[$0].instrument == .padSampler ? s.session.tracks[$0].sampler?.slot(i)?.name:nil} ?? (s.samplerBank==0 && (s.selectedIndex.flatMap{s.session.tracks[$0].sampler?.useStarterPads} ?? true) ? names[i]:"Empty \(i+1)")).font(.caption.bold()).lineLimit(2)).frame(height:60)
                .gesture(DragGesture(minimumDistance:0).onChanged{_ in s.noteOn(padNote(i))}.onEnded{_ in s.noteOff(padNote(i))}) }
        }.padding(8)
        }
    }
}
