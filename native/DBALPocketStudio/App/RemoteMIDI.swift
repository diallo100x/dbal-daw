import Foundation
import Combine
import CoreMIDI

struct MIDITarget:Identifiable {let id:MIDIEndpointRef;let name:String}
// MIDI 1.0 packets retain the iPadOS 15.4 baseline. No audio is sent over this connection.
@MainActor final class RemoteMIDI:ObservableObject {
    @Published var targets:[MIDITarget]=[]
    @Published var target:MIDIEndpointRef=0 {willSet{if newValue != target{releaseNotes()}}}
    @Published var channel=1
    @Published var status="Choose a destination, or use the virtual output in another app."
    private var client:MIDIClientRef=0
    private var port:MIDIPortRef=0
    private var source:MIDIEndpointRef=0
    private var held=Set<Int>()
    private var networkOwned=false
    private var previousPolicy:MIDINetworkConnectionPolicy?
    init(){
        var result=MIDIClientCreate("DBAL Pocket Remote" as CFString,nil,nil,&client)
        if result==noErr{result=MIDIOutputPortCreate(client,"Remote Output" as CFString,&port)}
        if result==noErr{result=MIDISourceCreate(client,"DBAL Pocket Remote" as CFString,&source)}
        if result != noErr{status="MIDI setup failed: \(result)"}
        refresh()
    }
    deinit{if client != 0{MIDIClientDispose(client)}}
    func refresh(){
        targets=(0..<MIDIGetNumberOfDestinations()).map{index in
            let endpoint=MIDIGetDestination(index);var name:Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint,kMIDIPropertyDisplayName,&name)
            return MIDITarget(id:endpoint,name:name?.takeRetainedValue() as String? ?? "MIDI Destination")
        }
    }
    func network(){
        let session=MIDINetworkSession.default()
        if !session.isEnabled{networkOwned=true;session.isEnabled=true}
        if previousPolicy==nil{previousPolicy=session.connectionPolicy}
        session.connectionPolicy = .anyone
        refresh();target=session.destinationEndpoint()
        status="Network MIDI enabled. Connect this iPad from the Mac's MIDI Network Setup."
    }
    func note(_ note:Int,on:Bool){
        let n=max(0,min(127,note)),key=(channel-1)*128+n
        if on{guard held.insert(key).inserted else{return}}
        else{guard held.remove(key) != nil else{return}}
        send(status:UInt8((on ? 0x90:0x80)+(channel-1)),data:[UInt8(n),on ? 100:0])
    }
    func cc(_ number:Int,value:Double,channel:Int){send(status:UInt8(0xB0+max(0,min(15,channel-1))),data:[UInt8(clamping:number),UInt8(max(0,min(127,Int(value.rounded()))))])}
    func releaseNotes(){
        for key in held{send(status:UInt8(0x80+key/128),data:[UInt8(key%128),0])};held=[]
    }
    func panic(){
        releaseNotes()
        for ch in 1...16{cc(120,value:0,channel:ch);cc(123,value:0,channel:ch)}
    }
    func close(){
        releaseNotes()
        if let previous=previousPolicy{MIDINetworkSession.default().connectionPolicy=previous;previousPolicy=nil}
        if networkOwned{MIDINetworkSession.default().isEnabled=false;networkOwned=false}
    }
    func send(status:UInt8,data:[UInt8]=[]){
        guard port != 0,source != 0 else{return}
        let bytes=[status]+data
        var list=MIDIPacketList()
        let result:OSStatus=withUnsafeMutablePointer(to:&list){pointer in
            let packet=MIDIPacketListInit(pointer)
            let added=bytes.withUnsafeBufferPointer{MIDIPacketListAdd(pointer,MemoryLayout<MIDIPacketList>.size,packet,0,$0.count,$0.baseAddress!)}
            guard added != nil else{return OSStatus(-50)}
            return target==0 ? MIDIReceived(source,pointer):MIDISend(port,target,pointer)
        }
        if result != noErr{self.status="MIDI send failed: \(result). Refresh destinations and reconnect."}
    }
}
