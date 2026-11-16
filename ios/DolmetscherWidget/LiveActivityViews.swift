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

