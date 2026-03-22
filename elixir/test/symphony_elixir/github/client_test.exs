defmodule SymphonyElixir.GitHub.ClientTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.{Client, Issue}

  defmodule GraphqlEndpointPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn)
      payload = Jason.decode!(body)
      send(opts[:test_pid], {:github_http_request, payload, conn.req_headers})
      response = opts[:response_fun].(payload)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    end
  end

  setup do
    Client.clear_project_cache_for_test()
    :ok
  end

  test "hydrates configured projects and caches status field metadata" do
    tracker = github_tracker(projects: [%{"number" => 5}, %{"number" => 6}])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      {:ok,
       %{
         "data" => %{
           "owner" => %{
             "project" => %{
               "id" => "project-#{variables.number}",
               "number" => variables.number,
               "title" => "Project #{variables.number}",
               "url" => "https://github.com/users/octo-org/projects/#{variables.number}",
               "field" => %{
                 "id" => "field-#{variables.number}",
                 "name" => "Status",
                 "dataType" => "SINGLE_SELECT",
                 "options" => [
                   %{"id" => "opt-todo-#{variables.number}", "name" => "Todo"},
                   %{"id" => "opt-progress-#{variables.number}", "name" => "In Progress"}
                 ]
               }
             }
           }
         }
       }}
    end

    assert {:ok, catalog} = Client.hydrate_projects_for_test(tracker, graphql_fun)
    assert length(catalog.projects) == 2
    assert Enum.map(catalog.projects, & &1.project_number) == [5, 6]
    assert hd(catalog.projects).status_option_ids_by_name["Todo"] == "opt-todo-5"

    assert_receive {:graphql_call, hydration_query, %{login: "octo-org", number: 5, statusFieldName: "Status"}}
    assert hydration_query =~ "query SymphonyGithubHydrate"
    assert_receive {:graphql_call, ^hydration_query, %{login: "octo-org", number: 6, statusFieldName: "Status"}}

    assert {:ok, cached_catalog} = Client.hydrate_projects_for_test(tracker, graphql_fun)
    assert cached_catalog == catalog
    refute_receive {:graphql_call, _, _}
  end

  test "fetch_candidate_issues polls configured projects with server-side status filtering" do
    tracker = github_tracker(projects: [%{"number" => 5}])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubHydrate" ->
          {:ok,
           %{
             "data" => %{
               "owner" => %{
                 "project" => %{
                   "id" => "project-5",
                   "number" => 5,
                   "title" => "Tracker Project",
                   "url" => "https://github.com/users/octo-org/projects/5",
                   "field" => %{
                     "id" => "field-5",
                     "name" => "Status",
                     "dataType" => "SINGLE_SELECT",
                     "options" => [
                       %{"id" => "opt-todo", "name" => "Todo"},
                       %{"id" => "opt-progress", "name" => "In Progress"}
                     ]
                   }
                 }
               }
             }
           }}

        query =~ "SymphonyGithubPoll" and variables.query == ~s(is:issue is:open status:"Todo") ->
          {:ok,
           %{
             "data" => %{
               "owner" => %{
                 "project" => %{
                   "items" => %{
                     "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                     "nodes" => [
                       %{
                         "id" => "item-1",
                         "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"},
                         "content" => %{
                           "id" => "issue-node-1",
                           "number" => 42,
                           "title" => "Implement GitHub client",
                           "body" => "Track GitHub projects",
                           "url" => "https://github.com/octo-org/example/issues/42",
                           "state" => "OPEN",
                           "stateReason" => nil,
                           "updatedAt" => "2026-03-21T10:20:30Z",
                           "repository" => %{
                             "nameWithOwner" => "octo-org/example",
                             "url" => "https://github.com/octo-org/example",
                             "sshUrl" => "git@github.com:octo-org/example.git",
                             "defaultBranchRef" => %{"name" => "main"}
                           },
                           "labels" => %{"nodes" => [%{"name" => "Orchestration"}]},
                           "assignees" => %{"nodes" => [%{"login" => "octo-worker"}]},
                           "issueDependenciesSummary" => %{"blockedBy" => 1, "totalBlockedBy" => 1},
                           "blockedBy" => %{
                             "nodes" => [
                               %{
                                 "id" => "blocker-1",
                                 "number" => 7,
                                 "state" => "CLOSED",
                                 "stateReason" => "COMPLETED"
                               }
                             ]
                           }
                         }
                       }
                     ]
                   }
                 }
               }
             }
           }}

        query =~ "SymphonyGithubPoll" and
            variables.query == ~s(is:issue is:open status:"In Progress") ->
          {:ok,
           %{
             "data" => %{
               "owner" => %{
                 "project" => %{
                   "items" => %{
                     "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                     "nodes" => []
                   }
                 }
               }
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert {:ok, [%Issue{} = issue]} =
             Client.fetch_candidate_issues_for_test(tracker, ["Todo", "In Progress"], graphql_fun)

    assert issue.id == "issue-node-1"
    assert issue.identifier == "octo-org/example#42"
    assert issue.state == "Todo"
    assert issue.state_option_id == "opt-todo"
    assert issue.repository_name_with_owner == "octo-org/example"
    assert issue.repository_default_branch == "main"
    assert issue.labels == ["orchestration"]

    assert issue.blocked_by == [
             %{id: "blocker-1", identifier: "github#7", number: 7, state: "CLOSED", state_reason: "COMPLETED"}
           ]

    assert issue.project_number == 5
    assert issue.project_item_id == "item-1"

    assert_receive {:graphql_call, _hydrate_query, %{number: 5}}

    assert_receive {:graphql_call, poll_query,
                    %{
                      number: 5,
                      query: todo_filter,
                      statusFieldName: "Status",
                      first: 50,
                      after: nil
                    }}

    assert poll_query =~ "query SymphonyGithubPoll"
    assert todo_filter == ~s(is:issue is:open status:"Todo")

    assert_receive {:graphql_call, ^poll_query,
                    %{
                      number: 5,
                      query: progress_filter,
                      statusFieldName: "Status",
                      first: 50,
                      after: nil
                    }}

    assert progress_filter == ~s(is:issue is:open status:"In Progress")
  end

  test "public client wrappers short-circuit safely without network when states are empty or token is missing" do
    write_github_workflow!(
      api_key: nil,
      projects: [%{"number" => 5}],
      active_states: []
    )

    assert {:ok, []} = Client.fetch_candidate_issues()
    assert {:ok, []} = Client.fetch_issues_by_states([])
    assert {:ok, []} = Client.fetch_issue_states_by_ids([])

    assert {:error, {:github_api_request, :missing_github_api_token}} =
             Client.create_comment("issue-1", "body")

    assert {:error, {:github_api_request, :missing_github_api_token}} =
             Client.update_comment("comment-1", "body")

    assert {:error, {:github_api_request, :missing_github_api_token}} =
             Client.upsert_workpad_comment("issue-1", "## Codex Workpad\n<!-- symphony:workpad -->\nbody")

    assert {:error, {:github_api_request, :missing_github_api_token}} =
             Client.update_issue_state("issue-1", "Done")
  end

  test "public fetch_issues_by_states uses the configured github endpoint when states are present" do
    endpoint =
      start_github_graphql_server!(fn payload ->
        query = payload["query"]
        variables = payload["variables"]

        cond do
          query =~ "SymphonyGithubHydrate" ->
            github_hydration_response(variables["number"])

          query =~ "SymphonyGithubPoll" ->
            github_poll_response([
              %{
                "id" => "item-1",
                "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"},
                "content" => github_issue_node("issue-node-1", 42)
              }
            ])

          true ->
            flunk("unexpected payload: #{inspect(payload)}")
        end
      end)

    write_github_workflow!(
      endpoint: endpoint,
      api_key: "live-gh-token",
      projects: [%{"number" => 5}],
      active_states: ["Todo"]
    )

    assert {:ok, [%Issue{} = issue]} = Client.fetch_issues_by_states([" Todo ", "", "Todo"])
    assert issue.id == "issue-node-1"
    assert issue.identifier == "octo-org/example#42"

    assert_receive {:github_http_request, hydrate_payload, hydrate_headers}
    assert hydrate_payload["variables"]["number"] == 5
    assert Enum.any?(hydrate_headers, fn {name, value} -> name == "authorization" and value == "Bearer live-gh-token" end)

    assert_receive {:github_http_request, poll_payload, _poll_headers}
    assert poll_payload["variables"]["query"] == ~s(is:issue is:open status:"Todo")
    assert poll_payload["variables"]["after"] == nil
  end

  test "fetch_issue_states_by_ids refreshes issues by node id and preserves requested order" do
    tracker = github_tracker(projects: [%{"number" => 5}], assignee: "octo-worker")
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubHydrate" ->
          {:ok,
           %{
             "data" => %{
               "owner" => %{
                 "project" => %{
                   "id" => "project-5",
                   "number" => 5,
                   "title" => "Tracker Project",
                   "url" => "https://github.com/users/octo-org/projects/5",
                   "field" => %{
                     "id" => "field-5",
                     "name" => "Status",
                     "dataType" => "SINGLE_SELECT",
                     "options" => [
                       %{"id" => "opt-merging", "name" => "Merging"},
                       %{"id" => "opt-rework", "name" => "Rework"}
                     ]
                   }
                 }
               }
             }
           }}

        query =~ "SymphonyGithubIssueRefresh" ->
          {:ok,
           %{
             "data" => %{
               "node" => %{
                 "id" => variables.id,
                 "number" => if(variables.id == "issue-2", do: 2, else: 1),
                 "title" => "Issue #{variables.id}",
                 "body" => "Body #{variables.id}",
                 "url" => "https://github.com/octo-org/example/issues/#{variables.id}",
                 "state" => "OPEN",
                 "stateReason" => nil,
                 "updatedAt" => "2026-03-21T11:22:33Z",
                 "repository" => %{
                   "nameWithOwner" => "octo-org/example",
                   "url" => "https://github.com/octo-org/example",
                   "sshUrl" => "git@github.com:octo-org/example.git",
                   "defaultBranchRef" => %{"name" => "main"}
                 },
                 "labels" => %{"nodes" => [%{"name" => "Needs Review"}]},
                 "assignees" => %{"nodes" => [%{"login" => "octo-worker"}]},
                 "issueDependenciesSummary" => %{"blockedBy" => 0, "totalBlockedBy" => 0},
                 "blockedBy" => %{"nodes" => []},
                 "projectItems" => %{
                   "nodes" => [
                     %{
                       "id" => "item-#{variables.id}",
                       "project" => %{
                         "id" => "project-5",
                         "number" => 5,
                         "title" => "Tracker Project",
                         "url" => "https://github.com/users/octo-org/projects/5"
                       },
                       "fieldValueByName" => %{
                         "name" => if(variables.id == "issue-2", do: "Merging", else: "Rework"),
                         "optionId" => if(variables.id == "issue-2", do: "opt-merging", else: "opt-rework")
                       }
                     }
                   ]
                 }
               }
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert {:ok, [first, second]} =
             Client.fetch_issue_states_by_ids_for_test(tracker, ["issue-2", "issue-1"], graphql_fun)

    assert first.id == "issue-2"
    assert first.state == "Merging"
    assert first.assigned_to_worker == true
    assert second.id == "issue-1"
    assert second.state == "Rework"

    assert second.project_items == [
             %{
               item_id: "item-issue-1",
               project_id: "project-5",
               project_number: 5,
               project_title: "Tracker Project",
               project_url: "https://github.com/users/octo-org/projects/5",
               status: "Rework",
               status_option_id: "opt-rework"
             }
           ]
  end

  test "graphql returns adapter-ready error tuples" do
    assert {:error, {:github_api_status, 502}} =
             Client.graphql(
               "query Viewer { viewer { login } }",
               %{},
               request_fun: fn _payload, _headers -> {:ok, %{status: 502, body: %{"message" => "bad gateway"}}} end
             )

    assert {:error, {:github_api_request, :econnrefused}} =
             Client.graphql(
               "query Viewer { viewer { login } }",
               %{},
               request_fun: fn _payload, _headers -> {:error, :econnrefused} end
             )

    assert {:error, {:github_graphql_errors, [%{"message" => "boom"}]}} =
             Client.graphql(
               "query Viewer { viewer { login } }",
               %{},
               request_fun: fn _payload, _headers -> {:ok, %{status: 200, body: %{"errors" => [%{"message" => "boom"}]}}} end
             )
  end

  test "graphql trims operation names, omits blank names, and truncates error bodies in logs" do
    parent = self()

    log =
      capture_log(fn ->
        assert {:error, {:github_api_status, 502}} =
                 Client.graphql(
                   "query Viewer { viewer { login } }",
                   %{},
                   operation_name: "  ViewerLookup  ",
                   request_fun: fn payload, _headers ->
                     send(parent, {:payload, payload})
                     {:ok, %{status: 502, body: String.duplicate("abcdefghij", 140)}}
                   end
                 )
      end)

    assert_receive {:payload, %{"operationName" => "ViewerLookup"}}
    assert log =~ "operation=ViewerLookup"
    assert log =~ "<truncated>"

    assert {:ok, %{"data" => %{"viewer" => %{"login" => "octo-org"}}}} =
             Client.graphql(
               "query Viewer { viewer { login } }",
               %{},
               operation_name: "   ",
               request_fun: fn payload, _headers ->
                 send(parent, {:blank_payload, payload})
                 {:ok, %{status: 200, body: %{"data" => %{"viewer" => %{"login" => "octo-org"}}}}}
               end
             )

    assert_receive {:blank_payload, blank_payload}
    refute Map.has_key?(blank_payload, "operationName")
  end

  test "create_comment and update_comment mutations return adapter-friendly results" do
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubAddComment" ->
          {:ok, %{"data" => %{"addComment" => %{"commentEdge" => %{"node" => %{"id" => "comment-1"}}}}}}

        query =~ "SymphonyGithubUpdateComment" ->
          {:ok, %{"data" => %{"updateIssueComment" => %{"issueComment" => %{"id" => variables.id}}}}}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert {:ok, "comment-1"} = Client.create_comment_for_test("issue-1", "hello", graphql_fun)
    assert_receive {:graphql_call, create_query, %{subjectId: "issue-1", body: "hello"}}
    assert create_query =~ "mutation SymphonyGithubAddComment"

    assert :ok = Client.update_comment_for_test("comment-1", "updated", graphql_fun)
    assert_receive {:graphql_call, update_query, %{id: "comment-1", body: "updated"}}
    assert update_query =~ "mutation SymphonyGithubUpdateComment"
  end

  test "comment mutations surface malformed github responses" do
    assert {:error, :github_comment_create_failed} =
             Client.create_comment_for_test("issue-1", "hello", fn _query, _variables ->
               {:ok, %{"data" => %{"addComment" => %{}}}}
             end)

    assert {:error, :github_comment_update_failed} =
             Client.update_comment_for_test("comment-1", "hello", fn _query, _variables ->
               {:ok, %{"data" => %{"updateIssueComment" => %{}}}}
             end)
  end

  test "upsert_workpad_comment creates a comment when no tracked workpad exists" do
    tracker = github_tracker([])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubWorkpadComments" ->
          {:ok,
           %{
             "data" => %{
               "viewer" => %{"login" => "octo-bot"},
               "node" => %{"comments" => %{"nodes" => []}}
             }
           }}

        query =~ "SymphonyGithubAddComment" ->
          {:ok,
           %{
             "data" => %{
               "addComment" => %{"commentEdge" => %{"node" => %{"id" => "comment-new"}}}
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert :ok =
             Client.upsert_workpad_comment_for_test(
               tracker,
               "issue-1",
               "## Codex Workpad\n<!-- symphony:workpad -->\nhello",
               graphql_fun
             )

    assert_receive {:graphql_call, lookup_query, %{id: "issue-1", commentsFirst: 50}}
    assert lookup_query =~ "query SymphonyGithubWorkpadComments"
    assert_receive {:graphql_call, create_query, %{subjectId: "issue-1", body: body}}
    assert create_query =~ "mutation SymphonyGithubAddComment"
    assert body =~ "<!-- symphony:workpad -->"
    refute_receive {:graphql_call, _, %{id: "comment-1", body: _}}
  end

  test "upsert_workpad_comment updates the matching tracked workpad comment in place" do
    tracker = github_tracker([])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubWorkpadComments" ->
          {:ok,
           %{
             "data" => %{
               "viewer" => %{"login" => "octo-bot"},
               "node" => %{
                 "comments" => %{
                   "nodes" => [
                     %{
                       "id" => "comment-1",
                       "body" => "## Codex Workpad\n<!-- symphony:workpad -->\nold body",
                       "author" => %{"login" => "octo-bot"}
                     }
                   ]
                 }
               }
             }
           }}

        query =~ "SymphonyGithubUpdateComment" ->
          {:ok,
           %{
             "data" => %{
               "updateIssueComment" => %{"issueComment" => %{"id" => variables.id}}
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert :ok =
             Client.upsert_workpad_comment_for_test(
               tracker,
               "issue-1",
               "## Codex Workpad\n<!-- symphony:workpad -->\nupdated body",
               graphql_fun
             )

    assert_receive {:graphql_call, lookup_query, %{id: "issue-1", commentsFirst: 50}}
    assert lookup_query =~ "query SymphonyGithubWorkpadComments"
    assert_receive {:graphql_call, update_query, %{id: "comment-1", body: body}}
    assert update_query =~ "mutation SymphonyGithubUpdateComment"
    assert body =~ "updated body"
    refute_receive {:graphql_call, _, %{subjectId: "issue-1", body: _}}
  end

  test "upsert_workpad_comment ignores marker matches authored by someone else" do
    tracker = github_tracker([])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubWorkpadComments" ->
          {:ok,
           %{
             "data" => %{
               "viewer" => %{"login" => "octo-bot"},
               "node" => %{
                 "comments" => %{
                   "nodes" => [
                     %{
                       "id" => "comment-other",
                       "body" => "## Codex Workpad\n<!-- symphony:workpad -->\nforeign body",
                       "author" => %{"login" => "someone-else"}
                     }
                   ]
                 }
               }
             }
           }}

        query =~ "SymphonyGithubAddComment" ->
          {:ok,
           %{
             "data" => %{
               "addComment" => %{"commentEdge" => %{"node" => %{"id" => "comment-new"}}}
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert :ok =
             Client.upsert_workpad_comment_for_test(
               tracker,
               "issue-1",
               "## Codex Workpad\n<!-- symphony:workpad -->\nours",
               graphql_fun
             )

    assert_receive {:graphql_call, _lookup_query, %{id: "issue-1", commentsFirst: 50}}
    assert_receive {:graphql_call, create_query, %{subjectId: "issue-1", body: body}}
    assert create_query =~ "mutation SymphonyGithubAddComment"
    assert body =~ "ours"
    refute_receive {:graphql_call, _, %{id: "comment-other", body: _}}
  end

  test "upsert_workpad_comment accepts atom-key marker config and returns create failures" do
    tracker = github_tracker(workpad_comment: %{heading: "## Codex Workpad", marker: "<!-- atom-workpad -->"})

    assert {:error, :github_comment_create_failed} =
             Client.upsert_workpad_comment_for_test(
               tracker,
               "issue-1",
               "## Codex Workpad\n<!-- atom-workpad -->\nbody",
               fn query, _variables ->
                 if query =~ "SymphonyGithubWorkpadComments" do
                   {:ok, %{"data" => %{"viewer" => %{"login" => "octo-bot"}, "node" => %{"comments" => %{"nodes" => []}}}}}
                 else
                   {:ok, %{"data" => %{"addComment" => %{}}}}
                 end
               end
             )
  end

  test "upsert_workpad_comment extracts markers from the body and ignores malformed comment entries" do
    tracker = github_tracker(workpad_comment: %{heading: "## Codex Workpad"})
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubWorkpadComments" ->
          {:ok,
           %{
             "data" => %{
               "viewer" => %{},
               "node" => %{
                 "comments" => %{
                   "nodes" => [
                     %{"body" => "<!-- extracted-workpad -->\nmissing id"},
                     %{"id" => "comment-1", "body" => "## Codex Workpad\n<!-- extracted-workpad -->\nold body"}
                   ]
                 }
               }
             }
           }}

        query =~ "SymphonyGithubUpdateComment" ->
          {:ok, %{"data" => %{"updateIssueComment" => %{"issueComment" => %{"id" => variables.id}}}}}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert :ok =
             Client.upsert_workpad_comment_for_test(
               tracker,
               "issue-1",
               "## Codex Workpad\n<!-- extracted-workpad -->\nupdated body",
               graphql_fun
             )

    assert_receive {:graphql_call, _lookup_query, %{id: "issue-1", commentsFirst: 50}}
    assert_receive {:graphql_call, update_query, %{id: "comment-1", body: updated_body}}
    assert update_query =~ "mutation SymphonyGithubUpdateComment"
    assert updated_body =~ "updated body"
  end

  test "upsert_workpad_comment returns an error when no marker can be resolved" do
    tracker = github_tracker(workpad_comment: %{heading: "## Codex Workpad"})

    assert {:error, :github_workpad_marker_missing} =
             Client.upsert_workpad_comment_for_test(
               tracker,
               "issue-1",
               "## Codex Workpad\nbody only",
               fn _query, _variables -> flunk("graphql should not be called without a marker") end
             )
  end

  test "update_issue_state resolves the tracked project item and status option id" do
    tracker = github_tracker(projects: [%{"number" => 5}])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      cond do
        query =~ "SymphonyGithubHydrate" ->
          {:ok,
           %{
             "data" => %{
               "owner" => %{
                 "project" => %{
                   "id" => "project-5",
                   "number" => 5,
                   "title" => "Tracker Project",
                   "url" => "https://github.com/users/octo-org/projects/5",
                   "field" => %{
                     "id" => "field-5",
                     "name" => "Status",
                     "dataType" => "SINGLE_SELECT",
                     "options" => [
                       %{"id" => "opt-merging", "name" => "Merging"},
                       %{"id" => "opt-done", "name" => "Done"}
                     ]
                   }
                 }
               }
             }
           }}

        query =~ "SymphonyGithubIssueRefresh" ->
          {:ok,
           %{
             "data" => %{
               "node" => %{
                 "id" => variables.id,
                 "number" => 42,
                 "title" => "Issue #{variables.id}",
                 "body" => "Body #{variables.id}",
                 "url" => "https://github.com/octo-org/example/issues/42",
                 "state" => "OPEN",
                 "stateReason" => nil,
                 "updatedAt" => "2026-03-21T11:22:33Z",
                 "repository" => %{
                   "nameWithOwner" => "octo-org/example",
                   "url" => "https://github.com/octo-org/example",
                   "sshUrl" => "git@github.com:octo-org/example.git",
                   "defaultBranchRef" => %{"name" => "main"}
                 },
                 "labels" => %{"nodes" => []},
                 "assignees" => %{"nodes" => []},
                 "issueDependenciesSummary" => %{"blockedBy" => 0, "totalBlockedBy" => 0},
                 "blockedBy" => %{"nodes" => []},
                 "projectItems" => %{
                   "nodes" => [
                     %{
                       "id" => "item-1",
                       "project" => %{
                         "id" => "project-5",
                         "number" => 5,
                         "title" => "Tracker Project",
                         "url" => "https://github.com/users/octo-org/projects/5"
                       },
                       "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"}
                     }
                   ]
                 }
               }
             }
           }}

        query =~ "SymphonyGithubUpdateProjectItemStatus" ->
          {:ok,
           %{
             "data" => %{
               "updateProjectV2ItemFieldValue" => %{
                 "projectV2Item" => %{"id" => variables.itemId}
               }
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query}")
      end
    end

    assert :ok = Client.update_issue_state_for_test(tracker, "issue-1", "Done", graphql_fun)
    assert_receive {:graphql_call, _hydrate_query, %{number: 5, statusFieldName: "Status"}}
    assert_receive {:graphql_call, refresh_query, %{id: "issue-1", statusFieldName: "Status"}}
    assert refresh_query =~ "query SymphonyGithubIssueRefresh"

    assert_receive {:graphql_call, update_query, %{projectId: "project-5", itemId: "item-1", fieldId: "field-5", optionId: "opt-done"}}

    assert update_query =~ "mutation SymphonyGithubUpdateProjectItemStatus"
  end

  test "update_issue_state surfaces missing project items, unknown states, and malformed update payloads" do
    tracker = github_tracker(projects: [%{"number" => 5}])

    missing_project_item_fun = fn query, variables ->
      cond do
        query =~ "SymphonyGithubHydrate" ->
          {:ok, github_hydration_response(5)}

        query =~ "SymphonyGithubIssueRefresh" ->
          {:ok,
           %{
             "data" => %{
               "node" => github_issue_node("issue-1", 42, project_items: %{"nodes" => [%{"id" => "item-x", "project" => %{"number" => 99}}]})
             }
           }}

        true ->
          flunk("unexpected graphql query: #{query} #{inspect(variables)}")
      end
    end

    assert {:error, :github_project_item_not_found} =
             Client.update_issue_state_for_test(tracker, "issue-1", "Done", missing_project_item_fun)

    assert {:error, {:github_status_option_not_found, "Archived"}} =
             Client.update_issue_state_for_test(tracker, "issue-1", "Archived", fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok, github_hydration_response(5, options: [%{"id" => "opt-todo", "name" => "Todo"}])}

                 query =~ "SymphonyGithubIssueRefresh" ->
                   {:ok,
                    %{
                      "data" => %{
                        "node" =>
                          github_issue_node("issue-1", 42,
                            project_items: %{
                              "nodes" => [
                                %{
                                  "id" => "item-1",
                                  "project" => %{"id" => "project-5", "number" => 5, "title" => "Project 5", "url" => "https://github.com/users/octo-org/projects/5"},
                                  "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"}
                                }
                              ]
                            }
                          )
                      }
                    }}

                 true ->
                   flunk("unexpected graphql query: #{query} #{inspect(variables)}")
               end
             end)

    assert {:error, :github_issue_update_failed} =
             Client.update_issue_state_for_test(tracker, "issue-1", "Done", fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok,
                    github_hydration_response(5,
                      options: [
                        %{"id" => "opt-todo", "name" => "Todo"},
                        %{"id" => "opt-done", "name" => "Done"}
                      ]
                    )}

                 query =~ "SymphonyGithubIssueRefresh" ->
                   {:ok,
                    %{
                      "data" => %{
                        "node" =>
                          github_issue_node("issue-1", 42,
                            project_items: %{
                              "nodes" => [
                                %{
                                  "id" => "item-1",
                                  "project" => %{"id" => "project-5", "number" => 5, "title" => "Project 5", "url" => "https://github.com/users/octo-org/projects/5"},
                                  "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"}
                                }
                              ]
                            }
                          )
                      }
                    }}

                 query =~ "SymphonyGithubUpdateProjectItemStatus" ->
                   {:ok, %{"data" => %{"updateProjectV2ItemFieldValue" => %{}}}}

                 true ->
                   flunk("unexpected graphql query: #{query} #{inspect(variables)}")
               end
             end)
  end

  test "hydrate_projects_for_test accepts mixed project config entries and ignores malformed options" do
    tracker = github_tracker(projects: [%{number: 5}, 6, %{"number" => "bad"}])
    parent = self()

    graphql_fun = fn query, variables ->
      send(parent, {:graphql_call, query, variables})

      {:ok,
       github_hydration_response(variables.number,
         options: [
           %{"id" => "opt-todo-#{variables.number}", "name" => "Todo"},
           %{"id" => "opt-done-#{variables.number}", "name" => "Done"},
           %{"id" => variables.number}
         ]
       )}
    end

    assert {:ok, catalog} = Client.hydrate_projects_for_test(tracker, graphql_fun)
    assert Enum.map(catalog.projects, & &1.project_number) == [5, 6]
    assert hd(catalog.projects).status_option_ids_by_name["Todo"] == "opt-todo-5"

    assert_receive {:graphql_call, _query, %{number: 5}}
    assert_receive {:graphql_call, _query, %{number: 6}}
    refute_receive {:graphql_call, _query, %{number: "bad"}}
  end

  test "hydrate_projects_for_test surfaces owner and status field decode failures" do
    tracker = github_tracker([])

    assert {:error, :github_owner_not_found} =
             Client.hydrate_projects_for_test(tracker, fn _query, _variables ->
               {:ok, %{"data" => %{"owner" => nil}}}
             end)

    assert {:error, {:github_project_not_found, 5}} =
             Client.hydrate_projects_for_test(tracker, fn _query, _variables ->
               {:ok, %{"data" => %{"owner" => %{"project" => nil}}}}
             end)

    assert {:error, {:github_project_hydration_failed, 5}} =
             Client.hydrate_projects_for_test(tracker, fn _query, _variables ->
               {:ok, %{"data" => %{}}}
             end)

    assert {:error, {:github_status_field_not_found, "Status"}} =
             Client.hydrate_projects_for_test(tracker, fn _query, _variables ->
               {:ok,
                %{
                  "data" => %{
                    "owner" => %{
                      "project" => %{
                        "id" => "project-5",
                        "number" => 5,
                        "title" => "Tracker Project",
                        "url" => "https://github.com/users/octo-org/projects/5",
                        "field" => %{"id" => "field-5", "name" => "Priority", "options" => []}
                      }
                    }
                  }
                }}
             end)

    assert {:error, {:github_status_field_not_found, "Status"}} =
             Client.hydrate_projects_for_test(tracker, fn _query, _variables ->
               {:ok,
                %{
                  "data" => %{
                    "owner" => %{
                      "project" => %{
                        "id" => "project-5",
                        "number" => 5,
                        "title" => "Tracker Project",
                        "url" => "https://github.com/users/octo-org/projects/5",
                        "field" => %{"id" => "field-5"}
                      }
                    }
                  }
                }}
             end)
  end

  test "fetch_candidate_issues_for_test paginates results, skips malformed items, and de-duplicates issues across projects" do
    tracker = github_tracker(projects: [%{"number" => 5}, %{"number" => 6}])

    graphql_fun = fn query, variables ->
      cond do
        query =~ "SymphonyGithubHydrate" ->
          {:ok, github_hydration_response(variables.number)}

        query =~ "SymphonyGithubPoll" and variables.number == 5 and is_nil(variables.after) ->
          {:ok,
           github_poll_response(
             [
               %{
                 "id" => "item-1",
                 "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"},
                 "content" => github_issue_node("shared-issue", 42)
               },
               %{"id" => "broken-item"}
             ],
             has_next_page: true,
             end_cursor: "cursor-1"
           )}

        query =~ "SymphonyGithubPoll" and variables.number == 5 and variables.after == "cursor-1" ->
          {:ok,
           github_poll_response([
             %{
               "id" => "item-2",
               "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"},
               "content" => github_issue_node("issue-5", 43)
             }
           ])}

        query =~ "SymphonyGithubPoll" and variables.number == 6 ->
          {:ok,
           github_poll_response([
             %{
               "id" => "item-3",
               "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"},
               "content" => github_issue_node("shared-issue", 42)
             },
             %{
               "id" => "item-4",
               "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"},
               "content" => github_issue_node("issue-6", 44)
             }
           ])}

        true ->
          flunk("unexpected graphql query: #{query} #{inspect(variables)}")
      end
    end

    assert {:ok, issues} = Client.fetch_candidate_issues_for_test(tracker, ["Todo"], graphql_fun)
    assert Enum.map(issues, & &1.id) == ["shared-issue", "issue-5", "issue-6"]
  end

  test "fetch_candidate_issues_for_test surfaces poll transport, decode, and pagination cursor failures" do
    tracker = github_tracker([])

    assert {:error, :poll_failed} =
             Client.fetch_candidate_issues_for_test(tracker, ["Todo"], fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok, github_hydration_response(variables.number)}

                 query =~ "SymphonyGithubPoll" ->
                   {:error, :poll_failed}

                 true ->
                   flunk("unexpected graphql query: #{query}")
               end
             end)

    Client.clear_project_cache_for_test()

    assert {:error, :github_poll_decode_failed} =
             Client.fetch_candidate_issues_for_test(tracker, ["Todo"], fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok, github_hydration_response(variables.number)}

                 query =~ "SymphonyGithubPoll" ->
                   {:ok, %{"data" => %{}}}

                 true ->
                   flunk("unexpected graphql query: #{query}")
               end
             end)

    Client.clear_project_cache_for_test()

    assert {:error, :github_missing_end_cursor} =
             Client.fetch_candidate_issues_for_test(tracker, ["Todo"], fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok, github_hydration_response(variables.number)}

                 query =~ "SymphonyGithubPoll" ->
                   {:ok, github_poll_response([], has_next_page: true, end_cursor: nil)}

                 true ->
                   flunk("unexpected graphql query: #{query}")
               end
             end)
  end

  test "fetch_issue_states_by_ids_for_test surfaces refresh transport and decode failures" do
    tracker = github_tracker([])

    assert {:error, :refresh_failed} =
             Client.fetch_issue_states_by_ids_for_test(tracker, ["issue-1"], fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok, github_hydration_response(variables.number)}

                 query =~ "SymphonyGithubIssueRefresh" ->
                   {:error, :refresh_failed}

                 true ->
                   flunk("unexpected graphql query: #{query}")
               end
             end)

    Client.clear_project_cache_for_test()

    assert {:error, :github_issue_refresh_decode_failed} =
             Client.fetch_issue_states_by_ids_for_test(tracker, ["issue-1"], fn query, variables ->
               cond do
                 query =~ "SymphonyGithubHydrate" ->
                   {:ok, github_hydration_response(variables.number)}

                 query =~ "SymphonyGithubIssueRefresh" ->
                   {:ok, %{"data" => %{}}}

                 true ->
                   flunk("unexpected graphql query: #{query}")
               end
             end)
  end

  test "normalize_issue_for_test keeps sparse issues stable when project items are malformed or unmatched" do
    catalog = %{
      status_field_name: "Status",
      fingerprint: {"user", "octo-org", [5], "Status", "octo-worker"},
      projects_by_number: %{5 => %{status_field_id: "field-5"}}
    }

    issue =
      github_issue_node("issue-1", "not-an-int",
        updated_at: "not-a-date",
        assignees: %{"nodes" => [%{"login" => 42}, 123]},
        labels: nil,
        blocked_by: nil,
        project_items: %{
          "nodes" => [
            %{"id" => "item-unknown", "project" => %{"number" => 99}},
            %{"project" => %{"number" => 5}}
          ]
        }
      )

    normalized = Client.normalize_issue_for_test(issue, catalog)
    assert normalized.identifier == nil
    assert normalized.project_items == []
    assert normalized.project_id == nil
    assert normalized.project_number == nil
    assert normalized.project_title == nil
    assert normalized.project_url == nil
    assert normalized.project_item_id == nil
    assert normalized.status_field_id == nil
    assert normalized.labels == []
    assert normalized.blocked_by == []
    assert normalized.assigned_to_worker == false
    assert normalized.updated_at == nil
  end

  test "normalize_issue_for_test falls back cleanly when project items or tracker metadata are missing" do
    issue =
      github_issue_node("issue-2", 2,
        updated_at: nil,
        assignees: %{"nodes" => [%{"login" => "octo-worker"}]},
        project_items: %{"nodes" => "broken"}
      )

    normalized_with_missing_project_items =
      Client.normalize_issue_for_test(issue, %{
        status_field_name: "Status",
        fingerprint: {"user", "octo-org", [5], "Status", 123},
        projects_by_number: %{5 => %{status_field_id: "field-5"}}
      })

    assert normalized_with_missing_project_items.project_items == []
    assert normalized_with_missing_project_items.assigned_to_worker == false

    normalized =
      Client.normalize_issue_for_test(issue, %{
        status_field_name: "Status",
        fingerprint: :invalid
      })

    assert normalized.project_items == []
    assert normalized.project_id == nil
    assert normalized.project_item_id == nil
    assert normalized.updated_at == nil
    assert normalized.assigned_to_worker == true
  end

  test "github issue label_names returns normalized labels unchanged" do
    issue = %Issue{labels: ["orchestration", "bug"]}
    assert Issue.label_names(issue) == ["orchestration", "bug"]
  end

  defp github_tracker(overrides) when is_list(overrides) do
    Keyword.merge(
      [
        endpoint: "https://api.github.com/graphql",
        api_key: "gh-token",
        owner: %{"type" => "user", "login" => "octo-org"},
        projects: [%{"number" => 5}],
        status_field_name: "Status",
        workpad_comment: %{"heading" => "## Codex Workpad", "marker" => "<!-- symphony:workpad -->"},
        active_states: ["Todo", "In Progress", "Rework", "Merging"],
        assignee: nil
      ],
      overrides
    )
    |> Enum.into(%{})
  end

  defp write_github_workflow!(opts) do
    api_key = Keyword.get(opts, :api_key, "token")
    endpoint = Keyword.get(opts, :endpoint, "https://api.github.com/graphql")
    active_states = Keyword.get(opts, :active_states, ["Todo", "In Progress", "Rework", "Merging"])
    projects = Keyword.get(opts, :projects, [%{"number" => 5}])
    workspace_root = Path.join(System.tmp_dir!(), "symphony-github-client-tests")

    contents =
      [
        "---",
        "tracker:",
        "  kind: \"github\"",
        "  endpoint: #{yaml_value(endpoint)}",
        "  api_key: #{yaml_value(api_key)}",
        "  owner: {\"login\": \"octo-org\", \"type\": \"organization\"}",
        "  projects: #{yaml_value(projects)}",
        "  status_field_name: \"Status\"",
        "  workpad_comment: {\"heading\": \"## Codex Workpad\", \"marker\": \"<!-- symphony:workpad -->\"}",
        "  active_states: #{yaml_value(active_states)}",
        "workspace:",
        "  root: #{yaml_value(workspace_root)}",
        "---",
        "GitHub workflow prompt"
      ]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    File.write!(Workflow.workflow_file_path(), contents)
    SymphonyElixir.WorkflowStore.force_reload()
  end

  defp yaml_value(nil), do: "null"
  defp yaml_value(value) when is_binary(value), do: inspect(value)
  defp yaml_value(value) when is_integer(value), do: Integer.to_string(value)
  defp yaml_value(values) when is_list(values), do: "[" <> Enum.map_join(values, ", ", &yaml_value/1) <> "]"

  defp yaml_value(values) when is_map(values) do
    "{" <>
      Enum.map_join(values, ", ", fn {key, value} ->
        "#{yaml_value(to_string(key))}: #{yaml_value(value)}"
      end) <> "}"
  end

  defp start_github_graphql_server!(response_fun) do
    {:ok, pid} =
      Bandit.start_link(
        plug: {GraphqlEndpointPlug, test_pid: self(), response_fun: response_fun},
        ip: {127, 0, 0, 1},
        port: 0
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/graphql"
  end

  defp github_hydration_response(project_number, opts \\ []) do
    options =
      Keyword.get(opts, :options, [
        %{"id" => "opt-todo", "name" => "Todo"},
        %{"id" => "opt-done", "name" => "Done"}
      ])

    field =
      Keyword.get(opts, :field, %{
        "id" => "field-#{project_number}",
        "name" => "Status",
        "dataType" => "SINGLE_SELECT",
        "options" => options
      })

    %{
      "data" => %{
        "owner" => %{
          "project" => %{
            "id" => "project-#{project_number}",
            "number" => project_number,
            "title" => "Project #{project_number}",
            "url" => "https://github.com/users/octo-org/projects/#{project_number}",
            "field" => field
          }
        }
      }
    }
  end

  defp github_poll_response(nodes, opts \\ []) do
    %{
      "data" => %{
        "owner" => %{
          "project" => %{
            "items" => %{
              "nodes" => nodes,
              "pageInfo" => %{
                "hasNextPage" => Keyword.get(opts, :has_next_page, false),
                "endCursor" => Keyword.get(opts, :end_cursor, nil)
              }
            }
          }
        }
      }
    }
  end

  defp github_issue_node(issue_id, number, opts \\ []) do
    repository =
      Keyword.get(opts, :repository, %{
        "nameWithOwner" => "octo-org/example",
        "url" => "https://github.com/octo-org/example",
        "sshUrl" => "git@github.com:octo-org/example.git",
        "defaultBranchRef" => %{"name" => "main"}
      })

    %{
      "id" => issue_id,
      "number" => number,
      "title" => Keyword.get(opts, :title, "Issue #{issue_id}"),
      "body" => Keyword.get(opts, :body, "Body #{issue_id}"),
      "url" => Keyword.get(opts, :url, "https://github.com/octo-org/example/issues/#{number}"),
      "state" => Keyword.get(opts, :issue_state, "OPEN"),
      "stateReason" => Keyword.get(opts, :state_reason, nil),
      "updatedAt" => Keyword.get(opts, :updated_at, "2026-03-21T11:22:33Z"),
      "repository" => repository,
      "labels" => Keyword.get(opts, :labels, %{"nodes" => [%{"name" => "Needs Review"}]}),
      "assignees" => Keyword.get(opts, :assignees, %{"nodes" => [%{"login" => "octo-worker"}]}),
      "issueDependenciesSummary" => %{"blockedBy" => 0, "totalBlockedBy" => 0},
      "blockedBy" => Keyword.get(opts, :blocked_by, %{"nodes" => []}),
      "projectItems" =>
        Keyword.get(opts, :project_items, %{
          "nodes" => [
            %{
              "id" => "item-#{issue_id}",
              "project" => %{
                "id" => "project-5",
                "number" => 5,
                "title" => "Project 5",
                "url" => "https://github.com/users/octo-org/projects/5"
              },
              "fieldValueByName" => %{"name" => "Todo", "optionId" => "opt-todo"}
            }
          ]
        })
    }
  end
end
