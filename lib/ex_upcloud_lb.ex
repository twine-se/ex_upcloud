defmodule ExUpcloud.Lb do
  @moduledoc false
  import ExUpcloud.Labels
  import ExUpcloud.Request

  alias ExUpcloud.Config

  def list(%Config{} = config, filter_labels \\ []) do
    case get("/1.3/load-balancer", config) do
      {:ok, %Req.Response{body: body}} ->
        lbs =
          Enum.filter(body, fn lb ->
            Enum.all?(
              filter_labels,
              &has_label(lb, &1 |> elem(0) |> to_string(), &1 |> elem(1) |> to_string())
            )
          end)

        {:ok, lbs}

      other ->
        other
    end
  end

  def list!(%Config{} = config, filter_labels \\ []) do
    case list(config, filter_labels) do
      {:ok, lbs} ->
        lbs

      {:error, reason} ->
        raise "Could not get load balancers: #{inspect(reason)}"
    end
  end

  def get_metrics!(uuid, %Config{} = config) do
    case get("/1.3/load-balancer/#{uuid}/metrics", config) do
      {:ok, %Req.Response{body: body}} -> body
      {:error, reason} -> raise "Could not get load balancer metrics: #{inspect(reason)}"
    end
  end

  def attach_member!(
        %{load_balancer_uuid: load_balancer_uuid, backend_name: backend_name},
        %{hostname: hostname, ip: ip, port: port},
        %Config{} = config
      ) do
    body = %{
      name: hostname,
      ip: ip,
      port: port,
      type: "static",
      weight: 100,
      max_sessions: 10_000,
      enabled: true
    }

    response =
      post(
        "/1.3/load-balancer/#{load_balancer_uuid}/backends/#{backend_name}/members",
        body,
        config
      )

    case response do
      {:ok, %Req.Response{status: 201}} ->
        :ok

      {:error, %{reason: reason}} ->
        raise "Could not attach member: #{inspect(reason)}"
    end
  end

  def set_member_weight!(
        %{load_balancer_uuid: load_balancer_uuid, backend_name: backend_name, member_name: member_name},
        weight,
        %Config{} = config
      ) do
    body = %{
      weight: weight
    }

    response =
      patch(
        "/1.3/load-balancer/#{load_balancer_uuid}/backends/#{backend_name}/members/#{member_name}",
        body,
        config
      )

    case response do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:error, %{reason: reason}} ->
        raise "Could not set member weight: #{inspect(reason)}"
    end
  end

  def delete_member!(
        %{load_balancer_uuid: load_balancer_uuid, backend_name: backend_name, member_name: member_name},
        %Config{} = config
      ) do
    response =
      delete(
        "/1.3/load-balancer/#{load_balancer_uuid}/backends/#{backend_name}/members/#{member_name}",
        nil,
        config
      )

    case response do
      {:ok, %Req.Response{status: 204}} ->
        :ok

      {:error, %{reason: reason}} ->
        raise "Could not delete backend member: #{inspect(reason)}"
    end
  end

  def wait_for_member_health_check!(
        %{load_balancer_uuid: load_balancer_uuid, backend_name: backend_name, member_name: member_name} = ids,
        %{timeout: timeout} = params,
        %Config{} = config
      ) do
    count = Map.get(params, :count, 0)

    if count / 1000 > timeout do
      IO.puts("Member failed to become healthy within #{timeout} seconds. Cleaning up load balancer...")

      delete_member!(ids, config)

      raise "Member health check failed"
    end

    start_time = System.monotonic_time(:millisecond)

    %{"backends" => backends} =
      get_metrics!(load_balancer_uuid, config)

    backend = Enum.find(backends, &(Map.get(&1, "name") == backend_name))
    member = Enum.find(backend["members"], &(Map.get(&1, "name") == member_name))

    case member do
      nil ->
        raise "Member #{member_name} not found"

      %{"status" => "up", "check_status" => "http_ok"} ->
        :ok

      %{"status" => "down"} ->
        IO.puts("Member #{member_name} is down. Cleaning up load balancer...")

        delete_member!(ids, config)
        raise "Member health check failed"

      _ ->
        :timer.sleep(1000)

        wait_for_member_health_check!(
          ids,
          %{timeout: timeout, count: count + System.monotonic_time(:millisecond) - start_time},
          config
        )
    end
  end
end
