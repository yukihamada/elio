import SwiftUI
import LlamaSwift

/// Benchmark screen for testing tool selection accuracy and multi-turn conversation quality.
/// Ported from NOU app's TestResultsView.
struct BenchmarkView: View {
    @StateObject private var runner = BenchmarkRunner()
    let modelPath: String
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header stats
                    headerView
                        .padding()

                    // Progress bar
                    if runner.isRunning {
                        ProgressView(value: Double(runner.results.count + runner.multiTurnResults.count),
                                     total: Double(max(1, runner.totalTests)))
                            .tint(.accentColor)
                            .padding(.horizontal)
                    }

                    // Results list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                // Tool selection results
                                if !runner.results.isEmpty {
                                    sectionHeader("Tool Selection")
                                }
                                ForEach(Array(runner.results.enumerated()), id: \.offset) { idx, result in
                                    BenchmarkResultRow(index: idx + 1, result: result)
                                        .id("tool-\(idx)")
                                }

                                // Multi-turn results
                                if !runner.multiTurnResults.isEmpty {
                                    sectionHeader("Multi-Turn Conversation")
                                        .padding(.top, 8)
                                }
                                ForEach(Array(runner.multiTurnResults.enumerated()), id: \.offset) { idx, mt in
                                    BenchmarkMultiTurnRow(index: idx + 1, result: mt)
                                        .id("mt-\(idx)")
                                }
                            }
                            .padding()
                        }
                        .onChange(of: runner.multiTurnResults.count) { _, count in
                            if count > 0 {
                                withAnimation { proxy.scrollTo("mt-\(count - 1)", anchor: .bottom) }
                            }
                        }
                    }

                    // Category breakdown
                    if !runner.isRunning && !runner.results.isEmpty {
                        categoryBreakdown
                            .padding()
                    }
                }
            }
            .navigationTitle("Benchmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !runner.isRunning && !runner.results.isEmpty {
                        Button("Done") { onDone() }
                    }
                }
            }
        }
        .onAppear {
            runner.start(modelPath: modelPath)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if runner.isRunning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("\(runner.phase): \(runner.results.count + runner.multiTurnResults.count) tests...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !runner.results.isEmpty {
                let toolPct = Int(Float(runner.passCount) / Float(max(1, runner.results.count)) * 100)
                let mtPct = runner.multiTurnResults.isEmpty ? 0 : Int(Float(runner.mtPassCount) / Float(runner.multiTurnResults.count) * 100)
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Tools")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(runner.passCount)/\(runner.results.count) (\(toolPct)%)")
                            .font(.title3.bold())
                            .foregroundStyle(toolPct >= 90 ? .green : .orange)
                    }
                    if !runner.multiTurnResults.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Multi-turn")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(runner.mtPassCount)/\(runner.multiTurnResults.count) (\(mtPct)%)")
                                .font(.title3.bold())
                                .foregroundStyle(mtPct >= 75 ? .green : .orange)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryBreakdown: some View {
        let categories = Dictionary(grouping: runner.results, by: { $0.category })
        let sorted = categories.sorted { $0.key < $1.key }

        return VStack(alignment: .leading, spacing: 6) {
            Text("By Category")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(sorted, id: \.key) { cat, results in
                let passed = results.filter(\.passed).count
                HStack {
                    Text(cat)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text("\(passed)/\(results.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(passed == results.count ? .green : .orange)
                    Spacer()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Result Rows

struct BenchmarkResultRow: View {
    let index: Int
    let result: BenchmarkTestResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(result.passed ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.query)
                    .font(.system(size: 12))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(result.category)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if result.passed {
                        Text(result.expected)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(result.expected) -> \(result.got)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Text("#\(index)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct BenchmarkMultiTurnRow: View {
    let index: Int
    let result: BenchmarkMultiTurnResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(result.passed ? .green : .red)

                Text(result.testName)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text("\(result.turns.count) turns")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(result.turns.enumerated()), id: \.offset) { _, turn in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Q: \(turn.query)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("A: \(turn.response)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            if !result.passed {
                Text(result.reason)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Benchmark Runner

@MainActor
class BenchmarkRunner: ObservableObject {
    @Published var results: [BenchmarkTestResult] = []
    @Published var multiTurnResults: [BenchmarkMultiTurnResult] = []
    @Published var isRunning = false
    @Published var phase: String = ""
    @Published var totalTests = 0
    var passCount: Int { results.filter(\.passed).count }
    var mtPassCount: Int { multiTurnResults.filter(\.passed).count }

    func start(modelPath: String) {
        guard !isRunning else { return }
        isRunning = true
        totalTests = 47

        Task.detached { [weak self] in
            // Phase 1: Tool selection tests
            await MainActor.run { self?.phase = "Tool Selection" }
            let toolResults = runBenchmarkAutoTests(modelPath: modelPath, log: { msg in
                print("[Benchmark] \(msg)")
            }) { result in
                Task { @MainActor [weak self] in
                    self?.results.append(result)
                }
            }

            // Phase 2: Multi-turn tests
            await MainActor.run { self?.phase = "Multi-Turn" }
            let mtResults = runBenchmarkMultiTurnTests(modelPath: modelPath, log: { msg in
                print("[Benchmark] \(msg)")
            }) { result in
                Task { @MainActor [weak self] in
                    self?.multiTurnResults.append(result)
                }
            }

            Task { @MainActor [weak self] in
                self?.totalTests = toolResults.count + mtResults.count
                self?.isRunning = false
                self?.phase = "Done"
            }
        }
    }
}
