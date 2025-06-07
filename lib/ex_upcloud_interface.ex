defmodule ExUpcloud.Interface do
  @moduledoc false
  alias ExUpcloud.IpAddress
  alias ExUpcloud.Utils

  @type t :: %__MODULE__{
          type: String.t(),
          ip_addresses: [IpAddress.t()],
          network_uuid: String.t(),
          source_ip_filtering: boolean()
        }

  defstruct [
    :type,
    :ip_addresses,
    :network_uuid,
    :source_ip_filtering
  ]

  def to_payload(%ExUpcloud.Interface{} = interface) do
    Map.reject(
      %{
        type: interface.type,
        ip_addresses: %{ip_address: Enum.map(interface.ip_addresses, &IpAddress.to_payload/1)},
        network: interface.network_uuid,
        source_ip_filtering: Utils.yesno(interface.source_ip_filtering)
      },
      fn {_k, v} -> is_nil(v) end
    )
  end

  def parse(payload) do
    %__MODULE__{
      type: Map.get(payload, "type"),
      ip_addresses:
        payload |> Map.get("ip_addresses", %{}) |> Map.get("ip_address", []) |> Enum.map(&IpAddress.parse/1),
      network_uuid: Map.get(payload, "network"),
      source_ip_filtering: Utils.yesno(Map.get(payload, "source_ip_filtering", false))
    }
  end
end
