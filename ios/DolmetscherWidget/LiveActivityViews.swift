// LiveActivityViews.swift – Live-Aktivität beim Zuhören: Sperrbildschirm und Dynamic Island mit letztem Satz,
// Mikrofonstatus und Stopp-Knopf.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningActivityAttributes.self) { context in
            LiveLockView(pair: context.attributes.pair, state: context.state)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { LiveStatusIcon(status: context.state.status) }
                DynamicIslandExpandedRegion(.trailing) { StopButton() }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusText).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) { LastSentence(state: context.state, lines: 2) }
            } compactLeading: {
                LiveStatusIcon(status: context.state.status)
            } compactTrailing: {
                Text(context.state.dstFlag)
            } minimal: {
                LiveStatusIcon(status: context.state.status)
            }
        }
    }
}

struct LiveStatusIcon: View {
    let status: ListeningActivityAttributes.Status
    private var tint: Color { status == .hearing ? .green : status == .paused ? .gray : .orange }
    var body: some View {
        Image(systemName: status.symbol).foregroundStyle(tint)
    }
}

struct StopButton: View {
    var body: some View {
        Button(intent: StopListeningIntent()) {
            Image(systemName: "stop.fill")
        }
        .tint(.red)
        .accessibilityLabel(WidgetTexts.text("w_stop"))
    }
}

struct LastSentence: View {
    let state: ListeningActivityAttributes.ContentState
    var lines = 3

    var body: some View {
        if state.translation.isEmpty {
            Text(WidgetTexts.text("w_waiting")).font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.dstFlag) \(state.translation)").font(.headline).lineLimit(lines)
                Text("\(state.srcFlag) \(state.source)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LiveLockView: View {
    let pair: String
    let state: ListeningActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LiveStatusIcon(status: state.status)
                Text(state.statusText).font(.subheadline.weight(.semibold))
                Spacer()
                Text(pair).font(.caption)
                StopButton()
            }
            LastSentence(state: state)
        }
        .foregroundStyle(.white)
    }
}
