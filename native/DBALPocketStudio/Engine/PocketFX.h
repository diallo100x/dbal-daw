#pragma once
#include <stdint.h>
typedef struct PFX PFX;
PFX *px_create(double rate);
void px_destroy(PFX *fx);
void px_set(PFX *fx,int mode,float x,float y,double division);
void px_process(PFX *fx,float *left,float *right,int frames,double tempo,double beat);
