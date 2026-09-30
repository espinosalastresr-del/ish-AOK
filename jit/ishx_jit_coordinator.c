#include "jit/ishx_jit_coordinator.h"
#include <stdatomic.h>

static atomic_int backend = ISHX_JIT_BACKEND_GADGET;
static atomic_bool initialized = false;

/*
 * Gadget JIT is the mandatory iSH-X baseline. StikDebug is deliberately not
 * inferred from an environment variable, URL scheme, installed app, or other
 * unverified signal: doing so would make the guest believe it owns executable
 * memory that it does not actually have.
 *
 * A future StikDebug backend must publish readiness only after its real
 * authenticated host-side acquisition/handshake has completed. Until then,
 * this coordinator reports gadget-only operation.
 */
void ishx_jit_coordinator_init(void) {
    if (atomic_exchange_explicit(&initialized, true, memory_order_acq_rel))
        return;
}

struct ishx_jit_state ishx_jit_coordinator_state(void) {
    ishx_jit_coordinator_init();
    struct ishx_jit_state s = {
        .backend = atomic_load_explicit(&backend, memory_order_acquire),
        .gadget_ready = true,
        .stikdebug_available = false
    };
    return s;
}

const char *ishx_jit_backend_name(enum ishx_jit_backend v) {
    return v == ISHX_JIT_BACKEND_STIKDEBUG ? "stikdebug" : "gadget";
}
