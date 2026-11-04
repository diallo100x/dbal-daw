import AVFoundation
import AudioToolbox
import CoreAudioKit

/// VII music-effect AUv3 prototype. Add this source and VIIEngine.c/.h to a
/// macOS Audio Unit Extension target with aumf/VoII/DbAL registration.
/// This file has not yet been compiled in Xcode or verified in DBAL.
final class VIIAudioUnit: AUAudioUnit {
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private let inputs: AUAudioUnitBusArray
    private let outputs: AUAudioUnitBusArray
    private let wetParameter: AUParameter
    private let parameters: AUParameterTree
    private let state = UnsafeMutablePointer<VIIEngine>.allocate(capacity: 1)

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: nil, busType: .input, busses: [])
        outputs = AUAudioUnitBusArray(audioUnit: nil, busType: .output, busses: [])
        wetParameter = AUParameterTree.createParameter(withIdentifier: "wet", name: "Synth Mix",
            address: 0, min: 0, max: 1, unit: .generic,
            unitName: nil, flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil)
        parameters = AUParameterTree.createTree(withChildren: [wetParameter])
        super.init(componentDescription: componentDescription, options: options)
        // AUAudioUnitBusArray requires the owning Audio Unit after super.init.
        self.wetParameter.value = 1
        self.parameterTree?.implementorValueObserver = { [weak self] param, value in
            if param.address == 0 { self?.state.pointee.wet = value }
        }
        vii_init(state, 48000)
    }

    deinit { state.deallocate() }
    override var inputBusses: AUAudioUnitBusArray {
        AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
    }
    override var outputBusses: AUAudioUnitBusArray {
        AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }
    override var parameterTree: AUParameterTree? { parameters }

    override func allocateRenderResources() throws {
        guard inputBus.format.sampleRate == outputBus.format.sampleRate,
              inputBus.format.channelCount == outputBus.format.channelCount,
              inputBus.format.commonFormat == .pcmFormatFloat32,
              !inputBus.format.isInterleaved else {
            throw NSError(domain: "VII", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "VII requires matching noninterleaved Float32 buses."])
        }
        vii_init(state, Float(outputBus.format.sampleRate))
        state.pointee.wet = wetParameter.value
        try super.allocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let tracker = state
        return { _, timestamp, frameCount, _, output, _, pullInput in
            guard let pullInput = pullInput else { return kAudioUnitErr_NoConnection }
            let result = pullInput(nil, timestamp, frameCount, 0, output)
            guard result == noErr else { return result }
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard let first = buffers.first, let input = first.mData else { return noErr }
            let mono = input.assumingMemoryBound(to: Float.self)
            // In-place processing is safe: the core reads each sample before writing it.
            vii_process(tracker, mono, mono, frameCount)
            // Prototype mono synthesis on all channels. Stereo-safe, but does not
            // preserve stereo input in fully wet mode.
            if buffers.count > 1 {
                for channel in 1..<buffers.count {
                    guard let dest = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for i in 0..<Int(frameCount) { dest[i] = mono[i] }
                }
            }
            return noErr
        }
    }
}

final class VIIViewController: AUViewController, AUAudioUnitFactory {
    func createAudioUnit(with description: AudioComponentDescription) throws -> AUAudioUnit {
        try VIIAudioUnit(componentDescription: description)
    }
}
