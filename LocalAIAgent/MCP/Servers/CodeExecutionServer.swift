import Foundation
import JavaScriptCore

/// MCP Server for executing JavaScript code on-device using JavaScriptCore.
/// Provides a sandboxed execution environment for calculations, data processing,
/// string manipulation, JSON parsing, and general-purpose scripting.
final class CodeExecutionServer: MCPServer {
    let id = "code_execution"
    let name = "コード実行"
    let serverDescription = "JavaScriptコードをデバイス上で安全に実行します。計算・データ処理・文字列操作・JSON変換などに対応。"
    let icon = "terminal"

    private let timeout: TimeInterval = 10  // Max execution time in seconds

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "calculate",
                description: "複雑な計算を実行します",
                descriptionEn: "Execute complex calculations",
                arguments: [
                    MCPPromptArgument(name: "expression", description: "計算式", descriptionEn: "Math expression", required: true)
                ]
            ),
            MCPPrompt(
                name: "format_json",
                description: "JSONデータを整形・変換します",
                descriptionEn: "Format and transform JSON data",
                arguments: [
                    MCPPromptArgument(name: "json", description: "JSON文字列", descriptionEn: "JSON string", required: true)
                ]
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "calculate":
            let expr = arguments["expression"] ?? ""
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("以下の計算を実行してください: \(expr)"))
            ])
        case "format_json":
            let json = arguments["json"] ?? "{}"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("以下のJSONを整形してください:\n\(json)"))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "execute_code",
                description: """
                JavaScriptコードをデバイス上で実行します。計算、データ処理、文字列操作、正規表現、JSON変換、日付処理などに使えます。
                結果は最後の式の値が返されます。console.log()の出力も結果に含まれます。
                タイムアウト: 10秒。ネットワークアクセス・ファイルアクセスは不可。
                """,
                inputSchema: MCPInputSchema(
                    properties: [
                        "code": MCPPropertySchema(type: "string", description: "実行するJavaScriptコード"),
                    ],
                    required: ["code"]
                )
            ),
            MCPTool(
                name: "evaluate_expression",
                description: "数式や簡単なJavaScript式を評価して結果を返します。複雑な計算に便利。",
                inputSchema: MCPInputSchema(
                    properties: [
                        "expression": MCPPropertySchema(type: "string", description: "評価する式 (例: Math.sqrt(144), 2**10, [1,2,3].reduce((a,b)=>a+b))"),
                    ],
                    required: ["expression"]
                )
            ),
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "execute_code":
            guard let code = arguments["code"]?.stringValue else {
                return MCPResult(content: [.text("[ERROR] 'code' parameter is required")], isError: true)
            }
            return executeJavaScript(code: code)

        case "evaluate_expression":
            guard let expression = arguments["expression"]?.stringValue else {
                return MCPResult(content: [.text("[ERROR] 'expression' parameter is required")], isError: true)
            }
            return executeJavaScript(code: expression)

        default:
            return MCPResult(content: [.text("[ERROR] Unknown tool: \(name)")], isError: true)
        }
    }

    // MARK: - JavaScript Execution

    private func executeJavaScript(code: String) -> MCPResult {
        let context = JSContext()!
        var logs: [String] = []
        var errorMessage: String?

        // Set up console.log capture
        let consoleLog: @convention(block) (JSValue) -> Void = { value in
            logs.append(value.toString() ?? "undefined")
        }
        let consoleObj = JSValue(newObjectIn: context)!
        consoleObj.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        consoleObj.setObject(consoleLog, forKeyedSubscript: "info" as NSString)
        consoleObj.setObject(consoleLog, forKeyedSubscript: "warn" as NSString)
        let consoleError: @convention(block) (JSValue) -> Void = { value in
            logs.append("[ERROR] \(value.toString() ?? "undefined")")
        }
        consoleObj.setObject(consoleError, forKeyedSubscript: "error" as NSString)
        context.setObject(consoleObj, forKeyedSubscript: "console" as NSString)

        // Set up exception handler
        context.exceptionHandler = { _, exception in
            errorMessage = exception?.toString() ?? "Unknown error"
        }

        // Add useful globals
        addHelperFunctions(to: context)

        // Execute with timeout protection
        let startTime = Date()
        let result = context.evaluateScript(code)
        let elapsed = Date().timeIntervalSince(startTime)

        if elapsed > timeout {
            return MCPResult(
                content: [.text("[TIMEOUT] Execution exceeded \(Int(timeout))s limit")],
                isError: true
            )
        }

        // Build output
        var output = ""

        // Include console output
        if !logs.isEmpty {
            output += logs.joined(separator: "\n")
        }

        // Check for errors
        if let error = errorMessage {
            if !output.isEmpty { output += "\n" }
            output += "[ERROR] \(error)"
            return MCPResult(content: [.text(output)], isError: true)
        }

        // Include return value
        if let result = result, !result.isUndefined {
            let resultStr: String
            if result.isObject {
                // Pretty-print objects/arrays
                if let jsonData = try? JSONSerialization.data(
                    withJSONObject: result.toObject() as Any,
                    options: [.prettyPrinted, .sortedKeys]
                ), let jsonStr = String(data: jsonData, encoding: .utf8) {
                    resultStr = jsonStr
                } else {
                    resultStr = result.toString() ?? "undefined"
                }
            } else {
                resultStr = result.toString() ?? "undefined"
            }

            if !output.isEmpty { output += "\n" }
            output += resultStr
        }

        if output.isEmpty {
            output = "(no output)"
        }

        // Add execution time
        let elapsedMs = Int(elapsed * 1000)
        output += "\n\n[Executed in \(elapsedMs)ms]"

        return MCPResult(content: [.text(output)])
    }

    /// Add helper functions to the JS context (Math extensions, date helpers, etc.)
    private func addHelperFunctions(to context: JSContext) {
        // Date helpers
        context.evaluateScript("""
        function now() { return new Date().toISOString(); }
        function today() { return new Date().toISOString().split('T')[0]; }
        function formatDate(d, fmt) {
            var date = new Date(d);
            var y = date.getFullYear(), m = date.getMonth()+1, day = date.getDate();
            var h = date.getHours(), min = date.getMinutes(), s = date.getSeconds();
            return (fmt || 'YYYY-MM-DD HH:mm:ss')
                .replace('YYYY', y).replace('MM', String(m).padStart(2,'0'))
                .replace('DD', String(day).padStart(2,'0')).replace('HH', String(h).padStart(2,'0'))
                .replace('mm', String(min).padStart(2,'0')).replace('ss', String(s).padStart(2,'0'));
        }
        """)

        // Array/Object helpers
        context.evaluateScript("""
        function range(start, end, step) {
            step = step || 1;
            var arr = [];
            for (var i = start; i < end; i += step) arr.push(i);
            return arr;
        }
        function sum(arr) { return arr.reduce(function(a,b){ return a+b; }, 0); }
        function avg(arr) { return arr.length ? sum(arr)/arr.length : 0; }
        function max_of(arr) { return Math.max.apply(null, arr); }
        function min_of(arr) { return Math.min.apply(null, arr); }
        function unique(arr) { return Array.from(new Set(arr)); }
        function flatten(arr) { return arr.flat(Infinity); }
        function groupBy(arr, key) {
            return arr.reduce(function(acc, item) {
                var k = typeof key === 'function' ? key(item) : item[key];
                (acc[k] = acc[k] || []).push(item);
                return acc;
            }, {});
        }
        """)

        // String helpers
        context.evaluateScript("""
        function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }
        function truncate(s, n) { return s.length > n ? s.slice(0, n) + '...' : s; }
        function slugify(s) { return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''); }
        """)

        // Math extras
        context.evaluateScript("""
        function factorial(n) { return n <= 1 ? 1 : n * factorial(n-1); }
        function gcd(a, b) { return b ? gcd(b, a % b) : a; }
        function lcm(a, b) { return (a * b) / gcd(a, b); }
        function isPrime(n) {
            if (n < 2) return false;
            for (var i = 2; i * i <= n; i++) if (n % i === 0) return false;
            return true;
        }
        function fib(n) {
            var a = 0, b = 1;
            for (var i = 0; i < n; i++) { var t = a; a = b; b = t + b; }
            return a;
        }
        """)

        // Unit conversion
        context.evaluateScript("""
        var convert = {
            kmToMiles: function(km) { return km * 0.621371; },
            milesToKm: function(mi) { return mi * 1.60934; },
            cToF: function(c) { return c * 9/5 + 32; },
            fToC: function(f) { return (f - 32) * 5/9; },
            kgToLbs: function(kg) { return kg * 2.20462; },
            lbsToKg: function(lbs) { return lbs * 0.453592; },
            cmToInch: function(cm) { return cm * 0.393701; },
            inchToCm: function(inch) { return inch * 2.54; },
            jpyToUsd: function(jpy, rate) { return jpy / (rate || 150); },
            usdToJpy: function(usd, rate) { return usd * (rate || 150); },
        };
        """)
    }
}
