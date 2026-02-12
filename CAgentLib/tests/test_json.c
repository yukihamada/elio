/**
 * @file test_json.c
 * @brief Unit tests for JSON parser and serializer
 */

#include "agent_lib.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <math.h>

#define TEST(name) static void test_##name(void)
#define RUN_TEST(name) do { printf("  " #name "..."); test_##name(); printf(" OK\n"); } while(0)

static agent_context_t* ctx;

/* Parsing tests */

TEST(parse_null) {
    agent_json_parse_result_t result = agent_json_parse_cstr(ctx, "null");
    assert(result.error == AGENT_OK);
    assert(result.value != NULL);
    assert(result.value->type == AGENT_JSON_NULL);
}

TEST(parse_bool) {
    agent_json_parse_result_t result;

    result = agent_json_parse_cstr(ctx, "true");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_BOOL);
    assert(result.value->data.bool_value == true);

    result = agent_json_parse_cstr(ctx, "false");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_BOOL);
    assert(result.value->data.bool_value == false);
}

TEST(parse_int) {
    agent_json_parse_result_t result;

    result = agent_json_parse_cstr(ctx, "42");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_INT);
    assert(result.value->data.int_value == 42);

    result = agent_json_parse_cstr(ctx, "-123");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_INT);
    assert(result.value->data.int_value == -123);

    result = agent_json_parse_cstr(ctx, "0");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_INT);
    assert(result.value->data.int_value == 0);
}

TEST(parse_double) {
    agent_json_parse_result_t result;

    result = agent_json_parse_cstr(ctx, "3.14");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_DOUBLE);
    assert(fabs(result.value->data.double_value - 3.14) < 0.0001);

    result = agent_json_parse_cstr(ctx, "-2.5e10");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_DOUBLE);
    assert(fabs(result.value->data.double_value - (-2.5e10)) < 1e5);

    result = agent_json_parse_cstr(ctx, "1.0E-5");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_DOUBLE);
}

TEST(parse_string) {
    agent_json_parse_result_t result;

    result = agent_json_parse_cstr(ctx, "\"hello\"");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_STRING);
    assert(result.value->data.string_value.length == 5);
    assert(memcmp(result.value->data.string_value.data, "hello", 5) == 0);

    /* Empty string */
    result = agent_json_parse_cstr(ctx, "\"\"");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_STRING);
    assert(result.value->data.string_value.length == 0);
}

TEST(parse_string_escapes) {
    agent_json_parse_result_t result;

    result = agent_json_parse_cstr(ctx, "\"hello\\nworld\"");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_STRING);
    assert(strchr(result.value->data.string_value.data, '\n') != NULL);

    result = agent_json_parse_cstr(ctx, "\"quote: \\\"test\\\"\"");
    assert(result.error == AGENT_OK);
    assert(strchr(result.value->data.string_value.data, '"') != NULL);

    /* Unicode escape */
    result = agent_json_parse_cstr(ctx, "\"\\u0041\"");  /* 'A' */
    assert(result.error == AGENT_OK);
    assert(result.value->data.string_value.data[0] == 'A');
}

TEST(parse_array) {
    agent_json_parse_result_t result;

    /* Empty array */
    result = agent_json_parse_cstr(ctx, "[]");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_ARRAY);
    assert(result.value->data.array_value.count == 0);

    /* Array with elements */
    result = agent_json_parse_cstr(ctx, "[1, 2, 3]");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_ARRAY);
    assert(result.value->data.array_value.count == 3);
    assert(result.value->data.array_value.items[0]->data.int_value == 1);
    assert(result.value->data.array_value.items[1]->data.int_value == 2);
    assert(result.value->data.array_value.items[2]->data.int_value == 3);

    /* Mixed array */
    result = agent_json_parse_cstr(ctx, "[1, \"hello\", true, null]");
    assert(result.error == AGENT_OK);
    assert(result.value->data.array_value.count == 4);
    assert(result.value->data.array_value.items[0]->type == AGENT_JSON_INT);
    assert(result.value->data.array_value.items[1]->type == AGENT_JSON_STRING);
    assert(result.value->data.array_value.items[2]->type == AGENT_JSON_BOOL);
    assert(result.value->data.array_value.items[3]->type == AGENT_JSON_NULL);
}

TEST(parse_object) {
    agent_json_parse_result_t result;

    /* Empty object */
    result = agent_json_parse_cstr(ctx, "{}");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_OBJECT);
    assert(result.value->data.object_value.count == 0);

    /* Object with fields */
    result = agent_json_parse_cstr(ctx, "{\"name\": \"test\", \"value\": 42}");
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_OBJECT);
    assert(result.value->data.object_value.count == 2);

    agent_json_value_t* name = agent_json_object_get(result.value, "name");
    assert(name != NULL);
    assert(name->type == AGENT_JSON_STRING);

    agent_json_value_t* value = agent_json_object_get(result.value, "value");
    assert(value != NULL);
    assert(value->type == AGENT_JSON_INT);
    assert(value->data.int_value == 42);
}

TEST(parse_nested) {
    const char* json = "{\"items\": [{\"id\": 1}, {\"id\": 2}], \"meta\": {\"total\": 2}}";
    agent_json_parse_result_t result = agent_json_parse_cstr(ctx, json);

    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_OBJECT);

    agent_json_value_t* items = agent_json_object_get(result.value, "items");
    assert(items != NULL);
    assert(items->type == AGENT_JSON_ARRAY);
    assert(items->data.array_value.count == 2);

    agent_json_value_t* first = items->data.array_value.items[0];
    assert(first->type == AGENT_JSON_OBJECT);
    agent_json_value_t* id = agent_json_object_get(first, "id");
    assert(id->data.int_value == 1);

    agent_json_value_t* meta = agent_json_object_get(result.value, "meta");
    assert(meta != NULL);
    agent_json_value_t* total = agent_json_object_get(meta, "total");
    assert(total->data.int_value == 2);
}

TEST(parse_whitespace) {
    const char* json = "  {\n  \"key\"  :  \"value\"  \n}  ";
    agent_json_parse_result_t result = agent_json_parse_cstr(ctx, json);
    assert(result.error == AGENT_OK);
    assert(result.value->type == AGENT_JSON_OBJECT);
}

TEST(parse_errors) {
    agent_json_parse_result_t result;

    result = agent_json_parse_cstr(ctx, "");
    assert(result.error == AGENT_ERROR_PARSE_ERROR);

    result = agent_json_parse_cstr(ctx, "{");
    assert(result.error == AGENT_ERROR_PARSE_ERROR);

    result = agent_json_parse_cstr(ctx, "[1, 2,]");
    assert(result.error == AGENT_ERROR_PARSE_ERROR);

    result = agent_json_parse_cstr(ctx, "{\"key\"}");
    assert(result.error == AGENT_ERROR_PARSE_ERROR);

    result = agent_json_parse_cstr(ctx, "invalid");
    assert(result.error == AGENT_ERROR_PARSE_ERROR);
}

/* Construction tests */

TEST(construct_values) {
    agent_json_value_t* null_val = agent_json_null(ctx);
    assert(null_val->type == AGENT_JSON_NULL);

    agent_json_value_t* bool_val = agent_json_bool(ctx, true);
    assert(bool_val->type == AGENT_JSON_BOOL);
    assert(bool_val->data.bool_value == true);

    agent_json_value_t* int_val = agent_json_int(ctx, 12345);
    assert(int_val->type == AGENT_JSON_INT);
    assert(int_val->data.int_value == 12345);

    agent_json_value_t* double_val = agent_json_double(ctx, 3.14159);
    assert(double_val->type == AGENT_JSON_DOUBLE);
    assert(fabs(double_val->data.double_value - 3.14159) < 0.00001);

    agent_json_value_t* string_val = agent_json_string(ctx, "test");
    assert(string_val->type == AGENT_JSON_STRING);
    assert(string_val->data.string_value.length == 4);
}

TEST(construct_array) {
    agent_json_value_t* arr = agent_json_array(ctx, 4);
    assert(arr->type == AGENT_JSON_ARRAY);
    assert(arr->data.array_value.count == 0);

    agent_json_array_append(ctx, arr, agent_json_int(ctx, 1));
    agent_json_array_append(ctx, arr, agent_json_int(ctx, 2));
    agent_json_array_append(ctx, arr, agent_json_int(ctx, 3));

    assert(arr->data.array_value.count == 3);
    assert(arr->data.array_value.items[0]->data.int_value == 1);
    assert(arr->data.array_value.items[2]->data.int_value == 3);
}

TEST(construct_object) {
    agent_json_value_t* obj = agent_json_object(ctx, 4);
    assert(obj->type == AGENT_JSON_OBJECT);
    assert(obj->data.object_value.count == 0);

    agent_json_object_set(ctx, obj, "name", agent_json_string(ctx, "test"));
    agent_json_object_set(ctx, obj, "value", agent_json_int(ctx, 42));

    assert(obj->data.object_value.count == 2);
    assert(agent_json_object_has(obj, "name"));
    assert(agent_json_object_has(obj, "value"));
    assert(!agent_json_object_has(obj, "missing"));

    agent_json_value_t* name = agent_json_object_get(obj, "name");
    assert(name->type == AGENT_JSON_STRING);

    /* Update existing key */
    agent_json_object_set(ctx, obj, "value", agent_json_int(ctx, 100));
    assert(obj->data.object_value.count == 2);  /* Same count */
    assert(agent_json_object_get(obj, "value")->data.int_value == 100);
}

/* Serialization tests */

TEST(serialize_primitives) {
    agent_string_t str;
    agent_string_init(&str, 64);

    agent_json_serialize(agent_json_null(ctx), &str, false);
    assert(strcmp(str.data, "null") == 0);
    agent_string_clear(&str);

    agent_json_serialize(agent_json_bool(ctx, true), &str, false);
    assert(strcmp(str.data, "true") == 0);
    agent_string_clear(&str);

    agent_json_serialize(agent_json_int(ctx, -42), &str, false);
    assert(strcmp(str.data, "-42") == 0);
    agent_string_clear(&str);

    agent_json_serialize(agent_json_string(ctx, "hello"), &str, false);
    assert(strcmp(str.data, "\"hello\"") == 0);

    agent_string_free(&str);
}

TEST(serialize_array) {
    agent_json_value_t* arr = agent_json_array(ctx, 4);
    agent_json_array_append(ctx, arr, agent_json_int(ctx, 1));
    agent_json_array_append(ctx, arr, agent_json_int(ctx, 2));
    agent_json_array_append(ctx, arr, agent_json_int(ctx, 3));

    agent_string_t str;
    agent_string_init(&str, 64);

    agent_json_serialize(arr, &str, false);
    assert(strcmp(str.data, "[1,2,3]") == 0);

    agent_string_free(&str);
}

TEST(serialize_object) {
    agent_json_value_t* obj = agent_json_object(ctx, 4);
    agent_json_object_set(ctx, obj, "a", agent_json_int(ctx, 1));
    agent_json_object_set(ctx, obj, "b", agent_json_string(ctx, "test"));

    agent_string_t str;
    agent_string_init(&str, 64);

    agent_json_serialize(obj, &str, false);
    /* Order is preserved */
    assert(strstr(str.data, "\"a\":1") != NULL);
    assert(strstr(str.data, "\"b\":\"test\"") != NULL);

    agent_string_free(&str);
}

TEST(serialize_escapes) {
    agent_json_value_t* str_val = agent_json_string(ctx, "line1\nline2\ttab");

    agent_string_t str;
    agent_string_init(&str, 64);

    agent_json_serialize(str_val, &str, false);
    assert(strstr(str.data, "\\n") != NULL);
    assert(strstr(str.data, "\\t") != NULL);

    agent_string_free(&str);
}

TEST(serialize_pretty) {
    agent_json_value_t* obj = agent_json_object(ctx, 2);
    agent_json_object_set(ctx, obj, "key", agent_json_string(ctx, "value"));

    agent_string_t str;
    agent_string_init(&str, 128);

    agent_json_serialize(obj, &str, true);
    assert(strstr(str.data, "\n") != NULL);  /* Has newlines */
    assert(strstr(str.data, "  ") != NULL);  /* Has indentation */

    agent_string_free(&str);
}

TEST(roundtrip) {
    const char* json = "{\"name\":\"test\",\"values\":[1,2,3],\"nested\":{\"flag\":true}}";
    agent_json_parse_result_t result = agent_json_parse_cstr(ctx, json);
    assert(result.error == AGENT_OK);

    char* serialized = agent_json_to_string(ctx, result.value, false);
    assert(serialized != NULL);

    /* Parse again and compare */
    agent_json_parse_result_t result2 = agent_json_parse_cstr(ctx, serialized);
    assert(result2.error == AGENT_OK);

    /* Check values match */
    agent_json_value_t* name = agent_json_object_get(result2.value, "name");
    assert(name != NULL);
    assert(strcmp(name->data.string_value.data, "test") == 0);

    agent_json_value_t* values = agent_json_object_get(result2.value, "values");
    assert(values != NULL);
    assert(values->data.array_value.count == 3);
}

int main(void) {
    ctx = agent_context_create(0);
    assert(ctx != NULL);

    printf("Running JSON parsing tests...\n");

    RUN_TEST(parse_null);
    RUN_TEST(parse_bool);
    RUN_TEST(parse_int);
    RUN_TEST(parse_double);
    RUN_TEST(parse_string);
    RUN_TEST(parse_string_escapes);
    RUN_TEST(parse_array);
    RUN_TEST(parse_object);
    RUN_TEST(parse_nested);
    RUN_TEST(parse_whitespace);
    RUN_TEST(parse_errors);

    agent_context_reset(ctx);

    printf("\nRunning JSON construction tests...\n");

    RUN_TEST(construct_values);
    RUN_TEST(construct_array);
    RUN_TEST(construct_object);

    agent_context_reset(ctx);

    printf("\nRunning JSON serialization tests...\n");

    RUN_TEST(serialize_primitives);
    RUN_TEST(serialize_array);
    RUN_TEST(serialize_object);
    RUN_TEST(serialize_escapes);
    RUN_TEST(serialize_pretty);
    RUN_TEST(roundtrip);

    agent_context_destroy(ctx);

    printf("\nAll JSON tests passed!\n");
    return 0;
}
