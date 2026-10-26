import Foundation

@main struct ClipEditTests {
    static func main() {
        var session=PocketSession();session.tempo=120
        let a=AudioClip(asset:"Assets/a.wav",start:2,offset:1,length:2,fadeIn:0.1,fadeOut:0.2,name:"A")
        let b=AudioClip(asset:"Assets/b.wav",start:6,length:1,name:"B")
        let t1=Track(name:"Audio 1",clips:[a]),t2=Track(name:"Audio 2",clips:[b])
        // A MIDI lane must never contribute to the audio-only marquee selection.
        session.tracks=[t1,t2,Track(name:"MIDI",isAudio:false,clips:[a])]
        let both:Set<UUID>=[a.id,b.id]
        let hits=ClipEdits.hits(in:session,from:CGPoint(x:15,y:0),to:CGPoint(x:90,y:180),zoom:10)
        assert(hits==both)
        assert(ClipEdits.hits(in:session,from:CGPoint(x:90,y:180),to:CGPoint(x:15,y:0),zoom:10)==both)
        assert(ClipEdits.hits(in:session,from:CGPoint(x:15,y:0),to:CGPoint(x:48,y:80),zoom:10)==[a.id])
        assert(ClipEdits.hits(in:session,from:CGPoint(x:100,y:0),to:CGPoint(x:120,y:200),zoom:10).isEmpty)
        assert(ClipEdits.hit(in:session,at:CGPoint(x:25,y:20),zoom:10)==a.id)
        assert(ClipEdits.hit(in:session,at:CGPoint(x:25,y:190),zoom:10)==nil)
        session.tracks.removeLast()
        let original=session
        let duplicated=ClipEdits.duplicate(in:&session,ids:both)
        assert(duplicated.count==2 && duplicated.isDisjoint(with:both))
        assert(session.tracks[0].clips.last!.start==7 && session.tracks[1].clips.last!.start==11)
        assert(session.tracks[0].clips.last!.offset==a.offset)
        // Value snapshots used by undo must retain the source session unchanged.
        assert(original.tracks[0].clips.count==1 && original.tracks[1].clips.count==1)
        session=original
        let clipboard=ClipEdits.placements(in:session,ids:both)
        ClipEdits.remove(in:&session,ids:both)
        assert(session.tracks.allSatisfy{$0.clips.isEmpty})
        let pasted=ClipEdits.paste(in:&session,items:clipboard,at:10)
        assert(pasted.count==2 && session.tracks[0].clips[0].start==10 && session.tracks[1].clips[0].start==14)
        assert(session.tracks[0].clips[0].asset==a.asset && session.tracks[0].clips[0].offset==a.offset)
        session=original
        let split=ClipEdits.split(in:&session,ids:both,at:3)
        assert(split.count==3 && session.tracks[0].clips.count==2 && session.tracks[1].clips.count==1)
        let left=session.tracks[0].clips[0],right=session.tracks[0].clips[1]
        assert(left.length==1 && right.length==1 && right.start==3 && right.offset==1.5)
        assert(left.fadeIn==0.1 && left.fadeOut==0 && right.fadeIn==0 && right.fadeOut==0.2)
        session=original
        ClipEdits.move(in:&session,ids:both,delta:-20)
        assert(session.tracks[0].clips[0].start==0 && session.tracks[1].clips[0].start==4)
        session=original
        ClipEdits.fades(in:&session,ids:both,seconds:10)
        assert(session.tracks[0].clips[0].fadeIn==0.5 && session.tracks[1].clips[0].fadeOut==0.25)
        assert(session.tracks[0].clips[0].asset==a.asset)
        let cropped=PerformanceMath.trimmed(a,left:true,delta:1,tempo:120,sourceDuration:5,grid:nil)
        assert(cropped.start==3 && cropped.offset==1.5 && cropped.length==1)
        let restored=PerformanceMath.trimmed(cropped,left:true,delta:-1,tempo:120,sourceDuration:5,grid:nil)
        assert(restored==a)
        let extended=PerformanceMath.trimmed(a,left:false,delta:100,tempo:120,sourceDuration:5,grid:nil)
        assert(extended.length==8 && extended.offset==a.offset && extended.asset==a.asset)
        let minimum=PerformanceMath.trimmed(a,left:false,delta:-100,tempo:120,sourceDuration:5,grid:nil)
        assert(minimum.length==0.03125)
        assert(FadeCurve.linear.gain(0.5)==0.5 && FadeCurve.slow.gain(0.5)==0.25 && FadeCurve.fast.gain(0.5)>0.7)
        assert(FadeCurve.fast.next == .linear)
        assert(PerformanceMath.division(0,snap:true)==4 && PerformanceMath.division(1,snap:true)==0.0625)
        // Old session JSON lacks every optional sampler/XY/curve field.
        let encoder=JSONEncoder(),decoder=JSONDecoder()
        let encoded=try! encoder.encode(original)
        let decoded=try! decoder.decode(PocketSession.self,from:encoded)
        assert(decoded==original && decoded.tracks[0].sampler==nil && decoded.tracks[0].clips[0].fadeCurve==nil)
        var new=original;new.tracks[0].xyFX=FXState();new.tracks[1].sampler=SamplerState()
        assert((try! decoder.decode(PocketSession.self,from:encoder.encode(new)))==new)
        var banks=SamplerState()
        let sample=SampleSlot(asset:"Assets/a.wav",name:"Chop",start:1,end:5,stretch:2,pitch:7)
        banks.bank=5;banks.setSlot(sample,pad:7)
        assert(banks.slot(7)==sample && banks.slot(7,bank:0)==nil)
        let notes=(0..<6).flatMap{bank in (0..<8).map{SamplerState.note($0,bank:bank)}}
        assert(Set(notes).count==48 && notes.allSatisfy{(0...127).contains($0)})
        let chops=SliceMath.slices(sample,count:8,peaks:[],duration:10,transients:false)
        assert(chops.count==8 && chops.first!.start==1 && chops.last!.end==5)
        assert(chops.allSatisfy{$0.stretch==2 && $0.pitch==7 && $0.asset==sample.asset && $0.oneShot})
        for i in 1..<8{assert(chops[i].start==chops[i-1].end)}
        var peaks=[Float](repeating:0,count:100);peaks[20]=1;peaks[35]=0.8
        let transient=SliceMath.slices(sample,count:8,peaks:peaks,duration:10,transients:true)
        assert(transient.count==3 && transient[1].start==2 && transient[2].start==3.5)
        new.tracks[1].sampler=banks
        assert((try! decoder.decode(PocketSession.self,from:encoder.encode(new)))==new)
        var midi=MIDIMessageDecoder()
        assert(midi.decode([0x91,60]).isEmpty)
        assert(midi.decode([100,0xF8,61,0]) == [MIDIMessage(status:0x91,data1:60,data2:100),MIDIMessage(status:0xF8),MIDIMessage(status:0x91,data1:61,data2:0)])
        assert(midi.decode([0xB7,7,127,0xFA,0xFC]) == [MIDIMessage(status:0xB7,data1:7,data2:127),MIDIMessage(status:0xFA),MIDIMessage(status:0xFC)])
        assert(midi.decode([0xF0,1,2,0xF7,3,4]).isEmpty)
        print("PASS: marquee/group edits, nondestructive trim/restore, source limits, fade curves, XY divisions and session round-trip.")
    }
}
