import AVFoundation
import AudioToolbox
import Darwin

final class PocketFXUnit:AUAudioUnit {
    private var input:AUAudioUnitBus!
    private var output:AUAudioUnitBus!
    private var inputs:AUAudioUnitBusArray!
    private var outputs:AUAudioUnitBusArray!
    private var dsp:OpaquePointer?
    var clock:HostClock?
    override init(componentDescription:AudioComponentDescription,options:AudioComponentInstantiationOptions=[]) throws {
        try super.init(componentDescription:componentDescription,options:options)
        guard let format=AVAudioFormat(standardFormatWithSampleRate:44100,channels:2) else {throw PocketError.message("FX format unavailable.")}
        input=try AUAudioUnitBus(format:format);output=try AUAudioUnitBus(format:format)
        inputs=AUAudioUnitBusArray(audioUnit:self,busType:.input,busses:[input]);outputs=AUAudioUnitBusArray(audioUnit:self,busType:.output,busses:[output])
        maximumFramesToRender=4096
    }
    override var inputBusses:AUAudioUnitBusArray {inputs}
    override var outputBusses:AUAudioUnitBusArray {outputs}
    override func allocateRenderResources() throws {
        guard input.format.channelCount==2,output.format.channelCount==2,!output.format.isInterleaved,!input.format.isInterleaved,input.format.commonFormat == .pcmFormatFloat32,output.format.commonFormat == .pcmFormatFloat32,input.format.sampleRate==output.format.sampleRate else {throw PocketError.message("XY effects require stereo float PCM.")}
        try super.allocateRenderResources()
        if let d=dsp {px_destroy(d)}
        dsp=px_create(output.format.sampleRate)
        guard dsp != nil else {throw PocketError.message("XY effect memory allocation failed.")}
        apply(settings)
    }
    override func deallocateRenderResources(){super.deallocateRenderResources();if let d=dsp{px_destroy(d);dsp=nil}}
    deinit {if let d=dsp{px_destroy(d)}}
    private var settings=FXState()
    func apply(_ state:FXState){settings=state;if let d=dsp{px_set(d,Int32(state.enabled ? state.mode.index : -1),Float(state.x),Float(state.y),state.division)}}
    override var internalRenderBlock:AUInternalRenderBlock {
        { [unowned self] flags,time,frames,_,data,_,pull in
            guard let pull=pull else{return kAudioUnitErr_NoConnection}
            let result=pull(flags,time,frames,0,data);if result != noErr{return result}
            guard let dsp=self.dsp else{return noErr}
            let buffers=UnsafeMutableAudioBufferListPointer(data)
            guard buffers.count==2,let left=buffers[0].mData,let right=buffers[1].mData else{return kAudioUnitErr_FormatNotSupported}
            let info=ph_get(self.clock?.handle,AVAudioTime.seconds(forHostTime:mach_absolute_time()))
            px_process(dsp,left.assumingMemoryBound(to:Float.self),right.assumingMemoryBound(to:Float.self),Int32(frames),info.tempo,info.beat)
            return noErr
        }
    }
}
