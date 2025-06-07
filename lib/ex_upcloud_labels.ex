defmodule ExUpcloud.Labels do
  @moduledoc false

  def has_label(%{"labels" => %{"label" => labels}}, key, value) do
    has_label(labels, key, value)
  end

  def has_label(%{"labels" => labels}, key, value) do
    has_label(labels, key, value)
  end

  def has_label(labels, key, value) when is_list(labels) do
    case Enum.find(labels, &(Map.get(&1, "key") == key)) do
      nil -> false
      label -> Map.get(label, "value") == value
    end
  end

  def to_payload(map) do
    Enum.map(map, fn {key, value} ->
      %{"key" => to_string(key), "value" => to_string(value)}
    end)
  end
end
