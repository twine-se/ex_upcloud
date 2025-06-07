defmodule ExUpcloud.IpAddress do
  @moduledoc false
  alias ExUpcloud.Utils

  @type t :: %__MODULE__{
          family: :ipv4 | :ipv6,
          ip_address: String.t(),
          dhcp_provided: boolean()
        }

  defstruct [
    :family,
    :ip_address,
    :dhcp_provided
  ]

  def to_payload(%ExUpcloud.IpAddress{} = ip_address) do
    Map.reject(
      %{
        family: family(ip_address.family),
        address: ip_address.ip_address,
        dhcp_provided: Utils.yesno(ip_address.dhcp_provided)
      },
      fn {_k, v} -> is_nil(v) end
    )
  end

  def parse(payload) do
    %__MODULE__{
      family: family(Map.get(payload, "family", "IPv4")),
      ip_address: Map.get(payload, "address"),
      dhcp_provided: Utils.yesno(Map.get(payload, "dhcp_provided"))
    }
  end

  defp family(:ipv6), do: "IPv6"
  defp family(:ipv4), do: "IPv4"
  defp family("IPv6"), do: :ipv6
  defp family("IPv4"), do: :ipv4
end
