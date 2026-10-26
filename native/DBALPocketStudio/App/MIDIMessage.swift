import Foundation
struct MIDIMessage:Equatable {var status:UInt8;var data1:UInt8=0;var data2:UInt8=0}
// Retains running status across packets; ignores SysEx/system-common messages.
struct MIDIMessageDecoder {
    private var status:UInt8=0
    private var data:[UInt8]=[]
    mutating func decode(_ bytes:[UInt8])->[MIDIMessage]{
        var result:[MIDIMessage]=[]
        for byte in bytes {
            if byte>=0xF8{result.append(MIDIMessage(status:byte));continue}
            if byte>=0x80{status=byte<0xF0 ? byte:0;data=[];continue}
            guard status>=0x80 else{continue}
            data.append(byte)
            let needed=(status&0xF0==0xC0 || status&0xF0==0xD0) ? 1:2
            if data.count==needed{result.append(MIDIMessage(status:status,data1:data[0],data2:needed==2 ? data[1]:0));data=[]}
        }
        return result
    }
}
