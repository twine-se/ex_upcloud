defmodule ExUpcloud.Servers do
  @moduledoc false
  import ExUpcloud.Labels
  import ExUpcloud.Request

  alias ExUpcloud.Config

  @stop_timeout 180

  def list(%Config{} = config, filter_labels \\ []) do
    case get("/1.3/server", config) do
      {:ok, %Req.Response{body: body}} ->
        servers =
          body
          |> Map.get("servers")
          |> Map.get("server")
          |> Enum.filter(fn server ->
            Enum.all?(
              filter_labels,
              &has_label(server, &1 |> elem(0) |> to_string(), &1 |> elem(1) |> to_string())
            )
          end)

        {:ok, servers}

      other ->
        other
    end
  end

  def list!(%Config{} = config, filter_labels \\ []) do
    case list(config, filter_labels) do
      {:ok, servers} ->
        servers

      {:error, reason} ->
        raise "Could not get servers: #{inspect(reason)}"
    end
  end

  def find(uuid, %Config{} = config) do
    case get("/1.3/server/#{uuid}", config) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, Map.get(body, "server")}
      {:error, reason} -> {:error, reason}
    end
  end

  def find!(uuid, %Config{} = config) do
    case find(uuid, config) do
      {:ok, server} ->
        server

      {:error, reason} ->
        raise "Could not get server: #{inspect(reason)}"
    end
  end

  def stop(uuid, %Config{} = config) do
    result =
      post(
        "/1.3/server/#{uuid}/stop",
        %{
          stop_server: %{
            stop_type: "soft",
            timeout: @stop_timeout
          }
        },
        config
      )

    case result do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def stop!(uuid, %Config{} = config) do
    case stop(uuid, config) do
      :ok -> :ok
      {:error, reason} -> raise "Could not stop server: #{inspect(reason)}"
    end
  end

  def start(uuid, %Config{} = config) do
    result =
      post(
        "/1.3/server/#{uuid}/start",
        %{
          server: %{
            start_type: "async"
          }
        },
        config
      )

    case result do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def start!(uuid, %Config{} = config) do
    case start(uuid, config) do
      :ok -> :ok
      {:error, reason} -> raise "Could not start server: #{inspect(reason)}"
    end
  end

  def remove!(uuid, %Config{} = config) do
    %Req.Response{status: 204} =
      delete!("/1.3/server/#{uuid}?storages=true&backups=delete", nil, config)

    :ok
  end

  def create(
        %{
          partition: partition,
          user_data: user_data,
          environment: environment,
          app: app,
          plan: plan,
          ssh_key: ssh_key,
          network_uuid: network_uuid,
          platform_storage_uuid: platform_storage_uuid,
          secrets_storage_uuid: secrets_storage_uuid
        },
        %Config{zone: zone} = config
      ) do
    labels = [
      %{
        key: "partition",
        value: partition
      },
      %{
        key: "app",
        value: app
      },
      %{
        key: "environment",
        value: environment
      }
    ]

    plan = plan || "1xCPU-1GB"

    body = %{
      server: %{
        labels: %{label: labels},
        hostname: "twine-core-#{environment}-#{partition}",
        title: "twine-core-#{environment}-#{partition}",
        password_delivery: "none",
        zone: zone,
        plan: plan,
        metadata: "yes",
        user_data: user_data,
        login_user: %{
          ssh_keys: %{
            ssh_key: [
              ssh_key
            ]
          }
        },
        storage_devices: %{
          storage_device:
            Enum.filter(
              [
                %{
                  action: "clone",
                  storage: platform_storage_uuid,
                  labels: labels,
                  title: "Debian Bookworm - Can be safely deleted",
                  size: 20,
                  tier: "maxiops"
                },
                if is_nil(secrets_storage_uuid) do
                  nil
                else
                  %{action: "attach", storage: secrets_storage_uuid}
                end
              ],
              &(&1 != nil)
            )
        },
        networking: %{
          interfaces: %{
            interface: [
              %{
                ip_addresses: %{
                  ip_address: [
                    %{
                      family: "IPv4"
                    }
                  ]
                },
                type: "utility"
              },
              %{
                type: "private",
                network: network_uuid,
                source_ip_filtering: "no",
                ip_addresses: %{
                  ip_address: [
                    %{
                      family: "IPv4",
                      dhcp_provided: "yes"
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }

    response =
      post(
        "/1.3/server",
        body,
        config
      )

    case response do
      {:ok, %Req.Response{status: 202, body: body}} ->
        {:ok, Map.get(body, "server")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create!(params, %Config{} = config) do
    case create(params, config) do
      {:ok, server} -> server
      {:error, reason} -> raise "Could not create server: #{inspect(reason)}"
    end
  end

  def detach_storage!(server_uuid, storage_uuid, %Config{} = config) do
    result =
      post(
        "/1.3/server/#{server_uuid}/storage/detach",
        %{
          storage_device: %{
            storage: storage_uuid
          }
        },
        config
      )

    case result do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Map.get(body, "server")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_server_by_uuid(servers, server_uuid) do
    Enum.find(servers, fn server -> server["uuid"] == server_uuid end)
  end

  def get_server_ip!(server, network_uuid) do
    case server
         |> Map.get("networking")
         |> Map.get("interfaces")
         |> Map.get("interface")
         |> Enum.find(&(Map.get(&1, "type") == "private" and Map.get(&1, "network") == network_uuid))
         |> Map.get("ip_addresses")
         |> Map.get("ip_address")
         |> Enum.find(&(Map.get(&1, "family") == "IPv4"))
         |> Map.get("address") do
      nil -> raise "No SDN IP found"
      ip -> ip
    end
  end

  def get_server_state!(server_uuid, %Config{} = config) do
    server_uuid
    |> find!(config)
    |> Map.get("state")
  end

  def wait_for_server_state!(server_uuid, required_state, timeout, %Config{} = config) do
    state = get_server_state!(server_uuid, config)

    if state != required_state do
      if timeout - 1 <= 0 do
        raise "Server did not reach state #{required_state} within specified timeout"
      else
        :timer.sleep(1000)
        wait_for_server_state!(server_uuid, required_state, timeout - 1, config)
      end
    end

    :ok
  end
end
