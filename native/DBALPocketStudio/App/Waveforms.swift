import SwiftUI
import AVFoundation

struct WaveformData {var duration:Double;var peaks:[Float]}
@MainActor final class Waveforms:ObservableObject {
    @Published var data:[String:WaveformData]=[:]
    private var loading=Set<String>()
    func load(_ asset:String,root:URL) async{
        guard data[asset]==nil,!loading.contains(asset) else{return};loading.insert(asset)
        let result=await Task.detached(priority:.utility){()->WaveformData? in
            guard let url=try? safeChild(root,asset),let file=try? AVAudioFile(forReading:url),file.length>0,
                  let pcm=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:8192) else{return nil}
            var peaks=[Float](repeating:0,count:1024),position:Int64=0
            do{
                while position<file.length{
                    try file.read(into:pcm,frameCount:AVAudioFrameCount(min(8192,file.length-position)))
                    guard pcm.frameLength>0,let channels=pcm.floatChannelData else{break}
                    for f in stride(from:0,to:Int(pcm.frameLength),by:8){
                        let index=min(1023,Int(Double(position+Int64(f))/Double(file.length)*1024))
                        for ch in 0..<Int(pcm.format.channelCount){peaks[index]=max(peaks[index],abs(channels[ch][f]))}
                    };position+=Int64(pcm.frameLength)
                }
                return WaveformData(duration:Double(file.length)/file.processingFormat.sampleRate,peaks:peaks)
            }catch{return nil}
        }.value
        if let result=result{data[asset]=result};loading.remove(asset)
    }
}
