defmodule ExUpcloud.Storage do
  @moduledoc false
  import ExUpcloud.Request

  alias ExUpcloud.Config
  alias ExUpcloud.Label
  alias ExUpcloud.Labels

  @type t() :: %__MODULE__{
          uuid: String.t(),
          title: String.t(),
          type: String.t(),
          access: String.t(),
          size: integer(),
          state: String.t(),
          tier: String.t(),
          zone: String.t(),
          labels: map(),
          created: DateTime.t(),
          servers: [String.t()]
        }

  defstruct [
    :title,
    :type,
    :access,
    :size,
    :state,
    :uuid,
    :tier,
    :zone,
    :labels,
    :created,
    :servers
  ]

  @list_opts [
    label: [
      type: {:list, {:tuple, [:string, :string]}},
      doc: "Filter servers by label. Can be used multiple times.",
      default: []
    ],
    access: [
      type: {:in, [nil, :public, :private]},
      doc: "Filter servers by access type",
      default: nil
    ],
    type: [
      type: {:in, [nil, :normal, :backup, :cdrom, :template, :favorite]},
      doc: "Filter servers by type (e.g., `normal`, `backup`).",
      default: nil
    ]
  ]

  def list(%Config{} = config, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @list_opts)

    suffix =
      case {opts[:access], opts[:type]} do
        {nil, nil} -> ""
        {access, nil} -> "/#{to_string(access)}"
        {_, type} -> "/#{to_string(type)}"
      end

    filter_labels = Enum.map(opts[:label], &{elem(&1, 0), elem(&1, 1)})

    case get("/1.3/storage" <> suffix, config) do
      {:ok, %Req.Response{body: body}} ->
        storages =
          body
          |> Map.get("storages")
          |> Map.get("storage")
          |> Enum.filter(fn storage ->
            (is_nil(opts[:access]) or Map.get(storage, "access") == to_string(opts[:access])) and
              (is_nil(opts[:type]) or Map.get(storage, "type") == to_string(opts[:type]))
          end)
          |> Enum.filter(fn storage ->
            Enum.all?(
              filter_labels,
              &Labels.has_label(storage, &1 |> elem(0) |> to_string(), &1 |> elem(1) |> to_string())
            )
          end)
          |> Enum.map(&parse/1)

        {:ok, storages}

      other ->
        other
    end
  end

  def find(%Config{} = config, storage_uuid) do
    case get("/1.3/storage/#{storage_uuid}", config) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body |> Map.get("storage") |> parse()}

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def find!(%Config{} = config, storage_uuid) do
    case find(config, storage_uuid) do
      {:ok, storage} ->
        storage

      {:error, reason} ->
        raise "Could not get storage: #{inspect(reason)}"
    end
  end

  def create_template(%Config{} = config, storage_uuid, title) do
    result =
      post(
        "/1.3/storage/#{storage_uuid}/templatize",
        %{
          storage: %{title: title}
        },
        config
      )

    case result do
      {:ok, %Req.Response{status: 201, body: body}} ->
        {:ok, Map.get(body, "storage")}

      {_, reason} ->
        {:error, reason}
    end
  end

  def wait_for_state!(%Config{} = config, storage_uuid, required_state, timeout \\ 180_000) do
    %{state: state} = find!(config, storage_uuid)

    if state != required_state do
      if timeout - 1 <= 0 do
        raise "Storage did not reach state #{required_state} within specified timeout"
      else
        :timer.sleep(1000)
        wait_for_state!(config, storage_uuid, required_state, timeout - 1)
      end
    end

    :ok
  end

  def parse(payload) do
    with {:ok, created, _} <- parse_date(payload["created"]) do
      %__MODULE__{
        uuid: payload["uuid"] || payload["storage"],
        title: payload["title"] || payload["storage_title"],
        type: payload["type"],
        access: payload["access"],
        size: payload["size"] || payload["storage_size"],
        state: payload["state"],
        tier: payload["tier"],
        zone: payload["zone"],
        labels: Label.parse(payload["labels"]),
        created: created,
        servers: payload |> Map.get("servers", %{}) |> Map.get("server", [])
      }
    end
  end

  defp parse_date(nil), do: {:ok, nil, 0}
  defp parse_date(date_str), do: DateTime.from_iso8601(date_str)
end
