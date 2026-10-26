import SwiftUI
#if os(iOS)
import UIKit
import CoreAudioKit

@MainActor struct RemotePanel:View {
    @EnvironmentObject var s:Studio
    @Environment(\.presentationMode) var presentation
    @StateObject private var midi=RemoteMIDI()
    @State private var bluetooth=false
    @State private var octave=4
    @State private var faders=[Double](repeating:100,count:8)
    @State private var crossfade=64.0
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16){
                Group {
                HStack{Text("POCKET MIDI REMOTE").font(.headline);Spacer();Button("Return to Studio"){presentation.wrappedValue.dismiss()}}
                Text("MIDI controller mode • local audio engine paused").font(.caption)
                HStack{
                    Picker("Destination",selection:$midi.target){Text("Virtual output (local apps)").tag(UInt32(0));ForEach(midi.targets){Text($0.name).tag($0.id)}}
                    Button("Refresh"){midi.releaseNotes();midi.refresh()}
                    Button("Network MIDI"){midi.releaseNotes();midi.network()}
                    #if !targetEnvironment(macCatalyst)
                    Button("Bluetooth MIDI"){bluetooth=true}
                    #endif
                }
                Text(midi.status).font(.caption)
                }
                HStack {
                    Stepper("Keyboard channel \(midi.channel)",value:Binding(get:{midi.channel},set:{midi.releaseNotes();midi.channel=$0}),in:1...16)
                    Stepper("Octave \(octave)",value:Binding(get:{octave},set:{midi.releaseNotes();octave=$0}),in:0...7)
                    Button("Panic"){midi.panic()}
                    Button("Start"){midi.send(status:0xFA)};Button("Stop"){midi.send(status:0xFC);midi.panic()}
                }.font(.caption)
                keyboard.frame(height:155)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4)){
                    ForEach(0..<8){pad in RoundedRectangle(cornerRadius:8).fill(Color.orange).overlay(Text("Pad \(pad+1) • \(SamplerState.padNotes[pad])").foregroundColor(.black)).frame(height:65)
                        .gesture(DragGesture(minimumDistance:0).onChanged{_ in midi.note(SamplerState.padNotes[pad],on:true)}.onEnded{_ in midi.note(SamplerState.padNotes[pad],on:false)})}
                }
                Text("CHANNEL FADERS • CC 7 • channels 1–8").font(.caption.bold())
                HStack{ForEach(0..<8){i in VStack{
                    Text("\(i+1)").font(.caption)
                    Slider(value:Binding(get:{faders[i]},set:{faders[i]=$0;midi.cc(7,value:$0,channel:i+1)}),in:0...127,step:1)
                        .frame(width:145).rotationEffect(.degrees(-90)).frame(width:46,height:150)
                    Text("\(Int(faders[i]))").font(.caption2)
                }.frame(maxWidth:.infinity)}}
                HStack{Text("Crossfader • CC 16");Slider(value:$crossfade,in:0...127,step:1).onChange(of:crossfade){midi.cc(16,value:$0,channel:midi.channel)}}.font(.caption)
                Text("Connect the iPad in macOS Audio MIDI Setup (Bluetooth or Network), refresh destinations, and select the connected endpoint. Other DAWs need MIDI input/MIDI learn enabled. This sends notes, CC and Start/Stop, not audio or MIDI clock.").font(.caption).foregroundColor(.secondary)
            }.padding()
        }.onAppear{s.stop();s.save(capture:true);s.audio.destroyGraph()}
        .onDisappear{midi.close();Task{await s.rebuild()}}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.willResignActiveNotification)){_ in midi.releaseNotes()}
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented:$bluetooth){VStack{HStack{Spacer();Button("Done"){bluetooth=false}}.padding();BluetoothAdvertiser()}}
        #endif
    }
    private var keyboard:some View {
        GeometryReader{geo in
            let white=[0,2,4,5,7,9,11,12,14,16,17,19,21,23]
            let black:[(Int,Double)]=[(1,1),(3,2),(6,4),(8,5),(10,6),(13,8),(15,9),(18,11),(20,12),(22,13)]
            let width=geo.size.width/14
            ZStack(alignment:.topLeading){
                HStack(spacing:1){ForEach(white,id:\.self){key($0,color:.white).frame(width:width-1)}}
                ForEach(black,id:\.0){note,pos in key(note,color:.black).frame(width:width*0.62,height:geo.size.height*0.62).offset(x:width*pos-width*0.31)}
            }
        }
    }
    private func key(_ note:Int,color:Color)->some View {RoundedRectangle(cornerRadius:3).fill(color).gesture(DragGesture(minimumDistance:0).onChanged{_ in midi.note((octave+1)*12+note,on:true)}.onEnded{_ in midi.note((octave+1)*12+note,on:false)})}
}
#if !targetEnvironment(macCatalyst)
struct BluetoothAdvertiser:UIViewControllerRepresentable {
    func makeUIViewController(context:Context)->CABTMIDILocalPeripheralViewController{CABTMIDILocalPeripheralViewController()}
    func updateUIViewController(_ view:CABTMIDILocalPeripheralViewController,context:Context){}
}
#endif
#endif
