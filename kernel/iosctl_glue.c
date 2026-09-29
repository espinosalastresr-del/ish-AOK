#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "kernel/native_io.h"
#include "kernel/native_libc.h"
#if __APPLE__
extern int ishx_native_bridge_run(int argc, char *const argv[], char *out, size_t out_size);
#else
static int ishx_native_bridge_run(int argc, char *const argv[], char *out, size_t out_size) {
    (void)argc; (void)argv;
    if (out_size) snprintf(out, out_size, "{\"ok\":false,\"error\":\"iosctl requires the iOS host\"}\n");
    return 127;
}
#endif
int native_iosctl_main(int argc, char *const argv[], char *const envp[]) {
    (void)envp;
    char out[16384] = {0};
    int rc = ishx_native_bridge_run(argc, argv, out, sizeof(out));
    if (out[0] != '\0') native_write(1, out, strlen(out));
    nlibc_flush_std();
    return rc;
}
