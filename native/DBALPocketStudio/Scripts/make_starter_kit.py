#!/usr/bin/env python3
"""Original deterministic synthesized starter percussion. Assets dedicated to CC0."""
from pathlib import Path
import math,random,wave,struct
root=Path(__file__).resolve().parents[1]/'Resources/StarterKit'
root.mkdir(parents=True,exist_ok=True)
rate=44100
kits=[('Kick',36,.65),('Snare',38,.38),('ClosedHat',42,.12),('OpenHat',46,.65),('LowTom',41,.55),('HighTom',45,.4),('Crash',49,1.2),('Ride',51,.9)]
rng=random.Random(914)
for name,note,duration in kits:
    pcm=[];last=0.;phase=0.
    for i in range(int(duration*rate)):
        t=i/rate;noise=rng.uniform(-1,1);high=noise-last;last=noise
        if name=='Kick':
            hz=48+130*math.exp(-t*40);phase+=2*math.pi*hz/rate
            x=math.sin(phase)*math.exp(-t*9)+.2*high*math.exp(-t*120)
        elif name=='Snare':x=(.65*noise+.35*math.sin(2*math.pi*180*t))*math.exp(-t*15)
        elif 'Tom' in name:x=math.sin(2*math.pi*(100 if name=='LowTom' else 155)*t)*math.exp(-t*10)+.08*noise*math.exp(-t*25)
        elif name in ['ClosedHat','OpenHat']:x=high*.42*math.exp(-t*(45 if name=='ClosedHat' else 7))
        else:x=(high*.32+sum(math.sin(2*math.pi*f*t) for f in [1877,2933,4021,6113])*.07)*math.exp(-t*(4 if name=='Crash' else 6))
        x*=min(1,t/.001)
        pcm.append(struct.pack('<h',int(max(-1,min(1,x*.75))*32767)))
    with wave.open(str(root/(name+'.wav')),'wb') as out:out.setnchannels(1);out.setsampwidth(2);out.setframerate(rate);out.writeframes(b''.join(pcm))
(root/'StarterKit.sfz').write_text('// Original DBAL starter percussion, CC0. GM note numbers.\n'+''.join(f'<region> sample={name}.wav key={note} loop_mode=one_shot ampeg_release=0.08\n' for name,note,_ in kits))
(root/'LICENSE.txt').write_text('DBAL Pocket Studio Starter Kit\nOriginal synthesized sounds created for this project.\nTo the extent possible under law, the authors waive all copyright and related rights in these WAV and SFZ assets under CC0 1.0 Universal.\nhttps://creativecommons.org/publicdomain/zero/1.0/\n')
print('Generated 8 compact percussion samples.')
