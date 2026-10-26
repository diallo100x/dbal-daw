import AVFoundation
import CryptoKit

// Offline preparation only: no per-voice time-stretch nodes on the live render path.
enum SampleTransform {
    static func prepare(_ input:[Float],rate:Double,slot:SampleSlot,source:URL,root:URL,memoryLimit:Int)throws->[Float]{
        let stretch=slot.stretch ?? 1,pitch=slot.pitch ?? 0
        if stretch==1 && pitch==0{return input}
        let attrs=try FileManager.default.attributesOfItem(atPath:source.path)
        let encoded=try JSONEncoder().encode(slot)
        var signature=encoded
        signature.append(Data("\(rate)|\(attrs[.size] ?? 0)|\(attrs[.modificationDate] ?? Date.distantPast)".utf8))
        let key=SHA256.hash(data:signature).map{String(format:"%02x",$0)}.joined()
        let cache=root.appendingPathComponent("Cache/Sampler",isDirectory:true)
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        let target=cache.appendingPathComponent(key).appendingPathExtension("caf")
        if let file=try? AVAudioFile(forReading:target),file.length>1,file.length<Int64(memoryLimit/12),
           let pcm=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)){
            try file.read(into:pcm)
            if let channel=pcm.floatChannelData{return Array(UnsafeBufferPointer(start:channel[0],count:Int(pcm.frameLength)))}
        }
        let result=try render(input,rate:rate,stretch:stretch,pitch:pitch,memoryLimit:memoryLimit)
        guard let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:1),let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(result.count)) else{throw PocketError.message("Cannot cache prepared sample.")}
        pcm.frameLength=AVAudioFrameCount(result.count)
        result.withUnsafeBufferPointer{pcm.floatChannelData![0].update(from:$0.baseAddress!,count:result.count)}
        let temp=cache.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        do {let file=try AVAudioFile(forWriting:temp,settings:format.settings);try file.write(from:pcm)}
        do{if FileManager.default.fileExists(atPath:target.path){try FileManager.default.removeItem(at:target)};try FileManager.default.moveItem(at:temp,to:target)}catch{try? FileManager.default.removeItem(at:temp);throw error}
        return result
    }

    static func render(_ input:[Float],rate:Double,stretch:Double,pitch:Double,memoryLimit:Int)throws->[Float]{
        if stretch==1 && pitch==0{return input}
        let count=Int((Double(input.count)*stretch).rounded())
        guard count>1,count<=memoryLimit/12,let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:1),
              let source=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(input.count)),
              let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024) else{throw PocketError.message("Stretch exceeds the preparation memory budget. Crop a smaller sample.")}
        source.frameLength=AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer{source.floatChannelData![0].update(from:$0.baseAddress!,count:input.count)}
        let engine=AVAudioEngine(),player=AVAudioPlayerNode(),unit=AVAudioUnitTimePitch()
        unit.rate=Float(1/stretch);unit.pitch=Float(pitch*100)
        engine.attach(player);engine.attach(unit);engine.connect(player,to:unit,format:format);engine.connect(unit,to:engine.mainMixerNode,format:format)
        try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:1024)
        defer{player.stop();engine.stop();engine.disableManualRenderingMode()}
        player.scheduleBuffer(source,at:nil,options:[],completionHandler:nil);try engine.start();player.play()
        var result=[Float]();result.reserveCapacity(count)
        // Discard declared processing latency, then retain exactly the requested duration.
        var skip=Int((unit.auAudioUnit.latency*rate).rounded()),retries=0
        while result.count<count {
            let status=try engine.renderOffline(AVAudioFrameCount(min(1024,count-result.count+skip)),to:output)
            switch status {
            case .success:
                guard output.frameLength>0 else{throw PocketError.message("Sample preparation produced no audio.")}
                let drop=min(skip,Int(output.frameLength));skip-=drop
                let take=min(count-result.count,Int(output.frameLength)-drop)
                if take>0{result.append(contentsOf:UnsafeBufferPointer(start:output.floatChannelData![0].advanced(by:drop),count:take))}
                retries=0
            case .cannotDoInCurrentContext,.insufficientDataFromInputNode:
                retries+=1;if retries>100{throw PocketError.message("Time-stretch preparation stalled.")}
            case .error:throw PocketError.message("Time-stretch preparation failed.")
            @unknown default:throw PocketError.message("Unknown sample render status.")
            }
        }
        return result
    }
}
