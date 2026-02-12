/**
 * @file agent_lib.c
 * @brief Library initialization and version
 */

#include "agent_lib.h"
#include <stdbool.h>

static bool g_initialized = false;

const char* agent_lib_version(void) {
    return "1.0.0";
}

agent_error_t agent_lib_init(void) {
    if (g_initialized) {
        return AGENT_OK;
    }

    /* No global initialization needed currently */

    g_initialized = true;
    return AGENT_OK;
}

void agent_lib_cleanup(void) {
    if (!g_initialized) {
        return;
    }

    /* No global cleanup needed currently */

    g_initialized = false;
}
