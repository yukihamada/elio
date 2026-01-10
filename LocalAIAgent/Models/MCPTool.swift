import Foundation

struct MCPTool: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let inputSchema: MCPInputSchema

    init(name: String, description: String, inputSchema: MCPInputSchema) {
        self.id = name
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

struct MCPInputSchema: Codable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?

    init(
        type: String = "object",
        properties: [String: MCPPropertySchema]? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

final class MCPPropertySchema: Codable {
    let type: String
    let description: String?
    let enumValues: [String]?
    let items: MCPPropertySchema?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case items
    }

    init(
        type: String,
        description: String? = nil,
        enumValues: [String]? = nil,
        items: MCPPropertySchema? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
}

struct MCPServerInfo: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    var isEnabled: Bool
    let tools: [MCPTool]

    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        isEnabled: Bool = true,
        tools: [MCPTool]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.isEnabled = isEnabled
        self.tools = tools
    }
}
