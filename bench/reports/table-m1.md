# pm-ws S8 integrated table

host: Apple M1, Darwin 25.5.0 arm64
commit: bb151f4
generated_at: 2026-09-09T10:32:59Z

Produced by, from the repository root:

```sh
bench/make_table.sh bench/reports/table-m1.md --workdir /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/table-m1-final
```

Every row is a local run against `examples/table_peer.rs` on a loopback socket. **No venue
traffic of any kind.** The socket-arrival stamps are real WebSocket frame arrivals; the update
cadence is synthetic, which is why each row states the rate it was offered and the rate the
daemon actually ingested.

- **Latency** is socket-arrival -> consumer-observable, in microseconds, measured by
  `examples/latency_probe.rs` attached by descriptor transfer through the control socket. Both
  consumers read the whole segment, so the sampled workload is every market on the shard they
  attached to, not only the market they leased to get there. A parked cell that says
  "ran as spin" is a run whose doorbell could not be parked on and fell back.
- **The two consumers run concurrently, for the same window.** The parked figures are therefore
  measured with a busy-polling consumer resident on the same host, which is the two-consumer
  workload the row states and *not* a parked-alone measurement. A parked-alone number is a
  different run: one consumer, `--mode parked`, nothing else attached.
- **Socket coverage** is connected shards over configured shards. `pmwsd` holds one venue
  connection per shard and no hot standby in this configuration, so replicas per book is 1 and
  the shard count is the socket count. Each row states the shard count it was configured with;
  nothing here caps it.
  The gauge is read at the closing scrape, so the connection attempts started inside the window
  are reported beside it: zero of them is what makes "connected throughout" more than
  "connected at the end".
- **Ingested frames/s** is the `pmws_shard_frames_seen` delta over the measured window, which
  opens once both consumers hold the segment and closes at the final scrape. It counts every
  WebSocket message the shard read, which includes one Engine.IO ping per connection per second.
- **Queue age** is the shard's own ingest-queue age histogram. It is cumulative over the
  daemon's whole life and therefore includes the initial subscription burst, and each of p50,
  p99 and max is the worst value across shards, so the three need not come from one shard.
  Drop, loss and decode counters are deltas across the measured window.
- **RSS** is the daemon's resident set as `ps -o rss=` reports it at the end of the window.
- **Latency percentiles** are nearest-rank over the kept samples; p99 is the figure to cite.
  A p99.99 cell prints `--` below its 20,000-sample floor rather than dressing one or two
  outliers up as a distribution. The queue-age gauge exports p50/p99/max only, so that
  column keeps its own shape.

| markets | offered upd/s (per market / aggregate) | ingested frames/s | depth (levels/side) | consumers | shards connected / configured | parked p50/p95/p99/p99.99 µs | spin p50/p95/p99/p99.99 µs | queue age p50/p99/max µs | overload drops | continuity losses | decode failures | RSS |
| ---: | --- | ---: | ---: | ---: | :---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| 1 | 200 / 200 | 201 | 5 | 2 (1 parked, 1 spin) | 1 / 1 | 46.000 / 76.000 / 105.000 / -- | 33.000 / 46.000 / 74.000 / -- | 32 / 128 / 1078 | 0 | 0 | 0 | 54 MiB |
| 100 | 20 / 2000 | 2001 | 5 | 2 (1 parked, 1 spin) | 1 / 1 | 63.000 / 87.000 / 137.000 / 2674.000 | 56.000 / 73.000 / 114.000 / 1288.000 | 64 / 256 / 3069 | 0 | 0 | 0 | 63 MiB |
| 10000 | 2 / 20000 | 20002 | 5 | 2 (1 parked, 1 spin) | 2 / 2 | 492.000 / 797.000 / 33114.000 / 222181.000 | 484.000 / 787.000 / 33102.000 / 222181.000 | 512 / 16384 / 223585 | 11249 | 21145 | 0 | 433 MiB |

## What each row observed

| markets | probe seconds | counter window s | parked samples / markets seen | spin samples / markets seen | parked wakes/s | spin rescans | snapshots applied | queue-age samples | markets dropped | connection attempts in window |
| ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 60 | 60.0 | 11996 / 1 | 12000 / 1 | 199.936 | 0 | 11998 | 13226 | 0 | 0 |
| 100 | 60 | 59.9 | 120003 / 100 | 120001 / 100 | 1707.949 | 0 | 119878 | 131239 | 0 | 0 |
| 10000 | 60 | 59.9 | 596035 / 5000 | 596033 / 5000 | 8964.647 | 0 | 1187520 | 1298782 | 0 | 0 |

Every requested row ran.


## The configuration each row ran under

### 1 markets

```toml
control_socket = "/tmp/pmws-table-50661.sock"
endpoint = "ws://127.0.0.1:56798/socket.io/?EIO=4&transport=websocket"
metrics_listen = "127.0.0.1:0"
lease_ttl_ms = 30000
markets = [ 1 generated slugs, bench-market-000000 .. bench-market-000000 ]

[delivery]
directory = "/private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/table-m1-final/n1"
profile = "common"
```

peer: `table_peer --rate 200 --depth 5`

### 100 markets

```toml
control_socket = "/tmp/pmws-table-50661.sock"
endpoint = "ws://127.0.0.1:56870/socket.io/?EIO=4&transport=websocket"
metrics_listen = "127.0.0.1:0"
lease_ttl_ms = 30000
markets = [ 100 generated slugs, bench-market-000000 .. bench-market-000099 ]

[delivery]
directory = "/private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/table-m1-final/n100"
profile = "common"
```

peer: `table_peer --rate 20 --depth 5`

### 10000 markets

```toml
control_socket = "/tmp/pmws-table-50661.sock"
endpoint = "ws://127.0.0.1:56922/socket.io/?EIO=4&transport=websocket"
metrics_listen = "127.0.0.1:0"
lease_ttl_ms = 30000
markets_per_shard = 5000
markets = [ 10000 generated slugs, bench-market-000000 .. bench-market-009999 ]

[delivery]
directory = "/private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/table-m1-final/n10000"
profile = "scale"
segment_slots = 6250
```

peer: `table_peer --rate 2 --depth 5`
