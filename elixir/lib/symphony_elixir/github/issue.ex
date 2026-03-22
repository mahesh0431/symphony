defmodule SymphonyElixir.GitHub.Issue do
  @moduledoc """
  Normalized GitHub issue representation used by the tracker/orchestrator flow.
  """

  defstruct [
    :id,
    :identifier,
    :number,
    :title,
    :description,
    :priority,
    :state,
    :state_option_id,
    :issue_state,
    :issue_state_reason,
    :branch_name,
    :url,
    :assignee_id,
    :repository_name_with_owner,
    :repository_url,
    :repository_ssh_url,
    :repository_default_branch,
    :project_id,
    :project_number,
    :project_title,
    :project_url,
    :project_item_id,
    :status_field_id,
    :status_field_name,
    tracker_metadata: %{"kind" => "github"},
    blocked_by: [],
    labels: [],
    assigned_to_worker: true,
    project_items: [],
    created_at: nil,
    updated_at: nil
  ]

  @type project_item :: %{
          item_id: String.t() | nil,
          project_id: String.t() | nil,
          project_number: integer() | nil,
          project_title: String.t() | nil,
          project_url: String.t() | nil,
          status: String.t() | nil,
          status_option_id: String.t() | nil
        }

  @type blocker :: %{
          id: String.t() | nil,
          identifier: String.t() | nil,
          number: integer() | nil,
          state: String.t() | nil,
          state_reason: String.t() | nil
        }

  @type tracker_metadata :: %{
          optional(atom() | String.t()) => String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          number: integer() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          state_option_id: String.t() | nil,
          issue_state: String.t() | nil,
          issue_state_reason: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          repository_name_with_owner: String.t() | nil,
          repository_url: String.t() | nil,
          repository_ssh_url: String.t() | nil,
          repository_default_branch: String.t() | nil,
          project_id: String.t() | nil,
          project_number: integer() | nil,
          project_title: String.t() | nil,
          project_url: String.t() | nil,
          project_item_id: String.t() | nil,
          status_field_id: String.t() | nil,
          status_field_name: String.t() | nil,
          tracker_metadata: tracker_metadata() | nil,
          blocked_by: [blocker()],
          labels: [String.t()],
          assigned_to_worker: boolean(),
          project_items: [project_item()],
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}), do: labels
end
