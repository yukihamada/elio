/**
 * @file agent_parser.c
 * @brief Response parser implementation
 */

#include "agent_parser.h"
#include "agent_string.h"
#include <string.h>
#include <stdlib.h>

/* Tag constants */
static const char* TAG_TOOL_CALL_OPEN = "<tool_call>";
static const char* TAG_TOOL_CALL_CLOSE = "</tool_call>";
static const char* TAG_THINK_OPEN = "<think>";
static const char* TAG_THINK_CLOSE = "</think>";
static const char* TAG_THINKING_OPEN = "<thinking>";
static const char* TAG_THINKING_CLOSE = "</thinking>";

#define TAG_TOOL_CALL_OPEN_LEN 11
#define TAG_TOOL_CALL_CLOSE_LEN 12
#define TAG_THINK_OPEN_LEN 7
#define TAG_THINK_CLOSE_LEN 8
#define TAG_THINKING_OPEN_LEN 10
#define TAG_THINKING_CLOSE_LEN 11

/* Helper: find substring in buffer */
static const char* find_substr(const char* haystack, size_t haystack_len,
                               const char* needle, size_t needle_len) {
    if (needle_len == 0) return haystack;
    if (needle_len > haystack_len) return NULL;

    const char* end = haystack + haystack_len - needle_len + 1;
    for (const char* p = haystack; p < end; p++) {
        if (memcmp(p, needle, needle_len) == 0) {
            return p;
        }
    }
    return NULL;
}

/* Helper: find matching brace */
static const char* find_matching_brace(const char* start, size_t length) {
    if (length == 0 || *start != '{') return NULL;

    int depth = 0;
    bool in_string = false;
    bool escape = false;

    for (size_t i = 0; i < length; i++) {
        char c = start[i];

        if (escape) {
            escape = false;
            continue;
        }

        if (c == '\\' && in_string) {
            escape = true;
            continue;
        }

        if (c == '"') {
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (c == '{') {
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth == 0) {
                    return start + i;
                }
            }
        }
    }

    return NULL;
}

/* Parse tool call JSON */
agent_parsed_tool_call_t* agent_parser_parse_tool_call_json(agent_context_t* ctx,
                                                            const char* json, size_t length) {
    if (!ctx || !json || length == 0) {
        return NULL;
    }

    agent_json_parse_result_t result = agent_json_parse(ctx, json, length);
    if (result.error != AGENT_OK || !result.value) {
        return NULL;
    }

    if (result.value->type != AGENT_JSON_OBJECT) {
        return NULL;
    }

    /* Get "name" field */
    agent_json_value_t* name_val = agent_json_object_get(result.value, "name");
    if (!name_val || name_val->type != AGENT_JSON_STRING) {
        return NULL;
    }

    /* Get "arguments" field */
    agent_json_value_t* args_val = agent_json_object_get(result.value, "arguments");
    if (!args_val) {
        /* Create empty object if no arguments */
        args_val = agent_json_object(ctx, 0);
    }

    agent_parsed_tool_call_t* tc = agent_context_alloc(ctx, sizeof(agent_parsed_tool_call_t));
    if (!tc) {
        return NULL;
    }

    tc->name = name_val->data.string_value;
    tc->arguments = args_val;
    tc->raw_json = agent_context_string_view_n(ctx, json, length);

    return tc;
}

/* Find bare JSON tool call */
agent_parsed_tool_call_t* agent_parser_find_bare_json(agent_context_t* ctx,
                                                      const char* response, size_t length,
                                                      agent_string_view_t* out_before,
                                                      agent_string_view_t* out_after) {
    if (!ctx || !response || length == 0) {
        return NULL;
    }

    /* Search for "name" pattern followed by colon */
    const char* name_pattern = "\"name\"";
    const char* found = find_substr(response, length, name_pattern, 6);
    if (!found) {
        return NULL;
    }

    /* Scan backward to find opening brace */
    const char* json_start = NULL;
    for (const char* p = found - 1; p >= response; p--) {
        if (*p == '{') {
            json_start = p;
            break;
        } else if (*p != ' ' && *p != '\t' && *p != '\n' && *p != '\r') {
            /* Found non-whitespace before "name" - not a bare JSON */
            break;
        }
    }

    if (!json_start) {
        return NULL;
    }

    /* Find matching closing brace */
    size_t remaining = length - (size_t)(json_start - response);
    const char* json_end = find_matching_brace(json_start, remaining);
    if (!json_end) {
        return NULL;
    }

    size_t json_len = (size_t)(json_end - json_start) + 1;

    /* Check for "arguments" field */
    const char* args_pattern = "\"arguments\"";
    if (!find_substr(json_start, json_len, args_pattern, 11)) {
        return NULL;
    }

    /* Parse the JSON */
    agent_parsed_tool_call_t* tc = agent_parser_parse_tool_call_json(ctx, json_start, json_len);
    if (!tc) {
        return NULL;
    }

    /* Set before/after if requested */
    if (out_before) {
        size_t before_len = (size_t)(json_start - response);
        *out_before = agent_context_string_view_n(ctx, response, before_len);
    }

    if (out_after) {
        const char* after_start = json_end + 1;
        size_t after_len = length - (size_t)(after_start - response);
        *out_after = agent_context_string_view_n(ctx, after_start, after_len);
    }

    return tc;
}

/* Check for tool call tag */
bool agent_parser_has_tool_call(const char* response, size_t length) {
    if (!response || length == 0) {
        return false;
    }

    const char* open = find_substr(response, length, TAG_TOOL_CALL_OPEN, TAG_TOOL_CALL_OPEN_LEN);
    if (!open) {
        return false;
    }

    size_t remaining = length - (size_t)(open - response);
    const char* close = find_substr(open, remaining, TAG_TOOL_CALL_CLOSE, TAG_TOOL_CALL_CLOSE_LEN);
    return close != NULL;
}

bool agent_parser_has_incomplete_tool_call(const char* response, size_t length) {
    if (!response || length == 0) {
        return false;
    }

    const char* open = find_substr(response, length, TAG_TOOL_CALL_OPEN, TAG_TOOL_CALL_OPEN_LEN);
    if (!open) {
        return false;
    }

    size_t remaining = length - (size_t)(open - response);
    const char* close = find_substr(open, remaining, TAG_TOOL_CALL_CLOSE, TAG_TOOL_CALL_CLOSE_LEN);
    return close == NULL;
}

agent_string_view_t agent_parser_text_before_tool_call(agent_context_t* ctx,
                                                       const char* response, size_t length) {
    agent_string_view_t result = {NULL, 0};

    if (!ctx || !response) {
        return result;
    }

    const char* tag = find_substr(response, length, TAG_TOOL_CALL_OPEN, TAG_TOOL_CALL_OPEN_LEN);
    if (tag) {
        size_t before_len = (size_t)(tag - response);
        result = agent_context_string_view_n(ctx, response, before_len);
        result = agent_sv_trim(result);
    } else {
        result = agent_context_string_view_n(ctx, response, length);
        result = agent_sv_trim(result);
    }

    return result;
}

agent_string_view_t agent_parser_text_after_tool_call(agent_context_t* ctx,
                                                      const char* response, size_t length) {
    agent_string_view_t result = {NULL, 0};

    if (!ctx || !response) {
        return result;
    }

    const char* close = find_substr(response, length, TAG_TOOL_CALL_CLOSE, TAG_TOOL_CALL_CLOSE_LEN);
    if (close) {
        const char* after_start = close + TAG_TOOL_CALL_CLOSE_LEN;
        size_t after_len = length - (size_t)(after_start - response);
        result = agent_context_string_view_n(ctx, after_start, after_len);
        result = agent_sv_trim(result);
    }

    return result;
}

/* Extract thinking content */
void agent_parser_extract_thinking(agent_context_t* ctx,
                                   const char* response, size_t length,
                                   agent_string_view_t* out_thinking,
                                   agent_string_view_t* out_content) {
    if (!ctx || !response) {
        if (out_thinking) *out_thinking = (agent_string_view_t){NULL, 0};
        if (out_content) *out_content = (agent_string_view_t){NULL, 0};
        return;
    }

    /* Try <think> first, then <thinking> */
    const char* open_tag = NULL;
    const char* close_tag = NULL;
    size_t open_len = 0;
    size_t close_len = 0;

    open_tag = find_substr(response, length, TAG_THINK_OPEN, TAG_THINK_OPEN_LEN);
    if (open_tag) {
        open_len = TAG_THINK_OPEN_LEN;
        size_t remaining = length - (size_t)(open_tag - response);
        close_tag = find_substr(open_tag, remaining, TAG_THINK_CLOSE, TAG_THINK_CLOSE_LEN);
        close_len = TAG_THINK_CLOSE_LEN;
    }

    if (!open_tag) {
        open_tag = find_substr(response, length, TAG_THINKING_OPEN, TAG_THINKING_OPEN_LEN);
        if (open_tag) {
            open_len = TAG_THINKING_OPEN_LEN;
            size_t remaining = length - (size_t)(open_tag - response);
            close_tag = find_substr(open_tag, remaining, TAG_THINKING_CLOSE, TAG_THINKING_CLOSE_LEN);
            close_len = TAG_THINKING_CLOSE_LEN;
        }
    }

    /* Handle case where only closing tag is present (thinking was in prompt) */
    if (!open_tag) {
        close_tag = find_substr(response, length, TAG_THINK_CLOSE, TAG_THINK_CLOSE_LEN);
        if (!close_tag) {
            close_tag = find_substr(response, length, TAG_THINKING_CLOSE, TAG_THINKING_CLOSE_LEN);
            close_len = TAG_THINKING_CLOSE_LEN;
        } else {
            close_len = TAG_THINK_CLOSE_LEN;
        }

        if (close_tag) {
            /* Everything before close tag is thinking */
            if (out_thinking) {
                size_t think_len = (size_t)(close_tag - response);
                *out_thinking = agent_context_string_view_n(ctx, response, think_len);
                *out_thinking = agent_sv_trim(*out_thinking);
            }
            if (out_content) {
                const char* after = close_tag + close_len;
                size_t after_len = length - (size_t)(after - response);
                *out_content = agent_context_string_view_n(ctx, after, after_len);
                *out_content = agent_sv_trim(*out_content);
            }
            return;
        }
    }

    if (open_tag && close_tag) {
        /* Extract thinking content */
        if (out_thinking) {
            const char* think_start = open_tag + open_len;
            size_t think_len = (size_t)(close_tag - think_start);
            *out_thinking = agent_context_string_view_n(ctx, think_start, think_len);
            *out_thinking = agent_sv_trim(*out_thinking);
        }

        /* Build content without thinking */
        if (out_content) {
            size_t before_len = (size_t)(open_tag - response);
            const char* after = close_tag + close_len;
            size_t after_len = length - (size_t)(after - response);

            size_t total_len = before_len + after_len;
            char* content = agent_context_alloc(ctx, total_len + 1);
            if (content) {
                if (before_len > 0) {
                    memcpy(content, response, before_len);
                }
                if (after_len > 0) {
                    memcpy(content + before_len, after, after_len);
                }
                content[total_len] = '\0';
                *out_content = agent_sv_from_parts(content, total_len);
                *out_content = agent_sv_trim(*out_content);
            }
        }
    } else {
        /* No thinking tags found */
        if (out_thinking) {
            *out_thinking = (agent_string_view_t){NULL, 0};
        }
        if (out_content) {
            *out_content = agent_context_string_view_n(ctx, response, length);
        }
    }
}

/* Parse complete response */
agent_parse_result_t agent_parser_parse(agent_context_t* ctx,
                                        const char* response, size_t length) {
    agent_parse_result_t result = {NULL, 0, 0};

    if (!ctx || !response || length == 0) {
        return result;
    }

    /* Allocate initial array */
    result.capacity = 4;
    result.contents = agent_context_calloc(ctx, result.capacity, sizeof(agent_parsed_content_t));
    if (!result.contents) {
        return result;
    }

    /* First, try to find <tool_call> tags */
    const char* pos = response;
    size_t remaining = length;

    while (remaining > 0) {
        const char* tool_open = find_substr(pos, remaining, TAG_TOOL_CALL_OPEN, TAG_TOOL_CALL_OPEN_LEN);

        if (!tool_open) {
            /* No more tool calls - check for bare JSON */
            agent_string_view_t before, after;
            agent_parsed_tool_call_t* bare_tc = agent_parser_find_bare_json(ctx, pos, remaining, &before, &after);

            if (bare_tc) {
                /* Add text before */
                if (before.length > 0) {
                    agent_string_view_t trimmed = agent_sv_trim(before);
                    if (trimmed.length > 0) {
                        if (result.count >= result.capacity) {
                            /* Expand array */
                            size_t new_cap = result.capacity * 2;
                            agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                            if (!new_arr) return result;
                            memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                            result.contents = new_arr;
                            result.capacity = new_cap;
                        }
                        result.contents[result.count].type = AGENT_CONTENT_TEXT;
                        result.contents[result.count].data.text = trimmed;
                        result.count++;
                    }
                }

                /* Add tool call */
                if (result.count >= result.capacity) {
                    size_t new_cap = result.capacity * 2;
                    agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                    if (!new_arr) return result;
                    memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                    result.contents = new_arr;
                    result.capacity = new_cap;
                }
                result.contents[result.count].type = AGENT_CONTENT_TOOL_CALL;
                result.contents[result.count].data.tool_call.name = bare_tc->name;
                result.contents[result.count].data.tool_call.arguments = bare_tc->arguments;
                result.count++;

                /* Continue with text after */
                if (after.length > 0) {
                    agent_string_view_t trimmed = agent_sv_trim(after);
                    if (trimmed.length > 0) {
                        if (result.count >= result.capacity) {
                            size_t new_cap = result.capacity * 2;
                            agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                            if (!new_arr) return result;
                            memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                            result.contents = new_arr;
                            result.capacity = new_cap;
                        }
                        result.contents[result.count].type = AGENT_CONTENT_TEXT;
                        result.contents[result.count].data.text = trimmed;
                        result.count++;
                    }
                }
            } else {
                /* Just text */
                agent_string_view_t text = agent_sv_from_parts(pos, remaining);
                text = agent_sv_trim(text);
                if (text.length > 0) {
                    if (result.count >= result.capacity) {
                        size_t new_cap = result.capacity * 2;
                        agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                        if (!new_arr) return result;
                        memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                        result.contents = new_arr;
                        result.capacity = new_cap;
                    }
                    result.contents[result.count].type = AGENT_CONTENT_TEXT;
                    result.contents[result.count].data.text = agent_context_string_view_n(ctx, text.data, text.length);
                    result.count++;
                }
            }
            break;
        }

        /* Add text before tool call */
        if (tool_open > pos) {
            agent_string_view_t text = agent_sv_from_parts(pos, (size_t)(tool_open - pos));
            text = agent_sv_trim(text);
            if (text.length > 0) {
                if (result.count >= result.capacity) {
                    size_t new_cap = result.capacity * 2;
                    agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                    if (!new_arr) return result;
                    memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                    result.contents = new_arr;
                    result.capacity = new_cap;
                }
                result.contents[result.count].type = AGENT_CONTENT_TEXT;
                result.contents[result.count].data.text = agent_context_string_view_n(ctx, text.data, text.length);
                result.count++;
            }
        }

        /* Find closing tag */
        const char* content_start = tool_open + TAG_TOOL_CALL_OPEN_LEN;
        size_t content_remaining = remaining - (size_t)(content_start - pos);
        const char* tool_close = find_substr(content_start, content_remaining, TAG_TOOL_CALL_CLOSE, TAG_TOOL_CALL_CLOSE_LEN);

        if (!tool_close) {
            /* Incomplete tag - treat rest as text */
            break;
        }

        /* Parse tool call JSON */
        size_t json_len = (size_t)(tool_close - content_start);
        agent_parsed_tool_call_t* tc = agent_parser_parse_tool_call_json(ctx, content_start, json_len);

        if (tc) {
            if (result.count >= result.capacity) {
                size_t new_cap = result.capacity * 2;
                agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                if (!new_arr) return result;
                memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                result.contents = new_arr;
                result.capacity = new_cap;
            }
            result.contents[result.count].type = AGENT_CONTENT_TOOL_CALL;
            result.contents[result.count].data.tool_call.name = tc->name;
            result.contents[result.count].data.tool_call.arguments = tc->arguments;
            result.count++;
        }

        /* Move past this tool call */
        pos = tool_close + TAG_TOOL_CALL_CLOSE_LEN;
        remaining = length - (size_t)(pos - response);
    }

    /* Extract thinking content from any text items */
    for (size_t i = 0; i < result.count; i++) {
        if (result.contents[i].type == AGENT_CONTENT_TEXT) {
            agent_string_view_t thinking, content;
            agent_parser_extract_thinking(ctx,
                result.contents[i].data.text.data,
                result.contents[i].data.text.length,
                &thinking, &content);

            if (thinking.length > 0) {
                /* Insert thinking content before this text */
                if (result.count >= result.capacity) {
                    size_t new_cap = result.capacity * 2;
                    agent_parsed_content_t* new_arr = agent_context_calloc(ctx, new_cap, sizeof(agent_parsed_content_t));
                    if (!new_arr) return result;
                    memcpy(new_arr, result.contents, result.count * sizeof(agent_parsed_content_t));
                    result.contents = new_arr;
                    result.capacity = new_cap;
                }

                /* Shift items after i */
                memmove(&result.contents[i + 2], &result.contents[i + 1],
                        (result.count - i - 1) * sizeof(agent_parsed_content_t));

                /* Insert thinking */
                result.contents[i].type = AGENT_CONTENT_THINKING;
                result.contents[i].data.thinking = thinking;

                /* Update text */
                result.contents[i + 1].type = AGENT_CONTENT_TEXT;
                result.contents[i + 1].data.text = content;

                result.count++;
                i++;  /* Skip the newly inserted item */
            }
        }
    }

    return result;
}

agent_parse_result_t agent_parser_parse_cstr(agent_context_t* ctx, const char* response) {
    if (!response) {
        agent_parse_result_t result = {NULL, 0, 0};
        return result;
    }
    return agent_parser_parse(ctx, response, strlen(response));
}

/* Streaming parser implementation */

agent_error_t agent_streaming_parser_init(agent_streaming_parser_t* parser,
                                          agent_context_t* ctx) {
    if (!parser || !ctx) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    memset(parser, 0, sizeof(agent_streaming_parser_t));
    parser->ctx = ctx;
    parser->state = PARSER_STATE_TEXT;

    agent_error_t err;
    err = agent_string_init(&parser->buffer, 256);
    if (err != AGENT_OK) return err;

    err = agent_string_init(&parser->tag_buffer, 32);
    if (err != AGENT_OK) {
        agent_string_free(&parser->buffer);
        return err;
    }

    err = agent_string_init(&parser->content_buffer, 256);
    if (err != AGENT_OK) {
        agent_string_free(&parser->buffer);
        agent_string_free(&parser->tag_buffer);
        return err;
    }

    return AGENT_OK;
}

void agent_streaming_parser_free(agent_streaming_parser_t* parser) {
    if (!parser) return;

    agent_string_free(&parser->buffer);
    agent_string_free(&parser->tag_buffer);
    agent_string_free(&parser->content_buffer);
}

void agent_streaming_parser_reset(agent_streaming_parser_t* parser) {
    if (!parser) return;

    parser->state = PARSER_STATE_TEXT;
    agent_string_clear(&parser->buffer);
    agent_string_clear(&parser->tag_buffer);
    agent_string_clear(&parser->content_buffer);
    parser->in_tool_call = false;
    parser->in_think = false;
    parser->brace_depth = 0;
}

agent_error_t agent_streaming_parser_feed(agent_streaming_parser_t* parser,
                                          const char* token, size_t length) {
    if (!parser || !token) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    for (size_t i = 0; i < length; i++) {
        char c = token[i];

        switch (parser->state) {
            case PARSER_STATE_TEXT:
                if (c == '<') {
                    parser->state = PARSER_STATE_TAG_OPEN;
                    agent_string_clear(&parser->tag_buffer);
                    agent_string_append_char(&parser->tag_buffer, c);
                } else {
                    agent_string_append_char(&parser->buffer, c);
                }
                break;

            case PARSER_STATE_TAG_OPEN:
                agent_string_append_char(&parser->tag_buffer, c);

                if (c == '>') {
                    /* Check what tag we have */
                    const char* tag = agent_string_cstr(&parser->tag_buffer);

                    if (strcmp(tag, TAG_TOOL_CALL_OPEN) == 0) {
                        /* Emit buffered text */
                        if (parser->buffer.length > 0 && parser->on_text) {
                            parser->on_text(parser->buffer.data, parser->buffer.length, parser->user_data);
                        }
                        agent_string_clear(&parser->buffer);
                        parser->state = PARSER_STATE_TOOL_CALL;
                        parser->in_tool_call = true;
                        agent_string_clear(&parser->content_buffer);
                    } else if (strcmp(tag, TAG_THINK_OPEN) == 0 ||
                               strcmp(tag, TAG_THINKING_OPEN) == 0) {
                        /* Emit buffered text */
                        if (parser->buffer.length > 0 && parser->on_text) {
                            parser->on_text(parser->buffer.data, parser->buffer.length, parser->user_data);
                        }
                        agent_string_clear(&parser->buffer);
                        parser->state = PARSER_STATE_THINK;
                        parser->in_think = true;
                        agent_string_clear(&parser->content_buffer);
                    } else {
                        /* Not a recognized tag - add to buffer */
                        agent_string_append(&parser->buffer, tag);
                        parser->state = PARSER_STATE_TEXT;
                    }
                    agent_string_clear(&parser->tag_buffer);
                } else if (parser->tag_buffer.length > 15) {
                    /* Tag too long - not a valid tag */
                    agent_string_append_sv(&parser->buffer, agent_string_view(&parser->tag_buffer));
                    agent_string_clear(&parser->tag_buffer);
                    parser->state = PARSER_STATE_TEXT;
                }
                break;

            case PARSER_STATE_TOOL_CALL:
                agent_string_append_char(&parser->content_buffer, c);

                /* Check for closing tag */
                if (parser->content_buffer.length >= TAG_TOOL_CALL_CLOSE_LEN) {
                    const char* end = parser->content_buffer.data + parser->content_buffer.length - TAG_TOOL_CALL_CLOSE_LEN;
                    if (memcmp(end, TAG_TOOL_CALL_CLOSE, TAG_TOOL_CALL_CLOSE_LEN) == 0) {
                        /* Found closing tag - parse tool call */
                        size_t json_len = parser->content_buffer.length - TAG_TOOL_CALL_CLOSE_LEN;
                        agent_parsed_tool_call_t* tc = agent_parser_parse_tool_call_json(
                            parser->ctx, parser->content_buffer.data, json_len);

                        if (tc && parser->on_tool_call) {
                            parser->on_tool_call(tc->name.data, tc->arguments, parser->user_data);
                        }

                        agent_string_clear(&parser->content_buffer);
                        parser->state = PARSER_STATE_TEXT;
                        parser->in_tool_call = false;
                    }
                }
                break;

            case PARSER_STATE_THINK:
                agent_string_append_char(&parser->content_buffer, c);

                /* Check for closing tags */
                if (parser->content_buffer.length >= TAG_THINK_CLOSE_LEN) {
                    const char* end = parser->content_buffer.data + parser->content_buffer.length - TAG_THINK_CLOSE_LEN;
                    bool closed = false;

                    if (memcmp(end, TAG_THINK_CLOSE, TAG_THINK_CLOSE_LEN) == 0) {
                        size_t think_len = parser->content_buffer.length - TAG_THINK_CLOSE_LEN;
                        if (parser->on_thinking) {
                            parser->on_thinking(parser->content_buffer.data, think_len, parser->user_data);
                        }
                        closed = true;
                    } else if (parser->content_buffer.length >= TAG_THINKING_CLOSE_LEN) {
                        end = parser->content_buffer.data + parser->content_buffer.length - TAG_THINKING_CLOSE_LEN;
                        if (memcmp(end, TAG_THINKING_CLOSE, TAG_THINKING_CLOSE_LEN) == 0) {
                            size_t think_len = parser->content_buffer.length - TAG_THINKING_CLOSE_LEN;
                            if (parser->on_thinking) {
                                parser->on_thinking(parser->content_buffer.data, think_len, parser->user_data);
                            }
                            closed = true;
                        }
                    }

                    if (closed) {
                        agent_string_clear(&parser->content_buffer);
                        parser->state = PARSER_STATE_TEXT;
                        parser->in_think = false;
                    }
                }
                break;

            default:
                parser->state = PARSER_STATE_TEXT;
                break;
        }
    }

    /* If in TEXT state, emit buffered text incrementally */
    if (parser->state == PARSER_STATE_TEXT && parser->buffer.length > 0) {
        /* Keep some buffer in case we're mid-tag */
        size_t emit_len = parser->buffer.length;
        if (emit_len > 0 && parser->on_text) {
            parser->on_text(parser->buffer.data, emit_len, parser->user_data);
        }
        agent_string_clear(&parser->buffer);
    }

    return AGENT_OK;
}

agent_error_t agent_streaming_parser_flush(agent_streaming_parser_t* parser) {
    if (!parser) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    /* Emit any remaining buffered content */
    if (parser->buffer.length > 0 && parser->on_text) {
        parser->on_text(parser->buffer.data, parser->buffer.length, parser->user_data);
    }

    if (parser->tag_buffer.length > 0 && parser->on_text) {
        parser->on_text(parser->tag_buffer.data, parser->tag_buffer.length, parser->user_data);
    }

    agent_string_clear(&parser->buffer);
    agent_string_clear(&parser->tag_buffer);

    return AGENT_OK;
}

bool agent_streaming_parser_in_tool_call(const agent_streaming_parser_t* parser) {
    if (!parser) return false;
    return parser->in_tool_call;
}
