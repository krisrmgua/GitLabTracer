# GitLab Tracer

GitLab Tracer is a macOS menu-bar app for the GitLab.com activity that is yours: open merge requests you created, pipelines on projects you belong to, failed jobs, and a merge button that re-checks GitLab before it merges.

The panel is a dark activity inbox. Failures stay at the top until a later pipeline for that same commit succeeds. Clicking away closes the panel. The next open returns to the overview unless you turn on **Reopen where I left off**.

Requires **macOS 13** or later, the Swift command-line tools, and [`glab`](https://gitlab.com/gitlab-org/cli) signed in to `gitlab.com`.

## Install glab and sign in

GitLab Tracer does not ask for your GitLab password and it does not store a personal access token. `glab` owns the token. Install it, then log in once:

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

## Install the app

```bash
git clone https://github.com/krisrmgua/GitLabTracer.git
cd GitLabTracer/menubar
./install.sh
```

That builds `GitLab Tracer.app`, copies it to `~/Applications/GitLab Tracer.app`, and starts it at login. Run `./install.sh` again to update. The bundle id is `com.kris.gitlabtracer`.

A manual build, without installing, is:

```bash
cd menubar
./make-app.sh
open "GitLab Tracer.app"
```

Quit and rerun `./install.sh` after you change the source if you want the menu-bar copy updated.

## How it works

On a timer, Tracer asks GitLab.com, through `glab`, for:

- open merge requests you created (up to 30)
- projects you belong to that were active in the last few days (up to 60)
- your recent pipelines on those projects (10 per project, inside the hour window you set)
- jobs for a pipeline when you open it (up to 100)

The overview groups that into:

- **Attention needed** for the latest failed pipeline on a branch. A newer successful pipeline for the same commit clears it. A success on a different commit does not.
- **Active** pipelines that are running, queued, or waiting.
- **Recent successes**, collapsed until you open the section.
- **Canceled and skipped**, collapsed the same way.
- **Merge requests**, with draft, blocked, and ready state.

Open a pipeline for its jobs, grouped by stage. Open a job for a log snapshot. Logs can be filtered and copied. They are not saved to disk. A job that prints a secret will show it here. **Open in GitLab** is there when you want the full page.

The back control is the chevron and the title together. A section header toggles that section, not only the small arrow.

### Merge

**Merge** is off unless you turn the preference on. It asks you to confirm, loads the merge request again, and continues only when GitLab still says it is open, not a draft, and mergeable, and the source SHA still matches the one you were looking at. The request is `PUT` through `glab` with that SHA. One merge is sent at a time. A notification never merges for you.

### Notifications

Banners are titled **GitLab Tracer**. Failures play the default sound and are requested as time sensitive. macOS shows a normal banner unless the app has Apple's Time Sensitive entitlement, which this ad-hoc build does not. Each unresolved failure notifies once, including failures already present at launch. Clicking a banner opens the `https://gitlab.com` page for that event.

Allow notifications the first time macOS asks, or from **Preferences** inside the panel. **Send test** posts one sample banner.

### Preferences

| Item | Default |
|---|---|
| Reopen where I left off | Off. Closing the panel returns you to the overview. |
| Refresh interval | A few minutes. The menu lists the choices. |
| Pipeline window | How many hours of pipelines to fetch. |
| Merge button | Off until you enable it. |
| Menu bar colors | Navy capsule. Failures use a stronger treatment so the menu bar is obvious. |

Preferences live in UserDefaults under `com.kris.gitlabtracer`. They are not credentials.

### Clicking away

Clicking outside the panel closes it, including a click on the desktop. The menu-bar icon still toggles the panel. A popup menu or a confirmation dialog stays up while you use it.

## Develop

```bash
cd menubar
swift run GitLabTracer --self-check
"./GitLab Tracer.app/Contents/MacOS/GitLabTracer" --preview
```

`--self-check` covers status rules, dates, and notification text without calling GitLab. `--preview` opens sample data (`example/app`, `example/web`) and does not send notifications or merge anything. `--dump` prints a read-only summary of the live `glab` response. `--notification-preview` posts one sample banner after you allow notifications.

XCTest is not required. Command Line Tools can run `--self-check`.

## Layout

| Path | What |
|---|---|
| `menubar/` | Swift Package Manager app |
| `menubar/install.sh` | Build, install to `~/Applications`, and login start |
| `menubar/Artwork/` | Menu-bar icon. Regenerate with `swift Artwork/generate-icon.swift` from `menubar/`, then `iconutil`. |

## License

[MIT](LICENSE). Copyright 2026 Kristopher Simmons.
