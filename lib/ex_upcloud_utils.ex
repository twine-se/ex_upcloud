defmodule ExUpcloud.Utils do
  @moduledoc false
  def yesno(true), do: "yes"
  def yesno(false), do: "no"
  def yesno(nil), do: nil
  def yesno("yes"), do: true
  def yesno("no"), do: false
end
