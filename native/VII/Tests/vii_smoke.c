#include "../Core/VIIEngine.h"
#include <math.h>
#include <stdio.h>
#define PI 3.14159265358979323846
int main(void) {
    VIIEngine e; vii_init(&e,48000);
    float in[256],out[256];
    double energy=0;
    for(int b=0;b<240;++b){
        for(int i=0;i<256;++i){
            int n=b*256+i;
            in[i]=0.25f*sinf((float)(2*PI*220*n/48000));
        }
        vii_process(&e,in,out,256);
        for(int i=0;i<256;++i)energy+=out[i]*out[i];
    }
    printf("VII pitch %.1f Hz; output energy %.2f; voiced %d\n",e.targetFrequency,energy,e.voiced);
    if(!e.voiced || fabsf(e.targetFrequency-220)>15 || energy<1) return 1;
    return 0;
}
