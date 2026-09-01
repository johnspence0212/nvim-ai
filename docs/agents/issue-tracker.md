# Issue tracker: Linear

Issues and specs for this repo live as Linear issues in project **NVIM-AI** on team **Johnspence**. Use Linear MCP for all operations. Identify issues by Linear identifier (`JOH-123`).

GitHub Issues are not used. GitHub PRs are delivery only: one Linear ticket → one feature branch (the issue’s `gitBranchName` when present) → one PR into `main`.

Workspace: https://linear.app/johnspence
Project: https://linear.app/johnspence/project/nvim-ai-f99d350b43af

## Conventions

- **Create an issue**: `save_issue` with `team: "Johnspence"`, `project: "NVIM-AI"`, title, and markdown body. Apply triage labels from `docs/agents/triage-labels.md`.
- **Read an issue**: `get_issue` with `id: "JOH-n"` and `includeRelations: true`, plus `list_comments` with `issueId: "JOH-n"`.
- **List issues**: `list_issues` with `project: "NVIM-AI"` (and `team: "Johnspence"` when scoping), plus `label` / `state` / `assignee` filters as needed. Include `labels`, `status`, `gitBranchName`, `assignee`, `parentId`, `url` in `fields`.
- **Comment on an issue**: `save_comment` with `issueId: "JOH-n"` and markdown `body`.
- **Apply / remove labels**: `save_issue` `labels` **replaces the full set**. Read current labels first, then send the merged list. Do not drop unrelated labels (e.g. `wayfinder:*`, `Bug`).
- **Close (done)**: `save_issue` with `id: "JOH-n"` and `state: "Done"`.
- **Close (wontfix / rejected)**: `save_issue` with `id: "JOH-n"` and `state: "Canceled"`.
- **Blocking**: native Linear relations. Set `blockedBy: ["JOH-n"]` (and `blocks` the other way) on `save_issue`. These are append-only; use `removeBlockedBy` / `removeBlocks` to drop an edge.
- **Parent / sub-issue**: `parentId` on `save_issue`. List children with `list_issues` `parentId: "JOH-n"`.
- **Claim**: `save_issue` with `assignee: "me"`.
- **Branch**: use the issue’s `gitBranchName` from `get_issue` / `list_issues` when present.

Team workflow states: Backlog, Todo, In Progress, In Review, Done, Canceled, Duplicate.

If a triage label does not exist yet, create it once with `create_issue_label` (workspace label: omit `teamId`) using the names in `docs/agents/triage-labels.md`.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

## When a skill says "publish to the issue tracker"

Create a Linear issue in project NVIM-AI as above. Use native `blockedBy` for blocking edges. Apply the `ready-for-agent` triage label unless instructed otherwise.

## When a skill says "fetch the relevant ticket"

`get_issue` for `JOH-n` with `includeRelations: true`, then `list_comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets. Wayfinder labels already exist in this workspace (`wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task`).

- **Map**: a Linear issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `save_issue` with `team: "Johnspence"`, `project: "NVIM-AI"`, `labels: ["wayfinder:map"]`.
- **Child ticket**: a Linear sub-issue of the map (`parentId` = map identifier). Labels: `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`). Once claimed, assign the ticket to the driving dev.
- **Blocking**: Linear’s native `blockedBy` / `blocks` relations. A ticket is unblocked when every blocker is in a completed or canceled state (`Done`, `Canceled`, `Duplicate`).
- **Frontier query**: `list_issues` with `parentId` of the map, open states only, drop any with an open blocker (`includeRelations`) or an assignee; first in map order wins.
- **Claim**: `save_issue` `assignee: "me"`, the session’s first write.
- **Resolve**: `save_comment` with the answer, set `state: "Done"`, then append a context pointer (gist + link) to the map’s Decisions-so-far.
