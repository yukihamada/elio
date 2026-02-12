import SwiftUI

/// View for adjusting per-model generation parameters
struct ModelSettingsView: View {
    let modelId: String
    let modelName: String

    @StateObject private var settingsManager = ModelSettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var temperature: Float = 0.7
    @State private var topP: Float = 0.9
    @State private var topK: Int = 40
    @State private var maxTokens: Int = 2048
    @State private var repeatPenalty: Float = 1.1
    @State private var enableThinking: Bool = true
    @State private var systemPrompt: String = ""
    @State private var selectedPreset: ModelSettingsPreset = .balanced
    @State private var kvCacheTypeK: KVCacheQuantType = .q8_0
    @State private var kvCacheTypeV: KVCacheQuantType = .q8_0

    private let modelLoader = ModelLoader()

    /// Get recommended max tokens for current model
    private var recommendedMaxTokens: Int {
        modelLoader.getModelInfo(modelId)?.recommendedMaxTokens ?? 2048
    }

    /// Max slider value for tokens (double the recommended, capped at 8192)
    private var maxTokensSliderLimit: Int {
        min(recommendedMaxTokens * 2, 8192)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView

                        // Preset selection
                        presetSection

                        // Parameters
                        parametersSection

                        // System prompt
                        systemPromptSection

                        // Reset button
                        resetSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(String(localized: "settings.model.parameters"))
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.linearGradient(
                        colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28))
                    .foregroundStyle(.linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }

            Text(modelName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(String(localized: "settings.model.parameters.description"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.preset.title"), icon: "wand.and.stars", color: .purple)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ModelSettingsPreset.allCases) { preset in
                        PresetButton(
                            preset: preset,
                            isSelected: selectedPreset == preset,
                            action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedPreset = preset
                                    if preset != .custom {
                                        applyPreset(preset)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Parameters Section

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.parameters.title"), icon: "dial.low", color: .blue)

            VStack(spacing: 0) {
                // Temperature
                ParameterSlider(
                    title: String(localized: "settings.parameter.temperature"),
                    description: String(localized: "settings.parameter.temperature.description"),
                    value: $temperature,
                    range: 0...2,
                    step: 0.05,
                    format: "%.2f",
                    onChange: { selectedPreset = .custom }
                )

                Divider().padding(.leading, 16)

                // Top P
                ParameterSlider(
                    title: String(localized: "settings.parameter.top.p"),
                    description: String(localized: "settings.parameter.top.p.description"),
                    value: $topP,
                    range: 0...1,
                    step: 0.05,
                    format: "%.2f",
                    onChange: { selectedPreset = .custom }
                )

                Divider().padding(.leading, 16)

                // Top K
                ParameterIntSlider(
                    title: String(localized: "settings.parameter.top.k"),
                    description: String(localized: "settings.parameter.top.k.description"),
                    value: $topK,
                    range: 1...100,
                    onChange: { selectedPreset = .custom }
                )

                Divider().padding(.leading, 16)

                // Max Tokens
                ParameterIntSlider(
                    title: String(localized: "settings.parameter.max.tokens"),
                    description: String(localized: "settings.parameter.max.tokens.description"),
                    value: $maxTokens,
                    range: 128...maxTokensSliderLimit,
                    step: 128,
                    onChange: { selectedPreset = .custom }
                )

                Divider().padding(.leading, 16)

                // Repeat Penalty
                ParameterSlider(
                    title: String(localized: "settings.parameter.repeat.penalty"),
                    description: String(localized: "settings.parameter.repeat.penalty.description"),
                    value: $repeatPenalty,
                    range: 1...2,
                    step: 0.05,
                    format: "%.2f",
                    onChange: { selectedPreset = .custom }
                )

                Divider().padding(.leading, 16)

                // Enable Thinking
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.parameter.thinking"))
                            .font(.system(size: 15))
                        Text(String(localized: "settings.parameter.thinking.description"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $enableThinking)
                        .labelsHidden()
                        .onChange(of: enableThinking) { _, _ in
                            selectedPreset = .custom
                        }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - System Prompt Section

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.system.prompt.title"), icon: "text.bubble", color: .green)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.system.prompt.description"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextEditor(text: $systemPrompt)
                    .font(.system(size: 14))
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                    .onChange(of: systemPrompt) { _, _ in
                        selectedPreset = .custom
                    }

                // Quick prompts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickPromptButton(title: "日本語アシスタント", prompt: "あなたは日本語に特化したAIアシスタントです。自然で丁寧な日本語で回答してください。") {
                            systemPrompt = $0
                            selectedPreset = .custom
                        }
                        QuickPromptButton(title: "コード専門家", prompt: "あなたはプログラミングの専門家です。コードの説明は簡潔に、実装は正確に行ってください。") {
                            systemPrompt = $0
                            selectedPreset = .custom
                        }
                        QuickPromptButton(title: "クリエイター", prompt: "あなたは創造的なAIアシスタントです。独創的で興味深いアイデアを提案してください。") {
                            systemPrompt = $0
                            selectedPreset = .custom
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Button(action: resetToDefault) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                Text(String(localized: "settings.reset.to.default"))
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
            )
        }
    }

    // MARK: - Actions

    private func loadCurrentSettings() {
        let settings = settingsManager.settings(for: modelId)
        temperature = settings.temperature
        topP = settings.topP
        topK = settings.topK
        maxTokens = settings.maxTokens
        repeatPenalty = settings.repeatPenalty
        enableThinking = settings.enableThinking
        systemPrompt = settings.systemPrompt
        kvCacheTypeK = settings.kvCacheTypeK
        kvCacheTypeV = settings.kvCacheTypeV

        // Detect current preset
        selectedPreset = detectPreset(from: settings)
    }

    private func detectPreset(from settings: ModelSettings) -> ModelSettingsPreset {
        for preset in ModelSettingsPreset.allCases where preset != .custom {
            let presetSettings = preset.settings
            if settings.temperature == presetSettings.temperature &&
               settings.topP == presetSettings.topP &&
               settings.topK == presetSettings.topK &&
               settings.maxTokens == presetSettings.maxTokens &&
               settings.repeatPenalty == presetSettings.repeatPenalty {
                return preset
            }
        }
        return .custom
    }

    private func applyPreset(_ preset: ModelSettingsPreset) {
        let settings = preset.settings
        temperature = settings.temperature
        topP = settings.topP
        topK = settings.topK
        maxTokens = settings.maxTokens
        repeatPenalty = settings.repeatPenalty
        enableThinking = settings.enableThinking
        // Keep current system prompt unless preset has one
        if !settings.systemPrompt.isEmpty {
            systemPrompt = settings.systemPrompt
        }
    }

    private func saveSettings() {
        let settings = ModelSettings(
            temperature: temperature,
            topP: topP,
            topK: topK,
            maxTokens: maxTokens,
            repeatPenalty: repeatPenalty,
            enableThinking: enableThinking,
            systemPrompt: systemPrompt,
            kvCacheTypeK: kvCacheTypeK,
            kvCacheTypeV: kvCacheTypeV
        )
        settingsManager.updateSettings(for: modelId, settings: settings)
    }

    private func resetToDefault() {
        settingsManager.resetSettings(for: modelId)
        loadCurrentSettings()
        selectedPreset = .balanced
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let preset: ModelSettingsPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14))
                Text(preset.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.purple.opacity(0.15) : Color(.tertiarySystemBackground))
            )
            .foregroundStyle(isSelected ? .purple : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Parameter Slider

struct ParameterSlider: View {
    let title: String
    let description: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var step: Float = 0.1
    var format: String = "%.1f"
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: format, value))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.purple)
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(value: $value, in: range, step: step)
                .tint(.purple)
                .onChange(of: value) { _, _ in onChange() }
        }
        .padding(16)
    }
}

// MARK: - Parameter Int Slider

struct ParameterIntSlider: View {
    let title: String
    let description: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var onChange: () -> Void = {}

    @State private var sliderValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(value)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.purple)
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(
                value: $sliderValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(.purple)
            .onChange(of: sliderValue) { _, newValue in
                value = Int(newValue)
                onChange()
            }
        }
        .padding(16)
        .onAppear {
            sliderValue = Double(value)
        }
        .onChange(of: value) { _, newValue in
            if Int(sliderValue) != newValue {
                sliderValue = Double(newValue)
            }
        }
    }
}

// MARK: - Quick Prompt Button

struct QuickPromptButton: View {
    let title: String
    let prompt: String
    let onSelect: (String) -> Void

    var body: some View {
        Button(action: { onSelect(prompt) }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .foregroundStyle(.purple)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    ModelSettingsView(modelId: "qwen3-1.7b", modelName: "Qwen3 1.7B")
}
