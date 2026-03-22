# GitHub Integration Cleanup Plan

Status: ready for review  
Date: 2026-03-22

Purpose: this file is the single source of truth for the next GitHub
integration cleanup phase. It follows the current working GitHub integration
with a narrow, mergeability-oriented refactor pass: make shared tracker paths
more tracker-neutral, carry explicit tracker metadata instead of inferring from
map shape, and move only a small set of high-friction policy branches behind
tracker callbacks or capabilities.

## Progress Rules

- [ ] Use this file as the implementation ledger.
- [ ] Treat every checkbox in every milestone as an independently completable item.
- [ ] Mark an item `[X]` immediately after that specific item is done.
- [ ] Do not wait for the whole milestone to finish before marking completed items.
- [ ] If scope changes, add new checklist items in the relevant milestone before implementing them.
- [ ] If a milestone is blocked, leave the blocked item unchecked and add a short note under that milestone.

## Locked Decisions

- keep the current documented GitHub support contract narrow unless a later plan explicitly widens it
- org-backed GitHub Projects are not supported or tested in this cleanup phase
- SSH clone/bootstrap is not supported or tested in this cleanup phase
- do not add dispatch-order or `created_at` behavior changes in this cleanup phase
- do not turn this follow-up into a full tracker abstraction rewrite
- prefer additive capability extraction over broad interface churn
- preserve the current working GitHub tracker behavior while reducing future merge pain
- bias tracker-specific behavior toward tracker-specific modules instead of adding new `tracker.kind` branching in upstream-hot core files
- keep validation targeted while the refactor is in progress, then run broader checks before closing the phase

## Non-Goals for This Follow-Up

- org-backed GitHub Project execution
- SSH clone/bootstrap support
- GitHub App auth
- webhook support
- REST tracker fallbacks
- `created_at`-driven dispatch ordering changes
- a full end-to-end tracker abstraction redesign
- widening the supported GitHub contract beyond the current user-only and HTTPS-only setup
- broad refactors unrelated to tracker-neutrality, explicit metadata, or selected capability extraction

## Implementation Scope

This plan covers the agreed cleanup scope coming out of the GitHub review:

- make tracker-generic shared paths actually tracker-neutral in wording and behavior
- stop inferring tracker kind from incidental issue map shape or repository fields
- carry explicit tracker metadata through normalized issue and prompt/workspace context
- move a small, carefully chosen set of orchestration and workspace policy decisions behind tracker callbacks or capabilities
- keep the current supported GitHub contract narrow unless a later plan explicitly widens it
- preserve upstream mergeability by keeping the change set incremental and avoiding a rewrite

This follow-up is intentionally not a rewrite plan. The target outcome is a
cleaner boundary with less tracker-specific drift in shared runtime paths, while
keeping the current GitHub integration behavior stable and the future upstream
merge story more manageable.

## Current Code Surface

Primary implementation touch points:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [agent_runner.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/agent_runner.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [orchestrator.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/orchestrator.ex)
- [status_dashboard.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/status_dashboard.ex)
- [github/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/adapter.ex)
- [github/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/issue.ex)
- [linear/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/adapter.ex)
- [linear/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/issue.ex)

Primary test surfaces:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)

Docs/examples to re-check only if needed to avoid contradiction:

- [elixir/README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/README.md)
- [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md)

## Progress

- [X] Milestone 1: Make shared tracker-generic paths tracker-neutral
- [X] Milestone 2: Carry explicit tracker metadata end-to-end
- [X] Milestone 3: Extract the first tracker capabilities for workspace and shared rendering paths
- [X] Milestone 4: Extract low-risk orchestration policy hooks
- [X] Milestone 5: Validation and regression proof

## Milestones

### Milestone 1: Make shared tracker-generic paths tracker-neutral

Files:

- [agent_runner.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/agent_runner.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)

Checklist:

- [X] Replace tracker-specific continuation and shared-runtime wording that still assumes Linear in generic paths
- [X] Remove any tracker-kind fallback behavior in shared prompt helpers that depends on incidental map shape
- [X] Keep the existing prompt contract stable where possible while making tracker identity resolution explicit
- [X] Add or update focused tests proving shared wording and prompt rendering remain correct for GitHub, Linear, and memory contexts

### Milestone 2: Carry explicit tracker metadata end-to-end

Files:

- [github/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/issue.ex)
- [linear/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/issue.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [github/client.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/client.ex)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)

Checklist:

- [X] Decide on one explicit tracker metadata shape that can travel through normalized issue/context data without map-shape inference
- [X] Populate that metadata in GitHub and Linear issue normalization paths without widening the supported GitHub contract
- [X] Update shared consumers to read the explicit tracker metadata instead of re-deriving tracker kind from repository fields or struct shape
- [X] Keep current repository-aware GitHub prompt and workspace behavior intact after the metadata change
- [X] Add or update tests proving tracker metadata survives the relevant parsing, prompt, and workspace flows

### Milestone 3: Extract the first tracker capabilities for workspace and shared rendering paths

Files:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [status_dashboard.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/status_dashboard.ex)
- [github/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/adapter.ex)
- [linear/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/adapter.ex)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)

Checklist:

- [X] Add the smallest useful capability or callback surface needed for tracker-specific workspace bootstrap and repository source selection
- [X] Move shared dashboard or project-link rendering decisions behind tracker-provided behavior where that reduces core branching cleanly
- [X] Keep the capability surface intentionally small and avoid extracting behavior that is still genuinely shared
- [X] Add or update tests proving GitHub-specific bootstrap and project-link behavior still works while Linear and memory behavior remain unchanged

### Milestone 4: Extract low-risk orchestration policy hooks

Files:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [orchestrator.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/orchestrator.ex)
- [github/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/adapter.ex)
- [linear/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/adapter.ex)
- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)

Checklist:

- [X] Identify one or two orchestration policy branches that are currently the highest-friction `tracker.kind` checks and are safe to extract now
- [X] Move only those low-risk policy decisions behind tracker callbacks or capability checks
- [X] Keep candidate polling semantics and blocker handling stable unless an extraction is clearly behavior-preserving
- [X] Defer any extraction that starts to widen into dispatch-order or broader scheduler changes instead of forcing it into this phase
- [X] Add or update focused tests that lock the intended tracker-specific policy behavior after extraction

Milestone 4 implementation note (2026-03-22):

- extracted two low-risk orchestration policy hooks only: candidate-poll slot gating and active-state runnability
- deliberately deferred blocker completion/extraction paths that would broaden scheduler or dispatch-order scope in this phase

### Milestone 5: Validation and regression proof

Files:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)
- optional contradiction check in [elixir/README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/README.md) and [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md) only if changes are required to avoid drift

Checklist:

- [X] Run targeted tests for the shared-path, metadata, workspace, and orchestration slices touched by this refactor
- [X] Run a broader repo check after the targeted slices are green
- [X] Re-check that the documented support contract remains narrow and was not accidentally widened by code or test changes
- [X] Confirm org-backed, SSH, and `created_at` paths remain explicitly out of scope for this phase
- [X] Summarize any remaining tracker-boundary follow-ups as deferred work instead of widening this plan during implementation

Milestone 5 validation note (2026-03-22):

- targeted validation command passed: `cd elixir && mise exec -- mix test test/symphony_elixir/core_test.exs test/symphony_elixir/workspace_and_config_test.exs test/symphony_elixir/orchestrator_status_test.exs test/symphony_elixir/github/client_test.exs` (`177 tests, 0 failures`)
- broader validation command passed: `cd elixir && mise exec -- make all` (setup/build/fmt-check/lint/coverage/dialyzer all green; coverage `100.00%` total)

Deferred follow-ups kept out of scope for this pass:

- widening the supported GitHub contract to org-backed Projects or SSH bootstrap
- deeper tracker abstraction work beyond the first capability extractions listed here
- dispatch-order or scheduler behavior changes tied to `created_at` or broader fairness policy
