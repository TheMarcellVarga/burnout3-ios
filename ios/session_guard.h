#ifndef BO3_IOS_SESSION_GUARD_H
#define BO3_IOS_SESSION_GUARD_H
/* Main-thread state: nested UI/background holds must not resume each other. */
enum { BO3_HOLD_SETTINGS=1, BO3_HOLD_LAUNCHER=2, BO3_HOLD_BACKGROUND=4 };
enum { BO3_SESSION_PAUSE=1, BO3_SESSION_RESUME=2, BO3_SESSION_BLOCK=4, BO3_SESSION_UNBLOCK=8 };
typedef struct { unsigned reasons; int owns_pause; } bo3_session_guard;
unsigned bo3_session_hold(bo3_session_guard *s, unsigned reason, int already_paused);
unsigned bo3_session_release(bo3_session_guard *s, unsigned reason);
#endif
