#ifndef BO3_HOST_DISPLAY_H
#define BO3_HOST_DISPLAY_H

#include <stdint.h>

void bo3_host_enhance_init(void);
void bo3_host_display_register_patches(void);
void bo3_host_display_pace_log_start(void);
uint32_t bo3_host_display_flip_count(void);
double bo3_host_display_vehicle_lod_scale(void);
double bo3_host_display_scenery_lod_scale(void);

#endif
