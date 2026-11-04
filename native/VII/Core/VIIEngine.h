#ifndef DBAL_VII_ENGINE_H
#define DBAL_VII_ENGINE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    float sampleRate, phase, envelope, frequency, targetFrequency;
    float ring[2048];
    uint32_t writeIndex, filled, samplesUntilAnalysis;
    float threshold, tracking, wet;
    int voiced;
} VIIEngine;
void vii_init(VIIEngine *v, float sampleRate);
void vii_process(VIIEngine *v, const float *input, float *output, uint32_t frames);
#ifdef __cplusplus
}
#endif
#endif
