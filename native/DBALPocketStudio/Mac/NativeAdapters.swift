import SwiftUI
import AppKit
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

@MainActor struct ImportPicker:View {
    let types:[UTType]
    let asCopy:Bool
    let picked:(URL)->Void
    @Environment(\.presentationMode) var presentation
    var body:some View {
        Text("Choose a file…").frame(width:250,height:80).onAppear{
            let panel=NSOpenPanel();panel.canChooseDirectories=types.contains(.folder);panel.canChooseFiles = !panel.canChooseDirectories
            if !panel.canChooseDirectories{panel.allowedContentTypes=types}
            panel.begin{response in if response == .OK,let url=panel.url{picked(url)};presentation.wrappedValue.dismiss()}
        }
    }
}
@MainActor struct WaveformHandles:NSViewRepresentable {
    var fadeInWidth:Double
    var fadeOutWidth:Double
    var edit:(WaveHandle,Double,Bool,Bool)->Void
    var curve:()->Void
    func makeNSView(context:Context)->MacHandles{MacHandles()}
    func updateNSView(_ view:MacHandles,context:Context){view.leftFade=fadeInWidth;view.rightFade=fadeOutWidth;view.edit=edit;view.curve=curve}
}
@MainActor final class MacHandles:NSView {
    var leftFade=0.0,rightFade=0.0
    var edit:((WaveHandle,Double,Bool,Bool)->Void)?
    var curve:(()->Void)?
    var origin=CGPoint.zero
    var mode:WaveHandle?
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{
        let p=convert(point,from:superview)
        guard bounds.contains(p) else{return nil}
        let fade=p.x<=leftFade || p.x>=bounds.width-rightFade
        return p.x<18 || p.x>bounds.width-18 || (NSEvent.modifierFlags.contains(.shift) && fade) ? self:nil
    }
    override func mouseDown(with event:NSEvent){
        origin=convert(event.locationInWindow,from:nil)
        if event.modifierFlags.contains(.shift){curve?();return}
        let left=origin.x<bounds.width/2
        mode=(origin.y<20 || origin.y>bounds.height-20) ? (left ? .fadeIn:.fadeOut):(left ? .trimLeft:.trimRight)
    }
    override func mouseDragged(with event:NSEvent){if let mode=mode{edit?(mode,convert(event.locationInWindow,from:nil).x-origin.x,false,false)}}
    override func mouseUp(with event:NSEvent){if let mode=mode{edit?(mode,convert(event.locationInWindow,from:nil).x-origin.x,true,false)};mode=nil}
}
struct MacPluginController:NSViewControllerRepresentable {
    let controller:NSViewController
    func makeNSViewController(context:Context)->NSViewController{controller}
    func updateNSViewController(_ view:NSViewController,context:Context){}
}
struct MacParameterEditor:View {
    let unit:AVAudioUnit
    var body:some View {
        ScrollView {VStack(alignment:.leading){
            Text("Audio Unit Parameters").font(.headline)
            if let tree=unit.auAudioUnit.parameterTree {
                ForEach(tree.allParameters,id:\.address){parameter in MacParameterRow(parameter:parameter)}
            }else{Text("This plugin exposes no generic parameters.")}
        }.padding()}.frame(minWidth:400,minHeight:300)
    }
}
struct MacParameterRow:View {
    let parameter:AUParameter
    @State private var value=0.0
    var body:some View {
        HStack{Text(parameter.displayName).frame(width:160,alignment:.leading)
            if parameter.maxValue>parameter.minValue {
                Slider(value:$value,in:Double(parameter.minValue)...Double(parameter.maxValue)).onChange(of:value){parameter.value=Float($0)}
            }
            Text(parameter.string(fromValue:nil)).font(.caption)
        }.onAppear{value=Double(parameter.value)}
    }
}
