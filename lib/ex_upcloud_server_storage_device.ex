defmodule ExUpcloud.ServerStorageDevice do
  @moduledoc false
  alias ExUpcloud.Labels
  alias ExUpcloud.Utils

  @type t :: %__MODULE__{
          action: :create | :clone | :attach,
          size: integer(),
          uuid: String.t(),
          title: String.t(),
          type: :disk | :cdrom,
          tier: :maxiops | String.t(),
          labels: map(),
          encrypted: boolean()
        }

  defstruct [
    :action,
    :size,
    :uuid,
    :title,
    :type,
    :tier,
    :labels,
    :encrypted
  ]

  def to_payload(%ExUpcloud.ServerStorageDevice{} = device) do
    payload =
      Map.reject(
        %{
          action: device.action,
          size: device.size,
          storage: device.uuid,
          title: device.title,
          type: device.type,
          tier: device.tier,
          encrypted: Utils.yesno(device.encrypted)
        },
        fn {_k, v} -> is_nil(v) end
      )

    case {device.action, device.labels} do
      {:attach, _} ->
        payload

      {_, labels} when map_size(labels) > 0 ->
        Map.put(payload, :labels, Labels.to_payload(labels))

      {_, _} ->
        payload
    end
  end
end
