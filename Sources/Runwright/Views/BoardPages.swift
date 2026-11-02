import RunwrightCore
import RunwrightGitHub
import RunwrightGitLab
import SlateDesign
import SwiftUI

/// The overview: GitLab's runner, then GitHub's when there are any.
struct OverviewPage: View {
    @Environment(GitHubProvider.self) private var github

    var body: some View {
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            GitLabOverview()
            if github.isSetUp { GitHubOverview() }
        }
    }
}

/// Every provider's running jobs and events.
struct JobsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(GitHubProvider.self) private var github

    var body: some View {
        let status = model.status
        // Only GitLab's live status counts finished jobs.
        let rate = "\(String(format: "%.1f", gitlab.store.jobsPerMinute)) finished per minute\(github.isSetUp ? " on GitLab" : "")"
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: "Jobs", subtitle: "\(status.busySlots) running · \(rate)")
            Pane("Running jobs", icon: "list.bullet.rectangle", padded: false) { RunningJobsList().padding(SlateSpacing.sm) }
            Pane("Activity feed", icon: "clock.arrow.circlepath", padded: false) { EventFeed(events: status.events) }
        }
    }
}

/// Failures from every provider: GitLab's reasons and API health, then
/// GitHub's failed jobs when there are GitHub runners.
struct FailuresPage: View {
    @Environment(GitLabProvider.self) private var gitlab
    @Environment(GitHubProvider.self) private var github

    var body: some View {
        VStack(alignment: .leading, spacing: SlateSpacing.lg) {
            ContentHeader(title: "Failures", subtitle: "\(Int(gitlab.store.snapshot?.failedTotal ?? 0)) failed jobs since the runner started")
            GitLabFailures()
            if github.isSetUp {
                Pane("GitHub Action runner failures", icon: "xmark.octagon") { GitHubFailures() }
            }
        }
    }
}
