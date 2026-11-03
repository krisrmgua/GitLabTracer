# Security

Pipeline Tracer does not store your GitLab password or personal access token. `glab` does. This app stores preferences and the ids of failure notifications it has already shown.

## Reporting

Open a GitHub issue for a vulnerability in this repository. Do not paste tokens, job logs, or private repository contents. Describe the behavior and the impact.

## What the app stores

UserDefaults domain `com.kris.gitlabtracer` holds the refresh interval, the pipeline window, whether the merge button is available, whether the panel reopens where you left it, and the failure ids already announced. Those are settings, not credentials.

Job logs are shown in the panel and can be copied. They are not written to disk. A pipeline that prints a secret will show that secret here, the same way GitLab's own job page would.

## How commands run

`glab` is started as `/usr/bin/env` with an argument array. Project ids and merge-request iids are numbers from the GitLab API. The merge call sends the source SHA from a fresh fetch, and only after GitLab still reports the request as open, not a draft, and mergeable.

Notification clicks open a URL only when the scheme is `https` and the host is `gitlab.com`.

## Out of scope

The app is not sandboxed. It needs to run `glab` and open GitLab in your browser. Protect the `glab` token the same way you protect any other GitLab credential on this Mac (`glab auth status`, and revoke the token from GitLab if it leaks).
