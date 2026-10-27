#include "session_guard.h"
unsigned bo3_session_hold(bo3_session_guard *s,unsigned reason,int already_paused) {
    reason &= BO3_HOLD_SETTINGS|BO3_HOLD_LAUNCHER|BO3_HOLD_BACKGROUND;
    if(!reason || (s->reasons&reason)==reason) return 0;
    unsigned action=0;
    if(!s->reasons) {
        s->owns_pause=!already_paused;
        action=BO3_SESSION_BLOCK|(s->owns_pause ? BO3_SESSION_PAUSE : 0);
    }
    s->reasons|=reason;
    return action;
}
unsigned bo3_session_release(bo3_session_guard *s,unsigned reason) {
    if(!(s->reasons&reason)) return 0;
    s->reasons&=~reason;
    if(s->reasons) return 0;
    unsigned action=BO3_SESSION_UNBLOCK|(s->owns_pause ? BO3_SESSION_RESUME : 0);
    s->owns_pause=0;
    return action;
}
