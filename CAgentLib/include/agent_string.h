/**
 * @file agent_string.h
 * @brief UTF-8 string utilities
 */

#ifndef AGENT_STRING_H
#define AGENT_STRING_H

#include "agent_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* String view operations */

/**
 * @brief Create a string view from a C string
 * @param str Null-terminated string
 * @return String view
 */
agent_string_view_t agent_sv_from_cstr(const char* str);

/**
 * @brief Create a string view from pointer and length
 * @param data Pointer to string data
 * @param length Length in bytes
 * @return String view
 */
agent_string_view_t agent_sv_from_parts(const char* data, size_t length);

/**
 * @brief Check if string view is empty
 * @param sv String view
 * @return true if empty
 */
bool agent_sv_is_empty(agent_string_view_t sv);

/**
 * @brief Compare two string views for equality
 * @param a First string view
 * @param b Second string view
 * @return true if equal
 */
bool agent_sv_equals(agent_string_view_t a, agent_string_view_t b);

/**
 * @brief Compare string view with C string
 * @param sv String view
 * @param str C string
 * @return true if equal
 */
bool agent_sv_equals_cstr(agent_string_view_t sv, const char* str);

/**
 * @brief Check if string view starts with prefix
 * @param sv String view
 * @param prefix Prefix to check
 * @return true if sv starts with prefix
 */
bool agent_sv_starts_with(agent_string_view_t sv, agent_string_view_t prefix);

/**
 * @brief Check if string view starts with C string prefix
 * @param sv String view
 * @param prefix Prefix to check
 * @return true if sv starts with prefix
 */
bool agent_sv_starts_with_cstr(agent_string_view_t sv, const char* prefix);

/**
 * @brief Check if string view ends with suffix
 * @param sv String view
 * @param suffix Suffix to check
 * @return true if sv ends with suffix
 */
bool agent_sv_ends_with(agent_string_view_t sv, agent_string_view_t suffix);

/**
 * @brief Find first occurrence of substring
 * @param sv String view to search in
 * @param needle Substring to find
 * @return Index of first occurrence, or -1 if not found
 */
ptrdiff_t agent_sv_find(agent_string_view_t sv, agent_string_view_t needle);

/**
 * @brief Find first occurrence of C string
 * @param sv String view to search in
 * @param needle C string to find
 * @return Index of first occurrence, or -1 if not found
 */
ptrdiff_t agent_sv_find_cstr(agent_string_view_t sv, const char* needle);

/**
 * @brief Find first occurrence of character
 * @param sv String view to search in
 * @param c Character to find
 * @return Index of first occurrence, or -1 if not found
 */
ptrdiff_t agent_sv_find_char(agent_string_view_t sv, char c);

/**
 * @brief Get substring
 * @param sv String view
 * @param start Start index
 * @param length Length (or SIZE_MAX for rest of string)
 * @return Substring view
 */
agent_string_view_t agent_sv_substr(agent_string_view_t sv, size_t start, size_t length);

/**
 * @brief Trim whitespace from both ends
 * @param sv String view
 * @return Trimmed view
 */
agent_string_view_t agent_sv_trim(agent_string_view_t sv);

/**
 * @brief Trim whitespace from start
 * @param sv String view
 * @return Trimmed view
 */
agent_string_view_t agent_sv_trim_start(agent_string_view_t sv);

/**
 * @brief Trim whitespace from end
 * @param sv String view
 * @return Trimmed view
 */
agent_string_view_t agent_sv_trim_end(agent_string_view_t sv);

/* UTF-8 operations */

/**
 * @brief Validate UTF-8 string
 * @param data String data
 * @param length Length in bytes
 * @return true if valid UTF-8
 */
bool agent_utf8_validate(const char* data, size_t length);

/**
 * @brief Get length of UTF-8 character from first byte
 * @param first_byte First byte of character
 * @return Length in bytes (1-4), or 0 if invalid
 */
size_t agent_utf8_char_length(uint8_t first_byte);

/**
 * @brief Count UTF-8 characters in string
 * @param data String data
 * @param length Length in bytes
 * @return Number of UTF-8 characters
 */
size_t agent_utf8_char_count(const char* data, size_t length);

/**
 * @brief Find UTF-8 character boundary
 *
 * Given a byte position, find the start of the UTF-8 character containing it.
 *
 * @param data String data
 * @param length Length in bytes
 * @param pos Byte position
 * @return Byte position of character start
 */
size_t agent_utf8_char_start(const char* data, size_t length, size_t pos);

/**
 * @brief Extract next complete UTF-8 character from potentially incomplete buffer
 *
 * Used for streaming: validates that we have a complete character before outputting.
 *
 * @param buffer Current buffer
 * @param length Buffer length
 * @param out_char Output: pointer to character start (within buffer)
 * @param out_char_len Output: character length in bytes
 * @return Number of bytes consumed (may be less than length if incomplete char at end)
 */
size_t agent_utf8_extract_char(const char* buffer, size_t length,
                               const char** out_char, size_t* out_char_len);

/**
 * @brief Find the boundary of complete UTF-8 characters in a buffer
 *
 * Returns the number of bytes that form complete UTF-8 characters.
 * Useful for streaming when you need to output only complete characters.
 *
 * @param data Buffer data
 * @param length Buffer length
 * @return Number of bytes that form complete characters
 */
size_t agent_utf8_complete_boundary(const char* data, size_t length);

/* Mutable string operations */

/**
 * @brief Initialize a mutable string
 * @param str String to initialize
 * @param initial_capacity Initial capacity (0 for default: 64)
 * @return AGENT_OK on success
 */
agent_error_t agent_string_init(agent_string_t* str, size_t initial_capacity);

/**
 * @brief Free a mutable string
 * @param str String to free
 */
void agent_string_free(agent_string_t* str);

/**
 * @brief Clear string contents (keeps capacity)
 * @param str String to clear
 */
void agent_string_clear(agent_string_t* str);

/**
 * @brief Append C string
 * @param str String to append to
 * @param cstr C string to append
 * @return AGENT_OK on success
 */
agent_error_t agent_string_append(agent_string_t* str, const char* cstr);

/**
 * @brief Append string with length
 * @param str String to append to
 * @param data Data to append
 * @param length Length of data
 * @return AGENT_OK on success
 */
agent_error_t agent_string_append_n(agent_string_t* str, const char* data, size_t length);

/**
 * @brief Append string view
 * @param str String to append to
 * @param sv String view to append
 * @return AGENT_OK on success
 */
agent_error_t agent_string_append_sv(agent_string_t* str, agent_string_view_t sv);

/**
 * @brief Append single character
 * @param str String to append to
 * @param c Character to append
 * @return AGENT_OK on success
 */
agent_error_t agent_string_append_char(agent_string_t* str, char c);

/**
 * @brief Append formatted string
 * @param str String to append to
 * @param fmt Format string
 * @param ... Arguments
 * @return AGENT_OK on success
 */
agent_error_t agent_string_append_fmt(agent_string_t* str, const char* fmt, ...);

/**
 * @brief Reserve capacity
 * @param str String
 * @param capacity Required capacity
 * @return AGENT_OK on success
 */
agent_error_t agent_string_reserve(agent_string_t* str, size_t capacity);

/**
 * @brief Get string view of mutable string
 * @param str Mutable string
 * @return String view
 */
agent_string_view_t agent_string_view(const agent_string_t* str);

/**
 * @brief Get C string (null-terminated)
 * @param str Mutable string
 * @return C string
 */
const char* agent_string_cstr(const agent_string_t* str);

/* UUID operations */

/**
 * @brief Generate a new random UUID
 * @return New UUID
 */
agent_uuid_t agent_uuid_generate(void);

/**
 * @brief Create UUID from string (36 chars: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
 * @param str UUID string
 * @param out_uuid Output UUID
 * @return AGENT_OK on success
 */
agent_error_t agent_uuid_from_string(const char* str, agent_uuid_t* out_uuid);

/**
 * @brief Convert UUID to string
 * @param uuid UUID
 * @param buffer Output buffer (must be at least 37 bytes)
 */
void agent_uuid_to_string(agent_uuid_t uuid, char* buffer);

/**
 * @brief Compare two UUIDs
 * @param a First UUID
 * @param b Second UUID
 * @return true if equal
 */
bool agent_uuid_equals(agent_uuid_t a, agent_uuid_t b);

/**
 * @brief Check if UUID is nil (all zeros)
 * @param uuid UUID to check
 * @return true if nil
 */
bool agent_uuid_is_nil(agent_uuid_t uuid);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_STRING_H */
