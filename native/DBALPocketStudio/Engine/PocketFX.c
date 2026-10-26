#include "PocketFX.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <math.h>
struct PFX {double rate;int size,write,filled,lastMode,repeating,captured,repeatStart,repeatLength,repeatPos;float *left,*right,filter[2],gate;atomic_int mode;_Atomic float x,y;_Atomic double division;};
PFX *px_create(double rate){if(!isfinite(rate)||rate<8000||rate>192000)return NULL;PFX*f=calloc(1,sizeof(*f));if(!f)return NULL;f->rate=rate;f->size=(int)(rate*8)+2;f->left=calloc((size_t)f->size,sizeof(float));f->right=calloc((size_t)f->size,sizeof(float));if(!f->left||!f->right){px_destroy(f);return NULL;}atomic_init(&f->mode,-1);atomic_init(&f->x,.5f);atomic_init(&f->y,.5f);atomic_init(&f->division,.25);f->lastMode=-2;f->gate=1;return f;}
void px_destroy(PFX*f){if(f){free(f->left);free(f->right);free(f);}}
void px_set(PFX*f,int mode,float x,float y,double div){if(!f)return;atomic_store(&f->x,fminf(1,fmaxf(0,x)));atomic_store(&f->y,fminf(1,fmaxf(0,y)));atomic_store(&f->division,fmin(4,fmax(.0625,div)));atomic_store(&f->mode,mode);}
void px_process(PFX*f,float*l,float*r,int frames,double tempo,double beat){
 if(!f||!l||!r||tempo<=0||!isfinite(tempo)||!isfinite(beat))return;
 int mode=atomic_load(&f->mode);float x=atomic_load(&f->x),wet=atomic_load(&f->y);double division=atomic_load(&f->division);
 int length=(int)fmin(f->size-2,fmax(16,division*60/tempo*f->rate));
 if(mode!=f->lastMode||length!=f->repeatLength){f->captured=0;f->repeating=0;f->repeatPos=0;f->repeatLength=length;f->lastMode=mode;}
 for(int i=0;i<frames;i++){
  float dry[2]={l[i],r[i]},out[2]={dry[0],dry[1]};
  double b=beat+(double)i/f->rate*tempo/60,phase=b/division-floor(b/division);
  if(mode==1){
   if(!f->repeating){f->captured++;if(f->captured>=length){f->left[f->write]=dry[0];f->right[f->write]=dry[1];f->write=(f->write+1)%f->size;f->repeatStart=(f->write-length+f->size)%f->size;f->repeatPos=0;f->repeating=1;}}
   if(f->repeating){int j=(f->repeatStart+f->repeatPos)%f->size;float fade=fminf(1,fminf((float)f->repeatPos/64,(float)(length-f->repeatPos-1)/64));out[0]=f->left[j]*fade;out[1]=f->right[j]*fade;f->repeatPos=(f->repeatPos+1)%length;}
  }else if(mode==2||mode==3){
   double cutoff=40*pow(400,x);if(mode==3)cutoff=200*pow(20,.5+.5*sin(b/division*6.28318530718));
   float a=(float)(1-exp(-6.28318530718*fmin(cutoff,f->rate*.45)/f->rate));
   for(int c=0;c<2;c++){f->filter[c]+=a*(dry[c]-f->filter[c]);out[c]=f->filter[c];}
  }else if(mode==4){float target=phase<.5?1:0;f->gate+=.02f*(target-f->gate);out[0]*=f->gate;out[1]*=f->gate;
  }else if(mode==5){
   double delay=f->rate*(.001+.004*(1+sin(b/division*6.28318530718)));
   double position=f->write-delay;while(position<0)position+=f->size;int a=(int)position,j=(a+1)%f->size;float blend=(float)(position-a);
   out[0]=.5f*(dry[0]+f->left[a]*(1-blend)+f->left[j]*blend);out[1]=.5f*(dry[1]+f->right[a]*(1-blend)+f->right[j]*blend);
  }
  // Repeater holds its captured region. Other modes continuously refresh history.
  if(mode!=1||!f->repeating){f->left[f->write]=dry[0];f->right[f->write]=dry[1];f->write=(f->write+1)%f->size;}
  l[i]=dry[0]*(1-wet)+out[0]*wet;r[i]=dry[1]*(1-wet)+out[1]*wet;
 }
}
