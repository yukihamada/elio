import Foundation
import EventKit

final class CalendarServer: MCPServer {
    let id = "calendar"
    let name = "カレンダー"
    let serverDescription = "カレンダーの予定を読み書きします"
    let icon = "calendar"

    private let eventStore = EKEventStore()

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "today_schedule",
                description: "今日のスケジュールを確認して要約します",
                descriptionEn: "Check and summarize today's schedule"
            ),
            MCPPrompt(
                name: "weekly_overview",
                description: "今週の予定を一覧で確認します",
                descriptionEn: "Get an overview of this week's schedule"
            ),
            MCPPrompt(
                name: "schedule_meeting",
                description: "新しい会議を設定します",
                descriptionEn: "Schedule a new meeting",
                arguments: [
                    MCPPromptArgument(name: "title", description: "会議のタイトル", descriptionEn: "Meeting title", required: true),
                    MCPPromptArgument(name: "date", description: "日付 (YYYY-MM-DD)", descriptionEn: "Date (YYYY-MM-DD)", required: true),
                    MCPPromptArgument(name: "time", description: "時間 (HH:mm)", descriptionEn: "Time (HH:mm)", required: true)
                ]
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "today_schedule":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("今日のスケジュールを教えてください。予定がある場合は時間順に整理して、重要な予定があれば強調してください。"))
            ])
        case "weekly_overview":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("今週の予定を確認してください。曜日ごとに整理して、空いている時間帯も教えてください。"))
            ])
        case "schedule_meeting":
            let title = arguments["title"] ?? "会議"
            let date = arguments["date"] ?? "today"
            let time = arguments["time"] ?? "10:00"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("\(date)の\(time)に「\(title)」という予定を作成してください。"))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "list_events",
                description: "指定期間の予定一覧を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "start_date": MCPPropertySchema(type: "string", description: "開始日 (YYYY-MM-DD形式、省略時は今日)"),
                        "end_date": MCPPropertySchema(type: "string", description: "終了日 (YYYY-MM-DD形式、省略時は開始日から7日後)"),
                        "calendar_name": MCPPropertySchema(type: "string", description: "カレンダー名（省略時は全カレンダー）")
                    ]
                )
            ),
            MCPTool(
                name: "create_event",
                description: "新しい予定を作成します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "title": MCPPropertySchema(type: "string", description: "予定のタイトル"),
                        "start_date": MCPPropertySchema(type: "string", description: "開始日時 (YYYY-MM-DD HH:mm形式)"),
                        "end_date": MCPPropertySchema(type: "string", description: "終了日時 (YYYY-MM-DD HH:mm形式)"),
                        "location": MCPPropertySchema(type: "string", description: "場所"),
                        "notes": MCPPropertySchema(type: "string", description: "メモ"),
                        "all_day": MCPPropertySchema(type: "boolean", description: "終日イベントかどうか")
                    ],
                    required: ["title", "start_date"]
                )
            ),
            MCPTool(
                name: "delete_event",
                description: "予定を削除します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "event_id": MCPPropertySchema(type: "string", description: "予定のID")
                    ],
                    required: ["event_id"]
                )
            ),
            MCPTool(
                name: "list_calendars",
                description: "利用可能なカレンダー一覧を取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "today_schedule",
                description: "今日のスケジュールを取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        try await requestAccess()

        switch name {
        case "list_events":
            return try await listEvents(arguments: arguments)
        case "create_event":
            return try await createEvent(arguments: arguments)
        case "delete_event":
            return try await deleteEvent(arguments: arguments)
        case "list_calendars":
            return try await listCalendars()
        case "today_schedule":
            return try await todaySchedule()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func requestAccess() async throws {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else {
                throw MCPClientError.permissionDenied("カレンダーへのアクセスが拒否されました")
            }
        } else {
            let granted = try await eventStore.requestAccess(to: .event)
            guard granted else {
                throw MCPClientError.permissionDenied("カレンダーへのアクセスが拒否されました")
            }
        }
    }

    private func listEvents(arguments: [String: JSONValue]) async throws -> MCPResult {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDate: Date
        if let startStr = arguments["start_date"]?.stringValue,
           let date = dateFormatter.date(from: startStr) {
            startDate = date
        } else {
            startDate = Calendar.current.startOfDay(for: Date())
        }

        let endDate: Date
        if let endStr = arguments["end_date"]?.stringValue,
           let date = dateFormatter.date(from: endStr) {
            endDate = date
        } else {
            endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        }

        let calendars: [EKCalendar]?
        if let calendarName = arguments["calendar_name"]?.stringValue {
            calendars = eventStore.calendars(for: .event).filter { $0.title == calendarName }
        } else {
            calendars = nil
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        var result = "📅 予定一覧\n"
        result += "\(formatDateRange(startDate, endDate))\n\n"

        if events.isEmpty {
            result += "予定はありません"
        } else {
            let grouped = Dictionary(grouping: events) {
                Calendar.current.startOfDay(for: $0.startDate)
            }

            for date in grouped.keys.sorted() {
                result += "### \(formatDayHeader(date))\n"
                for event in grouped[date]! {
                    result += formatEvent(event)
                }
                result += "\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func createEvent(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let title = arguments["title"]?.stringValue,
              let startStr = arguments["start_date"]?.stringValue else {
            throw MCPClientError.invalidArguments("title and start_date are required")
        }

        // Try multiple date formats for flexibility
        let startDate = parseDateTime(startStr)

        guard let startDate = startDate else {
            // Try all-day format
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let allDayStart = dateFormatter.date(from: startStr) else {
                throw MCPClientError.invalidArguments("Invalid date format. Use: YYYY-MM-DD HH:mm or YYYY-MM-DDTHH:mm")
            }

            return try await createAllDayEvent(title: title, date: allDayStart, arguments: arguments)
        }

        let endDate: Date
        if let endStr = arguments["end_date"]?.stringValue,
           let date = parseDateTime(endStr) {
            endDate = date
        } else {
            endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.location = arguments["location"]?.stringValue
        event.notes = arguments["notes"]?.stringValue

        try eventStore.save(event, span: .thisEvent)

        return MCPResult(content: [.text("予定を作成しました: \(title)\n日時: \(formatEventTime(startDate, endDate))")])
    }

    private func createAllDayEvent(title: String, date: Date, arguments: [String: JSONValue]) async throws -> MCPResult {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = date
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        event.isAllDay = true
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.location = arguments["location"]?.stringValue
        event.notes = arguments["notes"]?.stringValue

        try eventStore.save(event, span: .thisEvent)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年M月d日"

        return MCPResult(content: [.text("終日予定を作成しました: \(title)\n日付: \(dateFormatter.string(from: date))")])
    }

    private func deleteEvent(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let eventId = arguments["event_id"]?.stringValue,
              let event = eventStore.event(withIdentifier: eventId) else {
            throw MCPClientError.invalidArguments("Event not found")
        }

        let title = event.title ?? "無題"
        try eventStore.remove(event, span: .thisEvent)

        return MCPResult(content: [.text("予定を削除しました: \(title)")])
    }

    private func listCalendars() async throws -> MCPResult {
        let calendars = eventStore.calendars(for: .event)

        var result = "📅 カレンダー一覧\n\n"
        for calendar in calendars {
            let icon = calendar.isImmutable ? "🔒" : "📝"
            result += "\(icon) \(calendar.title)\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func todaySchedule() async throws -> MCPResult {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let predicate = eventStore.predicateForEvents(withStart: today, end: tomorrow, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        var result = "📅 今日のスケジュール\n"
        result += "\(formatDayHeader(today))\n\n"

        if events.isEmpty {
            result += "今日の予定はありません"
        } else {
            for event in events {
                result += formatEvent(event)
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func formatEvent(_ event: EKEvent) -> String {
        var str = ""
        if event.isAllDay {
            str += "🌅 終日: "
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            str += "⏰ \(timeFormatter.string(from: event.startDate))-\(timeFormatter.string(from: event.endDate)): "
        }
        str += "\(event.title ?? "無題")"
        if let location = event.location, !location.isEmpty {
            str += " 📍\(location)"
        }
        str += "\n"
        return str
    }

    private func formatDayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter.string(from: date)
    }

    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: start)) 〜 \(formatter.string(from: end))"
    }

    private func formatEventTime(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 HH:mm"
        return "\(formatter.string(from: start)) 〜 \(formatter.string(from: end))"
    }

    /// Parse datetime string with multiple format support
    private func parseDateTime(_ string: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm",      // Space separator
            "yyyy-MM-dd'T'HH:mm",    // ISO 8601 with T
            "yyyy-MM-dd'T'HH:mm:ss", // ISO 8601 full
            "yyyy/MM/dd HH:mm",      // Slash separator
            "yyyy-MM-dd HH:mm:ss",   // With seconds
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }
}
