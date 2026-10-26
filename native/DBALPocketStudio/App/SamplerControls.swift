import SwiftUI

@MainActor struct SamplerBankBar:View {
    @EnvironmentObject var s:Studio
    var body:some View {
        HStack {
            Button{ s.switchSamplerBank(s.samplerBank-1) }label:{Image(systemName:"chevron.left")}.disabled(s.samplerBank==0)
            Text("BANK \(SamplerState.bankNames[s.samplerBank]) • 8 PADS").font(.caption.bold())
            Button{ s.switchSamplerBank(s.samplerBank+1) }label:{Image(systemName:"chevron.right")}.disabled(s.samplerBank==5)
            Spacer()
        }.disabled(s.recording || s.busy)
    }
}

struct SampleStretchControls:View {
    @Binding var slot:SampleSlot
    var tempo:Double
    @State private var beats=4
    var body:some View {
        VStack(alignment:.leading,spacing:5){
            HStack {
                Text("Stretch \(Int((slot.stretch ?? 1)*100))%")
                Slider(value:Binding(get:{slot.stretch ?? 1},set:{slot.stretch=$0}),in:0.25...4,step:0.01)
                Stepper("Pitch \(slot.pitch ?? 0,specifier:"%.0f") st",value:Binding(get:{slot.pitch ?? 0},set:{slot.pitch=$0}),in:-24...24,step:1)
            }
            HStack {
                Stepper("Fit \(beats) beats",value:$beats,in:1...64)
                Button("Fit to BPM") {slot.stretch=max(0.25,min(4,Double(beats)*60/tempo/(slot.end-slot.start)))}
                Text("Length \((slot.end-slot.start)*(slot.stretch ?? 1),specifier:"%.2f") s")
                Button("Reset"){slot.stretch=nil;slot.pitch=nil}
            }
            Text("Apply to prepare independent stretch/pitch. Fit is limited to 25–400%. Keyboard transposition still changes playback speed.").foregroundColor(.secondary)
        }.font(.caption)
    }
}
