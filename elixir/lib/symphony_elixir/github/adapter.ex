defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.Client

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: client_module().fetch_candidate_issues()

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: client_module().fetch_issues_by_states(states)

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: client_module().fetch_issue_states_by_ids(issue_ids)

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    case client_module().create_comment(issue_id, body) do
      {:ok, _comment_id} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_comment_create_failed}
    end
  end

  @spec upsert_workpad_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def upsert_workpad_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    client_module().upsert_workpad_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    client_module().update_issue_state(issue_id, state_name)
  end

  @spec workspace_bootstrap_clone_source(map()) :: {:ok, String.t()} | :skip | {:error, term()}
  def workspace_bootstrap_clone_source(issue_context) when is_map(issue_context) do
    case issue_context_value(issue_context, :github_clone_url) ||
           issue_context_value(issue_context, :repository_url) ||
           issue_context_value(issue_context, :repository_ssh_url) do
      clone_source when is_binary(clone_source) and clone_source != "" ->
        {:ok, clone_source}

      _ ->
        missing_identifier =
          issue_context_value(issue_context, :project_item_id) ||
            issue_context_value(issue_context, :issue_id) ||
            issue_context_value(issue_context, :issue_identifier)

        {:error, {:github_issue_repository_missing, missing_identifier}}
    end
  end

  def workspace_bootstrap_clone_source(_issue_context), do: :skip

  @spec project_urls(map()) :: [String.t()]
  def project_urls(tracker) when is_map(tracker) do
    owner = Map.get(tracker, :owner) || Map.get(tracker, "owner")
    owner_type = github_owner_type(owner)
    owner_login = github_owner_login(owner)
    web_base = tracker |> github_endpoint() |> endpoint_to_project_web_base()

    tracker
    |> github_projects()
    |> Enum.map(&github_project_url(web_base, owner_type, owner_login, &1))
    |> Enum.reject(&is_nil/1)
  end

  def project_urls(_tracker), do: []

  @spec candidate_poll_requires_available_slots?() :: boolean()
  def candidate_poll_requires_available_slots?, do: true

  @spec runnable_active_state?(String.t()) :: boolean()
  def runnable_active_state?(state_name) when is_binary(state_name) do
    normalized_state = state_name |> String.trim() |> String.downcase()
    normalized_state not in ["backlog", "human review"]
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :github_client_module, Client)
  end

  defp issue_context_value(issue_context, key) when is_map(issue_context) do
    Map.get(issue_context, key) || Map.get(issue_context, to_string(key))
  end

  defp github_projects(tracker) when is_map(tracker) do
    Map.get(tracker, :projects) || Map.get(tracker, "projects") || []
  end

  defp github_owner_type(owner) when is_map(owner) do
    owner_type = Map.get(owner, :type) || Map.get(owner, "type")

    case owner_type do
      owner_type when owner_type in ["organization", "org"] -> "org"
      owner_type when owner_type in ["user", "users"] -> "user"
      _ -> nil
    end
  end

  defp github_owner_type(_owner), do: nil

  defp github_owner_login(owner) when is_map(owner) do
    Map.get(owner, :login) || Map.get(owner, "login")
  end

  defp github_owner_login(_owner), do: nil

  defp github_project_url(web_base, owner_type, owner_login, project)
       when is_binary(web_base) and owner_type in ["org", "user"] and is_binary(owner_login) do
    case github_project_number(project) do
      project_number when is_integer(project_number) ->
        "#{web_base}/#{github_project_owner_segment(owner_type, owner_login)}/projects/#{project_number}"

      _ ->
        nil
    end
  end

  defp github_project_url(_web_base, _owner_type, _owner_login, _project), do: nil

  defp github_project_number(%{number: number}) when is_integer(number), do: number
  defp github_project_number(%{"number" => number}) when is_integer(number), do: number

  defp github_project_number(%{number: number}) when is_binary(number), do: parse_integer(number)
  defp github_project_number(%{"number" => number}) when is_binary(number), do: parse_integer(number)
  defp github_project_number(_project), do: nil

  defp github_project_owner_segment("org", owner_login), do: "orgs/#{owner_login}"
  defp github_project_owner_segment("user", owner_login), do: "users/#{owner_login}"

  defp github_endpoint(tracker) when is_map(tracker) do
    case Map.get(tracker, :endpoint) || Map.get(tracker, "endpoint") do
      endpoint when is_binary(endpoint) and endpoint != "" -> endpoint
      _ -> "https://api.github.com/graphql"
    end
  end

  defp endpoint_to_project_web_base(endpoint) when is_binary(endpoint) do
    case URI.parse(String.trim(endpoint)) do
      %URI{scheme: "https", host: host, path: path, port: port}
      when is_binary(host) and host != "" ->
        endpoint_to_project_web_base(host, normalize_endpoint_path(path), port)

      _ ->
        nil
    end
  end

  defp endpoint_to_project_web_base("api.github.com", "/graphql", _port), do: "https://github.com"

  defp endpoint_to_project_web_base(host, "/api/graphql", port) when is_binary(host) and host != "" do
    "https://#{host_with_port(host, port)}"
  end

  defp endpoint_to_project_web_base(_host, _path, _port), do: nil

  defp normalize_endpoint_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> case do
      "/" -> "/"
      value -> String.trim_trailing(value, "/")
    end
  end

  defp normalize_endpoint_path(_path), do: "/"

  defp host_with_port(host, port) when is_integer(port) and port > 0 and port != 443,
    do: "#{host}:#{port}"

  defp host_with_port(host, _port), do: host

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end
end
