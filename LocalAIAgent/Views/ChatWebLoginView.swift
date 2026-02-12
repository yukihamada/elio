import SwiftUI

/// Login / Register sheet for chatweb.ai account linking
struct ChatWebLoginView: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.indigo)
                        Text("chatweb.ai")
                            .font(.title2.bold())
                        Text(String(localized: "login.subtitle", defaultValue: "Sign in to sync conversations across devices"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section {
                    TextField(
                        String(localized: "login.email", defaultValue: "Email"),
                        text: $email
                    )
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                    SecureField(
                        String(localized: "login.password", defaultValue: "Password"),
                        text: $password
                    )
                    .textContentType(isRegistering ? .newPassword : .password)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(isRegistering
                                ? String(localized: "login.register", defaultValue: "Create Account")
                                : String(localized: "login.signin", defaultValue: "Sign In"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)

                    Button(action: { isRegistering.toggle() }) {
                        Text(isRegistering
                            ? String(localized: "login.switch_to_login", defaultValue: "Already have an account? Sign In")
                            : String(localized: "login.switch_to_register", defaultValue: "Don't have an account? Create one"))
                            .font(.footnote)
                            .foregroundColor(.indigo)
                    }
                    .frame(maxWidth: .infinity)
                }

                Section {
                    VStack(spacing: 4) {
                        Text(String(localized: "login.benefits.title", defaultValue: "Benefits of signing in:"))
                            .font(.footnote.bold())
                        VStack(alignment: .leading, spacing: 2) {
                            Label(String(localized: "login.benefit.sync", defaultValue: "Sync conversations with chatweb.ai"),
                                  systemImage: "arrow.triangle.2.circlepath")
                            Label(String(localized: "login.benefit.credits", defaultValue: "Use cloud AI credits"),
                                  systemImage: "bolt.fill")
                            Label(String(localized: "login.benefit.backup", defaultValue: "Back up local conversations"),
                                  systemImage: "icloud.and.arrow.up")
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isRegistering
                ? String(localized: "login.title.register", defaultValue: "Create Account")
                : String(localized: "login.title.login", defaultValue: "Sign In"))
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                if isRegistering {
                    // Register first, then login
                    try await register()
                }
                try await syncManager.login(email: email, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func register() async throws {
        let url = URL(string: "\(syncManager.baseURL)/api/v1/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        // 200 = success, 409 = already exists (ok for login flow)
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 409 {
            return
        }

        if httpResponse.statusCode == 429 {
            throw SyncError.rateLimited
        }

        // Parse error message
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            throw SyncError.serverError(httpResponse.statusCode)
        }

        throw SyncError.serverError(httpResponse.statusCode)
    }
}
