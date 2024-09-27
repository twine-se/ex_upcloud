defmodule ExUpcloud.Tags do
  @moduledoc false
  import ExUpcloud.Request

  alias ExUpcloud.Config

  def assign_to_server(uuid, tags, %Config{} = config) do
    response =
      post(
        "/1.3/server/#{uuid}/tag/#{Enum.join(tags, ",")}",
        nil,
        config
      )

    case response do
      {:ok, %Req.Response{status: 204, body: body}} ->
        {:ok, Map.get(body, "server")}

      {:error, reason} ->
        raise "Could not assign tags to server: #{inspect(reason)}"
    end
  end

  def has_tag(%{"tags" => %{"tag" => tags}}, tag) when is_list(tags) do
    tag in tags
  end

  def has_tag(_, _), do: false
end
