defmodule ExUpcloud.LoadBalancers do
  @moduledoc false
  import ExUpcloud.Labels
  import ExUpcloud.Request

  alias ExUpcloud.Backend
  alias ExUpcloud.BackendMember
  alias ExUpcloud.Config
  alias ExUpcloud.LoadBalancer

  def list(%Config{} = config, filter_labels \\ []) do
    case get("/1.3/load-balancer", config) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        lbs =
          body
          |> Enum.filter(fn lb ->
            Enum.all?(
              filter_labels,
              &has_label(lb, &1 |> elem(0) |> to_string(), &1 |> elem(1) |> to_string())
            )
          end)
          |> Enum.map(&LoadBalancer.parse/1)

        {:ok, lbs}

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
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

  def get_metrics(%Config{} = config, uuid) do
    case get("/1.3/load-balancer/#{uuid}/metrics", config) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  def attach_member(
        %Config{} = config,
        %LoadBalancer{} = load_balancer,
        %Backend{} = backend,
        %BackendMember{} = member
      ) do
    response =
      post(
        "/1.3/load-balancer/#{load_balancer.uuid}/backends/#{backend.name}/members",
        BackendMember.to_payload(member),
        config
      )

    case response do
      {:ok, %Req.Response{status: 201}} ->
        :ok

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  def update_member(
        %Config{} = config,
        %LoadBalancer{} = load_balancer,
        %Backend{} = backend,
        %BackendMember{} = member
      ) do
    response =
      patch(
        "/1.3/load-balancer/#{load_balancer.uuid}/backends/#{backend.name}/members/#{member.name}",
        BackendMember.to_payload(member),
        config
      )

    case response do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_member(
        %Config{} = config,
        %LoadBalancer{} = load_balancer,
        %Backend{} = backend,
        %BackendMember{} = member
      ) do
    response =
      delete(
        "/1.3/load-balancer/#{load_balancer.uuid}/backends/#{backend.name}/members/#{member.name}",
        nil,
        config
      )

    case response do
      {:ok, %Req.Response{status: 204}} ->
        :ok

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def wait_for_member_health_check(
        %Config{} = config,
        %LoadBalancer{} = load_balancer,
        %Backend{} = backend,
        %BackendMember{} = member,
        timeout \\ 180
      ) do
    with {:ok, %{"backends" => backends}} <-
           get_metrics(load_balancer.uuid, config) do
      backend = Enum.find(backends, &(Map.get(&1, "name") == backend.name))
      member = Enum.find(backend["members"], &(Map.get(&1, "name") == member.name))

      case member do
        nil ->
          {:error, "Member #{member.name} not found in backend #{backend.name}"}

        %{"status" => "up", "check_status" => "http_ok"} ->
          :ok

        %{"status" => "down"} ->
          {:error, "Member #{member.name} is down"}

        _ ->
          :timer.sleep(4000)

          wait_for_member_health_check(
            config,
            load_balancer,
            backend,
            member,
            timeout - 4
          )
      end
    end
  end
end
