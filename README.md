<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="Runwright icon">
</p>

<h1 align="center">Runwright</h1>

<p align="center">Set up, register and look after self-hosted CI runners on your Mac, without the terminal.</p>

<p align="center"><a href="#install"><b>Build for macOS</b></a> · GitLab Runner · GitHub Actions</p>

---

## Why

Putting a CI runner on a Mac means a download, a token, a config file, a service and a `PATH` that never quite matches your Terminal's. Then it's a black box: you find out it stopped, or that a job can't find `flutter`, when a pipeline fails.

Runwright is a Mac app that does that setup for you and then shows you what your runners are doing. It lives in the menu bar. Everything is local: no Grafana, no Docker, and no API token kept.

## What it does

- **Register a runner in a few clicks.** Paste the token GitLab or GitHub shows when you create a runner. Runwright installs or downloads the runner, registers it and starts it. The token goes straight to the runner's own tooling; Runwright doesn't keep it.
- **See every runner on the Mac.** Homebrew services, runners with their own binary and `config.toml`, and GitHub Actions runner folders (`~/actions-runner` and its siblings), running or stopped.
- **Start, stop and restart.** As a background service that outlives the app, or inside Runwright with the output in a log. Switch single runners on and off.
- **Live status.** Running jobs and their current step, slots in use, failures, job durations and API health, refreshed every few seconds. Watch a job's log live on the runner's page.
- **Missing tools.** Spots tools your Terminal has that jobs can't find, such as `flutter`, `node` or `docker`. One click gives jobs your Terminal's `PATH`.
- **Updates.** Tells you when a newer GitHub Actions runner release is out.
- **Alerts.** Notifies you when a job fails or a runner goes offline.
- **Demo mode** to try it without a runner.

| | GitLab Runner | GitHub Actions |
|---|---|---|
| Install the runner | Homebrew `gitlab-runner` | downloads `actions/runner` |
| Register | runner authentication token (`glrt-…`) from *Settings → CI/CD → Runners → New project runner* | token from *Settings → Actions → Runners → New self-hosted runner* |
| Run | `brew services` or in the app | `svc.sh` (launchd) or `run.sh` in the app |
| Live metrics | metrics endpoint, switched on for you | from the runner's logs |

## Private repositories only

Only register a runner with a private GitHub repository or a private GitLab project.

A runner on your Mac runs every job it is given as your macOS user, with your files, your keychain and your network. On a public repository, anyone can open a pull request or merge request that changes the pipeline, and their code then runs on your Mac. GitHub advises against self-hosted runners on public repositories for this reason.

- Register runners per repository or project, not for a whole organization or group that has public repositories in it.
- Keep the people who can push to the repository to people you trust with your Mac.
- If a repository is made public, remove its runner first.

## Install

There are no prebuilt downloads: you build Runwright from source on your own Mac. Requires macOS 14 or later and Xcode 16+ (Swift 6).

```sh
git clone https://github.com/krnblds/runwright.git
cd runwright
scripts/bundle.sh --install   # builds Runwright.app and copies it to /Applications
```

Then open Runwright from Applications; it lives in the menu bar. Running `scripts/bundle.sh` without `--install` leaves the app and a DMG in `build/`.

To update, `git pull` and run `scripts/bundle.sh --install` again.

The app's version is the `v*` tag on `HEAD` without its `v`, or `VERSION=1.2.0 scripts/bundle.sh` to set it. Untagged builds are `0.0.0`.

### Run from source

```sh
swift run Runwright   # or open Package.swift in Xcode and run the Runwright scheme
swift test
```

This runs a bare executable rather than the app bundle, so it has no icon and some macOS features, such as notifications, may not work. Use `scripts/bundle.sh` for everyday use.

## How it works

| Reads | For |
|---|---|
| `http://127.0.0.1:9252/metrics` (`listen_address`) | live jobs, counters, histogram |
| `~/.gitlab-runner/config.toml` and other runners' configs | registered runners, executor, `PATH` |
| `brew services`, `ps` | what's running and how |
| GitHub runner folders: `.runner`, `_diag` logs | registered GitHub runners, their jobs and version |
| `launchctl` | GitHub runners installed as a service |

Runwright never reads a runner's credentials. It only changes `config.toml` when you ask it to (turn on live status, use your Terminal's tools). It keeps a `.runwright-backup` copy next to the file each time.

## Project layout

```
Sources/SlateDesign            Command Slate design system in SwiftUI (Carbon theme)
Sources/RunwrightCore          shared, provider-neutral pieces: processes, Terminal tools,
                               events, and the RunnerProvider protocol with RunnerSummary
Sources/RunwrightGitLab        gitlab-runner: metrics parser, models, store, runner control,
                               and GitLabProvider
Sources/RunwrightGitHub        GitHub Actions self-hosted runners: finding runner folders,
                               .runner and _diag log parsing, svc.sh / run.sh control, and
                               GitHubProvider (local only: no GitHub API, no tokens)
Sources/Runwright              the app: menu bar panel, dashboard, settings
Sources/Runwright/Views/GitLab views only GitLab has: metrics charts, setup, runner pages
Sources/Runwright/Views/GitHub views only GitHub has: setup steps, runner page, sidebar section
Tests/RunwrightCoreTests       tests for the shared helpers and combined status
Tests/RunwrightGitLabTests     parser, store, config and provider tests with real fixtures
Tests/RunwrightGitHubTests     .runner, diag log, ps / launchctl, folder and provider tests
scripts                        bundle.sh, make-icon.swift
```

```sh
swift test
```

## Roadmap

- Buildkite runners
- Project and pipeline names via the GitLab API (opt-in token, stored in the Keychain)
- Job history that survives a restart

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
