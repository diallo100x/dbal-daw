#include "../Engine/PocketSampler.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>
static atomic_int producer_done;
static float energy(float*x,int n){float e=0;for(int i=0;i<n;i++){assert(isfinite(x[i]));e+=x[i]*x[i];}return e;}
static void *produce(void*arg){PSampler*s=arg;for(int i=0;i<10000;i++){while(!ps_midi(s,60,100)){}while(!ps_midi(s,60,0)){}}atomic_store(&producer_done,1);return NULL;}
int main(void){
 float l[512],r[512],sample[1024];for(int i=0;i<1024;i++)sample[i]=sinf((float)i*.1f);
 PSampler*s=ps_create(44100,16,0);assert(s);
 ps_render(s,l,r,512);assert(energy(l,512)==0);
 assert(ps_midi(s,60,100));ps_render(s,l,r,512);assert(energy(l,512)>.1f);
 assert(ps_midi(s,60,0));for(int i=0;i<100;i++)ps_render(s,l,r,512);assert(energy(l,512)<.0001f);ps_destroy(s);
 // Key/velocity filtering and stereo panning.
 s=ps_create(44100,4,0);assert(ps_region(s,sample,1024,44100,60,60,60,90,127,0,1,0,1024,.01f,0,0));
 ps_midi(s,59,100);ps_midi(s,60,20);ps_render(s,l,r,512);assert(energy(l,512)==0&&energy(r,512)==0);
 ps_midi(s,60,100);ps_render(s,l,r,512);assert(energy(l,512)==0&&energy(r,512)>.1f);
 // Sustain loop does not read beyond the region on long playback or high pitch.
 for(int i=0;i<1000;i++)ps_render(s,l,r,512);
 ps_midi(s,60,0);for(int i=0;i<100;i++)ps_render(s,l,r,512);assert(energy(r,512)<.0001f);ps_destroy(s);
 // One-shot ignores a note-off but panic still stops it.
 s=ps_create(44100,4,0);assert(ps_region(s,sample,1024,44100,60,60,60,1,127,0,0,0,1024,.005f,0,1));
 ps_midi(s,60,100);ps_render(s,l,r,128);ps_midi(s,60,0);ps_render(s,l,r,128);assert(energy(l,128)>.01f);
 ps_midi(s,128,0);for(int i=0;i<10;i++)ps_render(s,l,r,512);assert(energy(l,512)==0);ps_destroy(s);
 // Bounded queue rejects overflow and resumes after consumption.
 s=ps_create(48000,8,0);int accepted=0;for(int i=0;i<2000;i++)accepted+=ps_midi(s,60,100);assert(accepted==1023);
 ps_render(s,l,r,512);assert(ps_midi(s,128,0));ps_render(s,l,r,512);ps_destroy(s);
 // Invalid regions never allocate/read invalid sample ranges.
 s=ps_create(44100,2,0);assert(!ps_region(s,sample,1,44100,0,127,60,1,127,0,0,0,0,.1f,0,0));assert(!ps_midi(s,-1,100));assert(!ps_midi(s,60,128));ps_destroy(s);
 // Single producer + render consumer stress exercises atomics.
 s=ps_create(44100,16,0);pthread_t thread;assert(!pthread_create(&thread,NULL,produce,s));
 while(!atomic_load(&producer_done)) { ps_render(s,l,r,512); }
 pthread_join(thread,NULL);ps_render(s,l,r,512);ps_destroy(s);
 PCounter*c=pc_create();for(int i=0;i<16;i++)assert(pc_claim(c));assert(!pc_claim(c));assert(pc_overflowed(c));for(int i=0;i<16;i++)pc_release(c);assert(pc_claim(c));pc_release(c);pc_destroy(c);
 PHost*h=ph_create();ph_set(h,120,4,8,100,1,1,0,0,16,0);PHInfo info=ph_get(h,101);assert(fabs(info.beat-10)<.00001);assert(info.meter==4&&info.cycling);
 ph_set(h,120,3,12,100,1,0,1,0,16,1);info=ph_get(h,500);assert(info.beat==12&&info.recording);ph_destroy(h);
 puts("PASS: sampler silence, release, key/velocity ranges, pan, loops, one-shot/panic, queue overflow, concurrent MIDI, recording backpressure, host transport.");return 0;
}
