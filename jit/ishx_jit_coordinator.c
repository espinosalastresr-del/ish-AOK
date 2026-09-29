#include "jit/ishx_jit_coordinator.h"
#include <stdatomic.h>
#include <stdlib.h>
static atomic_int backend = ISHX_JIT_BACKEND_GADGET;
static atomic_bool initialized = false;
static bool stikdebug_available;
void ishx_jit_coordinator_init(void) {
    if (atomic_exchange_explicit(&initialized, true, memory_order_acq_rel)) return;
    /* StikDebug is not treated as a URL launch. It becomes eligible only after
       a future host-side authenticated JIT handshake reports readiness. */
    const char *probe = getenv("ISHX_STIKDEBUG_READY");
    stikdebug_available = probe != NULL &&
        (probe[0]=='1'||probe[0]=='y'||probe[0]=='Y'||probe[0]=='t'||probe[0]=='T');
    if (stikdebug_available)
        atomic_store_explicit(&backend, ISHX_JIT_BACKEND_STIKDEBUG, memory_order_release);
}
struct ishx_jit_state ishx_jit_coordinator_state(void) {
    ishx_jit_coordinator_init();
    struct ishx_jit_state s = {
        .backend = atomic_load_explicit(&backend, memory_order_acquire),
        .gadget_ready = true,
        .stikdebug_available = stikdebug_available
    };
    return s;
}
const char *ishx_jit_backend_name(enum ishx_jit_backend v) {
    return v == ISHX_JIT_BACKEND_STIKDEBUG ? "stikdebug" : "gadget";
}
