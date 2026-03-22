defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Adapter boundary for issue tracker reads and writes.

  The tracker boundary covers the minimal read/write lifecycle needed by the
  orchestrator, including persistent workpad comment updates when supported by
  the underlying tracker.
  """

  alias SymphonyElixir.Config
  alias SymphonyElixir.GitHub.Issue, as: GitHubIssue
  alias SymphonyElixir.Linear.Issue

  @known_tracker_kinds ["memory", "github", "linear"]

  @type tracker_kind :: String.t()
  @type tracker_kind_error :: :missing_tracker_kind | {:invalid_tracker_kind, term()}
  @type issue_tracker_kind_error ::
          :missing_tracker_metadata | :missing_tracker_kind | {:invalid_tracker_kind, term()}
  @type adapter_module ::
          SymphonyElixir.Tracker.Memory | SymphonyElixir.GitHub.Adapter | SymphonyElixir.Linear.Adapter

  @callback fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback upsert_workpad_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  @callback workspace_bootstrap_clone_source(map()) :: {:ok, String.t()} | :skip | {:error, term()}
  @callback project_urls(map()) :: [String.t()]
  @callback candidate_poll_requires_available_slots?() :: boolean()
  @callback runnable_active_state?(String.t()) :: boolean()

  @optional_callbacks workspace_bootstrap_clone_source: 1,
                      project_urls: 1,
                      candidate_poll_requires_available_slots?: 0,
                      runnable_active_state?: 1

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues do
    adapter().fetch_candidate_issues()
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    adapter().fetch_issues_by_states(states)
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    adapter().fetch_issue_states_by_ids(issue_ids)
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    adapter().create_comment(issue_id, body)
  end

  @spec upsert_workpad_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def upsert_workpad_comment(issue_id, body) do
    adapter().upsert_workpad_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    adapter().update_issue_state(issue_id, state_name)
  end

  @spec workspace_bootstrap_clone_source(map()) :: {:ok, String.t()} | :skip | {:error, term()}
  def workspace_bootstrap_clone_source(issue_context) when is_map(issue_context) do
    case resolve_issue_tracker_kind(issue_context) do
      {:ok, tracker_kind} ->
        maybe_optional(adapter_for_kind(tracker_kind), :workspace_bootstrap_clone_source, [issue_context], :skip)

      {:error, :missing_tracker_metadata} ->
        :skip

      {:error, :missing_tracker_kind} ->
        {:error, :issue_tracker_kind_missing}

      {:error, {:invalid_tracker_kind, tracker_kind}} ->
        {:error, {:unsupported_issue_tracker_kind, tracker_kind}}
    end
  end

  def workspace_bootstrap_clone_source(_issue_context), do: :skip

  @spec project_urls() :: [String.t()]
  def project_urls do
    project_urls(Config.settings!().tracker)
  end

  @spec project_urls(term()) :: [String.t()]
  def project_urls(tracker) when is_map(tracker) do
    fallback = default_project_urls(tracker)

    case resolve_tracker_kind(tracker) do
      {:ok, tracker_kind} ->
        maybe_optional(adapter_for_kind(tracker_kind), :project_urls, [tracker], fallback)

      {:error, _reason} ->
        fallback
    end
  end

  def project_urls(_tracker), do: []

  @spec candidate_poll_requires_available_slots?() :: boolean()
  def candidate_poll_requires_available_slots? do
    maybe_optional(adapter(), :candidate_poll_requires_available_slots?, [], false) == true
  end

  @spec runnable_active_state?(String.t()) :: boolean()
  def runnable_active_state?(state_name) when is_binary(state_name) do
    maybe_optional(adapter(), :runnable_active_state?, [state_name], true) != false
  end

  def runnable_active_state?(_state_name), do: false

  @spec adapter() :: adapter_module()
  def adapter do
    case resolve_tracker_kind(Config.settings!().tracker) do
      {:ok, tracker_kind} ->
        adapter_for_kind(tracker_kind)

      {:error, reason} ->
        raise ArgumentError, "unable to resolve tracker adapter: #{inspect(reason)}"
    end
  end

  @spec resolve_tracker_kind(term()) :: {:ok, tracker_kind()} | {:error, tracker_kind_error()}
  def resolve_tracker_kind(source) do
    source
    |> explicit_tracker_kind()
    |> normalize_tracker_kind()
  end

  @spec resolve_issue_tracker_kind(term()) ::
          {:ok, tracker_kind()} | {:error, issue_tracker_kind_error()}
  def resolve_issue_tracker_kind(source) do
    with {:ok, tracker_metadata} <- tracker_metadata(source) do
      tracker_metadata
      |> tracker_metadata_kind()
      |> normalize_tracker_kind()
    end
  end

  defp maybe_optional(module, function, args, fallback) when is_atom(module) and is_atom(function) do
    if function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      fallback
    end
  end

  defp default_project_urls(tracker) when is_map(tracker) do
    case Map.get(tracker, :project_slug) || Map.get(tracker, "project_slug") do
      project_slug when is_binary(project_slug) and project_slug != "" ->
        ["https://linear.app/project/#{project_slug}/issues"]

      _ ->
        []
    end
  end

  defp explicit_tracker_kind(source) when is_binary(source), do: source

  defp explicit_tracker_kind(source) when is_map(source) do
    Map.get(source, :tracker_kind) ||
      Map.get(source, "tracker_kind") ||
      Map.get(source, :kind) ||
      Map.get(source, "kind")
  end

  defp explicit_tracker_kind(_source), do: nil

  defp tracker_metadata(source) when is_map(source) do
    case Map.get(source, :tracker_metadata) || Map.get(source, "tracker_metadata") do
      tracker_metadata when is_map(tracker_metadata) ->
        {:ok, tracker_metadata}

      nil ->
        struct_tracker_metadata(source)

      _ ->
        {:error, :missing_tracker_metadata}
    end
  end

  defp tracker_metadata(_source), do: {:error, :missing_tracker_metadata}

  defp struct_tracker_metadata(%GitHubIssue{}), do: {:error, :missing_tracker_metadata}
  defp struct_tracker_metadata(%Issue{}), do: {:error, :missing_tracker_metadata}
  defp struct_tracker_metadata(_source), do: {:error, :missing_tracker_metadata}

  defp tracker_metadata_kind(tracker_metadata) when is_map(tracker_metadata) do
    Map.get(tracker_metadata, :kind) || Map.get(tracker_metadata, "kind")
  end

  defp normalize_tracker_kind(kind) when is_binary(kind) do
    normalized_kind =
      kind
      |> String.trim()
      |> String.downcase()

    if normalized_kind in @known_tracker_kinds do
      {:ok, normalized_kind}
    else
      {:error, {:invalid_tracker_kind, kind}}
    end
  end

  defp normalize_tracker_kind(nil), do: {:error, :missing_tracker_kind}
  defp normalize_tracker_kind(kind), do: {:error, {:invalid_tracker_kind, kind}}

  defp adapter_for_kind("memory"), do: SymphonyElixir.Tracker.Memory
  defp adapter_for_kind("github"), do: SymphonyElixir.GitHub.Adapter
  defp adapter_for_kind("linear"), do: SymphonyElixir.Linear.Adapter
end
