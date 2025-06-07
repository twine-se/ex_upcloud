defmodule ExUpcloud.LoadBalancer do
  @moduledoc false
  defstruct [
    :uuid,
    :name,
    :zone,
    :backends
  ]

  def parse(payload) do
    %__MODULE__{
      uuid: Map.get(payload, "uuid"),
      name: Map.get(payload, "name"),
      zone: Map.get(payload, "zone"),
      backends:
        payload
        |> Map.get("backends", [])
        |> Enum.map(&ExUpcloud.Backend.parse/1)
    }
  end

  def get_backend(%__MODULE__{} = load_balancer, backend_name) do
    Enum.find(load_balancer.backends, fn backend -> backend.name == backend_name end)
  end
end
