#include "input/touch_pad.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures,checks;
#define CHECK(x) do { checks++; if(!(x)) { failures++; fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x); } } while(0)
static int driving(void) { return 1; }
static xbox_touch_draw controls[XBOX_TOUCH_MAX_CONTROLS];
static int refresh(void) { return xbox_InputTouchDrawList(controls,XBOX_TOUCH_MAX_CONTROLS); }
static xbox_touch_draw find(const char *label) {
    int n=refresh();
    for(int i=0;i<n;i++) if((label && controls[i].label && !strcmp(controls[i].label,label)) ||
        (!label && controls[i].kind==XBOX_TOUCH_KIND_STICK)) return controls[i];
    CHECK(0); return (xbox_touch_draw){0};
}
static XBOX_GAMEPAD state(void) { XBOX_INPUT_STATE s; refresh(); xbox_InputTouchState(&s); return s.Gamepad; }
static void setup(float w,float h,float scale,int tablet) {
    xbox_InputTouchReset(); xbox_InputTouchSetMode(XBOX_TOUCH_ALWAYS);
    xbox_InputTouchSetHybrid(1); xbox_InputTouchSetScreen(w,h);
    xbox_InputTouchSetScale(scale); xbox_InputTouchSetDpi(tablet ? 132 : 163);
    xbox_InputTouchSetInsets(tablet ? 0 : 59,0,tablet ? 0 : 59,21);
    xbox_InputTouchSetDrivingHook(driving); refresh();
}
int main(void) {
    /* Targets stay separate, safe and reachable at phone/tablet sizes. */
    const float sizes[][2]={{692,320},{844,390},{932,430},{1024,768},{1366,1024}};
    for(int k=0;k<5;k++) for(int large=0;large<2;large++) {
        setup(sizes[k][0],sizes[k][1],large ? 1.2f : 1,k>2);
        int n=refresh();
        for(int i=0;i<n;i++) {
            xbox_touch_draw a=controls[i];
            CHECK(a.x-a.r >= (k>2 ? 0 : 59) && a.x+a.r<=sizes[k][0]-(k>2 ? 0 : 59));
            CHECK(a.y-a.r>=0 && a.y+a.r<=sizes[k][1]-21);
            if(a.kind==XBOX_TOUCH_KIND_BUTTON) CHECK(a.r*2>=44);
            for(int j=i+1;j<n;j++) {
                xbox_touch_draw b=controls[j];
                CHECK(hypotf(a.x-b.x,a.y-b.y)>=a.r+b.r);
            }
        }
    }
    setup(932,430,1,0);
    xbox_touch_draw stick=find(NULL),gas=find("GAS"),boost=find("BOOST"),brake=find("BRAKE");
    float travel=stick.r*0.65f;
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,1,stick.x,stick.y);
    CHECK(state().sThumbLX==0);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,1,stick.x+travel*0.04f,stick.y);
    CHECK(state().sThumbLX==0); /* Stable dead center. */
    int previous=0;
    for(int i=1;i<=20;i++) {
        xbox_InputTouchFinger(XBOX_TOUCH_MOVE,1,stick.x+travel*i/20,stick.y);
        int value=state().sThumbLX; CHECK(value>=previous); previous=value;
    }
    CHECK(previous==32767);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,1,stick.x-travel,stick.y); CHECK(state().sThumbLX==-32767);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,1,stick.x+travel*.5f,stick.y);
    int standard=state().sThumbLX;
    xbox_InputTouchSetSteeringResponse(1); int gentle=state().sThumbLX;
    xbox_InputTouchSetSteeringResponse(2); int quick=state().sThumbLX;
    CHECK(gentle<standard && standard<quick);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,1,stick.x-travel*.5f,stick.y); CHECK(state().sThumbLX==-quick);
    xbox_InputTouchSetSteeringResponse(0);
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,2,gas.x,gas.y);
    CHECK(state().sThumbLX<0 && state().bAnalogButtons[XBOX_BUTTON_RTRIGGER]==255);
    for(int i=0;i<=20;i++) {
        float t=i/20.0f;
        xbox_InputTouchFinger(XBOX_TOUCH_MOVE,2,gas.x+(boost.x-gas.x)*t,gas.y+(boost.y-gas.y)*t);
        CHECK(state().bAnalogButtons[XBOX_BUTTON_RTRIGGER]==255);
    }
    CHECK(state().bAnalogButtons[XBOX_BUTTON_A]==255);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,2,brake.x,brake.y);
    CHECK(state().bAnalogButtons[XBOX_BUTTON_LTRIGGER]==255 && state().bAnalogButtons[XBOX_BUTTON_RTRIGGER]==0);
    /* A competing finger cannot steal the steering stick. */
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,3,stick.x,stick.y+stick.r*1.5f);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,3,stick.x+travel,stick.y+stick.r*1.5f);
    CHECK(state().sThumbLX<0);
    xbox_InputTouchFinger(XBOX_TOUCH_CANCEL,1,0,0); CHECK(state().sThumbLX==0);
    CHECK(state().bAnalogButtons[XBOX_BUTTON_LTRIGGER]==255); /* Independent fingers. */
    xbox_InputTouchFinger(XBOX_TOUCH_CANCEL,2,0,0); CHECK(state().bAnalogButtons[XBOX_BUTTON_LTRIGGER]==0);
    xbox_InputTouchFinger(XBOX_TOUCH_CANCEL,3,0,0);
    /* Off-center pickup stays neutral; only deliberate movement steers. */
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,4,stick.x+travel*.5f,stick.y); CHECK(state().sThumbLX==0);
    xbox_touch_draw anchored=find(NULL); CHECK(anchored.x==stick.x && anchored.y==stick.y);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,4,stick.x+travel,stick.y); CHECK(state().sThumbLX>10000);
    xbox_InputTouchFinger(XBOX_TOUCH_UP,4,0,0); CHECK(state().sThumbLX==0);
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,5,430,250); CHECK(state().sThumbLX==0);
    xbox_InputTouchFinger(XBOX_TOUCH_MOVE,5,430+travel,250); CHECK(state().sThumbLX==32767);
    xbox_InputTouchReleaseAll(); CHECK(state().sThumbLX==0);
    /* Short cancelled taps never stay latched; changing layout releases all. */
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,6,gas.x,gas.y);
    xbox_InputTouchFinger(XBOX_TOUCH_CANCEL,6,gas.x,gas.y); CHECK(state().bAnalogButtons[XBOX_BUTTON_RTRIGGER]==0);
    xbox_InputTouchFinger(XBOX_TOUCH_DOWN,7,gas.x,gas.y);
    xbox_InputTouchSetHybrid(0); CHECK(state().bAnalogButtons[XBOX_BUTTON_RTRIGGER]==0);
    printf("hybrid_touch: %d checks, %d failures\n",checks,failures);
    return failures!=0;
}
