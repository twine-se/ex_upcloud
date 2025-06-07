defmodule ExUpcloud.BackendMember do
  @moduledoc false

  defstruct [
    :backup,
    :enabled,
    :ip,
    :max_sessions,
    :name,
    :port,
    :type,
    :weight,
    :backend_name
  ]

  def parse(payload) do
    %__MODULE__{
      backup: Map.get(payload, "backup", false),
      enabled: Map.get(payload, "enabled", true),
      ip: Map.get(payload, "ip"),
      max_sessions: Map.get(payload, "max_sessions", 0),
      name: Map.get(payload, "name"),
      port: Map.get(payload, "port", 0),
      type: Map.get(payload, "type", "static"),
      weight: Map.get(payload, "weight", 1)
    }
  end

  def to_payload(%ExUpcloud.BackendMember{} = member) do
    Map.reject(
      %{
        backup: member.backup,
        enabled: member.enabled,
        ip: member.ip,
        max_sessions: member.max_sessions,
        name: member.name,
        port: member.port,
        type: member.type,
        weight: member.weight
      },
      fn {_k, v} -> is_nil(v) end
    )
  end
end
