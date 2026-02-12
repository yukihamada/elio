import Foundation

/// MCP Server for Emergency Knowledge Base - Offline emergency information
/// Provides first aid, disaster response, fact-checking, and emergency contacts
final class EmergencyKnowledgeBaseServer: MCPServer {
    let id = "emergency_kb"
    let name = "緊急ナレッジベース"
    let serverDescription = "災害時・緊急時の応急処置・避難・ファクトチェック情報を提供します"
    let icon = "cross.case"

    private var knowledgeBase: [String: Any] = [:]
    private let currentLocale: String

    init() {
        // Detect locale - default to Japanese
        let langCode = Locale.current.language.languageCode?.identifier ?? "ja"
        self.currentLocale = ["ja", "en"].contains(langCode) ? langCode : "en"
        loadKnowledgeBase()
    }

    private func loadKnowledgeBase() {
        guard let url = Bundle.main.url(forResource: "EmergencyKnowledgeBase", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locales = json["locales"] as? [String: Any] else {
            return
        }
        self.knowledgeBase = locales
    }

    private func localizedData() -> [String: Any] {
        return knowledgeBase[currentLocale] as? [String: Any] ?? knowledgeBase["en"] as? [String: Any] ?? [:]
    }

    // MARK: - Tools

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "search_emergency_kb",
                description: "緊急ナレッジベースをキーワードで検索します / Search the emergency knowledge base",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "検索キーワード / Search keyword"),
                        "category": MCPPropertySchema(
                            type: "string",
                            description: "カテゴリ (first_aid, disaster, infrastructure, fact_check, evacuation, contacts)",
                            enumValues: ["first_aid", "disaster", "infrastructure", "fact_check", "evacuation", "contacts"]
                        )
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "get_first_aid",
                description: "応急処置ガイドを取得します / Get first aid guide",
                inputSchema: MCPInputSchema(
                    properties: [
                        "condition": MCPPropertySchema(
                            type: "string",
                            description: "症状・状況 (cpr, bleeding, burns, fracture, aed, heatstroke, choking)",
                            enumValues: ["cpr", "bleeding", "burns", "fracture", "aed", "heatstroke", "choking"]
                        )
                    ],
                    required: ["condition"]
                )
            ),
            MCPTool(
                name: "get_disaster_guide",
                description: "災害対応ガイドを取得します / Get disaster response guide",
                inputSchema: MCPInputSchema(
                    properties: [
                        "disaster_type": MCPPropertySchema(
                            type: "string",
                            description: "災害の種類 (earthquake, tsunami, typhoon, flood, fire, landslide, volcano)",
                            enumValues: ["earthquake", "tsunami", "typhoon", "flood", "fire", "landslide", "volcano"]
                        )
                    ],
                    required: ["disaster_type"]
                )
            ),
            MCPTool(
                name: "get_fact_check_guide",
                description: "ファクトチェック手順を取得します / Get fact-checking guide",
                inputSchema: MCPInputSchema(
                    properties: [
                        "topic": MCPPropertySchema(
                            type: "string",
                            description: "トピック (identify_misinfo, deepfake, reliable_sources, before_sharing)",
                            enumValues: ["identify_misinfo", "deepfake", "reliable_sources", "before_sharing"]
                        )
                    ],
                    required: []
                )
            ),
            MCPTool(
                name: "get_emergency_contacts",
                description: "緊急連絡先一覧を取得します / Get emergency contact numbers",
                inputSchema: MCPInputSchema(
                    properties: nil,
                    required: nil
                )
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "search_emergency_kb":
            return searchKnowledgeBase(arguments: arguments)
        case "get_first_aid":
            return getFirstAid(arguments: arguments)
        case "get_disaster_guide":
            return getDisasterGuide(arguments: arguments)
        case "get_fact_check_guide":
            return getFactCheckGuide(arguments: arguments)
        case "get_emergency_contacts":
            return getEmergencyContacts()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    // MARK: - Prompts

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "first_aid_guide",
                description: "応急処置の方法を教えます",
                descriptionEn: "Get first aid instructions",
                arguments: [
                    MCPPromptArgument(name: "condition", description: "症状・怪我の種類", descriptionEn: "Type of injury or condition", required: true)
                ]
            ),
            MCPPrompt(
                name: "disaster_response",
                description: "災害への対応方法を教えます",
                descriptionEn: "Get disaster response instructions",
                arguments: [
                    MCPPromptArgument(name: "disaster", description: "災害の種類", descriptionEn: "Type of disaster", required: true)
                ]
            ),
            MCPPrompt(
                name: "fact_check",
                description: "情報の真偽確認の手順を教えます",
                descriptionEn: "Get fact-checking procedures",
                arguments: [
                    MCPPromptArgument(name: "info", description: "確認したい情報", descriptionEn: "Information to verify", required: true)
                ]
            ),
            MCPPrompt(
                name: "evacuation_checklist",
                description: "避難チェックリストを作成します",
                descriptionEn: "Create an evacuation checklist",
                arguments: [
                    MCPPromptArgument(name: "situation", description: "現在の状況", descriptionEn: "Current situation", required: true)
                ]
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        let isJapanese = currentLocale == "ja"

        switch name {
        case "first_aid_guide":
            let condition = arguments["condition"] ?? (isJapanese ? "怪我" : "injury")
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text(
                    isJapanese
                    ? "次の症状・怪我の応急処置方法を教えてください: \(condition)"
                    : "Please provide first aid instructions for: \(condition)"
                ))
            ])
        case "disaster_response":
            let disaster = arguments["disaster"] ?? (isJapanese ? "災害" : "disaster")
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text(
                    isJapanese
                    ? "次の災害が発生しました。対応手順を教えてください: \(disaster)"
                    : "The following disaster has occurred. Please provide response procedures: \(disaster)"
                ))
            ])
        case "fact_check":
            let info = arguments["info"] ?? ""
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text(
                    isJapanese
                    ? "次の情報の信頼性を確認してください。事実確認のポイントも教えてください: \(info)"
                    : "Please verify the reliability of this information and provide fact-checking tips: \(info)"
                ))
            ])
        case "evacuation_checklist":
            let situation = arguments["situation"] ?? (isJapanese ? "現在の状況" : "current situation")
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text(
                    isJapanese
                    ? "現在の状況に合った避難チェックリストを作成してください: \(situation)"
                    : "Please create an evacuation checklist for the current situation: \(situation)"
                ))
            ])
        default:
            return nil
        }
    }

    // MARK: - Tool Implementations

    private func searchKnowledgeBase(arguments: [String: JSONValue]) -> MCPResult {
        guard let query = arguments["query"]?.stringValue?.lowercased() else {
            return MCPResult(content: [.text("検索キーワードを指定してください / Please provide a search query")])
        }

        let data = localizedData()
        let categoryFilter = arguments["category"]?.stringValue
        var results: [String] = []

        for (categoryKey, categoryValue) in data {
            // Filter by category if specified
            if let filter = categoryFilter, categoryKey != filter { continue }

            guard let category = categoryValue as? [String: Any],
                  let categoryTitle = category["title"] as? String,
                  let items = category["items"] as? [String: Any] else { continue }

            for (_, itemValue) in items {
                guard let item = itemValue as? [String: Any],
                      let title = item["title"] as? String else { continue }

                // Search in title and steps/entries
                var matchFound = false
                var itemText = "## \(categoryTitle) > \(title)\n"

                if title.lowercased().contains(query) {
                    matchFound = true
                }

                if let steps = item["steps"] as? [String] {
                    let stepsText = steps.joined(separator: "\n")
                    if stepsText.lowercased().contains(query) {
                        matchFound = true
                    }
                    itemText += stepsText
                }

                if let entries = item["entries"] as? [[String: String]] {
                    let entriesText = entries.map { "\($0["number"] ?? ""): \($0["description"] ?? "")" }.joined(separator: "\n")
                    if entriesText.lowercased().contains(query) {
                        matchFound = true
                    }
                    itemText += entriesText
                }

                if matchFound {
                    results.append(itemText)
                }
            }
        }

        if results.isEmpty {
            let isJapanese = currentLocale == "ja"
            return MCPResult(content: [.text(
                isJapanese
                ? "「\(query)」に関する情報は見つかりませんでした。カテゴリを変えて検索してみてください。"
                : "No results found for '\(query)'. Try searching in a different category."
            )])
        }

        return MCPResult(content: [.text(results.joined(separator: "\n\n"))])
    }

    private func getFirstAid(arguments: [String: JSONValue]) -> MCPResult {
        guard let condition = arguments["condition"]?.stringValue else {
            return MCPResult(content: [.text("症状・状況を指定してください / Please specify a condition")])
        }

        return getItemFromCategory("first_aid", itemKey: condition)
    }

    private func getDisasterGuide(arguments: [String: JSONValue]) -> MCPResult {
        guard let disasterType = arguments["disaster_type"]?.stringValue else {
            return MCPResult(content: [.text("災害の種類を指定してください / Please specify a disaster type")])
        }

        return getItemFromCategory("disaster", itemKey: disasterType)
    }

    private func getFactCheckGuide(arguments: [String: JSONValue]) -> MCPResult {
        let topic = arguments["topic"]?.stringValue

        let data = localizedData()
        guard let factCheck = data["fact_check"] as? [String: Any],
              let categoryTitle = factCheck["title"] as? String,
              let items = factCheck["items"] as? [String: Any] else {
            return MCPResult(content: [.text("ファクトチェック情報を取得できませんでした")])
        }

        // If no topic specified, return all fact-check guides
        if let topic = topic {
            return getItemFromCategory("fact_check", itemKey: topic)
        }

        var result = "# \(categoryTitle)\n\n"
        for (_, itemValue) in items {
            guard let item = itemValue as? [String: Any],
                  let title = item["title"] as? String else { continue }

            result += "## \(title)\n"
            if let steps = item["steps"] as? [String] {
                result += steps.joined(separator: "\n") + "\n\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func getEmergencyContacts() -> MCPResult {
        let data = localizedData()
        guard let contacts = data["contacts"] as? [String: Any],
              let contactsTitle = contacts["title"] as? String,
              let items = contacts["items"] as? [String: Any],
              let emergencyNumbers = items["emergency_numbers"] as? [String: Any],
              let title = emergencyNumbers["title"] as? String,
              let entries = emergencyNumbers["entries"] as? [[String: String]] else {
            return MCPResult(content: [.text("緊急連絡先を取得できませんでした / Could not retrieve emergency contacts")])
        }

        var result = "# \(contactsTitle) - \(title)\n\n"
        for entry in entries {
            let number = entry["number"] ?? ""
            let desc = entry["description"] ?? ""
            result += "📞 **\(number)** — \(desc)\n"
        }

        return MCPResult(content: [.text(result)])
    }

    // MARK: - Helpers

    private func getItemFromCategory(_ categoryKey: String, itemKey: String) -> MCPResult {
        let data = localizedData()
        guard let category = data[categoryKey] as? [String: Any],
              let categoryTitle = category["title"] as? String,
              let items = category["items"] as? [String: Any],
              let item = items[itemKey] as? [String: Any],
              let title = item["title"] as? String else {
            let isJapanese = currentLocale == "ja"
            return MCPResult(content: [.text(
                isJapanese
                ? "「\(itemKey)」の情報が見つかりませんでした"
                : "Information for '\(itemKey)' was not found"
            )])
        }

        var result = "# \(categoryTitle) — \(title)\n\n"

        if let steps = item["steps"] as? [String] {
            result += steps.joined(separator: "\n")
        }

        if let entries = item["entries"] as? [[String: String]] {
            for entry in entries {
                let number = entry["number"] ?? ""
                let desc = entry["description"] ?? ""
                result += "📞 **\(number)** — \(desc)\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }
}
