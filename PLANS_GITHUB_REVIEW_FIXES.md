# GitHub Review Fixes Plan

Status: ready for review  
Date: 2026-03-22

Purpose: this file is the single source of truth for the next narrow GitHub
review-fixes pass. It follows the current working GitHub integration and the
completed cleanup follow-up work, but keeps this phase intentionally tight:
derive GitHub project URLs from the existing configured tracker endpoint, make
tracker-kind resolution strict and centralized around normalized issue metadata,
and align GitHub example-workflow testing with the repo's actual precedent
instead of expanding template-test coverage.

## Progress Rules

- [ ] Use this file as the implementation ledger.
- [ ] Treat every checkbox in every milestone as an independently completable item.
- [ ] Mark an item `[X]` immediately after that specific item is done.
- [ ] Do not wait for the whole milestone to finish before marking completed items.
- [ ] If scope changes, add new checklist items in the relevant milestone before implementing them.
- [ ] If a milestone is blocked, leave the blocked item unchecked and add a short note under that milestone.

## Locked Decisions

- keep the current documented GitHub support contract narrow unless a later plan explicitly widens it
- do not introduce a new `tracker.web_url` config field, alias, or parallel GitHub web-URL override in this pass
- GitHub project URLs must use the existing configured tracker endpoint as their source of truth instead of a hardcoded `github.com` host
- endpoint-derived GitHub project URL handling is a consistency fix only; it does not widen the supported GitHub contract
- use one shared tracker-kind resolver for shared runtime paths that need tracker identity
- treat `tracker_metadata.kind` as the intended canonical tracker source for normalized issue/runtime context
- workflow config may supply tracker kind only when there is no normalized issue context at all
- do not silently fall back to Linear when a normalized issue context is missing, invalid, or ambiguous about tracker kind
- do not turn this pass into a broad tracker-boundary cleanup or abstraction rewrite
- do not take on the partial-boundary cleanup items already deferred in orchestrator unless one is directly required to land an approved fix
- keep edits incremental, behavior-preserving, and validation-focused
- preserve current working behavior outside the three approved review fixes

## Non-Goals for This Follow-Up

- widening the supported GitHub contract beyond the current documented user-owned and HTTPS-bootstrap setup
- adding a new GitHub-specific web URL setting
- claiming broad GitHub Enterprise or arbitrary endpoint-shape support beyond the minimal endpoint-to-web derivation needed here
- broader tracker abstraction or boundary cleanup outside the selected resolver consolidation
- scheduler, dispatch-order, or blocker-policy changes
- opportunistic orchestrator cleanup unrelated to one of the three approved fixes
- turning checked-in workflow examples into a broad template-render or snapshot-test suite

## Implementation Scope

This plan covers only the agreed review-fix scope:

- replace hardcoded GitHub project URL generation with endpoint-derived project URL generation using the existing configured tracker endpoint
- centralize tracker-kind resolution behind one shared strict resolver
- make normalized `tracker_metadata.kind` the canonical runtime source for per-issue tracker identity
- remove silent per-issue fallback-to-Linear behavior from shared runtime paths
- keep workflow-config tracker kind as a config-only fallback when no normalized issue context exists at all
- align GitHub example-workflow testing with current repo precedent and avoid keeping heavy GitHub-only template tests if there is no matching tested Linear starter-template precedent

This follow-up is intentionally not a broader cleanup pass. The target outcome
is to close the accepted review gaps with the smallest set of runtime and test
changes needed to make behavior explicit, strict, and easier to reason about,
without widening the public GitHub contract or reopening unrelated tracker
boundary work.

## Current Code Surface

Primary implementation touch points:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [github/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/adapter.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [github/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/issue.ex)
- [linear/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/issue.ex)
- optional targeted touch in [orchestrator.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/orchestrator.ex) only if the shared resolver cannot land cleanly without it

Primary test surfaces:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)

Docs/examples to re-check only if needed to avoid contradiction:

- [PLANS_GITHUB_INTEGRATION_FOLLOWUPS.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS_GITHUB_INTEGRATION_FOLLOWUPS.md)
- [PLANS_REVIEW.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS_REVIEW.md)
- [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md)

## Progress

- [X] Milestone 1: Lock decisions and validation boundaries for the review fixes
- [X] Milestone 2: Endpoint-derived GitHub project URL fix
- [X] Milestone 3: Strict unified tracker-kind resolution
- [X] Milestone 4: GitHub example-workflow test alignment
- [X] Milestone 5: Validation and regression proof

## Milestones

### Milestone 1: Lock decisions and validation boundaries for the review fixes

Files:

- [PLANS_GITHUB_REVIEW_FIXES.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS_GITHUB_REVIEW_FIXES.md)
- optional contradiction-only note updates in [PLANS_GITHUB_INTEGRATION_FOLLOWUPS.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS_GITHUB_INTEGRATION_FOLLOWUPS.md) or [PLANS_REVIEW.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS_REVIEW.md) only if implementation later requires clarifying cross-plan boundaries

Checklist:

- [X] Restate the three approved fixes and explicit deferrals before any runtime edits begin
- [X] Confirm this pass does not add a new config field for GitHub web URLs
- [X] Confirm workflow config is allowed as tracker-kind input only when there is no normalized issue context at all
- [X] Confirm per-issue runtime paths must not silently drift to Linear when normalized tracker metadata is missing or invalid
- [X] Define the targeted validation slice up front so failures remain attributable to one approved fix at a time

Targeted validation slice for this Milestone 1-2 implementation pass:

- [X] `cd elixir && mise exec -- mix test test/symphony_elixir/core_test.exs:997 test/symphony_elixir/core_test.exs:1022 test/symphony_elixir/orchestrator_status_test.exs:1011 test/symphony_elixir/orchestrator_status_test.exs:1051`

### Milestone 2: Endpoint-derived GitHub project URL fix

Files:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [github/adapter.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/adapter.ex)
- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)

Checklist:

- [X] Replace hardcoded `https://github.com/...` project URL generation with a helper that derives the web base from the existing configured GitHub tracker endpoint
- [X] Keep public GitHub behavior unchanged for the default `https://api.github.com/graphql` endpoint
- [X] Limit endpoint-to-web derivation to the smallest behavior-preserving transformation needed for configured GitHub endpoints already accepted by this repo
- [X] Keep Linear project URL behavior and non-GitHub tracker helper fallbacks unchanged
- [X] Add or update focused tests proving GitHub project links in helper and dashboard paths follow the configured endpoint while the default public endpoint still renders the same URLs as today

### Milestone 3: Strict unified tracker-kind resolution

Files:

- [tracker.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/tracker.ex)
- [prompt_builder.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/prompt_builder.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [github/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/issue.ex)
- [linear/issue.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/linear/issue.ex)
- optional targeted touch in [orchestrator.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/orchestrator.ex) only if a narrow compatibility shim is required
- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)

Checklist:

- [X] Introduce one shared resolver for tracker-kind decisions instead of keeping duplicated normalization and fallback logic in tracker, prompt, and workspace paths
- [X] Make `tracker_metadata.kind` the canonical tracker source for normalized GitHub and Linear issue contexts
- [X] Keep normalized issue producers aligned with that contract so the canonical tracker metadata remains populated where issue context exists
- [X] Allow workflow-config tracker kind only when the caller truly has no normalized issue context at all
- [X] Remove silent fallback-to-Linear behavior from adapter selection and other shared runtime paths that currently infer tracker kind too loosely
- [X] Defer any broader resolver or adapter cleanup that would widen into tracker-boundary redesign instead of forcing it into this pass
- [X] Add or update focused tests proving GitHub and Linear normalized issue contexts resolve strictly, invalid per-issue tracker kind does not drift to Linear, and config-only paths still work where no normalized issue context exists

### Milestone 4: GitHub example-workflow test alignment

Files:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md) only if a contradiction fix is required after test narrowing

Checklist:

- [X] Compare the current GitHub example-workflow tests against actual repo precedent for checked-in starter templates before changing coverage
- [X] If the repo still does not treat a checked-in Linear example workflow as a tested starter template, remove or narrow heavy GitHub-only contract/render tests instead of preserving asymmetric template-test weight
- [X] Keep only the minimum coverage needed to prove the GitHub example remains loadable, coherent with the supported narrow contract, and non-contradictory with canonical workflow guidance
- [X] Avoid expanding this pass into broad example-template rendering, snapshot, or doc-contract testing
- [X] Preserve the example file content unless a direct contradiction with the approved scope is uncovered

Milestone 4 completion note:

- removed the heavyweight GitHub-only prompt-render contract test and kept one narrow `Workflow.load/0` coherence check for `WORKFLOW.github.example.md`
- left `WORKFLOW.github.example.md` unchanged because no direct contradiction with approved scope was found
- targeted validation passed: `cd elixir && mise exec -- mix test test/symphony_elixir/core_test.exs:93`

Milestone 4 starting-point note (current repo state):

- the repo currently checks in [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md) but no matching checked-in `WORKFLOW.linear.example.md`; treat that asymmetry as a precedent check before keeping heavy GitHub-only example-template tests

### Milestone 5: Validation and regression proof

Files:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [orchestrator_status_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/orchestrator_status_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)
- optional contradiction-only re-check in [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md)

Checklist:

- [X] Run targeted tests for endpoint-derived project URLs, strict tracker-kind resolution, workspace/prompt issue-context behavior, and status dashboard project-link rendering
- [X] Run a broader repo check only after the targeted slices are green
- [X] Re-check that the GitHub support contract was not widened and that no new GitHub web-URL config field was introduced
- [X] Confirm any orchestrator touch stayed strictly limited to what was needed for an approved fix
- [X] Summarize any remaining tracker-boundary or template-test cleanup as deferred work instead of widening this plan during implementation

Expected targeted validation slice:

- [X] `cd elixir && mise exec -- mix test test/symphony_elixir/core_test.exs test/symphony_elixir/workspace_and_config_test.exs test/symphony_elixir/orchestrator_status_test.exs test/symphony_elixir/github/client_test.exs`

Milestone 5 execution note:

- targeted validation initially failed due a cascading test-order regression (`SymphonyElixir.Application.stop(:normal)` in `orchestrator_status_test.exs` left the app stopped for later test setup); fixed with a minimal `on_exit` app restart in that test
- targeted slice rerun passed after the fix (`179 tests, 0 failures`)
- coverage blocker follow-up (kept narrow to review-fix surfaces):
  - identified uncovered review-fix branches in `tracker.ex`, `github/adapter.ex`, and `prompt_builder.ex`
  - added focused tests in `core_test.exs` and `workspace_and_config_test.exs` to cover strict resolver and endpoint-derived URL edge cases
  - removed two unreachable defensive branches introduced in `github/adapter.ex` so coverage reflects executable behavior only
  - reran targeted slice: `cd elixir && mise exec -- mix test test/symphony_elixir/core_test.exs test/symphony_elixir/workspace_and_config_test.exs test/symphony_elixir/orchestrator_status_test.exs test/symphony_elixir/github/client_test.exs` (passes: `181 tests, 0 failures`)
- broader checks run only after targeted green:
  - `cd elixir && mise exec -- make all` reached `100.00%` total coverage, then failed in Dialyzer with:
    `lib/symphony_elixir/workspace.ex:604:8:pattern_match_cov The pattern variable __issue@1 can never match the type, because it is covered by previous clauses.`
  - fixed the Dialyzer blocker with the smallest runtime change: removed the unreachable fallback clause `defp issue_context_tracker_kind(_issue), do: nil` in `workspace.ex`
  - reran `cd elixir && mise exec -- make all`; final result: passes end-to-end (coverage `100.00%`, Dialyzer `done (passed successfully)`)
- support contract re-check: no `tracker.web_url` (or equivalent GitHub web-URL config field) was introduced in this pass
- orchestrator touch remained narrow to a test-only restart guard in `orchestrator_status_test.exs` needed to keep Milestone 5 validation deterministic

Deferred follow-ups kept out of scope for this pass:

- a broader tracker-boundary cleanup beyond the shared strict resolver needed here
- additional orchestrator boundary cleanup already deferred in the prior GitHub integration follow-up
- any new GitHub config surface for web URLs
- broader workflow-example testing strategy work beyond the narrow alignment called out above
