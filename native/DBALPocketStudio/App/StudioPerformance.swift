import SwiftUI
import AVFoundation

struct RepeatHold {var track:UUID;var base:Int;var next:Double;var velocity:Int?=nil}
struct PendingNoteOff {var track:UUID;var note:Int;var seconds:Double}
@MainActor extension Studio {
    var midiExpression:MIDIExpression {PerformanceMath.expression(mode:midiMatrixMode,x:midiX,y:midiY,snap:midiSnap,repeatBeats:repeatBeats)}
    var midiPitchOffset:Int {midiExpression.pitch}
    var midiVelocity:Int {midiExpression.velocity}
    var effectiveRepeatBeats:Double {midiExpression.beats}
    func noteOn(_ key:Int, velocity incoming:Int? = nil) {
        guard !busy,let i=selectedIndex,!session.tracks[i].isAudio,held[key]==nil,repeatHeld[key]==nil else{return}
        let track=session.tracks[i].id,base=key == -1 ? midiRoot:key
        if repeaterEnabled {
            let rate=effectiveRepeatBeats
            let delay=midiSnap && playing ? max(0,(ceil(currentBeat/rate)*rate-currentBeat)*60/session.tempo):0
            repeatHeld[key]=RepeatHold(track:track,base:base,next:nowSeconds+delay,velocity:incoming)
            performanceTick();startPerformanceTimer();return
        }
        let note=max(0,min(127,base+midiPitchOffset))
        let velocity=PerformanceMath.velocity(incoming,expression:midiVelocity)
        audio.send(track:track,note:note,velocity:velocity)
        heldVelocities[key]=velocity
        held[key]=(track,currentBeat);soundingNotes[key]=note
    }
    func noteOff(_ key:Int) {
        if repeatHeld.removeValue(forKey:key) != nil{return}
        guard let entry=held.removeValue(forKey:key) else{return}
        let note=soundingNotes.removeValue(forKey:key) ?? key
        let velocity=heldVelocities.removeValue(forKey:key) ?? 100
        audio.send(track:entry.0,note:note,velocity:0)
        if recording,armed==entry.0,let i=session.tracks.firstIndex(where:{$0.id==entry.0}) {
            session.tracks[i].notes.append(MIDINoteEdits.recorded(start:entry.1,end:currentBeat,note:note,velocity:velocity,grid:inputQuantize ? grid:nil))
        }
    }
    func startPerformanceTimer(){
        guard performanceTimer==nil else{return}
        let timer=Timer(timeInterval:0.005,repeats:true){[weak self] _ in Task{@MainActor in self?.performanceTick()}}
        performanceTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func performanceTick(){
        let now=nowSeconds
        for off in pendingNoteOffs where off.seconds<=now {audio.send(track:off.track,note:off.note,velocity:0)}
        pendingNoteOffs.removeAll{$0.seconds<=now}
        let interval=effectiveRepeatBeats*60/session.tempo
        for key in Array(repeatHeld.keys) {
            guard var item=repeatHeld[key],now>=item.next else{continue}
            let note=max(0,min(127,item.base+midiPitchOffset)),velocity=PerformanceMath.velocity(item.velocity,expression:midiVelocity)
            audio.send(track:item.track,note:note,velocity:velocity)
            pendingNoteOffs.append(PendingNoteOff(track:item.track,note:note,seconds:now+interval*0.65))
            if recording,now>=startSeconds,armed==item.track,let i=session.tracks.firstIndex(where:{$0.id==item.track}) {
                session.tracks[i].notes.append(MIDINoteEdits.recorded(start:currentBeat,end:currentBeat+effectiveRepeatBeats*0.65,note:note,velocity:velocity,grid:inputQuantize ? grid:nil))
            }
            item.next+=interval;if item.next<=now{item.next=now+interval};repeatHeld[key]=item
        }
        if repeatHeld.isEmpty && pendingNoteOffs.isEmpty {performanceTimer?.invalidate();performanceTimer=nil}
    }
    func cancelRepeater(){
        performanceTimer?.invalidate();performanceTimer=nil
        for off in pendingNoteOffs{audio.send(track:off.track,note:off.note,velocity:0)}
        pendingNoteOffs=[];repeatHeld=[:]
    }
    func updateMIDIMatrix(x:Double,y:Double,triggerRoot:Bool=true){
        midiX=x;midiY=y
        if let output=soundingNotes[-1],output != max(0,min(127,midiRoot+midiPitchOffset)){noteOff(-1)}
        if triggerRoot{noteOn(-1)}
    }
    func releasePerformanceTouches(){
        for key in Array(held.keys){noteOff(key)}
        cancelRepeater()
    }
    func commitClip(_ clip:AudioClip){
        guard !busy,!recording,let ti=session.tracks.firstIndex(where:{$0.clips.contains{$0.id==clip.id}}),let ci=session.tracks[ti].clips.firstIndex(where:{$0.id==clip.id}),clip != session.tracks[ti].clips[ci] else{return}
        change({$0.tracks[ti].clips[ci]=clip},graph:true)
    }
    func cycleFadeCurve(_ id:UUID){
        guard let c=session.tracks.flatMap({$0.clips}).first(where:{$0.id==id}) else{return}
        var next=c;next.fadeCurve=(c.fadeCurve ?? .linear).next;commitClip(next)
    }
    func cycleSelectedFadeCurves(){
        let ids=selectedClips
        change({session in
            for ti in session.tracks.indices {for ci in session.tracks[ti].clips.indices where ids.contains(session.tracks[ti].clips[ci].id){
                let old=session.tracks[ti].clips[ci].fadeCurve ?? .linear
                session.tracks[ti].clips[ci].fadeCurve=old.next
            }}
        },graph:true);showSelectionMenu=false
    }
    func importSample(_ url:URL,pad:Int?) async {
        guard !busy,!recording,let i=selectedIndex,!session.tracks[i].isAudio else{return}
        stop();save(capture:true)
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        do {
            let file=try AVAudioFile(forReading:url)
            let asset="Assets/\(UUID().uuidString).\(url.pathExtension)"
            try FileManager.default.copyItem(at:url,to:safeChild(root,asset))
            let slot=SampleSlot(asset:asset,name:url.deletingPathExtension().lastPathComponent,end:Double(file.length)/file.processingFormat.sampleRate,root:60,oneShot:pad != nil)
            saveSample(slot,pad:pad)
        }catch{fail(error)}
    }
    func saveSample(_ slot:SampleSlot,pad:Int?){
        guard let i=selectedIndex,!session.tracks[i].isAudio else{return}
        change({session in
            var state=session.tracks[i].sampler ?? SamplerState()
            if let pad=pad{state.setSlot(slot,pad:pad)}else{state.keyboard=slot}
            session.tracks[i].sampler=state;session.tracks[i].instrument=pad == nil ? .sample:.padSampler
            session.tracks[i].plugin=nil
        },graph:true)
    }
    var samplerBank:Int {selectedIndex.map{session.tracks[$0].sampler?.activeBank ?? 0} ?? 0}
    func switchSamplerBank(_ bank:Int){
        guard !busy,!recording,let i=selectedIndex else{return}
        // No graph rebuild: all banks already have distinct loaded note mappings.
        stop();var state=session.tracks[i].sampler ?? SamplerState();state.bank=max(0,min(5,bank));session.tracks[i].sampler=state;save()
    }
    func populateSlices(_ slots:[SampleSlot]){
        guard !slots.isEmpty,let i=selectedIndex else{return}
        change({session in
            var state=session.tracks[i].sampler ?? SamplerState()
            state.useStarterPads=false
            for pad in 0..<8{state.setSlot(pad<slots.count ? slots[pad]:nil,pad:pad)}
            session.tracks[i].sampler=state;session.tracks[i].instrument = .padSampler;session.tracks[i].plugin=nil
        },graph:true)
    }
    func setFX(_ state:FXState,rebuild:Bool){
        guard let i=selectedIndex else{return}
        if rebuild {
            let graph=(session.tracks[i].xyFX?.enabled ?? false) != state.enabled
            if graph{change({$0.tracks[i].xyFX=state},graph:true)}
            else{guard !busy,!recording else{return};checkpoint();session.tracks[i].xyFX=state;audio.updateFX(session);save()}
        }else{session.tracks[i].xyFX=state;audio.updateFX(session)}
    }
}

@MainActor extension Studio {
    func quantizeNotes(track: UUID, selected: UUID? = nil, mode: MIDIQuantizeMode = .starts) {
        guard let ti = session.tracks.firstIndex(where: { $0.id == track && !$0.isAudio }),
              !session.tracks[ti].notes.isEmpty else { return }
        let division = grid
        change { session in
            for ni in session.tracks[ti].notes.indices {
                let note = session.tracks[ti].notes[ni]
                if selected == nil || note.id == selected {
                    session.tracks[ti].notes[ni] = MIDINoteEdits.quantized(note, grid: division, mode: mode)
                }
            }
        }
    }
}
