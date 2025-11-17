defmodule Limiter.Plug do
  @moduledoc """
  Plug that rate-limits per-client (by IP or header)
  using Limiter.TokenBucket
  """

  import Plug.Conn
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    key_fun = Keyword.get(opts, :key, fn c -> Tuple.to_list(c.peer_data.address) end)
    capacity = Keyword.fetch!(opts, :capacity)
    refill = Keyword.fetch!(opts, :refill_per_ms)
    cost = Keyword.get(opts, :cost, 1)

    key = key_fun.(conn)
    :erlang.put(:limiter_current_key, key)

    case Limiter.TokenBucket.check(key, capacity: capacity, refill_per_ms: refill, cost: cost) do
      {:ok, remaining} ->
        put_resp_header(conn, "x-rate-remaining", Integer.to_string(remaining))

      {:error, :rate_limited, retry_in} ->
        conn
        |> put_resp_header("retry-after-ms", Integer.to_string(retry_in))
        |> send_resp(429, "rate limited")
        |> halt()
    end
  end
end
