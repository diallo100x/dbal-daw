#include "VIIEngine.h"
#include <math.h>
#include <string.h>
#define VII_PI 3.14159265358979323846f

void vii_init(VIIEngine *v, float sampleRate) {
    memset(v, 0, sizeof(*v));
    v->sampleRate = sampleRate > 1000 ? sampleRate : 48000;
    v->threshold = 0.008f;
    v->wet = 1.0f;
    v->samplesUntilAnalysis = 512;
}
static void analyze(VIIEngine *v) {
    // Downsampled autocorrelation with normalized periodicity check.
    // Monophonic pitched voice/whistle only; not polyphonic transcription.
    if (v->filled < 2048) return;
    const int stride = 4, length = 512;
    float x[length], rms = 0;
    for (int i=0; i<length; ++i) {
        x[i] = v->ring[(v->writeIndex + i*stride) & 2047];
        rms += x[i]*x[i];
    }
    rms = sqrtf(rms / length);
    if (rms < v->threshold) { v->voiced=0; return; }
    const float rate = v->sampleRate / stride;
    int minLag = (int)(rate / 900.0f);
    int maxLag = (int)(rate / 80.0f);
    if (minLag < 8) minLag = 8;
    if (maxLag > 180) maxLag = 180;
    float best = 0;
    int bestLag = 0;
    for (int lag=minLag; lag<=maxLag; ++lag) {
        double dot=0, a=0, b=0;
        for (int i=0; i<length-lag; ++i) {
            double s=x[i], t=x[i+lag];
            dot+=s*t; a+=s*s; b+=t*t;
        }
        float corr = (float)(dot / sqrt(a*b+1e-20));
        // Prefer shorter periods among near-equal candidates, reducing octave errors.
        if (corr > best + 0.012f) { best=corr; bestLag=lag; }
    }
    if (bestLag && best > 0.73f) {
        v->targetFrequency = rate / bestLag;
        v->tracking = best;
        v->voiced = 1;
    } else v->voiced = 0;
}
void vii_process(VIIEngine *v, const float *input, float *output, uint32_t frames) {
    if (!v || !input || !output) return;
    const float sr=v->sampleRate;
    for (uint32_t i=0;i<frames;++i) {
        const float in=input[i];
        v->ring[v->writeIndex] = in;
        v->writeIndex = (v->writeIndex+1)&2047;
        if (v->filled < 2048) ++v->filled;
        if (--v->samplesUntilAnalysis == 0) {
            analyze(v);
            v->samplesUntilAnalysis=512;
        }
        float amp = v->voiced ? fminf(1.0f, fabsf(in)*7.0f) : 0;
        v->envelope += (amp-v->envelope)*(amp>v->envelope ? 0.004f : 0.0007f);
        if (v->targetFrequency > 0) {
            if (v->frequency <= 0) v->frequency=v->targetFrequency;
            v->frequency += (v->targetFrequency-v->frequency)*0.0015f;
        }
        v->phase += v->frequency/sr;
        if (v->phase >= 1.0f) v->phase -= floorf(v->phase);
        // Original, lightweight reed-like additive tone; replace with DNA/VTI engine later.
        const float p=2*VII_PI*v->phase;
        const float synth=(sinf(p)+0.27f*sinf(2*p)+0.09f*sinf(3*p))*0.5f*v->envelope;
        output[i] = in*(1-v->wet) + synth*v->wet;
    }
}
