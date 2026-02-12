/**
 * @file agent_string.c
 * @brief UTF-8 string utilities implementation
 */

#include "agent_string.h"
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <ctype.h>

#if defined(__APPLE__)
#include <CommonCrypto/CommonRandom.h>
#elif defined(__linux__)
#include <sys/random.h>
#endif

#define DEFAULT_STRING_CAPACITY 64

/* String view operations */

agent_string_view_t agent_sv_from_cstr(const char* str) {
    agent_string_view_t sv;
    if (str) {
        sv.data = str;
        sv.length = strlen(str);
    } else {
        sv.data = NULL;
        sv.length = 0;
    }
    return sv;
}

agent_string_view_t agent_sv_from_parts(const char* data, size_t length) {
    agent_string_view_t sv;
    sv.data = data;
    sv.length = length;
    return sv;
}

bool agent_sv_is_empty(agent_string_view_t sv) {
    return sv.data == NULL || sv.length == 0;
}

bool agent_sv_equals(agent_string_view_t a, agent_string_view_t b) {
    if (a.length != b.length) {
        return false;
    }
    if (a.length == 0) {
        return true;
    }
    return memcmp(a.data, b.data, a.length) == 0;
}

bool agent_sv_equals_cstr(agent_string_view_t sv, const char* str) {
    if (!str) {
        return sv.data == NULL;
    }
    size_t len = strlen(str);
    if (sv.length != len) {
        return false;
    }
    return memcmp(sv.data, str, len) == 0;
}

bool agent_sv_starts_with(agent_string_view_t sv, agent_string_view_t prefix) {
    if (prefix.length > sv.length) {
        return false;
    }
    return memcmp(sv.data, prefix.data, prefix.length) == 0;
}

bool agent_sv_starts_with_cstr(agent_string_view_t sv, const char* prefix) {
    if (!prefix) {
        return true;
    }
    size_t prefix_len = strlen(prefix);
    if (prefix_len > sv.length) {
        return false;
    }
    return memcmp(sv.data, prefix, prefix_len) == 0;
}

bool agent_sv_ends_with(agent_string_view_t sv, agent_string_view_t suffix) {
    if (suffix.length > sv.length) {
        return false;
    }
    return memcmp(sv.data + sv.length - suffix.length, suffix.data, suffix.length) == 0;
}

ptrdiff_t agent_sv_find(agent_string_view_t sv, agent_string_view_t needle) {
    if (needle.length == 0) {
        return 0;
    }
    if (needle.length > sv.length) {
        return -1;
    }

    const char* end = sv.data + sv.length - needle.length + 1;
    for (const char* p = sv.data; p < end; p++) {
        if (memcmp(p, needle.data, needle.length) == 0) {
            return p - sv.data;
        }
    }
    return -1;
}

ptrdiff_t agent_sv_find_cstr(agent_string_view_t sv, const char* needle) {
    if (!needle) {
        return -1;
    }
    return agent_sv_find(sv, agent_sv_from_cstr(needle));
}

ptrdiff_t agent_sv_find_char(agent_string_view_t sv, char c) {
    for (size_t i = 0; i < sv.length; i++) {
        if (sv.data[i] == c) {
            return (ptrdiff_t)i;
        }
    }
    return -1;
}

agent_string_view_t agent_sv_substr(agent_string_view_t sv, size_t start, size_t length) {
    agent_string_view_t result = {NULL, 0};

    if (start >= sv.length) {
        return result;
    }

    size_t remaining = sv.length - start;
    size_t actual_length = length < remaining ? length : remaining;

    result.data = sv.data + start;
    result.length = actual_length;
    return result;
}

agent_string_view_t agent_sv_trim(agent_string_view_t sv) {
    sv = agent_sv_trim_start(sv);
    sv = agent_sv_trim_end(sv);
    return sv;
}

agent_string_view_t agent_sv_trim_start(agent_string_view_t sv) {
    while (sv.length > 0 && isspace((unsigned char)sv.data[0])) {
        sv.data++;
        sv.length--;
    }
    return sv;
}

agent_string_view_t agent_sv_trim_end(agent_string_view_t sv) {
    while (sv.length > 0 && isspace((unsigned char)sv.data[sv.length - 1])) {
        sv.length--;
    }
    return sv;
}

/* UTF-8 operations */

bool agent_utf8_validate(const char* data, size_t length) {
    if (!data) {
        return length == 0;
    }

    const uint8_t* p = (const uint8_t*)data;
    const uint8_t* end = p + length;

    while (p < end) {
        uint8_t byte = *p;

        if (byte < 0x80) {
            /* ASCII */
            p++;
        } else if ((byte & 0xE0) == 0xC0) {
            /* 2-byte sequence */
            if (p + 1 >= end) return false;
            if ((p[1] & 0xC0) != 0x80) return false;
            /* Check for overlong encoding */
            if (byte < 0xC2) return false;
            p += 2;
        } else if ((byte & 0xF0) == 0xE0) {
            /* 3-byte sequence */
            if (p + 2 >= end) return false;
            if ((p[1] & 0xC0) != 0x80) return false;
            if ((p[2] & 0xC0) != 0x80) return false;
            /* Check for overlong encoding and surrogates */
            uint32_t cp = ((byte & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
            if (cp < 0x800) return false;
            if (cp >= 0xD800 && cp <= 0xDFFF) return false;
            p += 3;
        } else if ((byte & 0xF8) == 0xF0) {
            /* 4-byte sequence */
            if (p + 3 >= end) return false;
            if ((p[1] & 0xC0) != 0x80) return false;
            if ((p[2] & 0xC0) != 0x80) return false;
            if ((p[3] & 0xC0) != 0x80) return false;
            /* Check for overlong encoding and valid range */
            uint32_t cp = ((byte & 0x07) << 18) | ((p[1] & 0x3F) << 12) |
                          ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
            if (cp < 0x10000 || cp > 0x10FFFF) return false;
            p += 4;
        } else {
            /* Invalid byte */
            return false;
        }
    }

    return true;
}

size_t agent_utf8_char_length(uint8_t first_byte) {
    if (first_byte < 0x80) {
        return 1;
    } else if ((first_byte & 0xE0) == 0xC0) {
        return 2;
    } else if ((first_byte & 0xF0) == 0xE0) {
        return 3;
    } else if ((first_byte & 0xF8) == 0xF0) {
        return 4;
    }
    return 0;  /* Invalid */
}

size_t agent_utf8_char_count(const char* data, size_t length) {
    if (!data) {
        return 0;
    }

    size_t count = 0;
    const uint8_t* p = (const uint8_t*)data;
    const uint8_t* end = p + length;

    while (p < end) {
        size_t char_len = agent_utf8_char_length(*p);
        if (char_len == 0 || p + char_len > end) {
            break;
        }
        count++;
        p += char_len;
    }

    return count;
}

size_t agent_utf8_char_start(const char* data, size_t length, size_t pos) {
    if (!data || pos >= length) {
        return pos;
    }

    /* Scan backwards to find the start of the character */
    const uint8_t* p = (const uint8_t*)data;
    while (pos > 0 && (p[pos] & 0xC0) == 0x80) {
        pos--;
    }
    return pos;
}

size_t agent_utf8_extract_char(const char* buffer, size_t length,
                               const char** out_char, size_t* out_char_len) {
    if (!buffer || length == 0 || !out_char || !out_char_len) {
        return 0;
    }

    const uint8_t* p = (const uint8_t*)buffer;
    size_t char_len = agent_utf8_char_length(p[0]);

    if (char_len == 0) {
        /* Invalid first byte - skip it */
        *out_char = buffer;
        *out_char_len = 1;
        return 1;
    }

    if (char_len > length) {
        /* Incomplete character */
        *out_char = NULL;
        *out_char_len = 0;
        return 0;
    }

    /* Validate continuation bytes */
    for (size_t i = 1; i < char_len; i++) {
        if ((p[i] & 0xC0) != 0x80) {
            /* Invalid continuation byte */
            *out_char = buffer;
            *out_char_len = 1;
            return 1;
        }
    }

    *out_char = buffer;
    *out_char_len = char_len;
    return char_len;
}

size_t agent_utf8_complete_boundary(const char* data, size_t length) {
    if (!data || length == 0) {
        return 0;
    }

    const uint8_t* p = (const uint8_t*)data;
    size_t pos = 0;

    while (pos < length) {
        size_t char_len = agent_utf8_char_length(p[pos]);

        if (char_len == 0) {
            /* Invalid byte - include it */
            pos++;
            continue;
        }

        if (pos + char_len > length) {
            /* Incomplete character at end */
            break;
        }

        pos += char_len;
    }

    return pos;
}

/* Mutable string operations */

agent_error_t agent_string_init(agent_string_t* str, size_t initial_capacity) {
    if (!str) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    size_t capacity = initial_capacity > 0 ? initial_capacity : DEFAULT_STRING_CAPACITY;
    str->data = (char*)malloc(capacity);
    if (!str->data) {
        return AGENT_ERROR_OUT_OF_MEMORY;
    }

    str->data[0] = '\0';
    str->length = 0;
    str->capacity = capacity;
    return AGENT_OK;
}

void agent_string_free(agent_string_t* str) {
    if (str && str->data) {
        free(str->data);
        str->data = NULL;
        str->length = 0;
        str->capacity = 0;
    }
}

void agent_string_clear(agent_string_t* str) {
    if (str && str->data) {
        str->data[0] = '\0';
        str->length = 0;
    }
}

agent_error_t agent_string_reserve(agent_string_t* str, size_t capacity) {
    if (!str) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    if (capacity <= str->capacity) {
        return AGENT_OK;
    }

    /* Grow by at least 1.5x */
    size_t new_capacity = str->capacity + (str->capacity >> 1);
    if (new_capacity < capacity) {
        new_capacity = capacity;
    }

    char* new_data = (char*)realloc(str->data, new_capacity);
    if (!new_data) {
        return AGENT_ERROR_OUT_OF_MEMORY;
    }

    str->data = new_data;
    str->capacity = new_capacity;
    return AGENT_OK;
}

agent_error_t agent_string_append(agent_string_t* str, const char* cstr) {
    if (!cstr) {
        return AGENT_OK;
    }
    return agent_string_append_n(str, cstr, strlen(cstr));
}

agent_error_t agent_string_append_n(agent_string_t* str, const char* data, size_t length) {
    if (!str || !str->data) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }
    if (!data || length == 0) {
        return AGENT_OK;
    }

    size_t required = str->length + length + 1;
    if (required > str->capacity) {
        agent_error_t err = agent_string_reserve(str, required);
        if (err != AGENT_OK) {
            return err;
        }
    }

    memcpy(str->data + str->length, data, length);
    str->length += length;
    str->data[str->length] = '\0';
    return AGENT_OK;
}

agent_error_t agent_string_append_sv(agent_string_t* str, agent_string_view_t sv) {
    return agent_string_append_n(str, sv.data, sv.length);
}

agent_error_t agent_string_append_char(agent_string_t* str, char c) {
    return agent_string_append_n(str, &c, 1);
}

agent_error_t agent_string_append_fmt(agent_string_t* str, const char* fmt, ...) {
    if (!str || !str->data || !fmt) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    va_list args, args_copy;
    va_start(args, fmt);
    va_copy(args_copy, args);

    /* First, determine the required size */
    int needed = vsnprintf(NULL, 0, fmt, args);
    va_end(args);

    if (needed < 0) {
        va_end(args_copy);
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    size_t required = str->length + (size_t)needed + 1;
    if (required > str->capacity) {
        agent_error_t err = agent_string_reserve(str, required);
        if (err != AGENT_OK) {
            va_end(args_copy);
            return err;
        }
    }

    /* Now format into the buffer */
    vsnprintf(str->data + str->length, (size_t)needed + 1, fmt, args_copy);
    va_end(args_copy);

    str->length += (size_t)needed;
    return AGENT_OK;
}

agent_string_view_t agent_string_view(const agent_string_t* str) {
    agent_string_view_t sv = {NULL, 0};
    if (str && str->data) {
        sv.data = str->data;
        sv.length = str->length;
    }
    return sv;
}

const char* agent_string_cstr(const agent_string_t* str) {
    if (str && str->data) {
        return str->data;
    }
    return "";
}

/* UUID operations */

agent_uuid_t agent_uuid_generate(void) {
    agent_uuid_t uuid;

#if defined(__APPLE__)
    CCRandomGenerateBytes(uuid.bytes, 16);
#elif defined(__linux__)
    getrandom(uuid.bytes, 16, 0);
#else
    /* Fallback - not cryptographically secure */
    for (int i = 0; i < 16; i++) {
        uuid.bytes[i] = (uint8_t)(rand() & 0xFF);
    }
#endif

    /* Set version (4) and variant (RFC 4122) bits */
    uuid.bytes[6] = (uuid.bytes[6] & 0x0F) | 0x40;  /* Version 4 */
    uuid.bytes[8] = (uuid.bytes[8] & 0x3F) | 0x80;  /* Variant */

    return uuid;
}

static int hex_to_int(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

agent_error_t agent_uuid_from_string(const char* str, agent_uuid_t* out_uuid) {
    if (!str || !out_uuid) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    /* Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx */
    if (strlen(str) != 36) {
        return AGENT_ERROR_PARSE_ERROR;
    }

    const int positions[] = {0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34};
    const int dash_positions[] = {8, 13, 18, 23};

    /* Verify dashes */
    for (int i = 0; i < 4; i++) {
        if (str[dash_positions[i]] != '-') {
            return AGENT_ERROR_PARSE_ERROR;
        }
    }

    /* Parse hex bytes */
    for (int i = 0; i < 16; i++) {
        int hi = hex_to_int(str[positions[i]]);
        int lo = hex_to_int(str[positions[i] + 1]);
        if (hi < 0 || lo < 0) {
            return AGENT_ERROR_PARSE_ERROR;
        }
        out_uuid->bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    return AGENT_OK;
}

void agent_uuid_to_string(agent_uuid_t uuid, char* buffer) {
    static const char hex[] = "0123456789abcdef";
    int j = 0;
    for (int i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) {
            buffer[j++] = '-';
        }
        buffer[j++] = hex[(uuid.bytes[i] >> 4) & 0x0F];
        buffer[j++] = hex[uuid.bytes[i] & 0x0F];
    }
    buffer[j] = '\0';
}

bool agent_uuid_equals(agent_uuid_t a, agent_uuid_t b) {
    return memcmp(a.bytes, b.bytes, 16) == 0;
}

bool agent_uuid_is_nil(agent_uuid_t uuid) {
    for (int i = 0; i < 16; i++) {
        if (uuid.bytes[i] != 0) {
            return false;
        }
    }
    return true;
}
