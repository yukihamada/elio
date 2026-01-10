import Foundation
import EventKit

final class RemindersServer: MCPServer {
    let id = "reminders"
    let name = "リマインダー"
    let serverDescription = "リマインダーの作成・管理を行います"
    let icon = "checklist"

    private let eventStore = EKEventStore()

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "pending_tasks",
                description: "未完了のタスクを確認します",
                descriptionEn: "Check pending tasks"
            ),
            MCPPrompt(
                name: "add_quick_reminder",
                description: "簡単にリマインダーを追加します",
                descriptionEn: "Quickly add a reminder",
                arguments: [
                    MCPPromptArgument(name: "task", description: "タスクの内容", descriptionEn: "Task content", required: true)
                ]
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "pending_tasks":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("未完了のリマインダーを確認して、優先度順に整理してください。期限が近いものがあれば教えてください。"))
            ])
        case "add_quick_reminder":
            let task = arguments["task"] ?? "タスク"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("「\(task)」というリマインダーを作成してください。"))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "list_reminders",
                description: "リマインダー一覧を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "list_name": MCPPropertySchema(type: "string", description: "リスト名（省略時は全リスト）"),
                        "include_completed": MCPPropertySchema(type: "boolean", description: "完了済みも含める")
                    ]
                )
            ),
            MCPTool(
                name: "create_reminder",
                description: "新しいリマインダーを作成します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "title": MCPPropertySchema(type: "string", description: "リマインダーのタイトル"),
                        "due_date": MCPPropertySchema(type: "string", description: "期限 (YYYY-MM-DD HH:mm形式)"),
                        "notes": MCPPropertySchema(type: "string", description: "メモ"),
                        "priority": MCPPropertySchema(type: "integer", description: "優先度 (1-9, 1が最高)")
                    ],
                    required: ["title"]
                )
            ),
            MCPTool(
                name: "complete_reminder",
                description: "リマインダーを完了にします",
                inputSchema: MCPInputSchema(
                    properties: [
                        "reminder_id": MCPPropertySchema(type: "string", description: "リマインダーのID")
                    ],
                    required: ["reminder_id"]
                )
            ),
            MCPTool(
                name: "delete_reminder",
                description: "リマインダーを削除します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "reminder_id": MCPPropertySchema(type: "string", description: "リマインダーのID")
                    ],
                    required: ["reminder_id"]
                )
            ),
            MCPTool(
                name: "list_reminder_lists",
                description: "リマインダーリスト一覧を取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        try await requestAccess()

        switch name {
        case "list_reminders":
            return try await listReminders(arguments: arguments)
        case "create_reminder":
            return try await createReminder(arguments: arguments)
        case "complete_reminder":
            return try await completeReminder(arguments: arguments)
        case "delete_reminder":
            return try await deleteReminder(arguments: arguments)
        case "list_reminder_lists":
            return try await listReminderLists()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func requestAccess() async throws {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToReminders()
            guard granted else {
                throw MCPClientError.permissionDenied("リマインダーへのアクセスが拒否されました")
            }
        } else {
            let granted = try await eventStore.requestAccess(to: .reminder)
            guard granted else {
                throw MCPClientError.permissionDenied("リマインダーへのアクセスが拒否されました")
            }
        }
    }

    private func listReminders(arguments: [String: JSONValue]) async throws -> MCPResult {
        let calendars: [EKCalendar]?
        if let listName = arguments["list_name"]?.stringValue {
            calendars = eventStore.calendars(for: .reminder).filter { $0.title == listName }
        } else {
            calendars = eventStore.calendars(for: .reminder)
        }

        let includeCompleted = arguments["include_completed"]?.boolValue ?? false

        let predicate = eventStore.predicateForReminders(in: calendars)

        let reminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }

        let filtered = reminders.filter { includeCompleted || !$0.isCompleted }
            .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }

        var result = "✅ リマインダー一覧\n\n"

        if filtered.isEmpty {
            result += "リマインダーはありません"
        } else {
            for reminder in filtered {
                result += formatReminder(reminder)
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func createReminder(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let title = arguments["title"]?.stringValue else {
            throw MCPClientError.invalidArguments("title is required")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dueDateStr = arguments["due_date"]?.stringValue {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

            if let dueDate = dateFormatter.date(from: dueDateStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )

                let alarm = EKAlarm(absoluteDate: dueDate)
                reminder.addAlarm(alarm)
            }
        }

        reminder.notes = arguments["notes"]?.stringValue

        if let priority = arguments["priority"]?.intValue {
            reminder.priority = max(1, min(9, priority))
        }

        try eventStore.save(reminder, commit: true)

        var resultText = "リマインダーを作成しました: \(title)"
        if let components = reminder.dueDateComponents, let date = components.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日 HH:mm"
            resultText += "\n期限: \(formatter.string(from: date))"
        }

        return MCPResult(content: [.text(resultText)])
    }

    private func completeReminder(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let reminderId = arguments["reminder_id"]?.stringValue,
              let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw MCPClientError.invalidArguments("Reminder not found")
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()
        try eventStore.save(reminder, commit: true)

        return MCPResult(content: [.text("リマインダーを完了にしました: \(reminder.title ?? "無題")")])
    }

    private func deleteReminder(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let reminderId = arguments["reminder_id"]?.stringValue,
              let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw MCPClientError.invalidArguments("Reminder not found")
        }

        let title = reminder.title ?? "無題"
        try eventStore.remove(reminder, commit: true)

        return MCPResult(content: [.text("リマインダーを削除しました: \(title)")])
    }

    private func listReminderLists() async throws -> MCPResult {
        let calendars = eventStore.calendars(for: .reminder)

        var result = "📋 リマインダーリスト一覧\n\n"
        for calendar in calendars {
            result += "• \(calendar.title)\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func formatReminder(_ reminder: EKReminder) -> String {
        var str = reminder.isCompleted ? "☑️ " : "⬜ "
        str += reminder.title ?? "無題"

        if let priority = priorityEmoji(reminder.priority) {
            str += " \(priority)"
        }

        if let components = reminder.dueDateComponents, let date = components.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d HH:mm"
            str += " 📅\(formatter.string(from: date))"
        }

        str += "\n"
        return str
    }

    private func priorityEmoji(_ priority: Int) -> String? {
        switch priority {
        case 1...3: return "🔴"
        case 4...6: return "🟡"
        case 7...9: return "🔵"
        default: return nil
        }
    }
}
