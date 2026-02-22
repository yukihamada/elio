import XCTest
@testable import LocalAIAgent

final class ToolParserTests: XCTestCase {

    // MARK: - Empty/Invalid Input Tests

    func testParseEmptyString() throws {
        let result = ToolParser.extractToolCalls(from: "")
        XCTAssertTrue(result.isEmpty, "Empty string should return no tool calls")
    }

    func testParseTextWithoutToolCall() throws {
        let text = "This is just regular text without any tool calls."
        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertTrue(result.isEmpty, "Text without tool calls should return empty array")
    }

    func testHasToolCallReturnsFalseForPlainText() throws {
        let text = "Hello, how can I help you today?"
        XCTAssertFalse(ToolParser.hasToolCall(in: text))
    }

    // MARK: - Single Tool Call Tests

    func testParseSingleToolCall() throws {
        let text = """
        Let me check the weather for you.
        <tool_call>
        {"name": "weather", "arguments": {"location": "Tokyo"}}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertEqual(result.count, 1, "Should find exactly one tool call")
        XCTAssertEqual(result.first?.name, "weather")
        XCTAssertEqual(result.first?.arguments["location"], .string("Tokyo"))
    }

    func testHasToolCallReturnsTrue() throws {
        let text = """
        <tool_call>
        {"name": "test", "arguments": {}}
        </tool_call>
        """
        XCTAssertTrue(ToolParser.hasToolCall(in: text))
    }

    // MARK: - Multiple Tool Calls Tests

    func testParseMultipleToolCalls() throws {
        let text = """
        <tool_call>
        {"name": "weather", "arguments": {"location": "Tokyo"}}
        </tool_call>
        And now checking another location.
        <tool_call>
        {"name": "weather", "arguments": {"location": "Osaka"}}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertEqual(result.count, 2, "Should find two tool calls")
        XCTAssertEqual(result[0].name, "weather")
        XCTAssertEqual(result[0].arguments["location"], .string("Tokyo"))
        XCTAssertEqual(result[1].name, "weather")
        XCTAssertEqual(result[1].arguments["location"], .string("Osaka"))
    }

    // MARK: - Invalid JSON Tests

    func testParseInvalidJSON() throws {
        let text = """
        <tool_call>
        {invalid json here}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertTrue(result.isEmpty, "Invalid JSON should not produce tool calls")
    }

    func testParseMissingName() throws {
        let text = """
        <tool_call>
        {"arguments": {"key": "value"}}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertTrue(result.isEmpty, "Tool call without name should be ignored")
    }

    // MARK: - Argument Types Tests

    func testParseVariousArgumentTypes() throws {
        let text = """
        <tool_call>
        {"name": "test", "arguments": {
            "stringArg": "hello",
            "intArg": 42,
            "doubleArg": 3.14,
            "boolArg": true,
            "nullArg": null
        }}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertEqual(result.count, 1)

        let args = result.first?.arguments
        XCTAssertEqual(args?["stringArg"], .string("hello"))
        XCTAssertEqual(args?["intArg"], .int(42))
        // Note: JSON booleans are decoded as integers by JSONValue
        XCTAssertEqual(args?["boolArg"], .int(1))
        XCTAssertEqual(args?["nullArg"], .null)
    }

    func testParseNestedArguments() throws {
        let text = """
        <tool_call>
        {"name": "search", "arguments": {
            "query": "test",
            "options": {"limit": 10, "sort": "date"}
        }}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "search")

        if case .object(let options) = result.first?.arguments["options"] {
            XCTAssertEqual(options["limit"], .int(10))
            XCTAssertEqual(options["sort"], .string("date"))
        } else {
            XCTFail("Expected nested object argument")
        }
    }

    func testParseArrayArgument() throws {
        let text = """
        <tool_call>
        {"name": "multi", "arguments": {"items": ["a", "b", "c"]}}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertEqual(result.count, 1)

        if case .array(let items) = result.first?.arguments["items"] {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0], .string("a"))
            XCTAssertEqual(items[1], .string("b"))
            XCTAssertEqual(items[2], .string("c"))
        } else {
            XCTFail("Expected array argument")
        }
    }

    // MARK: - Text Extraction Tests

    func testExtractTextBeforeToolCall() throws {
        let text = """
        Here is some text before the tool call.
        <tool_call>
        {"name": "test", "arguments": {}}
        </tool_call>
        """

        let before = ToolParser.extractTextBeforeToolCall(from: text)
        XCTAssertEqual(before, "Here is some text before the tool call.")
    }

    func testExtractTextAfterToolResult() throws {
        let text = """
        <tool_call>
        {"name": "test", "arguments": {}}
        </tool_call>
        And here is some text after.
        """

        let after = ToolParser.extractTextAfterToolResult(from: text)
        XCTAssertEqual(after, "And here is some text after.")
    }

    // MARK: - Incomplete Tool Call Tests

    func testHasIncompleteToolCall() throws {
        let text = """
        <tool_call>
        {"name": "weather", "arguments":
        """
        XCTAssertTrue(ToolParser.hasIncompleteToolCall(in: text))
    }

    func testCompleteToolCallNotIncomplete() throws {
        let text = """
        <tool_call>
        {"name": "test", "arguments": {}}
        </tool_call>
        """
        XCTAssertFalse(ToolParser.hasIncompleteToolCall(in: text))
    }

    // MARK: - Format Display Tests

    func testFormatToolCallForDisplay() throws {
        let toolCall = ToolParser.ParsedToolCall(
            name: "weather",
            arguments: ["location": .string("Tokyo"), "unit": .string("celsius")],
            rawJSON: "{}"
        )

        let display = ToolParser.formatToolCallForDisplay(toolCall)
        XCTAssertTrue(display.contains("weather"))
        XCTAssertTrue(display.contains("location"))
        XCTAssertTrue(display.contains("Tokyo"))
    }

    func testEmptyArguments() throws {
        let text = """
        <tool_call>
        {"name": "ping", "arguments": {}}
        </tool_call>
        """

        let result = ToolParser.extractToolCalls(from: text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "ping")
        XCTAssertTrue(result.first?.arguments.isEmpty ?? false)
    }
}
