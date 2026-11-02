import Foundation
import RunwrightCore

/// A pretend runner that writes realistic `/metrics` text, so the app can be
/// tried before a real runner is installed. It goes through the same parser
/// as the real endpoint.
public final class DemoMetricsSource: MetricsSource, @unchecked Sendable {
    private struct Job {
        var runner: String
        var stage: String
        var executorStage: String
        var endsAt: Date
        var started: Date
        var fails: Bool
    }

    private let lock = NSLock()
    private var jobs: [Job] = []
    private var jobsTotal: [String: Int] = [:]
    private var failed: [String: Int] = [:]
    private var durations: [Double] = []
    private var warnings = 0
    private var apiOK = 40
    private var apiBad = 0
    private let runners = ["mac-shell", "mac-docker"]
    // A real runner reports the job's step in `stage` and what the executor
    // is doing in `executor_stage`; both move as the job runs.
    private let stages = ["prepare_script", "get_sources", "restore_cache", "step_script", "archive_cache", "upload_artifacts_on_success"]
    private let executorStages = ["prepare", "build", "build", "build", "build", "finish"]
    private let reasons = ["script_failure", "job_execution_timeout", "runner_system_failure"]
    private let bounds: [Double] = [30, 60, 300, 600, 1800, 3600, 7200]

    public init() {}

    public func fetch() async throws -> String {
        lock.withLock {
            tick(now: .now)
            return render(now: .now)
        }
    }

    private func tick(now: Date) {
        // Finish jobs whose time is up.
        for job in jobs where job.endsAt <= now {
            jobsTotal[job.runner, default: 0] += 1
            durations.append(now.timeIntervalSince(job.started) * 12)
            if job.fails { failed[reasons.randomElement()!, default: 0] += 1 }
        }
        jobs.removeAll { $0.endsAt <= now }

        // Start new ones now and then, up to the concurrency limit.
        if jobs.count < 4, Double.random(in: 0...1) < 0.35 {
            let started = now
            jobs.append(Job(
                runner: runners.randomElement()!,
                stage: stages[0],
                executorStage: executorStages[0],
                endsAt: now.addingTimeInterval(.random(in: 8...40)),
                started: started,
                fails: Double.random(in: 0...1) < 0.15
            ))
        }
        // Move running jobs through executor stages.
        for i in jobs.indices {
            let progress = now.timeIntervalSince(jobs[i].started) / jobs[i].endsAt.timeIntervalSince(jobs[i].started)
            let idx = min(stages.count - 1, Int(progress * Double(stages.count)))
            jobs[i].stage = stages[idx]
            jobs[i].executorStage = executorStages[idx]
        }
        apiOK += Int.random(in: 1...3)
        if Double.random(in: 0...1) < 0.04 { apiBad += 1 }
        if Double.random(in: 0...1) < 0.03 { warnings += 1 }
    }

    private func render(now: Date) -> String {
        var out = """
        # HELP gitlab_runner_version_info A metric with a constant '1' value labeled by different build stats fields.
        # TYPE gitlab_runner_version_info gauge
        gitlab_runner_version_info{architecture="arm64",branch="19-5-stable",built_at="2026-10-20 00:00:00 +0000",go_version="go1.24.4",name="gitlab-runner",os="darwin",revision="demo1234",version="19.5.2"} 1
        # TYPE gitlab_runner_concurrent gauge
        gitlab_runner_concurrent 4

        """
        for r in runners {
            out += "gitlab_runner_limit{runner=\"\(r.prefix(8))\",runner_name=\"\(r)\",system_id=\"s_demo\"} 2\n"
            out += "gitlab_runner_jobs_total{runner=\"\(r.prefix(8))\",runner_name=\"\(r)\",system_id=\"s_demo\"} \(jobsTotal[r, default: 0])\n"
        }
        var groups: [String: Int] = [:]
        for j in jobs { groups["\(j.runner)|\(j.stage)|\(j.executorStage)", default: 0] += 1 }
        for (key, count) in groups.sorted(by: { $0.key < $1.key }) {
            let p = key.split(separator: "|").map(String.init)
            out += "gitlab_runner_jobs{executor_stage=\"\(p[2])\",runner=\"\(p[0].prefix(8))\",runner_name=\"\(p[0])\",stage=\"\(p[1])\",state=\"running\",system_id=\"s_demo\"} \(count)\n"
        }
        for reason in reasons {
            out += "gitlab_runner_failed_jobs_total{failure_reason=\"\(reason)\",runner=\"demo\",runner_name=\"mac-shell\",system_id=\"s_demo\"} \(failed[reason, default: 0])\n"
        }
        out += "gitlab_runner_errors_total{level=\"warning\"} \(warnings)\n"
        out += "gitlab_runner_errors_total{level=\"error\"} 0\n"
        out += "gitlab_runner_api_request_statuses_total{endpoint=\"request_job\",runner=\"demo\",status=\"200\"} \(apiOK)\n"
        out += "gitlab_runner_api_request_statuses_total{endpoint=\"request_job\",runner=\"demo\",status=\"204\"} \(apiOK * 3)\n"
        out += "gitlab_runner_api_request_statuses_total{endpoint=\"update_job\",runner=\"demo\",status=\"500\"} \(apiBad)\n"
        for b in bounds {
            let n = durations.filter { $0 <= b }.count
            out += "gitlab_runner_job_duration_seconds_bucket{runner=\"demo\",le=\"\(Int(b))\"} \(n)\n"
        }
        out += "gitlab_runner_job_duration_seconds_bucket{runner=\"demo\",le=\"+Inf\"} \(durations.count)\n"
        out += "gitlab_runner_job_duration_seconds_sum{runner=\"demo\"} \(durations.reduce(0, +))\n"
        out += "gitlab_runner_job_duration_seconds_count{runner=\"demo\"} \(durations.count)\n"
        return out
    }
}
