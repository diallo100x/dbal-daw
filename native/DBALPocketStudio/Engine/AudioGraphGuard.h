#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
// nil means success; exception text is returned as a normal host error.
FOUNDATION_EXPORT NSString * _Nullable DBALConnectAudioNodes(AVAudioEngine *engine, AVAudioNode *source, AVAudioNode *destination, AVAudioFormat * _Nullable format);
FOUNDATION_EXPORT NSString * _Nullable DBALPrepareAndStartAudioEngine(AVAudioEngine *engine);
NS_ASSUME_NONNULL_END
