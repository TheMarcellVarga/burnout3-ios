#include "session_guard.h"
#include <stdio.h>
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x); return 1; } } while(0)
int main(void) {
    bo3_session_guard s={0};
    CHECK(bo3_session_hold(&s,BO3_HOLD_SETTINGS,0)==(BO3_SESSION_PAUSE|BO3_SESSION_BLOCK));
    CHECK(bo3_session_hold(&s,BO3_HOLD_SETTINGS,1)==0);
    CHECK(bo3_session_hold(&s,BO3_HOLD_LAUNCHER,1)==0);
    CHECK(bo3_session_release(&s,BO3_HOLD_SETTINGS)==0); /* Transfer without unpausing. */
    CHECK(bo3_session_hold(&s,BO3_HOLD_SETTINGS,1)==0); /* Settings from Resume launcher. */
    CHECK(bo3_session_hold(&s,BO3_HOLD_BACKGROUND,1)==0);
    CHECK(bo3_session_release(&s,BO3_HOLD_SETTINGS)==0);
    CHECK(bo3_session_release(&s,BO3_HOLD_BACKGROUND)==0);
    CHECK(s.reasons==BO3_HOLD_LAUNCHER);
    CHECK(bo3_session_release(&s,BO3_HOLD_LAUNCHER)==(BO3_SESSION_RESUME|BO3_SESSION_UNBLOCK));
    CHECK(s.reasons==0 && !s.owns_pause);
    CHECK(bo3_session_release(&s,BO3_HOLD_LAUNCHER)==0);
    CHECK(bo3_session_hold(&s,BO3_HOLD_BACKGROUND,1)==BO3_SESSION_BLOCK);
    CHECK(bo3_session_release(&s,BO3_HOLD_BACKGROUND)==BO3_SESSION_UNBLOCK); /* Preserve an external pause. */
    CHECK(bo3_session_hold(&s,0,0)==0 && bo3_session_hold(&s,128,0)==0);
    CHECK(bo3_session_hold(&s,BO3_HOLD_BACKGROUND,0)==(BO3_SESSION_PAUSE|BO3_SESSION_BLOCK));
    CHECK(bo3_session_release(&s,BO3_HOLD_BACKGROUND)==(BO3_SESSION_RESUME|BO3_SESSION_UNBLOCK));
    puts("Session ownership, nested sheets, background and idempotence passed.");
    return 0;
}
