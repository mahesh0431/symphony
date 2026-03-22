defmodule SymphonyElixir.GitHub.AdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.Adapter

  defmodule FakeGitHubClient do
    def fetch_candidate_issues do
      send(self(), :github_fetch_candidate_issues_called)
      {:ok, [:candidate]}
    end

    def fetch_issues_by_states(states) do
      send(self(), {:github_fetch_issues_by_states_called, states})
      {:ok, states}
    end

    def fetch_issue_states_by_ids(issue_ids) do
      send(self(), {:github_fetch_issue_states_by_ids_called, issue_ids})
      {:ok, issue_ids}
    end

    def create_comment(issue_id, body) do
      send(self(), {:github_create_comment_called, issue_id, body})
      Process.get({__MODULE__, :create_comment_result}, {:ok, "comment-1"})
    end

    def upsert_workpad_comment(issue_id, body) do
      send(self(), {:github_upsert_workpad_comment_called, issue_id, body})
      Process.get({__MODULE__, :upsert_workpad_comment_result}, :ok)
    end

    def update_issue_state(issue_id, state_name) do
      send(self(), {:github_update_issue_state_called, issue_id, state_name})
      Process.get({__MODULE__, :update_issue_state_result}, :ok)
    end
  end

  setup do
    previous_client_module = Application.get_env(:symphony_elixir, :github_client_module)

    Application.put_env(:symphony_elixir, :github_client_module, FakeGitHubClient)

    on_exit(fn ->
      if is_nil(previous_client_module) do
        Application.delete_env(:symphony_elixir, :github_client_module)
      else
        Application.put_env(:symphony_elixir, :github_client_module, previous_client_module)
      end
    end)

    :ok
  end

  test "github adapter delegates reads and tracker-facing mutations" do
    assert {:ok, [:candidate]} = Adapter.fetch_candidate_issues()
    assert_receive :github_fetch_candidate_issues_called

    assert {:ok, ["Todo"]} = Adapter.fetch_issues_by_states(["Todo"])
    assert_receive {:github_fetch_issues_by_states_called, ["Todo"]}

    assert {:ok, ["issue-1"]} = Adapter.fetch_issue_states_by_ids(["issue-1"])
    assert_receive {:github_fetch_issue_states_by_ids_called, ["issue-1"]}

    assert :ok = Adapter.create_comment("issue-1", "hello")
    assert_receive {:github_create_comment_called, "issue-1", "hello"}

    Process.put({FakeGitHubClient, :create_comment_result}, {:error, :boom})
    assert {:error, :boom} = Adapter.create_comment("issue-1", "boom")

    Process.put({FakeGitHubClient, :create_comment_result}, :unexpected)
    assert {:error, :github_comment_create_failed} = Adapter.create_comment("issue-1", "odd")

    assert :ok = Adapter.upsert_workpad_comment("issue-1", "## Codex Workpad")
    assert_receive {:github_upsert_workpad_comment_called, "issue-1", "## Codex Workpad"}

    Process.put({FakeGitHubClient, :upsert_workpad_comment_result}, {:error, :boom})
    assert {:error, :boom} = Adapter.upsert_workpad_comment("issue-1", "broken")

    assert :ok = Adapter.update_issue_state("issue-1", "Done")
    assert_receive {:github_update_issue_state_called, "issue-1", "Done"}

    Process.put({FakeGitHubClient, :update_issue_state_result}, {:error, :state_not_found})
    assert {:error, :state_not_found} = Adapter.update_issue_state("issue-1", "Missing")
  end
end
