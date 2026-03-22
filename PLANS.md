# GitHub Tracker Plan

Status: ready for review  
Date: 2026-03-21

Purpose: this file is the single source of truth for implementing `tracker.kind: github` in the Elixir reference implementation. It replaces the earlier GitHub spec and scratchpad notes.

## Progress Rules

- [ ] Use this file as the implementation ledger.
- [ ] Treat every checkbox in every milestone as an independently completable item.
- [ ] Mark an item `[X]` immediately after that specific item is done.
- [ ] Do not wait for the whole milestone to finish before marking completed items.
- [ ] If scope changes, add new checklist items in the relevant milestone before implementing them.
- [ ] If a milestone is blocked, leave the blocked item unchecked and add a short note under that milestone.

## Locked Decisions

- PAT-only auth via `tracker.api_key`, typically `$GITHUB_TOKEN`
- GitHub v1 defaults to `https://api.github.com/graphql`, but `tracker.endpoint`
  remains configurable via `WORKFLOW.md`
- GraphQL-only tracker path in v1
- no `gh` CLI fallback in tracker code
- no REST in the tracker loop
- do not modify the existing `linear_graphql` dynamic tool in v1
- GitHub mode must not depend on any new dynamic tool in v1
- polling interval for GitHub example/config is `10000`
- configured GitHub Projects live in `WORKFLOW.md`
- repository bootstrap comes from the linked GitHub issue
- only repo-backed GitHub issues are runnable
- ignore draft items
- ignore PR-backed project items
- assume one tracked-project membership per issue in v1
- keep one persistent GitHub issue workpad comment
- `Backlog` is intake; `Todo` is runnable
- disable GitHub Project workflow `PR linked -> In Progress`
- blocker resolution uses GitHub-native dependency completion:
  - blocker issue must be `CLOSED`
  - blocker `stateReason` must be `COMPLETED`
- completion is merge-driven by GitHub defaults
- do not change existing `linear` or `memory` behavior

## Non-Goals for v1

- GitHub App auth
- webhooks
- org-specific webhook architecture
- duplicate tracked-project handling beyond documenting the assumption
- PR-backed execution items
- draft issue execution
- generic `github_graphql` dynamic tool
- REST optimizations
- auto-refresh TTL for project field metadata

## Required External GitHub Setup

These are part of the expected GitHub Project setup, even though they live outside Symphony code.

- `PR linked -> In Progress` must be disabled
- if item-added automation is used, it should place items into `Backlog`, not `Todo`
- keep the default GitHub workflow that moves closed issues to `Done`
- keeping the built-in `merged PR -> Done` workflow is fine, but v1 should not depend on it for issue-only execution
- if `Done -> close issue` is enabled, treat `Done` as terminal only and never move items there early
- repositories should keep GitHub auto-close for linked issues enabled
- completion should use PR bodies such as `Closes #123`

## Runtime Model

### Candidate selection

- Symphony polls only the configured GitHub Projects
- candidate polling is server-filtered by project status
- only issue-backed open items are candidates
- `Backlog` is parked and ignored
- `Human Review` is intentionally non-runnable and should stay out of `active_states`
- default runnable states are:
  - `Todo`
  - `In Progress`
  - `Rework`
  - `Merging`

### Blockers

- a blocked issue can start or resume only when every blocker is:
  - `state == CLOSED`
  - `stateReason == COMPLETED`
- `NOT_PLANNED` does not unblock
- `DUPLICATE` does not unblock
- `REOPENED` does not unblock
- use `blockedBy.nodes.state/stateReason` as the gate
- `issueDependenciesSummary` is counts-only and not the gate

### Completion

- agent work produces or updates a PR
- PR description/body includes a closing keyword like `Closes #123`
- when that PR merges into the repository default branch:
  - GitHub auto-closes the issue
  - issue becomes `CLOSED + COMPLETED`
  - in the default Project v2 workflow setup, the closed issue item moves to `Done`
- do not add a Symphony-side fallback close mutation in v1

## Code and Config Examples

### Example `WORKFLOW.md` front matter

```yaml
---
tracker:
  kind: github
  api_key: $GITHUB_TOKEN
  owner:
    type: user
    login: your-github-login
  projects:
    - number: 5
    - number: 6
  active_states:
    - Todo
    - In Progress
    - Rework
    - Merging
  terminal_states:
    - Done
    - Closed
    - Cancelled
  status_field_name: Status
  workpad_comment:
    heading: "## Codex Workpad"
    marker: "<!-- symphony:workpad -->"
polling:
  interval_ms: 10000
workspace:
  root: ~/code/symphony-workspaces
hooks:
  after_create: |
    if command -v mise >/dev/null 2>&1; then
      cd elixir && mise trust && mise exec -- mix deps.get
    fi
---
```

### Startup hydration query example

```graphql
query {
  user(login: "your-github-login") {
    project5: projectV2(number: 5) {
      id
      number
      title
      url
      field(name: "Status") {
        ... on ProjectV2FieldCommon {
          id
          name
          dataType
        }
        ... on ProjectV2SingleSelectField {
          options {
            id
            name
          }
        }
      }
    }
  }
}
```

### Candidate poll query example

```graphql
query {
  user(login: "your-github-login") {
    project5: projectV2(number: 5) {
      items(first: 50, query: "is:issue is:open status:\"Todo\",\"In Progress\",\"Rework\",\"Merging\"") {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name
              optionId
            }
          }
          content {
            ... on Issue {
              id
              number
              title
              body
              url
              state
              stateReason
              updatedAt
              repository {
                nameWithOwner
                url
                sshUrl
                defaultBranchRef {
                  name
                }
              }
              labels(first: 20) {
                nodes {
                  name
                }
              }
              assignees(first: 10) {
                nodes {
                  login
                }
              }
              issueDependenciesSummary {
                blockedBy
                totalBlockedBy
              }
              blockedBy(first: 20) {
                nodes {
                  id
                  number
                  state
                  stateReason
                }
              }
            }
          }
        }
      }
    }
  }
}
```

### Running-issue refresh query example

```graphql
query($id: ID!) {
  node(id: $id) {
    ... on Issue {
      id
      number
      state
      stateReason
      updatedAt
      repository {
        nameWithOwner
      }
      issueDependenciesSummary {
        blockedBy
        totalBlockedBy
      }
      blockedBy(first: 20) {
        nodes {
          id
          number
          state
          stateReason
        }
      }
      projectItems(first: 20) {
        nodes {
          id
          project {
            number
            title
          }
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name
              optionId
            }
          }
        }
      }
    }
  }
}
```

### Mutation examples

Project status update:

```graphql
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(
    input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }
  ) {
    projectV2Item {
      id
    }
  }
}
```

Create workpad comment:

```graphql
mutation($subjectId: ID!, $body: String!) {
  addComment(input: { subjectId: $subjectId, body: $body }) {
    commentEdge {
      node {
        id
      }
    }
  }
}
```

Update workpad comment:

```graphql
mutation($id: ID!, $body: String!) {
  updateIssueComment(input: { id: $id, body: $body }) {
    issueComment {
      id
    }
  }
}
```

## Current Code Surface

Primary implementation touch points:

- [config.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config.ex)
- [schema.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config/schema.ex)
- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [orchestrator.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/orchestrator.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- [status_dashboard.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/status_dashboard.ex)
- [elixir/README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/README.md)
- [elixir/WORKFLOW.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.md)

Expected new modules:

- `elixir/lib/symphony_elixir/github/client.ex`
- `elixir/lib/symphony_elixir/github/adapter.ex`
- `elixir/lib/symphony_elixir/github/issue.ex`

Primary test surfaces:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [extensions_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/extensions_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)
- new GitHub adapter/client tests
- targeted orchestrator tests for GitHub-specific state rules

## Progress

- [x] Milestone 1: Config and schema foundation
- [x] Milestone 2: GitHub client and normalized model
- [x] Milestone 3: Tracker adapter boundary
- [x] Milestone 4: Orchestrator integration
- [x] Milestone 5: Workspace bootstrap and prompt metadata
- [x] Milestone 6: Workpad persistence
- [x] Milestone 7: Docs and workflow samples
- [x] Milestone 8: Validation and non-regression proof
- [ ] Milestone 9: Live end-to-end GitHub validation and cleanup

## Milestones

### Milestone 1: Config and schema foundation

Files:

- [config.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config.ex)
- [schema.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config/schema.ex)
- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)

Checklist:

- [x] Extend supported tracker kinds from `linear` and `memory` to include `github`
- [x] Add GitHub tracker schema fields for `owner`, `projects`, `status_field_name`, and `workpad_comment`
- [x] Decide endpoint handling for GitHub mode explicitly
- [x] Prevent the Linear default endpoint from silently applying to GitHub mode
- [x] Keep current Linear defaults intact
- [x] Keep `LINEAR_API_KEY` env fallback isolated to Linear only
- [x] Add GitHub-specific config validation errors for missing PAT, owner login, or projects
- [x] Add tests proving current Linear and Memory config still parse unchanged
- [x] Add tests proving invalid GitHub config fails with precise errors

### Milestone 2: GitHub client and normalized model

Files:

- `elixir/lib/symphony_elixir/github/client.ex`
- `elixir/lib/symphony_elixir/github/issue.ex`
- new GitHub client tests

Checklist:

- [x] Add a dedicated GitHub GraphQL transport module using `tracker.api_key`
- [x] Implement startup hydration for configured projects only
- [x] Fetch `field(name: "Status")` and cache the field/options on startup or workflow reload
- [x] Implement normalized GitHub issue/project-item structs or maps
- [x] Implement candidate polling with server-side status filtering
- [x] Implement running-issue refresh by GitHub issue node ids
- [x] Implement blocker field normalization using `blockedBy.nodes.state/stateReason`
- [x] Prove no tracker code shells out to `gh`
- [x] Add tests for polling, refresh, normalization, and GraphQL error handling

### Milestone 3: Tracker adapter boundary

Files:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- `elixir/lib/symphony_elixir/github/adapter.ex`
- [extensions_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/extensions_test.exs)

Checklist:

- [x] Route `tracker.kind == "github"` to a new GitHub adapter
- [x] Implement `fetch_candidate_issues/0`
- [x] Implement `fetch_issues_by_states/1` or explicitly narrow the tracker behaviour if that callback is no longer required
- [x] Implement `fetch_issue_states_by_ids/1`
- [x] Implement `update_issue_state/2` using GitHub Project `Status`
- [x] Implement comment creation for GitHub issues
- [x] Decide whether the tracker behaviour needs explicit comment-update support for a persistent workpad
- [x] If behaviour expands, update Linear and Memory adapters without changing their semantics
- [x] Add adapter-dispatch tests across `memory`, `linear`, and `github`

### Milestone 4: Orchestrator integration

Files:

- [orchestrator.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/orchestrator.ex)
- orchestrator-focused tests

Checklist:

- [x] Keep the overall orchestration shape close to the current Linear path
- [x] For GitHub mode, skip new-candidate polling when no agent slots are free
- [x] Preserve running-issue reconciliation
- [x] Apply blocker gating for GitHub using `CLOSED + COMPLETED`
- [x] Treat `Backlog` as non-runnable
- [x] Keep `Human Review` non-runnable and outside GitHub `active_states`
- [x] Keep `Todo`, `In Progress`, `Rework`, and `Merging` as the default active example states
- [x] Preserve claimed/running protections against double dispatch
- [x] Add tests for blocked issues, unblocked issues, and capacity-first candidate skip
- [x] Add tests proving Linear behavior stays unchanged

### Milestone 5: Workspace bootstrap and prompt metadata

Files:

- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- workspace-related tests

Checklist:

- [x] Pass repository metadata from GitHub issue records into workspace creation
- [x] Clone from the linked GitHub issue repository before `hooks.after_create`
- [x] Keep `hooks.after_create` as post-clone setup only
- [x] Expose prompt variables for repository name, URLs, and default branch
- [x] Ensure GitHub workflow examples ship with an explicit Markdown prompt body so GitHub runs do not rely on the current shared Linear default prompt
- [x] Ensure GitHub mode does not require or advertise `linear_graphql`
- [x] Keep the lack of a GitHub dynamic tool explicit in v1 without modifying the existing Linear dynamic tool surface
- [x] Fail safely when a GitHub issue is not linked to a repository
- [x] Add tests proving bootstrap uses issue-derived repository metadata instead of hardcoded workflow repository config

### Milestone 6: Workpad persistence

Files:

- GitHub adapter/client/comment logic
- orchestrator or helper code that owns workpad updates
- tests for comment reuse/update

Checklist:

- [x] Find an existing workpad comment by marker
- [x] Reuse the same comment id instead of creating new progress comments
- [x] Create a workpad comment only when one does not already exist
- [x] Update the same comment id for subsequent progress writes
- [x] Add safe marker and author matching if needed by the GitHub API shape
- [x] Add tests proving steady-state runs use one persistent comment only

### Milestone 7: Docs, workflow samples, and observability

Files:

- [README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/README.md)
- [elixir/README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/README.md)
- [elixir/WORKFLOW.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.md)
- [status_dashboard.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/status_dashboard.ex)

Checklist:

- [x] Keep this `PLANS.md` file as the GitHub source of truth
- [x] Update root README notes to point at `PLANS.md`, not deleted draft docs
- [x] Add GitHub setup guidance to `elixir/README.md`
- [x] Document required GitHub Project workflow settings
- [x] Document `Backlog` vs `Todo`
- [x] Document merge-driven completion with `Closes #123`
- [x] Update or split workflow examples so GitHub config is represented clearly
- [x] Update dashboard/status surfaces so GitHub runs do not render Linear-specific project links or labels

### Milestone 8: Validation and non-regression proof

Checklist:

- [x] Run focused config tests
- [x] Run focused GitHub client and adapter tests
- [x] Run focused orchestrator tests for blocker gating
- [x] Run focused orchestrator tests for capacity-first candidate skip
- [x] Run workspace/bootstrap tests
- [x] Run touched-module `mix test` slices
- [x] Run `mix specs.check`
- [x] Run `make all`
- [x] Record any remaining gaps or intentionally deferred items in this file before calling implementation complete

Completion evidence:

- The previously flaky retry-timing and SSH timing tests were stabilized by synchronizing on actual retry scheduling and port output instead of fixed sleeps or trace-file polling.
- Targeted validation passed while iterating:
  - `mise exec -- mix test test/symphony_elixir/core_test.exs test/symphony_elixir/orchestrator_status_test.exs test/symphony_elixir/orchestrator_github_test.exs test/symphony_elixir/github/client_test.exs test/symphony_elixir/extensions_test.exs test/symphony_elixir/workspace_and_config_test.exs`
  - `mise exec -- mix specs.check`
- Repo-wide validation now passes end to end with the existing `100.00%` coverage gate intact:
  - `mise exec -- make all`
  - test suite: `274 tests, 0 failures, 2 skipped`
  - coverage: `100.00%`
  - dialyzer: `Total errors: 0`

### Milestone 9: Live end-to-end GitHub validation and cleanup

Goal:

- prove the GitHub tracker works in a real disposable setup, not only in unit/module tests
- use Symphony itself against a small dummy GitHub project and repository
- oversee the run, inspect results, and feed any required fixes back into implementation before final signoff

Disposable test assets:

- one temporary private GitHub repository
- one temporary user-owned GitHub Project v2
- a very small dummy app, preferably a todo app with one or two simple enhancement issues
- temporary issues, PRs, project items, and workpad comments created during the run

Checklist:

- [x] Create a temporary private GitHub repository for live validation
- [x] Seed the repository with a minimal dummy app, preferably a small todo app
- [x] Create a temporary user-owned GitHub Project v2 with the required Symphony workflow settings
- [x] Pause for required manual GitHub Project setup before Symphony execution
- [x] Wait for user confirmation that manual GitHub Project setup is complete before continuing
- [x] Create a small set of real GitHub issues in that repo and add them to the project
- [x] Configure a GitHub `WORKFLOW.md` against that disposable project and repository
- [x] Run Symphony end-to-end against the disposable setup
- [x] Oversee the run and verify the full lifecycle:
  - issue intake and candidate polling
  - workspace bootstrap from linked repository metadata
  - persistent workpad comment behavior
  - status transitions
  - blocker handling
  - PR creation/update behavior
  - merge-driven completion
  - issue closure and `Done` movement
- [x] Record concrete evidence for any mismatches between the plan and runtime behavior
- [x] Implement any required follow-up fixes discovered during the live run
- [x] Re-run the live validation after those fixes if needed
- [x] Summarize the final observed behavior and any remaining gaps in this file
- [ ] Delete the temporary GitHub repository, project, issues, PRs, and any other disposable assets created for the live test
- [ ] Confirm the cleanup is complete

Manual GitHub Project setup to complete before the live run:

- disable the built-in workflow `PR linked -> In Progress`
- set item-added intake to `Backlog` instead of `Todo`, or otherwise ensure new items do not land directly in runnable `Todo`
- add or confirm the needed `Status` options in the project:
  - `Backlog`
  - `Todo`
  - `In Progress`
  - `Human Review`
  - `Rework`
  - `Merging`
  - `Done`
- keep the built-in workflow that moves closed issues to `Done`
- keep GitHub repo auto-close for linked issues enabled
- if `Done -> close issue` is enabled for the test project, treat `Done` as terminal only

Completion evidence:

- Disposable assets used:
  - repo: `mahesh0431/symphony-gh-live-20260321-181655`
  - project: `mahesh0431` user project `#9`
- Issue `#1` live flow:
  - claimed from the disposable project into a real workspace clone
  - one persistent workpad comment created and updated in place: `issuecomment-4103379326`
  - PR `#3` opened with `Closes #1`, then merged at `2026-03-21T13:58:17Z`
  - issue auto-closed at `2026-03-21T13:58:18Z`
  - project item moved to `Done`
- Blocker handling and issue `#2` live flow:
  - issue `#2` carried a real `blockedBy` link to issue `#1`
  - while `#1` remained open, `#2` stayed unclaimed until the blocker cleared
  - after PR `#3` merged and issue `#1` closed, Symphony picked up `#2`, created one persistent workpad comment `issuecomment-4103399355`, and moved it through `In Progress` to `Human Review`
  - PR `#4` opened with `Closes #2`
  - after human approval moved the item to `Merging`, Symphony resumed on the existing workspace, ran the landing path, and PR `#4` merged at `2026-03-21T14:10:53Z`
  - issue `#2` auto-closed at `2026-03-21T14:10:54Z`
  - project item moved to `Done`
- Concrete evidence captured during the live run:
  - workspace bootstrap used the linked repo metadata and cloned the disposable repository into `/private/tmp/symphony-live-repo-WWGnk8/workspaces/...`
  - focused browser validation was performed against localhost-served copies of the dummy app for both issues
  - both publish flows hit GitHub email privacy protection `GH007`; the worker recovered by switching the local git author email to the GitHub noreply address and retrying the push
  - final GitHub state before cleanup:
    - both issues closed with `stateReason: COMPLETED`
    - both PRs merged
    - both project items in `Done`
- Remaining gap noted from the live run:
  - the `Merging` turn successfully landed PR `#4`, but the existing workpad comment stayed on the pre-merge `Human Review` summary instead of being refreshed with final landing evidence before the issue auto-closed
  - this did not block the state or merge lifecycle, but it is worth tracking as a workpad-polish follow-up if final landing evidence in the issue thread is required
- Cleanup outcome:
  - deleted successfully:
    - GitHub Project v2 `mahesh0431` project `#9`
    - local disposable clone `/tmp/symphony-live-repo-WWGnk8`
  - still pending:
    - remote repo `mahesh0431/symphony-gh-live-20260321-181655`
  - repo deletion was attempted with `gh repo delete mahesh0431/symphony-gh-live-20260321-181655 --yes` but GitHub returned `HTTP 403: Must have admin rights to Repository` and required a token refresh with the `delete_repo` scope
  - because the remote disposable repo still exists, the final cleanup checkbox items remain open until that repo is deleted and cleanup can be re-confirmed

## Recommended Implementation Order

1. Milestone 1
2. Milestone 2
3. Milestone 3
4. Milestone 4
5. Milestone 5
6. Milestone 6
7. Milestone 7
8. Milestone 8
9. Milestone 9

## Non-Regression Rules

- do not change current Linear polling semantics unless the branch is explicitly guarded by `tracker.kind == "github"`
- do not break `memory` tracker behavior or tests
- do not introduce GitHub state names into Linear-only prompts or docs
- do not require GitHub auth for Linear runs
- do not add `gh` CLI dependencies to tracker core runtime paths
- do not modify the existing `linear_graphql` dynamic tool in this v1 GitHub work
- do not depend on external GitHub Project workflow tweaks for core code correctness except where explicitly documented above

## Open Risks to Watch

- tracker behaviour may need a small expansion for explicit comment update/upsert
- workspace bootstrap changes can accidentally alter current Linear clone flow if not isolated by tracker kind
- config schema growth can make workflow examples harder to read if GitHub fields are not nested cleanly
- project workflow assumptions live partly outside Symphony, so docs must stay explicit

## Later TODOs

- support project URLs in config in addition to numbers
- hard fail or explicit skip when one issue appears in multiple tracked projects
- GitHub App auth and webhook mode
- generic GitHub GraphQL dynamic tool
- richer project field support beyond `Status`
