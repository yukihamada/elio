/**
 * @file agent_json.c
 * @brief JSON parser and serializer implementation
 */

#include "agent_json.h"
#include "agent_string.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#define DEFAULT_ARRAY_CAPACITY 8
#define DEFAULT_OBJECT_CAPACITY 8

/* Parser state */
typedef struct {
    agent_context_t* ctx;
    const char* json;
    size_t length;
    size_t pos;
    agent_error_t error;
    const char* error_message;
} json_parser_t;

/* Forward declarations */
static agent_json_value_t* parse_value(json_parser_t* p);
static void skip_whitespace(json_parser_t* p);

/* Constructors */

agent_json_value_t* agent_json_null(agent_context_t* ctx) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (val) {
        val->type = AGENT_JSON_NULL;
    }
    return val;
}

agent_json_value_t* agent_json_bool(agent_context_t* ctx, bool value) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (val) {
        val->type = AGENT_JSON_BOOL;
        val->data.bool_value = value;
    }
    return val;
}

agent_json_value_t* agent_json_int(agent_context_t* ctx, int64_t value) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (val) {
        val->type = AGENT_JSON_INT;
        val->data.int_value = value;
    }
    return val;
}

agent_json_value_t* agent_json_double(agent_context_t* ctx, double value) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (val) {
        val->type = AGENT_JSON_DOUBLE;
        val->data.double_value = value;
    }
    return val;
}

agent_json_value_t* agent_json_string(agent_context_t* ctx, const char* str) {
    if (!str) {
        return agent_json_null(ctx);
    }
    return agent_json_string_n(ctx, str, strlen(str));
}

agent_json_value_t* agent_json_string_n(agent_context_t* ctx, const char* str, size_t len) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (val) {
        val->type = AGENT_JSON_STRING;
        val->data.string_value = agent_context_string_view_n(ctx, str, len);
    }
    return val;
}

agent_json_value_t* agent_json_array(agent_context_t* ctx, size_t initial_capacity) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (!val) {
        return NULL;
    }

    size_t capacity = initial_capacity > 0 ? initial_capacity : DEFAULT_ARRAY_CAPACITY;
    agent_json_value_t** items = agent_context_calloc(ctx, capacity, sizeof(agent_json_value_t*));
    if (!items) {
        return NULL;
    }

    val->type = AGENT_JSON_ARRAY;
    val->data.array_value.items = items;
    val->data.array_value.count = 0;
    return val;
}

agent_json_value_t* agent_json_object(agent_context_t* ctx, size_t initial_capacity) {
    agent_json_value_t* val = agent_context_alloc(ctx, sizeof(agent_json_value_t));
    if (!val) {
        return NULL;
    }

    size_t capacity = initial_capacity > 0 ? initial_capacity : DEFAULT_OBJECT_CAPACITY;
    agent_json_entry_t* entries = agent_context_calloc(ctx, capacity, sizeof(agent_json_entry_t));
    if (!entries) {
        return NULL;
    }

    val->type = AGENT_JSON_OBJECT;
    val->data.object_value.entries = entries;
    val->data.object_value.count = 0;
    return val;
}

/* Array operations */

agent_error_t agent_json_array_append(agent_context_t* ctx, agent_json_value_t* array,
                                      agent_json_value_t* value) {
    if (!array || array->type != AGENT_JSON_ARRAY || !value) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    /* Note: In an arena allocator, we can't resize in place easily.
       For simplicity, we allocate a new larger array and copy. */
    size_t count = array->data.array_value.count;

    /* Check if we have space (we don't track capacity, so estimate) */
    agent_json_value_t** new_items = agent_context_calloc(ctx, count + 1, sizeof(agent_json_value_t*));
    if (!new_items) {
        return AGENT_ERROR_OUT_OF_MEMORY;
    }

    memcpy(new_items, array->data.array_value.items, count * sizeof(agent_json_value_t*));
    new_items[count] = value;

    array->data.array_value.items = new_items;
    array->data.array_value.count = count + 1;
    return AGENT_OK;
}

size_t agent_json_array_length(const agent_json_value_t* array) {
    if (!array || array->type != AGENT_JSON_ARRAY) {
        return 0;
    }
    return array->data.array_value.count;
}

agent_json_value_t* agent_json_array_get(const agent_json_value_t* array, size_t index) {
    if (!array || array->type != AGENT_JSON_ARRAY) {
        return NULL;
    }
    if (index >= array->data.array_value.count) {
        return NULL;
    }
    return array->data.array_value.items[index];
}

/* Object operations */

agent_error_t agent_json_object_set(agent_context_t* ctx, agent_json_value_t* object,
                                    const char* key, agent_json_value_t* value) {
    if (!key) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    return agent_json_object_set_n(ctx, object, key, strlen(key), value);
}

agent_error_t agent_json_object_set_n(agent_context_t* ctx, agent_json_value_t* object,
                                      const char* key, size_t key_len, agent_json_value_t* value) {
    if (!object || object->type != AGENT_JSON_OBJECT || !key || !value) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    /* Check if key already exists */
    for (size_t i = 0; i < object->data.object_value.count; i++) {
        agent_json_entry_t* entry = &object->data.object_value.entries[i];
        if (entry->key.length == key_len &&
            memcmp(entry->key.data, key, key_len) == 0) {
            entry->value = value;
            return AGENT_OK;
        }
    }

    /* Add new entry */
    size_t count = object->data.object_value.count;
    agent_json_entry_t* new_entries = agent_context_calloc(ctx, count + 1, sizeof(agent_json_entry_t));
    if (!new_entries) {
        return AGENT_ERROR_OUT_OF_MEMORY;
    }

    memcpy(new_entries, object->data.object_value.entries, count * sizeof(agent_json_entry_t));
    new_entries[count].key = agent_context_string_view_n(ctx, key, key_len);
    new_entries[count].value = value;

    object->data.object_value.entries = new_entries;
    object->data.object_value.count = count + 1;
    return AGENT_OK;
}

agent_json_value_t* agent_json_object_get(const agent_json_value_t* object, const char* key) {
    if (!key) {
        return NULL;
    }
    return agent_json_object_get_n(object, key, strlen(key));
}

agent_json_value_t* agent_json_object_get_n(const agent_json_value_t* object,
                                            const char* key, size_t key_len) {
    if (!object || object->type != AGENT_JSON_OBJECT || !key) {
        return NULL;
    }

    for (size_t i = 0; i < object->data.object_value.count; i++) {
        const agent_json_entry_t* entry = &object->data.object_value.entries[i];
        if (entry->key.length == key_len &&
            memcmp(entry->key.data, key, key_len) == 0) {
            return entry->value;
        }
    }
    return NULL;
}

bool agent_json_object_has(const agent_json_value_t* object, const char* key) {
    return agent_json_object_get(object, key) != NULL;
}

size_t agent_json_object_length(const agent_json_value_t* object) {
    if (!object || object->type != AGENT_JSON_OBJECT) {
        return 0;
    }
    return object->data.object_value.count;
}

/* Type accessors */

agent_json_type_t agent_json_get_type(const agent_json_value_t* value) {
    if (!value) {
        return AGENT_JSON_NULL;
    }
    return value->type;
}

agent_error_t agent_json_get_bool(const agent_json_value_t* value, bool* out_value) {
    if (!value || !out_value) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    if (value->type != AGENT_JSON_BOOL) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    *out_value = value->data.bool_value;
    return AGENT_OK;
}

agent_error_t agent_json_get_int(const agent_json_value_t* value, int64_t* out_value) {
    if (!value || !out_value) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    if (value->type == AGENT_JSON_INT) {
        *out_value = value->data.int_value;
        return AGENT_OK;
    }
    if (value->type == AGENT_JSON_DOUBLE) {
        *out_value = (int64_t)value->data.double_value;
        return AGENT_OK;
    }
    return AGENT_ERROR_INVALID_ARGUMENT;
}

agent_error_t agent_json_get_double(const agent_json_value_t* value, double* out_value) {
    if (!value || !out_value) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    if (value->type == AGENT_JSON_DOUBLE) {
        *out_value = value->data.double_value;
        return AGENT_OK;
    }
    if (value->type == AGENT_JSON_INT) {
        *out_value = (double)value->data.int_value;
        return AGENT_OK;
    }
    return AGENT_ERROR_INVALID_ARGUMENT;
}

agent_error_t agent_json_get_string(const agent_json_value_t* value, agent_string_view_t* out_value) {
    if (!value || !out_value) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    if (value->type != AGENT_JSON_STRING) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    *out_value = value->data.string_value;
    return AGENT_OK;
}

/* Parser helpers */

static inline bool is_at_end(json_parser_t* p) {
    return p->pos >= p->length;
}

static inline char peek(json_parser_t* p) {
    if (is_at_end(p)) return '\0';
    return p->json[p->pos];
}

static inline char advance(json_parser_t* p) {
    if (is_at_end(p)) return '\0';
    return p->json[p->pos++];
}

static inline bool match(json_parser_t* p, char expected) {
    if (is_at_end(p) || p->json[p->pos] != expected) {
        return false;
    }
    p->pos++;
    return true;
}

static void skip_whitespace(json_parser_t* p) {
    while (!is_at_end(p)) {
        char c = peek(p);
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            p->pos++;
        } else {
            break;
        }
    }
}

static void set_error(json_parser_t* p, const char* message) {
    if (p->error == AGENT_OK) {
        p->error = AGENT_ERROR_PARSE_ERROR;
        p->error_message = message;
    }
}

/* Parse string (handles escape sequences) */
static agent_json_value_t* parse_string(json_parser_t* p) {
    if (!match(p, '"')) {
        set_error(p, "Expected '\"'");
        return NULL;
    }

    size_t start = p->pos;
    bool has_escapes = false;

    while (!is_at_end(p) && peek(p) != '"') {
        if (peek(p) == '\\') {
            has_escapes = true;
            p->pos++;  /* Skip backslash */
            if (is_at_end(p)) {
                set_error(p, "Unterminated string");
                return NULL;
            }
            p->pos++;  /* Skip escaped character */
        } else {
            p->pos++;
        }
    }

    if (!match(p, '"')) {
        set_error(p, "Unterminated string");
        return NULL;
    }

    size_t end = p->pos - 1;
    const char* str = p->json + start;
    size_t len = end - start;

    if (!has_escapes) {
        return agent_json_string_n(p->ctx, str, len);
    }

    /* Handle escape sequences */
    char* buf = agent_context_alloc(p->ctx, len + 1);
    if (!buf) {
        set_error(p, "Out of memory");
        return NULL;
    }

    size_t j = 0;
    for (size_t i = 0; i < len; i++) {
        if (str[i] == '\\' && i + 1 < len) {
            i++;
            switch (str[i]) {
                case '"':  buf[j++] = '"';  break;
                case '\\': buf[j++] = '\\'; break;
                case '/':  buf[j++] = '/';  break;
                case 'b':  buf[j++] = '\b'; break;
                case 'f':  buf[j++] = '\f'; break;
                case 'n':  buf[j++] = '\n'; break;
                case 'r':  buf[j++] = '\r'; break;
                case 't':  buf[j++] = '\t'; break;
                case 'u': {
                    /* Parse Unicode escape \uXXXX */
                    if (i + 4 >= len) {
                        buf[j++] = str[i];
                        break;
                    }
                    unsigned int codepoint = 0;
                    for (int k = 0; k < 4; k++) {
                        char c = str[i + 1 + k];
                        codepoint <<= 4;
                        if (c >= '0' && c <= '9') codepoint |= (c - '0');
                        else if (c >= 'a' && c <= 'f') codepoint |= (c - 'a' + 10);
                        else if (c >= 'A' && c <= 'F') codepoint |= (c - 'A' + 10);
                        else {
                            codepoint = 0xFFFFFFFF;
                            break;
                        }
                    }
                    if (codepoint == 0xFFFFFFFF) {
                        buf[j++] = 'u';
                        break;
                    }
                    i += 4;
                    /* Encode as UTF-8 */
                    if (codepoint < 0x80) {
                        buf[j++] = (char)codepoint;
                    } else if (codepoint < 0x800) {
                        buf[j++] = (char)(0xC0 | (codepoint >> 6));
                        buf[j++] = (char)(0x80 | (codepoint & 0x3F));
                    } else if (codepoint < 0x10000) {
                        buf[j++] = (char)(0xE0 | (codepoint >> 12));
                        buf[j++] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
                        buf[j++] = (char)(0x80 | (codepoint & 0x3F));
                    } else {
                        buf[j++] = (char)(0xF0 | (codepoint >> 18));
                        buf[j++] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
                        buf[j++] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
                        buf[j++] = (char)(0x80 | (codepoint & 0x3F));
                    }
                    break;
                }
                default:
                    buf[j++] = str[i];
                    break;
            }
        } else {
            buf[j++] = str[i];
        }
    }
    buf[j] = '\0';

    agent_json_value_t* val = agent_context_alloc(p->ctx, sizeof(agent_json_value_t));
    if (!val) {
        return NULL;
    }
    val->type = AGENT_JSON_STRING;
    val->data.string_value.data = buf;
    val->data.string_value.length = j;
    return val;
}

/* Parse number */
static agent_json_value_t* parse_number(json_parser_t* p) {
    size_t start = p->pos;
    bool is_double = false;

    /* Optional minus */
    if (peek(p) == '-') {
        advance(p);
    }

    /* Integer part */
    if (peek(p) == '0') {
        advance(p);
    } else if (peek(p) >= '1' && peek(p) <= '9') {
        while (peek(p) >= '0' && peek(p) <= '9') {
            advance(p);
        }
    } else {
        set_error(p, "Invalid number");
        return NULL;
    }

    /* Fractional part */
    if (peek(p) == '.') {
        is_double = true;
        advance(p);
        if (peek(p) < '0' || peek(p) > '9') {
            set_error(p, "Expected digit after decimal point");
            return NULL;
        }
        while (peek(p) >= '0' && peek(p) <= '9') {
            advance(p);
        }
    }

    /* Exponent */
    if (peek(p) == 'e' || peek(p) == 'E') {
        is_double = true;
        advance(p);
        if (peek(p) == '+' || peek(p) == '-') {
            advance(p);
        }
        if (peek(p) < '0' || peek(p) > '9') {
            set_error(p, "Expected digit in exponent");
            return NULL;
        }
        while (peek(p) >= '0' && peek(p) <= '9') {
            advance(p);
        }
    }

    size_t len = p->pos - start;
    char* num_str = agent_context_strndup(p->ctx, p->json + start, len);
    if (!num_str) {
        set_error(p, "Out of memory");
        return NULL;
    }

    if (is_double) {
        double d = strtod(num_str, NULL);
        return agent_json_double(p->ctx, d);
    } else {
        int64_t i = strtoll(num_str, NULL, 10);
        return agent_json_int(p->ctx, i);
    }
}

/* Parse array */
static agent_json_value_t* parse_array(json_parser_t* p) {
    if (!match(p, '[')) {
        set_error(p, "Expected '['");
        return NULL;
    }

    agent_json_value_t* array = agent_json_array(p->ctx, DEFAULT_ARRAY_CAPACITY);
    if (!array) {
        set_error(p, "Out of memory");
        return NULL;
    }

    skip_whitespace(p);
    if (match(p, ']')) {
        return array;
    }

    do {
        skip_whitespace(p);
        agent_json_value_t* element = parse_value(p);
        if (!element || p->error != AGENT_OK) {
            return NULL;
        }

        agent_error_t err = agent_json_array_append(p->ctx, array, element);
        if (err != AGENT_OK) {
            set_error(p, "Out of memory");
            return NULL;
        }

        skip_whitespace(p);
    } while (match(p, ','));

    if (!match(p, ']')) {
        set_error(p, "Expected ',' or ']'");
        return NULL;
    }

    return array;
}

/* Parse object */
static agent_json_value_t* parse_object(json_parser_t* p) {
    if (!match(p, '{')) {
        set_error(p, "Expected '{'");
        return NULL;
    }

    agent_json_value_t* object = agent_json_object(p->ctx, DEFAULT_OBJECT_CAPACITY);
    if (!object) {
        set_error(p, "Out of memory");
        return NULL;
    }

    skip_whitespace(p);
    if (match(p, '}')) {
        return object;
    }

    do {
        skip_whitespace(p);

        /* Parse key */
        if (peek(p) != '"') {
            set_error(p, "Expected string key");
            return NULL;
        }
        agent_json_value_t* key_val = parse_string(p);
        if (!key_val || p->error != AGENT_OK) {
            return NULL;
        }

        skip_whitespace(p);
        if (!match(p, ':')) {
            set_error(p, "Expected ':'");
            return NULL;
        }

        skip_whitespace(p);
        agent_json_value_t* value = parse_value(p);
        if (!value || p->error != AGENT_OK) {
            return NULL;
        }

        agent_error_t err = agent_json_object_set_n(p->ctx, object,
            key_val->data.string_value.data,
            key_val->data.string_value.length,
            value);
        if (err != AGENT_OK) {
            set_error(p, "Out of memory");
            return NULL;
        }

        skip_whitespace(p);
    } while (match(p, ','));

    if (!match(p, '}')) {
        set_error(p, "Expected ',' or '}'");
        return NULL;
    }

    return object;
}

/* Parse any value */
static agent_json_value_t* parse_value(json_parser_t* p) {
    skip_whitespace(p);

    if (is_at_end(p)) {
        set_error(p, "Unexpected end of input");
        return NULL;
    }

    char c = peek(p);

    if (c == 'n') {
        if (p->pos + 4 <= p->length && memcmp(p->json + p->pos, "null", 4) == 0) {
            p->pos += 4;
            return agent_json_null(p->ctx);
        }
    } else if (c == 't') {
        if (p->pos + 4 <= p->length && memcmp(p->json + p->pos, "true", 4) == 0) {
            p->pos += 4;
            return agent_json_bool(p->ctx, true);
        }
    } else if (c == 'f') {
        if (p->pos + 5 <= p->length && memcmp(p->json + p->pos, "false", 5) == 0) {
            p->pos += 5;
            return agent_json_bool(p->ctx, false);
        }
    } else if (c == '"') {
        return parse_string(p);
    } else if (c == '[') {
        return parse_array(p);
    } else if (c == '{') {
        return parse_object(p);
    } else if (c == '-' || (c >= '0' && c <= '9')) {
        return parse_number(p);
    }

    set_error(p, "Unexpected character");
    return NULL;
}

/* Public parsing functions */

agent_json_parse_result_t agent_json_parse(agent_context_t* ctx, const char* json, size_t length) {
    agent_json_parse_result_t result = {0};

    if (!ctx || !json) {
        result.error = AGENT_ERROR_INVALID_ARGUMENT;
        result.error_message = "Invalid arguments";
        return result;
    }

    json_parser_t parser = {
        .ctx = ctx,
        .json = json,
        .length = length,
        .pos = 0,
        .error = AGENT_OK,
        .error_message = NULL
    };

    result.value = parse_value(&parser);
    result.error = parser.error;
    result.error_message = parser.error_message;
    result.error_position = parser.pos;

    /* Check for trailing content */
    if (result.error == AGENT_OK) {
        skip_whitespace(&parser);
        if (!is_at_end(&parser)) {
            result.error = AGENT_ERROR_PARSE_ERROR;
            result.error_message = "Unexpected content after JSON";
            result.error_position = parser.pos;
        }
    }

    return result;
}

agent_json_parse_result_t agent_json_parse_cstr(agent_context_t* ctx, const char* json) {
    if (!json) {
        agent_json_parse_result_t result = {0};
        result.error = AGENT_ERROR_INVALID_ARGUMENT;
        result.error_message = "Invalid arguments";
        return result;
    }
    return agent_json_parse(ctx, json, strlen(json));
}

/* Serialization helpers */

static agent_error_t serialize_string(const char* str, size_t len, agent_string_t* out) {
    agent_error_t err = agent_string_append_char(out, '"');
    if (err != AGENT_OK) return err;

    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)str[i];
        switch (c) {
            case '"':  err = agent_string_append(out, "\\\""); break;
            case '\\': err = agent_string_append(out, "\\\\"); break;
            case '\b': err = agent_string_append(out, "\\b"); break;
            case '\f': err = agent_string_append(out, "\\f"); break;
            case '\n': err = agent_string_append(out, "\\n"); break;
            case '\r': err = agent_string_append(out, "\\r"); break;
            case '\t': err = agent_string_append(out, "\\t"); break;
            default:
                if (c < 0x20) {
                    err = agent_string_append_fmt(out, "\\u%04x", c);
                } else {
                    err = agent_string_append_char(out, (char)c);
                }
                break;
        }
        if (err != AGENT_OK) return err;
    }

    return agent_string_append_char(out, '"');
}

static agent_error_t serialize_value(const agent_json_value_t* value, agent_string_t* out,
                                     bool pretty, int depth);

static agent_error_t serialize_indent(agent_string_t* out, int depth) {
    for (int i = 0; i < depth; i++) {
        agent_error_t err = agent_string_append(out, "  ");
        if (err != AGENT_OK) return err;
    }
    return AGENT_OK;
}

static agent_error_t serialize_array(const agent_json_value_t* array, agent_string_t* out,
                                     bool pretty, int depth) {
    agent_error_t err = agent_string_append_char(out, '[');
    if (err != AGENT_OK) return err;

    size_t count = array->data.array_value.count;
    if (count == 0) {
        return agent_string_append_char(out, ']');
    }

    if (pretty) {
        err = agent_string_append_char(out, '\n');
        if (err != AGENT_OK) return err;
    }

    for (size_t i = 0; i < count; i++) {
        if (pretty) {
            err = serialize_indent(out, depth + 1);
            if (err != AGENT_OK) return err;
        }

        err = serialize_value(array->data.array_value.items[i], out, pretty, depth + 1);
        if (err != AGENT_OK) return err;

        if (i < count - 1) {
            err = agent_string_append_char(out, ',');
            if (err != AGENT_OK) return err;
        }

        if (pretty) {
            err = agent_string_append_char(out, '\n');
            if (err != AGENT_OK) return err;
        }
    }

    if (pretty) {
        err = serialize_indent(out, depth);
        if (err != AGENT_OK) return err;
    }

    return agent_string_append_char(out, ']');
}

static agent_error_t serialize_object(const agent_json_value_t* object, agent_string_t* out,
                                      bool pretty, int depth) {
    agent_error_t err = agent_string_append_char(out, '{');
    if (err != AGENT_OK) return err;

    size_t count = object->data.object_value.count;
    if (count == 0) {
        return agent_string_append_char(out, '}');
    }

    if (pretty) {
        err = agent_string_append_char(out, '\n');
        if (err != AGENT_OK) return err;
    }

    for (size_t i = 0; i < count; i++) {
        const agent_json_entry_t* entry = &object->data.object_value.entries[i];

        if (pretty) {
            err = serialize_indent(out, depth + 1);
            if (err != AGENT_OK) return err;
        }

        err = serialize_string(entry->key.data, entry->key.length, out);
        if (err != AGENT_OK) return err;

        err = agent_string_append_char(out, ':');
        if (err != AGENT_OK) return err;

        if (pretty) {
            err = agent_string_append_char(out, ' ');
            if (err != AGENT_OK) return err;
        }

        err = serialize_value(entry->value, out, pretty, depth + 1);
        if (err != AGENT_OK) return err;

        if (i < count - 1) {
            err = agent_string_append_char(out, ',');
            if (err != AGENT_OK) return err;
        }

        if (pretty) {
            err = agent_string_append_char(out, '\n');
            if (err != AGENT_OK) return err;
        }
    }

    if (pretty) {
        err = serialize_indent(out, depth);
        if (err != AGENT_OK) return err;
    }

    return agent_string_append_char(out, '}');
}

static agent_error_t serialize_value(const agent_json_value_t* value, agent_string_t* out,
                                     bool pretty, int depth) {
    if (!value) {
        return agent_string_append(out, "null");
    }

    switch (value->type) {
        case AGENT_JSON_NULL:
            return agent_string_append(out, "null");

        case AGENT_JSON_BOOL:
            return agent_string_append(out, value->data.bool_value ? "true" : "false");

        case AGENT_JSON_INT:
            return agent_string_append_fmt(out, "%lld", (long long)value->data.int_value);

        case AGENT_JSON_DOUBLE: {
            double d = value->data.double_value;
            if (isnan(d) || isinf(d)) {
                return agent_string_append(out, "null");
            }
            /* Check if it's a whole number */
            if (floor(d) == d && fabs(d) < 1e15) {
                return agent_string_append_fmt(out, "%.0f", d);
            }
            return agent_string_append_fmt(out, "%.15g", d);
        }

        case AGENT_JSON_STRING:
            return serialize_string(value->data.string_value.data,
                                   value->data.string_value.length, out);

        case AGENT_JSON_ARRAY:
            return serialize_array(value, out, pretty, depth);

        case AGENT_JSON_OBJECT:
            return serialize_object(value, out, pretty, depth);
    }

    return AGENT_ERROR_INVALID_ARGUMENT;
}

agent_error_t agent_json_serialize(const agent_json_value_t* value, agent_string_t* str, bool pretty) {
    if (!str) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    return serialize_value(value, str, pretty, 0);
}

char* agent_json_to_string(agent_context_t* ctx, const agent_json_value_t* value, bool pretty) {
    if (!ctx) {
        return NULL;
    }

    agent_string_t str;
    if (agent_string_init(&str, 256) != AGENT_OK) {
        return NULL;
    }

    agent_error_t err = agent_json_serialize(value, &str, pretty);
    if (err != AGENT_OK) {
        agent_string_free(&str);
        return NULL;
    }

    /* Copy to arena */
    char* result = agent_context_strdup(ctx, str.data);
    agent_string_free(&str);
    return result;
}
