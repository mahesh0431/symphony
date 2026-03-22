defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """
  Builds agent prompts from tracker issue data.
  """

  alias SymphonyElixir.{Config, Workflow}

  @render_opts [strict_variables: true, strict_filters: true]

  @default_github_prompt """
  # GitHub Issue

  - Identifier: {{ issue.identifier }}
  - Title: {{ issue.title }}
  {% if repository.name_with_owner %}- Repository: {{ repository.name_with_owner }}
  {% endif %}{% if repository.default_branch %}- Default branch: {{ repository.default_branch }}
  {% endif %}{% if issue.url %}- Issue URL: {{ issue.url }}
  {% endif %}

  ## Runtime notes
  - GitHub v1 does not inject a GitHub-specific dynamic tool into the Codex session.

  ## Description
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @spec build_prompt(map(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    template =
      Workflow.current()
      |> prompt_template!(issue)
      |> parse_template!()

    template
    |> Solid.render!(
      %{
        "attempt" => Keyword.get(opts, :attempt),
        "issue" => issue_map(issue),
        "project" => project_context(issue),
        "repository" => repository_context(issue),
        "tracker" => %{"kind" => tracker_kind(issue)}
      },
      @render_opts
    )
    |> IO.iodata_to_binary()
  end

  defp prompt_template!({:ok, %{prompt_template: prompt}}, issue), do: default_prompt(prompt, issue)

  defp prompt_template!({:error, reason}, _issue) do
    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt) when is_binary(prompt) do
    Solid.parse!(prompt)
  rescue
    error ->
      reraise %RuntimeError{
                message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
              },
              __STACKTRACE__
  end

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp issue_map(%_{} = issue), do: issue |> Map.from_struct() |> to_solid_map()
  defp issue_map(issue) when is_map(issue), do: to_solid_map(issue)

  defp repository_context(issue) do
    %{
      "name_with_owner" => issue_field(issue, :repository_name_with_owner),
      "url" => issue_field(issue, :repository_url),
      "ssh_url" => issue_field(issue, :repository_ssh_url),
      "default_branch" => issue_field(issue, :repository_default_branch)
    }
  end

  defp project_context(issue) do
    %{
      "id" => issue_field(issue, :project_id),
      "number" => issue_field(issue, :project_number),
      "title" => issue_field(issue, :project_title),
      "url" => issue_field(issue, :project_url),
      "item_id" => issue_field(issue, :project_item_id),
      "status_field_name" => issue_field(issue, :status_field_name)
    }
  end

  defp tracker_kind(%SymphonyElixir.GitHub.Issue{}), do: "github"
  defp tracker_kind(%SymphonyElixir.Linear.Issue{}), do: "linear"

  defp tracker_kind(issue) do
    issue
    |> issue_field(:repository_name_with_owner)
    |> case do
      repo when is_binary(repo) and repo != "" -> "github"
      _ -> Config.settings!().tracker.kind
    end
  end

  defp issue_field(issue, key) when is_map(issue) do
    Map.get(issue, key) || Map.get(issue, to_string(key))
  end

  defp default_prompt(prompt, issue) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      case tracker_kind(issue) do
        "github" -> @default_github_prompt
        _ -> Config.workflow_prompt()
      end
    else
      prompt
    end
  end
end
