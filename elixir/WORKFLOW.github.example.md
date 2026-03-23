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
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex app-server
---

# GitHub Issue

- Identifier: {{ issue.identifier }}
- Title: {{ issue.title }}
- Repository: {{ repository.name_with_owner }}
- Default branch: {{ repository.default_branch }}
- Issue URL: {{ issue.url }}
- Project URL: {{ project.url }}

## Runtime notes

- Keep the body aligned with `WORKFLOW.md`; only the tracker front matter and GitHub issue
  header should differ.
- This example is intentionally scoped to user-owned GitHub Projects only.
- Keep `owner.type: user`; org-backed Projects are not supported or tested in this pass.
- Keep each runnable GitHub issue attached to only one tracked GitHub Project item at a time.
- If the same issue is present in more than one tracked GitHub Project, status refresh/update
  behavior is not guaranteed in this pass.
- Use `Backlog` as intake and `Todo` as the first runnable state.
- When GitHub allows it, scope `Item added to project` to `issue` only and route those items to
  `Backlog`.
- Keep `Human Review` outside `active_states`.
- Use `Human Review -> Merging -> Done` as the intended approval and landing flow.
- Use merge-driven completion with a PR body such as `Closes #123`.
- GitHub v1 does not inject a GitHub-specific dynamic tool.
- This follow-up expects HTTPS-based repository bootstrap only.
- SSH clone/bootstrap is not supported or tested in this pass.

## Description

{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}
