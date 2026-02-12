import SwiftUI

/// Quick action buttons shown when emergency mode is active
struct EmergencyQuickActionsView: View {
    let onAction: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                emergencyButton(
                    title: String(localized: "emergency.action.firstaid"),
                    icon: "cross.case.fill",
                    color: .red,
                    message: String(localized: "emergency.action.firstaid.message")
                )

                emergencyButton(
                    title: String(localized: "emergency.action.disaster"),
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    message: String(localized: "emergency.action.disaster.message")
                )

                emergencyButton(
                    title: String(localized: "emergency.action.factcheck"),
                    icon: "checkmark.shield.fill",
                    color: .blue,
                    message: String(localized: "emergency.action.factcheck.message")
                )

                emergencyButton(
                    title: String(localized: "emergency.action.contacts"),
                    icon: "phone.fill",
                    color: .green,
                    message: String(localized: "emergency.action.contacts.message")
                )

                emergencyButton(
                    title: String(localized: "emergency.action.evacuation"),
                    icon: "figure.walk",
                    color: .purple,
                    message: String(localized: "emergency.action.evacuation.message")
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func emergencyButton(title: String, icon: String, color: Color, message: String) -> some View {
        Button(action: { onAction(message) }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
    }
}

/// Emergency mode status banner
struct EmergencyModeBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
            Text(String(localized: "emergency.mode.active"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [.red, .orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}
