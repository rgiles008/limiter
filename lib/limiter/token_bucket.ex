defmodule Limiter.TokenBucket do
  @moduledoc """
  Per-key token bucket limiter backed by ETS.
  O(1) check/consume, monotonic time based.
  Emits `[:limiter, :token_bucket, :check]` 
  telemetry events
  """
  use GenServer

  @type key :: term()
  @type opts :: [
          capacity: pos_integer(),
          refill_per_ms: number(),
          cost: pos_integer()
        ]

  @table __MODULE__.Table

  @spec start_link(opts) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))

  @doc """
  Returns {:ok, remaining} if allowed; {:error, :rate_limited, retry_in_ms} otherwise.

  Options:
    * capacity: integer >= 1 (max tokens)
    * refill_per_ms: float token/ms
    * cost: integer >= 1
  """

  @spec check(key, opts()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(key, opts) do
    capacity = Keyword.fetch!(opts, :capacity)
    refill = Keyword.fetch!(opts, :refill_per_ms)
    cost = Keyword.get(opts, :cost, 1)
    now = System.monotonic_time(:millisecond)

    {tokens_after, allowed?, retry_in} =
      case :ets.lookup(@table, key) do
        [] ->
          tokens0 = capacity * 1.0
          spend(tokens0, capacity, cost, refill, now)

        [{^key, last_ts, tokens0}] ->
          delta_ms = max(now - last_ts, 0)
          refilled = tokens0 + delta_ms * refill
          tokens1 = min(capacity * 1.0, refilled)
          spend(tokens1, capacity, cost, refill, now)
      end

    :ets.insert(@table, {key, now, tokens_after})

    remaining_int = trunc(max(tokens_after, 0.0))

    :telemetry.execute(
      [:limiter, :token_bucket, :check],
      %{cost: cost, remaining: remaining_int, retry_in: retry_in},
      %{key: key, capacity: capacity, refill_per_ms: refill, allowed?: allowed?}
    )

    if allowed? do
      {:ok, remaining_int}
    else
      {:error, :rate_limited, retry_in}
    end
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table, __MODULE__.Table)
    ensure_table_exists(table)

    {:ok, %{table: table}}
  end

  def ensure_table_exists(table) do
    case :ets.whereis(table) do
      :undefined ->
        ^table =
          :ets.new(table, [
            :named_table,
            :set,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])

        :ok

      _tid ->
        :ok
    end
  end

  defp spend(tokens, _capacity, cost, refill_per_ms, _now) do
    if tokens >= cost do
      {tokens - cost, true, 0}
    else
      needed = cost - tokens

      retry_in_ms =
        cond do
          refill_per_ms <= 0 ->
            86_400_000

          true ->
            (needed / refill_per_ms)
            |> Float.ceil()
            |> trunc()
        end

      {tokens, false, retry_in_ms}
    end
  end
end
