/**
 * @file test_string.c
 * @brief Unit tests for string utilities
 */

#include "agent_lib.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

#define TEST(name) static void test_##name(void)
#define RUN_TEST(name) do { printf("  " #name "..."); test_##name(); printf(" OK\n"); } while(0)

/* String view tests */

TEST(sv_from_cstr) {
    agent_string_view_t sv = agent_sv_from_cstr("hello");
    assert(sv.length == 5);
    assert(memcmp(sv.data, "hello", 5) == 0);

    sv = agent_sv_from_cstr(NULL);
    assert(sv.data == NULL);
    assert(sv.length == 0);
}

TEST(sv_equals) {
    agent_string_view_t a = agent_sv_from_cstr("hello");
    agent_string_view_t b = agent_sv_from_cstr("hello");
    agent_string_view_t c = agent_sv_from_cstr("world");

    assert(agent_sv_equals(a, b));
    assert(!agent_sv_equals(a, c));
}

TEST(sv_starts_with) {
    agent_string_view_t sv = agent_sv_from_cstr("hello world");

    assert(agent_sv_starts_with_cstr(sv, "hello"));
    assert(!agent_sv_starts_with_cstr(sv, "world"));
    assert(agent_sv_starts_with_cstr(sv, ""));
}

TEST(sv_find) {
    agent_string_view_t sv = agent_sv_from_cstr("hello world hello");

    assert(agent_sv_find_cstr(sv, "world") == 6);
    assert(agent_sv_find_cstr(sv, "hello") == 0);
    assert(agent_sv_find_cstr(sv, "xyz") == -1);
    assert(agent_sv_find_char(sv, 'o') == 4);
}

TEST(sv_substr) {
    agent_string_view_t sv = agent_sv_from_cstr("hello world");

    agent_string_view_t sub = agent_sv_substr(sv, 6, 5);
    assert(sub.length == 5);
    assert(memcmp(sub.data, "world", 5) == 0);

    sub = agent_sv_substr(sv, 6, 100);
    assert(sub.length == 5);  /* Clamped to remaining */
}

TEST(sv_trim) {
    agent_string_view_t sv = agent_sv_from_cstr("  hello  ");
    agent_string_view_t trimmed = agent_sv_trim(sv);

    assert(trimmed.length == 5);
    assert(memcmp(trimmed.data, "hello", 5) == 0);
}

/* UTF-8 tests */

TEST(utf8_validate) {
    assert(agent_utf8_validate("hello", 5));
    assert(agent_utf8_validate("日本語", 9));  /* 3 chars * 3 bytes */
    assert(agent_utf8_validate("emoji: 😀", 12));  /* emoji is 4 bytes */

    /* Invalid sequences */
    char invalid1[] = {(char)0xFF, 0};
    assert(!agent_utf8_validate(invalid1, 1));

    char invalid2[] = {(char)0xC0, (char)0x80, 0};  /* Overlong encoding */
    assert(!agent_utf8_validate(invalid2, 2));
}

TEST(utf8_char_length) {
    assert(agent_utf8_char_length('A') == 1);
    assert(agent_utf8_char_length(0xC0) == 2);
    assert(agent_utf8_char_length(0xE0) == 3);
    assert(agent_utf8_char_length(0xF0) == 4);
    assert(agent_utf8_char_length(0x80) == 0);  /* Invalid */
}

TEST(utf8_char_count) {
    assert(agent_utf8_char_count("hello", 5) == 5);
    assert(agent_utf8_char_count("日本語", 9) == 3);
    assert(agent_utf8_char_count("a日b", 5) == 3);
}

TEST(utf8_complete_boundary) {
    /* Complete string */
    assert(agent_utf8_complete_boundary("hello", 5) == 5);

    /* Partial UTF-8 at end */
    const char* s = "日";  /* 3 bytes */
    assert(agent_utf8_complete_boundary(s, 2) == 0);  /* Only 2 bytes available */
    assert(agent_utf8_complete_boundary(s, 3) == 3);  /* All 3 bytes */
}

/* Mutable string tests */

TEST(string_init_free) {
    agent_string_t str;
    assert(agent_string_init(&str, 0) == AGENT_OK);
    assert(str.data != NULL);
    assert(str.length == 0);
    assert(str.capacity > 0);
    agent_string_free(&str);
}

TEST(string_append) {
    agent_string_t str;
    agent_string_init(&str, 16);

    agent_string_append(&str, "hello");
    assert(str.length == 5);
    assert(strcmp(str.data, "hello") == 0);

    agent_string_append(&str, " world");
    assert(str.length == 11);
    assert(strcmp(str.data, "hello world") == 0);

    agent_string_free(&str);
}

TEST(string_append_fmt) {
    agent_string_t str;
    agent_string_init(&str, 16);

    agent_string_append_fmt(&str, "Number: %d", 42);
    assert(strcmp(str.data, "Number: 42") == 0);

    agent_string_append_fmt(&str, ", Float: %.1f", 3.14);
    assert(strcmp(str.data, "Number: 42, Float: 3.1") == 0);

    agent_string_free(&str);
}

TEST(string_reserve) {
    agent_string_t str;
    agent_string_init(&str, 8);

    /* Force reallocation */
    agent_string_reserve(&str, 100);
    assert(str.capacity >= 100);

    /* Add lots of data */
    for (int i = 0; i < 20; i++) {
        agent_string_append(&str, "hello ");
    }
    assert(str.length == 120);

    agent_string_free(&str);
}

/* UUID tests */

TEST(uuid_generate) {
    agent_uuid_t uuid1 = agent_uuid_generate();
    agent_uuid_t uuid2 = agent_uuid_generate();

    /* UUIDs should be different */
    assert(!agent_uuid_equals(uuid1, uuid2));

    /* Check version bits */
    assert((uuid1.bytes[6] & 0xF0) == 0x40);  /* Version 4 */
    assert((uuid1.bytes[8] & 0xC0) == 0x80);  /* Variant */
}

TEST(uuid_string) {
    agent_uuid_t uuid = agent_uuid_generate();
    char buffer[37];

    agent_uuid_to_string(uuid, buffer);
    assert(strlen(buffer) == 36);
    assert(buffer[8] == '-');
    assert(buffer[13] == '-');
    assert(buffer[18] == '-');
    assert(buffer[23] == '-');

    /* Parse back */
    agent_uuid_t parsed;
    assert(agent_uuid_from_string(buffer, &parsed) == AGENT_OK);
    assert(agent_uuid_equals(uuid, parsed));
}

TEST(uuid_nil) {
    agent_uuid_t nil = {0};
    assert(agent_uuid_is_nil(nil));

    agent_uuid_t uuid = agent_uuid_generate();
    assert(!agent_uuid_is_nil(uuid));
}

int main(void) {
    printf("Running string tests...\n");

    RUN_TEST(sv_from_cstr);
    RUN_TEST(sv_equals);
    RUN_TEST(sv_starts_with);
    RUN_TEST(sv_find);
    RUN_TEST(sv_substr);
    RUN_TEST(sv_trim);

    printf("\nRunning UTF-8 tests...\n");

    RUN_TEST(utf8_validate);
    RUN_TEST(utf8_char_length);
    RUN_TEST(utf8_char_count);
    RUN_TEST(utf8_complete_boundary);

    printf("\nRunning mutable string tests...\n");

    RUN_TEST(string_init_free);
    RUN_TEST(string_append);
    RUN_TEST(string_append_fmt);
    RUN_TEST(string_reserve);

    printf("\nRunning UUID tests...\n");

    RUN_TEST(uuid_generate);
    RUN_TEST(uuid_string);
    RUN_TEST(uuid_nil);

    printf("\nAll string tests passed!\n");
    return 0;
}
