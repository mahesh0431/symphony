# GitHub Review Implementation Plan

Status: ready for review  
Date: 2026-03-21

Purpose: this file is the single source of truth for implementing the agreed
follow-up changes from the GitHub tracker review. It is intentionally narrower
than [PLANS.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS.md)
and only covers the accepted review items.

## Progress Rules

- [ ] Use this file as the implementation ledger.
- [ ] Treat every checkbox in every milestone as an independently completable item.
- [ ] Mark an item `[X]` immediately after that specific item is done.
- [ ] Do not wait for the whole milestone to finish before marking completed items.
- [ ] If scope changes, add new checklist items in the relevant milestone before implementing them.
- [ ] If a milestone is blocked, leave the blocked item unchecked and add a short note under that milestone.

## Locked Decisions

- keep GitHub tracker ownership support user-only in this follow-up
- org-backed GitHub Projects are not supported or tested in this pass
- keep GitHub workspace bootstrap HTTPS-only in this follow-up
- SSH clone/bootstrap is not supported or tested in this pass
- make `tracker.endpoint` a real configurable `WORKFLOW.md` field
- keep the default GitHub endpoint `https://api.github.com/graphql` when unset or blank
- do not add GitHub `created_at` dispatch-order support in this pass
- keep the current PAT-based GitHub auth model
- keep the current GraphQL-only tracker path
- do not expand GitHub dynamic-tool support in this pass

## Non-Goals for This Follow-Up

- org-backed GitHub Project execution
- SSH clone/bootstrap support
- GitHub App auth
- webhook support
- REST tracker fallbacks
- `createdAt`-driven dispatch ordering changes
- live end-to-end validation against a real org-backed Project
- live end-to-end validation of SSH-based repository bootstrap

## Implementation Scope

This plan covers the agreed implementation scope coming out of the review:

- clarify and document the current GitHub tracker scope as user-only for now
- clarify and document the current GitHub bootstrap scope as HTTPS-only for now
- make `tracker.endpoint` truly configurable instead of fixed to `api.github.com`
- leave GitHub dispatch ordering unchanged for now

This follow-up is intentionally a v1 contract/documentation clarification pass.
Where broader runtime behavior still exists today, this plan narrows the
documented and tested contract without claiming that every broader behavior path
has already been removed. In particular, this pass keeps the public GitHub
tracker example and supported setup user-only and HTTPS-only, even if other
runtime-adjacent code paths still exist outside that supported contract.

## Current Code Surface

Primary implementation touch points:

- [config.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config.ex)
- [schema.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config/schema.ex)
- [workspace.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/workspace.ex)
- [github/client.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/github/client.ex)
- [elixir/README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/README.md)
- [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md)

Primary test surfaces:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)

## Progress

- [X] Milestone 1: Lock the v1 GitHub scope in docs and examples
- [X] Milestone 2: Make `tracker.endpoint` fully configurable
- [X] Milestone 3: Validation and regression proof

## Milestones

### Milestone 1: Lock the v1 GitHub scope in docs and examples

Files:

- [elixir/README.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/README.md)
- [WORKFLOW.github.example.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/WORKFLOW.github.example.md)
- optional targeted comment updates in [PLANS.md](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/PLANS.md) only if they are needed to avoid contradiction

Checklist:

- [X] Add an explicit user-only disclaimer to the GitHub setup docs
- [X] State that org-backed Projects are not supported or tested in this pass
- [X] Keep the example `owner.type: user` and make that expectation obvious
- [X] Add an explicit HTTPS-only bootstrap disclaimer to the GitHub docs/example
- [X] State that SSH clone/bootstrap is not supported or tested in this pass
- [X] Verify there is no doc/example text implying org or SSH support in this follow-up

### Milestone 2: Make `tracker.endpoint` fully configurable

Files:

- [config.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config.ex)
- [schema.ex](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/lib/symphony_elixir/config/schema.ex)
- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)

Checklist:

- [X] Remove the exact-match GitHub endpoint validation that blocks custom endpoints
- [X] Keep the default GitHub endpoint when `tracker.endpoint` is omitted or blank
- [X] Keep the current guard against silently inheriting the Linear default endpoint in GitHub mode
- [X] Ensure the runtime still reads the configured GitHub endpoint from `WORKFLOW.md`
- [X] Add tests proving a non-default GitHub endpoint passes config validation
- [X] Keep current Linear and Memory endpoint behavior unchanged

### Milestone 3: Validation and regression proof

Files:

- [core_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/core_test.exs)
- [workspace_and_config_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/workspace_and_config_test.exs)
- [github/client_test.exs](/Users/I562188/SAP%20Projects%20MacBook/symphony-openai/elixir/test/symphony_elixir/github/client_test.exs)

Checklist:

- [X] Run targeted tests for config parsing and GitHub client endpoint handling
- [X] Add or update tests that lock the intended user-only and HTTPS-only contract where practical
- [X] Re-check docs and example workflow for contradiction after code/test changes
- [X] Confirm `created_at` work remains out of scope for this pass
- [X] Summarize any remaining deferred items as explicit follow-ups instead of widening this plan

Deferred follow-ups kept out of scope for this pass:

- remove or narrow broader runtime-adjacent GitHub owner-type and SSH-adjacent paths if the implementation contract is later tightened beyond the documented v1 scope
- revisit GitHub dispatch ordering separately if `created_at` should become part of the supported scheduling contract
