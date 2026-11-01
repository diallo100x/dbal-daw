// User-supplied harmonic recipes; authored tone profiles, not pickup measurements.
export const PICKUP_PROFILES=[
 null,
 [1,.75,.4,.35,.12,.08,.02,.01,0,0],
 [.45,.68,.82,.95,.7,.62,.48,.35,.15,.1],
 [.85,.7,.65,.6,.55,.5,.45,.4,.35,.3]
];
export const SCALAR_DEFAULTS={pickup:0,vibratoDepth:0,vibratoRate:5.2,bodyTexture:0,room:0,slideFrom:-2,auditionMidi:66};
export function scalarControls(dna){return {...SCALAR_DEFAULTS,...dna.extensions?.scalarControls};}
export function validateScalarControls(c){
 if(!c||typeof c!=='object'||Array.isArray(c))throw Error('Invalid guitar controls');
 for(const [key,lo,hi] of [['pickup',0,3],['vibratoDepth',0,1],['vibratoRate',.5,9],['bodyTexture',0,1],['room',0,1],['slideFrom',-12,12],['auditionMidi',40,88]])if(key in c&&(!Number.isFinite(c[key])||c[key]<lo||c[key]>hi||(['pickup','auditionMidi'].includes(key)&&!Number.isInteger(c[key]))))throw Error(`Invalid guitar ${key}`);
 return c;
}
// Compact shared-room comb network. Frequencies/time remain independent of pitch.
export class GuitarRoom {
 constructor(rate){this.lines=[.0297,.0371,.0411,.0437].map(t=>new Float32Array(Math.max(2,Math.round(rate*t))));this.indices=[0,0,0,0];this.low=[0,0,0,0];}
 reset(){for(const line of this.lines)line.fill(0);this.indices.fill(0);this.low.fill(0);}
 tick(input,amount){let wet=0;for(let j=0;j<4;j++){const line=this.lines[j],at=this.indices[j],old=line[at];this.low[j]+=.35*(old-this.low[j]);line[at]=Math.tanh(input*.22+this.low[j]*.74);wet+=old;this.indices[j]=(at+1)%line.length;}return input*(1-.18*amount)+wet*.45*amount;}
}
