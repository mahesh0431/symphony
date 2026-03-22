defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  Thin GitHub GraphQL client for Project v2 hydration and issue polling.
  """

  require Logger

  alias SymphonyElixir.{Config, GitHub.Issue}

  @issue_page_size 50
  @blocker_page_size 20
  @comment_page_size 50
  @max_error_body_log_bytes 1_000
  @project_cache_key {__MODULE__, :project_catalog}

  @type tracker_settings :: map()

  @type project_metadata :: %{
          project_id: String.t(),
          project_number: integer(),
          project_title: String.t() | nil,
          project_url: String.t() | nil,
          status_field_id: String.t(),
          status_field_name: String.t(),
          status_options_by_id: %{optional(String.t()) => String.t()},
          status_option_ids_by_name: %{optional(String.t()) => String.t()}
        }

  @type project_catalog :: %{
          fingerprint: term(),
          owner_login: String.t(),
          owner_type: String.t(),
          status_field_name: String.t(),
          projects: [project_metadata()],
          projects_by_number: %{optional(integer()) => project_metadata()}
        }

  @create_comment_mutation """
  mutation SymphonyGithubAddComment($subjectId: ID!, $body: String!) {
    addComment(input: { subjectId: $subjectId, body: $body }) {
      commentEdge {
        node {
          id
        }
      }
    }
  }
  """

  @update_comment_mutation """
  mutation SymphonyGithubUpdateComment($id: ID!, $body: String!) {
    updateIssueComment(input: { id: $id, body: $body }) {
      issueComment {
        id
      }
    }
  }
  """

  @workpad_comments_query """
  query SymphonyGithubWorkpadComments($id: ID!, $commentsFirst: Int!) {
    viewer {
      login
    }
    node(id: $id) {
      ... on Issue {
        comments(first: $commentsFirst) {
          nodes {
            id
            body
            author {
              login
            }
          }
        }
      }
    }
  }
  """

  @update_status_mutation """
  mutation SymphonyGithubUpdateProjectItemStatus(
    $projectId: ID!
    $itemId: ID!
    $fieldId: ID!
    $optionId: String!
  ) {
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
  """

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tracker = github_tracker!()
    fetch_candidate_issues_for_test(tracker, tracker_active_states(tracker), &graphql/2)
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    tracker = github_tracker!()
    normalized_states = normalize_state_names(state_names)

    if normalized_states == [] do
      {:ok, []}
    else
      fetch_candidate_issues_for_test(tracker, normalized_states, &graphql/2)
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    tracker = github_tracker!()
    fetch_issue_states_by_ids_for_test(tracker, issue_ids, &graphql/2)
  end

  @spec create_comment(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    create_comment_for_test(issue_id, body, &graphql/2)
  end

  @spec update_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def update_comment(comment_id, body) when is_binary(comment_id) and is_binary(body) do
    update_comment_for_test(comment_id, body, &graphql/2)
  end

  @spec upsert_workpad_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def upsert_workpad_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    tracker = github_tracker!()
    upsert_workpad_comment_for_test(tracker, issue_id, body, &graphql/2)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    tracker = github_tracker!()
    update_issue_state_for_test(tracker, issue_id, state_name, &graphql/2)
  end

  @spec graphql(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def graphql(query, variables \\ %{}, opts \\ [])
      when is_binary(query) and is_map(variables) and is_list(opts) do
    payload = build_graphql_payload(query, variables, Keyword.get(opts, :operation_name))
    request_fun = Keyword.get(opts, :request_fun, &post_graphql_request/2)

    with {:ok, headers} <- graphql_headers(),
         {:ok, %{status: 200, body: body}} <- request_fun.(payload, headers),
         :ok <- maybe_raise_graphql_errors(body) do
      {:ok, body}
    else
      {:ok, response} ->
        Logger.error(
          "GitHub GraphQL request failed status=#{response.status}" <>
            github_error_context(payload, response)
        )

        {:error, {:github_api_status, response.status}}

      {:error, {:github_graphql_errors, _errors} = reason} ->
        Logger.error("GitHub GraphQL returned errors #{github_error_context(payload, %{body: elem(reason, 1)})}")
        {:error, reason}

      {:error, reason} ->
        Logger.error("GitHub GraphQL request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  @doc false
  @spec hydrate_projects_for_test(tracker_settings(), (String.t(), map() -> {:ok, map()} | {:error, term()})) ::
          {:ok, project_catalog()} | {:error, term()}
  def hydrate_projects_for_test(tracker, graphql_fun)
      when is_map(tracker) and is_function(graphql_fun, 2) do
    do_hydrate_projects(tracker, graphql_fun)
  end

  @doc false
  @spec fetch_candidate_issues_for_test(
          tracker_settings(),
          [String.t()],
          (String.t(), map() -> {:ok, map()} | {:error, term()})
        ) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues_for_test(tracker, state_names, graphql_fun)
      when is_map(tracker) and is_list(state_names) and is_function(graphql_fun, 2) do
    normalized_states = normalize_state_names(state_names)

    if normalized_states == [] do
      {:ok, []}
    else
      with {:ok, catalog} <- do_hydrate_projects(tracker, graphql_fun) do
        fetch_candidates_from_catalog(catalog, normalized_states, graphql_fun)
      end
    end
  end

  @doc false
  @spec fetch_issue_states_by_ids_for_test(
          tracker_settings(),
          [String.t()],
          (String.t(), map() -> {:ok, map()} | {:error, term()})
        ) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids_for_test(tracker, issue_ids, graphql_fun)
      when is_map(tracker) and is_list(issue_ids) and is_function(graphql_fun, 2) do
    ids = issue_ids |> Enum.filter(&is_binary/1) |> Enum.uniq()

    case ids do
      [] ->
        {:ok, []}

      _ ->
        with {:ok, catalog} <- do_hydrate_projects(tracker, graphql_fun) do
          refresh_requested_issues(ids, catalog, graphql_fun)
        end
    end
  end

  @doc false
  @spec create_comment_for_test(String.t(), String.t(), (String.t(), map() -> {:ok, map()} | {:error, term()})) ::
          {:ok, String.t()} | {:error, term()}
  def create_comment_for_test(issue_id, body, graphql_fun)
      when is_binary(issue_id) and is_binary(body) and is_function(graphql_fun, 2) do
    with {:ok, response} <- graphql_fun.(@create_comment_mutation, %{subjectId: issue_id, body: body}),
         comment_id when is_binary(comment_id) <-
           get_in(response, ["data", "addComment", "commentEdge", "node", "id"]) do
      {:ok, comment_id}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_comment_create_failed}
    end
  end

  @doc false
  @spec update_comment_for_test(String.t(), String.t(), (String.t(), map() -> {:ok, map()} | {:error, term()})) ::
          :ok | {:error, term()}
  def update_comment_for_test(comment_id, body, graphql_fun)
      when is_binary(comment_id) and is_binary(body) and is_function(graphql_fun, 2) do
    with {:ok, response} <- graphql_fun.(@update_comment_mutation, %{id: comment_id, body: body}),
         updated_id when is_binary(updated_id) <-
           get_in(response, ["data", "updateIssueComment", "issueComment", "id"]) do
      if updated_id == comment_id do
        :ok
      else
        {:error, :github_comment_update_failed}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_comment_update_failed}
    end
  end

  @doc false
  @spec upsert_workpad_comment_for_test(
          tracker_settings(),
          String.t(),
          String.t(),
          (String.t(), map() -> {:ok, map()} | {:error, term()})
        ) :: :ok | {:error, term()}
  def upsert_workpad_comment_for_test(tracker, issue_id, body, graphql_fun)
      when is_map(tracker) and is_binary(issue_id) and is_binary(body) and is_function(graphql_fun, 2) do
    with {:ok, marker} <- workpad_marker(tracker, body),
         {:ok, existing_comment_id} <- find_workpad_comment_id(tracker, issue_id, marker, graphql_fun) do
      persist_workpad_comment(issue_id, body, existing_comment_id, graphql_fun)
    end
  end

  @doc false
  @spec update_issue_state_for_test(
          tracker_settings(),
          String.t(),
          String.t(),
          (String.t(), map() -> {:ok, map()} | {:error, term()})
        ) :: :ok | {:error, term()}
  def update_issue_state_for_test(tracker, issue_id, state_name, graphql_fun)
      when is_map(tracker) and is_binary(issue_id) and is_binary(state_name) and is_function(graphql_fun, 2) do
    with {:ok, catalog} <- do_hydrate_projects(tracker, graphql_fun),
         {:ok, [%Issue{} = issue]} <- fetch_issue_states_by_ids_for_test(tracker, [issue_id], graphql_fun),
         {:ok, project_item, project} <- tracked_project_item(issue, catalog),
         {:ok, option_id} <- status_option_id(project, state_name),
         {:ok, response} <-
           graphql_fun.(@update_status_mutation, %{
             projectId: project.project_id,
             itemId: project_item.item_id,
             fieldId: project.status_field_id,
             optionId: option_id
           }),
         updated_item_id when is_binary(updated_item_id) <-
           get_in(response, ["data", "updateProjectV2ItemFieldValue", "projectV2Item", "id"]) do
      if updated_item_id == project_item.item_id do
        :ok
      else
        {:error, :github_issue_update_failed}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_issue_update_failed}
    end
  end

  @doc false
  @spec normalize_issue_for_test(map(), project_catalog()) :: Issue.t()
  def normalize_issue_for_test(raw_issue, catalog) when is_map(raw_issue) and is_map(catalog) do
    normalize_issue(raw_issue, catalog)
  end

  @doc false
  @spec clear_project_cache_for_test() :: :ok
  def clear_project_cache_for_test do
    :persistent_term.erase(@project_cache_key)
    :ok
  end

  defp github_tracker! do
    Config.settings!().tracker
  end

  defp find_workpad_comment_id(tracker, issue_id, marker, graphql_fun)
       when is_map(tracker) and is_binary(issue_id) and is_binary(marker) and is_function(graphql_fun, 2) do
    variables = %{id: issue_id, commentsFirst: @comment_page_size}

    with {:ok, response} <- graphql_fun.(@workpad_comments_query, variables) do
      comments = get_in(response, ["data", "node", "comments", "nodes"]) || []
      viewer_login = get_in(response, ["data", "viewer", "login"])

      {:ok,
       Enum.find_value(comments, fn comment ->
         if workpad_comment_match?(comment, marker, viewer_login) do
           Map.get(comment, "id")
         end
       end)}
    end
  end

  defp fetch_candidates_from_catalog(catalog, normalized_states, graphql_fun) do
    Enum.reduce_while(catalog.projects, {:ok, []}, fn project, {:ok, issues} ->
      case fetch_project_candidates(project, catalog, normalized_states, graphql_fun) do
        {:ok, project_issues} -> {:cont, {:ok, merge_issue_lists(issues, project_issues)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp refresh_requested_issues(ids, catalog, graphql_fun) do
    issue_order_index = issue_order_index(ids)

    ids
    |> Enum.reduce_while({:ok, []}, fn issue_id, {:ok, issues} ->
      refresh_issue(issue_id, catalog, issues, graphql_fun)
    end)
    |> finalize_refreshed_issues(issue_order_index)
  end

  defp refresh_issue(issue_id, catalog, issues, graphql_fun) do
    case graphql_fun.(refresh_query(), %{id: issue_id, statusFieldName: catalog.status_field_name}) do
      {:ok, body} ->
        case decode_refresh_response(body, catalog) do
          {:ok, issue} -> {:cont, {:ok, [issue | issues]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp finalize_refreshed_issues({:ok, issues}, issue_order_index) do
    issues
    |> Enum.reverse()
    |> sort_issues_by_requested_ids(issue_order_index)
    |> then(&{:ok, &1})
  end

  defp finalize_refreshed_issues(error, _issue_order_index), do: error

  defp persist_workpad_comment(issue_id, body, nil, graphql_fun) do
    case create_comment_for_test(issue_id, body, graphql_fun) do
      {:ok, _comment_id} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_workpad_comment(_issue_id, body, comment_id, graphql_fun) do
    update_comment_for_test(comment_id, body, graphql_fun)
  end

  defp tracked_project_item(%Issue{project_items: project_items}, %{projects_by_number: projects_by_number})
       when is_list(project_items) and is_map(projects_by_number) do
    case Enum.find(project_items, fn project_item ->
           Map.has_key?(projects_by_number, project_item.project_number) and is_binary(project_item.item_id)
         end) do
      %{project_number: project_number} = project_item ->
        {:ok, project_item, Map.fetch!(projects_by_number, project_number)}

      nil ->
        {:error, :github_project_item_not_found}
    end
  end

  defp status_option_id(project, state_name) when is_map(project) and is_binary(state_name) do
    normalized_name = String.trim(state_name)

    case Map.get(project.status_option_ids_by_name, normalized_name) do
      option_id when is_binary(option_id) -> {:ok, option_id}
      _ -> {:error, {:github_status_option_not_found, normalized_name}}
    end
  end

  defp do_hydrate_projects(tracker, graphql_fun) do
    fingerprint = tracker_fingerprint(tracker)

    case :persistent_term.get(@project_cache_key, nil) do
      %{fingerprint: ^fingerprint} = cached ->
        {:ok, cached}

      _ ->
        with {:ok, catalog} <- fetch_project_catalog(tracker, graphql_fun) do
          :persistent_term.put(@project_cache_key, catalog)
          {:ok, catalog}
        end
    end
  end

  defp fetch_project_catalog(tracker, graphql_fun) do
    owner_type = tracker_owner_type(tracker)
    owner_login = tracker_owner_login(tracker)
    status_field_name = tracker_status_field_name(tracker)

    tracker_projects(tracker)
    |> Enum.reduce_while({:ok, []}, fn project_number, {:ok, projects} ->
      hydrate_project(project_number, owner_login, owner_type, status_field_name, graphql_fun, projects)
    end)
    |> build_project_catalog(tracker, owner_login, owner_type, status_field_name)
  end

  defp fetch_project_candidates(project, catalog, state_names, graphql_fun) do
    Enum.reduce_while(state_names, {:ok, []}, fn state_name, {:ok, issues} ->
      query_string = build_project_items_query(state_name)

      case fetch_project_candidates_page(project, catalog, query_string, nil, [], graphql_fun) do
        {:ok, project_issues} -> {:cont, {:ok, merge_issue_lists(issues, project_issues)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_project_candidates_page(project, catalog, query_string, after_cursor, acc_issues, graphql_fun) do
    variables = %{
      login: catalog.owner_login,
      number: project.project_number,
      query: query_string,
      first: @issue_page_size,
      after: after_cursor,
      statusFieldName: catalog.status_field_name
    }

    case graphql_fun.(poll_query(catalog.owner_type), variables) do
      {:ok, body} ->
        handle_candidates_page(body, project, catalog, query_string, acc_issues, graphql_fun)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hydrate_project(project_number, owner_login, owner_type, status_field_name, graphql_fun, projects) do
    variables = %{
      login: owner_login,
      number: project_number,
      statusFieldName: status_field_name
    }

    case graphql_fun.(hydration_query(owner_type), variables) do
      {:ok, body} ->
        case decode_project_hydration(body, project_number, status_field_name) do
          {:ok, project} -> {:cont, {:ok, [project | projects]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp build_project_catalog({:ok, projects}, tracker, owner_login, owner_type, status_field_name) do
    projects = Enum.reverse(projects)

    {:ok,
     %{
       fingerprint: tracker_fingerprint(tracker),
       owner_login: owner_login,
       owner_type: owner_type,
       status_field_name: status_field_name,
       projects: projects,
       projects_by_number: Map.new(projects, &{&1.project_number, &1})
     }}
  end

  defp build_project_catalog(error, _tracker, _owner_login, _owner_type, _status_field_name), do: error

  defp handle_candidates_page(body, project, catalog, query_string, acc_issues, graphql_fun) do
    with {:ok, issues, page_info} <- decode_poll_response(body, project, catalog) do
      updated_acc = prepend_page_issues(issues, acc_issues)
      continue_candidates_page(project, catalog, query_string, updated_acc, page_info, graphql_fun)
    end
  end

  defp continue_candidates_page(project, catalog, query_string, updated_acc, page_info, graphql_fun) do
    case next_page_cursor(page_info) do
      {:ok, next_cursor} ->
        fetch_project_candidates_page(project, catalog, query_string, next_cursor, updated_acc, graphql_fun)

      {:error, reason} ->
        {:error, reason}

      :done ->
        {:ok, finalize_paginated_issues(updated_acc)}
    end
  end

  defp build_graphql_payload(query, variables, operation_name) do
    %{"query" => query, "variables" => variables}
    |> maybe_put_operation_name(operation_name)
  end

  defp maybe_put_operation_name(payload, operation_name) when is_binary(operation_name) do
    trimmed = String.trim(operation_name)

    if trimmed == "" do
      payload
    else
      Map.put(payload, "operationName", trimmed)
    end
  end

  defp maybe_put_operation_name(payload, _operation_name), do: payload

  defp maybe_raise_graphql_errors(%{"errors" => errors}) when is_list(errors),
    do: {:error, {:github_graphql_errors, errors}}

  defp maybe_raise_graphql_errors(_body), do: :ok

  defp github_error_context(payload, response) when is_map(payload) do
    operation_name =
      case Map.get(payload, "operationName") do
        name when is_binary(name) and name != "" -> " operation=#{name}"
        _ -> ""
      end

    body =
      response
      |> Map.get(:body)
      |> summarize_error_body()

    operation_name <> " body=" <> body
  end

  defp summarize_error_body(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate_error_body()
    |> inspect()
  end

  defp summarize_error_body(body) do
    body
    |> inspect(limit: 20, printable_limit: @max_error_body_log_bytes)
    |> truncate_error_body()
  end

  defp truncate_error_body(body) when is_binary(body) do
    if byte_size(body) > @max_error_body_log_bytes do
      binary_part(body, 0, @max_error_body_log_bytes) <> "...<truncated>"
    else
      body
    end
  end

  defp graphql_headers do
    case Config.settings!().tracker.api_key do
      nil ->
        {:error, :missing_github_api_token}

      token ->
        {:ok,
         [
           {"Authorization", "Bearer #{token}"},
           {"Content-Type", "application/json"},
           {"User-Agent", "symphony-elixir"}
         ]}
    end
  end

  defp workpad_marker(tracker, body) when is_map(tracker) and is_binary(body) do
    marker =
      case Map.get(tracker, :workpad_comment) || Map.get(tracker, "workpad_comment") do
        %{"marker" => configured_marker} -> configured_marker
        %{marker: configured_marker} -> configured_marker
        _ -> extract_html_comment_marker(body)
      end

    if is_binary(marker) and String.trim(marker) != "" do
      {:ok, marker}
    else
      {:error, :github_workpad_marker_missing}
    end
  end

  defp extract_html_comment_marker(body) when is_binary(body) do
    case Regex.run(~r/(<!--\s*[^>]+-->)/, body, capture: :all_but_first) do
      [marker] -> marker
      _ -> nil
    end
  end

  defp workpad_comment_match?(%{"id" => comment_id, "body" => comment_body} = comment, marker, viewer_login)
       when is_binary(comment_id) and is_binary(comment_body) and is_binary(marker) do
    String.contains?(comment_body, marker) and author_matches_viewer?(comment, viewer_login)
  end

  defp workpad_comment_match?(_comment, _marker, _viewer_login), do: false

  defp author_matches_viewer?(comment, viewer_login) when is_binary(viewer_login) and viewer_login != "" do
    get_in(comment, ["author", "login"]) == viewer_login
  end

  defp author_matches_viewer?(_comment, _viewer_login), do: true

  defp post_graphql_request(payload, headers) do
    Req.post(Config.settings!().tracker.endpoint,
      headers: headers,
      json: payload,
      connect_options: [timeout: 30_000]
    )
  end

  defp hydration_query(owner_type) do
    """
    query SymphonyGithubHydrate($login: String!, $number: Int!, $statusFieldName: String!) {
      owner: #{owner_type}(login: $login) {
        project: projectV2(number: $number) {
          id
          number
          title
          url
          field(name: $statusFieldName) {
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
    """
  end

  defp poll_query(owner_type) do
    """
    query SymphonyGithubPoll(
      $login: String!
      $number: Int!
      $query: String!
      $first: Int!
      $after: String
      $statusFieldName: String!
    ) {
      owner: #{owner_type}(login: $login) {
        project: projectV2(number: $number) {
          items(first: $first, after: $after, query: $query) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              fieldValueByName(name: $statusFieldName) {
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
                  blockedBy(first: #{@blocker_page_size}) {
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
    """
  end

  defp refresh_query do
    """
    query SymphonyGithubIssueRefresh($id: ID!, $statusFieldName: String!) {
      node(id: $id) {
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
          blockedBy(first: #{@blocker_page_size}) {
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
                id
                number
                title
                url
              }
              fieldValueByName(name: $statusFieldName) {
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
    """
  end

  defp decode_project_hydration(
         %{
           "data" => %{
             "owner" => %{
               "project" => %{
                 "id" => project_id,
                 "number" => number,
                 "title" => title,
                 "url" => url,
                 "field" => field
               }
             }
           }
         },
         _project_number,
         status_field_name
       )
       when is_binary(project_id) and is_integer(number) and is_map(field) do
    with {:ok, status_field_id, options_by_id, option_ids_by_name} <-
           decode_status_field(field, status_field_name) do
      {:ok,
       %{
         project_id: project_id,
         project_number: number,
         project_title: title,
         project_url: url,
         status_field_id: status_field_id,
         status_field_name: status_field_name,
         status_options_by_id: options_by_id,
         status_option_ids_by_name: option_ids_by_name
       }}
    end
  end

  defp decode_project_hydration(%{"data" => %{"owner" => %{"project" => nil}}}, project_number, _status_field_name) do
    {:error, {:github_project_not_found, project_number}}
  end

  defp decode_project_hydration(%{"data" => %{"owner" => nil}}, _project_number, _status_field_name) do
    {:error, :github_owner_not_found}
  end

  defp decode_project_hydration(_body, project_number, _status_field_name) do
    {:error, {:github_project_hydration_failed, project_number}}
  end

  defp decode_status_field(%{"id" => field_id, "name" => field_name, "options" => options}, expected_name)
       when is_binary(field_id) and is_binary(field_name) and is_list(options) do
    if field_name == expected_name do
      options_by_id =
        options
        |> Enum.reduce(%{}, fn
          %{"id" => option_id, "name" => option_name}, acc
          when is_binary(option_id) and is_binary(option_name) ->
            Map.put(acc, option_id, option_name)

          _option, acc ->
            acc
        end)

      option_ids_by_name = Map.new(options_by_id, fn {option_id, option_name} -> {option_name, option_id} end)

      {:ok, field_id, options_by_id, option_ids_by_name}
    else
      {:error, {:github_status_field_not_found, expected_name}}
    end
  end

  defp decode_status_field(_field, expected_name), do: {:error, {:github_status_field_not_found, expected_name}}

  defp decode_poll_response(
         %{
           "data" => %{
             "owner" => %{
               "project" => %{
                 "items" => %{
                   "nodes" => nodes,
                   "pageInfo" => %{"hasNextPage" => has_next_page, "endCursor" => end_cursor}
                 }
               }
             }
           }
         },
         project,
         catalog
       )
       when is_list(nodes) do
    issues =
      nodes
      |> Enum.map(&normalize_project_item_issue(&1, project, catalog))
      |> Enum.reject(&is_nil/1)

    {:ok, issues, %{has_next_page: has_next_page == true, end_cursor: end_cursor}}
  end

  defp decode_poll_response(_body, _project, _catalog), do: {:error, :github_poll_decode_failed}

  defp decode_refresh_response(%{"data" => %{"node" => issue}}, catalog) when is_map(issue),
    do: {:ok, normalize_issue(issue, catalog)}

  defp decode_refresh_response(_body, _catalog), do: {:error, :github_issue_refresh_decode_failed}

  defp normalize_project_item_issue(%{"content" => issue} = item, project, catalog) when is_map(issue) do
    issue
    |> Map.put("projectItems", %{"nodes" => [build_project_item_node(item, project)]})
    |> normalize_issue(catalog)
  end

  defp normalize_project_item_issue(_item, _project, _catalog), do: nil

  defp build_project_item_node(item, project) do
    %{
      "id" => item["id"],
      "project" => %{
        "id" => project.project_id,
        "number" => project.project_number,
        "title" => project.project_title,
        "url" => project.project_url
      },
      "fieldValueByName" => Map.get(item, "fieldValueByName")
    }
  end

  defp normalize_issue(issue, catalog) when is_map(issue) do
    project_items = extract_project_items(issue, catalog)
    primary_project_item = Enum.at(project_items, 0)
    repository = Map.get(issue, "repository", %{})
    repository_name = Map.get(repository, "nameWithOwner")
    assignees = get_in(issue, ["assignees", "nodes"])

    %Issue{
      id: issue["id"],
      identifier: github_identifier(repository_name, issue["number"]),
      number: issue["number"],
      title: issue["title"],
      description: issue["body"],
      priority: nil,
      state: primary_status_name(primary_project_item),
      state_option_id: primary_status_option_id(primary_project_item),
      issue_state: issue["state"],
      issue_state_reason: issue["stateReason"],
      branch_name: nil,
      url: issue["url"],
      assignee_id: nil,
      repository_name_with_owner: repository_name,
      repository_url: repository["url"],
      repository_ssh_url: repository["sshUrl"],
      repository_default_branch: get_in(repository, ["defaultBranchRef", "name"]),
      project_id: primary_project_id(primary_project_item),
      project_number: primary_project_number(primary_project_item),
      project_title: primary_project_title(primary_project_item),
      project_url: primary_project_url(primary_project_item),
      project_item_id: primary_project_item_id(primary_project_item),
      status_field_id: primary_status_field_id(primary_project_item, catalog),
      status_field_name: catalog.status_field_name,
      tracker_metadata: %{"kind" => "github", "clone_url" => repository["url"]},
      blocked_by: extract_blockers(issue),
      labels: extract_labels(issue),
      assigned_to_worker: assigned_to_worker?(assignees, tracker_assignee(catalog)),
      project_items: project_items,
      created_at: nil,
      updated_at: parse_datetime(issue["updatedAt"])
    }
  end

  defp extract_project_items(issue, %{projects_by_number: projects_by_number}) when is_map(projects_by_number) do
    issue
    |> get_in(["projectItems", "nodes"])
    |> case do
      project_items when is_list(project_items) ->
        Enum.flat_map(project_items, &normalize_project_item(&1, projects_by_number))

      _ ->
        []
    end
  end

  defp extract_project_items(_issue, _catalog), do: []

  defp normalize_project_item(
         %{"id" => item_id, "project" => %{"number" => number} = project_info} = item,
         projects_by_number
       ) do
    case Map.get(projects_by_number, number) do
      nil ->
        []

      project ->
        [
          %{
            item_id: item_id,
            project_id: project_info["id"] || project.project_id,
            project_number: number,
            project_title: project_info["title"] || project.project_title,
            project_url: project_info["url"] || project.project_url,
            status: get_in(item, ["fieldValueByName", "name"]),
            status_option_id: get_in(item, ["fieldValueByName", "optionId"])
          }
        ]
    end
  end

  defp normalize_project_item(_item, _projects_by_number), do: []

  defp extract_labels(%{"labels" => %{"nodes" => labels}}) when is_list(labels) do
    labels
    |> Enum.map(& &1["name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_labels(_issue), do: []

  defp extract_blockers(%{"blockedBy" => %{"nodes" => blockers}}) when is_list(blockers) do
    Enum.map(blockers, fn blocker ->
      %{
        id: blocker["id"],
        identifier: github_identifier(nil, blocker["number"]),
        number: blocker["number"],
        state: blocker["state"],
        state_reason: blocker["stateReason"]
      }
    end)
  end

  defp extract_blockers(_issue), do: []

  defp assigned_to_worker?(_assignees, nil), do: true

  defp assigned_to_worker?(assignees, assignee) when is_list(assignees) and is_binary(assignee) do
    target = normalize_login(assignee)

    Enum.any?(assignees, fn
      %{"login" => login} -> normalize_login(login) == target
      _ -> false
    end)
  end

  defp assigned_to_worker?(_assignees, _assignee), do: false

  defp normalize_login(login) when is_binary(login), do: login |> String.trim() |> String.downcase()
  defp normalize_login(_login), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp tracker_owner_type(tracker) do
    tracker
    |> tracker_owner()
    |> Map.get("type", Map.get(tracker_owner(tracker), :type, "user"))
    |> to_string()
    |> String.downcase()
    |> case do
      "organization" -> "organization"
      _ -> "user"
    end
  end

  defp tracker_owner_login(tracker) do
    tracker
    |> tracker_owner()
    |> Map.get("login", Map.get(tracker_owner(tracker), :login))
    |> to_string()
  end

  defp tracker_status_field_name(tracker) do
    tracker
    |> Map.get(:status_field_name, Map.get(tracker, "status_field_name", "Status"))
    |> to_string()
  end

  defp tracker_owner(tracker) do
    Map.get(tracker, :owner, Map.get(tracker, "owner", %{}))
  end

  defp tracker_projects(tracker) do
    tracker
    |> Map.get(:projects, Map.get(tracker, "projects", []))
    |> Enum.flat_map(fn
      %{"number" => number} when is_integer(number) -> [number]
      %{number: number} when is_integer(number) -> [number]
      number when is_integer(number) -> [number]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp tracker_active_states(tracker) do
    tracker
    |> Map.get(:active_states, Map.get(tracker, "active_states", []))
    |> normalize_state_names()
  end

  defp tracker_assignee(%{fingerprint: fingerprint}) do
    case fingerprint do
      {_owner_type, _owner_login, _projects, _status_field_name, assignee} -> assignee
      _ -> nil
    end
  end

  defp tracker_fingerprint(tracker) do
    {
      tracker_owner_type(tracker),
      tracker_owner_login(tracker),
      tracker_projects(tracker),
      tracker_status_field_name(tracker),
      Map.get(tracker, :assignee, Map.get(tracker, "assignee"))
    }
  end

  defp normalize_state_names(state_names) do
    state_names
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp build_project_items_query(state_name) when is_binary(state_name) do
    ~s(is:issue is:open status:"#{state_name}")
  end

  defp next_page_cursor(%{has_next_page: true, end_cursor: end_cursor})
       when is_binary(end_cursor) and byte_size(end_cursor) > 0 do
    {:ok, end_cursor}
  end

  defp next_page_cursor(%{has_next_page: true}), do: {:error, :github_missing_end_cursor}
  defp next_page_cursor(_page_info), do: :done

  defp prepend_page_issues(issues, acc_issues) when is_list(issues) and is_list(acc_issues) do
    Enum.reverse(issues, acc_issues)
  end

  defp finalize_paginated_issues(acc_issues) when is_list(acc_issues), do: Enum.reverse(acc_issues)

  defp merge_issue_lists(existing_issues, new_issues) do
    existing_ids =
      existing_issues
      |> Enum.map(& &1.id)
      |> MapSet.new()

    existing_issues ++ Enum.reject(new_issues, &MapSet.member?(existing_ids, &1.id))
  end

  defp issue_order_index(ids) when is_list(ids) do
    ids
    |> Enum.with_index()
    |> Map.new()
  end

  defp sort_issues_by_requested_ids(issues, issue_order_index)
       when is_list(issues) and is_map(issue_order_index) do
    fallback_index = map_size(issue_order_index)

    Enum.sort_by(issues, &Map.get(issue_order_index, &1.id, fallback_index))
  end

  defp github_identifier(repository_name_with_owner, issue_number) when is_integer(issue_number) do
    prefix =
      case repository_name_with_owner do
        name when is_binary(name) and name != "" -> name
        _ -> "github"
      end

    "#{prefix}##{issue_number}"
  end

  defp github_identifier(_repository_name_with_owner, _issue_number), do: nil

  defp primary_status_name(nil), do: nil
  defp primary_status_name(project_item), do: Map.get(project_item, :status) || Map.get(project_item, "status")

  defp primary_status_option_id(nil), do: nil

  defp primary_status_option_id(project_item) do
    Map.get(project_item, :status_option_id) || Map.get(project_item, "status_option_id")
  end

  defp primary_project_id(nil), do: nil
  defp primary_project_id(project_item), do: Map.get(project_item, :project_id) || Map.get(project_item, "project_id")

  defp primary_project_number(nil), do: nil

  defp primary_project_number(project_item) do
    Map.get(project_item, :project_number) || Map.get(project_item, "project_number")
  end

  defp primary_project_title(nil), do: nil

  defp primary_project_title(project_item) do
    Map.get(project_item, :project_title) || Map.get(project_item, "project_title")
  end

  defp primary_project_url(nil), do: nil
  defp primary_project_url(project_item), do: Map.get(project_item, :project_url) || Map.get(project_item, "project_url")

  defp primary_project_item_id(nil), do: nil

  defp primary_project_item_id(project_item) do
    Map.get(project_item, :item_id) || Map.get(project_item, "item_id")
  end

  defp primary_status_field_id(nil, _catalog), do: nil

  defp primary_status_field_id(project_item, %{projects_by_number: projects_by_number}) do
    project_item
    |> primary_project_number()
    |> then(&Map.fetch!(projects_by_number, &1))
    |> then(& &1.status_field_id)
  end
end
