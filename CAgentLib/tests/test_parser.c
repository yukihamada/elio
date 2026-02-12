/**
 * @file test_parser.c
 * @brief Unit tests for response parser
 */

#include "agent_lib.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

#define TEST(name) static void test_##name(void)
#define RUN_TEST(name) do { printf("  " #name "..."); test_##name(); printf(" OK\n"); } while(0)

static agent_context_t* ctx;

/* Tool call detection tests */

TEST(has_tool_call) {
    assert(agent_parser_has_tool_call("<tool_call>{}</tool_call>", 25));
    assert(agent_parser_has_tool_call("text <tool_call>{}</tool_call> more", 35));
    assert(!agent_parser_has_tool_call("no tool call here", 17));
    assert(!agent_parser_has_tool_call("<tool_call>incomplete", 21));
}

TEST(has_incomplete_tool_call) {
    assert(agent_parser_has_incomplete_tool_call("<tool_call>no close", 19));
    assert(!agent_parser_has_incomplete_tool_call("<tool_call>{}</tool_call>", 25));
    assert(!agent_parser_has_incomplete_tool_call("no tool call", 12));
}

/* Tag extraction tests */

TEST(text_before_tool_call) {
    const char* response = "Hello world <tool_call>{}</tool_call>";
    agent_string_view_t text = agent_parser_text_before_tool_call(ctx, response, strlen(response));

    assert(text.length == 11);
    assert(memcmp(text.data, "Hello world", 11) == 0);

    /* No tool call */
    const char* response2 = "Just plain text";
    text = agent_parser_text_before_tool_call(ctx, response2, strlen(response2));
    assert(text.length == 15);
}

TEST(text_after_tool_call) {
    const char* response = "<tool_call>{}</tool_call> After text";
    agent_string_view_t text = agent_parser_text_after_tool_call(ctx, response, strlen(response));

    assert(text.length == 10);
    assert(memcmp(text.data, "After text", 10) == 0);

    /* No tool call */
    const char* response2 = "No tool call here";
    text = agent_parser_text_after_tool_call(ctx, response2, strlen(response2));
    assert(text.length == 0);
}

/* Thinking extraction tests */

TEST(extract_thinking_simple) {
    const char* response = "<think>My reasoning here</think>The actual response";
    agent_string_view_t thinking, content;

    agent_parser_extract_thinking(ctx, response, strlen(response), &thinking, &content);

    assert(thinking.length > 0);
    assert(memcmp(thinking.data, "My reasoning here", thinking.length) == 0);
    assert(memcmp(content.data, "The actual response", content.length) == 0);
}

TEST(extract_thinking_tag) {
    const char* response = "<thinking>Longer form</thinking>Response";
    agent_string_view_t thinking, content;

    agent_parser_extract_thinking(ctx, response, strlen(response), &thinking, &content);

    assert(thinking.length > 0);
    assert(strstr(thinking.data, "Longer form") != NULL);
}

TEST(extract_thinking_only_close) {
    /* When <think> was in the prompt, response starts with content and ends with </think> */
    const char* response = "Thinking continuation</think>Visible response";
    agent_string_view_t thinking, content;

    agent_parser_extract_thinking(ctx, response, strlen(response), &thinking, &content);

    assert(thinking.length > 0);
    assert(content.length > 0);
}

TEST(extract_thinking_none) {
    const char* response = "Just a normal response without thinking";
    agent_string_view_t thinking, content;

    agent_parser_extract_thinking(ctx, response, strlen(response), &thinking, &content);

    assert(thinking.data == NULL || thinking.length == 0);
    assert(content.length == strlen(response));
}

/* Tool call JSON parsing tests */

TEST(parse_tool_call_json) {
    const char* json = "{\"name\": \"test_tool\", \"arguments\": {\"arg1\": \"value1\", \"arg2\": 42}}";
    agent_parsed_tool_call_t* tc = agent_parser_parse_tool_call_json(ctx, json, strlen(json));

    assert(tc != NULL);
    assert(tc->name.length > 0);
    assert(memcmp(tc->name.data, "test_tool", 9) == 0);
    assert(tc->arguments != NULL);
    assert(tc->arguments->type == AGENT_JSON_OBJECT);

    agent_json_value_t* arg1 = agent_json_object_get(tc->arguments, "arg1");
    assert(arg1 != NULL);
    assert(arg1->type == AGENT_JSON_STRING);

    agent_json_value_t* arg2 = agent_json_object_get(tc->arguments, "arg2");
    assert(arg2 != NULL);
    assert(arg2->type == AGENT_JSON_INT);
    assert(arg2->data.int_value == 42);
}

TEST(parse_tool_call_json_minimal) {
    const char* json = "{\"name\": \"simple\", \"arguments\": {}}";
    agent_parsed_tool_call_t* tc = agent_parser_parse_tool_call_json(ctx, json, strlen(json));

    assert(tc != NULL);
    assert(memcmp(tc->name.data, "simple", 6) == 0);
    assert(tc->arguments->type == AGENT_JSON_OBJECT);
    assert(tc->arguments->data.object_value.count == 0);
}

TEST(parse_tool_call_json_invalid) {
    /* Missing name */
    const char* json1 = "{\"arguments\": {}}";
    assert(agent_parser_parse_tool_call_json(ctx, json1, strlen(json1)) == NULL);

    /* Invalid JSON */
    const char* json2 = "{invalid}";
    assert(agent_parser_parse_tool_call_json(ctx, json2, strlen(json2)) == NULL);

    /* Not an object */
    const char* json3 = "[]";
    assert(agent_parser_parse_tool_call_json(ctx, json3, strlen(json3)) == NULL);
}

/* Bare JSON detection tests */

TEST(find_bare_json) {
    const char* response = "Some text {\"name\": \"tool\", \"arguments\": {\"x\": 1}} more text";
    agent_string_view_t before, after;

    agent_parsed_tool_call_t* tc = agent_parser_find_bare_json(ctx, response, strlen(response), &before, &after);

    assert(tc != NULL);
    assert(memcmp(tc->name.data, "tool", 4) == 0);
    assert(before.length > 0);
    assert(strstr(before.data, "Some text") != NULL);
    assert(after.length > 0);
    assert(strstr(after.data, "more text") != NULL);
}

TEST(find_bare_json_not_found) {
    const char* response = "No tool call here";
    agent_parsed_tool_call_t* tc = agent_parser_find_bare_json(ctx, response, strlen(response), NULL, NULL);
    assert(tc == NULL);

    /* Has name but no arguments */
    const char* response2 = "{\"name\": \"test\"}";
    tc = agent_parser_find_bare_json(ctx, response2, strlen(response2), NULL, NULL);
    assert(tc == NULL);
}

/* Full parse tests */

TEST(parse_simple_text) {
    const char* response = "Just a simple response with no tool calls";
    agent_parse_result_t result = agent_parser_parse(ctx, response, strlen(response));

    assert(result.count == 1);
    assert(result.contents[0].type == AGENT_CONTENT_TEXT);
    assert(result.contents[0].data.text.length > 0);
}

TEST(parse_tool_call_tag) {
    const char* response = "Before <tool_call>{\"name\": \"test\", \"arguments\": {}}</tool_call> After";
    agent_parse_result_t result = agent_parser_parse(ctx, response, strlen(response));

    /* Should have: text, tool_call, text */
    assert(result.count >= 2);

    bool found_text = false;
    bool found_tool = false;

    for (size_t i = 0; i < result.count; i++) {
        if (result.contents[i].type == AGENT_CONTENT_TEXT) {
            found_text = true;
        } else if (result.contents[i].type == AGENT_CONTENT_TOOL_CALL) {
            found_tool = true;
            assert(memcmp(result.contents[i].data.tool_call.name.data, "test", 4) == 0);
        }
    }

    assert(found_text);
    assert(found_tool);
}

TEST(parse_multiple_tool_calls) {
    const char* response =
        "<tool_call>{\"name\": \"first\", \"arguments\": {}}</tool_call>"
        "<tool_call>{\"name\": \"second\", \"arguments\": {}}</tool_call>";

    agent_parse_result_t result = agent_parser_parse(ctx, response, strlen(response));

    int tool_count = 0;
    for (size_t i = 0; i < result.count; i++) {
        if (result.contents[i].type == AGENT_CONTENT_TOOL_CALL) {
            tool_count++;
        }
    }

    assert(tool_count == 2);
}

TEST(parse_with_thinking) {
    const char* response = "<think>Let me think about this</think>Here is my response";
    agent_parse_result_t result = agent_parser_parse(ctx, response, strlen(response));

    bool found_thinking = false;
    bool found_text = false;

    for (size_t i = 0; i < result.count; i++) {
        if (result.contents[i].type == AGENT_CONTENT_THINKING) {
            found_thinking = true;
        } else if (result.contents[i].type == AGENT_CONTENT_TEXT) {
            found_text = true;
        }
    }

    assert(found_thinking);
    assert(found_text);
}

/* Streaming parser tests */

/* Helper for streaming_basic test */
static char g_received_text[256];
static size_t g_received_len;

static void streaming_text_callback(const char* text, size_t len, void* user_data) {
    (void)user_data;
    memcpy(g_received_text + g_received_len, text, len);
    g_received_len += len;
}

TEST(streaming_basic) {
    agent_streaming_parser_t parser;
    agent_streaming_parser_init(&parser, ctx);

    memset(g_received_text, 0, sizeof(g_received_text));
    g_received_len = 0;

    parser.user_data = NULL;
    parser.on_text = streaming_text_callback;

    /* Feed tokens one by one */
    agent_streaming_parser_feed(&parser, "Hello", 5);
    agent_streaming_parser_feed(&parser, " ", 1);
    agent_streaming_parser_feed(&parser, "World", 5);
    agent_streaming_parser_flush(&parser);

    /* Check received text */
    assert(g_received_len == 11);
    assert(strcmp(g_received_text, "Hello World") == 0);

    agent_streaming_parser_free(&parser);
}

TEST(streaming_tool_call_detection) {
    agent_streaming_parser_t parser;
    agent_streaming_parser_init(&parser, ctx);

    /* Feed partial tool call */
    agent_streaming_parser_feed(&parser, "Text <tool", 10);
    assert(!agent_streaming_parser_in_tool_call(&parser));

    agent_streaming_parser_feed(&parser, "_call>{\"name\":", 14);
    assert(agent_streaming_parser_in_tool_call(&parser));

    agent_streaming_parser_free(&parser);
}

int main(void) {
    ctx = agent_context_create(0);
    assert(ctx != NULL);

    printf("Running tool call detection tests...\n");

    RUN_TEST(has_tool_call);
    RUN_TEST(has_incomplete_tool_call);

    agent_context_reset(ctx);

    printf("\nRunning tag extraction tests...\n");

    RUN_TEST(text_before_tool_call);
    RUN_TEST(text_after_tool_call);

    agent_context_reset(ctx);

    printf("\nRunning thinking extraction tests...\n");

    RUN_TEST(extract_thinking_simple);
    RUN_TEST(extract_thinking_tag);
    RUN_TEST(extract_thinking_only_close);
    RUN_TEST(extract_thinking_none);

    agent_context_reset(ctx);

    printf("\nRunning tool call JSON parsing tests...\n");

    RUN_TEST(parse_tool_call_json);
    RUN_TEST(parse_tool_call_json_minimal);
    RUN_TEST(parse_tool_call_json_invalid);

    agent_context_reset(ctx);

    printf("\nRunning bare JSON detection tests...\n");

    RUN_TEST(find_bare_json);
    RUN_TEST(find_bare_json_not_found);

    agent_context_reset(ctx);

    printf("\nRunning full parse tests...\n");

    RUN_TEST(parse_simple_text);
    RUN_TEST(parse_tool_call_tag);
    RUN_TEST(parse_multiple_tool_calls);
    RUN_TEST(parse_with_thinking);

    agent_context_reset(ctx);

    printf("\nRunning streaming parser tests...\n");

    RUN_TEST(streaming_basic);
    RUN_TEST(streaming_tool_call_detection);

    agent_context_destroy(ctx);

    printf("\nAll parser tests passed!\n");
    return 0;
}
