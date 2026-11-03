# Security

Pipeline Tracer does not store your GitLab or GitHub password or personal access token. `glab` and `gh` do. This app stores preferences and the ids of failure notifications it has already shown.

## Reporting

Open a GitHub issue for a vulnerability in this repository. Do not paste tokens, job logs, or private repository contents. Describe the behavior and the impact.

## What the app stores

UserDefaults domain `com.kris.pipelinetracer` holds the refresh interval, the pipeline window, whether the merge button is available, whether the panel reopens where you left it, and the failure ids already announced. Those are settings, not credentials.

Job logs are shown in the panel and can be copied. They are not written to disk. A pipeline that prints a secret will show that secret here, the same way GitLab or GitHub would on the job page. GitHub log downloads that come back as a zip are not unpacked.

## How commands run

`glab` and `gh` are started as `/usr/bin/env` with an argument array. Project ids, merge-request iids, and Actions run and job ids are numbers from the API. A GitHub repo is used in a path only when it is `owner/name` made of letters, numbers, `.`, `_`, and `-`. A merge sends the source SHA from a fresh fetch, and only after the host still reports the request as open, not a draft, and mergeable. GitHub's call is `PUT /repos/{owner}/{repo}/pulls/{n}/merge` with that SHA. Close is a `PATCH` that sets `state` to `closed`. Neither call deletes the branch. The repo name is checked before it is placed in the path, and the SHA has to be hexadecimal.

Notification clicks, and the in-app open buttons, open a URL only when the scheme is `https` and the host is `gitlab.com` or `github.com`.

## Out of scope

The app is not sandboxed. It needs to run `glab` and `gh`, and open GitLab or GitHub in your browser. Protect those tokens the same way you protect any other credential on this Mac (`glab auth status`, `gh auth status`), and revoke a token from the host if it leaks.
