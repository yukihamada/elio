import Foundation
import HealthKit

final class HealthServer: MCPServer {
    let id = "health"
    let name = "ヘルスケア"
    let serverDescription = "ヘルスケアデータにアクセスします"
    let icon = "heart"

    private let healthStore = HKHealthStore()

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "daily_health_report",
                description: "今日の健康データをまとめてレポートします",
                descriptionEn: "Generate a daily health report"
            ),
            MCPPrompt(
                name: "sleep_analysis",
                description: "睡眠データを分析してアドバイスします",
                descriptionEn: "Analyze sleep data and provide advice"
            ),
            MCPPrompt(
                name: "fitness_goals",
                description: "運動目標の達成状況を確認します",
                descriptionEn: "Check fitness goal progress"
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "daily_health_report":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("今日の健康データ（歩数、消費カロリー、心拍数など）をすべて確認して、健康レポートを作成してください。改善点があればアドバイスもお願いします。"))
            ])
        case "sleep_analysis":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("昨夜の睡眠データを確認して分析してください。睡眠の質を改善するためのアドバイスがあれば教えてください。"))
            ])
        case "fitness_goals":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("今日の運動目標（歩数10,000歩、消費カロリー500kcalなど）の達成状況を確認してください。目標達成のためのアドバイスもお願いします。"))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "get_step_count",
                description: "歩数を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "date": MCPPropertySchema(type: "string", description: "日付 (YYYY-MM-DD形式、省略時は今日)")
                    ]
                )
            ),
            MCPTool(
                name: "get_heart_rate",
                description: "心拍数を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "date": MCPPropertySchema(type: "string", description: "日付 (YYYY-MM-DD形式、省略時は今日)")
                    ]
                )
            ),
            MCPTool(
                name: "get_sleep_data",
                description: "睡眠データを取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "date": MCPPropertySchema(type: "string", description: "日付 (YYYY-MM-DD形式、省略時は昨夜)")
                    ]
                )
            ),
            MCPTool(
                name: "get_activity_summary",
                description: "アクティビティサマリーを取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "date": MCPPropertySchema(type: "string", description: "日付 (YYYY-MM-DD形式、省略時は今日)")
                    ]
                )
            ),
            MCPTool(
                name: "get_health_overview",
                description: "健康データの概要を取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw MCPClientError.executionFailed("ヘルスケアはこのデバイスで利用できません")
        }

        try await requestAccess()

        switch name {
        case "get_step_count":
            return try await getStepCount(arguments: arguments)
        case "get_heart_rate":
            return try await getHeartRate(arguments: arguments)
        case "get_sleep_data":
            return try await getSleepData(arguments: arguments)
        case "get_activity_summary":
            return try await getActivitySummary(arguments: arguments)
        case "get_health_overview":
            return try await getHealthOverview()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func requestAccess() async throws {
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKCategoryType(.sleepAnalysis)
        ]

        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }

    private func getStepCount(arguments: [String: JSONValue]) async throws -> MCPResult {
        let date = parseDate(arguments["date"]?.stringValue) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let steps = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: sum)
            }

            healthStore.execute(query)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月d日"

        var result = "👟 歩数\n\n"
        result += "日付: \(dateFormatter.string(from: date))\n"
        result += "歩数: \(Int(steps).formatted()) 歩\n"

        let goalProgress = min(steps / 10000 * 100, 100)
        result += "目標達成率: \(Int(goalProgress))% (10,000歩目標)\n"

        return MCPResult(content: [.text(result)])
    }

    private func getHeartRate(arguments: [String: JSONValue]) async throws -> MCPResult {
        let date = parseDate(arguments["date"]?.stringValue) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }

            healthStore.execute(query)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月d日"

        var result = "❤️ 心拍数\n\n"
        result += "日付: \(dateFormatter.string(from: date))\n\n"

        if samples.isEmpty {
            result += "データがありません"
        } else {
            let heartRates = samples.map {
                $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }

            let avg = heartRates.reduce(0, +) / Double(heartRates.count)
            let min = heartRates.min() ?? 0
            let max = heartRates.max() ?? 0

            result += "平均: \(Int(avg)) bpm\n"
            result += "最低: \(Int(min)) bpm\n"
            result += "最高: \(Int(max)) bpm\n"
            result += "測定回数: \(samples.count)回\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func getSleepData(arguments: [String: JSONValue]) async throws -> MCPResult {
        let date = parseDate(arguments["date"]?.stringValue) ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfNextDay = Calendar.current.date(byAdding: .day, value: 2, to: startOfDay)!

        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfNextDay)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }

            healthStore.execute(query)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月d日"

        var result = "😴 睡眠データ\n\n"
        result += "日付: \(dateFormatter.string(from: date))\n\n"

        if samples.isEmpty {
            result += "睡眠データがありません"
        } else {
            var totalSleep: TimeInterval = 0

            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                totalSleep += duration
            }

            let hours = Int(totalSleep) / 3600
            let minutes = (Int(totalSleep) % 3600) / 60

            result += "合計睡眠時間: \(hours)時間\(minutes)分\n"

            if let firstSleep = samples.first, let lastSleep = samples.last {
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"

                result += "就寝時刻: \(timeFormatter.string(from: firstSleep.startDate))\n"
                result += "起床時刻: \(timeFormatter.string(from: lastSleep.endDate))\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func getActivitySummary(arguments: [String: JSONValue]) async throws -> MCPResult {
        let date = parseDate(arguments["date"]?.stringValue) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let stepsValue = try await getQuantitySum(.stepCount, startDate: startOfDay, endDate: endOfDay, unit: .count())
        let caloriesValue = try await getQuantitySum(.activeEnergyBurned, startDate: startOfDay, endDate: endOfDay, unit: .kilocalorie())
        let distanceValue = try await getQuantitySum(.distanceWalkingRunning, startDate: startOfDay, endDate: endOfDay, unit: .meter())

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月d日"

        var result = "🏃 アクティビティサマリー\n\n"
        result += "日付: \(dateFormatter.string(from: date))\n\n"
        result += "👟 歩数: \(Int(stepsValue).formatted()) 歩\n"
        result += "🔥 消費カロリー: \(Int(caloriesValue)) kcal\n"
        result += "📏 距離: \(String(format: "%.2f", distanceValue / 1000)) km\n"

        return MCPResult(content: [.text(result)])
    }

    private func getHealthOverview() async throws -> MCPResult {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let stepsValue = try await getQuantitySum(.stepCount, startDate: today, endDate: tomorrow, unit: .count())
        let caloriesValue = try await getQuantitySum(.activeEnergyBurned, startDate: today, endDate: tomorrow, unit: .kilocalorie())

        var result = "🏥 健康データ概要\n\n"
        result += "### 今日のアクティビティ\n"
        result += "歩数: \(Int(stepsValue).formatted()) 歩\n"
        result += "消費カロリー: \(Int(caloriesValue)) kcal\n"

        return MCPResult(content: [.text(result)])
    }

    private func getQuantitySum(
        _ identifier: HKQuantityTypeIdentifier,
        startDate: Date,
        endDate: Date,
        unit: HKUnit
    ) async throws -> Double {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }

            healthStore.execute(query)
        }
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}
