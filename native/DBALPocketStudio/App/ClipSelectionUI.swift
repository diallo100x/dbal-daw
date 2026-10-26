import SwiftUI
import UIKit

enum MarqueePhase { case began, changed, ended, cancelled }
// Mouse: primary-button drag. Touch/Pencil: hold, then drag, so a quick swipe can scroll.
@MainActor struct ClipSelectionSurface: UIViewRepresentable {
    let enabled: Bool
    var edges:[CGRect]=[]
    var fadedAreas:[CGRect]=[]
    let onTap: (CGPoint) -> Void
    let onSelection: (CGPoint,CGPoint,MarqueePhase) -> Void
    func makeUIView(context: Context) -> MarqueeView { MarqueeView() }
    func updateUIView(_ view: MarqueeView, context: Context) {
        view.passThrough=edges;view.shiftPassThrough=fadedAreas;view.onTap=onTap;view.onSelection=onSelection;view.isUserInteractionEnabled=enabled
    }
}
@MainActor final class MarqueeView: UIView, UIGestureRecognizerDelegate {
    var onTap: ((CGPoint)->Void)?
    var onSelection: ((CGPoint,CGPoint,MarqueePhase)->Void)?
    var passThrough:[CGRect]=[]
    var shiftPassThrough:[CGRect]=[]
    override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
        if passThrough.contains(where:{$0.contains(point)}) || (event?.modifierFlags.contains(.shift)==true && shiftPassThrough.contains(where:{$0.contains(point)})){return nil}
        return super.hitTest(point,with:event)
    }
    private var origin=CGPoint.zero
    private var active=false
    private let outline=CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame:frame);backgroundColor = .clear;isOpaque=false
        outline.fillColor=UIColor.systemTeal.withAlphaComponent(0.16).cgColor
        outline.strokeColor=UIColor.systemTeal.cgColor;outline.lineWidth=1.5;outline.lineDashPattern=[5,3]
        layer.addSublayer(outline)
        let mouse=UIPanGestureRecognizer(target:self,action:#selector(drag(_:)))
        mouse.allowedTouchTypes=[NSNumber(value:UITouch.TouchType.indirectPointer.rawValue)]
        mouse.minimumNumberOfTouches=1;mouse.maximumNumberOfTouches=1;mouse.delegate=self
        addGestureRecognizer(mouse)
        let hold=UILongPressGestureRecognizer(target:self,action:#selector(drag(_:)))
        hold.minimumPressDuration=0.28;hold.allowableMovement=10
        hold.allowedTouchTypes=[NSNumber(value:UITouch.TouchType.direct.rawValue),NSNumber(value:UITouch.TouchType.pencil.rawValue)]
        hold.delegate=self;addGestureRecognizer(hold)
        let tap=UITapGestureRecognizer(target:self,action:#selector(tapped(_:)))
        tap.require(toFail:mouse);tap.require(toFail:hold);addGestureRecognizer(tap)
        accessibilityLabel="Audio clip selection area"
        accessibilityHint="Drag with a pointer, or hold then drag with a finger, to select audio clips."
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func tapped(_ gesture:UITapGestureRecognizer) { onTap?(gesture.location(in:self)) }
    @objc private func drag(_ gesture:UIGestureRecognizer) {
        let point=gesture.location(in:self)
        switch gesture.state {
        case .began:
            active=true;origin=point
            if let pan=gesture as? UIPanGestureRecognizer {
                let translation=pan.translation(in:self)
                origin=CGPoint(x:point.x-translation.x,y:point.y-translation.y)
            }
            draw(to:point);onSelection?(origin,point,.began)
        case .changed: if active { draw(to:point);onSelection?(origin,point,.changed) }
        case .ended: if active { active=false;outline.path=nil;onSelection?(origin,point,.ended) }
        case .cancelled,.failed: if active { active=false;outline.path=nil;onSelection?(origin,point,.cancelled) }
        default:break
        }
    }
    private func draw(to point:CGPoint) {
        let rect=CGRect(x:min(origin.x,point.x),y:min(origin.y,point.y),width:max(1,abs(point.x-origin.x)),height:max(1,abs(point.y-origin.y)))
        CATransaction.begin();CATransaction.setDisableActions(true)
        outline.path=UIBezierPath(rect:rect).cgPath;CATransaction.commit()
    }
}
@MainActor struct SelectionCommands: View {
    @EnvironmentObject var s:Studio
    var body:some View {
        Group {
            Group {
            Button("Copy"){s.copySelection()}.disabled(s.selectedClips.isEmpty)
            Button("Cut"){s.cutSelection()}.disabled(s.selectedClips.isEmpty)
            Button("Paste at Cursor"){s.pasteSelection()}.disabled(s.clipboard.isEmpty)
            Button("Duplicate Group After Selection"){s.duplicateClip()}.disabled(s.selectedClips.isEmpty)
            Button("Split Selected at Cursor"){s.splitClip()}.disabled(s.selectedClips.isEmpty)
            }
            Divider()
            Button("Add 10 ms Edge Fades"){s.setSelectionFades(0.01)}.disabled(s.selectedClips.isEmpty)
            Button("Cycle Fade Curve"){s.cycleSelectedFadeCurves()}.disabled(s.selectedClips.isEmpty)
            Button("Remove Edge Fades"){s.setSelectionFades(0)}.disabled(s.selectedClips.isEmpty)
            Divider()
            Button("Delete Selected",role:.destructive){s.deleteClip()}.disabled(s.selectedClips.isEmpty)
            Button("Clear Selection"){s.clearClipSelection()}
        }.disabled(s.busy || s.recording)
    }
}
