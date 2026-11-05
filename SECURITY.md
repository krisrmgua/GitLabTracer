# Security

Pipeline Tracer does not store your GitLab or GitHub password or personal access token. `glab` and `gh` do. This app stores preferences and the ids of failure notifications it has already shown.

## Reporting

Open a GitHub issue for a vulnerability in this repository. Do not paste tokens, job logs, or private repository contents. Describe the behavior and the impact.

## What the app stores

The Electron app keeps one JSON file, `pipelinetracer.json`, under the app data folder (`~/Library/Application Support/Pipeline Tracer/data/` on macOS, `%APPDATA%\Pipeline Tracer\data\` on Windows). It holds the refresh interval, the pipeline window, whether the merge button is available, which repos list every open request, whether the panel reopens where you left it, the Windows start-at-login choice, and the failure ids already announced. Those are settings, not credentials. On macOS the file is written with mode `600`.

The legacy Swift app in `menubar/` kept the same settings in the UserDefaults domain `com.kris.pipelinetracer`.

Job logs are shown in the panel and can be copied. They are not written to disk. A pipeline that prints a secret will show that secret here, the same way GitLab or GitHub would on the job page. GitHub log downloads that come back as a zip are not unpacked.

## How commands run

`glab` and `gh` are found by searching `PATH` plus the usual install folders (Homebrew on macOS; winget, Scoop, Chocolatey, and the GitHub CLI installer on Windows), then started directly with an argument array. No shell is involved, so nothing in an API response is ever interpreted as a command. On Windows only a real `glab.exe` or `gh.exe` is accepted, never a `.cmd` or `.bat` shim.

The panel never sends API paths to the main process. It sends the key of a pipeline or request the main process already loaded, and the main process builds the call from its own copy. Project ids, merge-request iids, and Actions run and job ids are numbers from the API. A GitHub repo is used in a path only when it is `owner/name` made of letters, numbers, `.`, `_`, and `-`. A merge sends the source SHA from a fresh fetch, and only after the host still reports the request as open, not a draft, and mergeable. GitHub's call is `PUT /repos/{owner}/{repo}/pulls/{n}/merge` with that SHA. Close is a `PATCH` that sets `state` to `closed`. Neither call deletes the branch. The repo name is checked before it is placed in the path, and the SHA has to be hexadecimal.

Notification clicks, and the in-app open buttons, open a URL only when the scheme is `https`, there are no credentials in the URL, and the host is `gitlab.com` or `github.com`.

The panel runs with context isolation on and Node integration off, behind a Content Security Policy that only allows the app's own scripts.

## Out of scope

The app is not sandboxed. It needs to run `glab` and `gh`, and open GitLab or GitHub in your browser. Protect those tokens the same way you protect any other credential on this machine (`glab auth status`, `gh auth status`), and revoke a token from the host if it leaks.
