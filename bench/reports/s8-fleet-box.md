# pm-ws S8 full-fleet benchmark (fleet-sharded)
host_label: box, S8 full-fleet, 2026-09-09
generated_at: 2026-09-09T11:01:23Z
uname: Linux Encrypted8532 6.6.87.2-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC Thu Jun  5 18:30:46 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
commit: bb151f4
workdir: /home/codebuster22/s8-fleet/run1
control_socket: /tmp/pmws-bench-25954.sock
fleet_markets: 547
target_shards: 20
markets_per_shard: 28
overflow_shard: 19
overflow_capacity: 13
duplicates_dropped: 0
seconds: 900
lease_ttl_ms: 30000
metrics_port: 19090
rest_calls_total: 3

plan_shards: 547 unique markets (0 duplicate line(s) dropped), markets_per_shard=28, target_shards=20, overflow_capacity=13
plan_shards: 35 fast-recurring slug(s) matched -5-min-/-hourly-/up-or-down
plan_shards: fast-recurring slugs sorted into shard(s) {0, 2, 3, 5, 6, 9, 10, 13, 14, 19} -- daemon.rs sorts `markets` before chunking, so input order cannot place them; this is where they landed, not where anything asked them to land

## commands
cargo build --release --locked
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so /home/codebuster22/pm-ws/target/release/pmwsd --config /home/codebuster22/s8-fleet/run1/pmwsd.toml
/home/codebuster22/pm-ws/target/release/pmwsctl --socket /tmp/pmws-bench-25954.sock status
curl -fsS 127.0.0.1:19090/metrics > /home/codebuster22/s8-fleet/run1/metrics-<point>.prom
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-0.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 0 of 20" > /home/codebuster22/s8-fleet/run1/consumer-0.log 2> /home/codebuster22/s8-fleet/run1/consumer-0.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-1.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 1 of 20" > /home/codebuster22/s8-fleet/run1/consumer-1.log 2> /home/codebuster22/s8-fleet/run1/consumer-1.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-2.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 2 of 20" > /home/codebuster22/s8-fleet/run1/consumer-2.log 2> /home/codebuster22/s8-fleet/run1/consumer-2.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-3.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 3 of 20" > /home/codebuster22/s8-fleet/run1/consumer-3.log 2> /home/codebuster22/s8-fleet/run1/consumer-3.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-4.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 4 of 20" > /home/codebuster22/s8-fleet/run1/consumer-4.log 2> /home/codebuster22/s8-fleet/run1/consumer-4.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-5.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 5 of 20" > /home/codebuster22/s8-fleet/run1/consumer-5.log 2> /home/codebuster22/s8-fleet/run1/consumer-5.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-6.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 6 of 20" > /home/codebuster22/s8-fleet/run1/consumer-6.log 2> /home/codebuster22/s8-fleet/run1/consumer-6.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-7.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 7 of 20" > /home/codebuster22/s8-fleet/run1/consumer-7.log 2> /home/codebuster22/s8-fleet/run1/consumer-7.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-8.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 8 of 20" > /home/codebuster22/s8-fleet/run1/consumer-8.log 2> /home/codebuster22/s8-fleet/run1/consumer-8.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-9.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 9 of 20" > /home/codebuster22/s8-fleet/run1/consumer-9.log 2> /home/codebuster22/s8-fleet/run1/consumer-9.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-10.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 10 of 20" > /home/codebuster22/s8-fleet/run1/consumer-10.log 2> /home/codebuster22/s8-fleet/run1/consumer-10.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-11.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 11 of 20" > /home/codebuster22/s8-fleet/run1/consumer-11.log 2> /home/codebuster22/s8-fleet/run1/consumer-11.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-12.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 12 of 20" > /home/codebuster22/s8-fleet/run1/consumer-12.log 2> /home/codebuster22/s8-fleet/run1/consumer-12.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-13.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 13 of 20" > /home/codebuster22/s8-fleet/run1/consumer-13.log 2> /home/codebuster22/s8-fleet/run1/consumer-13.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-14.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 14 of 20" > /home/codebuster22/s8-fleet/run1/consumer-14.log 2> /home/codebuster22/s8-fleet/run1/consumer-14.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-15.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 15 of 20" > /home/codebuster22/s8-fleet/run1/consumer-15.log 2> /home/codebuster22/s8-fleet/run1/consumer-15.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-16.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 16 of 20" > /home/codebuster22/s8-fleet/run1/consumer-16.log 2> /home/codebuster22/s8-fleet/run1/consumer-16.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-17.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 17 of 20" > /home/codebuster22/s8-fleet/run1/consumer-17.log 2> /home/codebuster22/s8-fleet/run1/consumer-17.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so python3 /home/codebuster22/pm-ws/examples/bench_consumer.py --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-18.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, python binding consumer, shard 18 of 20" > /home/codebuster22/s8-fleet/run1/consumer-18.log 2> /home/codebuster22/s8-fleet/run1/consumer-18.err &
PMWS_LIB=/home/codebuster22/pm-ws/target/release/libpm_ws.so node /home/codebuster22/pm-ws/examples/bench_consumer.ts --control /tmp/pmws-bench-25954.sock --slugs /home/codebuster22/s8-fleet/run1/shard-19.slugs --seconds 900 --lease-ttl-ms 30000 --spin-micros 0 --label "box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 19 of 20" > /home/codebuster22/s8-fleet/run1/consumer-19.log 2> /home/codebuster22/s8-fleet/run1/consumer-19.err &
python3 /home/codebuster22/pm-ws/bench/discover_markets.py --page1-only --known /home/codebuster22/s8-fleet/markets.txt --known /home/codebuster22/s8-fleet/run1/discovered-new-slugs.txt

## daemon
start_rss_kib: 1074432
start_attachments_refused: 0
start_shards_connected: 20/20
start_segment_markets_total: 547
start_shard_0_queue_age_us: samples=25 p50=64 p99=73 max=73
start_shard_0_attachments: 0
start_shard_1_queue_age_us: samples=25 p50=64 p99=69 max=69
start_shard_1_attachments: 0
start_shard_2_queue_age_us: samples=89 p50=64 p99=167 max=167
start_shard_2_attachments: 0
start_shard_3_queue_age_us: samples=26 p50=64 p99=78 max=78
start_shard_3_attachments: 0
start_shard_4_queue_age_us: samples=5 p50=32 p99=91 max=91
start_shard_4_attachments: 0
start_shard_5_queue_age_us: samples=14 p50=64 p99=68 max=68
start_shard_5_attachments: 0
start_shard_6_queue_age_us: samples=30 p50=64 p99=64 max=64
start_shard_6_attachments: 0
start_shard_7_queue_age_us: samples=13 p50=32 p99=73 max=73
start_shard_7_attachments: 0
start_shard_8_queue_age_us: samples=19 p50=32 p99=75 max=75
start_shard_8_attachments: 0
start_shard_9_queue_age_us: samples=20 p50=56 p99=56 max=56
start_shard_9_attachments: 0
start_shard_10_queue_age_us: samples=24 p50=64 p99=92 max=92
start_shard_10_attachments: 0
start_shard_11_queue_age_us: samples=21 p50=64 p99=66 max=66
start_shard_11_attachments: 0
start_shard_12_queue_age_us: samples=22 p50=32 p99=64 max=64
start_shard_12_attachments: 0
start_shard_13_queue_age_us: samples=39 p50=32 p99=70 max=70
start_shard_13_attachments: 0
start_shard_14_queue_age_us: samples=25 p50=58 p99=58 max=58
start_shard_14_attachments: 0
start_shard_15_queue_age_us: samples=11 p50=32 p99=69 max=69
start_shard_15_attachments: 0
start_shard_16_queue_age_us: samples=10 p50=64 p99=65 max=65
start_shard_16_attachments: 0
start_shard_17_queue_age_us: samples=6 p50=32 p99=40 max=40
start_shard_17_attachments: 0
start_shard_18_queue_age_us: samples=21 p50=63 p99=63 max=63
start_shard_18_attachments: 0
start_shard_19_queue_age_us: samples=19 p50=64 p99=86 max=86
start_shard_19_attachments: 0
start_markets_reported: 547
start_markets_leased: 0
start_leases_total: 0
middle_rss_kib: 731392
middle_attachments_refused: 0
middle_shards_connected: 20/20
middle_segment_markets_total: 551
middle_shard_0_queue_age_us: samples=136 p50=64 p99=388 max=388
middle_shard_0_attachments: 28
middle_shard_1_queue_age_us: samples=33 p50=64 p99=112 max=112
middle_shard_1_attachments: 28
middle_shard_2_queue_age_us: samples=4640 p50=64 p99=512 max=3885
middle_shard_2_attachments: 28
middle_shard_3_queue_age_us: samples=343 p50=128 p99=512 max=639
middle_shard_3_attachments: 28
middle_shard_4_queue_age_us: samples=5 p50=32 p99=91 max=91
middle_shard_4_attachments: 28
middle_shard_5_queue_age_us: samples=938 p50=128 p99=1024 max=1370
middle_shard_5_attachments: 28
middle_shard_6_queue_age_us: samples=258 p50=64 p99=512 max=581
middle_shard_6_attachments: 28
middle_shard_7_queue_age_us: samples=43 p50=32 p99=98 max=98
middle_shard_7_attachments: 28
middle_shard_8_queue_age_us: samples=19 p50=32 p99=75 max=75
middle_shard_8_attachments: 28
middle_shard_9_queue_age_us: samples=42 p50=64 p99=473 max=473
middle_shard_9_attachments: 28
middle_shard_10_queue_age_us: samples=101 p50=64 p99=474 max=474
middle_shard_10_attachments: 28
middle_shard_11_queue_age_us: samples=38 p50=64 p99=68 max=68
middle_shard_11_attachments: 28
middle_shard_12_queue_age_us: samples=47 p50=64 p99=234 max=234
middle_shard_12_attachments: 28
middle_shard_13_queue_age_us: samples=1885 p50=16 p99=512 max=612
middle_shard_13_attachments: 28
middle_shard_14_queue_age_us: samples=923 p50=64 p99=512 max=1420
middle_shard_14_attachments: 28
middle_shard_15_queue_age_us: samples=676 p50=64 p99=989 max=989
middle_shard_15_attachments: 28
middle_shard_16_queue_age_us: samples=20 p50=64 p99=105 max=105
middle_shard_16_attachments: 28
middle_shard_17_queue_age_us: samples=6 p50=32 p99=40 max=40
middle_shard_17_attachments: 28
middle_shard_18_queue_age_us: samples=23 p50=63 p99=63 max=63
middle_shard_18_attachments: 28
middle_shard_19_queue_age_us: samples=2307 p50=64 p99=512 max=867
middle_shard_19_attachments: 19
middle_markets_reported: 551
middle_markets_leased: 550
middle_leases_total: 550
end_rss_kib: 722136
end_attachments_refused: 0
end_shards_connected: 19/20
end_segment_markets_total: 547
end_shard_0_queue_age_us: samples=164 p50=64 p99=388 max=388
end_shard_0_attachments: 28
end_shard_1_queue_age_us: samples=43 p50=64 p99=112 max=112
end_shard_1_attachments: 28
end_shard_2_queue_age_us: samples=7898 p50=64 p99=512 max=3885
end_shard_2_attachments: 28
end_shard_3_queue_age_us: samples=523 p50=128 p99=512 max=639
end_shard_3_attachments: 28
end_shard_4_queue_age_us: samples=5 p50=32 p99=91 max=91
end_shard_4_attachments: 28
end_shard_5_queue_age_us: samples=1288 p50=128 p99=1024 max=1370
end_shard_5_attachments: 28
end_shard_6_queue_age_us: samples=328 p50=64 p99=512 max=581
end_shard_6_attachments: 28
end_shard_7_queue_age_us: samples=205 p50=64 p99=128 max=170
end_shard_7_attachments: 28
end_shard_8_queue_age_us: samples=19 p50=32 p99=75 max=75
end_shard_8_attachments: 28
end_shard_9_queue_age_us: samples=78 p50=64 p99=473 max=473
end_shard_9_attachments: 28
end_shard_10_queue_age_us: samples=151 p50=64 p99=474 max=474
end_shard_10_attachments: 28
end_shard_11_queue_age_us: samples=67 p50=64 p99=81 max=81
end_shard_11_attachments: 28
end_shard_12_queue_age_us: samples=85 p50=64 p99=234 max=234
end_shard_12_attachments: 28
end_shard_13_queue_age_us: samples=3443 p50=16 p99=256 max=612
end_shard_13_attachments: 28
end_shard_14_queue_age_us: samples=2002 p50=32 p99=512 max=1420
end_shard_14_attachments: 28
end_shard_15_queue_age_us: samples=1083 p50=64 p99=989 max=989
end_shard_15_attachments: 28
end_shard_16_queue_age_us: samples=20 p50=64 p99=105 max=105
end_shard_16_attachments: 28
end_shard_17_queue_age_us: samples=6 p50=32 p99=40 max=40
end_shard_17_attachments: 28
end_shard_18_queue_age_us: samples=28 p50=64 p99=81 max=81
end_shard_18_attachments: 28
end_shard_19_queue_age_us: samples=4333 p50=32 p99=512 max=867
end_shard_19_attachments: 21
end_markets_reported: 547
end_markets_leased: 0
end_leases_total: 0

## start-vs-end diff
released_mid_run_count: 0
newly_leased_count: 0

## middle-vs-end diff
released_mid_run_count: 550
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
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 0 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.020
anchor_market: 2026-mens-us-open-winner-tennis-1784794788358
markets_leased_peak: 28
markets_held: 28
markets_seen: 5
samples_kept: 137
percentiles: withheld, only 137 kept samples (floor is 1000)
wakes: 139
wakes_per_second: 0.154
timeouts: 8890
dirty_delivered: 138
dirty_delivered_ours: 138
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 4.186
control_stall_max_ms: 0.407
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 161
daemon_percentiles: withheld, only 161 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 137
consumer_percentiles: withheld, only 137 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 1 (typescript)
consumer shard 1 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 1 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 5.958
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.024
anchor_market: aston-villa-and-nottingham-forest-both-to-score-1788600620531
markets_leased_peak: 28
markets_held: 28
markets_seen: 2
samples_kept: 15
percentiles: withheld, only 15 kept samples (floor is 1000)
wakes: 18
wakes_per_second: 0.020
timeouts: 8977
dirty_delivered: 17
dirty_delivered_ours: 17
rescans: 0
samples_skipped: 0
samples_discarded: 1
samples_discarded_clock_step: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 1.263
control_stall_max_ms: 0.196
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 39
daemon_percentiles: withheld, only 39 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 15
consumer_percentiles: withheld, only 15 kept samples (floor is 1000)
consumer_samples_discarded: 1
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 2 (python)
consumer shard 2 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 2 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.083
anchor_market: betboom-team-vs-astralis-map-2-winner-1788890700657
markets_leased_peak: 28
markets_held: 28
markets_seen: 9
samples_kept: 5158
p50_us: 273
p95_us: 1119
p99_us: 2092
p99.9_us: 5123
max_us: 9018
wakes: 5017
wakes_per_second: 5.574
timeouts: 6474
dirty_delivered: 5163
dirty_delivered_ours: 5163
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 30
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 177
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 29
control_stall_total_ms: 12.795
control_stall_max_ms: 5.149
resolutions_observed: 2
leases_released_on_resolution: 2
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 5174
daemon_p50_us: 87
daemon_p95_us: 294
daemon_p99_us: 544
daemon_p99.9_us: 1384
daemon_max_us: 4012
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 5158
consumer_p50_us: 181
consumer_p95_us: 757
consumer_p99_us: 1647
consumer_p99.9_us: 4391
consumer_max_us: 8492
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 3 (typescript)
consumer shard 3 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 3 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 0
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.034
anchor_market: celta-vigo-and-malaga-both-to-score-1788687005199
markets_leased_peak: 28
markets_held: 28
markets_seen: 5
samples_kept: 471
percentiles: withheld, only 471 kept samples (floor is 1000)
wakes: 484
wakes_per_second: 0.538
timeouts: 8651
dirty_delivered: 484
dirty_delivered_ours: 484
rescans: 0
samples_skipped: 0
samples_discarded: 5
samples_discarded_clock_step: 5
samples_after_control: 29
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 28
control_stall_total_ms: 1.879
control_stall_max_ms: 0.285
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 500
daemon_percentiles: withheld, only 500 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 471
consumer_percentiles: withheld, only 471 kept samples (floor is 1000)
consumer_samples_discarded: 5
consumer_samples_discarded_clock_step: 5
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 4 (python)
consumer shard 4 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 4 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.003
anchor_market: efl-champ-charlton-vs-qpr-1788339609344
markets_leased_peak: 28
markets_held: 28
markets_seen: 0
samples_kept: 0
percentiles: withheld, only 0 kept samples (floor is 1000)
wakes: 0
wakes_per_second: 0.000
timeouts: 8983
dirty_delivered: 0
dirty_delivered_ours: 0
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 6.126
control_stall_max_ms: 0.906
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
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 5 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 910
clock_divergence_ns_per_s: 0
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.045
anchor_market: epl-chelsea-vs-hull-city-1788598818729
markets_leased_peak: 28
markets_held: 28
markets_seen: 6
samples_kept: 1205
p50_us: 330
p95_us: 1256
p99_us: 2107
p99.9_us: 4486
max_us: 6037
wakes: 1235
wakes_per_second: 1.372
timeouts: 8168
dirty_delivered: 1237
dirty_delivered_ours: 1237
rescans: 0
samples_skipped: 0
samples_discarded: 9
samples_discarded_clock_step: 16
samples_after_control: 30
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 29
control_stall_total_ms: 2.710
control_stall_max_ms: 1.040
resolutions_observed: 2
leases_released_on_resolution: 2
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 1244
daemon_p50_us: 150
daemon_p95_us: 505
daemon_p99_us: 718
daemon_p99.9_us: 1365
daemon_max_us: 1648
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 1205
consumer_p50_us: 176
consumer_p95_us: 726
consumer_p99_us: 1490
consumer_p99.9_us: 3964
consumer_max_us: 5469
consumer_samples_discarded: 9
consumer_samples_discarded_clock_step: 16
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 6 (python)
consumer shard 6 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 6 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.052
anchor_market: fed-decision-in-september-1786349751858
markets_leased_peak: 28
markets_held: 28
markets_seen: 4
samples_kept: 293
percentiles: withheld, only 293 kept samples (floor is 1000)
wakes: 297
wakes_per_second: 0.330
timeouts: 8762
dirty_delivered: 297
dirty_delivered_ours: 297
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 29
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 29
control_stall_total_ms: 3.784
control_stall_max_ms: 0.464
resolutions_observed: 2
leases_released_on_resolution: 2
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 315
daemon_percentiles: withheld, only 315 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 293
consumer_percentiles: withheld, only 293 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 7 (typescript)
consumer shard 7 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 7 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 0
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.053
anchor_market: india-vs-afghanistan-1788703202291
markets_leased_peak: 28
markets_held: 28
markets_seen: 6
samples_kept: 187
percentiles: withheld, only 187 kept samples (floor is 1000)
wakes: 189
wakes_per_second: 0.210
timeouts: 8857
dirty_delivered: 189
dirty_delivered_ours: 189
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_discarded_clock_step: 1
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 1.587
control_stall_max_ms: 0.164
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 199
daemon_percentiles: withheld, only 199 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 187
consumer_percentiles: withheld, only 187 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 1
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 8 (python)
consumer shard 8 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 8 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.081
anchor_market: laliga-osasuna-vs-espanyol-1788598812779
markets_leased_peak: 28
markets_held: 28
markets_seen: 0
samples_kept: 0
percentiles: withheld, only 0 kept samples (floor is 1000)
wakes: 0
wakes_per_second: 0.000
timeouts: 8983
dirty_delivered: 0
dirty_delivered_ours: 0
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 27
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 16.423
control_stall_max_ms: 5.002
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 17
daemon_percentiles: withheld, only 17 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 0
consumer_percentiles: withheld, only 0 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 9 (typescript)
consumer shard 9 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 9 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 0.989
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.029
anchor_market: ligue-1-le-mans-vs-lens-1788685202160
markets_leased_peak: 28
markets_held: 28
markets_seen: 4
samples_kept: 54
percentiles: withheld, only 54 kept samples (floor is 1000)
wakes: 56
wakes_per_second: 0.062
timeouts: 8950
dirty_delivered: 55
dirty_delivered_ours: 55
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
anchor_renewals: 179
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 1.260
control_stall_max_ms: 0.230
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 73
daemon_percentiles: withheld, only 73 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 54
consumer_percentiles: withheld, only 54 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 10 (python)
consumer shard 10 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 10 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.081
anchor_market: mirra-andreeva-vs-cori-gauff-1788829203728
markets_leased_peak: 28
markets_held: 28
markets_seen: 6
samples_kept: 121
percentiles: withheld, only 121 kept samples (floor is 1000)
wakes: 123
wakes_per_second: 0.137
timeouts: 8896
dirty_delivered: 122
dirty_delivered_ours: 122
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 4.726
control_stall_max_ms: 0.446
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 143
daemon_percentiles: withheld, only 143 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 121
consumer_percentiles: withheld, only 121 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 11 (typescript)
consumer shard 11 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 11 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: -1.986
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.066
anchor_market: olympiakos-piraeus-and-jagiellonia-both-to-score-1788946211896
markets_leased_peak: 28
markets_held: 28
markets_seen: 4
samples_kept: 44
percentiles: withheld, only 44 kept samples (floor is 1000)
wakes: 46
wakes_per_second: 0.051
timeouts: 8952
dirty_delivered: 45
dirty_delivered_ours: 45
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
anchor_renewals: 179
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 1.148
control_stall_max_ms: 0.105
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 63
daemon_percentiles: withheld, only 63 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 44
consumer_percentiles: withheld, only 44 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 12 (python)
consumer shard 12 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 12 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.048
anchor_market: por-pl-nacional-vs-alverca-1788598836852
markets_leased_peak: 28
markets_held: 28
markets_seen: 7
samples_kept: 61
percentiles: withheld, only 61 kept samples (floor is 1000)
wakes: 63
wakes_per_second: 0.070
timeouts: 8940
dirty_delivered: 62
dirty_delivered_ours: 62
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 3.920
control_stall_max_ms: 0.357
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 82
daemon_percentiles: withheld, only 82 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 61
consumer_percentiles: withheld, only 61 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 13 (typescript)
consumer shard 13 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 13 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 0
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.054
anchor_market: rio-ave-and-estrela-have-3-or-more-total-goals-1788773400723
markets_leased_peak: 28
markets_held: 28
markets_seen: 3
samples_kept: 738
percentiles: withheld, only 738 kept samples (floor is 1000)
wakes: 760
wakes_per_second: 0.844
timeouts: 8491
dirty_delivered: 758
dirty_delivered_ours: 758
rescans: 0
samples_skipped: 0
samples_discarded: 10
samples_discarded_clock_step: 7
samples_after_control: 29
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 28
control_stall_total_ms: 1.896
control_stall_max_ms: 0.326
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 770
daemon_percentiles: withheld, only 770 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 738
consumer_percentiles: withheld, only 738 kept samples (floor is 1000)
consumer_samples_discarded: 10
consumer_samples_discarded_clock_step: 7
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 14 (python)
consumer shard 14 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 14 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.077
anchor_market: south-korea-annual-inflation-2026-1782140945081
markets_leased_peak: 28
markets_held: 28
markets_seen: 10
samples_kept: 711
percentiles: withheld, only 711 kept samples (floor is 1000)
wakes: 711
wakes_per_second: 0.790
timeouts: 8470
dirty_delivered: 712
dirty_delivered_ours: 712
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
control_stall_total_ms: 10.193
control_stall_max_ms: 2.575
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 734
daemon_percentiles: withheld, only 734 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 711
consumer_percentiles: withheld, only 711 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 15 (typescript)
consumer shard 15 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 15 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 1.984
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.009
anchor_market: theo-fdv-above-dollar700m-one-day-after-launch-1767795159750
markets_leased_peak: 28
markets_held: 28
markets_seen: 4
samples_kept: 1029
p50_us: 212
p95_us: 957
p99_us: 1888
p99.9_us: 4978
max_us: 5628
wakes: 1050
wakes_per_second: 1.167
timeouts: 8310
dirty_delivered: 1065
dirty_delivered_ours: 1065
rescans: 0
samples_skipped: 0
samples_discarded: 24
samples_discarded_clock_step: 7
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 1.037
control_stall_max_ms: 0.126
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 1069
daemon_p50_us: 73
daemon_p95_us: 273
daemon_p99_us: 674
daemon_p99.9_us: 1013
daemon_max_us: 1072
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 1029
consumer_p50_us: 137
consumer_p95_us: 577
consumer_p99_us: 1563
consumer_p99.9_us: 4912
consumer_max_us: 5422
consumer_samples_discarded: 24
consumer_samples_discarded_clock_step: 7
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 16 (python)
consumer shard 16 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 16 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.081
anchor_market: uel-bayer-leverkusen-vs-celje-1788944420530
markets_leased_peak: 28
markets_held: 28
markets_seen: 6
samples_kept: 6
percentiles: withheld, only 6 kept samples (floor is 1000)
wakes: 7
wakes_per_second: 0.008
timeouts: 8980
dirty_delivered: 8
dirty_delivered_ours: 8
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 29
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 12.378
control_stall_max_ms: 3.219
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 16
daemon_percentiles: withheld, only 16 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 6
consumer_percentiles: withheld, only 6 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 17 (typescript)
consumer shard 17 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 17 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: -0.995
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.092
anchor_market: what-price-will-ethereum-hit-september-7-13-1788767219231
markets_leased_peak: 28
markets_held: 28
markets_seen: 0
samples_kept: 0
percentiles: withheld, only 0 kept samples (floor is 1000)
wakes: 0
wakes_per_second: 0.000
timeouts: 8987
dirty_delivered: 0
dirty_delivered_ours: 0
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
anchor_renewals: 179
anchor_renew_failures: 0
control_stall_count: 27
control_stall_total_ms: 1.340
control_stall_max_ms: 0.113
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 4
daemon_percentiles: withheld, only 4 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 0
consumer_percentiles: withheld, only 0 kept samples (floor is 1000)
consumer_samples_discarded: 0
consumer_samples_discarded_clock_step: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 18 (python)
consumer shard 18 (python) exit 0
label: box, S8 full-fleet, 2026-09-09, python binding consumer, shard 18 of 20
consumer: bench_consumer.py
runtime: python 3.12.3
mode: parked
spin_budget_us: 0
clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.022
anchor_market: will-dollarlaptop-flip-dollartrump-by-1788861794134
markets_leased_peak: 28
markets_held: 28
markets_seen: 1
samples_kept: 5
percentiles: withheld, only 5 kept samples (floor is 1000)
wakes: 7
wakes_per_second: 0.008
timeouts: 8979
dirty_delivered: 6
dirty_delivered_ours: 6
rescans: 0
samples_skipped: 0
samples_discarded: 0
samples_after_control: 28
transient_event_faults: 0
continuity_losses: 0
lease_renewals: 0
lease_renew_failures: 0
anchor_renewals: 179
anchor_renew_failures: 0
lease_attach_failures: 0
control_stall_count: 27
control_stall_total_ms: 7.038
control_stall_max_ms: 1.614
resolutions_observed: 0
leases_released_on_resolution: 0
anchor_resolutions_unreleased: 0
slugs_added_midrun: 0
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process (no consumer clock is involved)
daemon_samples_kept: 25
daemon_percentiles: withheld, only 25 kept samples (floor is 1000)
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 5
consumer_percentiles: withheld, only 5 kept samples (floor is 1000)
consumer_samples_discarded: 0
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## consumer: shard 19 (typescript)
consumer shard 19 (typescript) exit 0
label: box, S8 full-fleet, 2026-09-09, typescript binding consumer, shard 19 of 20
consumer: bench_consumer.ts
runtime: node v22.23.2
mode: parked
spin_budget_us: 0
clock: monotonic process.hrtime.bigint plus a millisecond-edge calibrated offset, recalibrated once a second off the measured thread
clock_derivations: 911
clock_divergence_ns_per_s: 0.99
clock_steps_detected: 31
clock_calibrations_rejected: 0
lease_ttl_ms: 30000
renew_interval_ms: 5000
duration_seconds: 900.031
anchor_market: will-trump-acquire-greenland-before-2027-1768930762585
markets_leased_peak: 20
markets_held: 21
markets_seen: 21
samples_kept: 1700
p50_us: 244
p95_us: 712
p99_us: 1683
p99.9_us: 3929
max_us: 4927
wakes: 1721
wakes_per_second: 1.912
timeouts: 8048
dirty_delivered: 1945
dirty_delivered_ours: 1945
rescans: 0
samples_skipped: 162
samples_discarded: 24
samples_discarded_clock_step: 21
samples_after_control: 51
transient_event_faults: 0
continuity_losses: 3140
lease_renewals: 0
lease_renew_failures: 0
lease_attach_failures: 0
anchor_renewals: 178
anchor_renew_failures: 0
control_stall_count: 21
control_stall_total_ms: 3.040
control_stall_max_ms: 0.851
resolutions_observed: 1
leases_released_on_resolution: 1
anchor_resolutions_unreleased: 0
slugs_added_midrun: 6
daemon_latency: commit_time - arrival_time, both stamped by the daemon on one clock in one process -- this consumer's derived clock, and every calibration and step it carries, has nothing to do with it
daemon_samples_kept: 1760
daemon_p50_us: 95
daemon_p95_us: 214
daemon_p99_us: 572
daemon_p99.9_us: 1028
daemon_max_us: 1205
daemon_samples_discarded: 0
consumer_latency: observation - commit_time
consumer_samples_kept: 1862
consumer_p50_us: 150
consumer_p95_us: 652
consumer_p99_us: 1203
consumer_p99.9_us: 3194
consumer_max_us: 3987
consumer_samples_discarded: 24
consumer_samples_discarded_clock_step: 21
end_to_end: observation - arrival_time, reported above as samples_kept and p50_us through max_us

## deviation from ship wording
S8 ship wording says one Python and one TypeScript consumer; a consumer session maps one
shard's segment, so a 20-shard fleet is observed by 10 Python + 10 TypeScript single-segment
consumers, one per shard.
