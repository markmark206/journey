defmodule Journey.ToolsTest do
  use ExUnit.Case, async: false

  alias Journey.Scheduler.BackgroundSweeps

  setup do
    # Use start_owner! for better handling of spawned processes
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Journey.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "summarize/1" do
    test "basic validation" do
      graph = Journey.Test.Support.create_test_graph1()
      execution = Journey.start_execution(graph)

      summary = Journey.Tools.summarize(execution.id)

      assert summary =~ """
             Execution summary:
             - ID: '#{execution.id}'
             - Graph: 'test graph 1 Elixir.Journey.Test.Support' | '1.0.0'
             - Archived at: not archived
             """
    end

    test "no such execution" do
      graph = Journey.Test.Support.create_test_graph1()
      _execution = Journey.start_execution(graph)

      assert_raise KeyError, fn ->
        Journey.Tools.summarize("none such")
      end
    end

    test "basic validation, progressed execution " do
      graph = Journey.Test.Support.create_test_graph1()

      execution =
        Journey.start_execution(graph)
        |> Journey.set_value(:user_name, "John Doe")

      background_sweeps_task = BackgroundSweeps.start_background_sweeps_in_test(execution.id)

      {:ok, _} = Journey.get_value(execution, :reminder, wait_any: true)

      summary = Journey.Tools.summarize(execution.id)

      assert summary =~ """
             Execution summary:
             - ID: '#{execution.id}'
             - Graph: 'test graph 1 Elixir.Journey.Test.Support' | '1.0.0'
             - Archived at: not archived
             """

      BackgroundSweeps.stop_background_sweeps_in_test(background_sweeps_task)
    end
  end

  describe "generate_mermaid_graph/1" do
    test "sunny day" do
      graph = Journey.Test.Support.create_test_graph1()

      mermaid_graph =
        Journey.Tools.generate_mermaid_graph(graph)
        |> String.split("\n")
        |> Enum.filter(fn line ->
          !String.contains?(line, "Generated at")
        end)
        |> Enum.join("\n")

      assert mermaid_graph ==
               "graph TD\n    %% Graph\n    subgraph Graph[\"🧩 'test graph 1 Elixir.Journey.Test.Support', version 1.0.0\"]\n        execution_id[execution_id]\n        last_updated_at[last_updated_at]\n        user_name[user_name]\n        greeting[\"greeting<br/>(anonymous fn)\"]\n        time_to_issue_reminder_schedule[\"time_to_issue_reminder_schedule<br/>(anonymous fn)<br/>schedule_once node\"]\n        reminder[\"reminder<br/>(anonymous fn)\"]\n\n        user_name -->  greeting\n        greeting -->  time_to_issue_reminder_schedule\n        greeting -->  reminder\n        time_to_issue_reminder_schedule -->  reminder\n    end\n\n    %% Legend\n    subgraph Legend[\"📖 Legend\"]\n        LegendInput[\"Input Node<br/>User-provided data\"]\n        LegendCompute[\"Compute Node<br/>Self-computing value\"]\n        LegendSchedule[\"Schedule Node<br/>Scheduled trigger\"]\n        LegendMutate[\"Mutate Node<br/>Mutates the value of another node\"]\n    end\n\n    %% Caption\n\n    %% Styling\n    classDef inputNode fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000\n    classDef computeNode fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000\n    classDef scheduleNode fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000000\n    classDef mutateNode fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px,color:#000000\n\n    %% Apply styles to legend nodes\n    class LegendInput inputNode\n    class LegendCompute computeNode\n    class LegendSchedule scheduleNode\n    class LegendMutate mutateNode\n\n    %% Apply styles to actual nodes\n    class user_name,last_updated_at,execution_id inputNode\n    class reminder,greeting computeNode\n    class time_to_issue_reminder_schedule scheduleNode"
    end
  end

  describe "increment_revision/1" do
    test "sunny day" do
      graph = Journey.Test.Support.create_test_graph1()

      execution =
        Journey.start_execution(graph)
        |> Journey.set_value(:user_name, "John Doe")

      background_sweeps_task = BackgroundSweeps.start_background_sweeps_in_test(execution.id)

      {:ok, _} = Journey.get_value(execution, :reminder, wait_any: true)
      execution = execution |> Journey.load()
      assert execution.revision == 7

      Journey.Tools.increment_revision(execution.id, :user_name)
      {:ok, _} = Journey.get_value(execution, :reminder, wait_new: true)
      execution = execution |> Journey.load()
      assert execution.revision == 12

      BackgroundSweeps.stop_background_sweeps_in_test(background_sweeps_task)
    end
  end

  describe "outstanding_computations/1" do
    test "basic validation" do
      graph = Journey.Test.Support.create_test_graph1()
      execution = Journey.start_execution(graph)

      ocs = Journey.Tools.outstanding_computations(execution.id)
      assert Enum.count(ocs) == 3

      Enum.each(ocs, fn %{computation: computation} = oc ->
        case computation.node_name do
          :greeting ->
            assert computation.state == :not_set
            assert oc.conditions_met == []
            assert Enum.count(oc.conditions_not_met) == 1

          :reminder ->
            assert computation.state == :not_set
            assert oc.conditions_met == []
            assert Enum.count(oc.conditions_not_met) == 2

          :time_to_issue_reminder_schedule ->
            assert computation.state == :not_set
            assert oc.conditions_met == []
            assert Enum.count(oc.conditions_not_met) == 1
        end
      end)

      execution =
        execution
        |> Journey.set_value(:user_name, "John Doe")

      background_sweeps_task = BackgroundSweeps.start_background_sweeps_in_test(execution.id)

      {:ok, _} = Journey.get_value(execution, :reminder, wait_any: true)

      ocs = Journey.Tools.outstanding_computations(execution.id)
      assert ocs == []

      BackgroundSweeps.stop_background_sweeps_in_test(background_sweeps_task)
    end
  end
end
