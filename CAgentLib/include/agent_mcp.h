/**
 * @file agent_mcp.h
 * @brief MCP (Model Context Protocol) schema generation
 */

#ifndef AGENT_MCP_H
#define AGENT_MCP_H

#include "agent_types.h"
#include "agent_context.h"
#include "agent_json.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Property schema type
 */
typedef enum {
    AGENT_SCHEMA_STRING = 0,
    AGENT_SCHEMA_INTEGER = 1,
    AGENT_SCHEMA_NUMBER = 2,
    AGENT_SCHEMA_BOOLEAN = 3,
    AGENT_SCHEMA_ARRAY = 4,
    AGENT_SCHEMA_OBJECT = 5
} agent_schema_type_t;

/**
 * @brief Property schema definition
 */
typedef struct agent_property_schema_t {
    const char* name;
    agent_schema_type_t type;
    const char* description;
    bool required;

    /* For enum types */
    const char** enum_values;
    size_t enum_count;

    /* For array types */
    struct agent_property_schema_t* items_schema;

    /* For object types */
    struct agent_property_schema_t* properties;
    size_t properties_count;
} agent_property_schema_t;

/**
 * @brief Tool definition
 */
typedef struct {
    const char* name;           /* Full tool name (e.g., "filesystem.read_file") */
    const char* description;
    agent_property_schema_t* parameters;
    size_t parameters_count;
} agent_tool_definition_t;

/**
 * @brief Tool registry
 */
typedef struct {
    agent_tool_definition_t* tools;
    size_t count;
    size_t capacity;
} agent_tool_registry_t;

/**
 * @brief Initialize tool registry
 * @param registry Registry to initialize
 * @param initial_capacity Initial capacity
 * @return AGENT_OK on success
 */
agent_error_t agent_tool_registry_init(agent_tool_registry_t* registry, size_t initial_capacity);

/**
 * @brief Free tool registry
 * @param registry Registry to free
 */
void agent_tool_registry_free(agent_tool_registry_t* registry);

/**
 * @brief Register a tool
 * @param registry Registry
 * @param tool Tool definition
 * @return AGENT_OK on success
 */
agent_error_t agent_tool_registry_add(agent_tool_registry_t* registry,
                                      const agent_tool_definition_t* tool);

/**
 * @brief Find tool by name
 * @param registry Registry
 * @param name Tool name
 * @return Tool definition or NULL if not found
 */
const agent_tool_definition_t* agent_tool_registry_find(const agent_tool_registry_t* registry,
                                                        const char* name);

/* Schema generation */

/**
 * @brief Generate JSON schema for a property
 * @param ctx Arena context
 * @param prop Property schema
 * @return JSON value representing the schema
 */
agent_json_value_t* agent_mcp_property_to_json(agent_context_t* ctx,
                                               const agent_property_schema_t* prop);

/**
 * @brief Generate JSON schema for a tool
 * @param ctx Arena context
 * @param tool Tool definition
 * @return JSON object in OpenAI function calling format
 */
agent_json_value_t* agent_mcp_tool_to_json(agent_context_t* ctx,
                                           const agent_tool_definition_t* tool);

/**
 * @brief Generate JSON schema for all tools in registry
 * @param ctx Arena context
 * @param registry Tool registry
 * @return JSON array of tool schemas
 */
agent_json_value_t* agent_mcp_registry_to_json(agent_context_t* ctx,
                                               const agent_tool_registry_t* registry);

/**
 * @brief Generate tools schema JSON string
 * @param ctx Arena context
 * @param registry Tool registry
 * @param pretty Pretty print
 * @return JSON string (arena-allocated)
 */
char* agent_mcp_get_schema_json(agent_context_t* ctx,
                                const agent_tool_registry_t* registry,
                                bool pretty);

/* Helper functions for building tool definitions */

/**
 * @brief Create a string property schema
 * @param name Property name
 * @param description Description
 * @param required Is required
 * @return Property schema (stack-allocated, copy if needed)
 */
agent_property_schema_t agent_mcp_string_property(const char* name,
                                                  const char* description,
                                                  bool required);

/**
 * @brief Create an integer property schema
 */
agent_property_schema_t agent_mcp_int_property(const char* name,
                                               const char* description,
                                               bool required);

/**
 * @brief Create a number property schema
 */
agent_property_schema_t agent_mcp_number_property(const char* name,
                                                  const char* description,
                                                  bool required);

/**
 * @brief Create a boolean property schema
 */
agent_property_schema_t agent_mcp_bool_property(const char* name,
                                                const char* description,
                                                bool required);

/**
 * @brief Create an enum property schema
 * @param name Property name
 * @param description Description
 * @param required Is required
 * @param values Array of enum values
 * @param count Number of values
 * @return Property schema
 */
agent_property_schema_t agent_mcp_enum_property(const char* name,
                                                const char* description,
                                                bool required,
                                                const char** values,
                                                size_t count);

/**
 * @brief Create an array property schema
 * @param name Property name
 * @param description Description
 * @param required Is required
 * @param items_schema Schema for array items
 * @return Property schema
 */
agent_property_schema_t agent_mcp_array_property(const char* name,
                                                 const char* description,
                                                 bool required,
                                                 agent_property_schema_t* items_schema);

/* Human-readable description generation */

/**
 * @brief Generate human-readable tool description
 * @param ctx Arena context
 * @param tool Tool definition
 * @param japanese Use Japanese language
 * @return Description string
 */
char* agent_mcp_tool_description(agent_context_t* ctx,
                                 const agent_tool_definition_t* tool,
                                 bool japanese);

/**
 * @brief Generate human-readable description for all tools
 * @param ctx Arena context
 * @param registry Tool registry
 * @param japanese Use Japanese language
 * @return Description string
 */
char* agent_mcp_registry_description(agent_context_t* ctx,
                                     const agent_tool_registry_t* registry,
                                     bool japanese);

#ifdef __cplusplus
}
#endif

#endif /* AGENT_MCP_H */
