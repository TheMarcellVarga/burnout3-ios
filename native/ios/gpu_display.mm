#import "gpu_display.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include "ps2gpu/display.h"
#include "gpu_internal.h"
#include "ps2host/run.h"
#include "mobile_settings.h"
#import <MoltenVK/mvk_deprecated_api.h>
#include <memory>
#include <cstdio>
#include <algorithm>
#include <cmath>

@interface NativeMetalView : UIView
@end
@implementation NativeMetalView
+ (Class)layerClass { return CAMetalLayer.class; }
@end

namespace {
struct PresentedStats {
    std::mutex mutex;
    std::uint64_t count = 0;
    double last = 0, total = 0, squares = 0, longest = 0;
};
class MetalDisplay final : public ps2gpu::Display {
    std::unique_ptr<ps2gpu::Gpu> gpu_;
    CAMetalLayer *layer_;
    id<MTLCommandQueue> queue_;
    id<MTLRenderPipelineState> pipeline_;
    dispatch_semaphore_t slots_ = dispatch_semaphore_create(2);
    std::function<void()> first_;
    std::chrono::steady_clock::time_point last_present_{};
    std::shared_ptr<PresentedStats> stats_ = std::make_shared<PresentedStats>();
public:
    MetalDisplay(CAMetalLayer *layer, std::function<void()> first) : layer_(layer), first_(std::move(first)) {}
    bool Init() {
        std::string error;
        setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1);
        setenv("PS2HOST_SKIP_UNCHANGED_PRESENT", "1", 1);
        gpu_ = ps2gpu::CreateGpu(&error);
        if (!gpu_) { std::fprintf(stderr, "[display] %s\n", error.c_str()); return false; }
        auto& gpu = static_cast<ps2gpu::VulkanGpu&>(*gpu_);
        id<MTLCommandQueue> queue = nil;
        vkGetMTLCommandQueueMVK(gpu.queue, &queue);
        queue_ = queue;
        layer_.device = queue_.device;
        layer_.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer_.framebufferOnly = YES;
        layer_.maximumDrawableCount = 3;
        // Match the render scale so 2x detail reaches the screen.
        const unsigned scale = applehost::MobileRenderScale();
        layer_.drawableSize = CGSizeMake(640 * scale, 448 * scale);
        NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
            "struct V { float4 p [[position]]; float2 uv; };\n"
            "vertex V v(uint i [[vertex_id]]) { float2 p=float2((i<<1)&2,i&2); return {float4(p*float2(2,-2)+float2(-1,1),0,1),p}; }\n"
            "fragment float4 f(V v [[stage_in]], texture2d<float> t [[texture(0)]], constant float2& extent [[buffer(0)]]) { constexpr sampler s(coord::normalized,filter::linear,address::clamp_to_edge); return float4(t.sample(s,v.uv*extent).rgb,1); }\n";
        NSError *failure = nil;
        id<MTLLibrary> library = [queue_.device newLibraryWithSource:source options:nil error:&failure];
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [library newFunctionWithName:@"v"];
        desc.fragmentFunction = [library newFunctionWithName:@"f"];
        desc.colorAttachments[0].pixelFormat = layer_.pixelFormat;
        pipeline_ = [queue_.device newRenderPipelineStateWithDescriptor:desc error:&failure];
        if (!pipeline_) std::fprintf(stderr, "[display] %s\n", failure.description.UTF8String);
        return pipeline_ != nil && CheckPixels();
    }
    void Encode(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, unsigned width, unsigned height) {
            [encoder setRenderPipelineState:pipeline_];
            [encoder setFragmentTexture:texture atIndex:0];
            const float extent[] = {float(width)/texture.width, float(height)/texture.height};
            [encoder setFragmentBytes:extent length:sizeof(extent) atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }
    bool CheckPixels() {
        // Exercise the SAME shader used by live presentation. Asymmetric rows
        // catch vertical flips and channel swaps that a source-frame dump misses.
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
        desc.storageMode = MTLStorageModeShared;
        desc.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> source = [queue_.device newTextureWithDescriptor:desc];
        const unsigned pixels[] = {0xff0000ff, 0xff00ff00, 0xffff0000, 0xffffffff};
        [source replaceRegion:MTLRegionMake2D(0,0,2,2) mipmapLevel:0 withBytes:pixels bytesPerRow:8];
        desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> target = [queue_.device newTextureWithDescriptor:desc];
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = target;
        pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLCommandBuffer> command = [queue_ commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
        Encode(encoder, source, 2, 2);
        [encoder endEncoding];
        [command commit]; [command waitUntilCompleted];
        unsigned actual[4] = {};
        [target getBytes:actual bytesPerRow:8 fromRegion:MTLRegionMake2D(0,0,2,2) mipmapLevel:0];
        const unsigned expected[] = {0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff};
        const bool ok = command.status == MTLCommandBufferStatusCompleted && std::equal(std::begin(actual),std::end(actual),std::begin(expected));
        std::fprintf(stderr, "[display] GPU presentation pixel check: %s\n", ok ? "passed" : "FAILED");
        return ok;
    }
    bool PresentImage(std::uint64_t image, int, std::uint32_t width, std::uint32_t height) override {
        id<MTLTexture> texture = nil;
        vkGetMTLTextureMVK(reinterpret_cast<VkImage>(image), &texture);
        return PresentTexture(texture, width, height);
    }
    bool PresentTexture(id<MTLTexture> texture, unsigned width, unsigned height) {
        @autoreleasepool {
            // Loading can emit blanks faster than the physical display. Never
            // let nextDrawable throttle the GS/VIF queues to screen refresh.
            // Allow normal 60 Hz arrival jitter; drawable availability bounds
            // the real screen rate, not a strict 16 ms CPU deadline.
            const auto now = std::chrono::steady_clock::now();
            const bool accelerated = ps2host::VirtualClock() || ps2host::FastForward() > 1;
            if (accelerated && now - last_present_ < std::chrono::microseconds(8000)) return true;
            const dispatch_time_t deadline = accelerated ? DISPATCH_TIME_NOW :
                dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC);
            if (dispatch_semaphore_wait(slots_, deadline)) return true;
            last_present_ = now;
            id<CAMetalDrawable> drawable = [layer_ nextDrawable];
            if (!texture || !drawable) { dispatch_semaphore_signal(slots_); return false; }
            // The renderer submitted this image first. Commit on its SAME Metal
            // queue before the next Vulkan frame can overwrite the target.
            std::lock_guard<std::mutex> hold(ps2gpu::g_queue_lock);
            id<MTLCommandBuffer> command = [queue_ commandBuffer];
            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture = drawable.texture;
            pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
            Encode(encoder, texture, width, height);
            [encoder endEncoding];
            auto slots = slots_;
            auto stats = stats_;
            [drawable addPresentedHandler:^(id<MTLDrawable> shown) {
                dispatch_semaphore_signal(slots);
                const double now = shown.presentedTime;
                std::lock_guard<std::mutex> lock(stats->mutex);
                if (now <= 0) return;
                if (stats->last > 0 && now > stats->last) {
                    const double ms = (now - stats->last) * 1000;
                    ++stats->count; stats->total += ms; stats->squares += ms * ms;
                    stats->longest = std::max(stats->longest, ms);
                }
                stats->last = now;
            }];
            [command presentDrawable:drawable];
            [command commit];
            if (first_) { first_(); first_ = {}; }
            return true;
        }
    }
    Pacing TakePacing() override {
        std::lock_guard<std::mutex> lock(stats_->mutex);
        Pacing result;
        result.presents = stats_->count;
        if (result.presents) {
            result.mean_ms = stats_->total / result.presents;
            result.jitter_ms = std::sqrt(std::max(0.0, stats_->squares / result.presents - result.mean_ms * result.mean_ms));
            result.longest_ms = stats_->longest;
        }
        stats_->count = 0; stats_->total = stats_->squares = stats_->longest = 0;
        return result;
    }
    bool Present(const std::uint32_t* pixels, std::uint32_t width, std::uint32_t height) override {
        @autoreleasepool {
            // CPU-produced pictures (e.g. a video with no render target) also
            // reach the Metal surface. Each upload stays immutable in flight.
            MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
            desc.storageMode = MTLStorageModeShared; desc.usage = MTLTextureUsageShaderRead;
            id<MTLTexture> texture = [queue_.device newTextureWithDescriptor:desc];
            if (!texture) return false;
            [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels bytesPerRow:width * 4];
            return PresentTexture(texture, width, height);
        }
    }
    bool Pump() override { return true; }
    bool Focused() const override { return true; }
    bool KeyDown(int) const override { return false; }
    std::string Describe() const override { return "direct Metal presentation"; }
    ps2gpu::Gpu* SharedGpu() override { return gpu_.get(); }
};
std::unique_ptr<MetalDisplay> display;
}
namespace applehost {
void SetGpuDisplay(ps2gpu::Display*);
void SetGpuDisplayScale(UIView *view, unsigned scale) {
    scale = std::clamp(scale, 1u, 2u);
    CAMetalLayer *layer = (CAMetalLayer *)view.layer;
    const CGSize size = CGSizeMake(640 * scale, 448 * scale);
    if (!CGSizeEqualToSize(layer.drawableSize, size)) layer.drawableSize = size;
}
UIView *InstallGpuDisplay(UIView *parent, std::function<void()> first_frame) {
    NativeMetalView *view = [[NativeMetalView alloc] initWithFrame:parent.bounds];
    view.userInteractionEnabled = NO;
    auto candidate = std::make_unique<MetalDisplay>((CAMetalLayer *)view.layer, std::move(first_frame));
    if (!candidate->Init()) return nil;
    display = std::move(candidate);
    SetGpuDisplay(display.get());
    [parent addSubview:view];
    return view;
}
}
