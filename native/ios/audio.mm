#import <AVFAudio/AVFAudio.h>
#include "apple_audio_sink.h"
#include "audio_ring.h"
#include "ps2host/run.h"
#include <memory>
#include <cstring>

namespace {
AVAudioEngine *engine;
AVAudioSourceNode *source;
dispatch_source_t report_timer;
id interruption_observer, configuration_observer;
std::shared_ptr<applehost::AudioRing> ring;
NSString *last_error;
bool opened = false;

void Report() {
    auto active = ring;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSMutableArray *outputs = [NSMutableArray new];
    for (AVAudioSessionPortDescription *port in session.currentRoute.outputs)
        [outputs addObject:port.portType];
    NSDictionary *report = @{
        @"opened": @(opened), @"engine_running": @(engine.isRunning),
        @"error": last_error ?: NSNull.null, @"output_ports": outputs,
        @"output_volume": @(session.outputVolume), @"device_rate": @(session.sampleRate),
        @"source_rate": @48000,
        @"game_frames": @(active ? active->produced.load() : 0),
        @"game_nonzero_frames": @(active ? active->nonzero_input.load() : 0),
        @"rendered_frames": @(active ? active->rendered.load() : 0),
        @"rendered_nonzero_frames": @(active ? active->nonzero_output.load() : 0),
        @"underruns": @(active ? active->underruns.load() : 0),
        @"dropped_frames": @(active ? active->dropped.load() : 0),
        @"timestamp": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date]
    };
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
        writeToURL:[documents URLByAppendingPathComponent:@"native-audio.json"] atomically:YES];
}
void OnMain(dispatch_block_t work) {
    if (NSThread.isMainThread) work(); else dispatch_sync(dispatch_get_main_queue(), work);
}
bool Open() {
    __block bool success = false;
    OnMain(^{
        NSError *error = nil;
        AVAudioSession *session = AVAudioSession.sharedInstance;
        last_error = nil;
        if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error] ||
            ![session setPreferredSampleRate:48000 error:&error] ||
            ![session setPreferredIOBufferDuration:0.01 error:&error] ||
            ![session setActive:YES error:&error]) {
            last_error = error.localizedDescription; Report(); return;
        }
        ring = std::make_shared<applehost::AudioRing>();
        auto audio = ring;
        engine = [AVAudioEngine new];
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
        source = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *silence,
            const AudioTimeStamp *, AVAudioFrameCount count, AudioBufferList *data) {
            if (data->mNumberBuffers != 2 || !data->mBuffers[0].mData || !data->mBuffers[1].mData) {
                for (UInt32 i = 0; i < data->mNumberBuffers; ++i)
                    if (data->mBuffers[i].mData) memset(data->mBuffers[i].mData, 0, data->mBuffers[i].mDataByteSize);
                *silence = YES;
                return noErr;
            }
            audio->Render(static_cast<float*>(data->mBuffers[0].mData), static_cast<float*>(data->mBuffers[1].mData), count);
            *silence = NO;
            return noErr;
        }];
        [engine attachNode:source];
        [engine connect:source to:engine.mainMixerNode format:format];
        engine.mainMixerNode.outputVolume = 1.0;
        [engine prepare];
        opened = success = [engine startAndReturnError:&error];
        if (!success) { last_error = error.localizedDescription; engine = nil; source = nil; }
        if (success) {
            interruption_observer = [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification
                object:session queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
                        ps2host::StopRequested() = true;
                        [engine pause];
                    }
                    Report();
                }];
            configuration_observer = [NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification
                object:engine queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
                    if (opened && !engine.isRunning && !ps2host::StopRequested()) {
                        NSError *restart_error = nil;
                        if (![engine startAndReturnError:&restart_error]) last_error = restart_error.localizedDescription;
                    }
                    Report();
                }];
            report_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(report_timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
            dispatch_source_set_event_handler(report_timer, ^{ Report(); });
            dispatch_resume(report_timer);
        }
        Report();
    });
    return success;
}
void Close() {
    OnMain(^{
        opened = false;
        [engine stop];
        if (report_timer) { dispatch_source_cancel(report_timer); report_timer = nil; }
        if (interruption_observer) [NSNotificationCenter.defaultCenter removeObserver:interruption_observer];
        if (configuration_observer) [NSNotificationCenter.defaultCenter removeObserver:configuration_observer];
        interruption_observer = configuration_observer = nil;
        Report();
        source = nil; engine = nil;
        [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    });
}
void Write(const short* samples, unsigned frames) { if (ring) ring->Push(samples, frames); }
}

namespace applehost {
void InstallIosAudio() { SetAudioSink({Open, Close, Write}); }
}
