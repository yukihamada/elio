/**
 * @file agent_lib.h
 * @brief Main header for the C Agent Library
 *
 * This is the primary header to include when using the agent library.
 * It includes all other necessary headers.
 */

#ifndef AGENT_LIB_H
#define AGENT_LIB_H

/* Core types and data structures */
#include "agent_types.h"

/* Memory management (arena allocator) */
#include "agent_context.h"

/* String and UTF-8 utilities */
#include "agent_string.h"

/* JSON parser and serializer */
#include "agent_json.h"

/* Response parser (tool calls, thinking tags) */
#include "agent_parser.h"

/* MCP schema generation */
#include "agent_mcp.h"

/* Agent orchestrator (main loop) */
#include "agent_orchestrator.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Library version
 */
#define AGENT_LIB_VERSION_MAJOR 1
#define AGENT_LIB_VERSION_MINOR 0
#define AGENT_LIB_VERSION_PATCH 0

/**
 * @brief Get library version string
 * @return Version string (e.g., "1.0.0")
 */
const char* agent_lib_version(void);

/**
 * @brief Initialize the library
 *
 * Should be called once before using any other functions.
 * Safe to call multiple times.
 *
 * @return AGENT_OK on success
 */
agent_error_t agent_lib_init(void);

/**
 * @brief Cleanup the library
 *
 * Should be called when done using the library.
 */
void agent_lib_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_LIB_H */
