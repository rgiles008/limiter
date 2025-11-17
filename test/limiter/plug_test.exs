defmodule Limiter.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Test

  setup_all do
    start_supervised!(Limiter.TokenBucket)
    :ok
  end

  setup do
    :ets.delete_all_objects(Limiter.TokenBucket.Table)
    :ok
  end

  defp call(conn) do
    Limiter.Plug.call(conn,
      capacity: 1,
      refill_per_ms: 0.0,
      cost: 1
    )
  end

  test "passes first request, limits second" do
    conn =
      conn(:get, "/")
      |> Map.put(:peer_data, %{address: {127, 0, 0, 1}})
      |> call()

    assert conn.status in [nil, 200]

    conn2 =
      conn(:get, "/")
      |> Map.put(:peer_data, %{address: {127, 0, 0, 1}})
      |> call()

    assert conn2.halted
    assert conn2.status == 429
  end
end
