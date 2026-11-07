#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdatomic.h>
#include "ios_drawable_queue.h"

static int failures;
#define CHECK(x) do { if(!(x)) { failures++; fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x); } } while(0)
static atomic_int calls, layersFreed;
@interface BlockingLayer : NSObject {
@public
    dispatch_semaphore_t entered, unblock;
    NSObject *drawable;
    BOOL returnsNil;
}
- (id)nextDrawable;
@end
@implementation BlockingLayer
- (instancetype)init {
    if((self=[super init])) {
        entered=dispatch_semaphore_create(0); unblock=dispatch_semaphore_create(0);
        drawable=[[NSObject alloc] init];
    }
    return self;
}
- (id)nextDrawable {
    atomic_fetch_add(&calls,1);
    dispatch_semaphore_signal(entered);
    dispatch_semaphore_wait(unblock,DISPATCH_TIME_FOREVER);
    return returnsNil ? nil : drawable;
}
- (void)dealloc {
    [drawable release]; dispatch_release(entered); dispatch_release(unblock);
    atomic_fetch_add(&layersFreed,1); [super dealloc];
}
@end
static int await_value(atomic_int *value,int expected) {
    for(int i=0;i<1000;i++) {
        if(atomic_load(value)==expected) return 1;
        [NSThread sleepForTimeInterval:0.001];
    }
    return 0;
}
int main(void) {
    @autoreleasepool {
        BlockingLayer *layer=[[BlockingLayer alloc] init];
        void *queue=ios_drawable_queue_create(layer);
        CHECK(ios_drawable_queue_take(queue)==NULL);
        CHECK(dispatch_semaphore_wait(layer->entered,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
        CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
        for(int i=0;i<1000;i++) {
            ios_drawable_queue_request(queue);
            CHECK(ios_drawable_queue_take(queue)==NULL);
        }
        CHECK(CFAbsoluteTimeGetCurrent()-start<0.1); /* GPU remains blocked. */
        CHECK(atomic_load(&calls)==1); /* One request, no growing work queue. */
        dispatch_semaphore_signal(layer->unblock);
        void *drawable=NULL;
        for(int i=0;i<1000 && !drawable;i++) {
            drawable=ios_drawable_queue_take(queue);
            if(!drawable) [NSThread sleepForTimeInterval:0.001];
        }
        CHECK(drawable==layer->drawable);
        /* Cancellation must not wait for an acquisition or publish afterward. */
        ios_drawable_queue_request(queue);
        CHECK(dispatch_semaphore_wait(layer->entered,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
        start=CFAbsoluteTimeGetCurrent();
        ios_drawable_queue_destroy(queue);
        CHECK(CFAbsoluteTimeGetCurrent()-start<0.1);
        dispatch_semaphore_signal(layer->unblock);
        [layer release];
    }
    CHECK(await_value(&layersFreed,1)); /* No retained layer/drawable after cancellation. */
    @autoreleasepool {
        /* A timed-out/hidden layer may return nil; acquisition can recover. */
        BlockingLayer *layer=[[BlockingLayer alloc] init];
        layer->returnsNil=YES;
        void *queue=ios_drawable_queue_create(layer);
        ios_drawable_queue_request(queue);
        CHECK(dispatch_semaphore_wait(layer->entered,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
        dispatch_semaphore_signal(layer->unblock);
        /* Retry until the worker has returned nil and accepted a new request. */
        int retryStarted=0;
        for(int i=0;i<1000 && !retryStarted;i++) {
            CHECK(ios_drawable_queue_take(queue)==NULL);
            retryStarted=dispatch_semaphore_wait(layer->entered,DISPATCH_TIME_NOW)==0;
            if(!retryStarted) [NSThread sleepForTimeInterval:0.001];
        }
        CHECK(retryStarted);
        layer->returnsNil=NO;
        dispatch_semaphore_signal(layer->unblock);
        void *drawable=NULL;
        for(int i=0;i<1000 && !drawable;i++) {
            drawable=ios_drawable_queue_take(queue);
            if(!drawable) [NSThread sleepForTimeInterval:0.001];
        }
        CHECK(drawable==layer->drawable);
        ios_drawable_queue_destroy(queue);
        [layer release];
    }
    CHECK(await_value(&layersFreed,2));
    printf("drawable_queue: %d failures\n",failures);
    return failures!=0;
}
