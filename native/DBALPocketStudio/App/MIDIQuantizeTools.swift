import SwiftUI

@MainActor struct MIDIQuantizeTools: View {
    @EnvironmentObject var s: Studio
    let trackID: UUID
    var selected: UUID? = nil
    @State private var mode = MIDIQuantizeMode.starts
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Picker("Quantize", selection: $mode) {
                    ForEach(MIDIQuantizeMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }.frame(width:200)
                Button("Quantize selected") { s.quantizeNotes(track:trackID,selected:selected,mode:mode) }.disabled(selected == nil)
                Button("Quantize track") { s.quantizeNotes(track:trackID,mode:mode) }
                Toggle("Input Quantize", isOn:$s.inputQuantize).fixedSize()
            }.disabled(s.recording || s.busy)
        }
        Text("Quantize uses the Grid division independently of Snap. Input Quantize snaps recorded starts, preserves played lengths, and does not delay live sound.").font(.caption)
    }
}
