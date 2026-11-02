import Foundation
import RunwrightCore

/// Turns raw samples into a `RunnerSnapshot`.
public enum SnapshotMapper {
    public static func snapshot(from samples: [Sample], at date: Date = .now) -> RunnerSnapshot {
        var s = RunnerSnapshot(takenAt: date)
        var buckets: [HistogramBucket] = []

        for sample in samples {
            let l = sample.labels
            switch sample.name {
            case "gitlab_runner_version_info":
                s.version = l["version"]
                s.revision = l["revision"]
                s.architecture = l["architecture"]
                s.os = l["os"]
            case "gitlab_runner_concurrent":
                s.concurrent = Int(sample.value)
            case "gitlab_runner_limit":
                s.limits[runnerName(l), default: 0] += Int(sample.value)
            case "gitlab_runner_jobs":
                let count = Int(sample.value)
                guard count > 0 else { continue }
                s.jobs.append(JobGroup(
                    runner: runnerName(l),
                    state: l["state"] ?? "",
                    stage: l["stage"] ?? "",
                    executorStage: l["executor_stage"] ?? "",
                    count: count
                ))
            case "gitlab_runner_jobs_total":
                s.jobsTotal += sample.value
            case "gitlab_runner_failed_jobs_total":
                s.failedTotal += sample.value
                s.failuresByReason[l["failure_reason"] ?? "unknown", default: 0] += sample.value
            case "gitlab_runner_errors_total":
                s.errorsByLevel[l["level"] ?? "error", default: 0] += sample.value
            case "gitlab_runner_api_request_statuses_total":
                let key = "\(l["endpoint"] ?? "?") \(l["status"] ?? "0")"
                s.apiStatuses[key, default: 0] += sample.value
            case "gitlab_runner_job_duration_seconds_bucket":
                guard let le = l["le"].flatMap({ PrometheusParser.parseValue(Substring($0)) }) else { continue }
                // Sum across runners: merge buckets that share a bound.
                if let idx = buckets.firstIndex(where: { $0.upperBound == le }) {
                    buckets[idx].cumulativeCount += sample.value
                } else {
                    buckets.append(HistogramBucket(upperBound: le, cumulativeCount: sample.value))
                }
            case "gitlab_runner_job_duration_seconds_sum":
                s.duration.sum += sample.value
            case "gitlab_runner_job_duration_seconds_count":
                s.duration.count += sample.value
            default:
                continue
            }
        }

        s.duration.buckets = buckets.sorted { $0.upperBound < $1.upperBound }
        s.jobs.sort { ($0.runner, $0.stage) < ($1.runner, $1.stage) }
        // Unused failure reasons clutter the list.
        s.failuresByReason = s.failuresByReason.filter { $0.value > 0 }
        return s
    }

    /// Newer runners label metrics with `runner_name`; older ones only have the
    /// short token in `runner`.
    static func runnerName(_ labels: [String: String]) -> String {
        if let name = labels["runner_name"], !name.isEmpty { return name }
        return labels["runner"] ?? "runner"
    }
}
