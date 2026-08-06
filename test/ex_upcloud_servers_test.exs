defmodule ExUpcloud.StubAdapter do
  @moduledoc """
  Test adapter that answers every request from the process dictionary and
  forwards the outgoing request to the listening test process.

  A module rather than an anonymous function because Req 0.7 deprecated
  function adapters (`Req.Request.adapter/1`). Configuration travels through
  the process dictionary rather than options because Req runs the adapter
  inline in the calling process, so it is the test's own dictionary.
  """

  def run(request) do
    %{status: status, body: body, listener: listener} = Process.get(:ex_upcloud_stub)
    send(listener, {:request, request})
    {request, %Req.Response{status: status, body: body}}
  end
end

defmodule ExUpcloud.ServersTest do
  @moduledoc """
  Wire-level tests for the server lifecycle calls.

  `Req.Test` would be the other option, but it needs `:plug`, and since
  `Servers.stop/3` does not forward Req options the stub has to be installed
  globally either way — which forfeits the ownership model that is `Req.Test`'s
  real advantage. A plain adapter keeps the dependency list short.

  `Req.default_options/1` is global, hence `async: false`.
  """
  use ExUnit.Case, async: false

  alias ExUpcloud.Config
  alias ExUpcloud.Servers

  @config %Config{username: "user", password: "pass", zone: "fi-hel1"}
  @uuid "00000000-0000-0000-0000-000000000001"

  setup do
    on_exit(fn -> Req.default_options([]) end)
    :ok
  end

  # Answers every request with `status`/`body` and forwards the request itself
  # to the test process so the emitted payload can be asserted on.
  defp stub_response(status, body \\ %{}) do
    Process.put(:ex_upcloud_stub, %{status: status, body: body, listener: self()})
    Req.default_options(adapter: ExUpcloud.StubAdapter)
  end

  defp emitted_body do
    assert_received {:request, request}
    request.body |> IO.iodata_to_binary() |> Jason.decode!()
  end

  describe "stop/3" do
    test "defaults to a soft stop that leaves the server running on timeout" do
      stub_response(200)

      assert :ok = Servers.stop(@config, @uuid)

      assert %{"stop_server" => stop_server} = emitted_body()
      assert stop_server == %{"stop_type" => "soft", "timeout" => 180}
    end

    test "posts to the server's stop endpoint" do
      stub_response(200)

      assert :ok = Servers.stop(@config, @uuid)

      assert_received {:request, request}
      assert request.method == :post
      assert URI.to_string(request.url) =~ "/1.3/server/#{@uuid}/stop"
    end

    # The deploy pipeline needs a window long enough for the BEAM to drain its
    # Oban queues. The exact-map assertions here are the point: `stop_server`
    # rejects any attribute it does not know with `UNKNOWN_ATTRIBUTE`, and a
    # subset match let a bogus `timeout_action` reach a real deploy.
    test "honours an explicit timeout" do
      stub_response(200)

      assert :ok = Servers.stop(@config, @uuid, timeout: 540)

      assert %{"stop_server" => stop_server} = emitted_body()
      assert stop_server == %{"stop_type" => "soft", "timeout" => 540}
    end

    test "rejects timeout_action, which belongs to restart rather than stop" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Servers.stop(@config, @uuid, timeout_action: "destroy")
      end
    end

    test "supports a hard stop" do
      stub_response(200)

      assert :ok = Servers.stop(@config, @uuid, stop_type: "hard")

      assert %{"stop_server" => %{"stop_type" => "hard"}} = emitted_body()
    end

    test "rejects unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Servers.stop(@config, @uuid, wait_forever: true)
      end
    end

    test "rejects values the API would reject anyway" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Servers.stop(@config, @uuid, stop_type: "gentle")
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        Servers.stop(@config, @uuid, timeout: 0)
      end
    end

    # `Request.send/5` hands back `Req.request/1` verbatim, without the non-2xx
    # normalisation `Request.get/3` does — so an unhandled `{:ok, %Response{}}`
    # used to escape the case as a CaseClauseError instead of an error tuple.
    test "returns an error tuple rather than raising on a non-200 response" do
      stub_response(400, %{"error" => %{"error_code" => "INVALID_REQUEST"}})

      assert {:error, %{"error" => %{"error_code" => "INVALID_REQUEST"}}} =
               Servers.stop(@config, @uuid)
    end
  end

  describe "stop!/3" do
    test "passes its arguments through in the right order" do
      stub_response(200)

      assert :ok = Servers.stop!(@config, @uuid)
    end

    test "forwards options" do
      stub_response(200)

      assert :ok = Servers.stop!(@config, @uuid, timeout: 540)

      assert %{"stop_server" => %{"timeout" => 540}} = emitted_body()
    end

    test "raises on an API error" do
      stub_response(400, %{"error" => "nope"})

      assert_raise RuntimeError, ~r/Could not stop server/, fn ->
        Servers.stop!(@config, @uuid)
      end
    end
  end

  describe "start/2" do
    test "starts the server asynchronously" do
      stub_response(200)

      assert :ok = Servers.start(@config, @uuid)

      assert %{"server" => %{"start_type" => "async"}} = emitted_body()
    end

    test "returns an error tuple rather than raising on a non-200 response" do
      stub_response(400, %{"error" => "nope"})

      assert {:error, %{"error" => "nope"}} = Servers.start(@config, @uuid)
    end
  end

  describe "start!/2" do
    test "passes its arguments through in the right order" do
      stub_response(200)

      assert :ok = Servers.start!(@config, @uuid)
    end

    test "raises on an API error" do
      stub_response(400, %{"error" => "nope"})

      assert_raise RuntimeError, ~r/Could not start server/, fn ->
        Servers.start!(@config, @uuid)
      end
    end
  end
end
