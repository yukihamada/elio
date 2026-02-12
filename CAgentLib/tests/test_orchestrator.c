/**
 * @file test_orchestrator.c
 * @brief Unit tests for agent orchestrator
 */

#include "agent_lib.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

#define TEST(name) static void test_##name(void)
#define RUN_TEST(name) do { printf("  " #name "..."); test_##name(); printf(" OK\n"); } while(0)

/* Mock callbacks */

static int generate_call_count = 0;
static int tool_call_count = 0;
static const char* mock_responses[10];
static int mock_response_index = 0;

static agent_llm_result_t mock_generate(
    const agent_message_t* messages,
    size_t message_count,
    const char* system_prompt,
    agent_token_callback_t token_callback,
    void* user_data
) {
    (void)messages;
    (void)message_count;
    (void)system_prompt;

    generate_call_count++;

    agent_llm_result_t result = {0};
    result.error = AGENT_OK;

    const char* response = mock_responses[mock_response_index++];
    if (!response) {
        response = "Default response";
    }

    /* Simulate streaming */
    if (token_callback) {
        token_callback(response, strlen(response), user_data);
    }

    result.text.data = response;
    result.text.length = strlen(response);

    return result;
}

static agent_tool_execute_result_t mock_execute_tool(
    const char* tool_name,
    const agent_json_value_t* arguments,
    void* user_data
) {
    (void)arguments;
    (void)user_data;

    tool_call_count++;

    agent_tool_execute_result_t result = {0};
    result.error = AGENT_OK;
    result.is_error = false;

    if (strcmp(tool_name, "test_tool") == 0) {
        result.content.data = "Tool result: success";
        result.content.length = 20;
    } else if (strcmp(tool_name, "error_tool") == 0) {
        result.content.data = "Error: something went wrong";
        result.content.length = 27;
        result.is_error = true;
    } else {
        result.content.data = "Unknown tool";
        result.content.length = 12;
    }

    return result;
}

static const char* mock_get_tools_schema(void* user_data) {
    (void)user_data;
    return "[{\"type\":\"function\",\"function\":{\"name\":\"test_tool\",\"parameters\":{}}}]";
}

static void reset_mocks(void) {
    generate_call_count = 0;
    tool_call_count = 0;
    mock_response_index = 0;
    for (int i = 0; i < 10; i++) {
        mock_responses[i] = NULL;
    }
}

/* Tests */

TEST(init_free) {
    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;

    agent_error_t err = agent_init(&state, &config);
    assert(err == AGENT_OK);

    assert(!agent_is_processing(&state));
    assert(agent_current_step(&state) == AGENT_STEP_NONE);

    agent_free(&state);
}

TEST(init_with_options) {
    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    config.max_iterations = 5;
    config.use_japanese = true;
    config.custom_system_prompt = "Be helpful.";

    agent_error_t err = agent_init(&state, &config);
    assert(err == AGENT_OK);

    agent_free(&state);
}

TEST(init_requires_callbacks) {
    agent_state_t state;
    agent_config_t config = {0};

    /* No callbacks - should fail */
    agent_error_t err = agent_init(&state, &config);
    assert(err == AGENT_ERROR_INVALID_ARGUMENT);

    /* Only generate - should fail */
    config.generate = mock_generate;
    err = agent_init(&state, &config);
    assert(err == AGENT_ERROR_INVALID_ARGUMENT);

    /* Both callbacks - should succeed */
    config.execute_tool = mock_execute_tool;
    err = agent_init(&state, &config);
    assert(err == AGENT_OK);

    agent_free(&state);
}

TEST(add_messages) {
    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    agent_init(&state, &config);

    /* Add user message */
    agent_error_t err = agent_add_user_message(&state, "Hello");
    assert(err == AGENT_OK);

    /* Add system message */
    err = agent_add_system_message(&state, "Be helpful");
    assert(err == AGENT_OK);

    /* Check messages */
    const agent_message_t* messages;
    size_t count;
    agent_get_messages(&state, &messages, &count);
    assert(count == 2);
    assert(messages[0].role == AGENT_ROLE_USER);
    assert(messages[1].role == AGENT_ROLE_SYSTEM);

    agent_free(&state);
}

TEST(simple_response) {
    reset_mocks();
    mock_responses[0] = "Hello! How can I help you?";

    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    agent_init(&state, &config);

    agent_add_user_message(&state, "Hi");

    agent_run_result_t result = agent_run(&state);

    assert(result.error == AGENT_OK);
    assert(result.response.length > 0);
    assert(strstr(result.response.data, "Hello") != NULL);
    assert(generate_call_count == 1);
    assert(tool_call_count == 0);
    assert(result.iterations == 1);

    agent_free(&state);
}

TEST(tool_call_response) {
    reset_mocks();
    mock_responses[0] = "<tool_call>{\"name\": \"test_tool\", \"arguments\": {}}</tool_call>";
    mock_responses[1] = "Done! The tool worked.";

    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    config.get_tools_schema = mock_get_tools_schema;
    agent_init(&state, &config);

    agent_add_user_message(&state, "Use a tool");

    agent_run_result_t result = agent_run(&state);

    assert(result.error == AGENT_OK);
    assert(generate_call_count == 2);  /* Initial + after tool */
    assert(tool_call_count == 1);
    assert(result.tool_calls_count == 1);
    assert(result.iterations == 2);

    agent_free(&state);
}

TEST(multiple_tool_calls) {
    reset_mocks();
    mock_responses[0] = "<tool_call>{\"name\": \"test_tool\", \"arguments\": {}}</tool_call>";
    mock_responses[1] = "<tool_call>{\"name\": \"test_tool\", \"arguments\": {}}</tool_call>";
    mock_responses[2] = "All done!";

    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    agent_init(&state, &config);

    agent_add_user_message(&state, "Use tools");

    agent_run_result_t result = agent_run(&state);

    assert(result.error == AGENT_OK);
    assert(generate_call_count == 3);
    assert(tool_call_count == 2);
    assert(result.tool_calls_count == 2);

    agent_free(&state);
}

TEST(max_iterations) {
    reset_mocks();
    /* Always return tool call - will hit max iterations */
    for (int i = 0; i < 10; i++) {
        mock_responses[i] = "<tool_call>{\"name\": \"test_tool\", \"arguments\": {}}</tool_call>";
    }

    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    config.max_iterations = 3;
    agent_init(&state, &config);

    agent_add_user_message(&state, "Loop forever");

    agent_run_result_t result = agent_run(&state);

    assert(result.error == AGENT_ERROR_MAX_ITERATIONS);
    assert(result.iterations == 3);
    assert(tool_call_count == 3);

    agent_free(&state);
}

TEST(reset) {
    reset_mocks();
    mock_responses[0] = "Response 1";

    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    agent_init(&state, &config);

    agent_add_user_message(&state, "First");
    agent_run(&state);

    /* Reset and run again */
    agent_reset(&state);
    mock_response_index = 0;
    mock_responses[0] = "Response 2";

    const agent_message_t* messages;
    size_t count;
    agent_get_messages(&state, &messages, &count);
    assert(count == 0);  /* Messages cleared */

    agent_add_user_message(&state, "Second");
    agent_run_result_t result = agent_run(&state);

    assert(result.error == AGENT_OK);
    assert(strstr(result.response.data, "Response 2") != NULL);

    agent_free(&state);
}

TEST(stop) {
    reset_mocks();
    mock_responses[0] = "Starting...";

    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    agent_init(&state, &config);

    agent_add_user_message(&state, "Test");

    /* Stop before running - should cancel immediately */
    agent_stop(&state);

    /* Note: In a real async scenario, we'd test stopping mid-execution */

    agent_free(&state);
}

TEST(build_system_prompt) {
    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    config.get_tools_schema = mock_get_tools_schema;
    config.use_japanese = false;
    config.custom_system_prompt = "Custom instruction here.";
    agent_init(&state, &config);

    char* prompt = agent_build_system_prompt(&state);

    assert(prompt != NULL);
    assert(strstr(prompt, "helpful") != NULL);  /* Default prompt text */
    assert(strstr(prompt, "tool_call") != NULL);  /* Tool call format */
    assert(strstr(prompt, "Custom instruction") != NULL);  /* Custom prompt */

    agent_free(&state);
}

TEST(build_system_prompt_japanese) {
    agent_state_t state;
    agent_config_t config = {0};
    config.generate = mock_generate;
    config.execute_tool = mock_execute_tool;
    config.use_japanese = true;
    agent_init(&state, &config);

    char* prompt = agent_build_system_prompt(&state);

    assert(prompt != NULL);
    /* Should contain Japanese text */
    assert(strstr(prompt, "アシスタント") != NULL ||
           strstr(prompt, "ツール") != NULL);

    agent_free(&state);
}

TEST(truncate_text) {
    agent_context_t* ctx = agent_context_create(0);

    const char* long_text = "This is a very long text that should be truncated";

    char* truncated = agent_truncate_text(ctx, long_text, 20);
    assert(truncated != NULL);
    assert(strlen(truncated) <= 20);
    assert(strstr(truncated, "...") != NULL);

    /* Short text should not be truncated */
    char* short_result = agent_truncate_text(ctx, "Short", 100);
    assert(strcmp(short_result, "Short") == 0);

    agent_context_destroy(ctx);
}

TEST(format_tool_call) {
    agent_context_t* ctx = agent_context_create(0);

    agent_tool_call_t tc = {0};
    tc.name.data = "my_tool";
    tc.name.length = 7;
    tc.arguments = agent_json_object(ctx, 2);
    agent_json_object_set(ctx, tc.arguments, "param1", agent_json_string(ctx, "value1"));

    char* formatted = agent_format_tool_call(ctx, &tc, false);
    assert(formatted != NULL);
    assert(strstr(formatted, "my_tool") != NULL);
    assert(strstr(formatted, "param1") != NULL);

    char* formatted_ja = agent_format_tool_call(ctx, &tc, true);
    assert(formatted_ja != NULL);
    assert(strstr(formatted_ja, "ツール") != NULL);

    agent_context_destroy(ctx);
}

int main(void) {
    printf("Running orchestrator initialization tests...\n");

    RUN_TEST(init_free);
    RUN_TEST(init_with_options);
    RUN_TEST(init_requires_callbacks);

    printf("\nRunning message tests...\n");

    RUN_TEST(add_messages);

    printf("\nRunning execution tests...\n");

    RUN_TEST(simple_response);
    RUN_TEST(tool_call_response);
    RUN_TEST(multiple_tool_calls);
    RUN_TEST(max_iterations);

    printf("\nRunning state management tests...\n");

    RUN_TEST(reset);
    RUN_TEST(stop);

    printf("\nRunning utility tests...\n");

    RUN_TEST(build_system_prompt);
    RUN_TEST(build_system_prompt_japanese);
    RUN_TEST(truncate_text);
    RUN_TEST(format_tool_call);

    printf("\nAll orchestrator tests passed!\n");
    return 0;
}
