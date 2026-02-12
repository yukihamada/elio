/**
 * @file agent_context.h
 * @brief Arena/Pool allocator for efficient memory management
 */

#ifndef AGENT_CONTEXT_H
#define AGENT_CONTEXT_H

#include "agent_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Create a new agent context with arena allocator
 * @param initial_size Initial arena size in bytes (0 for default: 64KB)
 * @return New context, or NULL on failure
 */
agent_context_t* agent_context_create(size_t initial_size);

/**
 * @brief Destroy context and free all memory
 * @param ctx Context to destroy
 */
void agent_context_destroy(agent_context_t* ctx);

/**
 * @brief Allocate memory from the arena
 * @param ctx Context
 * @param size Size in bytes
 * @return Pointer to allocated memory, or NULL on failure
 */
void* agent_context_alloc(agent_context_t* ctx, size_t size);

/**
 * @brief Allocate zeroed memory from the arena
 * @param ctx Context
 * @param count Number of elements
 * @param size Size of each element
 * @return Pointer to allocated memory, or NULL on failure
 */
void* agent_context_calloc(agent_context_t* ctx, size_t count, size_t size);

/**
 * @brief Reset the arena (free all allocations but keep the memory)
 * @param ctx Context
 *
 * This is very fast - just resets the allocation pointer.
 * Use this between iterations to reuse memory.
 */
void agent_context_reset(agent_context_t* ctx);

/**
 * @brief Create a savepoint for partial reset
 * @param ctx Context
 * @return Savepoint value
 */
size_t agent_context_savepoint(agent_context_t* ctx);

/**
 * @brief Restore to a previous savepoint
 * @param ctx Context
 * @param savepoint Savepoint value from agent_context_savepoint
 */
void agent_context_restore(agent_context_t* ctx, size_t savepoint);

/**
 * @brief Get current memory usage
 * @param ctx Context
 * @return Number of bytes currently allocated
 */
size_t agent_context_used(agent_context_t* ctx);

/**
 * @brief Get total memory capacity
 * @param ctx Context
 * @return Total arena capacity in bytes
 */
size_t agent_context_capacity(agent_context_t* ctx);

/**
 * @brief Duplicate a string into the arena
 * @param ctx Context
 * @param str String to duplicate
 * @return New string in arena, or NULL on failure
 */
char* agent_context_strdup(agent_context_t* ctx, const char* str);

/**
 * @brief Duplicate a string with length into the arena
 * @param ctx Context
 * @param str String to duplicate
 * @param len Length of string
 * @return New null-terminated string in arena, or NULL on failure
 */
char* agent_context_strndup(agent_context_t* ctx, const char* str, size_t len);

/**
 * @brief Create a string view from a string in the arena
 * @param ctx Context
 * @param str String to copy
 * @return String view pointing to arena copy
 */
agent_string_view_t agent_context_string_view(agent_context_t* ctx, const char* str);

/**
 * @brief Create a string view from a string with length
 * @param ctx Context
 * @param str String to copy
 * @param len Length of string
 * @return String view pointing to arena copy
 */
agent_string_view_t agent_context_string_view_n(agent_context_t* ctx, const char* str, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_CONTEXT_H */
