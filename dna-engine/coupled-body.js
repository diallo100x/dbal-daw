// Original DBAL DSP: a shaped force excites a modal object, whose output
// drives a second modal body. One-way coupling is bounded and has no feedback.
const clamp=(x,a=0,b=1)=>Math.min(b,Math.max(a,x));
export class CoupledBody {
 constructor(model,rate){this.model=model;this.rate=rate;this.frame=0;this.age=0;this.airPhase=0;this.primary=Array.from({length:model.modes.length},()=>({y1:0,y2:0,a1:0,a2:0,b:0}));this.secondary=Array.from({length:model.coupledBody.modes.length},()=>({y1:0,y2:0,a1:0,a2:0,b:0}));}
 tick(hz,controls,filteredNoise){
  const m=this.model,b=m.coupledBody,sr=this.rate,v=clamp(controls.velocity??.8),hard=clamp(controls.hardness??m.hardness),position=clamp(controls.position??m.position,.02,.98),damp=clamp(controls.damping??.5),rich=clamp(controls.richness??.5),noise=clamp(controls.noise??m.noise),response=clamp(controls.velocityResponse??b.velocityResponse),coupling=clamp(controls.coupling??b.coupling),mix=clamp(controls.bodyMix??b.mix),follow=clamp(controls.resonatorFollow??b.follow);
  if(this.frame%32===0){
   const bodyHz=b.referenceHz*Math.pow(hz/b.referenceHz,follow),energy=clamp(.35+.65*hard+.35*response*v+.25*(rich-.5),.15,1.35);
   for(let group=0;group<2;group++){
    const modes=group?b.modes:m.modes,states=group?this.secondary:this.primary;
    for(let i=0;i<modes.length;i++){
     const mode=modes[i],state=states[i],stiff=group?1:Math.sqrt((1+b.inharmonicity*mode.ratio**2)/(1+b.inharmonicity));
     const frequency=(group?bodyHz:hz)*mode.ratio*stiff;
     if(frequency>=sr*.45){state.b=0;state.y1=state.y2=0;continue;}
     const t60=mode.t60*(1.5-damp)*(1+response*(v-.5)*.5)/(1+(group?0:b.materialLoss)*Math.sqrt(mode.ratio));
     const radius=Math.exp(-6.907755/(t60*sr)),angle=2*Math.PI*frequency/sr;
     state.a1=2*radius*Math.cos(angle);state.a2=-radius*radius;
     state.b=group?2*(1-radius)*Math.sin(angle)*mode.gain:Math.sin(angle)*mode.gain*Math.pow(energy,Math.log2(Math.max(1,mode.ratio)))*(.2+.8*Math.abs(Math.sin(Math.PI*position*(i+1))));
    }
   }
  }
  const contact=b.contactSeconds*(1.4-hard)*Math.max(.25,1-.65*response*v);
  let force=b.excitation==='pluck'?(this.frame===0?1:0):this.age<contact?2*Math.sin(Math.PI*this.age/contact)**2/(contact*sr):0;
  force+=filteredNoise*noise*(.04+.12*v)*Math.exp(-this.age/Math.max(.0001,contact*3));
  if(b.excitation==='air'){this.airPhase=(this.airPhase+2*Math.PI*hz/sr)%(2*Math.PI);force+=filteredNoise*noise*.012+Math.sin(this.airPhase)*.002;}
  let primary=0,normal=0;
  for(let i=0;i<this.primary.length;i++){const s=this.primary[i];const y=clamp(s.a1*s.y1+s.a2*s.y2+force*s.b,-8,8);s.y2=s.y1;s.y1=y;primary+=y;normal+=m.modes[i].gain;}
  primary/=Math.max(1,normal*.6);
  let body=0,bodyNormal=0;
  for(let i=0;i<this.secondary.length;i++){const s=this.secondary[i],y=clamp(s.a1*s.y1+s.a2*s.y2+primary*coupling*s.b,-8,8);s.y2=s.y1;s.y1=y;body+=y;bodyNormal+=b.modes[i].gain;}
  body/=Math.max(1,bodyNormal);this.frame++;this.age+=1/sr;
  return primary*(1-.25*mix)+body*mix*2;
 }
}
