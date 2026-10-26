#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct PSampler PSampler;
PSampler *ps_create(double rate, int voices, int mode);
void ps_destroy(PSampler *s);
/* Bank mutation requires a stopped/disconnected audio engine. Copies mono PCM. */
int ps_region(PSampler *s, const float *pcm, int frames, double rate,
 int low, int high, int root, int lovel, int hivel, float db, float pan,
 int loopStart, int loopEnd, float release, float tune, int playMode);
/* One control-thread producer; render is the only consumer. No render locks. */
int ps_midi(PSampler *s, int note, int velocity);
void ps_render(PSampler *s, float *left, float *right, int frames);
typedef struct PCounter PCounter;
PCounter *pc_create(void);
void pc_destroy(PCounter *c);
int pc_claim(PCounter *c);
void pc_release(PCounter *c);
int pc_overflowed(PCounter *c);
typedef struct PHost PHost;
typedef struct { double tempo,beat,loopStart,loopEnd; int meter,playing,cycling,recording; } PHInfo;
PHost *ph_create(void);
void ph_destroy(PHost *h);
void ph_set(PHost *h,double tempo,int meter,double beat,double seconds,int playing,int cycling,int recording,double loopStart,double loopEnd,int manual);
PHInfo ph_get(PHost *h,double seconds);
#ifdef __cplusplus
}
#endif
