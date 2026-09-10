# pm-ws reconnect-time benchmark

host: Apple M1, Darwin 25.5.0 arm64
commit: bb151f4
generated_at: 2026-09-09T11:13:34Z
offered cadence: 5.000 ms (200 updates/s), single market, loopback only

Produced by, from the repository root:

```sh
bench/reconnect_bench.sh bench/reports/reconnect.md
```

Raw per-trial records for every trial below, including failures, are kept at
`reconnect.trials.jsonl` beside this report.

**No venue traffic of any kind.** `examples/table_peer.rs` serves one market on a loopback
socket at the stated cadence; the fault is injected on that same peer process at a
configurable delay after it accepts the connection under test, so the daemon detects and
recovers from a real end of connection (`drop`) or a real missed heartbeat (`stall`),
never a task this script aborts from the outside. The recovery-gap metric is the largest
gap between two consecutive `(revision, observation-time)` rows one consumer process
logs on one clock (`examples/latency_probe.rs --obs-out`); it includes one cadence
interval by construction, which is why the cadence is stated beside every figure.

- **Percentiles are withheld below a stated sample floor**: p50 always prints when at
  least one trial succeeded, p95 needs 40 successful trials, p99 needs 200. `max` is
  always printed from whatever succeeded and is never dressed as a percentile.
- **`stall`'s recovery observably splits into two consecutive elevated gaps**: a
  stale-authority republish at the heartbeat deadline, then the actual post-reconnect
  recovery once backoff, reconnect and resubscribe finish. The headline `max gap`
  column is the single largest of the two, per this script's own metric definition; the
  `elevated span` column beside it sums every gap past 20 cadence intervals in the same
  trial, which is the more complete silence-to-recovery figure for that configuration
  specifically. This was found empirically while building this harness, not assumed.
- **`stall` detection is bounded below by the negotiated heartbeat cadence**
  (`ping_interval_ms + ping_timeout_ms`, the peer's default 2000 ms here), so its gap
  distribution cannot read faster than that floor regardless of trial count.
- **`standby`'s primary-role targeting is verified per trial, not assumed.** The fault is
  armed on the peer's first accepted connection; whether that connection actually held
  the publishing-primary role (rather than the hot standby) is checked against
  `pmws-run`'s own unconditional `connected ... replica=PublishingPrimary
  sid=table-peer-engine-session-1` line. A trial where that check failed faulted the
  standby instead of the primary and is excluded from the gap distribution below,
  reported separately as a role mismatch rather than folded into either count.

| config | fault shape | trials requested / run / succeeded / failed | role mismatches | p50 | p95 | **p99** | max | elevated span p50 / max | cadence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| drop | pmwsd, abrupt drop | 300 / 300 / 300 / 0 | 0 | 1004.1 | 1236.6 | **1253.5** | 1257.6 | 1004.1 / 1257.6 | 5.0 ms |
| stall | pmwsd, silent stall | 30 / 30 / 30 / 0 | 0 | 1020.8 | withheld (30 samples, floor 40) | **withheld (30 samples, floor 200)** | 1253.4 | 2026.3 / 2261.2 | 5.0 ms |
| standby | pmws-run --replicas 2, abrupt drop (single-market rail) | 30 / 30 / 30 / 0 | 0 | 10.0 | withheld (30 samples, floor 40) | **withheld (30 samples, floor 200)** | 18.3 | 0.0 / 0.0 | 5.0 ms |

## What each configuration observed

| config | strictly-increasing violations | fault-fired / reconnected | continuity losses (median per trial) | connection attempts (median per trial) |
| --- | ---: | ---: | ---: | ---: |
| drop | 0 | 300/300 fired, 300/300 reconnected | 1 | 1 |
| stall | 0 | 30/30 fired, 30/30 reconnected | 1 | 1 |
| standby | 0 | 30/30 fired, 30/30 reconnected | 1 | 3 |

Every requested trial ran and completed.
