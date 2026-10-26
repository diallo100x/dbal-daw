#import "AudioGraphGuard.h"

NSString *DBALConnectAudioNodes(AVAudioEngine *engine, AVAudioNode *source, AVAudioNode *destination, AVAudioFormat *format) {
    @try {
        NSString *route=[NSString stringWithFormat:@"%@ (%lu outputs) -> %@ (%lu inputs)",source,(unsigned long)source.numberOfOutputs,destination,(unsigned long)destination.numberOfInputs];
        NSLog(@"DBAL connect: %@",route);
        if (source.numberOfOutputs == 0) return [@"Audio source has no output bus: " stringByAppendingString:route];
        if (destination.numberOfInputs == 0 && ![destination isKindOfClass:AVAudioMixerNode.class]) return [@"Audio destination has no input bus: " stringByAppendingString:route];
        [engine connect:source to:destination format:format];
        return nil;
    } @catch (NSException *exception) {
        NSLog(@"DBAL connection rejected: %@ -> %@: %@",source,destination,exception.reason);
        return [NSString stringWithFormat:@"Audio connection rejected (%@ -> %@): %@",source,destination,exception.reason ?: exception.name];
    }
}
NSString *DBALPrepareAndStartAudioEngine(AVAudioEngine *engine) {
    @try {
        [engine prepare];
        NSError *error=nil;
        if (![engine startAndReturnError:&error]) return error.localizedDescription ?: @"Audio engine could not start.";
        return nil;
    } @catch (NSException *exception) {
        [engine stop];
        NSLog(@"DBAL engine start rejected: %@",exception.reason);
        return exception.reason ?: exception.name;
    }
}
