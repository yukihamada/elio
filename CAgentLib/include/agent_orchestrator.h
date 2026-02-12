/**
 * @file agent_orchestrator.h
 * @brief Agent orchestrator - main agent loop
 */

#ifndef AGENT_ORCHESTRATOR_H
#define AGENT_ORCHESTRATOR_H

#include "agent_types.h"
#include "agent_context.h"
#include "agent_json.h"
#include "agent_parser.h"
#include "agent_mcp.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Maximum number of agent iterations
 */
#define AGENT_MAX_ITERATIONS 10

/**
 * @brief Maximum tool result length before truncation
 */
#define AGENT_MAX_TOOL_RESULT_LENGTH 3000

/**
 * @brief Agent configuration
 */
typedef struct {
    /* Callbacks - required */
    agent_llm_generate_callback_t generate;
    agent_tool_execute_callback_t execute_tool;

    /* Callbacks - optional */
    agent_token_callback_t on_token;
    agent_tool_call_notify_t on_tool_call;
    agent_step_callback_t on_step_change;

    /* Schema callback (returns tool schema JSON) */
    agent_tools_schema_callback_t get_tools_schema;

    /* User data passed to all callbacks */
    void* user_data;

    /* Settings */
    int max_iterations;          /* 0 = use default (10) */
    size_t max_tool_result_len;  /* 0 = use default (3000) */
    bool use_japanese;           /* Use Japanese in prompts */

    /* Custom system prompt (appended to default) */
    const char* custom_system_prompt;
} agent_config_t;

/**
 * @brief Agent state
 */
typedef struct {
    agent_context_t* ctx;
    agent_config_t config;

    /* Message history */
    agent_message_array_t messages;

    /* Working history (includes tool messages) */
    agent_message_array_t working_history;

    /* Current state */
    agent_step_t current_step;
    int iteration_count;
    bool is_processing;
    bool should_stop;

    /* Streaming parser */
    agent_streaming_parser_t parser;

    /* Generated content in current turn */
    agent_string_t current_response;

    /* Extracted thinking content */
    agent_string_t thinking_content;
} agent_state_t;

/**
 * @brief Agent run result
 */
typedef struct {
    agent_error_t error;
    const char* error_message;

    /* Final assistant message */
    agent_string_view_t response;

    /* Tool calls made during this run */
    agent_tool_call_t* tool_calls;
    size_t tool_calls_count;

    /* Thinking content (if any) */
    agent_string_view_t thinking;

    /* Number of iterations used */
    int iterations;
} agent_run_result_t;

/**
 * @brief Initialize agent state
 * @param state Agent state to initialize
 * @param config Configuration
 * @return AGENT_OK on success
 */
agent_error_t agent_init(agent_state_t* state, const agent_config_t* config);

/**
 * @brief Free agent state
 * @param state Agent state to free
 */
void agent_free(agent_state_t* state);

/**
 * @brief Reset agent for new conversation
 * @param state Agent state
 */
void agent_reset(agent_state_t* state);

/**
 * @brief Add a user message
 * @param state Agent state
 * @param content Message content
 * @return AGENT_OK on success
 */
agent_error_t agent_add_user_message(agent_state_t* state, const char* content);

/**
 * @brief Add a user message with image
 * @param state Agent state
 * @param content Message content
 * @param image_data JPEG image data
 * @param image_size Image data size
 * @return AGENT_OK on success
 */
agent_error_t agent_add_user_message_with_image(agent_state_t* state,
                                                const char* content,
                                                const uint8_t* image_data,
                                                size_t image_size);

/**
 * @brief Add a system message
 * @param state Agent state
 * @param content Message content
 * @return AGENT_OK on success
 */
agent_error_t agent_add_system_message(agent_state_t* state, const char* content);

/**
 * @brief Run the agent (blocking)
 *
 * Processes messages and runs the agent loop until:
 * - Assistant generates a response without tool calls
 * - Maximum iterations reached
 * - Error occurs
 * - stop() is called
 *
 * @param state Agent state
 * @return Run result
 */
agent_run_result_t agent_run(agent_state_t* state);

/**
 * @brief Run the agent with streaming (blocking)
 *
 * Same as agent_run but calls on_token callback for each token.
 *
 * @param state Agent state
 * @return Run result
 */
agent_run_result_t agent_run_streaming(agent_state_t* state);

/**
 * @brief Request the agent to stop
 * @param state Agent state
 */
void agent_stop(agent_state_t* state);

/**
 * @brief Check if agent is currently processing
 * @param state Agent state
 * @return true if processing
 */
bool agent_is_processing(const agent_state_t* state);

/**
 * @brief Get current agent step
 * @param state Agent state
 * @return Current step
 */
agent_step_t agent_current_step(const agent_state_t* state);

/**
 * @brief Get message history
 * @param state Agent state
 * @param out_messages Output: pointer to messages array
 * @param out_count Output: number of messages
 */
void agent_get_messages(const agent_state_t* state,
                        const agent_message_t** out_messages,
                        size_t* out_count);

/**
 * @brief Build the system prompt
 * @param state Agent state
 * @return System prompt string (arena-allocated)
 */
char* agent_build_system_prompt(agent_state_t* state);

/**
 * @brief Execute a single tool call
 * @param state Agent state
 * @param tool_call Tool call to execute
 * @return Tool result
 */
agent_tool_result_t agent_execute_tool(agent_state_t* state,
                                       const agent_tool_call_t* tool_call);

/* Utility functions */

/**
 * @brief Truncate text to maximum length with ellipsis
 * @param ctx Arena context
 * @param text Text to truncate
 * @param max_len Maximum length
 * @return Truncated text
 */
char* agent_truncate_text(agent_context_t* ctx, const char* text, size_t max_len);

/**
 * @brief Format tool call for display
 * @param ctx Arena context
 * @param tool_call Tool call
 * @param japanese Use Japanese
 * @return Formatted string
 */
char* agent_format_tool_call(agent_context_t* ctx,
                             const agent_tool_call_t* tool_call,
                             bool japanese);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_ORCHESTRATOR_H */
