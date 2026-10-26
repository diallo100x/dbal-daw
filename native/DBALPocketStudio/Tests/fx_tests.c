#include "../Engine/PocketFX.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
 assert(px_create(0)==NULL);assert(px_create(NAN)==NULL);
 PFX *fx=px_create(48000);assert(fx);
 float l[257],r[257];
 for(int mode=-1;mode<6;mode++){
  px_set(fx,mode,.7f,mode==0?0:1,.0625);
  for(int block=0;block<1000;block++){
   for(int i=0;i<257;i++){l[i]=sinf((float)(block*257+i)*.08f);r[i]=l[i]*.5f;}
   px_process(fx,l,r,257,120,(double)block*257/24000);
   for(int i=0;i<257;i++){assert(isfinite(l[i])&&isfinite(r[i]));assert(fabsf(l[i])<=1.001f);assert(fabsf(r[i])<=.501f);}
  }
 }
 px_set(fx,2,0,0,.25);
 for(int i=0;i<257;i++){l[i]=.25f;r[i]=-.5f;}
 px_process(fx,l,r,257,90,0);
 for(int i=0;i<257;i++){assert(l[i]==.25f&&r[i]==-.5f);}
 px_set(fx,4,.5f,1,.25);
 for(int i=0;i<257;i++){l[i]=1;r[i]=1;}
 px_process(fx,l,r,257,120,.2);assert(l[256]<.01f);
 px_destroy(fx);px_destroy(NULL);
 puts("PASS: all XY DSP modes, stereo bounds, ring wrap, dry mix and tempo gate (ASan/UBSan).");
 return 0;
}
