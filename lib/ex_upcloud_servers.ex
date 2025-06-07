defmodule ExUpcloud.Servers do
  @moduledoc false
  import ExUpcloud.Labels
  import ExUpcloud.Request

  alias ExUpcloud.Config
  alias ExUpcloud.Labels
  alias ExUpcloud.Utils

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
          |> Enum.map(&ExUpcloud.Server.parse/1)

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

  def find(%Config{} = config, uuid) do
    case get("/1.3/server/#{uuid}", config) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body |> Map.get("server") |> ExUpcloud.Server.parse()}

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def find!(%Config{} = config, uuid) do
    case find(config, uuid) do
      {:ok, server} ->
        server

      {:error, reason} ->
        raise "Could not get server: #{inspect(reason)}"
    end
  end

  def stop(%Config{} = config, uuid) do
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

  def stop!(%Config{} = config, uuid) do
    case stop(uuid, config) do
      :ok -> :ok
      {:error, reason} -> raise "Could not stop server: #{inspect(reason)}"
    end
  end

  def start(%Config{} = config, uuid) do
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

  def start!(%Config{} = config, uuid) do
    case start(uuid, config) do
      :ok -> :ok
      {:error, reason} -> raise "Could not start server: #{inspect(reason)}"
    end
  end

  @remove_opts NimbleOptions.new!(
                 delete_storages: [
                   type: :boolean,
                   doc: "Whether to remove attached storage devices.",
                   default: false
                 ],
                 delete_backups: [
                   type: :boolean,
                   doc: "Whether to delete backups.",
                   default: false
                 ]
               )

  def remove(%Config{} = config, uuid, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @remove_opts)

    query =
      if opts[:delete_storages] do
        %{storages: "true"}
      else
        %{}
      end

    query =
      if opts[:delete_backups] do
        Map.put(query, :backups, "delete")
      else
        query
      end

    query = if Enum.empty?(query), do: "", else: "?" <> URI.encode_query(query)

    result = delete("/1.3/server/#{uuid}#{query}", nil, config)

    case result do
      {:ok, %Req.Response{status: 204}} -> :ok
      {:ok, %Req.Response{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @create_opts NimbleOptions.new!(
                 plan: [
                   type: :string,
                   doc: "Plan to use for the server, e.g., `1xCPU-1GB`.",
                   default: "1xCPU-1GB"
                 ],
                 user_data: [
                   type: :string,
                   doc: "User data to be passed to the server."
                 ],
                 ssh_key: [
                   type: :string,
                   doc: "SSH key to be used for the server.",
                   required: false
                 ],
                 interfaces: [
                   type: {:list, {:struct, ExUpcloud.Interface}},
                   required: true
                 ],
                 storages: [
                   type: {:list, {:struct, ExUpcloud.ServerStorageDevice}},
                   doc: "List of storage devices to attach to the server.",
                   default: []
                 ],
                 labels: [
                   type: :map,
                   default: %{}
                 ],
                 hostname: [
                   type: :string,
                   doc: "Hostname for the server.",
                   required: true
                 ],
                 title: [
                   type: :string,
                   doc: "Title for the server.",
                   required: false
                 ],
                 metadata: [
                   type: :boolean,
                   doc: "Whether to include metadata in the server creation.",
                   default: true
                 ],
                 password_delivery: [
                   type: :string,
                   doc: "Method of password delivery. Default is 'none'.",
                   default: "none"
                 ]
               )

  def create(%Config{zone: zone} = config, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @create_opts)

    body =
      Map.reject(
        %{
          server: %{
            labels: %{label: Labels.to_payload(opts[:labels])},
            hostname: opts[:hostname],
            title: opts[:title],
            password_delivery: opts[:password_delivery],
            zone: zone,
            plan: opts[:plan],
            metadata: Utils.yesno(opts[:metadata]),
            user_data: opts[:user_data],
            login_user: %{
              ssh_keys: %{
                ssh_key: [
                  opts[:ssh_key]
                ]
              }
            },
            storage_devices: %{
              storage_device: Enum.map(opts[:storages], &ExUpcloud.ServerStorageDevice.to_payload/1)
            },
            networking: %{
              interfaces: %{interface: Enum.map(opts[:interfaces], &ExUpcloud.Interface.to_payload/1)}
            }
          }
        },
        fn {_, v} -> is_nil(v) end
      )

    response =
      post(
        "/1.3/server",
        body,
        config
      )

    case response do
      {:ok, %Req.Response{status: 202, body: body}} ->
        {:ok, body |> Map.get("server") |> ExUpcloud.Server.parse()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create!(%Config{} = config, opts \\ []) do
    case create(config, opts) do
      {:ok, server} -> server
      {:error, reason} -> raise "Could not create server: #{inspect(reason)}"
    end
  end

  def detach_storage(%Config{} = config, server_uuid, storage_uuid) do
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
        {:ok, body |> Map.get("server") |> ExUpcloud.Server.parse()}

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_server_by_uuid(servers, server_uuid) do
    Enum.find(servers, fn server -> server.uuid == server_uuid end)
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

  def get_server_state!(%Config{} = config, uuid) do
    config
    |> find!(uuid)
    |> Map.get(:state)
  end

  def wait_for_server_state!(%Config{} = config, server_uuid, required_state, timeout \\ 180) do
    state = get_server_state!(config, server_uuid)

    if state != required_state do
      if timeout - 1 <= 0 do
        raise "Server did not reach state #{required_state} within specified timeout"
      else
        :timer.sleep(1000)
        wait_for_server_state!(config, server_uuid, required_state, timeout - 1)
      end
    end

    :ok
  end
end
