#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(_WIN32)
#include <windows.h>
#endif

#include "controls.h"
#include "kernel.h"
#include "platform/recomp_env.h"
#include "platform/recomp_patch.h"
#include "xbox_memory_layout.h"
#include "host_display.h"
#ifdef RECOMP_ENV_HAVE_ENHANCE_KEYS
#include "enhance.h"
#include "enhance_cfg.h"
#include "platform/recomp_exe_dir.h"
#endif

extern ptrdiff_t g_xbox_mem_offset;
void xbox_PresentCadenceSteps(uint32_t flip, int steps);

#define HD_M32(va) (*(const uint32_t *)((uintptr_t)g_xbox_mem_offset + (uint32_t)(va)))
#define HD_MF(va)  (*(const float *)((uintptr_t)g_xbox_mem_offset + (uint32_t)(va)))

/* BO3_PACE_LOG=<file>: one line per flip the title emits (the "uw_flip"
 * mark), for the 60 fps crash camera switch (graphics.crash_60fps, BO-111,
 * docs/crash60.md): host time and the title's own pacing state. Off unless
 * set; tools/headless/pace_report.py reads it.
 *
 *   P <flip> t <ms> req <r> cur <c> mode <m>/<m2> steps <n> gs <steps>
 *     wt <ticks> slow <div> run <0|1> crash <b0><b1> st <state> obj <va>
 *     gt <ticks> ft <seconds> pl <players> mu <state>/<state>
 *
 * req / cur: the game object's (0x4A71A0) "half rate" bytes, +0x2E1ED asked
 * for by the stage's update and +0x2E1EE in force (sub_00016EF0 copies one
 * to the other and sets D3DRS_PRESENTATIONINTERVAL to 2 or 1; the stepper
 * sub_001B58E0 takes 2..8 steps a frame with it and 1..4 without). mode:
 * the stepper's mode, +0x2E1F0 (used while +0x2E1F4 is 3): 0 steps = the
 * minimum every frame, 1 by the clock, 2 the menus'. steps: the steps this
 * frame ran (+0x2E20C). gs: the global step counter 0x4A1EB4. wt / slow /
 * run: the world timer 0x60EA00's ticks (+0xC: steps / divisor), slow-motion
 * divisor (+0x18) and running byte (+0x28). crash: the two players' "crash
 * camera" bytes (0x73BACA, the next 0x27E0 on). st: the game's state (+0x2E214). obj:
 * the stage's mode object ([stage + 0x1B8]). gt: the game timer 0x4AE1E0's
 * ticks (never paused). ft: the frame's simulated time, steps x the world
 * timer's step (+0x2E210), which the cameras are moved by. pl: the player
 * count 0x73A1C0. mu: the music manager's (0x4115E8) in-game state (+0x5F4;
 * 0xD = 13 is "no music", what split screen has as shipped) and its outer
 * state (+0x5F8); BO-116, docs/split-screen.md. */
static FILE *s_pl_f;

static double pace_ms(void)
{
#ifdef _WIN32
    LARGE_INTEGER c, f;
    QueryPerformanceCounter(&c);
    QueryPerformanceFrequency(&f);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
#endif
}

static void pace_log(uint32_t flip)
{
    const uint8_t *m = (const uint8_t *)(uintptr_t)g_xbox_mem_offset;
    uint32_t stage;

    if (!s_pl_f || !m)
        return;
    stage = HD_M32(0x4D5370);
    fprintf(s_pl_f, "P %u t %.3f req %u cur %u mode %u/%u steps %d gs %u"
            " wt %u slow %u run %u crash %u%u st %u obj %08X gt %u ft %.5f"
            " pl %u mu %u/%u\n",
            flip, pace_ms(), m[0x4D538D], m[0x4D538E], HD_M32(0x4D5390),
            HD_M32(0x4D5394), (int)HD_M32(0x4D53AC), HD_M32(0x4A1EB4),
            HD_M32(0x60EA0C), HD_M32(0x60EA18), m[0x60EA28],
            m[0x73BACA], m[0x73BACA + 0x27E0], HD_M32(0x4D53B4),
            (stage >= 0x10000u && stage < 0x08000000u) ? HD_M32(stage + 0x1B8) : 0,
            HD_M32(0x4AE1EC), HD_MF(0x4D53B0),
            HD_M32(0x73A1C0), HD_M32(0x4115E8 + 0x5F4), HD_M32(0x4115E8 + 0x5F8));
}

void bo3_host_display_pace_log_start(void)
{
    const char *path = getenv("BO3_PACE_LOG");

    if (!path || !*path)
        return;
    s_pl_f = fopen(path, "w");
    if (!s_pl_f)
        fprintf(stderr, "BO3_PACE_LOG: cannot write %s\n", path);
    else
        setvbuf(s_pl_f, NULL, _IOLBF, 0);
}


/* graphics.bloom / graphics.motion_blur (RECOMP_GFX_BLOOM,
 * RECOMP_GFX_MOTION_BLUR, BO-212): the strength 0..1 the patches' expressions
 * ("loaded * bloom_strength", "loaded * blur_strength", config/patches.json)
 * multiply the title's bloom weight / blur opacity by while the setting reads
 * anything but 1. Unset or unreadable is 1: the title as it ships; the old
 * spellings false / off read 0. docs/effects.md. */
static double fx_strength(recomp_env_id id)
{
    const char *v = recomp_env(id);
    char *end;
    double d;

    if (!v || !*v)
        return 1.0;
    d = strtod(v, &end);
    if (end == v || *end)
        return (!strcmp(v, "false") || !strcmp(v, "off")) ? 0.0 : 1.0;
    return d < 0.0 ? 0.0 : d > 1.0 ? 1.0 : d;
}

static double bloom_strength(void) { return fx_strength(RENV_GFX_BLOOM); }
static double blur_strength(void) { return fx_strength(RENV_GFX_MOTION_BLUR); }

/* graphics.vehicle_detail (RECOMP_GFX_VEHICLE_DETAIL, BO-112): the factor on
 * the title's vehicle level-of-detail distances, read by the patches'
 * expression ("loaded * vehicle_lod_scale", config/patches.json) while the
 * setting is not "original". docs/draw-distance.md. */
double bo3_host_display_vehicle_lod_scale(void)
{
    const char *v = recomp_env(RENV_GFX_VEHICLE_DETAIL);

    if (v && !strcmp(v, "far"))
        return 2.0;
    if (v && !strcmp(v, "farthest"))
        return 4.0;
    return 1.0;
}

/* graphics.scenery_detail (RECOMP_GFX_SCENERY_DETAIL, BO-177): the factor on
 * the switch distance of the track's props with two models (pine trees above
 * all), read by the patches' expression ("loaded * scenery_lod_scale",
 * config/patches.json) while the setting is "far". docs/draw-distance.md. */
#define SCENERY_FAR_SCALE 4.0
double bo3_host_display_scenery_lod_scale(void)
{
    const char *v = recomp_env(RENV_GFX_SCENERY_DETAIL);

    return (v && !strcmp(v, "far")) ? SCENERY_FAR_SCALE : 1.0;
}


/* What the window shows of the title's 640x480 frame, for the display.hud_fix
 * patches (config/patches.json, BO-89): the presenter's own source rectangle
 * (nv2a_present_layout), so another overscan or fit setting stays right.
 * vis_x0 / vis_x1: the columns the picture shows as it is presented;
 * ref_x0 / ref_x1: the columns a 4:3 picture shows in the same window, the
 * reference for "as far from the visible edge as in 4:3" (the 16:10 fill
 * crops a 16:9 picture's sides and not a 4:3 one's). In the title's 4:3 the
 * two are the same call, so the patched values are the title's. */
void nv2a_present_visible_x(uint32_t fw, uint32_t fh, double *x0, double *x1);
void nv2a_present_visible_x_at(uint32_t fw, uint32_t fh, int aspect, double *x0, double *x1);
void nv2a_present_note_output(uint32_t dw, uint32_t dh);
static int s_hud_wide;      /* the title is in its 16:9 mode */
static void hud_ref_x(double *x0, double *x1)
{
    if (s_hud_wide)
        nv2a_present_visible_x_at(640, 480, 1 /* NV2A_ASPECT_4_3 */, x0, x1);
    else
        nv2a_present_visible_x(640, 480, x0, x1);
}
/* The picture as the stage's frames will be presented: at its wide aspect
 * when display.ultrawide set one up (below), else as configured. */
void nv2a_present_visible_x_ratio(uint32_t fw, uint32_t fh, double ratio, double *x0, double *x1);
static volatile double s_uw_stage; /* set-up stage's wide aspect, or 0 */
static double hud_vis_x0(void)
{
    double x0, x1;
    nv2a_present_visible_x_ratio(640, 480, s_uw_stage, &x0, &x1);
    return x0;
}
static double hud_vis_x1(void)
{
    double x0, x1;
    nv2a_present_visible_x_ratio(640, 480, s_uw_stage, &x0, &x1);
    return x1;
}
static double hud_ref_x0(void)
{
    double x0, x1;
    hud_ref_x(&x0, &x1);
    return x0;
}
static double hud_ref_x1(void)
{
    double x0, x1;
    hud_ref_x(&x0, &x1);
    return x1;
}

/* ---- display.ultrawide (BO-94) -------------------------------------------
 *
 * The title's 3D drawn for a picture wider than 16:9, its front end left as
 * it is. Only the title's own values change, through the guest patches of
 * config/patches.json; this is the state they read.
 *
 *   uw_stage_setup   a stage (race, crash, ...) is being set up: its camera
 *                    (sub_0002F380 / sub_0002F480) and the HUD's layout take
 *                    the wide aspect if the setting is on now. The choice
 *                    holds until the next set-up: a change shows from the
 *                    next race.
 *   uw_fe_setup      the front end sets its camera up: the title's 16:9.
 *   uw_stage_render  the stage drew the 3D world in this frame.
 *   uw_flip          the title emits a flip (NV097_FLIP_STALL): the frame
 *                    that ends here is wide if the stage drew in it. The
 *                    presenter asks by flip number (uw_frame_aspect) and shows
 *                    that frame at the wide aspect, any other at 16:9 in the
 *                    middle: a loading screen, a menu, a video are never
 *                    stretched, and the switch is on the frame, not near it.
 *
 * Leaving a stage, the title draws one more stage frame with the loading
 * screen already up (uw_fe_owns_picture: a 16:9 frame), then flips once
 * without drawing; a flip without a stage frame is shown as the frame before
 * it, once.
 *
 * The flips are counted here as the title emits them and by the GPU executor
 * as it reaches them; the same sequence, so the same numbers. A flip the
 * count has not reached (it cannot, unless a flip came from elsewhere) is
 * shown at 16:9. */
void nv2a_present_frame_aspect_fn(double (*fn)(uint32_t flip));
void nv2a_present_window_aspect(double aspect);
double nv2a_present_output_aspect(void);

#define UW_RING 64                      /* flips the presenter may lag by */
static double s_base_aspect = 4.0 / 3.0;    /* the title's: 4:3 or 16:9 */
static volatile double s_uw_frame;      /* of the frame being drawn, or 0 */
static volatile uint32_t s_uw_flips;    /* flips the title emitted */
static float s_uw_ring[UW_RING];        /* wide aspect of flip n, or 0 */
static int s_uw_repeat;                 /* the repeated last frame was taken */
static int s_uw_log;

/* The setting's aspect now; 0: off (or the title is not in 16:9). */
static double uw_setting(void)
{
    const char *v = recomp_env(RENV_DISPLAY_ULTRAWIDE);
    double a = 0.0;

    if (!v || s_base_aspect < 1.5)
        return 0.0;
    if (!strcmp(v, "21:9"))
        a = 64.0 / 27.0;                /* 2560x1080, 3440x1440 */
    else if (!strcmp(v, "32:9"))
        a = 32.0 / 9.0;
    else if (!strcmp(v, "window"))
        a = nv2a_present_output_aspect();
    if (a > 4.0)
        a = 4.0;
    return a > s_base_aspect + 0.01 ? a : 0.0;
}

static void uw_stage_setup(void)
{
    double a = uw_setting();
    if (s_uw_log && a != s_uw_stage)
        fprintf(stderr, "UW: stage set-up, aspect %.4f (flip %u)\n", a, s_uw_flips);
    s_uw_stage = a;
}

static void uw_fe_setup(void)
{
    if (s_uw_log && s_uw_stage != 0.0)
        fprintf(stderr, "UW: front-end set-up (flip %u)\n", s_uw_flips);
    s_uw_stage = 0.0;
}

static void uw_stage_render(void)
{
    s_uw_frame = s_uw_stage;
    /* display.score_board (scoreboard.c, BO-165): before the HUD is drawn. */
    bo3_score_board_render();
}

/* BO-110 (HDR prototype, RECOMP_DEBUG=hdr): the start and the end of a
 * view's 3D (config/patches.json hdr_scene / hdr_ui), handed to the
 * toolkit as places in the push buffer: where the title's D3D will write
 * its next command, the device's m_pPut (D3D__pDevice at 0x35FB48, m_pPut
 * at +0; sub_0034CBF0 writes FLIP_STALL there). The executor runs behind
 * the guest, so the backend learns the change when its walk reaches that
 * word, in order with the draws around it. */
void nv2a_pb_stream_mark(uint32_t va, uint32_t tag);   /* toolkit nv2a_pb_state.h */
int  nv2a_host_hdr(void);                               /* toolkit nv2a_backend_common.h */
static void hdr_mark(uint32_t tag)
{
    uint32_t dev, put;
    /* graphics.hdr (live) or RECOMP_DEBUG=hdr: before, only the debug
     * switch marked, so the setting alone never gave the scene its light. */
    if (!nv2a_host_hdr())
        return;
    dev = HD_M32(0x35FB48);
    if (!dev)
        return;
    put = HD_M32(dev);
    if (put)
        nv2a_pb_stream_mark(put, tag);
}
static void hdr_scene(void) { hdr_mark(1); }
static void hdr_ui(void) { hdr_mark(0); }

static void uw_flip(void)
{
    uint32_t n = s_uw_flips + 1;
    float a = (float)s_uw_frame, prev = s_uw_ring[(n - 1) % UW_RING];

    /* The first flip after a stage's last frame shows that frame again (the
     * title flips without drawing while it leaves the stage): wide still.
     * Once: the frame after is the loading screen's. */
    if (a == 0.0f && prev > 0.0f && !s_uw_repeat) {
        a = prev;
        s_uw_repeat = 1;
    } else if (a > 0.0f) {
        s_uw_repeat = 0;
    }
    if (s_uw_log && a != prev)
        fprintf(stderr, "UW: flip %u %s\n", n, a > 0.0f ? "wide" : "16:9");
    s_uw_ring[n % UW_RING] = a;
    s_uw_flips = n;
    bo3_score_board_flip();
    pace_log(n);
    /* The simulation steps this frame ran (the stepper's count, +0x2E20C:
     * see BO3_PACE_LOG), for the overlay's frame-time graph: a frame of two
     * steps moves the world twice as far (present_cadence.h, BO-115). */
    if (g_xbox_mem_offset)
        xbox_PresentCadenceSteps(n, (int)HD_M32(0x4D53AC));
    s_uw_frame = 0.0;
}

static double uw_frame_aspect(uint32_t flip)
{
    uint32_t n = s_uw_flips;
    if (flip == 0 || flip > n || n - flip >= UW_RING)
        return 0.0;
    return (double)s_uw_ring[flip % UW_RING];
}

/* "aspect": the picture a stage is laid out for (the HUD's rectangle, the
 * camera); "frame_aspect": the picture this frame is shown at (what is
 * drawn outside a stage too: the EA Trax pop-up); "fe_squeeze": the factor
 * that keeps the front-end scene's 16:9 shape when it is drawn over a wide
 * frame (the pause menu, the race intro, results), 1 otherwise. */
static double hud_aspect(void)
{
    double a = s_uw_stage;
    return a > 0.0 ? a : s_base_aspect;
}

static double hud_frame_aspect(void)
{
    double a = s_uw_frame;
    return a > 0.0 ? a : s_base_aspect;
}

/* The front-end scene (0x557A20) puts a picture that fills the screen (a
 * loading screen's, a menu's background) on its layer 0; what it draws over
 * the 3D world (pause menu, intro banner, results) never uses that layer.
 * Leaving a stage, the title draws one more stage frame with the loading
 * screen already up: the front end owns that picture, so the frame is not a
 * wide one (the 3D is behind the picture anyway) and is shown, like the
 * loading screens after it, at 16:9. Read from the scene as the title built
 * it (the layer array at +0x2C, a layer's first object at +8); asked when the
 * scene's root is synced, which is before anything of it is drawn. */
static int uw_fe_owns_picture(void)
{
    const uint8_t *m = (const uint8_t *)(uintptr_t)g_xbox_mem_offset;
    uint32_t layers = *(const uint32_t *)(m + 0x557A20u + 0x2Cu);
    return layers && *(const uint32_t *)(m + layers + 8u) != 0;
}

static double uw_fe_squeeze(void)
{
    double a = s_uw_frame;
    if (a > 0.0 && uw_fe_owns_picture()) {
        s_uw_frame = 0.0;
        s_uw_repeat = 1;        /* and the flip after it repeats a 16:9 frame */
        return 1.0;
    }
    return a > 0.0 ? s_base_aspect / a : 1.0;
}

static void uw_init(void)
{
    const char *v = recomp_env(RENV_DISPLAY_ULTRAWIDE);

    s_uw_log = getenv("BO3_UW_LOG") != NULL;
    recomp_patch_set_var_fn("aspect", hud_aspect);
    recomp_patch_set_var_fn("frame_aspect", hud_frame_aspect);
    recomp_patch_set_var_fn("fe_squeeze", uw_fe_squeeze);
    nv2a_present_frame_aspect_fn(uw_frame_aspect);
    /* A new window opens at the chosen shape (the title's 16:9 otherwise). */
    if (v && s_base_aspect > 1.5) {
        if (!strcmp(v, "21:9"))
            nv2a_present_window_aspect(64.0 / 27.0);
        else if (!strcmp(v, "32:9"))
            nv2a_present_window_aspect(32.0 / 9.0);
    }
}

/* The enhancements (src/enhance in the apexJCL runtime): enhance.toml in the
 * per-user settings folder, else beside the executable (bin/; install.h),
 * RECOMP_* over it, every key stock by default;
 * config/enhance.toml.default lists them. Called once the environment
 * defaults are in and before the guest starts: the backends, the window and
 * the kernel read settled values, and the kernel bridge copies the AV pack
 * into guest memory.
 *
 * display.widescreen and display.hdtv are the dashboard's video settings,
 * which the kernel reports and the title reads itself: XGetVideoFlags
 * (sub_001CF913) at device setup, sub_0003C8A0, bit 0 -> widescreen, which
 * sub_0003D690 turns into D3DPRESENTFLAG_WIDESCREEN and sub_0002F380 into a
 * 16:9 projection; bit 3 (480p, HDTV pack only) -> D3DPRESENTFLAG_PROGRESSIVE.
 * The back buffer is 640x480 in every case, so 16:9 is anamorphic and
 * present.aspect stretches it. Without the layer this is nothing. */
void bo3_host_enhance_init(void)
{
#ifdef RECOMP_ENV_HAVE_ENHANCE_KEYS
    xbox_enhance_init(bo3_enhance_root(), NULL);
    /* The picture's shape, as the title gets it at device setup, for the
     * float patches of config/patches.json (display.hud_fix, BO-89). */
    s_hud_wide = enhance_cfg_bool("display.widescreen", 0);
    s_base_aspect = s_hud_wide ? 16.0 / 9.0 : 4.0 / 3.0;
    uw_init();
    enhance_cfg_report_unused();
    fflush(stderr);
#endif
}


/* Bind the HUD, aspect, effects, and model-detail patches to their host state. */
void bo3_host_display_register_patches(void)
{
    recomp_patch_set_var("aspect", 4.0 / 3.0);
    recomp_patch_set_var_fn("vis_x0", hud_vis_x0);
    recomp_patch_set_var_fn("vis_x1", hud_vis_x1);
    recomp_patch_set_var_fn("ref_x0", hud_ref_x0);
    recomp_patch_set_var_fn("ref_x1", hud_ref_x1);
    {
        const char *o = getenv("BO3_HUD_OUTPUT");
        unsigned ow = 0, oh = 0;
        if (o && sscanf(o, "%ux%u", &ow, &oh) == 2 && ow && oh)
            nv2a_present_note_output(ow, oh);
    }
    recomp_patch_enable("display.hud_fix", RENV_GFX_HUD_FIX);
    recomp_patch_enable("display.ultrawide", RENV_DISPLAY_ULTRAWIDE);
    recomp_patch_enable("graphics.bloom", RENV_GFX_BLOOM);
    recomp_patch_enable("graphics.motion_blur", RENV_GFX_MOTION_BLUR);
    recomp_patch_set_var_fn("bloom_strength", bloom_strength);
    recomp_patch_set_var_fn("blur_strength", blur_strength);
    recomp_patch_set_var_fn("vehicle_lod_scale", bo3_host_display_vehicle_lod_scale);
    recomp_patch_enable("graphics.vehicle_detail", RENV_GFX_VEHICLE_DETAIL);
    recomp_patch_set_var_fn("scenery_lod_scale", bo3_host_display_scenery_lod_scale);
    recomp_patch_enable("graphics.scenery_detail", RENV_GFX_SCENERY_DETAIL);
    recomp_patch_on_mark("uw_stage_setup", uw_stage_setup);
    recomp_patch_on_mark("uw_fe_setup", uw_fe_setup);
    recomp_patch_on_mark("uw_stage_render", uw_stage_render);
    recomp_patch_on_mark("uw_flip", uw_flip);
    recomp_patch_on_mark("hdr_scene", hdr_scene);
    recomp_patch_on_mark("hdr_ui", hdr_ui);
}

uint32_t bo3_host_display_flip_count(void)
{
    return s_uw_flips;
}
