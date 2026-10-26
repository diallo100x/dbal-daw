import AVFoundation

// Intentionally a small SFZ subset, not a claim of full SFZ compatibility.
final class SampleVoice {
    let handle: OpaquePointer
    let node: AVAudioSourceNode
    init(rate: Double, voices: Int) throws {
        guard let h = ps_create(rate, Int32(voices), 0), let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw PocketError.message("Could not create sampler.") }
        handle = h
        node = AVAudioSourceNode(format: format) { isSilence, _, frames, list in
            isSilence.pointee = false
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count == 2, let l = buffers[0].mData, let r = buffers[1].mData else { return noErr }
            ps_render(h, l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), Int32(frames))
            return noErr
        }
    }
    deinit { ps_destroy(handle) }
    func midi(_ note: Int, _ velocity: Int) { _ = ps_midi(handle, Int32(note), Int32(velocity)) }
    func silence() { _ = ps_midi(handle, 128, 0) }
    func load(_ url: URL, memoryLimit: Int) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.utf8.count < 2_000_000 else { throw PocketError.message("SFZ definition is too large.") }
        guard !text.contains("#include"), !text.contains("#define") else { throw PocketError.message("SFZ #include/#define are not supported in this build. Flatten the definition first.") }
        let clean = text.components(separatedBy: .newlines).map { String($0.components(separatedBy: "//")[0]) }.joined(separator: "\n")
        let tagRE = try NSRegularExpression(pattern: "<(global|group|region|control)>")
        let ns = clean as NSString
        let tags = tagRE.matches(in: clean, range: NSRange(location: 0, length: ns.length))
        guard !tags.isEmpty else { throw PocketError.message("No SFZ regions found.") }
        var global: [String:String] = [:], group: [String:String] = [:], control: [String:String] = [:]
        var used = 0, count = 0, unknown = Set<String>()
        let supported: Set<String> = ["sample","key","lokey","hikey","pitch_keycenter","lovel","hivel","volume","pan","tune","transpose","loop_mode","loop_start","loop_end","ampeg_release","default_path"]
        for (index, tag) in tags.enumerated() {
            let start = tag.range.location + tag.range.length
            let end = index+1 < tags.count ? tags[index+1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: end-start))
            // A sample filename may contain spaces; values end at the next opcode.
            let re = try NSRegularExpression(pattern: "([A-Za-z_][A-Za-z_0-9]*)\\s*=\\s*(.*?)(?=\\s+[A-Za-z_][A-Za-z_0-9]*\\s*=|$)", options: [.dotMatchesLineSeparators])
            let b = body as NSString
            var values: [String:String] = [:]
            for m in re.matches(in: body, range: NSRange(location: 0, length: b.length)) {
                let k = b.substring(with: m.range(at: 1))
                values[k] = b.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !supported.contains(k) { unknown.insert(k) }
            }
            let kind = ns.substring(with: tag.range(at: 1))
            if kind == "global" { global = values; group = [:]; continue }
            if kind == "group" { group = values; continue }
            if kind == "control" { control.merge(values) { _,new in new }; continue }
            let v = global.merging(group) { _,n in n }.merging(values) { _,n in n }
            guard let sample = v["sample"], !sample.hasPrefix("*") else { throw PocketError.message("Each SFZ region needs a WAV/AIFF sample.") }
            let path = ((control["default_path"] ?? "") + sample).replacingOccurrences(of: "\\", with: "/")
            let sampleURL = try safeChild(url.deletingLastPathComponent(), path)
            let file = try AVAudioFile(forReading: sampleURL)
            guard file.length > 1, file.length <= Int64(Int32.max) else { throw PocketError.message("Invalid or oversized SFZ sample.") }
            let bytes = Int(file.length) * 4
            used += bytes * (Int(file.processingFormat.channelCount) + 1)
            guard used <= memoryLimit else { throw PocketError.message("SFZ exceeds this flavor's sample memory budget. Use a smaller kit.") }
            guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw PocketError.message("Could not allocate sample.") }
            try file.read(into: pcm)
            guard let channels = pcm.floatChannelData else { throw PocketError.message("SFZ samples must decode to floating point PCM.") }
            let frames = Int(pcm.frameLength), nc = Int(pcm.format.channelCount)
            var mono = [Float](repeating: 0, count: frames)
            for c in 0..<nc { for f in 0..<frames { mono[f] += channels[c][f] / Float(nc) } }
            func num(_ key: String, _ fallback: Double) throws -> Double {
                guard let s = v[key] else { return fallback }
                guard let n = Double(s), n.isFinite else { throw PocketError.message("Invalid SFZ \(key).") }; return n
            }
            let key = try v["key"].map { try noteNumber($0) }
            let lo = try v["lokey"].map { try noteNumber($0) } ?? key ?? 0
            let hi = try v["hikey"].map { try noteNumber($0) } ?? key ?? 127
            let root = try v["pitch_keycenter"].map { try noteNumber($0) } ?? key ?? 60
            let lv = try num("lovel", 1), hv = try num("hivel", 127)
            let mode = v["loop_mode"] ?? "no_loop"
            guard ["no_loop","one_shot","loop_sustain","loop_continuous"].contains(mode) else { throw PocketError.message("Unsupported SFZ loop mode: \(mode)") }
            // Explicit bounds required: embedded WAV loop metadata is not interpreted.
            let looping = mode == "loop_sustain" || mode == "loop_continuous"
            if looping && (v["loop_start"] == nil || v["loop_end"] == nil) { throw PocketError.message("Looping SFZ regions need explicit loop_start and loop_end.") }
            let ls = looping ? try num("loop_start", 0) : 0
            let le = looping ? try num("loop_end", 0) + 1 : 0
            guard (0...127).contains(lo), (0...127).contains(hi), lo <= hi, (0...127).contains(root), lv >= 0, hv <= 127, lv <= hv,
                  ls >= 0, le <= Double(frames), !looping || le > ls,
                  abs(try num("transpose", 0)) <= 48, abs(try num("tune", 0)) <= 1200 else { throw PocketError.message("SFZ region is out of range.") }
            let db = try num("volume", 0), pan = try num("pan", 0), release = try num("ampeg_release", 0.08)
            guard (-96...12).contains(db), (-100...100).contains(pan), (0.005...30).contains(release) else { throw PocketError.message("SFZ gain, pan or release is out of range.") }
            let tuning = try num("tune", 0) + num("transpose", 0)*100
            let ok = mono.withUnsafeBufferPointer { ptr in
                ps_region(handle, ptr.baseAddress, Int32(frames), pcm.format.sampleRate, Int32(lo), Int32(hi), Int32(root), Int32(lv), Int32(hv), Float(db), Float(pan/100), Int32(ls), Int32(le), Float(release), Float(tuning), mode == "one_shot" ? 1 : mode == "loop_continuous" ? 2 : 0)
            }
            guard ok == 1 else { throw PocketError.message("Could not load SFZ region (maximum 256).") }
            count += 1
        }
        guard count > 0 else { throw PocketError.message("No SFZ regions loaded.") }
        let warnings = unknown.sorted().map { "Unsupported SFZ opcode: \($0)" }
        return warnings
    }
}
func noteNumber(_ value: String) throws -> Int {
    if let n = Int(value), (0...127).contains(n) { return n }
    let re = try NSRegularExpression(pattern: "^([A-Ga-g])([#b]?)(-?[0-9]+)$")
    let s = value as NSString
    if let m = re.firstMatch(in: value, range: NSRange(location: 0, length: s.length)),
       let octave = Int(s.substring(with: m.range(at: 3))) {
        let pitch = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][s.substring(with: m.range(at: 1)).uppercased()]!
        let accidental = s.substring(with: m.range(at: 2))
        let n = (octave+1)*12 + pitch + (accidental == "#" ? 1 : accidental == "b" ? -1 : 0)
        if (0...127).contains(n) { return n }
    }
    throw PocketError.message("Invalid SFZ key: \(value)")
}

extension SampleVoice {
    func loadSampler(_ state:SamplerState,pads:Bool,root:URL,memoryLimit:Int) throws {
        var bytes=0
        var entries:[(Int?,SampleSlot)]=[]
        if pads {
            let names=["Kick","Snare","ClosedHat","OpenHat","LowTom","HighTom","Crash","Ride"]
            for bank in 0..<6 {for pad in 0..<8 {
                if let slot=state.slot(pad,bank:bank){entries.append((SamplerState.note(pad,bank:bank),slot))}
                else if bank==0 && state.useStarterPads != false{entries.append((SamplerState.note(pad,bank:bank),SampleSlot(asset:"@starter/\(names[pad]).wav",name:names[pad],end:100,oneShot:true)))}
            }}
        }else if let slot=state.keyboard{entries=[(nil,slot)]}
        guard !entries.isEmpty else {throw PocketError.message("Load a sample into the sampler editor.")}
        for (pad,slot) in entries {
            let url:URL
            if slot.asset.hasPrefix("@starter/") {
                guard let bundled=Bundle.main.url(forResource:String(slot.asset.dropFirst(9)).replacingOccurrences(of:".wav",with:""),withExtension:"wav",subdirectory:"StarterKit") else{throw PocketError.message("Starter sample missing.")};url=bundled
            }else{url=try safeChild(root,slot.asset)}
            let file=try AVAudioFile(forReading:url),rate=file.processingFormat.sampleRate
            let first=AVAudioFramePosition(slot.start*rate),end=min(file.length,AVAudioFramePosition(slot.end*rate))
            guard first>=0,end>first+1,end-first<Int64(Int32.max) else {throw PocketError.message("Sampler crop is outside the file.")}
            let frames=Int(end-first),channels=Int(file.processingFormat.channelCount)
            bytes+=frames*4*(channels+1)
            guard bytes<=memoryLimit,let pcm=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(frames)) else {throw PocketError.message("Sampler memory budget exceeded. Crop a smaller region.")}
            file.framePosition=first;try file.read(into:pcm,frameCount:AVAudioFrameCount(frames))
            guard let data=pcm.floatChannelData else {throw PocketError.message("Sample decoding failed.")}
            var mono=[Float](repeating:0,count:Int(pcm.frameLength))
            for f in mono.indices {
                let t=Double(f)/rate,remaining=Double(mono.count-f-1)/rate
                let gain=slot.curve.gain(min(1,slot.fadeIn>0 ? t/slot.fadeIn : 1))*slot.curve.gain(min(1,slot.fadeOut>0 ? remaining/slot.fadeOut : 1))
                for c in 0..<channels {mono[f]+=data[c][f]/Float(channels)*Float(gain)}
            }
            mono=try SampleTransform.prepare(mono,rate:rate,slot:slot,source:url,root:root,memoryLimit:max(0,memoryLimit-bytes))
            bytes+=mono.count*4
            guard bytes<=memoryLimit else{throw PocketError.message("Prepared samples exceed the memory budget.")}
            let n=pad ?? slot.root
            let ok=mono.withUnsafeBufferPointer{p in ps_region(handle,p.baseAddress,Int32(p.count),rate,Int32(pad ?? 0),Int32(pad ?? 127),Int32(n),1,127,0,0,0,slot.loop ? Int32(p.count) : 0,0.05,0,slot.oneShot ? 1 : slot.loop ? 2 : 0)}
            guard ok==1 else {throw PocketError.message("Sampler region allocation failed.")}
        }
    }
}
