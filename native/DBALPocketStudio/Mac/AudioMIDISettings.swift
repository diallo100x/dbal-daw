import SwiftUI
import AppKit
import CoreMIDI
import CoreAudioKit

@MainActor struct MacAudioMIDISettings:View {
    @EnvironmentObject var s:Studio
    @ObservedObject var midi:MacMIDIReceiver
    @Environment(\.presentationMode) private var presentation
    @State private var networkEnabled=MIDINetworkSession.default().isEnabled
    @State private var policy=MIDINetworkSession.default().connectionPolicy.rawValue
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            HStack{Text("Audio & MIDI Settings").font(.title2);Spacer();Button("Done"){presentation.wrappedValue.dismiss()}}
            GroupBox("Audio input monitoring"){
                VStack(alignment:.leading,spacing:10){
                    if let id=s.selected,let track=s.session.tracks.first(where:{$0.id==id}),track.isAudio {
                        Toggle("Monitor input through \(track.name)",isOn:Binding(get:{s.monitoredTrack==id},set:{on in Task{await s.setInputMonitoring(on ? id:nil)}})).disabled(s.recording || s.busy)
                    }else{Text("Select an audio track to enable input monitoring.")}
                    if let id=s.monitoredTrack,let track=s.session.tracks.first(where:{$0.id==id}) {
                        Text("Monitoring: \(track.name)")
                        HStack{Text("Monitor level");Slider(value:Binding(get:{Double(s.monitorGain)},set:{s.setMonitorGain(Float($0))}),in:0...1);Button("Turn monitoring off"){Task{await s.setInputMonitoring(nil)}}.disabled(s.recording || s.busy)}
                    }
                    Text("Uses the system audio input and the monitored track's volume, mute/solo and effects. Monitoring stays on when you select another track. Use headphones to avoid feedback.").font(.caption).foregroundColor(.secondary)
                    Button("Audio / MIDI Setup…"){openAudioMIDISetup()}
                }.padding(6).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("MIDI connections"){
                VStack(alignment:.leading,spacing:10){
                    Toggle("Receive MIDI on the selected instrument track",isOn:Binding(get:{midi.enabled},set:{if $0{midi.start()}else{midi.close()}}))
                    HStack{Button("Bluetooth MIDI…"){midi.showBluetooth()};Button("Refresh sources"){if midi.enabled{midi.refreshSources()}else{midi.start()}}}
                    Text(midi.status).font(.caption)
                    ForEach(midi.sources){source in Label(source.name,systemImage:"pianokeys")}
                    if midi.sources.isEmpty{Text("No MIDI sources connected. Pair a Bluetooth controller or configure a network session, then enable MIDI input.").font(.caption).foregroundColor(.secondary)}
                }.padding(6).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("Network MIDI"){
                VStack(alignment:.leading,spacing:10){
                    Toggle("Enable system Network MIDI session",isOn:$networkEnabled).onChange(of:networkEnabled){value in MIDINetworkSession.default().isEnabled=value;if midi.enabled{midi.refreshSources()}}
                    Picker("Incoming connections",selection:$policy){Text("No one").tag(MIDINetworkConnectionPolicy.noOne.rawValue);Text("Contacts only").tag(MIDINetworkConnectionPolicy.hostsInContactList.rawValue);Text("Anyone on the network").tag(MIDINetworkConnectionPolicy.anyone.rawValue)}.onChange(of:policy){value in if let value=MIDINetworkConnectionPolicy(rawValue:value){MIDINetworkSession.default().connectionPolicy=value}}
                    Button("Open Network MIDI setup…"){openAudioMIDISetup()}
                    Text("In Audio MIDI Setup choose Window → Show MIDI Studio, then open Network to add peers. These settings control macOS's shared MIDI session. MIDI carries notes and controls, not audio.").font(.caption).foregroundColor(.secondary)
                }.padding(6).frame(maxWidth:.infinity,alignment:.leading)
            }
        }.padding(20).frame(width:650).onAppear{networkEnabled=MIDINetworkSession.default().isEnabled;policy=MIDINetworkSession.default().connectionPolicy.rawValue}
    }
    private func openAudioMIDISetup(){
        let url=URL(fileURLWithPath:"/System/Applications/Utilities/Audio MIDI Setup.app")
        if !NSWorkspace.shared.open(url){s.error="Open Audio MIDI Setup from Applications → Utilities."}
    }
}
