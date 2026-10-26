import Foundation
import Combine
import CoreMIDI
import CoreAudioKit

struct MacMIDISource:Identifiable {let id:MIDIEndpointRef;let name:String}

@MainActor final class MacMIDIReceiver:ObservableObject {
    @Published var sources:[MacMIDISource]=[]
    private var connected=Set<MIDIEndpointRef>()
    private var bluetooth:CABTLEMIDIWindowController?
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
        var result=MIDIClientCreateWithBlock("DBAL Native Input" as CFString,&client){[weak self] _ in Task{@MainActor in self?.refreshSources()}}
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
        enabled=true;refreshSources()
    }
    func showBluetooth(){
        if bluetooth==nil{bluetooth=CABTLEMIDIWindowController()}
        bluetooth?.showWindow(nil)
    }
    func refreshSources(){
        guard port != 0,enabled else{return}
        let current=Set((0..<MIDIGetNumberOfSources()).map{MIDIGetSource($0)})
        let removed=connected.subtracting(current)
        if !removed.isEmpty{release?()}
        for source in removed{MIDIPortDisconnectSource(port,source);connected.remove(source);decoders.removeValue(forKey:source)}
        for source in current.subtracting(connected){if MIDIPortConnectSource(port,source,UnsafeMutableRawPointer(bitPattern:UInt(source)))==noErr{connected.insert(source)}}
        sources=connected.sorted().map{source in
            var name:Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source,kMIDIPropertyDisplayName,&name)
            return MacMIDISource(id:source,name:name?.takeRetainedValue() as String? ?? "MIDI source")
        }
        status="Listening to \(sources.count) MIDI sources. New connections attach automatically."
    }
    func close(){generation+=1;release?();enabled=false;if client != 0{MIDIClientDispose(client);client=0;port=0};decoders=[:];connected=[];sources=[];status="MIDI input off"}
    deinit{if client != 0{MIDIClientDispose(client)}}
}
