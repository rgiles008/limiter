# Limiter

An ETS-backed, monotonic-time, token-bucket rate limiter for Elixir, with Plug support and Telemetry events.

## Summary

This project implements a simple, correct, concurrency-safe, highly performant token-bucket limiter using:

- ETS for constant-time hot-path reads/writes,
- Monotonic time for drift-free refill calculations,
- Telemetry events for observability,
- Optional Plug for instantly protecting Phoenix endpoints,
- Property-based tests + concurrency tests validating behavior.

## Architecture/Design Choices

### Why ETS?

ETS is chosen for the hot path because:

- O(1) read/write per check.
- Excellent concurrency — supports true parallel reads/writes when created with read_concurrency: true and write_concurrency: true.
- Process-independent — survives GenServer crashes; consistent behavior across BEAM schedulers.
- Allows storing thousands/millions of buckets without degrading performance.

### Why Monotonic Time

We use:

```elixir
System.monotonic_time(:millisecond)
```

instead of System.system_time/1 because:

- Monotonic clocks never go backwards, even if NTP sync adjusts OS time.
- Ensures refill math can’t produce negative deltas or bursts.
- Prevents systemic failures during Daylight Savings time shifts.
- Provides stable timing during container migration or clock skew.

### Token Bucket Algorithm (Summary)

For each key (user_id, IP, tenant, etc):

- Each check:
  - Computes how many tokens have refilled since the last timestamp.
  - Caps at capacity to control burstiness.
  - Deducts cost tokens.

- Returns:
  - {:ok, remaining} – allowed
  - {:error, :rate_limited, retry_in_ms} – blocked

This design supports:

- Bursts up to capacity
- Predictable refill rate
- Strict fairness under load
