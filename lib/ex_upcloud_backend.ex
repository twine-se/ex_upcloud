defmodule ExUpcloud.Backend do
  @moduledoc false
  defstruct [
    :name,
    :members
  ]

  def parse(payload) do
    %__MODULE__{
      name: Map.get(payload, "name"),
      members:
        payload
        |> Map.get("members", [])
        |> Enum.map(&ExUpcloud.BackendMember.parse/1)
        |> Enum.map(&Map.put(&1, :backend_name, Map.get(payload, "name")))
    }
  end
end
