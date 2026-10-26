import Foundation
import Combine
import CoreMIDI

@MainActor final class MacMIDIReceiver:ObservableObject {
    @Published var enabled=false
    @Published var status="MIDI remote input off"
    var receive:((MIDIMessage)->Void)?
    var release:(()->Void)?
    private var client:MIDIClientRef=0
    private var port:MIDIPortRef=0
    private var decoders:[MIDIEndpointRef:MIDIMessageDecoder]=[:]
    private var generation=0
    func start(){
        close()
        var result=MIDIClientCreate("DBAL Native Input" as CFString,nil,nil,&client)
        if result==noErr {
            let token=generation
            result=MIDIInputPortCreateWithBlock(client,"Remote Input" as CFString,&port){[weak self] list,connection in
                var bytes:[UInt8]=[]
                let offset=MemoryLayout<MIDIPacketList>.offset(of:\.packet)!
                var packet=UnsafeRawPointer(list).advanced(by:offset).assumingMemoryBound(to:MIDIPacket.self)
                for _ in 0..<list.pointee.numPackets {
                    let length=Int(packet.pointee.length)
                    let data=UnsafeRawPointer(packet).advanced(by:MemoryLayout<MIDIPacket>.offset(of:\.data)!).assumingMemoryBound(to:UInt8.self)
                    bytes.append(contentsOf:UnsafeBufferPointer(start:data,count:length))
                    packet=UnsafePointer(MIDIPacketNext(packet))
                }
                let copied=bytes,source=connection.map{MIDIEndpointRef(UInt(bitPattern:$0))} ?? 0
                Task{@MainActor in
                    guard let self=self,self.enabled,self.generation==token else{return}
                    var decoder=self.decoders[source] ?? MIDIMessageDecoder()
                    let messages=decoder.decode(copied);self.decoders[source]=decoder
                    for message in messages{self.receive?(message)}
                }
            }
        }
        guard result==noErr else{status="MIDI input failed: \(result)";return}
        var connected=0
        for index in 0..<MIDIGetNumberOfSources(){let source=MIDIGetSource(index);if MIDIPortConnectSource(port,source,UnsafeMutableRawPointer(bitPattern:UInt(source)))==noErr{connected+=1}}
        enabled=true;status="Listening to \(connected) MIDI sources. Refresh after connecting a device."
    }
    func close(){generation+=1;release?();enabled=false;if client != 0{MIDIClientDispose(client);client=0;port=0};decoders=[:]}
    deinit{if client != 0{MIDIClientDispose(client)}}
}
