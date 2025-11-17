defmodule Limiter.TokenBucketTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Limiter.TokenBucket

  setup_all do
    start_supervised!(Limiter.TokenBucket)
    :ok
  end

  setup do
    :ets.delete_all_objects(Limiter.TokenBucket.Table)
    :ok
  end

  test "allows within capacity and blocks beyond it" do
    key = :user_1

    assert {:ok, _} =
             TokenBucket.check(key,
               capacity: 3,
               refill_per_ms: 0.0,
               cost: 1
             )

    assert {:ok, _} =
             TokenBucket.check(key,
               capacity: 3,
               refill_per_ms: 0.0,
               cost: 1
             )

    assert {:ok, 0} =
             TokenBucket.check(key,
               capacity: 3,
               refill_per_ms: 0.0,
               cost: 1
             )

    assert {:error, :rate_limited, _} =
             TokenBucket.check(key,
               capacity: 3,
               refill_per_ms: 0.0,
               cost: 1
             )
  end

  test "refills over time" do
    key = :user_2

    assert {:error, :rate_limited, _} =
             Enum.reduce(1..5, nil, fn _, _ ->
               TokenBucket.check(key,
                 capacity: 2,
                 refill_per_ms: 0.0,
                 cost: 1
               )
             end)

    Process.sleep(20)

    assert {:ok, _} =
             TokenBucket.check(key,
               capacity: 2,
               refill_per_ms: 0.1,
               cost: 1
             )
  end

  property "never return negative remaining" do
    check all(cost <- positive_integer(), capacity <- positive_integer()) do
      key = {:p, cost, capacity}
      _ = TokenBucket.check(key, capacity: capacity, refill_per_ms: 0.0, cost: cost)

      case TokenBucket.check(key, capacity: capacity, refill_per_ms: 0.0, cost: cost) do
        {:ok, remaining} -> assert remaining >= 0
        {:error, :rate_limited, _} -> assert true
      end
    end
  end

  test "concurrency is safe" do
    key = :user_3

    results =
      Task.async_stream(
        1..20,
        fn _ ->
          TokenBucket.check(key, capacity: 5, refill_per_ms: 0.0, cost: 1)
        end,
        max_concurrency: 20,
        timeout: 1_000
      )
      |> Enum.to_list()

    allowed =
      Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

    assert allowed == 5
  end
end
