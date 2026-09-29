#ifndef ISHX_JIT_COORDINATOR_H
#define ISHX_JIT_COORDINATOR_H
#include <stdbool.h>
enum ishx_jit_backend { ISHX_JIT_BACKEND_GADGET = 0, ISHX_JIT_BACKEND_STIKDEBUG = 1 };
struct ishx_jit_state { enum ishx_jit_backend backend; bool gadget_ready; bool stikdebug_available; };
void ishx_jit_coordinator_init(void);
struct ishx_jit_state ishx_jit_coordinator_state(void);
const char *ishx_jit_backend_name(enum ishx_jit_backend backend);
#endif
