defmodule ExUpcloud.Label do
  @moduledoc false
  defstruct [:key, :value]

  def parse(%{"key" => key, "value" => value}) do
    %__MODULE__{key: key, value: value}
  end

  def parse(labels) when is_list(labels) do
    Enum.map(labels, &parse/1)
  end

  def to_payload(%__MODULE__{key: key, value: value}) do
    %{"key" => key, "value" => value}
  end

  def to_payload(labels) when is_list(labels) do
    Enum.map(labels, &to_payload/1)
  end
end
