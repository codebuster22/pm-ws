# pm-ws S8 full-fleet benchmark (fleet-sharded)
host_label: m1, S8 full-fleet, 2026-09-09
generated_at: 2026-09-09T14:13:57Z
uname: Darwin Mihirs-MacBook-Pro-2.local 25.5.0 Darwin Kernel Version 25.5.0: Tue Jun  9 22:26:46 PDT 2026; root:xnu-12377.121.10~1/RELEASE_ARM64_T8103 arm64
commit: 6d1ddad
workdir: /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1
control_socket: /tmp/pmws-bench-5191.sock
fleet_markets: 537
target_shards: 20
markets_per_shard: 27
overflow_shard: 19
overflow_capacity: 3
duplicates_dropped: 0
seconds: 900
lease_ttl_ms: 30000
metrics_port: 9090
rest_calls_total: 1

plan_shards: 537 unique markets (0 duplicate line(s) dropped), markets_per_shard=27, target_shards=20, overflow_capacity=3
plan_shards: 36 fast-recurring slug(s) matched -5-min-/-hourly-/up-or-down
plan_shards: fast-recurring slugs sorted into shard(s) {0, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15, 19} -- daemon.rs sorts `markets` before chunking, so input order cannot place them; this is where they landed, not where anything asked them to land

## commands
cargo build --release --locked
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/pmwsd --config /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/pmwsd.toml
/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/pmwsctl --socket /tmp/pmws-bench-5191.sock status
curl -fsS 127.0.0.1:9090/metrics > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/metrics-<point>.prom
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-0.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 0 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-0.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-0.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-1.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 1 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-1.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-1.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-2.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 2 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-2.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-2.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-3.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 3 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-3.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-3.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-4.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 4 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-4.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-4.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-5.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 5 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-5.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-5.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-6.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 6 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-6.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-6.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-7.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 7 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-7.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-7.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-8.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 8 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-8.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-8.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-9.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 9 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-9.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-9.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-10.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 10 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-10.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-10.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-11.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 11 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-11.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-11.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-12.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 12 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-12.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-12.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-13.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 13 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-13.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-13.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-14.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 14 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-14.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-14.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-15.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 15 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-15.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-15.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-16.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 16 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-16.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-16.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-17.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 17 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-17.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-17.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-18.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 18 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-18.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-18.err &
PMWS_LIB=/Users/0xmihir/Desktop/chain-labs/titus/pm-ws/target/release/libpm_ws.dylib node /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-5191.sock --slugs /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/shard-19.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 19 of 20" > /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-19.log 2> /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/consumer-19.err &
python3 /Users/0xmihir/Desktop/chain-labs/titus/pm-ws/bench/discover_markets.py --page1-only --known /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/markets.txt --known /private/tmp/claude-501/-Users-0xmihir-Desktop-chain-labs-titus-pm-ws/20c9c93f-7ae3-479c-93a3-915b9dd026c4/scratchpad/s8-fleet-m1/run1/discovered-new-slugs.txt

## daemon
start_rss_kib: 1093328
start_attachments_refused: 0
start_shards_connected: 20/20
start_segment_markets_total: 537
start_shard_0_queue_age_us: samples=25 p50=128 p99=298 max=298
start_shard_0_attachments: 0
start_shard_1_queue_age_us: samples=23 p50=256 p99=351 max=351
start_shard_1_attachments: 0
start_shard_2_queue_age_us: samples=44 p50=256 p99=1498 max=1498
start_shard_2_attachments: 0
start_shard_3_queue_age_us: samples=20 p50=256 p99=401 max=401
start_shard_3_attachments: 0
start_shard_4_queue_age_us: samples=5 p50=93 p99=93 max=93
start_shard_4_attachments: 0
start_shard_5_queue_age_us: samples=36 p50=128 p99=372 max=372
start_shard_5_attachments: 0
start_shard_6_queue_age_us: samples=22 p50=512 p99=687 max=687
start_shard_6_attachments: 0
start_shard_7_queue_age_us: samples=12 p50=256 p99=432 max=432
start_shard_7_attachments: 0
start_shard_8_queue_age_us: samples=19 p50=256 p99=340 max=340
start_shard_8_attachments: 0
start_shard_9_queue_age_us: samples=16 p50=128 p99=337 max=337
start_shard_9_attachments: 0
start_shard_10_queue_age_us: samples=25 p50=256 p99=398 max=398
start_shard_10_attachments: 0
start_shard_11_queue_age_us: samples=28 p50=256 p99=519 max=519
start_shard_11_attachments: 0
start_shard_12_queue_age_us: samples=16 p50=256 p99=406 max=406
start_shard_12_attachments: 0
start_shard_13_queue_age_us: samples=16 p50=128 p99=248 max=248
start_shard_13_attachments: 0
start_shard_14_queue_age_us: samples=1 p50=20 p99=20 max=20
start_shard_14_attachments: 0
start_shard_15_queue_age_us: samples=21 p50=512 p99=573 max=573
start_shard_15_attachments: 0
start_shard_16_queue_age_us: samples=13 p50=256 p99=385 max=385
start_shard_16_attachments: 0
start_shard_17_queue_age_us: samples=6 p50=377 p99=377 max=377
start_shard_17_attachments: 0
start_shard_18_queue_age_us: samples=18 p50=256 p99=309 max=309
start_shard_18_attachments: 0
start_shard_19_queue_age_us: samples=20 p50=128 p99=1008 max=1008
start_shard_19_attachments: 0
start_markets_reported: 537
start_markets_leased: 0
start_leases_total: 0
middle_rss_kib: 263040
middle_attachments_refused: 0
middle_shards_connected: 19/20
middle_segment_markets_total: 540
middle_shard_0_queue_age_us: samples=34 p50=128 p99=747 max=747
middle_shard_0_attachments: 27
middle_shard_1_queue_age_us: samples=44 p50=256 p99=470 max=470
middle_shard_1_attachments: 27
middle_shard_2_queue_age_us: samples=2355 p50=128 p99=1024 max=23153
middle_shard_2_attachments: 27
middle_shard_3_queue_age_us: samples=317 p50=256 p99=2048 max=10335
middle_shard_3_attachments: 27
middle_shard_4_queue_age_us: samples=5 p50=93 p99=93 max=93
middle_shard_4_attachments: 27
middle_shard_5_queue_age_us: samples=2584 p50=256 p99=2048 max=5827
middle_shard_5_attachments: 27
middle_shard_6_queue_age_us: samples=483 p50=64 p99=1024 max=5564
middle_shard_6_attachments: 27
middle_shard_7_queue_age_us: samples=50 p50=256 p99=1402 max=1402
middle_shard_7_attachments: 27
middle_shard_8_queue_age_us: samples=38 p50=256 p99=984 max=984
middle_shard_8_attachments: 27
middle_shard_9_queue_age_us: samples=27 p50=128 p99=520 max=520
middle_shard_9_attachments: 27
middle_shard_10_queue_age_us: samples=108 p50=256 p99=512 max=815
middle_shard_10_attachments: 27
middle_shard_11_queue_age_us: samples=509 p50=256 p99=1012 max=1012
middle_shard_11_attachments: 27
middle_shard_12_queue_age_us: samples=34 p50=256 p99=933 max=933
middle_shard_12_attachments: 27
middle_shard_13_queue_age_us: samples=88 p50=256 p99=901 max=901
middle_shard_13_attachments: 27
middle_shard_14_queue_age_us: samples=1226 p50=256 p99=1024 max=21741
middle_shard_14_attachments: 27
middle_shard_15_queue_age_us: samples=107 p50=256 p99=804 max=804
middle_shard_15_attachments: 27
middle_shard_16_queue_age_us: samples=13 p50=256 p99=385 max=385
middle_shard_16_attachments: 27
middle_shard_17_queue_age_us: samples=6 p50=377 p99=377 max=377
middle_shard_17_attachments: 27
middle_shard_18_queue_age_us: samples=18 p50=256 p99=309 max=309
middle_shard_18_attachments: 27
middle_shard_19_queue_age_us: samples=784 p50=512 p99=1024 max=2194
middle_shard_19_attachments: 27
middle_markets_reported: 540
middle_markets_leased: 528
middle_leases_total: 528
end_rss_kib: 94704
end_attachments_refused: 0
end_shards_connected: 19/20
end_segment_markets_total: 537
end_shard_0_queue_age_us: samples=47 p50=256 p99=1824 max=1824
end_shard_0_attachments: 27
end_shard_1_queue_age_us: samples=69 p50=256 p99=5974 max=5974
end_shard_1_attachments: 27
end_shard_2_queue_age_us: samples=4905 p50=128 p99=1024 max=55759
end_shard_2_attachments: 27
end_shard_3_queue_age_us: samples=672 p50=256 p99=2048 max=28744
end_shard_3_attachments: 27
end_shard_4_queue_age_us: samples=6 p50=119 p99=119 max=119
end_shard_4_attachments: 27
end_shard_5_queue_age_us: samples=5181 p50=256 p99=2048 max=55962
end_shard_5_attachments: 27
end_shard_6_queue_age_us: samples=961 p50=64 p99=1024 max=5564
end_shard_6_attachments: 27
end_shard_7_queue_age_us: samples=57 p50=256 p99=1402 max=1402
end_shard_7_attachments: 27
end_shard_8_queue_age_us: samples=58 p50=256 p99=984 max=984
end_shard_8_attachments: 27
end_shard_9_queue_age_us: samples=39 p50=256 p99=1498 max=1498
end_shard_9_attachments: 27
end_shard_10_queue_age_us: samples=318 p50=256 p99=1024 max=7252
end_shard_10_attachments: 27
end_shard_11_queue_age_us: samples=1087 p50=256 p99=1024 max=4012
end_shard_11_attachments: 27
end_shard_12_queue_age_us: samples=64 p50=256 p99=933 max=933
end_shard_12_attachments: 27
end_shard_13_queue_age_us: samples=244 p50=512 p99=1024 max=1365
end_shard_13_attachments: 27
end_shard_14_queue_age_us: samples=2144 p50=256 p99=1024 max=21741
end_shard_14_attachments: 27
end_shard_15_queue_age_us: samples=162 p50=256 p99=1552 max=1552
end_shard_15_attachments: 27
end_shard_16_queue_age_us: samples=13 p50=256 p99=385 max=385
end_shard_16_attachments: 27
end_shard_17_queue_age_us: samples=6 p50=377 p99=377 max=377
end_shard_17_attachments: 27
end_shard_18_queue_age_us: samples=24 p50=256 p99=309 max=309
end_shard_18_attachments: 27
end_shard_19_queue_age_us: samples=930 p50=512 p99=2048 max=2198
end_shard_19_attachments: 27
end_markets_reported: 537
end_markets_leased: 0
end_leases_total: 0

## start-vs-end diff
released_mid_run_count: 0
newly_leased_count: 0

## middle-vs-end diff
released_mid_run_count: 528
  released: 2026-mens-us-open-winner-tennis-1784794788358 shard=0
  released: 2026-womens-us-open-winner-tennis-1784794835561 shard=0
  released: 202627-english-premier-league-winner-1779725958467 shard=0
  released: ac-milan-and-benfica-both-to-score-1788946206239 shard=0
  released: ac-milan-and-benfica-have-3-or-more-total-goals-1788946220053 shard=0
  released: academico-viseu-and-vitoria-sc-both-to-score-1788600626431 shard=0
  released: academico-viseu-and-vitoria-sc-have-3-or-more-total-goals-1788600603498 shard=0
  released: aerospace-and-defense-etf-ita-up-or-down-daily-1788897600 shard=0
  released: alaves-and-valencia-both-to-score-1788859802176 shard=0
  released: alaves-and-valencia-have-3-or-more-total-goals-1788859808400 shard=0
  released: alexander-zverev-vs-botic-van-de-zandschulp-1788843604721 shard=0
  released: alexander-zverev-vs-botic-van-de-zandschulp-37-or-more-total-games-1788843603278 shard=0
  released: alexander-zverev-vs-botic-van-de-zandschulp-4-or-more-total-sets-1788843601714 shard=0
  released: amazon-amzn-up-or-down-daily-1788897600 shard=0
  released: anderlecht-and-lyon-both-to-score-1788946212037 shard=0
  released: anderlecht-and-lyon-have-3-or-more-total-goals-1788946221086 shard=0
  released: anthropic-acquired-before-2027-1764856036744 shard=0
  released: anthropic-ipo-closing-market-cap-middle-brackets-1780392410453 shard=0
  released: anyones-legend-vs-invictus-gaming-1788944403834 shard=0
  released: apple-aapl-up-or-down-daily-1788897600 shard=0
newly_leased_count: 0

## consumer: shard 0 (python)
consumer shard 0 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 0 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.001
anchor_market: 2026-mens-us-open-winner-tennis-1784794788358
markets_leased_peak: 27
markets_held: 27
markets_seen: 6
samples_kept: 20
percentiles: withheld, only 20 kept samples (floor is 1000)
wakes: 22
wakes_per_second: 0.024
timeouts: 8879
dirty_delivered: 21
dirty_delivered_ours: 21
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 66.501
control_stall_max_ms: 8.475
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 44
daemon_percentiles: withheld, only 44 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 20
consumer_percentiles: withheld, only 20 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 1 (typescript)
consumer shard 1 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 1 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16592.132
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.100
anchor_market: ast-spacemobile-bluebird-satellites-in-orbit-above-in-q4-2026-1779377186826
markets_leased_peak: 27
markets_held: 27
markets_seen: 5
samples_kept: 42
percentiles: withheld, only 42 kept samples (floor is 1000)
wakes: 43
wakes_per_second: 0.048
timeouts: 8876
dirty_delivered: 43
dirty_delivered_ours: 43
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 26
control_stall_total_ms: 1.520
control_stall_max_ms: 0.146
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 64
daemon_percentiles: withheld, only 64 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 42
consumer_percentiles: withheld, only 42 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 2 (python)
consumer shard 2 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 2 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.064
anchor_market: betboom-team-vs-astralis-1788901203713
markets_leased_peak: 27
markets_held: 27
markets_seen: 11
samples_kept: 2775
p50_us: 838
p95_us: 2065
p99_us: 5664
p99.9_us: 30317
max_us: 104261
wakes: 2644
wakes_per_second: 2.938
timeouts: 7498
dirty_delivered: 2784
dirty_delivered_ours: 2784
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 30
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 30
control_stall_total_ms: 90.472
control_stall_max_ms: 11.643
resolutions_observed: 4
leases_released_on_resolution: 4
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 2793
daemon_p50_us: 277
daemon_p95_us: 742
daemon_p99_us: 1276
daemon_p99.9_us: 22280
daemon_max_us: 55809
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 2775
consumer_p50_us: 544
consumer_p95_us: 1434
consumer_p99_us: 3063
consumer_p99.9_us: 22256
consumer_max_us: 80998
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 3 (typescript)
consumer shard 3 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 3 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16593.23
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.042
anchor_market: celta-vigo-and-malaga-have-3-or-more-total-goals-1788687012529
markets_leased_peak: 27
markets_held: 27
markets_seen: 6
samples_kept: 644
percentiles: withheld, only 644 kept samples (floor is 1000)
wakes: 648
wakes_per_second: 0.720
timeouts: 8498
dirty_delivered: 647
dirty_delivered_ours: 647
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 2.074
control_stall_max_ms: 0.358
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 662
daemon_percentiles: withheld, only 662 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 644
consumer_percentiles: withheld, only 644 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 4 (python)
consumer shard 4 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 4 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.043
anchor_market: efl-champ-charlton-vs-qpr-1788339609344
markets_leased_peak: 27
markets_held: 27
markets_seen: 0
samples_kept: 0
percentiles: withheld, only 0 kept samples (floor is 1000)
wakes: 1
wakes_per_second: 0.001
timeouts: 8891
dirty_delivered: 0
dirty_delivered_ours: 0
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 26
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 90.936
control_stall_max_ms: 11.717
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 3
daemon_percentiles: withheld, only 3 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 0
consumer_percentiles: withheld, only 0 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 5 (typescript)
consumer shard 5 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 5 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16568.187
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.024
anchor_market: epl-bournemouth-vs-brentford-1788598817234
markets_leased_peak: 27
markets_held: 27
markets_seen: 9
samples_kept: 4822
p50_us: 523
p95_us: 1439
p99_us: 3013
p99.9_us: 38348
max_us: 62928
wakes: 4663
wakes_per_second: 5.181
timeouts: 6724
dirty_delivered: 4838
dirty_delivered_ours: 4838
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 31
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 29
control_stall_total_ms: 3.822
control_stall_max_ms: 0.520
resolutions_observed: 3
leases_released_on_resolution: 3
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 4838
daemon_p50_us: 250
daemon_p95_us: 725
daemon_p99_us: 1635
daemon_p99.9_us: 28675
daemon_max_us: 55984
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 4822
consumer_p50_us: 256
consumer_p95_us: 719
consumer_p99_us: 1597
consumer_p99.9_us: 9619
consumer_max_us: 38829
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 6 (python)
consumer shard 6 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 6 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.058
anchor_market: famalicao-and-sporting-cp-have-3-or-more-total-goals-1788687003291
markets_leased_peak: 27
markets_held: 27
markets_seen: 4
samples_kept: 27
percentiles: withheld, only 27 kept samples (floor is 1000)
wakes: 31
wakes_per_second: 0.034
timeouts: 8873
dirty_delivered: 30
dirty_delivered_ours: 30
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 54.955
control_stall_max_ms: 8.481
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 48
daemon_percentiles: withheld, only 48 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 27
consumer_percentiles: withheld, only 27 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 7 (typescript)
consumer shard 7 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 7 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16585.64
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.026
anchor_market: how-low-will-trumps-approval-rating-go-in-2026-1787750049273
markets_leased_peak: 27
markets_held: 27
markets_seen: 6
samples_kept: 41
percentiles: withheld, only 41 kept samples (floor is 1000)
wakes: 45
wakes_per_second: 0.050
timeouts: 8875
dirty_delivered: 44
dirty_delivered_ours: 44
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 3.211
control_stall_max_ms: 0.367
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 53
daemon_percentiles: withheld, only 53 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 41
consumer_percentiles: withheld, only 41 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 8 (python)
consumer shard 8 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 8 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.030
anchor_market: laliga-levante-vs-athletic-club-1788944409273
markets_leased_peak: 27
markets_held: 27
markets_seen: 5
samples_kept: 37
percentiles: withheld, only 37 kept samples (floor is 1000)
wakes: 39
wakes_per_second: 0.043
timeouts: 8868
dirty_delivered: 38
dirty_delivered_ours: 38
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 76.069
control_stall_max_ms: 6.730
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 55
daemon_percentiles: withheld, only 55 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 37
consumer_percentiles: withheld, only 37 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 9 (typescript)
consumer shard 9 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 9 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16585.569
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.061
anchor_market: ligue-1-2027-champion-1784709773523
markets_leased_peak: 27
markets_held: 27
markets_seen: 6
samples_kept: 21
percentiles: withheld, only 21 kept samples (floor is 1000)
wakes: 23
wakes_per_second: 0.026
timeouts: 8887
dirty_delivered: 22
dirty_delivered_ours: 22
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 26
control_stall_total_ms: 2.178
control_stall_max_ms: 0.186
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 36
daemon_percentiles: withheld, only 36 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 21
consumer_percentiles: withheld, only 21 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 10 (python)
consumer shard 10 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 10 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.038
anchor_market: meta-meta-up-or-down-daily-1788897600
markets_leased_peak: 27
markets_held: 27
markets_seen: 6
samples_kept: 288
percentiles: withheld, only 288 kept samples (floor is 1000)
wakes: 290
wakes_per_second: 0.322
timeouts: 8717
dirty_delivered: 291
dirty_delivered_ours: 291
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 67.170
control_stall_max_ms: 7.519
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 311
daemon_percentiles: withheld, only 311 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 288
consumer_percentiles: withheld, only 288 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 11 (typescript)
consumer shard 11 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 11 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 901
clock_divergence_ns_per_s: 16584.588
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.069
anchor_market: next-senate-majority-leader-1785851933279
markets_leased_peak: 27
markets_held: 27
markets_seen: 10
samples_kept: 1049
p50_us: 479
p95_us: 1323
p99_us: 3727
p99.9_us: 14071
max_us: 14215
wakes: 1014
wakes_per_second: 1.127
timeouts: 8336
dirty_delivered: 1053
dirty_delivered_ours: 1053
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 26
control_stall_total_ms: 2.040
control_stall_max_ms: 0.154
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 1072
daemon_p50_us: 233
daemon_p95_us: 683
daemon_p99_us: 1276
daemon_p99.9_us: 3050
daemon_max_us: 4075
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 1049
consumer_p50_us: 239
consumer_p95_us: 694
consumer_p99_us: 2307
consumer_p99.9_us: 13634
consumer_max_us: 13688
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 12 (python)
consumer shard 12 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 12 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.019
anchor_market: por-pl-benfica-vs-gil-vicente-1788685221283
markets_leased_peak: 27
markets_held: 27
markets_seen: 14
samples_kept: 44
percentiles: withheld, only 44 kept samples (floor is 1000)
wakes: 38
wakes_per_second: 0.042
timeouts: 8867
dirty_delivered: 59
dirty_delivered_ours: 59
rescans: 0
samples_skipped: 14
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 42
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 82.240
control_stall_max_ms: 11.250
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 59
daemon_percentiles: withheld, only 59 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 58
consumer_percentiles: withheld, only 58 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 13 (typescript)
consumer shard 13 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 13 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16575.671
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.092
anchor_market: rennes-and-marseille-both-to-score-1788514204651
markets_leased_peak: 27
markets_held: 27
markets_seen: 4
samples_kept: 226
percentiles: withheld, only 226 kept samples (floor is 1000)
wakes: 228
wakes_per_second: 0.253
timeouts: 8752
dirty_delivered: 227
dirty_delivered_ours: 227
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 26
control_stall_total_ms: 1.966
control_stall_max_ms: 0.171
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 240
daemon_percentiles: withheld, only 240 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 226
consumer_percentiles: withheld, only 226 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 14 (python)
consumer shard 14 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 14 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.036
anchor_market: serie-a-venezia-vs-fiorentina-1788512402738
markets_leased_peak: 27
markets_held: 27
markets_seen: 11
samples_kept: 1192
p50_us: 969
p95_us: 2046
p99_us: 3307
p99.9_us: 24786
max_us: 63253
wakes: 1186
wakes_per_second: 1.318
timeouts: 8173
dirty_delivered: 1198
dirty_delivered_ours: 1198
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 54.616
control_stall_max_ms: 17.220
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 1214
daemon_p50_us: 300
daemon_p95_us: 665
daemon_p99_us: 1000
daemon_p99.9_us: 16261
daemon_max_us: 21912
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 1192
consumer_p50_us: 664
consumer_p95_us: 1428
consumer_p99_us: 2225
consumer_p99.9_us: 15685
consumer_max_us: 62824
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 15 (typescript)
consumer shard 15 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 15 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16584.433
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.053
anchor_market: sunderland-and-arsenal-both-to-score-1788600621464
markets_leased_peak: 27
markets_held: 27
markets_seen: 4
samples_kept: 136
percentiles: withheld, only 136 kept samples (floor is 1000)
wakes: 138
wakes_per_second: 0.153
timeouts: 8820
dirty_delivered: 137
dirty_delivered_ours: 137
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 26
control_stall_total_ms: 1.731
control_stall_max_ms: 0.134
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 149
daemon_percentiles: withheld, only 149 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 136
consumer_percentiles: withheld, only 136 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 16 (python)
consumer shard 16 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 16 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.011
anchor_market: ucl-vfb-stuttgart-vs-viking-1788175384893
markets_leased_peak: 27
markets_held: 27
markets_seen: 0
samples_kept: 0
percentiles: withheld, only 0 kept samples (floor is 1000)
wakes: 0
wakes_per_second: 0.000
timeouts: 8890
dirty_delivered: 0
dirty_delivered_ours: 0
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 26
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 88.961
control_stall_max_ms: 11.818
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 11
daemon_percentiles: withheld, only 11 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 0
consumer_percentiles: withheld, only 0 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 17 (typescript)
consumer shard 17 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 17 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16585.64
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.009
anchor_market: vfb-stuttgart-and-viking-have-3-or-more-total-goals-1788175606930
markets_leased_peak: 27
markets_held: 27
markets_seen: 0
samples_kept: 0
percentiles: withheld, only 0 kept samples (floor is 1000)
wakes: 0
wakes_per_second: 0.000
timeouts: 8901
dirty_delivered: 0
dirty_delivered_ours: 0
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 26
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 26
control_stall_total_ms: 2.700
control_stall_max_ms: 0.195
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 3
daemon_percentiles: withheld, only 3 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 0
consumer_percentiles: withheld, only 0 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 18 (python)
consumer shard 18 (python) exit 0
label: m1, S8 full-fleet, 2026-09-09, python binding consumer, shard 18 of 20
consumer: bench_consumer.py
runtime: python 3.14.5
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.030
anchor_market: wi-04-house-election-winner-1787333939679
markets_leased_peak: 27
markets_held: 27
markets_seen: 1
samples_kept: 4
percentiles: withheld, only 4 kept samples (floor is 1000)
wakes: 6
wakes_per_second: 0.007
timeouts: 8887
dirty_delivered: 5
dirty_delivered_ours: 5
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 26
control_stall_total_ms: 94.276
control_stall_max_ms: 26.768
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 21
daemon_percentiles: withheld, only 21 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 4
consumer_percentiles: withheld, only 4 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 19 (typescript)
consumer shard 19 (typescript) exit 0
label: m1, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 19 of 20
consumer: bench_consumer.ts
runtime: node v22.19.0
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 902
clock_divergence_ns_per_s: 16585.64
clock_steps_detected: 0
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.040
anchor_market: will-stablecoins-hit-dollar500b-before-2027-1767951992467
markets_leased_peak: 26
markets_held: 27
markets_seen: 27
samples_kept: 734
percentiles: withheld, only 734 kept samples (floor is 1000)
wakes: 616
wakes_per_second: 0.684
timeouts: 8568
dirty_delivered: 968
dirty_delivered_ours: 968
rescans: 0
samples_skipped: 207
samples_discarded: 0
samples_discarded_clock_step: 0
samples_after_control: 49
transient_event_faults: 0
continuity_losses: 7932
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 2.603
control_stall_max_ms: 0.633
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 3
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 756
daemon_percentiles: withheld, only 756 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 941
consumer_percentiles: withheld, only 941 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## deviation from ship wording
S8 ship wording says one Python and one TypeScript consumer; a consumer session maps one
shard's segment, so a 20-shard fleet is observed by 10 Python + 10 TypeScript single-segment
consumers, one per shard.
