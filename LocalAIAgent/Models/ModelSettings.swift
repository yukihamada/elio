import Foundation
import SwiftUI

/// Per-model generation settings
struct ModelSettings: Codable, Equatable {
    var temperature: Float
    var topP: Float
    var topK: Int
    var maxTokens: Int
    var repeatPenalty: Float
    var enableThinking: Bool
    var systemPrompt: String

    /// Default settings
    static let `default` = ModelSettings(
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        maxTokens: 1024,
        repeatPenalty: 1.1,
        enableThinking: true,
        systemPrompt: ""
    )

    /// Preset for creative writing
    static let creative = ModelSettings(
        temperature: 0.9,
        topP: 0.95,
        topK: 50,
        maxTokens: 2048,
        repeatPenalty: 1.05,
        enableThinking: true,
        systemPrompt: ""
    )

    /// Preset for precise/factual responses
    static let precise = ModelSettings(
        temperature: 0.3,
        topP: 0.8,
        topK: 20,
        maxTokens: 512,
        repeatPenalty: 1.15,
        enableThinking: false,
        systemPrompt: ""
    )

    /// Preset for code generation
    static let coding = ModelSettings(
        temperature: 0.2,
        topP: 0.85,
        topK: 30,
        maxTokens: 2048,
        repeatPenalty: 1.1,
        enableThinking: false,
        systemPrompt: ""
    )

    /// Preset for Japanese conversation
    static let japanese = ModelSettings(
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        maxTokens: 1024,
        repeatPenalty: 1.1,
        enableThinking: true,
        systemPrompt: "あなたは日本語に特化したAIアシスタントです。自然で丁寧な日本語で回答してください。"
    )
}

/// Available presets
enum ModelSettingsPreset: String, CaseIterable, Identifiable {
    case custom = "custom"
    case balanced = "balanced"
    case creative = "creative"
    case precise = "precise"
    case coding = "coding"
    case japanese = "japanese"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .custom: return String(localized: "settings.preset.custom")
        case .balanced: return String(localized: "settings.preset.balanced")
        case .creative: return String(localized: "settings.preset.creative")
        case .precise: return String(localized: "settings.preset.precise")
        case .coding: return String(localized: "settings.preset.coding")
        case .japanese: return String(localized: "settings.preset.japanese")
        }
    }

    var icon: String {
        switch self {
        case .custom: return "slider.horizontal.3"
        case .balanced: return "scale.3d"
        case .creative: return "paintbrush.fill"
        case .precise: return "scope"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .japanese: return "character.ja"
        }
    }

    var settings: ModelSettings {
        switch self {
        case .custom: return .default
        case .balanced: return .default
        case .creative: return .creative
        case .precise: return .precise
        case .coding: return .coding
        case .japanese: return .japanese
        }
    }
}

/// Manager for storing and retrieving per-model settings
@MainActor
final class ModelSettingsManager: ObservableObject {
    static let shared = ModelSettingsManager()

    @Published private(set) var modelSettings: [String: ModelSettings] = [:]

    private let settingsKey = "modelSettings"
    private let modelLoader = ModelLoader()

    private init() {
        loadSettings()
    }

    /// Get settings for a specific model (returns model-specific defaults if not customized)
    func settings(for modelId: String) -> ModelSettings {
        if let customSettings = modelSettings[modelId] {
            return customSettings
        }
        // Return default settings with model-specific maxTokens
        return defaultSettings(for: modelId)
    }

    /// Get default settings with model-specific maxTokens
    func defaultSettings(for modelId: String) -> ModelSettings {
        let recommendedMaxTokens = modelLoader.getModelInfo(modelId)?.recommendedMaxTokens ?? 2048
        return ModelSettings(
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
            maxTokens: recommendedMaxTokens,
            repeatPenalty: 1.1,
            enableThinking: true,
            systemPrompt: ""
        )
    }

    /// Update settings for a specific model
    func updateSettings(for modelId: String, settings: ModelSettings) {
        modelSettings[modelId] = settings
        saveSettings()
    }

    /// Apply a preset to a model
    func applyPreset(_ preset: ModelSettingsPreset, to modelId: String) {
        var settings = preset.settings
        // Keep custom system prompt if exists
        if preset != .custom, let existing = modelSettings[modelId] {
            if !existing.systemPrompt.isEmpty && settings.systemPrompt.isEmpty {
                settings.systemPrompt = existing.systemPrompt
            }
        }
        modelSettings[modelId] = settings
        saveSettings()
    }

    /// Reset settings for a model to model-specific defaults
    func resetSettings(for modelId: String) {
        modelSettings[modelId] = defaultSettings(for: modelId)
        saveSettings()
    }

    /// Check if model has custom settings
    func hasCustomSettings(for modelId: String) -> Bool {
        modelSettings[modelId] != nil
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: data) else {
            return
        }
        modelSettings = decoded
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(modelSettings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
