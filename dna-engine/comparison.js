import {serializable,importReflection} from './dna.js?v=0.8.3';

// Playable comparison files are explicitly separate from audio-free DNA Reflections.
const encode=bytes=>{let result='';for(let i=0;i<bytes.length;i+=16384)result+=String.fromCharCode(...bytes.subarray(i,i+16384));return btoa(result)};
const decode=base64=>{const text=atob(base64),bytes=new Uint8Array(text.length);for(let i=0;i<text.length;i++)bytes[i]=text.charCodeAt(i);return bytes};
function encodeClip(midi,clip){return {midi,sampleRate:clip.sampleRate,channels:Array.from({length:clip.numberOfChannels},(_,i)=>{
  const samples=clip.getChannelData(i),bytes=new Uint8Array(samples.buffer,samples.byteOffset,samples.byteLength);
  return encode(bytes);
})}}
export function saveComparison(dna,clips,hybridMode,layerClips=new Map()){
  const audio=[];
  for(const [midi,clip] of clips){
    if(!dna.anchors.some(a=>a.midi===midi))continue;
    audio.push(encodeClip(midi,clip));
  }
  const audioLayers=[];
  for(const [key,clip] of layerClips){const [layer,note]=key.split(':'),midi=Number(note);
    if(!dna.performance?.layers?.[layer]?.some(a=>a.midi===midi))continue;
    audioLayers.push({layer,...encodeClip(midi,clip)});
  }
  return {format:'instrument-dna-playable-comparison',version:1,hybridMode,reflection:serializable(dna),audio,audioLayers};
}
export function loadComparison(data,makeBuffer){
  if(data?.format!=='instrument-dna-playable-comparison'||data.version!==1||!Array.isArray(data.audio)||data.audio.length>127||data.audioLayers&&!Array.isArray(data.audioLayers)||data.audioLayers?.length>127)throw Error('Invalid playable comparison');
  const dna=importReflection(data.reflection),clips=new Map(),layerClips=new Map();
  for(const [entry,isLayer] of [...data.audio.map(x=>[x,false]),...(data.audioLayers||[]).map(x=>[x,true])]){
    const destination=isLayer?layerClips:clips,key=isLayer?`${entry.layer}:${entry.midi}`:entry.midi;
    const anchors=isLayer?dna.performance.layers[entry.layer]:dna.anchors;
    if(!Number.isInteger(entry.midi)||!anchors?.some(a=>a.midi===entry.midi)||destination.has(key)||!Number.isInteger(entry.sampleRate)||entry.sampleRate<8000||entry.sampleRate>192000||!Array.isArray(entry.channels)||entry.channels.length<1||entry.channels.length>8)throw Error('Invalid comparison anchor');
    const channels=entry.channels.map(encoded=>{
      if(typeof encoded!=='string'||encoded.length>32_000_000)throw Error('Comparison clip is too large');
      const bytes=decode(encoded);if(bytes.length%4||bytes.length<entry.sampleRate*.08*4||bytes.length>entry.sampleRate*15*4)throw Error('Invalid comparison clip length');
      const aligned=bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),samples=new Float32Array(aligned);
      if(!samples.every(Number.isFinite))throw Error('Invalid comparison audio');
      return samples;
    });
    if(channels.some(ch=>ch.length!==channels[0].length))throw Error('Inconsistent audio channels');
    const clip=makeBuffer(channels.length,channels[0].length,entry.sampleRate);
    channels.forEach((samples,i)=>clip.copyToChannel(samples,i));destination.set(key,clip);
  }
  return {dna,clips,layerClips,hybridMode:['HybridOriginal','HybridStretch','Mallet','Physical'].includes(data.hybridMode)?data.hybridMode:'HybridOriginal'};
}
