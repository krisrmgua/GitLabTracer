# Contributing

Issues and pull requests are welcome.

1. Fork the repository and create a branch from `main`.
2. Keep the change focused. Use a conventional commit such as `feat:`, `fix:`, or `docs:`.
3. From `menubar/`, run:

```bash
swift run GitLabTracer --self-check
```

4. Do not commit GitLab tokens, job logs, or private project data. Sample data in the repo uses `example/` paths.
5. Open a pull request that says what changed and how you tested it.

The app targets macOS 13 and is built with Swift Package Manager. A live check also needs `glab` signed in to `gitlab.com`.

User-facing behavior belongs in the README when install steps, GitLab setup, or preferences change.
