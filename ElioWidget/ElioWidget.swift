import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct ElioEntry: TimelineEntry {
    let date: Date
    let modelName: String?
    let isModelLoaded: Bool
    let recentConversationTitle: String?
    let configuration: ConfigurationAppIntent
}

// MARK: - Timeline Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ElioEntry {
        ElioEntry(
            date: Date(),
            modelName: "Elio",
            isModelLoaded: true,
            recentConversationTitle: nil,
            configuration: ConfigurationAppIntent()
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> ElioEntry {
        ElioEntry(
            date: Date(),
            modelName: "Elio",
            isModelLoaded: true,
            recentConversationTitle: "Sample conversation",
            configuration: configuration
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<ElioEntry> {
        // Load data from shared container
        let snapshot = SharedDataManager.loadAppStateSnapshot()

        let entry = ElioEntry(
            date: Date(),
            modelName: snapshot?.modelName ?? "Elio",
            isModelLoaded: snapshot?.isModelLoaded ?? false,
            recentConversationTitle: snapshot?.recentConversationTitle,
            configuration: configuration
        )

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Configuration Intent

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Elio Widget"
    static var description = IntentDescription("Quick access to AI assistant")
}

// MARK: - Widget Views

struct ElioWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: ElioEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Spacer()

                Circle()
                    .fill(entry.isModelLoaded ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            Spacer()

            Text("Elio")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.modelName ?? "AI Assistant")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Open app button
            Link(destination: URL(string: "elio://ask")!) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                    Text("Ask")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: ElioEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Circle()
                        .fill(entry.isModelLoaded ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }

                Text("Elio")
                    .font(.headline)

                Text(entry.modelName ?? "AI Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let title = entry.recentConversationTitle {
                    Divider()
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Right side - Actions
            VStack(spacing: 8) {
                Link(destination: URL(string: "elio://ask")!) {
                    VStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.title2)
                        Text("New Chat")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.blue)

                Link(destination: URL(string: "elio://conversations")!) {
                    VStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                        Text("History")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: 80)
        }
        .padding()
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: ElioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text("Elio")
                        .font(.headline)
                    Text(entry.modelName ?? "AI Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isModelLoaded ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(entry.isModelLoaded ? "Ready" : "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Recent conversation
            if let title = entry.recentConversationTitle {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "elio://conversation")!) {
                        HStack {
                            Image(systemName: "bubble.left")
                            Text(title)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .foregroundStyle(.primary)
                }
            }

            Spacer()

            // Quick actions
            HStack(spacing: 12) {
                Link(destination: URL(string: "elio://ask")!) {
                    HStack {
                        Image(systemName: "plus.bubble.fill")
                        Text("New Chat")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Link(destination: URL(string: "elio://conversations")!) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("History")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget Definition

struct ElioWidget: Widget {
    let kind: String = "ElioWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            ElioWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Elio")
        .description("Quick access to AI assistant")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ElioWidget()
} timeline: {
    ElioEntry(date: .now, modelName: "Llama 3.2", isModelLoaded: true, recentConversationTitle: nil, configuration: ConfigurationAppIntent())
}

#Preview(as: .systemMedium) {
    ElioWidget()
} timeline: {
    ElioEntry(date: .now, modelName: "Llama 3.2", isModelLoaded: true, recentConversationTitle: "How to cook pasta", configuration: ConfigurationAppIntent())
}

#Preview(as: .systemLarge) {
    ElioWidget()
} timeline: {
    ElioEntry(date: .now, modelName: "Llama 3.2", isModelLoaded: true, recentConversationTitle: "What is the meaning of life?", configuration: ConfigurationAppIntent())
}
