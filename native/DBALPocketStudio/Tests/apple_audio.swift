import Foundation
import AVFoundation

@main struct AppleAudioTests {
    static func frequency(_ signal:[Float],rate:Double)->Double{
        let start=signal.count/4,end=signal.count*3/4
        var crossings=0
        for i in (start+1)..<end{if signal[i-1]<=0 && signal[i]>0{crossings+=1}}
        return Double(crossings)*rate/Double(end-start)
    }
    static func main()throws{
        let rate=24000.0
        let input=(0..<24000).map{Float(sin(Double($0)*2*Double.pi*220/rate)*0.3)}
        for (stretch,pitch,hz) in [(2.0,0.0,220.0),(1.0,12.0,440.0),(0.5,-12.0,110.0)]{
            let result=try SampleTransform.render(input,rate:rate,stretch:stretch,pitch:pitch,memoryLimit:16*1024*1024)
            assert(result.count==Int(Double(input.count)*stretch))
            assert(result.allSatisfy{$0.isFinite})
            assert(result.map{abs($0)}.max()!>0.05,"Silent transform")
            let measured=frequency(result,rate:rate)
            assert(abs(measured-hz)<hz*0.15,"Pitch/duration coupling: measured \(measured), expected \(hz)")
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("source.caf")
        let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:1)!
        let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:24000)!
        pcm.frameLength=24000;input.withUnsafeBufferPointer{pcm.floatChannelData![0].update(from:$0.baseAddress!,count:input.count)}
        do{let file=try AVAudioFile(forWriting:source,settings:format.settings);try file.write(from:pcm)}
        let original=try Data(contentsOf:source)
        let slot=SampleSlot(asset:"source.caf",name:"Test",end:1,stretch:2,pitch:7)
        let first=try SampleTransform.prepare(input,rate:rate,slot:slot,source:source,root:root,memoryLimit:16*1024*1024)
        let cached=try SampleTransform.prepare(input,rate:rate,slot:slot,source:source,root:root,memoryLimit:16*1024*1024)
        let after=try Data(contentsOf:source)
        assert(first==cached && after==original)
        print("PASS: independent duration/pitch, finite non-silent renders, cache reuse and unchanged source.")
    }
}
