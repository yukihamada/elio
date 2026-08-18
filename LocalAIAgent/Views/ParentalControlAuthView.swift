
import SwiftUI
import LocalAuthentication

struct ParentalControlAuthView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var authenticationError: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text(String(localized: "parental.auth.title"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "parental.auth.description"))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let error = authenticationError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(action: authenticate) {
                Text(String(localized: "parental.auth.button"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.red)
                    )
            }
            .padding(.horizontal)

            Button(String(localized: "common.cancel")) {
                appState.isParentalControlEnabled = false
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear(perform: authenticate)
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "parental.auth.reason")) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        appState.isParentalControlEnabled = true
                        dismiss()
                    } else {
                        self.authenticationError = authError?.localizedDescription ?? String(localized: "parental.auth.failed")
                        appState.isParentalControlEnabled = false
                        dismiss()
                    }
                }
            }
        } else {
            self.authenticationError = String(localized: "parental.auth.no_biometrics")
            appState.isParentalControlEnabled = false
            dismiss()
        }
    }
}
