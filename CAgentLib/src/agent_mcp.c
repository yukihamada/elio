/**
 * @file agent_mcp.c
 * @brief MCP schema generation implementation
 */

#include "agent_mcp.h"
#include "agent_string.h"
#include <stdlib.h>
#include <string.h>

#define DEFAULT_REGISTRY_CAPACITY 16

/* Tool registry */

agent_error_t agent_tool_registry_init(agent_tool_registry_t* registry, size_t initial_capacity) {
    if (!registry) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    size_t capacity = initial_capacity > 0 ? initial_capacity : DEFAULT_REGISTRY_CAPACITY;
    registry->tools = (agent_tool_definition_t*)calloc(capacity, sizeof(agent_tool_definition_t));
    if (!registry->tools) {
        return AGENT_ERROR_OUT_OF_MEMORY;
    }

    registry->count = 0;
    registry->capacity = capacity;
    return AGENT_OK;
}

void agent_tool_registry_free(agent_tool_registry_t* registry) {
    if (!registry) return;

    free(registry->tools);
    registry->tools = NULL;
    registry->count = 0;
    registry->capacity = 0;
}

agent_error_t agent_tool_registry_add(agent_tool_registry_t* registry,
                                      const agent_tool_definition_t* tool) {
    if (!registry || !tool) {
        return AGENT_ERROR_INVALID_ARGUMENT;
    }

    /* Grow if needed */
    if (registry->count >= registry->capacity) {
        size_t new_capacity = registry->capacity * 2;
        agent_tool_definition_t* new_tools = (agent_tool_definition_t*)realloc(
            registry->tools, new_capacity * sizeof(agent_tool_definition_t));
        if (!new_tools) {
            return AGENT_ERROR_OUT_OF_MEMORY;
        }
        registry->tools = new_tools;
        registry->capacity = new_capacity;
    }

    registry->tools[registry->count++] = *tool;
    return AGENT_OK;
}

const agent_tool_definition_t* agent_tool_registry_find(const agent_tool_registry_t* registry,
                                                        const char* name) {
    if (!registry || !name) {
        return NULL;
    }

    for (size_t i = 0; i < registry->count; i++) {
        if (strcmp(registry->tools[i].name, name) == 0) {
            return &registry->tools[i];
        }
    }
    return NULL;
}

/* Helper to get type string */
static const char* schema_type_string(agent_schema_type_t type) {
    switch (type) {
        case AGENT_SCHEMA_STRING:  return "string";
        case AGENT_SCHEMA_INTEGER: return "integer";
        case AGENT_SCHEMA_NUMBER:  return "number";
        case AGENT_SCHEMA_BOOLEAN: return "boolean";
        case AGENT_SCHEMA_ARRAY:   return "array";
        case AGENT_SCHEMA_OBJECT:  return "object";
        default: return "string";
    }
}

/* Schema generation */

agent_json_value_t* agent_mcp_property_to_json(agent_context_t* ctx,
                                               const agent_property_schema_t* prop) {
    if (!ctx || !prop) {
        return NULL;
    }

    agent_json_value_t* obj = agent_json_object(ctx, 4);
    if (!obj) return NULL;

    /* Type */
    agent_json_object_set(ctx, obj, "type",
        agent_json_string(ctx, schema_type_string(prop->type)));

    /* Description */
    if (prop->description) {
        agent_json_object_set(ctx, obj, "description",
            agent_json_string(ctx, prop->description));
    }

    /* Enum values */
    if (prop->enum_values && prop->enum_count > 0) {
        agent_json_value_t* enum_arr = agent_json_array(ctx, prop->enum_count);
        for (size_t i = 0; i < prop->enum_count; i++) {
            agent_json_array_append(ctx, enum_arr, agent_json_string(ctx, prop->enum_values[i]));
        }
        agent_json_object_set(ctx, obj, "enum", enum_arr);
    }

    /* Array items */
    if (prop->type == AGENT_SCHEMA_ARRAY && prop->items_schema) {
        agent_json_value_t* items = agent_mcp_property_to_json(ctx, prop->items_schema);
        if (items) {
            agent_json_object_set(ctx, obj, "items", items);
        }
    }

    /* Nested object properties */
    if (prop->type == AGENT_SCHEMA_OBJECT && prop->properties && prop->properties_count > 0) {
        agent_json_value_t* props_obj = agent_json_object(ctx, prop->properties_count);
        agent_json_value_t* required_arr = agent_json_array(ctx, prop->properties_count);

        for (size_t i = 0; i < prop->properties_count; i++) {
            agent_property_schema_t* nested = &prop->properties[i];
            agent_json_value_t* nested_schema = agent_mcp_property_to_json(ctx, nested);
            if (nested_schema && nested->name) {
                agent_json_object_set(ctx, props_obj, nested->name, nested_schema);
                if (nested->required) {
                    agent_json_array_append(ctx, required_arr, agent_json_string(ctx, nested->name));
                }
            }
        }

        agent_json_object_set(ctx, obj, "properties", props_obj);
        if (agent_json_array_length(required_arr) > 0) {
            agent_json_object_set(ctx, obj, "required", required_arr);
        }
    }

    return obj;
}

agent_json_value_t* agent_mcp_tool_to_json(agent_context_t* ctx,
                                           const agent_tool_definition_t* tool) {
    if (!ctx || !tool) {
        return NULL;
    }

    /* OpenAI function calling format:
     * {
     *   "type": "function",
     *   "function": {
     *     "name": "...",
     *     "description": "...",
     *     "parameters": {
     *       "type": "object",
     *       "properties": {...},
     *       "required": [...]
     *     }
     *   }
     * }
     */

    agent_json_value_t* root = agent_json_object(ctx, 2);
    if (!root) return NULL;

    agent_json_object_set(ctx, root, "type", agent_json_string(ctx, "function"));

    agent_json_value_t* func = agent_json_object(ctx, 3);
    if (!func) return NULL;

    agent_json_object_set(ctx, func, "name", agent_json_string(ctx, tool->name));

    if (tool->description) {
        agent_json_object_set(ctx, func, "description", agent_json_string(ctx, tool->description));
    }

    /* Parameters */
    agent_json_value_t* params = agent_json_object(ctx, 3);
    agent_json_object_set(ctx, params, "type", agent_json_string(ctx, "object"));

    agent_json_value_t* properties = agent_json_object(ctx, tool->parameters_count);
    agent_json_value_t* required = agent_json_array(ctx, tool->parameters_count);

    for (size_t i = 0; i < tool->parameters_count; i++) {
        agent_property_schema_t* prop = &tool->parameters[i];
        agent_json_value_t* prop_schema = agent_mcp_property_to_json(ctx, prop);
        if (prop_schema && prop->name) {
            agent_json_object_set(ctx, properties, prop->name, prop_schema);
            if (prop->required) {
                agent_json_array_append(ctx, required, agent_json_string(ctx, prop->name));
            }
        }
    }

    agent_json_object_set(ctx, params, "properties", properties);
    if (agent_json_array_length(required) > 0) {
        agent_json_object_set(ctx, params, "required", required);
    }

    agent_json_object_set(ctx, func, "parameters", params);
    agent_json_object_set(ctx, root, "function", func);

    return root;
}

agent_json_value_t* agent_mcp_registry_to_json(agent_context_t* ctx,
                                               const agent_tool_registry_t* registry) {
    if (!ctx || !registry) {
        return agent_json_array(ctx, 0);
    }

    agent_json_value_t* arr = agent_json_array(ctx, registry->count);
    if (!arr) return NULL;

    for (size_t i = 0; i < registry->count; i++) {
        agent_json_value_t* tool_json = agent_mcp_tool_to_json(ctx, &registry->tools[i]);
        if (tool_json) {
            agent_json_array_append(ctx, arr, tool_json);
        }
    }

    return arr;
}

char* agent_mcp_get_schema_json(agent_context_t* ctx,
                                const agent_tool_registry_t* registry,
                                bool pretty) {
    if (!ctx) {
        return NULL;
    }

    agent_json_value_t* json = agent_mcp_registry_to_json(ctx, registry);
    if (!json) {
        return agent_context_strdup(ctx, "[]");
    }

    return agent_json_to_string(ctx, json, pretty);
}

/* Property schema helpers */

agent_property_schema_t agent_mcp_string_property(const char* name,
                                                  const char* description,
                                                  bool required) {
    agent_property_schema_t prop = {0};
    prop.name = name;
    prop.type = AGENT_SCHEMA_STRING;
    prop.description = description;
    prop.required = required;
    return prop;
}

agent_property_schema_t agent_mcp_int_property(const char* name,
                                               const char* description,
                                               bool required) {
    agent_property_schema_t prop = {0};
    prop.name = name;
    prop.type = AGENT_SCHEMA_INTEGER;
    prop.description = description;
    prop.required = required;
    return prop;
}

agent_property_schema_t agent_mcp_number_property(const char* name,
                                                  const char* description,
                                                  bool required) {
    agent_property_schema_t prop = {0};
    prop.name = name;
    prop.type = AGENT_SCHEMA_NUMBER;
    prop.description = description;
    prop.required = required;
    return prop;
}

agent_property_schema_t agent_mcp_bool_property(const char* name,
                                                const char* description,
                                                bool required) {
    agent_property_schema_t prop = {0};
    prop.name = name;
    prop.type = AGENT_SCHEMA_BOOLEAN;
    prop.description = description;
    prop.required = required;
    return prop;
}

agent_property_schema_t agent_mcp_enum_property(const char* name,
                                                const char* description,
                                                bool required,
                                                const char** values,
                                                size_t count) {
    agent_property_schema_t prop = {0};
    prop.name = name;
    prop.type = AGENT_SCHEMA_STRING;
    prop.description = description;
    prop.required = required;
    prop.enum_values = values;
    prop.enum_count = count;
    return prop;
}

agent_property_schema_t agent_mcp_array_property(const char* name,
                                                 const char* description,
                                                 bool required,
                                                 agent_property_schema_t* items_schema) {
    agent_property_schema_t prop = {0};
    prop.name = name;
    prop.type = AGENT_SCHEMA_ARRAY;
    prop.description = description;
    prop.required = required;
    prop.items_schema = items_schema;
    return prop;
}

/* Human-readable description */

char* agent_mcp_tool_description(agent_context_t* ctx,
                                 const agent_tool_definition_t* tool,
                                 bool japanese) {
    if (!ctx || !tool) {
        return NULL;
    }

    agent_string_t str;
    if (agent_string_init(&str, 512) != AGENT_OK) {
        return NULL;
    }

    /* Tool name and description */
    agent_string_append_fmt(&str, "### %s\n", tool->name);
    if (tool->description) {
        agent_string_append_fmt(&str, "%s\n\n", tool->description);
    }

    /* Parameters */
    if (tool->parameters_count > 0) {
        if (japanese) {
            agent_string_append(&str, "**パラメータ:**\n");
        } else {
            agent_string_append(&str, "**Parameters:**\n");
        }

        for (size_t i = 0; i < tool->parameters_count; i++) {
            agent_property_schema_t* prop = &tool->parameters[i];
            const char* type_str = schema_type_string(prop->type);

            agent_string_append_fmt(&str, "- `%s` (%s)", prop->name, type_str);

            if (prop->required) {
                if (japanese) {
                    agent_string_append(&str, " *必須*");
                } else {
                    agent_string_append(&str, " *required*");
                }
            }

            if (prop->description) {
                agent_string_append_fmt(&str, ": %s", prop->description);
            }

            if (prop->enum_values && prop->enum_count > 0) {
                agent_string_append(&str, " [");
                for (size_t j = 0; j < prop->enum_count; j++) {
                    if (j > 0) agent_string_append(&str, ", ");
                    agent_string_append_fmt(&str, "\"%s\"", prop->enum_values[j]);
                }
                agent_string_append(&str, "]");
            }

            agent_string_append(&str, "\n");
        }
    }

    char* result = agent_context_strdup(ctx, str.data);
    agent_string_free(&str);
    return result;
}

char* agent_mcp_registry_description(agent_context_t* ctx,
                                     const agent_tool_registry_t* registry,
                                     bool japanese) {
    if (!ctx || !registry) {
        return NULL;
    }

    agent_string_t str;
    if (agent_string_init(&str, 2048) != AGENT_OK) {
        return NULL;
    }

    if (japanese) {
        agent_string_append(&str, "# 利用可能なツール\n\n");
    } else {
        agent_string_append(&str, "# Available Tools\n\n");
    }

    for (size_t i = 0; i < registry->count; i++) {
        char* tool_desc = agent_mcp_tool_description(ctx, &registry->tools[i], japanese);
        if (tool_desc) {
            agent_string_append(&str, tool_desc);
            agent_string_append(&str, "\n");
        }
    }

    char* result = agent_context_strdup(ctx, str.data);
    agent_string_free(&str);
    return result;
}
