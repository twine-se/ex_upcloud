defmodule ExUpcloud.Request do
  @moduledoc false

  alias ExUpcloud.Config
  alias Req.Request
  alias Req.Response

  @base_url "https://api.upcloud.com"
  @content_type "application/json"
  @retryable_status_codes [408, 429, 500, 502, 503, 504]

  def get(path, %Config{} = config, opts \\ []) do
    result =
      [url: @base_url <> path, retry: &retry?/2]
      |> config_opts(config, [])
      |> Req.request(opts)

    case result do
      {:ok, %Response{status: status} = response} when status in 200..204 -> {:ok, response}
      {:ok, %Response{} = response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def post(path, body, %Config{} = config, opts \\ []), do: send(:post, path, body, config, opts)
  def post!(path, body, %Config{} = config, opts \\ []), do: send!(:post, path, body, config, opts)
  def put(path, body, %Config{} = config, opts \\ []), do: send(:put, path, body, config, opts)
  def put!(path, body, %Config{} = config, opts \\ []), do: send!(:put, path, body, config, opts)
  def patch(path, body, %Config{} = config, opts \\ []), do: send(:patch, path, body, config, opts)
  def patch!(path, body, %Config{} = config, opts \\ []), do: send!(:patch, path, body, config, opts)
  def delete(path, body, %Config{} = config, opts \\ []), do: send(:delete, path, body, config, opts)
  def delete!(path, body, %Config{} = config, opts \\ []), do: send!(:delete, path, body, config, opts)

  defp send(method, path, body, %Config{} = config, opts) do
    [method: method, url: @base_url <> path, json: body, retry: &retry?/2]
    |> config_opts(config, content_type: @content_type)
    |> Req.request(opts)
  end

  defp send!(method, path, body, %Config{} = config, opts) do
    case send(method, path, body, config, opts) do
      {:ok, response} -> response
      {:error, response} -> raise "Error: #{inspect(response)}"
    end
  end

  defp retry?(_, %Response{status: status}) when status in @retryable_status_codes do
    IO.puts(" ❌ Upcloud API returned #{status}, retrying in 5s...")
    {:delay, Application.get_env(:ex_upcloud, :retry_delay, 5000)}
  end

  defp retry?(%Request{method: :get}, %Req.TransportError{reason: :timeout}),
    do: Application.get_env(:ex_upcloud, :retry_on_timeout, true)

  defp retry?(%Request{method: :get}, %Req.TransportError{reason: :closed}),
    do: Application.get_env(:ex_upcloud, :retry_on_closed, true)

  defp retry?(_, _), do: false

  defp config_opts(opts, %Config{username: username, password: password}, headers) do
    Keyword.put(
      opts,
      :headers,
      Keyword.merge([authorization: "Basic #{Base.encode64("#{username}:#{password}")}"], headers)
    )
  end
end
