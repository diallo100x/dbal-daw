import SwiftUI
#if os(iOS)
import UIKit
#endif

enum WaveHandle:Equatable {case trimLeft,trimRight,fadeIn,fadeOut}
#if os(iOS)
@MainActor struct WaveformHandles:UIViewRepresentable {
    var fadeInWidth:Double
    var fadeOutWidth:Double
    var edit:(WaveHandle,Double,Bool,Bool)->Void
    var curve:()->Void
    func makeUIView(context:Context)->HandleView{HandleView()}
    func updateUIView(_ view:HandleView,context:Context){view.leftFade=fadeInWidth;view.rightFade=fadeOutWidth;view.edit=edit;view.curve=curve}
}
@MainActor final class HandleView:UIView {
    var leftFade:Double=0,rightFade:Double=0
    var edit:((WaveHandle,Double,Bool,Bool)->Void)?
    var curve:(()->Void)?
    private var mode:WaveHandle?
    override init(frame:CGRect){
        super.init(frame:frame);backgroundColor = .clear
        let pan=UIPanGestureRecognizer(target:self,action:#selector(drag(_:)));addGestureRecognizer(pan)
        let tap=UITapGestureRecognizer(target:self,action:#selector(tap(_:)));tap.require(toFail:pan);addGestureRecognizer(tap)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView?{
        guard bounds.contains(point) else{return nil}
        let fade=point.x<=leftFade || point.x>=Double(bounds.width)-rightFade
        if point.x<18 || point.x>bounds.width-18 || (event?.modifierFlags.contains(.shift)==true && fade){return self}
        return nil
    }
    @objc private func tap(_ g:UITapGestureRecognizer){if g.modifierFlags.contains(.shift){curve?()}}
    @objc private func drag(_ g:UIPanGestureRecognizer){
        let t=g.translation(in:self),p=g.location(in:self)
        if g.state == .began {
            let origin=CGPoint(x:p.x-t.x,y:p.y-t.y),left=origin.x<bounds.width/2
            mode=(origin.y<20 || origin.y>bounds.height-20) ? (left ? .fadeIn:.fadeOut):(left ? .trimLeft:.trimRight)
        }
        guard let mode=mode else{return}
        if g.state == .changed || g.state == .began {edit?(mode,Double(t.x),false,false)}
        if g.state == .ended {edit?(mode,Double(t.x),true,false);self.mode=nil}
        if g.state == .cancelled || g.state == .failed {edit?(mode,0,true,true);self.mode=nil}
    }
}
#endif
struct FadeDrawing:View {
    let fadeIn:Double
    let fadeOut:Double
    let duration:Double
    let curve:FadeCurve
    var body:some View {
        Canvas{context,size in
            guard duration>0 else{return}
            for side in 0..<2 {
                let width=min(Double(size.width),(side==0 ? fadeIn:fadeOut)/duration*Double(size.width))
                guard width>0 else{continue}
                var line=Path()
                for step in 0...32 {
                    let x=Double(step)/32*width
                    let gain=curve.gain(Double(step)/32)
                    let point=CGPoint(x:side==0 ? x:Double(size.width)-x,y:(1-gain)*Double(size.height))
                    if step==0{line.move(to:point)}else{line.addLine(to:point)}
                }
                context.stroke(line,with:.color(.orange),lineWidth:2)
            }
            for x in [0.0,Double(size.width)-7] {
                context.fill(Path(CGRect(x:x,y:22,width:7,height:max(1,size.height-28))),with:.color(.cyan.opacity(0.8)))
                context.fill(Path(CGRect(x:x,y:0,width:9,height:12)),with:.color(.orange))
            }
        }.allowsHitTesting(false)
    }
}
