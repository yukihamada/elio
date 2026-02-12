/**
 * @file agent_json.h
 * @brief JSON parser and serializer
 */

#ifndef AGENT_JSON_H
#define AGENT_JSON_H

#include "agent_types.h"
#include "agent_context.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief JSON value types
 */
typedef enum {
    AGENT_JSON_NULL = 0,
    AGENT_JSON_BOOL = 1,
    AGENT_JSON_INT = 2,
    AGENT_JSON_DOUBLE = 3,
    AGENT_JSON_STRING = 4,
    AGENT_JSON_ARRAY = 5,
    AGENT_JSON_OBJECT = 6
} agent_json_type_t;

/**
 * @brief JSON object entry (key-value pair)
 */
typedef struct {
    agent_string_view_t key;
    agent_json_value_t* value;
} agent_json_entry_t;

/**
 * @brief JSON value (tagged union)
 */
struct agent_json_value_t {
    agent_json_type_t type;
    union {
        bool bool_value;
        int64_t int_value;
        double double_value;
        agent_string_view_t string_value;
        struct {
            agent_json_value_t** items;
            size_t count;
        } array_value;
        struct {
            agent_json_entry_t* entries;
            size_t count;
        } object_value;
    } data;
};

/* Constructors */

/**
 * @brief Create a null JSON value
 * @param ctx Arena context
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_null(agent_context_t* ctx);

/**
 * @brief Create a boolean JSON value
 * @param ctx Arena context
 * @param value Boolean value
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_bool(agent_context_t* ctx, bool value);

/**
 * @brief Create an integer JSON value
 * @param ctx Arena context
 * @param value Integer value
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_int(agent_context_t* ctx, int64_t value);

/**
 * @brief Create a double JSON value
 * @param ctx Arena context
 * @param value Double value
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_double(agent_context_t* ctx, double value);

/**
 * @brief Create a string JSON value
 * @param ctx Arena context
 * @param str String value (will be copied to arena)
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_string(agent_context_t* ctx, const char* str);

/**
 * @brief Create a string JSON value with length
 * @param ctx Arena context
 * @param str String value
 * @param len String length
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_string_n(agent_context_t* ctx, const char* str, size_t len);

/**
 * @brief Create an empty array JSON value
 * @param ctx Arena context
 * @param initial_capacity Initial array capacity
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_array(agent_context_t* ctx, size_t initial_capacity);

/**
 * @brief Create an empty object JSON value
 * @param ctx Arena context
 * @param initial_capacity Initial object capacity
 * @return JSON value or NULL on error
 */
agent_json_value_t* agent_json_object(agent_context_t* ctx, size_t initial_capacity);

/* Array operations */

/**
 * @brief Append a value to a JSON array
 * @param ctx Arena context
 * @param array Array to append to
 * @param value Value to append
 * @return AGENT_OK on success
 */
agent_error_t agent_json_array_append(agent_context_t* ctx, agent_json_value_t* array,
                                      agent_json_value_t* value);

/**
 * @brief Get array length
 * @param array JSON array
 * @return Number of elements, or 0 if not an array
 */
size_t agent_json_array_length(const agent_json_value_t* array);

/**
 * @brief Get array element by index
 * @param array JSON array
 * @param index Element index
 * @return Element value or NULL if out of bounds
 */
agent_json_value_t* agent_json_array_get(const agent_json_value_t* array, size_t index);

/* Object operations */

/**
 * @brief Set a key-value pair in a JSON object
 * @param ctx Arena context
 * @param object Object to modify
 * @param key Key string
 * @param value Value to set
 * @return AGENT_OK on success
 */
agent_error_t agent_json_object_set(agent_context_t* ctx, agent_json_value_t* object,
                                    const char* key, agent_json_value_t* value);

/**
 * @brief Set a key-value pair with key length
 * @param ctx Arena context
 * @param object Object to modify
 * @param key Key string
 * @param key_len Key length
 * @param value Value to set
 * @return AGENT_OK on success
 */
agent_error_t agent_json_object_set_n(agent_context_t* ctx, agent_json_value_t* object,
                                      const char* key, size_t key_len, agent_json_value_t* value);

/**
 * @brief Get value by key
 * @param object JSON object
 * @param key Key string
 * @return Value or NULL if not found
 */
agent_json_value_t* agent_json_object_get(const agent_json_value_t* object, const char* key);

/**
 * @brief Get value by key with length
 * @param object JSON object
 * @param key Key string
 * @param key_len Key length
 * @return Value or NULL if not found
 */
agent_json_value_t* agent_json_object_get_n(const agent_json_value_t* object,
                                            const char* key, size_t key_len);

/**
 * @brief Check if object has key
 * @param object JSON object
 * @param key Key string
 * @return true if key exists
 */
bool agent_json_object_has(const agent_json_value_t* object, const char* key);

/**
 * @brief Get number of entries in object
 * @param object JSON object
 * @return Number of entries
 */
size_t agent_json_object_length(const agent_json_value_t* object);

/* Type accessors */

/**
 * @brief Get JSON value type
 * @param value JSON value
 * @return Value type
 */
agent_json_type_t agent_json_get_type(const agent_json_value_t* value);

/**
 * @brief Get boolean value
 * @param value JSON value
 * @param out_value Output boolean
 * @return AGENT_OK if value is a boolean
 */
agent_error_t agent_json_get_bool(const agent_json_value_t* value, bool* out_value);

/**
 * @brief Get integer value
 * @param value JSON value
 * @param out_value Output integer
 * @return AGENT_OK if value is an integer
 */
agent_error_t agent_json_get_int(const agent_json_value_t* value, int64_t* out_value);

/**
 * @brief Get double value
 * @param value JSON value
 * @param out_value Output double
 * @return AGENT_OK if value is numeric
 */
agent_error_t agent_json_get_double(const agent_json_value_t* value, double* out_value);

/**
 * @brief Get string value
 * @param value JSON value
 * @param out_value Output string view
 * @return AGENT_OK if value is a string
 */
agent_error_t agent_json_get_string(const agent_json_value_t* value, agent_string_view_t* out_value);

/* Parsing */

/**
 * @brief Parse result
 */
typedef struct {
    agent_json_value_t* value;
    agent_error_t error;
    const char* error_message;
    size_t error_position;
} agent_json_parse_result_t;

/**
 * @brief Parse JSON string
 * @param ctx Arena context for allocations
 * @param json JSON string
 * @param length JSON string length
 * @return Parse result
 */
agent_json_parse_result_t agent_json_parse(agent_context_t* ctx, const char* json, size_t length);

/**
 * @brief Parse JSON from C string
 * @param ctx Arena context
 * @param json Null-terminated JSON string
 * @return Parse result
 */
agent_json_parse_result_t agent_json_parse_cstr(agent_context_t* ctx, const char* json);

/* Serialization */

/**
 * @brief Serialize JSON value to string
 * @param value JSON value
 * @param str Output string (must be initialized)
 * @param pretty Pretty-print with indentation
 * @return AGENT_OK on success
 */
agent_error_t agent_json_serialize(const agent_json_value_t* value, agent_string_t* str, bool pretty);

/**
 * @brief Serialize JSON value to arena string
 * @param ctx Arena context
 * @param value JSON value
 * @param pretty Pretty-print
 * @return Serialized string or NULL on error
 */
char* agent_json_to_string(agent_context_t* ctx, const agent_json_value_t* value, bool pretty);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_JSON_H */
