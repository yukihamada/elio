import Foundation
import EventKit

final class CalendarServer: MCPServer {
    let id = "calendar"
    let name = "カレンダー"
    let serverDescription = "カレンダーの予定を読み書きします（iCloud, Google, Exchangeなど全カレンダー対応）"
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
                    MCPPromptArgument(name: "time", description: "時間 (HH:mm)", descriptionEn: "Time (HH:mm)", required: true),
                    MCPPromptArgument(name: "calendar_name", description: "カレンダー名（例: Google, 仕事）", descriptionEn: "Calendar name (e.g. Google, Work)", required: false)
                ]
            ),
            MCPPrompt(
                name: "add_event_from_message",
                description: "メッセージからイベント情報を抽出してカレンダーに追加します",
                descriptionEn: "Extract event details from a message and add to calendar",
                arguments: [
                    MCPPromptArgument(name: "message", description: "イベント情報を含むメッセージ", descriptionEn: "Message containing event details", required: true)
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
            let calendarNote = arguments["calendar_name"].map { "カレンダー「\($0)」に" } ?? ""
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("\(calendarNote)\(date)の\(time)に「\(title)」という予定を作成してください。"))
            ])
        case "add_event_from_message":
            let message = arguments["message"] ?? ""
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("""
                以下のメッセージからイベント情報（タイトル、日時、場所、URL、詳細）を抽出して、カレンダーに予定を追加してください。
                まずlist_calendarsでカレンダー一覧を確認し、適切なカレンダーを選んでください。

                メッセージ:
                \(message)
                """))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "list_events",
                description: "指定期間の予定一覧を取得します。Google Calendar、iCloudなど全カレンダーから取得可能",
                inputSchema: MCPInputSchema(
                    properties: [
                        "start_date": MCPPropertySchema(type: "string", description: "開始日 (YYYY-MM-DD形式、省略時は今日)"),
                        "end_date": MCPPropertySchema(type: "string", description: "終了日 (YYYY-MM-DD形式、省略時は開始日から7日後)"),
                        "calendar_name": MCPPropertySchema(type: "string", description: "カレンダー名で絞り込み（省略時は全カレンダー）")
                    ]
                )
            ),
            MCPTool(
                name: "create_event",
                description: "新しい予定を作成します。calendar_nameでGoogle Calendarなど特定のカレンダーを指定可能",
                inputSchema: MCPInputSchema(
                    properties: [
                        "title": MCPPropertySchema(type: "string", description: "予定のタイトル"),
                        "start_date": MCPPropertySchema(type: "string", description: "開始日時 (YYYY-MM-DD HH:mm形式)"),
                        "end_date": MCPPropertySchema(type: "string", description: "終了日時 (YYYY-MM-DD HH:mm形式、省略時は1時間後)"),
                        "calendar_name": MCPPropertySchema(type: "string", description: "追加先カレンダー名（例: Google, 仕事, プライベート。省略時はデフォルトカレンダー）"),
                        "location": MCPPropertySchema(type: "string", description: "場所（住所や会場名）"),
                        "url": MCPPropertySchema(type: "string", description: "関連URL（会議リンク、登録ページ、Webサイトなど）"),
                        "notes": MCPPropertySchema(type: "string", description: "メモ・詳細情報"),
                        "all_day": MCPPropertySchema(type: "boolean", description: "終日イベントかどうか"),
                        "alarm_minutes": MCPPropertySchema(type: "string", description: "アラーム（開始何分前に通知。例: 10, 30, 60）")
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
                name: "search_events",
                description: "キーワードで予定を検索します（タイトル、場所、メモから検索）",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "検索キーワード"),
                        "start_date": MCPPropertySchema(type: "string", description: "検索開始日 (YYYY-MM-DD形式、省略時は今日)"),
                        "end_date": MCPPropertySchema(type: "string", description: "検索終了日 (YYYY-MM-DD形式、省略時は90日後)")
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "list_calendars",
                description: "利用可能なカレンダー一覧を取得します（Google, iCloud, Exchange等のアカウント種別も表示）",
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
        case "search_events":
            return try await searchEvents(arguments: arguments)
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

    // MARK: - Calendar Resolution

    /// Find a writable calendar by name. Matches partial/case-insensitive names.
    private func findCalendar(named name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        let lowercased = name.lowercased()

        // Exact match first
        if let exact = calendars.first(where: { $0.title.lowercased() == lowercased && $0.allowsContentModifications }) {
            return exact
        }

        // Partial match (e.g., "Google" matches "Google - user@gmail.com")
        if let partial = calendars.first(where: { $0.title.lowercased().contains(lowercased) && $0.allowsContentModifications }) {
            return partial
        }

        // Match by source title (e.g., "Google" matches any calendar from Google source)
        if let bySource = calendars.first(where: { $0.source.title.lowercased().contains(lowercased) && $0.allowsContentModifications }) {
            return bySource
        }

        return nil
    }

    /// Resolve target calendar from arguments, defaulting to device default
    private func resolveTargetCalendar(from arguments: [String: JSONValue]) -> (calendar: EKCalendar, name: String)? {
        if let calendarName = arguments["calendar_name"]?.stringValue,
           let calendar = findCalendar(named: calendarName) {
            return (calendar, calendar.title)
        }
        if let defaultCal = eventStore.defaultCalendarForNewEvents {
            return (defaultCal, defaultCal.title)
        }
        return nil
    }

    /// Human-readable source type for a calendar
    private func sourceTypeLabel(for source: EKSource) -> String {
        switch source.sourceType {
        case .local:
            return "ローカル"
        case .exchange:
            return "Exchange"
        case .calDAV:
            // CalDAV includes both iCloud and Google
            let title = source.title.lowercased()
            if title.contains("icloud") {
                return "iCloud"
            } else if title.contains("google") || title.contains("gmail") {
                return "Google"
            }
            return "CalDAV"
        case .mobileMe:
            return "iCloud"
        case .subscribed:
            return "購読"
        case .birthdays:
            return "誕生日"
        @unknown default:
            return "その他"
        }
    }

    // MARK: - Tool Implementations

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
            calendars = eventStore.calendars(for: .event).filter {
                $0.title.lowercased().contains(calendarName.lowercased()) ||
                $0.source.title.lowercased().contains(calendarName.lowercased())
            }
        } else {
            calendars = nil
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        var result = "予定一覧\n"
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
                    result += formatEvent(event, includeDetails: true)
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

        // Resolve target calendar
        guard let (targetCalendar, calendarName) = resolveTargetCalendar(from: arguments) else {
            throw MCPClientError.executionFailed("利用可能なカレンダーが見つかりません。iOS設定でカレンダーアカウントを追加してください。")
        }

        // Check if all_day is explicitly requested
        let isAllDay = arguments["all_day"]?.boolValue == true

        // Try multiple date formats for flexibility
        let startDate = parseDateTime(startStr)

        guard let startDate = startDate else {
            // Try all-day format
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let allDayStart = dateFormatter.date(from: startStr) else {
                throw MCPClientError.invalidArguments("Invalid date format. Use: YYYY-MM-DD HH:mm or YYYY-MM-DDTHH:mm")
            }

            return try await createCalendarEvent(
                title: title,
                startDate: allDayStart,
                endDate: Calendar.current.date(byAdding: .day, value: 1, to: allDayStart)!,
                isAllDay: true,
                calendar: targetCalendar,
                calendarName: calendarName,
                arguments: arguments
            )
        }

        if isAllDay {
            let dayStart = Calendar.current.startOfDay(for: startDate)
            return try await createCalendarEvent(
                title: title,
                startDate: dayStart,
                endDate: Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!,
                isAllDay: true,
                calendar: targetCalendar,
                calendarName: calendarName,
                arguments: arguments
            )
        }

        let endDate: Date
        if let endStr = arguments["end_date"]?.stringValue,
           let date = parseDateTime(endStr) {
            endDate = date
        } else {
            endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
        }

        return try await createCalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            calendar: targetCalendar,
            calendarName: calendarName,
            arguments: arguments
        )
    }

    /// Unified event creation with full metadata support
    private func createCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendar: EKCalendar,
        calendarName: String,
        arguments: [String: JSONValue]
    ) async throws -> MCPResult {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.calendar = calendar

        // Location
        if let location = arguments["location"]?.stringValue, !location.isEmpty {
            event.location = location
        }

        // URL
        if let urlString = arguments["url"]?.stringValue,
           let url = URL(string: urlString) {
            event.url = url
        }

        // Notes - append URL to notes as well for visibility
        var notes = arguments["notes"]?.stringValue ?? ""
        if let urlString = arguments["url"]?.stringValue, !urlString.isEmpty {
            if !notes.isEmpty {
                notes += "\n\n"
            }
            notes += "URL: \(urlString)"
        }
        if !notes.isEmpty {
            event.notes = notes
        }

        // Alarm
        if let alarmStr = arguments["alarm_minutes"]?.stringValue,
           let minutes = Double(alarmStr) {
            let alarm = EKAlarm(relativeOffset: -minutes * 60)
            event.addAlarm(alarm)
        }

        try eventStore.save(event, span: .thisEvent)

        // Build confirmation message
        let sourceType = sourceTypeLabel(for: calendar.source)
        var confirmMsg = "予定を作成しました\n"
        confirmMsg += "タイトル: \(title)\n"
        confirmMsg += "カレンダー: \(calendarName) (\(sourceType))\n"

        if isAllDay {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy年M月d日"
            confirmMsg += "日付: \(dateFormatter.string(from: startDate))（終日）\n"
        } else {
            confirmMsg += "日時: \(formatEventTime(startDate, endDate))\n"
        }

        if let location = event.location {
            confirmMsg += "場所: \(location)\n"
        }
        if let url = event.url {
            confirmMsg += "URL: \(url.absoluteString)\n"
        }
        if let notes = event.notes, !notes.isEmpty {
            confirmMsg += "メモ: \(notes)\n"
        }
        if let alarms = event.alarms, !alarms.isEmpty {
            let minutes = Int(-alarms[0].relativeOffset / 60)
            confirmMsg += "アラーム: \(minutes)分前\n"
        }

        confirmMsg += "ID: \(event.eventIdentifier ?? "N/A")"

        return MCPResult(content: [.text(confirmMsg)])
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

    private func searchEvents(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            throw MCPClientError.invalidArguments("query is required")
        }

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
            endDate = Calendar.current.date(byAdding: .day, value: 90, to: startDate)!
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let allEvents = eventStore.events(matching: predicate)

        let lowQuery = query.lowercased()
        let matchingEvents = allEvents.filter { event in
            let titleMatch = event.title?.lowercased().contains(lowQuery) == true
            let locationMatch = event.location?.lowercased().contains(lowQuery) == true
            let notesMatch = event.notes?.lowercased().contains(lowQuery) == true
            return titleMatch || locationMatch || notesMatch
        }.sorted { $0.startDate < $1.startDate }

        var result = "検索結果: \"\(query)\"\n"
        result += "\(formatDateRange(startDate, endDate))\n\n"

        if matchingEvents.isEmpty {
            result += "該当する予定はありません"
        } else {
            result += "\(matchingEvents.count)件の予定が見つかりました\n\n"
            for event in matchingEvents.prefix(20) {
                result += formatEvent(event, includeDetails: true)
            }
            if matchingEvents.count > 20 {
                result += "\n...他\(matchingEvents.count - 20)件"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func listCalendars() async throws -> MCPResult {
        let calendars = eventStore.calendars(for: .event)

        // Group by source
        let grouped = Dictionary(grouping: calendars) { $0.source.title }

        var result = "カレンダー一覧\n\n"

        let defaultCal = eventStore.defaultCalendarForNewEvents

        for sourceTitle in grouped.keys.sorted() {
            guard let cals = grouped[sourceTitle] else { continue }
            let sourceType = sourceTypeLabel(for: cals[0].source)
            result += "## \(sourceTitle) (\(sourceType))\n"

            for calendar in cals.sorted(by: { $0.title < $1.title }) {
                let writableIcon = calendar.allowsContentModifications ? "[書込可]" : "[読取専用]"
                let defaultMark = (calendar.calendarIdentifier == defaultCal?.calendarIdentifier) ? " *デフォルト*" : ""
                result += "  - \(calendar.title) \(writableIcon)\(defaultMark)\n"
            }
            result += "\n"
        }

        result += "---\n"
        result += "ヒント: create_eventのcalendar_nameにカレンダー名を指定すると、そのカレンダーに予定を追加できます。\n"
        result += "Google Calendarに追加するには、iOS設定 > カレンダー > アカウントでGoogleアカウントを追加してください。"

        return MCPResult(content: [.text(result)])
    }

    private func todaySchedule() async throws -> MCPResult {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let predicate = eventStore.predicateForEvents(withStart: today, end: tomorrow, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        var result = "今日のスケジュール\n"
        result += "\(formatDayHeader(today))\n\n"

        if events.isEmpty {
            result += "今日の予定はありません"
        } else {
            for event in events {
                result += formatEvent(event, includeDetails: true)
            }
        }

        return MCPResult(content: [.text(result)])
    }

    // MARK: - Formatting Helpers

    private func formatEvent(_ event: EKEvent, includeDetails: Bool = false) -> String {
        var str = ""
        if event.isAllDay {
            str += "終日: "
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            str += "\(timeFormatter.string(from: event.startDate))-\(timeFormatter.string(from: event.endDate)): "
        }
        str += "\(event.title ?? "無題")"

        if includeDetails {
            str += " [\(event.calendar.title)]"
        }

        if let location = event.location, !location.isEmpty {
            str += " | 場所: \(location)"
        }

        if includeDetails {
            if let url = event.url {
                str += " | URL: \(url.absoluteString)"
            }
            if let notes = event.notes, !notes.isEmpty {
                let truncatedNotes = notes.count > 80 ? String(notes.prefix(80)) + "..." : notes
                str += " | メモ: \(truncatedNotes)"
            }
            if let eventId = event.eventIdentifier {
                str += " | ID: \(eventId)"
            }
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
            "yyyy-MM-dd'T'HH:mm:ssZ",       // ISO 8601 with timezone
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",   // ISO 8601 with timezone offset
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
