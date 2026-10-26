#import "../Engine/AudioGraphGuard.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        AVAudioEngine *engine=[AVAudioEngine new];
        AVAudioPlayerNode *source=[AVAudioPlayerNode new],*invalid=[AVAudioPlayerNode new];
        [engine attachNode:source];[engine attachNode:invalid];
        // A player has outputs but no inputs: this must become an error, not an exception.
        assert(invalid.numberOfInputs==0);
        NSString *rejected=DBALConnectAudioNodes(engine,source,invalid,nil);
        assert(rejected!=nil && [rejected containsString:@"no input bus"]);
        AVAudioFormat *stereo=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
        NSString *accepted=DBALConnectAudioNodes(engine,source,engine.mainMixerNode,stereo);
        assert(accepted==nil);
        NSLog(@"PASS: zero-input destination rejected without exception; mixer connection accepted.");
    }
    return 0;
}
