// Synthetic documentation fixtures. No accounts, credentials, or live services.
module.exports = {
  "bridge": "tracer",
  "width": 430,
  "minHeight": 220,
  "maxHeight": 850,
  "state": {
    "pipelines": [
      {
        "host": "gitlab",
        "projectID": 220,
        "id": 220,
        "project": "example/atlas",
        "ref": "feat/request-tracing",
        "sourceBranch": "feat/request-tracing",
        "status": "running",
        "url": "https://gitlab.com/example/atlas/-/pipelines/220",
        "updated": 1793807248428,
        "sha": "a1b2c3d4e5f6",
        "jobs": [
          {
            "id": 1,
            "name": "install",
            "stage": "prepare",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/1",
            "duration": 18
          },
          {
            "id": 2,
            "name": "lint",
            "stage": "test",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/2",
            "duration": 12
          },
          {
            "id": 3,
            "name": "test:integration",
            "stage": "test",
            "status": "running",
            "url": "https://gitlab.com/example/atlas/-/jobs/3",
            "duration": 38,
            "startedAt": 1793807330428
          },
          {
            "id": 4,
            "name": "deploy:preview",
            "stage": "deploy",
            "status": "pending",
            "url": "https://gitlab.com/example/atlas/-/jobs/4",
            "duration": 0
          }
        ],
        "workflow": ""
      },
      {
        "host": "github",
        "projectID": 418,
        "id": 418,
        "project": "example/web",
        "ref": "fix/navigation",
        "sourceBranch": "fix/navigation",
        "status": "running",
        "url": "https://github.com/example/web/actions/runs/418",
        "updated": 1793807248428,
        "sha": "a1b2c3d4e5f6",
        "jobs": [
          {
            "id": 1,
            "name": "install",
            "stage": "prepare",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/1",
            "duration": 18
          },
          {
            "id": 2,
            "name": "lint",
            "stage": "test",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/2",
            "duration": 12
          },
          {
            "id": 3,
            "name": "test:integration",
            "stage": "test",
            "status": "running",
            "url": "https://gitlab.com/example/atlas/-/jobs/3",
            "duration": 38,
            "startedAt": 1793807330428
          },
          {
            "id": 4,
            "name": "deploy:preview",
            "stage": "deploy",
            "status": "pending",
            "url": "https://gitlab.com/example/atlas/-/jobs/4",
            "duration": 0
          }
        ],
        "workflow": "Build & test"
      },
      {
        "host": "gitlab",
        "projectID": 87,
        "id": 87,
        "project": "example/api",
        "ref": "main",
        "sourceBranch": "main",
        "status": "failed",
        "url": "https://gitlab.com/example/api/-/pipelines/87",
        "updated": 1793807248428,
        "sha": "a1b2c3d4e5f6",
        "jobs": [
          {
            "id": 1,
            "name": "install",
            "stage": "prepare",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/1",
            "duration": 18
          },
          {
            "id": 2,
            "name": "lint",
            "stage": "test",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/2",
            "duration": 12
          },
          {
            "id": 3,
            "name": "test:integration",
            "stage": "test",
            "status": "failed",
            "url": "https://gitlab.com/example/atlas/-/jobs/3",
            "duration": 38,
            "startedAt": 1793807330428
          },
          {
            "id": 4,
            "name": "deploy:preview",
            "stage": "deploy",
            "status": "skipped",
            "url": "https://gitlab.com/example/atlas/-/jobs/4",
            "duration": 0
          }
        ],
        "workflow": ""
      },
      {
        "host": "github",
        "projectID": 219,
        "id": 219,
        "project": "example/docs",
        "ref": "docs/quickstart",
        "sourceBranch": "docs/quickstart",
        "status": "success",
        "url": "https://github.com/example/docs/actions/runs/219",
        "updated": 1793807248428,
        "sha": "a1b2c3d4e5f6",
        "jobs": [
          {
            "id": 1,
            "name": "install",
            "stage": "prepare",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/1",
            "duration": 22
          },
          {
            "id": 2,
            "name": "lint",
            "stage": "test",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/2",
            "duration": 22
          },
          {
            "id": 3,
            "name": "test:integration",
            "stage": "test",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/3",
            "duration": 22,
            "startedAt": 1793807330428
          },
          {
            "id": 4,
            "name": "deploy:preview",
            "stage": "deploy",
            "status": "success",
            "url": "https://gitlab.com/example/atlas/-/jobs/4",
            "duration": 22
          }
        ],
        "workflow": "Build & test"
      },
      {
        "host": "gitlab",
        "projectID": 86,
        "id": 86,
        "project": "example/api",
        "ref": "experiment/cache",
        "sourceBranch": "experiment/cache",
        "status": "canceled",
        "url": "https://gitlab.com/example/api/-/pipelines/86",
        "updated": 1793807248428,
        "sha": "a1b2c3d4e5f6",
        "jobs": [
          {
            "id": 1,
            "name": "install",
            "stage": "prepare",
            "status": "canceled",
            "url": "https://gitlab.com/example/atlas/-/jobs/1",
            "duration": 18
          },
          {
            "id": 2,
            "name": "lint",
            "stage": "test",
            "status": "canceled",
            "url": "https://gitlab.com/example/atlas/-/jobs/2",
            "duration": 12
          },
          {
            "id": 3,
            "name": "test:integration",
            "stage": "test",
            "status": "canceled",
            "url": "https://gitlab.com/example/atlas/-/jobs/3",
            "duration": 38,
            "startedAt": 1793807330428
          },
          {
            "id": 4,
            "name": "deploy:preview",
            "stage": "deploy",
            "status": "canceled",
            "url": "https://gitlab.com/example/atlas/-/jobs/4",
            "duration": 0
          }
        ],
        "workflow": ""
      }
    ],
    "mrs": [
      {
        "host": "gitlab",
        "projectID": 42,
        "iid": 42,
        "title": "Add request tracing",
        "project": "example/atlas",
        "url": "https://gitlab.com/example/atlas/-/merge_requests/42",
        "draft": false,
        "mergeStatus": "mergeable",
        "pipelineStatus": "success",
        "updated": 1793807308428,
        "sourceBranch": "feat/request-tracing",
        "targetBranch": "main",
        "sha": "a1b2c3d4e5f6"
      },
      {
        "host": "github",
        "projectID": 18,
        "iid": 18,
        "title": "Fix navigation focus",
        "project": "example/web",
        "url": "https://github.com/example/web/pull/18",
        "draft": false,
        "mergeStatus": "ci_still_running",
        "pipelineStatus": "running",
        "updated": 1793807308428,
        "sourceBranch": "fix/navigation",
        "targetBranch": "main",
        "sha": "a1b2c3d4e5f6"
      },
      {
        "host": "gitlab",
        "projectID": 12,
        "iid": 12,
        "title": "Draft: simplify cache layer",
        "project": "example/api",
        "url": "https://gitlab.com/example/api/-/merge_requests/12",
        "draft": true,
        "mergeStatus": "draft_status",
        "pipelineStatus": "running",
        "updated": 1793807308428,
        "sourceBranch": "fix/navigation",
        "targetBranch": "main",
        "sha": "a1b2c3d4e5f6"
      }
    ],
    "events": [
      {
        "id": "0",
        "title": "Pipeline failed",
        "detail": "example/api \u00b7 #87 \u00b7 main \u00b7 test:integration",
        "status": "failed",
        "url": "https://gitlab.com/example/api/-/pipelines/87",
        "date": 1793807368428
      },
      {
        "id": "1",
        "title": "Merge request ready",
        "detail": "example/atlas !42 \u00b7 Add request tracing",
        "status": "mergeable",
        "url": "https://gitlab.com/example/api/-/pipelines/87",
        "date": 1793807188428
      },
      {
        "id": "2",
        "title": "Pipeline passed",
        "detail": "example/docs \u00b7 #219 \u00b7 docs/quickstart",
        "status": "success",
        "url": "https://gitlab.com/example/api/-/pipelines/87",
        "date": 1793807008428
      }
    ],
    "refreshing": false,
    "error": null,
    "updated": 1793807368428,
    "result": null,
    "merging": null,
    "closing": null,
    "prefs": {
      "refreshSeconds": 60,
      "pipelineHours": 2,
      "mergeButton": true,
      "rememberPlace": false,
      "startAtLogin": true
    },
    "platform": "darwin",
    "version": "0.3.7",
    "cli": {
      "glab": "/opt/homebrew/bin/glab",
      "gh": "/opt/homebrew/bin/gh"
    },
    "notificationsSupported": true
  },
  "mrJobs": [
    {
      "id": 1,
      "name": "install",
      "stage": "prepare",
      "status": "success",
      "url": "https://gitlab.com/example/atlas/-/jobs/1",
      "duration": 18
    },
    {
      "id": 2,
      "name": "lint",
      "stage": "test",
      "status": "success",
      "url": "https://gitlab.com/example/atlas/-/jobs/2",
      "duration": 12
    },
    {
      "id": 3,
      "name": "test:integration",
      "stage": "test",
      "status": "success",
      "url": "https://gitlab.com/example/atlas/-/jobs/3",
      "duration": 38,
      "startedAt": 1793807330428
    },
    {
      "id": 4,
      "name": "deploy:preview",
      "stage": "deploy",
      "status": "success",
      "url": "https://gitlab.com/example/atlas/-/jobs/4",
      "duration": 22
    }
  ],
  "log": "Preparing integration environment\u2026\nPASS health-check.test.ts\nFAIL request-tracing.test.ts\n  Expected header x-request-id to be present\n  Received: undefined\nTests: 1 failed, 24 passed, 25 total\nERROR: Job failed: exit code 1",
  "shots": [
    {
      "name": "overview",
      "caption": "Activity inbox with failures, simultaneous pipelines, and requests in different states.",
      "action": "",
      "expect": "Attention needed"
    },
    {
      "name": "running-pipeline",
      "caption": "Running pipeline with completed, running, and queued jobs.",
      "action": "document.querySelector(\"[data-act=\\\"pipeline\\\"][data-key=\\\"gitlab:220:220\\\"]\").click();",
      "expect": "deploy:preview"
    },
    {
      "name": "pipeline",
      "caption": "Pipeline detail with per-stage progress and job durations.",
      "action": "document.querySelector(\"[data-act=\\\"back\\\"]\").click();document.querySelector(\"[data-act=\\\"pipeline\\\"][data-key=\\\"gitlab:87:87\\\"]\").click();",
      "expect": "test:integration"
    },
    {
      "name": "job-logs",
      "caption": "Failed-job trace in the actual log viewer.",
      "action": "document.querySelector(\"[data-act=\\\"log\\\"][data-job=\\\"3\\\"]\").click();",
      "expect": "Expected header"
    },
    {
      "name": "job-summary",
      "caption": "Job summary and the link to the CI host.",
      "action": "document.querySelector(\"[data-act=\\\"log-tab\\\"][data-value=\\\"summary\\\"]\").click();",
      "expect": ""
    },
    {
      "name": "merge-request",
      "caption": "Ready merge request workspace, checks, source/target, and actions.",
      "action": "document.querySelector(\"[data-act=\\\"back\\\"]\").click();document.querySelector(\"[data-act=\\\"mr\\\"][data-key=\\\"42:42\\\"]\").click();",
      "expect": "Ready to merge."
    },
    {
      "name": "merge-confirmation",
      "caption": "Merge confirmation before the host is rechecked.",
      "action": "document.querySelector(\"[data-act=\\\"merge-ask\\\"]\").click();",
      "expect": "Merge"
    },
    {
      "name": "close-confirmation",
      "caption": "Separate close-request confirmation.",
      "action": "document.querySelector(\"[data-act=\\\"confirm-cancel\\\"]\").click();document.querySelector(\"[data-act=\\\"close-ask\\\"]\").click();",
      "expect": "Close MR"
    },
    {
      "name": "running-request",
      "caption": "Request with running checks and disabled merge action.",
      "action": "document.querySelector(\"[data-act=\\\"confirm-cancel\\\"]\").click();document.querySelector(\"[data-act=\\\"mr\\\"][data-key=\\\"github:18:18\\\"]\").click();",
      "expect": "Merge unavailable"
    },
    {
      "name": "draft-request",
      "caption": "Draft request workspace keeps merge disabled.",
      "action": "document.querySelector(\"[data-act=\\\"mr\\\"][data-key=\\\"12:12\\\"]\").click();",
      "expect": "Draft"
    },
    {
      "name": "history",
      "caption": "Recent successes and their expandable job lists.",
      "action": "document.querySelector(\"[data-act=\\\"back\\\"]\").click();document.querySelector(\"[data-act=\\\"history\\\"]\").click();",
      "expect": "Recent successes"
    },
    {
      "name": "success-jobs",
      "caption": "Expanded successful run with individual job results.",
      "action": "document.querySelector(\"[data-act=\\\"history-toggle\\\"]\").click();",
      "expect": "View logs"
    },
    {
      "name": "notifications",
      "caption": "Notification inbox with status filters.",
      "action": "document.querySelector(\"[data-act=\\\"notifications\\\"]\").click();",
      "expect": "Pipeline failed"
    },
    {
      "name": "settings",
      "caption": "Preferences, notifications, startup, refresh cadence, and tool status.",
      "action": "document.querySelector(\"[data-act=\\\"settings\\\"]\").click();",
      "expect": "Show merge actions"
    }
  ]
};
