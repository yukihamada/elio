/**
 * @file agent_orchestrator.c
 * @brief Agent orchestrator implementation
 */

#include "agent_orchestrator.h"
#include "agent_string.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define DEFAULT_MESSAGE_CAPACITY 32
#define DEFAULT_TOOL_CALLS_CAPACITY 8

/* System prompt templates */
static const char* SYSTEM_PROMPT_EN =
    "You are a helpful AI assistant. You have access to various tools to help accomplish tasks.\n\n"
    "When you need to use a tool, output a tool call in this format:\n"
    "<tool_call>\n"
    "{\"name\": \"tool_name\", \"arguments\": {\"arg1\": \"value1\"}}\n"
    "</tool_call>\n\n"
    "Available tools:\n%s\n";

static const char* SYSTEM_PROMPT_JA =
    "あなたは便利なAIアシスタントです。タスクを達成するためにさまざまなツールを使用できます。\n\n"
    "ツールを使用する必要がある場合は、次の形式でツール呼び出しを出力してください：\n"
    "<tool_call>\n"
    "{\"name\": \"ツール名\", \"arguments\": {\"引数1\": \"値1\"}}\n"
    "</tool_call>\n\n"
    "利用可能なツール:\n%s\n";

/* Helper to get current time in milliseconds */
static int64_t current_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Helper to add message to array */
static agent_error_t message_array_add(agent_context_t* ctx,
                                       agent_message_array_t* arr,
                                       agent_message_t* msg) {
    if (arr->count >= arr->capacity) {
        size_t new_capacity = arr->capacity * 2;
        agent_message_t* new_messages = agent_context_calloc(ctx, new_capacity, sizeof(agent_message_t));
        if (!new_messages) {
            return AGENT_ERROR_OUT_OF_MEMORY;
        }
        memcpy(new_messages, arr->messages, arr->count * sizeof(agent_message_t));
        arr->messages = new_messages;
        arr->capacity = new_capacity;
    }

    arr->messages[arr->count++] = *msg;
    return AGENT_OK;
}

/* Initialize agent */
agent_error_t agent_init(agent_state_t* state, const agent_config_t* config) {
    if (!state || !config) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    if (!config->generate || !config->execute_tool) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    memset(state, 0, sizeof(agent_state_t));

    /* Create arena context */
    state->ctx = agent_context_create(0);
    if (!state->ctx) {
        return AGENT_ERROR_OUT_OF_MEMORY;
    }

    state->config = *config;

    /* Set defaults */
    if (state->config.max_iterations <= 0) {
        state->config.max_iterations = AGENT_MAX_ITERATIONS;
    }
    if (state->config.max_tool_result_len == 0) {
        state->config.max_tool_result_len = AGENT_MAX_TOOL_RESULT_LENGTH;
    }

    /* Initialize message arrays */
    state->messages.messages = agent_context_calloc(state->ctx, DEFAULT_MESSAGE_CAPACITY, sizeof(agent_message_t));
    state->messages.capacity = DEFAULT_MESSAGE_CAPACITY;

    state->working_history.messages = agent_context_calloc(state->ctx, DEFAULT_MESSAGE_CAPACITY, sizeof(agent_message_t));
    state->working_history.capacity = DEFAULT_MESSAGE_CAPACITY;

    /* Initialize streaming parser */
    agent_error_t err = agent_streaming_parser_init(&state->parser, state->ctx);
    if (err != AGENT_OK) {
        agent_context_destroy(state->ctx);
        return err;
    }

    /* Initialize response buffer */
    err = agent_string_init(&state->current_response, 1024);
    if (err != AGENT_OK) {
        agent_streaming_parser_free(&state->parser);
        agent_context_destroy(state->ctx);
        return err;
    }

    /* Initialize thinking buffer */
    err = agent_string_init(&state->thinking_content, 256);
    if (err != AGENT_OK) {
        agent_string_free(&state->current_response);
        agent_streaming_parser_free(&state->parser);
        agent_context_destroy(state->ctx);
        return err;
    }

    return AGENT_OK;
}

void agent_free(agent_state_t* state) {
    if (!state) return;

    agent_string_free(&state->current_response);
    agent_string_free(&state->thinking_content);
    agent_streaming_parser_free(&state->parser);
    agent_context_destroy(state->ctx);

    memset(state, 0, sizeof(agent_state_t));
}

void agent_reset(agent_state_t* state) {
    if (!state) return;

    /* Reset arena (keeps first block) */
    agent_context_reset(state->ctx);

    /* Reinitialize arrays */
    state->messages.messages = agent_context_calloc(state->ctx, DEFAULT_MESSAGE_CAPACITY, sizeof(agent_message_t));
    state->messages.count = 0;
    state->messages.capacity = DEFAULT_MESSAGE_CAPACITY;

    state->working_history.messages = agent_context_calloc(state->ctx, DEFAULT_MESSAGE_CAPACITY, sizeof(agent_message_t));
    state->working_history.count = 0;
    state->working_history.capacity = DEFAULT_MESSAGE_CAPACITY;

    /* Reset state */
    state->current_step = AGENT_STEP_NONE;
    state->iteration_count = 0;
    state->is_processing = false;
    state->should_stop = false;

    agent_string_clear(&state->current_response);
    agent_string_clear(&state->thinking_content);
    agent_streaming_parser_reset(&state->parser);
}

agent_error_t agent_add_user_message(agent_state_t* state, const char* content) {
    return agent_add_user_message_with_image(state, content, NULL, 0);
}

agent_error_t agent_add_user_message_with_image(agent_state_t* state,
                                                const char* content,
                                                const uint8_t* image_data,
                                                size_t image_size) {
    if (!state || !content) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    agent_message_t msg = {0};
    msg.id = agent_uuid_generate();
    msg.role = AGENT_ROLE_USER;
    msg.content = agent_context_string_view(state->ctx, content);
    msg.timestamp_ms = current_time_ms();

    if (image_data && image_size > 0) {
        uint8_t* img_copy = agent_context_alloc(state->ctx, image_size);
        if (img_copy) {
            memcpy(img_copy, image_data, image_size);
            msg.image_data = img_copy;
            msg.image_data_size = image_size;
        }
    }

    return message_array_add(state->ctx, &state->messages, &msg);
}

agent_error_t agent_add_system_message(agent_state_t* state, const char* content) {
    if (!state || !content) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    agent_message_t msg = {0};
    msg.id = agent_uuid_generate();
    msg.role = AGENT_ROLE_SYSTEM;
    msg.content = agent_context_string_view(state->ctx, content);
    msg.timestamp_ms = current_time_ms();

    return message_array_add(state->ctx, &state->messages, &msg);
}

char* agent_build_system_prompt(agent_state_t* state) {
    if (!state) return NULL;

    const char* tools_schema = "";
    if (state->config.get_tools_schema) {
        tools_schema = state->config.get_tools_schema(state->config.user_data);
        if (!tools_schema) tools_schema = "";
    }

    const char* template = state->config.use_japanese ? SYSTEM_PROMPT_JA : SYSTEM_PROMPT_EN;

    agent_string_t prompt;
    if (agent_string_init(&prompt, 2048) != AGENT_OK) {
        return NULL;
    }

    agent_string_append_fmt(&prompt, template, tools_schema);

    if (state->config.custom_system_prompt) {
        agent_string_append(&prompt, "\n\n");
        agent_string_append(&prompt, state->config.custom_system_prompt);
    }

    char* result = agent_context_strdup(state->ctx, prompt.data);
    agent_string_free(&prompt);
    return result;
}

/* Set step and notify callback */
static void set_step(agent_state_t* state, agent_step_t step, const char* tool_name) {
    state->current_step = step;
    if (state->config.on_step_change) {
        state->config.on_step_change(step, tool_name, state->config.user_data);
    }
}

/* Execute tool */
agent_tool_result_t agent_execute_tool(agent_state_t* state,
                                       const agent_tool_call_t* tool_call) {
    agent_tool_result_t result = {0};
    result.id = agent_uuid_generate();
    result.tool_call_id = tool_call->id;

    if (!state || !tool_call) {
        result.is_error = true;
        result.content = agent_sv_from_cstr("Invalid tool call");
        return result;
    }

    /* Notify tool call */
    if (state->config.on_tool_call) {
        state->config.on_tool_call(tool_call->name.data, state->config.user_data);
    }

    set_step(state, AGENT_STEP_CALLING_TOOL, tool_call->name.data);

    /* Execute via callback */
    agent_tool_execute_result_t exec_result = state->config.execute_tool(
        tool_call->name.data,
        tool_call->arguments,
        state->config.user_data
    );

    result.is_error = exec_result.is_error;

    /* Truncate result if needed */
    if (exec_result.content.length > state->config.max_tool_result_len) {
        char* truncated = agent_truncate_text(state->ctx, exec_result.content.data,
                                              state->config.max_tool_result_len);
        result.content = agent_sv_from_cstr(truncated);
    } else {
        result.content = agent_context_string_view_n(state->ctx,
            exec_result.content.data, exec_result.content.length);
    }

    set_step(state, AGENT_STEP_WAITING_FOR_RESULT, NULL);

    return result;
}

/* Streaming token callback wrapper */
typedef struct {
    agent_state_t* state;
    bool detected_tool_call;
} stream_context_t;

static bool streaming_token_callback(const char* token, size_t len, void* user_data) {
    stream_context_t* ctx = (stream_context_t*)user_data;
    agent_state_t* state = ctx->state;

    if (state->should_stop) {
        return false;
    }

    /* Append to current response */
    agent_string_append_n(&state->current_response, token, len);

    /* Check for tool call start */
    if (!ctx->detected_tool_call && agent_parser_has_incomplete_tool_call(
            state->current_response.data, state->current_response.length)) {
        ctx->detected_tool_call = true;
        set_step(state, AGENT_STEP_THINKING, NULL);
    }

    /* Pass through to user callback if not in tool call */
    if (!ctx->detected_tool_call && state->config.on_token) {
        return state->config.on_token(token, len, state->config.user_data);
    }

    return true;
}

/* Process a single iteration */
static agent_error_t process_iteration(agent_state_t* state,
                                       agent_tool_call_array_t* all_tool_calls,
                                       bool* has_tool_call) {
    *has_tool_call = false;

    /* Build system prompt */
    char* system_prompt = agent_build_system_prompt(state);

    /* Set up streaming context */
    stream_context_t stream_ctx = {
        .state = state,
        .detected_tool_call = false
    };

    set_step(state, AGENT_STEP_GENERATING, NULL);
    agent_string_clear(&state->current_response);

    /* Call LLM */
    agent_llm_result_t llm_result = state->config.generate(
        state->working_history.messages,
        state->working_history.count,
        system_prompt,
        streaming_token_callback,
        &stream_ctx
    );

    if (llm_result.error != AGENT_OK) {
        return llm_result.error;
    }

    if (state->should_stop) {
        return AGENT_ERROR_CANCELLED;
    }

    /* Parse response */
    agent_parse_result_t parse_result = agent_parser_parse(
        state->ctx,
        state->current_response.data,
        state->current_response.length
    );

    /* Process parsed content */
    agent_string_t text_content;
    agent_string_init(&text_content, 256);

    for (size_t i = 0; i < parse_result.count; i++) {
        agent_parsed_content_t* content = &parse_result.contents[i];

        switch (content->type) {
            case AGENT_CONTENT_TEXT:
                agent_string_append_sv(&text_content, content->data.text);
                agent_string_append(&text_content, " ");
                break;

            case AGENT_CONTENT_THINKING:
                agent_string_append_sv(&state->thinking_content, content->data.thinking);
                break;

            case AGENT_CONTENT_TOOL_CALL: {
                *has_tool_call = true;

                /* Create tool call */
                agent_tool_call_t tc = {0};
                tc.id = agent_uuid_generate();
                tc.name = content->data.tool_call.name;
                tc.arguments = content->data.tool_call.arguments;

                /* Add to array */
                if (all_tool_calls->count >= all_tool_calls->capacity) {
                    size_t new_cap = all_tool_calls->capacity * 2;
                    agent_tool_call_t* new_items = agent_context_calloc(
                        state->ctx, new_cap, sizeof(agent_tool_call_t));
                    if (!new_items) {
                        agent_string_free(&text_content);
                        return AGENT_ERROR_OUT_OF_MEMORY;
                    }
                    memcpy(new_items, all_tool_calls->items,
                           all_tool_calls->count * sizeof(agent_tool_call_t));
                    all_tool_calls->items = new_items;
                    all_tool_calls->capacity = new_cap;
                }
                all_tool_calls->items[all_tool_calls->count++] = tc;

                /* Execute tool */
                agent_tool_result_t result = agent_execute_tool(state, &tc);

                /* Add tool message to working history */
                agent_message_t tool_msg = {0};
                tool_msg.id = agent_uuid_generate();
                tool_msg.role = AGENT_ROLE_TOOL;
                tool_msg.content = result.content;
                tool_msg.timestamp_ms = current_time_ms();
                tool_msg.tool_results = agent_context_alloc(state->ctx, sizeof(agent_tool_result_t));
                if (tool_msg.tool_results) {
                    tool_msg.tool_results[0] = result;
                    tool_msg.tool_results_count = 1;
                }

                message_array_add(state->ctx, &state->working_history, &tool_msg);
                break;
            }
        }
    }

    /* Add assistant message to working history */
    if (text_content.length > 0 || !*has_tool_call) {
        agent_message_t assistant_msg = {0};
        assistant_msg.id = agent_uuid_generate();
        assistant_msg.role = AGENT_ROLE_ASSISTANT;
        assistant_msg.content = agent_context_string_view(state->ctx, text_content.data);
        assistant_msg.timestamp_ms = current_time_ms();

        if (state->thinking_content.length > 0) {
            assistant_msg.thinking_content = agent_context_string_view(
                state->ctx, state->thinking_content.data);
        }

        /* Attach tool calls if any in this iteration */
        if (*has_tool_call) {
            assistant_msg.tool_calls = all_tool_calls->items + (all_tool_calls->count - 1);
            assistant_msg.tool_calls_count = 1;  /* Just the latest one for this message */
        }

        message_array_add(state->ctx, &state->working_history, &assistant_msg);
    }

    agent_string_free(&text_content);
    return AGENT_OK;
}

agent_run_result_t agent_run(agent_state_t* state) {
    return agent_run_streaming(state);
}

agent_run_result_t agent_run_streaming(agent_state_t* state) {
    agent_run_result_t result = {0};

    if (!state) {
        result.error = AGENT_ERROR_INVALID_ARGUMENT;
        result.error_message = "Invalid state";
        return result;
    }

    if (state->is_processing) {
        result.error = AGENT_ERROR_INVALID_ARGUMENT;
        result.error_message = "Already processing";
        return result;
    }

    state->is_processing = true;
    state->should_stop = false;
    state->iteration_count = 0;
    agent_string_clear(&state->thinking_content);

    /* Copy messages to working history */
    state->working_history.count = 0;
    for (size_t i = 0; i < state->messages.count; i++) {
        message_array_add(state->ctx, &state->working_history, &state->messages.messages[i]);
    }

    /* Track all tool calls */
    agent_tool_call_array_t tool_calls = {0};
    tool_calls.items = agent_context_calloc(state->ctx, DEFAULT_TOOL_CALLS_CAPACITY, sizeof(agent_tool_call_t));
    tool_calls.capacity = DEFAULT_TOOL_CALLS_CAPACITY;

    /* Main loop */
    bool has_tool_call = true;
    while (has_tool_call && state->iteration_count < state->config.max_iterations) {
        state->iteration_count++;

        agent_error_t err = process_iteration(state, &tool_calls, &has_tool_call);
        if (err != AGENT_OK) {
            result.error = err;
            if (err == AGENT_ERROR_CANCELLED) {
                result.error_message = "Cancelled";
            } else {
                result.error_message = "Processing error";
            }
            break;
        }

        if (state->should_stop) {
            result.error = AGENT_ERROR_CANCELLED;
            result.error_message = "Stopped";
            break;
        }
    }

    /* Check if max iterations reached */
    if (has_tool_call && state->iteration_count >= state->config.max_iterations) {
        result.error = AGENT_ERROR_MAX_ITERATIONS;
        result.error_message = "Maximum iterations reached";
    }

    /* Build result */
    if (result.error == AGENT_OK || result.error == AGENT_ERROR_MAX_ITERATIONS) {
        /* Find last assistant message */
        for (size_t i = state->working_history.count; i > 0; i--) {
            agent_message_t* msg = &state->working_history.messages[i - 1];
            if (msg->role == AGENT_ROLE_ASSISTANT) {
                result.response = msg->content;
                break;
            }
        }

        result.tool_calls = tool_calls.items;
        result.tool_calls_count = tool_calls.count;

        if (state->thinking_content.length > 0) {
            result.thinking = agent_context_string_view(state->ctx, state->thinking_content.data);
        }
    }

    result.iterations = state->iteration_count;
    state->is_processing = false;
    set_step(state, AGENT_STEP_NONE, NULL);

    /* Add final message to main history */
    if (result.response.length > 0) {
        agent_message_t final_msg = {0};
        final_msg.id = agent_uuid_generate();
        final_msg.role = AGENT_ROLE_ASSISTANT;
        final_msg.content = result.response;
        final_msg.timestamp_ms = current_time_ms();
        final_msg.thinking_content = result.thinking;
        final_msg.tool_calls = result.tool_calls;
        final_msg.tool_calls_count = result.tool_calls_count;

        message_array_add(state->ctx, &state->messages, &final_msg);
    }

    return result;
}

void agent_stop(agent_state_t* state) {
    if (state) {
        state->should_stop = true;
    }
}

bool agent_is_processing(const agent_state_t* state) {
    return state ? state->is_processing : false;
}

agent_step_t agent_current_step(const agent_state_t* state) {
    return state ? state->current_step : AGENT_STEP_NONE;
}

void agent_get_messages(const agent_state_t* state,
                        const agent_message_t** out_messages,
                        size_t* out_count) {
    if (!state) {
        if (out_messages) *out_messages = NULL;
        if (out_count) *out_count = 0;
        return;
    }

    if (out_messages) *out_messages = state->messages.messages;
    if (out_count) *out_count = state->messages.count;
}

/* Utility functions */

char* agent_truncate_text(agent_context_t* ctx, const char* text, size_t max_len) {
    if (!ctx || !text) return NULL;

    size_t len = strlen(text);
    if (len <= max_len) {
        return agent_context_strdup(ctx, text);
    }

    /* Find UTF-8 boundary */
    size_t boundary = agent_utf8_complete_boundary(text, max_len - 3);  /* -3 for "..." */

    char* result = agent_context_alloc(ctx, boundary + 4);
    if (!result) return NULL;

    memcpy(result, text, boundary);
    memcpy(result + boundary, "...", 4);  /* includes null terminator */

    return result;
}

char* agent_format_tool_call(agent_context_t* ctx,
                             const agent_tool_call_t* tool_call,
                             bool japanese) {
    if (!ctx || !tool_call) return NULL;

    agent_string_t str;
    if (agent_string_init(&str, 256) != AGENT_OK) {
        return NULL;
    }

    if (japanese) {
        agent_string_append(&str, "ツール: ");
    } else {
        agent_string_append(&str, "Tool: ");
    }

    agent_string_append_sv(&str, tool_call->name);

    if (tool_call->arguments && tool_call->arguments->type == AGENT_JSON_OBJECT) {
        agent_string_append(&str, "\n");
        if (japanese) {
            agent_string_append(&str, "引数:\n");
        } else {
            agent_string_append(&str, "Arguments:\n");
        }

        size_t count = tool_call->arguments->data.object_value.count;
        for (size_t i = 0; i < count; i++) {
            agent_json_entry_t* entry = &tool_call->arguments->data.object_value.entries[i];
            agent_string_append(&str, "  - ");
            agent_string_append_sv(&str, entry->key);
            agent_string_append(&str, ": ");

            /* Serialize value */
            char* value_str = agent_json_to_string(ctx, entry->value, false);
            if (value_str) {
                agent_string_append(&str, value_str);
            }
            agent_string_append(&str, "\n");
        }
    }

    char* result = agent_context_strdup(ctx, str.data);
    agent_string_free(&str);
    return result;
}
