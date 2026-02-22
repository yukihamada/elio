import SwiftUI

/// Real-time interpreter view with speech recognition and translation
struct InterpreterView: View {
    @StateObject private var interpreter = InterpreterManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Language selector
                languageSelector

                // Status indicator
                statusIndicator

                // Recognized text card
                if !interpreter.recognizedText.isEmpty {
                    recognizedTextCard
                }

                // Translation card
                if !interpreter.translatedText.isEmpty {
                    translatedTextCard
                }

                Spacer()

                // Error message
                if let error = interpreter.errorMessage {
                    errorBanner(error)
                }

                // Control buttons
                controlButtons
            }
            .navigationTitle("Interpreter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        interpreter.stopInterpreting()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Language Selector

    private var languageSelector: some View {
        HStack(spacing: 16) {
            // Source language
            Menu {
                ForEach(Language.allCases) { lang in
                    Button {
                        interpreter.sourceLanguage = lang
                    } label: {
                        HStack {
                            Text(lang.flag)
                            Text(lang.displayName)
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Text(interpreter.sourceLanguage.flag)
                        .font(.system(size: 40))
                    Text(interpreter.sourceLanguage.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            // Swap button
            Button(action: { interpreter.swapLanguages() }) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            // Target language
            Menu {
                ForEach(Language.allCases) { lang in
                    Button {
                        interpreter.targetLanguage = lang
                    } label: {
                        HStack {
                            Text(lang.flag)
                            Text(lang.displayName)
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Text(interpreter.targetLanguage.flag)
                        .font(.system(size: 40))
                    Text(interpreter.targetLanguage.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            if interpreter.isListening {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(1.5)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: interpreter.isListening)
                    Text("Listening...")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            } else if interpreter.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Translating...")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            } else if interpreter.isSpeaking {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.green)
                    Text("Speaking...")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            } else if interpreter.isInterpreting {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 30)
        .padding(.horizontal)
    }

    // MARK: - Text Cards

    private var recognizedTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(interpreter.sourceLanguage.flag)
                Text("Recognized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    interpreter.speakText(interpreter.recognizedText, language: interpreter.sourceLanguage)
                }) {
                    Image(systemName: "speaker.wave.2")
                }
            }

            Text(interpreter.recognizedText)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var translatedTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(interpreter.targetLanguage.flag)
                Text("Translation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    interpreter.speakText(interpreter.translatedText, language: interpreter.targetLanguage)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.blue)
                }
            }

            Text(interpreter.translatedText)
                .font(.body)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.cyan.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        VStack(spacing: 16) {
            // Auto-speak toggle
            Toggle("Auto-speak translation", isOn: $interpreter.autoSpeak)
                .padding(.horizontal)

            // Start/Stop button
            Button(action: {
                if interpreter.isInterpreting {
                    interpreter.stopInterpreting()
                } else {
                    Task {
                        await interpreter.startInterpreting()
                    }
                }
            }) {
                HStack {
                    Image(systemName: interpreter.isInterpreting ? "stop.fill" : "mic.fill")
                    Text(interpreter.isInterpreting ? "Stop Interpreting" : "Start Interpreting")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(interpreter.isInterpreting ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") {
                interpreter.errorMessage = nil
            }
            .font(.caption)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Compact Widget for ChatView

struct InterpreterQuickAccessButton: View {
    @State private var showingInterpreter = false

    var body: some View {
        Button(action: { showingInterpreter = true }) {
            HStack(spacing: 6) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Interpreter")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(20)
        }
        .sheet(isPresented: $showingInterpreter) {
            InterpreterView()
        }
    }
}

#Preview {
    InterpreterView()
}
