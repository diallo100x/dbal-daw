// Independently authored, deterministic fitting of isolated decaying notes.
import {validatePhysicalModel} from './physical.js?v=0.8.3';
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
export const FIT_VERSION='physical-fit-1';
function spectrum(a,sr){
 let n=1;while(n*2<=Math.min(8192,a.length))n*=2;
 const re=new Float64Array(n),im=new Float64Array(n),offset=Math.min(Math.round(sr*.025),a.length-n);
 for(let i=0;i<n;i++)re[i]=a[offset+i]*(.5-.5*Math.cos(2*Math.PI*i/(n-1)));
 for(let i=1,j=0;i<n;i++){let b=n>>1;for(;j&b;b>>=1)j^=b;j^=b;if(i<j){[re[i],re[j]]=[re[j],re[i]];}}
 for(let size=2;size<=n;size*=2)for(let start=0;start<n;start+=size)for(let j=0;j<size/2;j++){
  const w=-2*Math.PI*j/size,c=Math.cos(w),s=Math.sin(w),p=start+j,q=p+size/2,r=re[q]*c-im[q]*s,t=re[q]*s+im[q]*c;re[q]=re[p]-r;im[q]=im[p]-t;re[p]+=r;im[p]+=t;
 }
 return {n,mag:Array.from({length:n/2},(_,i)=>Math.hypot(re[i],im[i]))};
}
function decay(a,sr,hz){
 const n=Math.min(4096,Math.max(512,Math.round(sr*Math.max(.055,8/hz)))),hop=Math.max(1,Math.round(sr*.045)),points=[];
 for(let start=Math.round(sr*.035);start+n<=a.length&&points.length<60;start+=hop){let re=0,im=0;for(let i=0;i<n;i++){const x=a[start+i]*(.5-.5*Math.cos(2*Math.PI*i/(n-1))),w=2*Math.PI*hz*i/sr;re+=x*Math.cos(w);im+=x*Math.sin(w);}points.push([(start+n/2)/sr,Math.hypot(re,im)/n]);}
 const peak=Math.max(...points.map(p=>p[1]),0),usable=points.filter(p=>p[1]>Math.max(1e-7,peak*.03));
 if(usable.length<5)return null;
 const count=usable.length,sx=usable.reduce((s,p)=>s+p[0],0),sy=usable.reduce((s,p)=>s+Math.log(p[1]),0),sxx=usable.reduce((s,p)=>s+p[0]**2,0),sxy=usable.reduce((s,p)=>s+p[0]*Math.log(p[1]),0),slope=(count*sxy-sx*sy)/(count*sxx-sx*sx),intercept=(sy-slope*sx)/count;
 const total=usable.reduce((s,p)=>s+(Math.log(p[1])-sy/count)**2,0),error=usable.reduce((s,p)=>s+(Math.log(p[1])-intercept-slope*p[0])**2,0),r2=1-error/Math.max(1e-12,total),drop=-slope*(usable.at(-1)[0]-usable[0][0]);
 if(!Number.isFinite(slope)||slope>=0||r2<.8||drop<.65)return null;
 const t60=-Math.log(1000)/slope;if(t60<.02||t60>15)return null;
 return {t60,slope,r2,observedSeconds:usable.at(-1)[0]-usable[0][0],confidence:clamp(r2*Math.min(1,drop/2.3),0,.85)};
}
export function fitPhysicalNote(a,sr,midi,kind='modal'){
 if(!['modal','waveguide'].includes(kind)||!Number.isFinite(sr)||sr<8000||sr>192000||!Number.isInteger(midi)||midi<24||midi>108||a.length<sr*.35||a.length>sr*15||Array.from(a).some(x=>!Number.isFinite(x)))throw Error('Choose a finite isolated note, 0.35–15 seconds, with a known root pitch.');
 const f0=440*2**((midi-69)/12),{n,mag}=spectrum(a,sr),maximum=Math.max(...mag),peaks=[];
 if(maximum<1e-5)throw Error('The reference is silent.');
 for(let i=2;i<mag.length-1;i++)if(mag[i]>maximum*.045&&mag[i]>=mag[i-1]&&mag[i]>mag[i+1]){
  const l=Math.log(mag[i-1]+1e-12),c=Math.log(mag[i]+1e-12),r=Math.log(mag[i+1]+1e-12),bin=i+clamp(.5*(l-r)/(l-2*c+r),-.5,.5),hz=bin*sr/n,ratio=hz/f0;
  if(!Number.isFinite(hz)||ratio<.25||ratio>64||hz>=sr*.45)continue;
  peaks.push({hz,ratio,gain:mag[i]/maximum});
 }
 peaks.sort((a,b)=>b.gain-a.gain);const measured=peaks.slice(0,32).map(p=>{const d=decay(a,sr,p.hz);return d?{...p,...d}:null;}).filter(Boolean).slice(0,16).sort((a,b)=>a.hz-b.hz);
 if(!measured.length)throw Error('No reliable decaying resonances. Use a clean struck/plucked note with a longer tail, not speech, a sustained wind note or a chord.');
 const model={version:1,kind,origin:'analyzed',referenceMidi:midi,continuous:false,hardness:.7,position:.5,noise:0,decay:measured[0].t60,modes:measured.map(p=>({ratio:p.ratio,gain:p.gain,t60:p.t60}))};
 let lossError=null;
 if(kind==='waveguide'){
  const harmonics=measured.filter(p=>Math.abs(p.ratio-Math.round(p.ratio))<.04&&Math.round(p.ratio)<=12);
  if(harmonics.length<2||!harmonics.some(p=>Math.abs(p.ratio-1)<.04))throw Error('String fitting needs a fundamental and at least one decaying harmonic. Try Modal for inharmonic mallet notes.');
  let best=null;
  for(let tone=.05;tone<=.98001;tone+=.005){
   const losses=harmonics.map(p=>f0*Math.log(tone/Math.sqrt(1+(1-tone)**2-2*(1-tone)*Math.cos(2*Math.PI*p.hz/sr))));
   const base=harmonics.reduce((s,p,i)=>s+p.slope-losses[i],0)/harmonics.length;if(base>=0)continue;
   const error=harmonics.reduce((s,p,i)=>s+(p.slope-base-losses[i])**2,0)/harmonics.length;
   if(!best||error<best.error)best={tone,base,error};
  }
  if(!best||-Math.log(1000)/best.base>15)throw Error('The measured decay cannot be represented reliably by this simple string loop. Use Modal or Hybrid.');
  model.waveguideTone=Math.round(best.tone*1000)/1000;model.lossSampleRate=sr;model.decay=clamp(-Math.log(1000)/best.base,.05,15);lossError=Math.sqrt(best.error);
 }
 validatePhysicalModel(model);
 const confidence=Math.min(...measured.map(p=>p.confidence))*(kind==='waveguide'?1/(1+(lossError??0)):.9);
 return {midi,model,analyzerVersion:FIT_VERSION,confidence,measurements:measured,lossError,unsupported:['excitation residual','body/string separation','dispersion','nonlinear response','velocity learning','wind excitation'],recommendation:confidence<.55?`Additional clean reference recommended near MIDI ${midi}.`:null};
}
export function physicalModelAt(dna,midi){
 const fits=dna.extensions?.physicalFits?.anchors??[];const nearest=[...fits].sort((a,b)=>Math.abs(a.midi-midi)-Math.abs(b.midi-midi)||a.midi-b.midi)[0];return nearest?.model??dna.extensions?.physicalModel;
}
