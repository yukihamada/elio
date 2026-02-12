/**
 * @file agent_types.h
 * @brief Core data types for the Agent Library
 */

#ifndef AGENT_TYPES_H
#define AGENT_TYPES_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declarations */
typedef struct agent_context_t agent_context_t;
typedef struct agent_json_value_t agent_json_value_t;

/**
 * @brief String view (non-owning reference to a string)
 */
typedef struct {
    const char* data;
    size_t length;
} agent_string_view_t;

/**
 * @brief Mutable string buffer
 */
typedef struct {
    char* data;
    size_t length;
    size_t capacity;
} agent_string_t;

/**
 * @brief UUID representation (128-bit)
 */
typedef struct {
    uint8_t bytes[16];
} agent_uuid_t;

/**
 * @brief Message role enum
 */
typedef enum {
    AGENT_ROLE_USER = 0,
    AGENT_ROLE_ASSISTANT = 1,
    AGENT_ROLE_SYSTEM = 2,
    AGENT_ROLE_TOOL = 3
} agent_role_t;

/**
 * @brief Agent step enum (for UI status)
 */
typedef enum {
    AGENT_STEP_NONE = 0,
    AGENT_STEP_THINKING = 1,
    AGENT_STEP_CALLING_TOOL = 2,
    AGENT_STEP_WAITING_FOR_RESULT = 3,
    AGENT_STEP_GENERATING = 4
} agent_step_t;

/**
 * @brief Tool call structure
 */
typedef struct {
    agent_uuid_t id;
    agent_string_view_t name;
    agent_json_value_t* arguments;  /* JSON object */
} agent_tool_call_t;

/**
 * @brief Tool result structure
 */
typedef struct {
    agent_uuid_t id;
    agent_uuid_t tool_call_id;
    agent_string_view_t content;
    bool is_error;
} agent_tool_result_t;

/**
 * @brief Message structure
 */
typedef struct {
    agent_uuid_t id;
    agent_role_t role;
    agent_string_view_t content;
    int64_t timestamp_ms;  /* Unix timestamp in milliseconds */

    /* Optional fields */
    agent_tool_call_t* tool_calls;
    size_t tool_calls_count;

    agent_tool_result_t* tool_results;
    size_t tool_results_count;

    agent_string_view_t thinking_content;

    /* Image data (JPEG) */
    const uint8_t* image_data;
    size_t image_data_size;
} agent_message_t;

/**
 * @brief Message array
 */
typedef struct {
    agent_message_t* messages;
    size_t count;
    size_t capacity;
} agent_message_array_t;

/**
 * @brief Tool call array
 */
typedef struct {
    agent_tool_call_t* items;
    size_t count;
    size_t capacity;
} agent_tool_call_array_t;

/**
 * @brief Parsed content type enum
 */
typedef enum {
    AGENT_CONTENT_TEXT = 0,
    AGENT_CONTENT_TOOL_CALL = 1,
    AGENT_CONTENT_THINKING = 2
} agent_content_type_t;

/**
 * @brief Parsed content (result of response parsing)
 */
typedef struct {
    agent_content_type_t type;
    union {
        agent_string_view_t text;
        struct {
            agent_string_view_t name;
            agent_json_value_t* arguments;
        } tool_call;
        agent_string_view_t thinking;
    } data;
} agent_parsed_content_t;

/**
 * @brief Parsed content array
 */
typedef struct {
    agent_parsed_content_t* items;
    size_t count;
    size_t capacity;
} agent_parsed_content_array_t;

/**
 * @brief Error codes
 */
typedef enum {
    AGENT_OK = 0,
    AGENT_ERROR_INVALID_ARGUMENT = -1,
    AGENT_ERROR_OUT_OF_MEMORY = -2,
    AGENT_ERROR_PARSE_ERROR = -3,
    AGENT_ERROR_INVALID_UTF8 = -4,
    AGENT_ERROR_BUFFER_TOO_SMALL = -5,
    AGENT_ERROR_NOT_FOUND = -6,
    AGENT_ERROR_MAX_ITERATIONS = -7,
    AGENT_ERROR_CALLBACK_FAILED = -8,
    AGENT_ERROR_CANCELLED = -9
} agent_error_t;

/**
 * @brief Result type for operations that may fail
 */
typedef struct {
    agent_error_t error;
    const char* error_message;
} agent_result_t;

/* Callback types for Swift bridging */

/**
 * @brief Token callback - called for each generated token
 * @param token The token string (UTF-8)
 * @param len Token length in bytes
 * @param user_data User-provided context
 * @return true to continue, false to stop generation
 */
typedef bool (*agent_token_callback_t)(const char* token, size_t len, void* user_data);

/**
 * @brief Tool call notification callback
 * @param tool_name The name of the tool being called
 * @param user_data User-provided context
 */
typedef void (*agent_tool_call_notify_t)(const char* tool_name, void* user_data);

/**
 * @brief Step change callback
 * @param step The new agent step
 * @param tool_name Tool name (if step is CALLING_TOOL, otherwise NULL)
 * @param user_data User-provided context
 */
typedef void (*agent_step_callback_t)(agent_step_t step, const char* tool_name, void* user_data);

/**
 * @brief LLM generation result
 */
typedef struct {
    agent_error_t error;
    agent_string_view_t text;
} agent_llm_result_t;

/**
 * @brief LLM generation callback
 * @param messages Array of messages
 * @param message_count Number of messages
 * @param system_prompt System prompt (may be NULL)
 * @param token_callback Callback for streaming tokens
 * @param user_data User-provided context
 * @return Generation result
 */
typedef agent_llm_result_t (*agent_llm_generate_callback_t)(
    const agent_message_t* messages,
    size_t message_count,
    const char* system_prompt,
    agent_token_callback_t token_callback,
    void* user_data
);

/**
 * @brief Tool execution result
 */
typedef struct {
    agent_error_t error;
    agent_string_view_t content;
    bool is_error;
} agent_tool_execute_result_t;

/**
 * @brief Tool execution callback
 * @param tool_name Full tool name (e.g., "filesystem.read_file")
 * @param arguments JSON arguments
 * @param user_data User-provided context
 * @return Execution result
 */
typedef agent_tool_execute_result_t (*agent_tool_execute_callback_t)(
    const char* tool_name,
    const agent_json_value_t* arguments,
    void* user_data
);

/**
 * @brief Tools schema callback (returns JSON schema string)
 * @param user_data User-provided context
 * @return JSON schema string (caller does NOT own this memory)
 */
typedef const char* (*agent_tools_schema_callback_t)(void* user_data);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_TYPES_H */
