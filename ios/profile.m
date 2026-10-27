#import <Foundation/Foundation.h>
#include <sys/resource.h>
#include <stdlib.h>
#include "kernel/kernel_pause.h"
#include "platform/xr_log.h"

/* Opt-in, whole-process CPU and recent guest flip timing. No per-frame I/O. */
void BO3ProfileTick(BOOL drew) {
    static int enabled=-1;
    static double start,cpu;
    static unsigned draws;
    if(enabled<0) { const char *v=getenv("RECOMP_IOS_PROFILE"); enabled=v && atoi(v)==1; }
    if(!enabled) return;
    if(drew) { draws++; return; }
    double now=NSProcessInfo.processInfo.systemUptime;
    if(start && now-start<5) return;
    struct rusage usage;
    if(getrusage(RUSAGE_SELF,&usage)) return;
    double used=usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6;
    if(start) {
        xbox_flip_stats flips={0}; xbox_HostFlipStats(&flips);
        XR_NOTICE("[IOS PERF] wall=%.2fs cpu=%.1f%% overlay_draws=%u paused=%d thermal=%ld recent_flip_p50=%.2fms p95=%.2fms max=%.2fms flips=%llu\n",
            now-start,100*(used-cpu)/(now-start),draws,xbox_HostPaused(),
            (long)NSProcessInfo.processInfo.thermalState,flips.recent_p50_ms,
            flips.recent_p95_ms,flips.recent_max_ms,(unsigned long long)flips.flips);
    }
    start=now; cpu=used; draws=0;
}
void BO3ProfileStart(void) {
    static BOOL started;
    const char *v=getenv("RECOMP_IOS_PROFILE");
    if(started || !v || atoi(v)!=1) return;
    started=YES; BO3ProfileTick(NO);
    /* The game overlay's display link stops behind native UI. Keep the
     * opt-in measurements alive there without a display-refresh wake-up. */
    NSTimer *timer=[NSTimer timerWithTimeInterval:5 repeats:YES block:^(NSTimer *t){ (void)t; BO3ProfileTick(NO); }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}
