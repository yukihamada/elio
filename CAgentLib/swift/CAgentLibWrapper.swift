/**
 * CAgentLibWrapper.swift
 * Swift wrapper for the C Agent Library
 *
 * Provides a Swift-friendly interface to the C library.
 */

import Foundation

// MARK: - Error Types

public enum AgentError: Error, LocalizedError {
    case invalidArgument
    case outOfMemory
    case parseError(String?)
    case invalidUTF8
    case bufferTooSmall
    case notFound
    case maxIterations
    case callbackFailed
    case cancelled
    case unknown(Int32)

    init(from error: agent_error_t) {
        switch error {
        case AGENT_OK:
            self = .invalidArgument  // shouldn't happen
        case AGENT_ERROR_INVALID_ARGUMENT:
            self = .invalidArgument
        case AGENT_ERROR_OUT_OF_MEMORY:
            self = .outOfMemory
        case AGENT_ERROR_PARSE_ERROR:
            self = .parseError(nil)
        case AGENT_ERROR_INVALID_UTF8:
            self = .invalidUTF8
        case AGENT_ERROR_BUFFER_TOO_SMALL:
            self = .bufferTooSmall
        case AGENT_ERROR_NOT_FOUND:
            self = .notFound
        case AGENT_ERROR_MAX_ITERATIONS:
            self = .maxIterations
        case AGENT_ERROR_CALLBACK_FAILED:
            self = .callbackFailed
        case AGENT_ERROR_CANCELLED:
            self = .cancelled
        default:
            self = .unknown(error.rawValue)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidArgument: return "Invalid argument"
        case .outOfMemory: return "Out of memory"
        case .parseError(let msg): return msg ?? "Parse error"
        case .invalidUTF8: return "Invalid UTF-8"
        case .bufferTooSmall: return "Buffer too small"
        case .notFound: return "Not found"
        case .maxIterations: return "Maximum iterations reached"
        case .callbackFailed: return "Callback failed"
        case .cancelled: return "Cancelled"
        case .unknown(let code): return "Unknown error: \(code)"
        }
    }
}

// MARK: - String View Extension

extension agent_string_view_t {
    var string: String? {
        guard let data = self.data, self.length > 0 else { return nil }
        return String(cString: data)
    }

    var stringValue: String {
        return string ?? ""
    }
}

// MARK: - JSON Value Wrapper

public class CJSONValue {
    let ptr: UnsafeMutablePointer<agent_json_value_t>
    private let ownsMemory: Bool

    init(_ ptr: UnsafeMutablePointer<agent_json_value_t>, ownsMemory: Bool = false) {
        self.ptr = ptr
        self.ownsMemory = ownsMemory
    }

    var type: agent_json_type_t {
        return ptr.pointee.type
    }

    var isNull: Bool { type == AGENT_JSON_NULL }
    var isBool: Bool { type == AGENT_JSON_BOOL }
    var isInt: Bool { type == AGENT_JSON_INT }
    var isDouble: Bool { type == AGENT_JSON_DOUBLE }
    var isString: Bool { type == AGENT_JSON_STRING }
    var isArray: Bool { type == AGENT_JSON_ARRAY }
    var isObject: Bool { type == AGENT_JSON_OBJECT }

    var boolValue: Bool? {
        guard isBool else { return nil }
        return ptr.pointee.data.bool_value
    }

    var intValue: Int64? {
        guard isInt else { return nil }
        return ptr.pointee.data.int_value
    }

    var doubleValue: Double? {
        if isDouble { return ptr.pointee.data.double_value }
        if isInt { return Double(ptr.pointee.data.int_value) }
        return nil
    }

    var stringValue: String? {
        guard isString else { return nil }
        return ptr.pointee.data.string_value.string
    }

    var arrayCount: Int {
        guard isArray else { return 0 }
        return Int(ptr.pointee.data.array_value.count)
    }

    subscript(index: Int) -> CJSONValue? {
        guard isArray, index >= 0, index < arrayCount else { return nil }
        guard let item = ptr.pointee.data.array_value.items[index] else { return nil }
        return CJSONValue(item)
    }

    var objectKeys: [String] {
        guard isObject else { return [] }
        var keys: [String] = []
        let count = Int(ptr.pointee.data.object_value.count)
        for i in 0..<count {
            let entry = ptr.pointee.data.object_value.entries[i]
            if let key = entry.key.string {
                keys.append(key)
            }
        }
        return keys
    }

    subscript(key: String) -> CJSONValue? {
        guard isObject else { return nil }
        guard let value = agent_json_object_get(ptr, key) else { return nil }
        return CJSONValue(value)
    }

    /// Convert to Swift Any type
    func toAny() -> Any {
        switch type {
        case AGENT_JSON_NULL:
            return NSNull()
        case AGENT_JSON_BOOL:
            return boolValue ?? false
        case AGENT_JSON_INT:
            return intValue ?? 0
        case AGENT_JSON_DOUBLE:
            return doubleValue ?? 0.0
        case AGENT_JSON_STRING:
            return stringValue ?? ""
        case AGENT_JSON_ARRAY:
            var arr: [Any] = []
            for i in 0..<arrayCount {
                if let item = self[i] {
                    arr.append(item.toAny())
                }
            }
            return arr
        case AGENT_JSON_OBJECT:
            var dict: [String: Any] = [:]
            for key in objectKeys {
                if let value = self[key] {
                    dict[key] = value.toAny()
                }
            }
            return dict
        default:
            return NSNull()
        }
    }
}

// MARK: - Agent Context Wrapper

public class CAgentContext {
    let ctx: OpaquePointer

    public init(initialSize: Int = 0) throws {
        guard let context = agent_context_create(initialSize) else {
            throw AgentError.outOfMemory
        }
        self.ctx = context
    }

    deinit {
        agent_context_destroy(ctx)
    }

    public func reset() {
        agent_context_reset(ctx)
    }

    public var used: Int {
        return agent_context_used(ctx)
    }

    public var capacity: Int {
        return agent_context_capacity(ctx)
    }
}

// MARK: - Agent State Wrapper

public class CAgentState {
    private var state: agent_state_t
    private var context: CAgentContext?

    // Callback closures (stored to prevent deallocation)
    private var generateCallback: ((UnsafePointer<agent_message_t>?, Int, String?, @escaping (String) -> Bool) -> (agent_error_t, String))?
    private var executeToolCallback: ((String, CJSONValue?) -> (agent_error_t, String, Bool))?
    private var tokenCallback: ((String) -> Bool)?
    private var toolCallNotifyCallback: ((String) -> Void)?
    private var stepChangeCallback: ((agent_step_t, String?) -> Void)?
    private var toolsSchemaCallback: (() -> String)?

    // User data for callbacks
    private var userData: UnsafeMutableRawPointer?

    public init() {
        state = agent_state_t()
    }

    deinit {
        agent_free(&state)
    }

    /// Configure the agent with callbacks
    public func configure(
        generate: @escaping ([Message], String?) -> AsyncStream<String>,
        executeTool: @escaping (String, [String: Any]) async -> (String, Bool),
        onToken: ((String) -> Bool)? = nil,
        onToolCall: ((String) -> Void)? = nil,
        onStepChange: ((AgentStep) -> Void)? = nil,
        getToolsSchema: @escaping () -> String,
        maxIterations: Int = 10,
        useJapanese: Bool = true,
        customSystemPrompt: String? = nil
    ) throws {
        // Store Swift callbacks
        self.tokenCallback = onToken
        self.toolCallNotifyCallback = onToolCall
        self.toolsSchemaCallback = getToolsSchema

        // Convert step callback
        if let stepChange = onStepChange {
            self.stepChangeCallback = { step, toolName in
                let swiftStep: AgentStep
                switch step {
                case AGENT_STEP_NONE: swiftStep = .none
                case AGENT_STEP_THINKING: swiftStep = .thinking
                case AGENT_STEP_CALLING_TOOL: swiftStep = .callingTool(toolName ?? "")
                case AGENT_STEP_WAITING_FOR_RESULT: swiftStep = .waitingForResult
                case AGENT_STEP_GENERATING: swiftStep = .generating
                default: swiftStep = .none
                }
                stepChange(swiftStep)
            }
        }

        // Create configuration
        // Note: The actual C callbacks need to be set up differently
        // This is a simplified example - real implementation would need
        // proper C function pointers and context passing

        var config = agent_config_t()
        config.max_iterations = Int32(maxIterations)
        config.use_japanese = useJapanese

        // For a real implementation, you would need to:
        // 1. Create C function pointer wrappers
        // 2. Store callback context in user_data
        // 3. Handle the async nature of Swift callbacks

        let result = agent_init(&state, &config)
        guard result == AGENT_OK else {
            throw AgentError(from: result)
        }
    }

    public func reset() {
        agent_reset(&state)
    }

    public func addUserMessage(_ content: String) throws {
        let result = agent_add_user_message(&state, content)
        guard result == AGENT_OK else {
            throw AgentError(from: result)
        }
    }

    public func addUserMessage(_ content: String, imageData: Data) throws {
        let result = imageData.withUnsafeBytes { bytes in
            agent_add_user_message_with_image(
                &state,
                content,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count
            )
        }
        guard result == AGENT_OK else {
            throw AgentError(from: result)
        }
    }

    public func stop() {
        agent_stop(&state)
    }

    public var isProcessing: Bool {
        return agent_is_processing(&state)
    }

    public var currentStep: AgentStep {
        let step = agent_current_step(&state)
        switch step {
        case AGENT_STEP_NONE: return .none
        case AGENT_STEP_THINKING: return .thinking
        case AGENT_STEP_CALLING_TOOL: return .callingTool("")
        case AGENT_STEP_WAITING_FOR_RESULT: return .waitingForResult
        case AGENT_STEP_GENERATING: return .generating
        default: return .none
        }
    }
}

// MARK: - Swift Types

public enum AgentStep {
    case none
    case thinking
    case callingTool(String)
    case waitingForResult
    case generating
}

public struct Message {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public var toolCalls: [ToolCall]?
    public var toolResults: [ToolResult]?
    public var thinkingContent: String?
    public var imageData: Data?

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        thinkingContent: String? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.thinkingContent = thinkingContent
        self.imageData = imageData
    }
}

public enum MessageRole {
    case user
    case assistant
    case system
    case tool
}

public struct ToolCall {
    public let id: UUID
    public let name: String
    public let arguments: [String: Any]

    public init(id: UUID = UUID(), name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolResult {
    public let id: UUID
    public let toolCallId: UUID
    public let content: String
    public let isError: Bool

    public init(id: UUID = UUID(), toolCallId: UUID, content: String, isError: Bool = false) {
        self.id = id
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

// MARK: - JSON Parsing Utility

public struct CJSONParser {
    public static func parse(_ json: String, using context: CAgentContext) throws -> CJSONValue {
        let result = json.withCString { cstr in
            agent_json_parse_cstr(context.ctx, cstr)
        }

        guard result.error == AGENT_OK, let value = result.value else {
            throw AgentError.parseError(result.error_message.map { String(cString: $0) })
        }

        return CJSONValue(value)
    }

    public static func serialize(_ value: CJSONValue, using context: CAgentContext, pretty: Bool = false) -> String? {
        guard let str = agent_json_to_string(context.ctx, value.ptr, pretty) else {
            return nil
        }
        return String(cString: str)
    }
}

// MARK: - Response Parser Utility

public struct CResponseParser {
    public static func hasToolCall(in response: String) -> Bool {
        return response.withCString { cstr in
            agent_parser_has_tool_call(cstr, strlen(cstr))
        }
    }

    public static func hasIncompleteToolCall(in response: String) -> Bool {
        return response.withCString { cstr in
            agent_parser_has_incomplete_tool_call(cstr, strlen(cstr))
        }
    }

    public static func textBeforeToolCall(in response: String, using context: CAgentContext) -> String {
        return response.withCString { cstr in
            let sv = agent_parser_text_before_tool_call(context.ctx, cstr, strlen(cstr))
            return sv.stringValue
        }
    }
}

// MARK: - Library Initialization

public func initializeAgentLib() throws {
    let result = agent_lib_init()
    guard result == AGENT_OK else {
        throw AgentError(from: result)
    }
}

public func cleanupAgentLib() {
    agent_lib_cleanup()
}

public func agentLibVersion() -> String {
    return String(cString: agent_lib_version())
}
