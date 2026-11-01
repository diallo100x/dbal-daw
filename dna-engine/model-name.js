export function suggestedModelName(instrument){const clean=String(instrument||'').trim();return clean&&clean!=='unspecified instrument'?`${clean} DNA Model`:'Instrument DNA Model'}
export function modelFilename(name,kind){
  const slug=String(name||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,64).replace(/-$/,'')||'instrument-dna';
  return `${slug}-${kind==='comparison'?'playable-comparison':'reflection'}.json`;
}
