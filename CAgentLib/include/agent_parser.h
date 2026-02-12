/**
 * @file agent_parser.h
 * @brief Response parser for tool calls and thinking tags
 */

#ifndef AGENT_PARSER_H
#define AGENT_PARSER_H

#include "agent_types.h"
#include "agent_context.h"
#include "agent_json.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Parser state for streaming
 */
typedef enum {
    PARSER_STATE_TEXT = 0,
    PARSER_STATE_TAG_OPEN = 1,
    PARSER_STATE_TOOL_CALL = 2,
    PARSER_STATE_THINK = 3,
    PARSER_STATE_TAG_CLOSE = 4
} agent_parser_state_t;

/**
 * @brief Streaming parser context
 */
typedef struct {
    agent_context_t* ctx;
    agent_parser_state_t state;

    /* Buffers */
    agent_string_t buffer;           /* Accumulated content */
    agent_string_t tag_buffer;       /* Current tag name */
    agent_string_t content_buffer;   /* Content within tags */

    /* State tracking */
    bool in_tool_call;
    bool in_think;
    int brace_depth;                 /* For JSON brace matching */

    /* Callbacks */
    void* user_data;
    void (*on_text)(const char* text, size_t len, void* user_data);
    void (*on_tool_call)(const char* name, const agent_json_value_t* args, void* user_data);
    void (*on_thinking)(const char* text, size_t len, void* user_data);
} agent_streaming_parser_t;

/**
 * @brief Parse result for tool call
 */
typedef struct {
    agent_string_view_t name;
    agent_json_value_t* arguments;
    agent_string_view_t raw_json;
} agent_parsed_tool_call_t;

/**
 * @brief Parse result for response
 */
typedef struct {
    agent_parsed_content_t* contents;
    size_t count;
    size_t capacity;
} agent_parse_result_t;

/* Static parsing (full response) */

/**
 * @brief Parse a complete LLM response
 *
 * Detects and extracts:
 * - <tool_call>...</tool_call> tags
 * - <think>...</think> or <thinking>...</thinking> tags
 * - Bare JSON tool calls (fallback)
 *
 * @param ctx Arena context
 * @param response Full response string
 * @param length Response length
 * @return Parse result with array of parsed content
 */
agent_parse_result_t agent_parser_parse(agent_context_t* ctx,
                                        const char* response, size_t length);

/**
 * @brief Parse a complete response (C string version)
 */
agent_parse_result_t agent_parser_parse_cstr(agent_context_t* ctx, const char* response);

/**
 * @brief Check if response contains a tool call
 * @param response Response string
 * @param length Response length
 * @return true if tool call tag found
 */
bool agent_parser_has_tool_call(const char* response, size_t length);

/**
 * @brief Check if response has incomplete tool call tag
 * @param response Response string
 * @param length Response length
 * @return true if opening tag without closing tag
 */
bool agent_parser_has_incomplete_tool_call(const char* response, size_t length);

/**
 * @brief Extract text before first tool call
 * @param ctx Arena context
 * @param response Response string
 * @param length Response length
 * @return Text before <tool_call>, or full response if none
 */
agent_string_view_t agent_parser_text_before_tool_call(agent_context_t* ctx,
                                                       const char* response, size_t length);

/**
 * @brief Extract text after tool result
 * @param ctx Arena context
 * @param response Response string
 * @param length Response length
 * @return Text after </tool_call>, or empty if none
 */
agent_string_view_t agent_parser_text_after_tool_call(agent_context_t* ctx,
                                                      const char* response, size_t length);

/**
 * @brief Parse thinking content from response
 * @param ctx Arena context
 * @param response Response string
 * @param length Response length
 * @param out_thinking Output: thinking content (may be empty)
 * @param out_content Output: content with thinking removed
 */
void agent_parser_extract_thinking(agent_context_t* ctx,
                                   const char* response, size_t length,
                                   agent_string_view_t* out_thinking,
                                   agent_string_view_t* out_content);

/* Streaming parsing */

/**
 * @brief Initialize streaming parser
 * @param parser Parser to initialize
 * @param ctx Arena context
 * @return AGENT_OK on success
 */
agent_error_t agent_streaming_parser_init(agent_streaming_parser_t* parser,
                                          agent_context_t* ctx);

/**
 * @brief Free streaming parser resources
 * @param parser Parser to free
 */
void agent_streaming_parser_free(agent_streaming_parser_t* parser);

/**
 * @brief Reset streaming parser for new response
 * @param parser Parser to reset
 */
void agent_streaming_parser_reset(agent_streaming_parser_t* parser);

/**
 * @brief Feed tokens to streaming parser
 * @param parser Parser
 * @param token Token string
 * @param length Token length
 * @return AGENT_OK on success
 */
agent_error_t agent_streaming_parser_feed(agent_streaming_parser_t* parser,
                                          const char* token, size_t length);

/**
 * @brief Flush any remaining content
 * @param parser Parser
 * @return AGENT_OK on success
 */
agent_error_t agent_streaming_parser_flush(agent_streaming_parser_t* parser);

/**
 * @brief Check if currently inside a tool call tag
 * @param parser Parser
 * @return true if inside <tool_call>...</tool_call>
 */
bool agent_streaming_parser_in_tool_call(const agent_streaming_parser_t* parser);

/* Tool call parsing utilities */

/**
 * @brief Parse JSON tool call
 *
 * Expected format: {"name": "...", "arguments": {...}}
 *
 * @param ctx Arena context
 * @param json JSON string
 * @param length JSON length
 * @return Parsed tool call or NULL on error
 */
agent_parsed_tool_call_t* agent_parser_parse_tool_call_json(agent_context_t* ctx,
                                                            const char* json, size_t length);

/**
 * @brief Find bare JSON tool call in response
 *
 * Searches for JSON object with "name" and "arguments" fields.
 *
 * @param ctx Arena context
 * @param response Response string
 * @param length Response length
 * @param out_before Output: text before JSON (may be NULL)
 * @param out_after Output: text after JSON (may be NULL)
 * @return Parsed tool call or NULL if not found
 */
agent_parsed_tool_call_t* agent_parser_find_bare_json(agent_context_t* ctx,
                                                      const char* response, size_t length,
                                                      agent_string_view_t* out_before,
                                                      agent_string_view_t* out_after);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_PARSER_H */
