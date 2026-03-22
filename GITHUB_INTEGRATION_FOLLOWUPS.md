# GitHub Integration Follow-ups

Purpose: capture the next high-level cleanup directions for the GitHub
tracker work without turning this into an implementation-ready plan yet.

## Goals

- keep the current GitHub integration working while reducing future merge pain
- make shared runtime paths more tracker-neutral
- align the documented support contract with the runtime we actually want to
  carry forward

## Recommended Follow-up Areas

### 1. Make shared paths tracker-neutral

Reduce tracker-specific wording and logic in generic runtime paths so shared
modules do not assume Linear by default.

Examples:

- continuation and retry messaging should talk about a generic tracker issue
- shared prompt helpers should not infer tracker type from incidental map shape

### 2. Carry explicit tracker metadata

Pass explicit tracker metadata through normalized issue/context objects instead
of re-deriving tracker kind from repository fields or other heuristics.

This should make future tracker additions safer and make GitHub behavior easier
to reason about.

### 3. Move selected policy behind tracker capabilities

Gradually move the most tracker-specific orchestration and workspace decisions
behind tracker callbacks or capability-style interfaces.

Good candidates:

- candidate polling policy
- blocker interpretation
- workspace bootstrap and repository source selection
- workpad update behavior
- tracker-specific dashboard/project link rendering

This is not a call for a full rewrite. The goal is to extract the highest-friction
branches first.

### 4. Align docs and runtime contract

Decide whether the supported GitHub contract is truly:

- user-owned projects only
- HTTPS-only bootstrap only

If yes, runtime and tests should eventually match that narrow contract more
closely. If no, docs should be widened to describe the broader supported shape.

### 5. Preserve upstream mergeability

Favor changes that keep GitHub-specific behavior inside tracker-specific
modules where possible, and minimize new branching in upstream-hot files such
as orchestration, workspace, prompt, and status rendering paths.

## Suggested Sequence

1. Clean up tracker-generic wording and explicit tracker metadata.
2. Extract a small set of tracker capabilities for the most obvious policy
   branches.
3. Reconcile docs/runtime/test scope for user-only and HTTPS-only support.
4. Re-evaluate whether any remaining core-file branching still needs to move.

## Out of Scope for This Note

- detailed callback signatures
- implementation task breakdown
- test matrix expansion
- org-backed or SSH support decisions beyond documenting the current direction
