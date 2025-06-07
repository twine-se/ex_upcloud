defmodule ExUpcloud.Server do
  @moduledoc false

  defstruct [
    :uuid,
    :title,
    :hostname,
    :storage_devices,
    :interfaces,
    :labels,
    :state
  ]

  def parse(payload) do
    %__MODULE__{
      uuid: Map.get(payload, "uuid"),
      title: Map.get(payload, "title"),
      hostname: Map.get(payload, "hostname"),
      state: Map.get(payload, "state"),
      storage_devices:
        payload
        |> Map.get("storage_devices", %{})
        |> Map.get("storage_device", [])
        |> Enum.map(&ExUpcloud.Storage.parse/1),
      interfaces:
        payload
        |> Map.get("networking", %{})
        |> Map.get("interfaces", %{})
        |> Map.get("interface", [])
        |> Enum.map(&ExUpcloud.Interface.parse/1),
      labels:
        payload
        |> Map.get("labels", %{})
        |> Map.get("label", [])
        |> ExUpcloud.Label.parse()
    }
  end

  def get_label(%__MODULE__{} = server, label_key) do
    Enum.find(server.labels, fn label -> label.key == label_key end)
  end

  def get_label_value(%__MODULE__{} = server, label_key) do
    case get_label(server, label_key) do
      nil -> nil
      label -> label.value
    end
  end

  def get_ip_address(%__MODULE__{} = server, network_uuid, family \\ :ipv4) do
    server.interfaces
    |> Enum.find(fn interface -> interface.network_uuid == network_uuid end)
    |> case do
      nil ->
        nil

      interface ->
        Enum.find(interface.ip_addresses, &(&1.family == family))
    end
    |> case do
      nil -> nil
      ip_address -> ip_address.ip_address
    end
  end
end
