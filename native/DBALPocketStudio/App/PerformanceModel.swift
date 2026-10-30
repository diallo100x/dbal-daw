import Foundation

enum FadeCurve:String,Codable,CaseIterable {
    case linear,slow,fast
    var next:FadeCurve {Self.allCases[(Self.allCases.firstIndex(of:self)!+1)%Self.allCases.count]}
    func gain(_ value:Double)->Double {
        let x=min(1,max(0,value))
        switch self {case .linear:return x;case .slow:return x*x;case .fast:return sqrt(x)}
    }
}
struct SampleSlot:Codable,Equatable {
    var asset:String
    var name:String
    var start:Double=0
    var end:Double
    var root:Int=60
    var fadeIn:Double=0
    var fadeOut:Double=0
    var curve:FadeCurve = .linear
    var loop=false
    var oneShot=false
    var stretch:Double? // Duration multiplier, independent of pitch.
    var pitch:Double? // Semitones baked during sample preparation.
}
struct SamplerState:Codable,Equatable {
    var keyboard:SampleSlot?
    var pads:[SampleSlot?]=Array(repeating:nil,count:8)
    var extraBanks:[[SampleSlot?]]?
    var bank:Int?
    var useStarterPads:Bool?
    var activeBank:Int {max(0,min(5,bank ?? 0))}
    static let bankNames=["A","B","C","D","E","F"]
    func slot(_ pad:Int,bank:Int?=nil)->SampleSlot? {
        let b=bank ?? activeBank
        return b==0 ? pads[pad] : extraBanks?[b-1][pad]
    }
    mutating func setSlot(_ value:SampleSlot?,pad:Int,bank:Int?=nil){
        let b=bank ?? activeBank
        if b==0{pads[pad]=value}else{
            if extraBanks==nil{extraBanks=Array(repeating:Array(repeating:nil,count:8),count:5)}
            extraBanks![b-1][pad]=value
        }
    }
    func note(_ pad:Int)->Int {Self.note(pad,bank:activeBank)}
    static func note(_ pad:Int,bank:Int)->Int {bank==0 ? padNotes[pad]:60+(bank-1)*8+pad}
    static let padNotes=[36,38,42,46,41,45,49,51]
}
enum XYEffect:String,Codable,CaseIterable {
    case pitch="Pitch",repeater="Repeater",filter="Filter",wah="Wah",gate="Gate",flange="Flange"
    var index:Int {Self.allCases.firstIndex(of:self)!}
}
struct FXState:Codable,Equatable {
    var enabled=false
    var mode:XYEffect = .filter
    var x:Double=0.5
    var y:Double=0.5
    var snap=true
    var division:Double {PerformanceMath.division(x,snap:snap)}
}
enum PerformanceMath {
    static let divisions:[Double]=[4,2,1,0.5,0.25,0.125,0.0625]
    static func division(_ x:Double,snap:Bool)->Double {
        let v=min(1,max(0,x))
        return snap ? divisions[min(6,Int((v*6).rounded()))] : 4*pow(2,-6*v)
    }
    static func point(_ x:Double,_ y:Double,snap:Bool)->(Double,Double) {
        let a=min(1,max(0,x)),b=min(1,max(0,y))
        return snap ? ((a*8).rounded()/8,(b*8).rounded()/8) : (a,b)
    }
    static func trimmed(_ original:AudioClip,left:Bool,delta:Double,tempo:Double,sourceDuration:Double,grid:Double?)->AudioClip {
        var c=original
        let unit=60/tempo
        var boundary=left ? c.start+delta : c.start+c.length+delta
        if let grid=grid {boundary=(boundary/grid).rounded()*grid}
        if left {
            boundary=max(max(0,c.start-c.offset/unit),min(c.start+c.length-0.03125,boundary))
            let shift=boundary-c.start;c.start=boundary;c.offset+=shift*unit;c.length-=shift
        }else{
            let last=c.start+max(0,sourceDuration-c.offset)/unit
            boundary=max(c.start+0.03125,min(last,boundary));c.length=boundary-c.start
        }
        c.fadeIn=min(c.fadeIn,c.length*unit);c.fadeOut=min(c.fadeOut,c.length*unit)
        return c
    }
}

// Peak-envelope transient detection, bounded to eight slices. Equal mode is deterministic.
enum SliceMath {
    static func slices(_ slot:SampleSlot,count:Int,peaks:[Float],duration:Double,transients:Bool)->[SampleSlot] {
        let n=max(1,min(8,count)),length=slot.end-slot.start
        guard length>=0.002*Double(n) else{return []}
        var boundaries=[slot.start]
        if transients && duration>0 && peaks.count>2 {
            let gap=max(0.02,length/Double(n)*0.3)
            var candidates:[(Double,Float)]=[]
            for i in 1..<peaks.count {
                let time=Double(i)/Double(peaks.count)*duration
                let rise=peaks[i]-peaks[i-1]
                if time>slot.start+gap && time<slot.end-gap && rise>0.015{candidates.append((time,rise))}
            }
            for c in candidates.sorted(by:{$0.1>$1.1}) {
                if boundaries.count>=n{break}
                if boundaries.allSatisfy({abs($0-c.0)>=gap}){boundaries.append(c.0)}
            }
        }else{boundaries+=(1..<n).map{slot.start+Double($0)*length/Double(n)}}
        boundaries.append(slot.end);boundaries.sort()
        return (0..<boundaries.count-1).map{i in
            var s=slot;s.start=boundaries[i];s.end=boundaries[i+1];s.name="\(slot.name) \(i+1)";s.loop=false;s.oneShot=true
            s.fadeIn=min(0.002,(s.end-s.start)/4);s.fadeOut=s.fadeIn;return s
        }
    }
}


enum MIDIMatrixMode: String, CaseIterable {
    case timingVelocity = "Timing / Velocity"
    case timingPitch = "Timing / Pitch"
    case pitchVelocity = "Pitch / Velocity"
}

struct MIDIExpression {
    var pitch: Int
    var velocity: Int
    var beats: Double
}

enum PerformanceLayout {
    static let whiteNotes = (0...127).filter { [0,2,4,5,7,9,11].contains($0 % 12) }
    static func keyWidth(_ value: Double) -> Double { value.isFinite ? min(110,max(22,value)) : 46 }
    static func firstWhite(_ value: Double, width: Double, viewport: Double) -> Double {
        let maximum=max(0,Double(whiteNotes.count)-max(1,viewport)/keyWidth(width))
        return min(maximum,max(0,value.isFinite ? value:35))
    }
    static func height(_ value: Double, maximum: Double) -> Double {
        min(max(260,maximum),max(260,value.isFinite ? value:280))
    }
}

extension PerformanceMath {
    static func expression(mode: MIDIMatrixMode, x: Double, y: Double,
                           snap: Bool, repeatBeats: Double) -> MIDIExpression {
        let a=x.isFinite ? min(1,max(0,x)):0.5
        let b=y.isFinite ? min(1,max(0,y)):0.5
        let pitch=mode == .pitchVelocity ? Int((a*24-12).rounded()) :
            mode == .timingPitch ? Int((b*24-12).rounded()) : 0
        let velocity=mode == .timingPitch ? 100:max(1,min(127,Int(b*126)+1))
        let beats=mode == .pitchVelocity ? (repeatBeats.isFinite ? min(4,max(0.0625,repeatBeats)):0.25) : division(a,snap:snap)
        return MIDIExpression(pitch:pitch,velocity:velocity,beats:beats)
    }
    static func velocity(_ incoming: Int?, expression: Int) -> Int {
        guard let incoming=incoming else{return min(127,max(1,expression))}
        return min(127,max(1,Int((Double(min(127,max(1,incoming)))*Double(min(127,max(1,expression)))/100).rounded())))
    }
}
