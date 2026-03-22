defmodule SymphonyElixir.OrchestratorGitHubTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.Issue, as: GitHubIssue

  test "github todo issues only unblock on closed plus completed blockers" do
    write_github_workflow!()

    base_state = empty_state()

    Enum.each(["NOT_PLANNED", "DUPLICATE", "REOPENED"], fn state_reason ->
      blocked_issue =
        github_issue(
          id: "issue-#{state_reason}",
          blocked_by: [%{id: "blocker-1", state: "CLOSED", state_reason: state_reason}]
        )

      refute Orchestrator.should_dispatch_issue_for_test(blocked_issue, base_state)
    end)

    ready_issue =
      github_issue(
        id: "issue-ready",
        blocked_by: [%{id: "blocker-2", state: "CLOSED", state_reason: "COMPLETED"}]
      )

    assert Orchestrator.should_dispatch_issue_for_test(ready_issue, base_state)
  end

  test "github backlog and human review stay non-runnable even when configured active" do
    write_github_workflow!(active_states: ["Backlog", "Todo", "Human Review", "In Progress"])

    state = empty_state()

    refute Orchestrator.should_dispatch_issue_for_test(
             github_issue(id: "issue-backlog", state: "Backlog"),
             state
           )

    refute Orchestrator.should_dispatch_issue_for_test(
             github_issue(id: "issue-human-review", state: "Human Review"),
             state
           )
  end

  test "github skips candidate polling when no agent slots are free but linear remains unchanged" do
    full_state = running_state(github_issue(id: "running-1", state: "In Progress"), 1)

    write_github_workflow!(max_concurrent_agents: 1)
    refute Orchestrator.should_poll_candidates_for_test(full_state)

    write_workflow_file!(Workflow.workflow_file_path(), max_concurrent_agents: 1)
    assert Orchestrator.should_poll_candidates_for_test(full_state)
  end

  test "github running issue reconciliation keeps active workers when issue stays active" do
    write_github_workflow!(active_states: ["Todo", "In Progress", "Rework", "Merging"])

    running_issue = github_issue(id: "issue-keep", state: "Todo")
    state = running_state(running_issue, 2)
    refreshed_issue = %{running_issue | state: "In Progress"}

    updated_state = Orchestrator.reconcile_issue_states_for_test([refreshed_issue], state)

    assert updated_state.running["issue-keep"].issue.state == "In Progress"
    assert MapSet.member?(updated_state.claimed, "issue-keep")
  end

  defp empty_state do
    %Orchestrator.State{
      max_concurrent_agents: 3,
      running: %{},
      claimed: MapSet.new(),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }
  end

  defp running_state(issue, max_concurrent_agents) do
    %Orchestrator.State{
      max_concurrent_agents: max_concurrent_agents,
      running: %{
        issue.id => %{
          pid: self(),
          ref: make_ref(),
          identifier: issue.identifier,
          issue: issue,
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue.id]),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }
  end

  defp github_issue(attrs) do
    defaults = %{
      id: "issue-1",
      identifier: "octo-org/example#1",
      number: 1,
      title: "GitHub issue",
      description: "Tracked via GitHub",
      state: "Todo",
      state_option_id: "opt-todo",
      issue_state: "OPEN",
      issue_state_reason: nil,
      url: "https://github.com/octo-org/example/issues/1",
      repository_name_with_owner: "octo-org/example",
      repository_url: "https://github.com/octo-org/example",
      repository_ssh_url: "git@github.com:octo-org/example.git",
      repository_default_branch: "main",
      project_id: "project-1",
      project_number: 1,
      project_title: "Project 1",
      project_url: "https://github.com/users/octo-org/projects/1",
      project_item_id: "item-1",
      status_field_id: "field-1",
      status_field_name: "Status",
      blocked_by: [],
      labels: [],
      assigned_to_worker: true,
      project_items: [],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(GitHubIssue, Map.merge(defaults, Map.new(attrs)))
  end

  defp write_github_workflow!(opts \\ []) do
    active_states = Keyword.get(opts, :active_states, ["Todo", "In Progress", "Rework", "Merging"])
    max_concurrent_agents = Keyword.get(opts, :max_concurrent_agents, 10)

    write_raw_workflow!(
      Workflow.workflow_file_path(),
      """
      ---
      tracker:
        kind: github
        endpoint: "https://api.github.com/graphql"
        api_key: "gh-token"
        owner: {login: "octo-org"}
        projects: [{number: 1}]
        status_field_name: "Status"
        active_states: #{yaml_list(active_states)}
        terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
      agent:
        max_concurrent_agents: #{max_concurrent_agents}
      ---
      You are an agent for this repository.
      """
    )
  end

  defp yaml_list(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &~s("#{&1}")) <> "]"
  end

  defp write_raw_workflow!(path, contents) do
    File.write!(path, contents)

    if Process.whereis(SymphonyElixir.WorkflowStore) do
      SymphonyElixir.WorkflowStore.force_reload()
    end

    :ok
  end
end
