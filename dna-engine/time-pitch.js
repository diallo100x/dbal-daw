// Short-note granular resynthesis. The grain's read rate sets pitch, while its
// source position advances in real time, so the recorded vibrato cadence is
// retained. Waveform matching reduces phase discontinuities at grain joins.
export function renderExpressiveNote(input,sampleRate,pitchRatio,durationSeconds,{preserveAttack=false}={}){
  if(!(input instanceof Float32Array)||!Number.isFinite(sampleRate)||sampleRate<=0||!Number.isFinite(pitchRatio)||pitchRatio<.75||pitchRatio>1.34||!Number.isFinite(durationSeconds)||durationSeconds<=0||durationSeconds>4)throw Error('Unsupported note render settings');
  const length=Math.max(1,Math.round(durationSeconds*sampleRate));
  if(input.length<Math.round(sampleRate*.08))throw Error('Source note is too short to stretch');
  if(pitchRatio===1&&length===input.length)return input.slice();
  const out=new Float32Array(length),weights=new Float32Array(length);
  const grain=Math.max(128,Math.min(Math.round(sampleRate*.075),Math.floor((input.length-3)/pitchRatio)));
  const hop=Math.max(32,Math.floor(grain/4));
  const maxStart=Math.max(0,input.length-2-Math.ceil((grain-1)*pitchRatio));
  const looping=length>input.length;
  const loopStart=Math.min(maxStart,Math.round(input.length*.22));
  const loopEnd=Math.max(loopStart+1,Math.min(maxStart,Math.round(input.length*.72)));
  const read=position=>{const p=Math.max(0,Math.min(input.length-2,position)),i=Math.floor(p);return input[i]+(input[i+1]-input[i])*(p-i)};
  for(let at=0;at<length;at+=hop){
    let expected=at;
    if(looping&&expected>loopEnd)expected=loopStart+(expected-loopStart)%(loopEnd-loopStart);
    expected=Math.min(expected,maxStart);
    let best=expected;
    if(at&&at<length-hop){
      let bestScore=-Infinity;
      const radius=Math.min(Math.round(sampleRate*.009),Math.floor(grain/5));
      const from=Math.max(0,Math.round(expected-radius)),to=Math.min(maxStart,Math.round(expected+radius));
      const compare=Math.min(grain/2,length-at),stride=Math.max(4,Math.round(sampleRate/5500));
      for(let candidate=from;candidate<=to;candidate+=3){
        let dot=0,a=0,b=0;
        for(let j=0;j<compare;j+=stride){
          if(!weights[at+j])continue;
          const previous=out[at+j]/weights[at+j],sample=read(candidate+j*pitchRatio);
          dot+=previous*sample;a+=previous*previous;b+=sample*sample;
        }
        const score=a*b>1e-12?dot/Math.sqrt(a*b):-2;
        if(score>bestScore){bestScore=score;best=candidate}
      }
    }
    for(let j=0;j<grain&&at+j<length;j++){
      const window=.5-.5*Math.cos(2*Math.PI*(j+.5)/grain),index=at+j;
      out[index]+=read(best+j*pitchRatio)*window;
      weights[index]+=window;
    }
  }
  for(let i=0;i<length;i++)out[i]=weights[i]>1e-5?out[i]/weights[i]:0;
  if(preserveAttack){
    // A mallet's initial strike is short; keep it outside the grain matching
    // stage and crossfade into the rendered ringing body.
    const core=Math.min(length,Math.round(sampleRate*.03)),blend=Math.min(length-core,Math.round(sampleRate*.012));
    for(let i=0;i<core+blend;i++){
      const direct=read(i*pitchRatio),mix=i<core?1:1-(i-core)/Math.max(1,blend);
      out[i]=direct*mix+out[i]*(1-mix);
    }
  }
  // Short boundary fades eliminate clicks without discarding the recorded attack.
  const fade=Math.min(Math.round(sampleRate*(preserveAttack?.002:.012)),Math.floor(length/8));
  for(let i=0;i<fade;i++)out[i]*=i/fade;
  const endFade=Math.min(Math.round(sampleRate*.012),Math.floor(length/8));
  for(let i=0;i<endFade;i++)out[length-1-i]*=i/endFade;
  return out;
}
