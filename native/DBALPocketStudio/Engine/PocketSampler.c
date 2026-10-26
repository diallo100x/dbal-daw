#include "PocketSampler.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define REGIONS 256
#define VOICES 64
#define QUEUE 1024
typedef struct { float *pcm; int frames,lo,hi,root,lv,hv,ls,le; double rate; float gain,pan,release,tune; int mode; } Region;
typedef struct { int active,note,region,released; double pos,step,phase; float level,env; uint32_t noise; int age; } Voice;
typedef struct { int note,vel; } Event;
struct PSampler { double rate; int count,limit,mode; Region regions[REGIONS]; Voice voices[VOICES]; Event events[QUEUE]; atomic_uint head,tail; };
PSampler *ps_create(double rate,int voices,int mode) {
 if(rate<=0) return NULL;
 PSampler *s=calloc(1,sizeof(*s)); if(!s)return NULL;
 s->rate=rate;s->limit=voices<1?1:(voices>VOICES?VOICES:voices);s->mode=mode;
 atomic_init(&s->head,0);atomic_init(&s->tail,0);return s;
}
void ps_destroy(PSampler *s) { if(!s)return;for(int i=0;i<s->count;i++)free(s->regions[i].pcm);free(s); }
int ps_region(PSampler *s,const float *pcm,int frames,double rate,int lo,int hi,int root,int lv,int hv,float db,float pan,int ls,int le,float release,float tune,int mode) {
 if(!s||!pcm||frames<2||s->count==REGIONS||rate<=0||lo>hi||lv>hv)return 0;
 float *copy=malloc(sizeof(float)*(size_t)frames);if(!copy)return 0;memcpy(copy,pcm,sizeof(float)*(size_t)frames);
 Region r={copy,frames,lo,hi,root,lv,hv,ls,le,rate,powf(10,db/20),fmaxf(-1,fminf(1,pan)),fmaxf(.005f,release),tune,mode};
 if(ls<0||le<=ls||le>frames){r.ls=0;r.le=0;} s->regions[s->count++]=r;return 1;
}
int ps_midi(PSampler *s,int note,int vel){
 if(!s||note<0||note>128||(note==128&&vel!=0)||vel<0||vel>127)return 0;
 unsigned h=atomic_load_explicit(&s->head,memory_order_relaxed), n=(h+1)%QUEUE;
 if(n==atomic_load_explicit(&s->tail,memory_order_acquire))return 0;
 s->events[h]=(Event){note,vel};atomic_store_explicit(&s->head,n,memory_order_release);return 1;
}
static void on(PSampler*s,int note,int vel,int ri){
 int slot=0;for(int i=0;i<s->limit;i++){if(!s->voices[i].active){slot=i;break;}if(s->voices[i].age>s->voices[slot].age)slot=i;}
 Voice v={0};v.active=1;v.note=note;v.region=ri;v.level=(float)vel/127*.3f;v.env=1;v.noise=12345u+(uint32_t)note;
 if(ri>=0){Region*r=&s->regions[ri];v.step=pow(2,((double)note-r->root+r->tune/100)/12)*r->rate/s->rate;}
 else v.step=440*pow(2,((double)note-69)/12)/s->rate;
 s->voices[slot]=v;
}
void ps_render(PSampler*s,float*l,float*r,int frames){
 if(!s||!l||!r||frames<0)return;
 memset(l,0,sizeof(float)*(size_t)frames);memset(r,0,sizeof(float)*(size_t)frames);
 unsigned t=atomic_load_explicit(&s->tail,memory_order_relaxed),h=atomic_load_explicit(&s->head,memory_order_acquire);
 while(t!=h){Event e=s->events[t];if(e.note==128){for(int j=0;j<s->limit;j++)s->voices[j].released=1;}
 else if(e.vel==0){for(int j=0;j<s->limit;j++)if(s->voices[j].note==e.note && !(s->voices[j].region>=0 && s->regions[s->voices[j].region].mode==1))s->voices[j].released=1;}
 else if(s->count){for(int j=0;j<s->count;j++){Region*z=&s->regions[j];if(e.note>=z->lo&&e.note<=z->hi&&e.vel>=z->lv&&e.vel<=z->hv)on(s,e.note,e.vel,j);}}
 else on(s,e.note,e.vel,-1);
 t=(t+1)%QUEUE;}
 atomic_store_explicit(&s->tail,t,memory_order_release);
 for(int j=0;j<s->limit;j++){Voice*v=&s->voices[j];if(!v->active)continue;Region*z=v->region>=0?&s->regions[v->region]:NULL;
 float pan=z?z->pan:0,gl=sqrtf((1-pan)*.5f),gr=sqrtf((1+pan)*.5f);
 float releaseCoef=expf(-1/(float)(s->rate*(z?z->release:.08)));
 for(int i=0;i<frames;i++){
 float x=0;
 if(z){if(z->le>z->ls&&(!v->released||z->mode==2)&&v->pos>=z->le)v->pos=z->ls+fmod(v->pos-z->ls,z->le-z->ls);
 int k=(int)v->pos;if(k>=z->frames-1){v->active=0;break;}float f=(float)(v->pos-k);x=(z->pcm[k]*(1-f)+z->pcm[k+1]*f)*z->gain;v->pos+=v->step;
 }else{v->phase+=v->step;v->phase-=floor(v->phase);x=(float)(sin(v->phase*6.28318530718)*.8+sin(v->phase*12.56637061436)*.2);}
 if(v->released)v->env*=releaseCoef;
 if(v->env<.0001f){v->active=0;break;}float attack=fminf(1,(float)v->age/(float)(s->rate*.003));
 x*=v->level*v->env*attack;l[i]+=x*gl;r[i]+=x*gr;v->age++;
 }
 }
}
struct PCounter { atomic_int pending,overflow; };
PCounter *pc_create(void){PCounter*c=calloc(1,sizeof(*c));if(c){atomic_init(&c->pending,0);atomic_init(&c->overflow,0);}return c;}
void pc_destroy(PCounter*c){free(c);}
int pc_claim(PCounter*c){if(!c)return 0;int old=atomic_fetch_add(&c->pending,1);if(old>=16){atomic_fetch_sub(&c->pending,1);atomic_store(&c->overflow,1);return 0;}return 1;}
void pc_release(PCounter*c){if(c)atomic_fetch_sub(&c->pending,1);}
int pc_overflowed(PCounter*c){return c?atomic_load(&c->overflow):0;}
struct PHost { _Atomic double tempo,beat,seconds,ls,le; atomic_int meter,playing,cycling,recording,manual; };
PHost *ph_create(void){PHost*h=calloc(1,sizeof(*h));if(h){atomic_init(&h->tempo,90);atomic_init(&h->beat,0);atomic_init(&h->seconds,0);atomic_init(&h->ls,0);atomic_init(&h->le,16);atomic_init(&h->meter,4);atomic_init(&h->playing,0);atomic_init(&h->cycling,0);atomic_init(&h->recording,0);atomic_init(&h->manual,0);}return h;}
void ph_destroy(PHost*h){free(h);}
void ph_set(PHost*h,double tempo,int meter,double beat,double seconds,int playing,int cycling,int recording,double ls,double le,int manual){if(!h)return;atomic_store(&h->tempo,tempo);atomic_store(&h->meter,meter);atomic_store(&h->beat,beat);atomic_store(&h->seconds,seconds);atomic_store(&h->playing,playing);atomic_store(&h->cycling,cycling);atomic_store(&h->recording,recording);atomic_store(&h->ls,ls);atomic_store(&h->le,le);atomic_store(&h->manual,manual);}
PHInfo ph_get(PHost*h,double seconds){PHInfo x={90,0,0,16,4,0,0,0};if(!h)return x;x.tempo=atomic_load(&h->tempo);x.beat=atomic_load(&h->beat);x.meter=atomic_load(&h->meter);x.playing=atomic_load(&h->playing);x.cycling=atomic_load(&h->cycling);x.recording=atomic_load(&h->recording);x.loopStart=atomic_load(&h->ls);x.loopEnd=atomic_load(&h->le);if(x.playing&&!atomic_load(&h->manual))x.beat+=fmax(0,seconds-atomic_load(&h->seconds))*x.tempo/60;return x;}
