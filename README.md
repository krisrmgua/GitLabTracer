# Pipeline Tracer

Pipeline Tracer is a macOS menu-bar app for the CI activity that is yours: GitLab.com merge requests and pipelines, GitHub Actions runs on repos you recently pushed, GitHub pull requests you opened, failed jobs, and a merge button that re-checks the host before it merges.

The panel is a dark activity inbox. Failures stay at the top until a later pipeline for that same commit succeeds. Clicking away closes the panel. The next open returns to the overview unless you turn on **Reopen where I left off**.

Requires **macOS 13** or later and the Swift command-line tools. GitLab needs [`glab`](https://gitlab.com/gitlab-org/cli) signed in to `gitlab.com`. GitHub Actions needs the [GitHub CLI](https://cli.github.com/) signed in to `github.com`. Either sign-in is enough. The other host stays empty until you log in.

## Install glab and sign in

Pipeline Tracer does not ask for your GitLab password and it does not store a personal access token. `glab` owns the token. Install it, then log in once:

```bash
brew install glab
glab auth login --hostname gitlab.com
```

When the prompt asks for a token, create one in GitLab under **Preferences → Access Tokens** (or use the browser login `glab` offers). The app calls `glab api` with `--hostname gitlab.com`, so the token has to be for `gitlab.com`. A token for a self-managed hostname is not used.

Check the login before you open the app:

```bash
glab auth status
glab api user
```

`glab api user` should print your GitLab user. Tracer uses that username to list your pipelines. If this command fails, Tracer has nothing to show.

Useful token scopes for what the app does:

- `read_api` to list merge requests, pipelines, jobs, and logs
- `api` if you want the in-app **Merge** button to merge

You can install with `read_api` only. Leave the merge button off in preferences and use GitLab in the browser to merge.

`glab` keeps the token in its own config (`~/.config/glab-cli`). Revoke it from GitLab if it leaks. Tracer never copies it.

## Install gh and sign in

Pipeline Tracer does not ask for a GitHub password and it does not store a personal access token. `gh` owns the token. GitHub is optional. If you only use GitLab, skip this section. If you only use GitHub, you can skip `glab`.

Install the CLI, then log in once to `github.com`:

```bash
brew install gh
gh auth login --hostname github.com
```

Choose **GitHub.com** when the prompt asks which host. A token for GitHub Enterprise is not used. The app always calls `gh api --hostname github.com`.

You can sign in through the browser, or paste a personal access token. Create a token under **Settings → Developer settings → Personal access tokens**.

Check the login before you open the app:

```bash
gh auth status
gh api --hostname github.com user
```

`gh auth status` should list `github.com` and the account you expect. `gh api --hostname github.com user` should print that user as JSON. Tracer caches the login for an hour. If this command fails, GitHub stays empty and GitLab still loads.

What the token needs:

- A classic token with the `repo` scope covers private repos, Actions runs, job logs, pull requests, merge, and close.
- A fine-grained token needs **Actions: Read** and **Pull requests: Read and write** on the repositories you want in the menu. Metadata read is included with a fine-grained token.
- Read-only access still lists runs and pull requests. Merge and close fail until the token can write pull requests.

The app never approves a review, never reruns a workflow, and never deletes the branch when it closes a pull request.

`gh` keeps the token in the macOS keychain, or in `~/.config/gh` when you paste a token. Revoke it from GitHub if it leaks. Tracer never copies it.

After you sign in, open Pipeline Tracer and set **Completion history**. That one control is the window for both GitLab pipelines and GitHub Actions runs. The default is 2 hours. The choices are 1, 2, 4, 6, 8, 12, and 24 hours. A run updated outside that window is hidden. Open pull requests and open merge requests stay listed while they are open. They are not cut off by this timer.

## Install the app

```bash
git clone https://github.com/krisrmgua/PipelineTracer.git
cd PipelineTracer/menubar
./install.sh
```

That builds `Pipeline Tracer.app`, copies it to `~/Applications/Pipeline Tracer.app`, and starts it at login. Run `./install.sh` again to update. The bundle id is `com.kris.pipelinetracer`.

A manual build, without installing, is:

```bash
cd menubar
./make-app.sh
open "Pipeline Tracer.app"
```

Quit and rerun `./install.sh` after you change the source if you want the menu-bar copy updated.

## How it works

On a timer, Tracer asks GitLab.com, through `glab`, for:

- open merge requests you created (one GraphQL query, up to 30; archived projects dropped in that response)
- your recent pipelines across projects (`GET /pipelines`, one call instead of one per project)
- jobs only for the status-card pipeline, newly finished failures, or when you open a pipeline (cached while status+sha stay the same)

Your GitLab username is cached for an hour so the timer does not re-hit `/user` every tick.

GitHub has no single "all of my workflow runs" endpoint. Tracer asks `gh` for the 30 repos you pushed most recently, keeps that list for 10 minutes, then loads the 20 newest Actions runs on the ones pushed inside the pipeline window (at most 12 repos). If nothing was pushed in that window, it checks the 8 most recently pushed repos instead. A scheduled workflow on a repo outside that set does not appear until the repo is pushed again. Each run becomes a pipeline. Each Actions job becomes a job, and the job name is the stage. Logs come from the job log endpoint, which is text. If GitHub returns a zip, the panel tells you to open the job in the browser instead of unpacking it. A failed workflow is cleared only by a later success of that same workflow, not by a different workflow on the same commit.

Open pull requests you created come from one GitHub GraphQL call, up to 30, newest update first. They sit in the same Requests section as GitLab merge requests. A `#` number is GitHub. A `!` number is GitLab. Opening a pull request reloads it and lists its check runs.

The overview groups that into:

- **Attention needed** for the latest failed pipeline on a branch. A newer successful pipeline for the same commit clears it. A success on a different commit does not.
- **Active** pipelines that are running, queued, or waiting.
- **Recent successes**, collapsed until you open the section.
- **Canceled and skipped**, collapsed the same way.
- **Requests**, GitLab merge requests and GitHub pull requests, with draft, blocked, and ready state.

Open a pipeline for its jobs. GitLab groups those jobs by stage on a sideways track. GitHub uses each Actions job name as the stage, and does not list the steps inside a job. Open a job for a log snapshot. Logs can be filtered and copied. They are not saved to disk. A job that prints a secret will show it here. GitHub sends some logs as a zip. That zip is not unpacked. Open the job in the browser for it. **Open in GitLab** and **Open on GitHub** are there when you want the full page.

The back control is the chevron and the title together. A section header toggles that section, not only the small arrow.

### Merge

**Merge** asks you to confirm, loads the request again, and continues only when it is still open, not a draft, and mergeable, and the source SHA still matches the one you were looking at. GitLab sends that SHA with `PUT` through `glab`. GitHub sends it with `PUT` through `gh`, and uses merge, squash, or rebase according to what that repo allows. One merge is sent at a time. A notification never merges for you. The button follows the **Show merge actions** preference. A workflow run still has no merge button, because a run is not a pull request.

**Close** sits beside Merge. It always asks you to confirm, then closes the GitLab merge request or the GitHub pull request. It does not delete the source branch.

### Notifications

Banners are titled **Pipeline Tracer**. Failures play the default sound and are requested as time sensitive. macOS shows a normal banner unless the app has Apple's Time Sensitive entitlement, which this ad-hoc build does not. Each unresolved failure notifies once, including failures already present at launch. Clicking a banner opens the page for that event when it is `https://gitlab.com` or `https://github.com`.

Allow notifications the first time macOS asks, or from **Preferences** inside the panel. **Send test** posts one sample banner.

### Preferences

| Item | Default |
|---|---|
| Reopen where I left off | Off. Closing the panel returns you to the overview. |
| Refresh interval | 60 seconds. The menu lists the choices. |
| Completion history | 2 hours. The menu calls this **Finished pipelines shown for**. GitLab pipelines and GitHub Actions runs both use it. Open requests do not. |
| Merge button | On. Covers GitLab merge requests and GitHub pull requests. |
| Menu bar colors | Navy capsule. Failures use a stronger treatment so the menu bar is obvious. |

Preferences live in UserDefaults under `com.kris.pipelinetracer`. They are not credentials.

### Clicking away

Clicking outside the panel closes it, including a click on the desktop. The menu-bar icon still toggles the panel. A popup menu or a confirmation dialog stays up while you use it.

## Develop

```bash
cd menubar
swift run PipelineTracer --self-check
"./Pipeline Tracer.app/Contents/MacOS/PipelineTracer" --preview
```

`--self-check` covers status rules, dates, notification text, GitHub run mapping, and pull-request status without calling GitLab or GitHub. `--preview` opens sample data (`example/app`, `example/web`) and does not send notifications or merge anything. `--dump` prints a read-only summary of the live `glab` and `gh` responses. `--notification-preview` posts one sample banner after you allow notifications.

XCTest is not required. Command Line Tools can run `--self-check`.

## Layout

| Path | What |
|---|---|
| `menubar/` | Swift Package Manager app |
| `menubar/install.sh` | Build, install to `~/Applications`, and login start |
| `menubar/Artwork/` | Menu-bar icon. Regenerate with `swift Artwork/generate-icon.swift` from `menubar/`, then `iconutil`. |

## License

[MIT](LICENSE). Copyright 2026 Kristopher Simmons.
