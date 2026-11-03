# Contributing

Issues and pull requests are welcome.

1. Fork the repository and create a branch from `main`.
2. Keep the change focused. Use a conventional commit such as `feat:`, `fix:`, or `docs:`.
3. From the repo root, run:

```bash
npm install
npm run check
npm run build
```

4. Do not commit GitLab or GitHub tokens, job logs, or private project data. Sample data in the repo uses `example/` paths.
5. Open a pull request that says what changed and how you tested it, and on which OS (macOS, Windows, or both).

The app is Electron + TypeScript and targets macOS 13+ and Windows 10/11. A live GitLab check needs `glab` signed in to `gitlab.com`. A live GitHub Actions check needs `gh` signed in to `github.com`.

Rules that both the panel and the main process use (status, grouping, parsing) belong in `electron/logic.ts`, which must not import Node or Electron so the panel can bundle it. Add a case to `electron/selfcheck.ts` when you change one.

The legacy Swift app in `menubar/` still builds with `swift run PipelineTracer --self-check`.

User-facing behavior belongs in the README when install steps, CLI setup, or preferences change.
