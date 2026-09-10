#!/bin/sh
# The S8 full-fleet benchmark, fleet-sharded: one `pmwsd` over a market set someone else
# discovered (`--markets`, produced by discover_markets.py), split into `--target-shards`
# shards the way the daemon itself will split it, one consumer process per shard -- Python on
# even shard indices, TypeScript on odd -- and one report naming the machine, the workload,
# and the commands that produced it.
#
# `src/daemon.rs` sorts the configured `markets` list lexicographically before it chunks that
# list into shards (`markets.sort()` precedes `markets.chunks(markets_per_shard)`), and that
# sorted order is exactly what seeds `Router::install`'s per-shard assignment table at
# startup. Config-list order therefore has no influence on which shard a market lands in: this
# script chunks the same sorted list the daemon will, so each `shard-<i>.slugs` file names
# markets the daemon actually co-locates in one segment. A consumer's anchor -- the first line
# of its slug file -- resolves to whatever real shard the daemon assigned that market to; every
# other line in the file must be a market the daemon put in the *same* shard, or leasing it is
# a fatal cross-shard abort.
#
# `markets_per_shard` (`mps`) is chosen with headroom of about one shard's worth of slots
# (`ceil((N + S) / S)`) so that every shard except the last is chunked exactly full and the
# last -- the "overflow" shard -- is the only one with spare capacity. A daemon routes a new
# lease to "the first shard with room" (`src/bin/pmwsd.rs` `plan_add`); with every other shard
# exactly full, that is always the overflow shard, regardless of which markets sorted into it.
# Mid-run new listings are appended to the overflow shard's slug file for this reason, and it
# holds for any market corpus -- but which markets happen to sort into the overflow shard is
# not something this script's input order can steer, so it cannot promise the overflow shard
# holds any particular *kind* of market (e.g. fast-resolving ones); it only detects and reports
# where they landed, in `plan-notes.txt` and the `plan_shards:` lines of the final report.
#
# This script never talks to a venue. The endpoint is a flag with no default (`--endpoint`); a
# run that forgets it is refused rather than pointed at the live venue by the daemon's own
# default. `--dry-run` produces the daemon config, the per-shard slug files, and a
# `planned-commands.txt` naming every command a real run would execute, then exits without
# building, launching, or touching the network.
#
# Usage:
#   bench/run_fleet_bench.sh --workdir <dir> --host-label <text> --seconds <n>
#                            --endpoint <ws-url> --markets <file>
#                            [--target-shards 20] [--metrics-port 9090]
#                            [--poll-interval 300] [--shards-ready-timeout 120]
#                            [--new-slugs <file>] [--socket <path>]
#                            [--lease-ttl-ms 30000] [--spin-micros 0] [--dry-run]
#
# `--markets` is one venue-native market key per line, blanks and `#` comments ignored; it is
# required and this script never discovers markets itself (`discover_markets.py` does).
# `--new-slugs` stays append-only external input, defaulting to `<workdir>/new-slugs.txt`
# (touched into existence if absent) and is optional.
#
# The control socket does NOT default into the workdir: a Unix domain socket address carries
# about a hundred bytes and a scratch workdir path alone can exceed that, so it goes under
# /tmp unless `--socket` names somewhere else. Everything else this run writes stays in the
# workdir.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MAX_SHARD_MARKETS=32768

usage() {
    cat >&2 <<'USAGE'
usage: run_fleet_bench.sh --workdir <dir> --host-label <text> --seconds <n>
                          --endpoint <ws-url> --markets <file>
                          [--target-shards 20] [--metrics-port 9090]
                          [--poll-interval 300] [--shards-ready-timeout 120]
                          [--new-slugs <file>] [--socket <path>]
                          [--lease-ttl-ms 30000] [--spin-micros 0] [--dry-run]
USAGE
    exit 2
}

WORKDIR=""
HOST_LABEL=""
DURATION=""
ENDPOINT=""
MARKETS=""
TARGET_SHARDS=20
METRICS_PORT=9090
POLL_INTERVAL=300
SHARDS_READY_TIMEOUT=120
NEW_SLUGS=""
SOCKET=""
LEASE_TTL_MS=30000
SPIN_MICROS=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --workdir) WORKDIR=${2:?--workdir needs a value}; shift 2 ;;
        --host-label) HOST_LABEL=${2:?--host-label needs a value}; shift 2 ;;
        --seconds) DURATION=${2:?--seconds needs a value}; shift 2 ;;
        --endpoint) ENDPOINT=${2:?--endpoint needs a value}; shift 2 ;;
        --markets) MARKETS=${2:?--markets needs a value}; shift 2 ;;
        --target-shards) TARGET_SHARDS=${2:?--target-shards needs a value}; shift 2 ;;
        --metrics-port) METRICS_PORT=${2:?--metrics-port needs a value}; shift 2 ;;
        --poll-interval) POLL_INTERVAL=${2:?--poll-interval needs a value}; shift 2 ;;
        --shards-ready-timeout) SHARDS_READY_TIMEOUT=${2:?--shards-ready-timeout needs a value}; shift 2 ;;
        --new-slugs) NEW_SLUGS=${2:?--new-slugs needs a value}; shift 2 ;;
        --socket) SOCKET=${2:?--socket needs a value}; shift 2 ;;
        --lease-ttl-ms) LEASE_TTL_MS=${2:?--lease-ttl-ms needs a value}; shift 2 ;;
        --spin-micros) SPIN_MICROS=${2:?--spin-micros needs a value}; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) echo "run_fleet_bench.sh: unrecognized argument: $1" >&2; usage ;;
    esac
done

[ -n "$WORKDIR" ] || usage
[ -n "$HOST_LABEL" ] || usage
[ -n "$DURATION" ] || usage
[ -n "$MARKETS" ] || usage
[ -n "$ENDPOINT" ] || { echo "run_fleet_bench.sh: --endpoint is required; this script never picks a venue for you" >&2; usage; }
case "$DURATION" in
    ''|*[!0-9]*) echo "run_fleet_bench.sh: --seconds must be a whole number of seconds" >&2; exit 2 ;;
esac
case "$TARGET_SHARDS" in
    ''|*[!0-9]*|0) echo "run_fleet_bench.sh: --target-shards must be a positive whole number" >&2; exit 2 ;;
esac
case "$POLL_INTERVAL" in
    ''|*[!0-9]*|0) echo "run_fleet_bench.sh: --poll-interval must be a positive whole number of seconds" >&2; exit 2 ;;
esac
case "$SHARDS_READY_TIMEOUT" in
    ''|*[!0-9]*|0) echo "run_fleet_bench.sh: --shards-ready-timeout must be a positive whole number of seconds" >&2; exit 2 ;;
esac

mkdir -p "$WORKDIR"
WORKDIR=$(CDPATH= cd -- "$WORKDIR" && pwd)
[ -f "$MARKETS" ] || { echo "run_fleet_bench.sh: $MARKETS does not exist; discover_markets.py produces it" >&2; exit 2; }
[ -n "$NEW_SLUGS" ] || NEW_SLUGS="$WORKDIR/new-slugs.txt"
[ -f "$NEW_SLUGS" ] || : > "$NEW_SLUGS"

case "$(uname -s)" in
    Darwin) LIB_NAME=libpm_ws.dylib ;;
    *) LIB_NAME=libpm_ws.so ;;
esac

[ -n "$SOCKET" ] || SOCKET="/tmp/pmws-bench-$$.sock"
SOCKET_BYTES=$(printf '%s' "$SOCKET" | wc -c | tr -d ' ')
if [ "$SOCKET_BYTES" -gt 100 ]; then
    echo "run_fleet_bench.sh: the control socket path is $SOCKET_BYTES bytes and a unix socket address carries 100; pass a shorter --socket" >&2
    exit 2
fi

CONFIG="$WORKDIR/pmwsd.toml"
APPENDED="$WORKDIR/discovered-new-slugs.txt"
PLANNED="$WORKDIR/planned-commands.txt"
REPORT="$WORKDIR/report.txt"
DAEMON_LOG="$WORKDIR/pmwsd.log"
: > "$APPENDED"

DAEMON_PID=""
POLL_PID=""
CONSUMER_PIDS=""
ALL_CONSUMER_PIDS=""

cleanup() {
    status=$?
    if [ -n "$POLL_PID" ]; then kill "$POLL_PID" 2>/dev/null || true; fi
    for pid in $CONSUMER_PIDS; do kill "$pid" 2>/dev/null || true; done
    if [ -n "$DAEMON_PID" ]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -f "$SOCKET" "$SOCKET.lock"
    return $status
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PMWS_LIB="$REPO/target/release/$LIB_NAME"
export PMWS_LIB

# Chunks the same sorted market list `src/daemon.rs` chunks, so a `shard-<i>.slugs` file names
# exactly the markets the daemon co-locates in one real shard; `mps`'s `+ TARGET_SHARDS`
# headroom leaves only the last chunk short of capacity, which is what makes "first shard with
# room" (`plan_add`) always mean the overflow shard at runtime.
python3 - "$MARKETS" "$WORKDIR" "$TARGET_SHARDS" "$MAX_SHARD_MARKETS" <<'PYEOF'
import re
import sys

markets_path, workdir, target_shards_s, max_shard_markets_s = sys.argv[1:5]
shard_count = int(target_shards_s)
max_shard_markets = int(max_shard_markets_s)

with open(markets_path, "r", encoding="utf-8") as handle:
    raw = [
        line.strip()
        for line in handle
        if line.strip() and not line.strip().startswith("#")
    ]

seen = set()
unique = []
for slug in raw:
    if slug not in seen:
        seen.add(slug)
        unique.append(slug)
duplicates = len(raw) - len(unique)
ordered = sorted(unique)
total = len(ordered)
if total == 0:
    print("run_fleet_bench.sh: --markets names 0 slugs after stripping comments/blanks", file=sys.stderr)
    raise SystemExit(2)

low = -(-total // shard_count)
high = -(-(total + shard_count) // shard_count)
mps = next(
    (
        candidate
        for candidate in range(low, high + 1)
        if -(-total // candidate) == shard_count and shard_count * candidate > total
    ),
    None,
)
if mps is None:
    actual_shards = -(-total // low)
    print(
        f"run_fleet_bench.sh: no markets_per_shard in [{low}, {high}] chunks {total} unique "
        f"markets into exactly {shard_count} shard(s) with overflow room; try "
        f"--target-shards {actual_shards}",
        file=sys.stderr,
    )
    raise SystemExit(2)
if mps > max_shard_markets:
    print(
        f"run_fleet_bench.sh: computed markets_per_shard {mps} exceeds the daemon's ceiling "
        f"{max_shard_markets}; raise --target-shards",
        file=sys.stderr,
    )
    raise SystemExit(2)

for shard in range(shard_count):
    chunk = ordered[shard * mps : (shard + 1) * mps]
    with open(f"{workdir}/shard-{shard}.slugs", "w", encoding="utf-8") as handle:
        for slug in chunk:
            handle.write(slug + "\n")

with open(f"{workdir}/markets-toml.txt", "w", encoding="utf-8") as handle:
    handle.write(", ".join(f'"{slug}"' for slug in ordered))

overflow_capacity = shard_count * mps - total
with open(f"{workdir}/shard-plan.env", "w", encoding="utf-8") as handle:
    handle.write(f"PLAN_N={total}\n")
    handle.write(f"PLAN_MPS={mps}\n")
    handle.write(f"PLAN_DUPLICATES={duplicates}\n")
    handle.write(f"PLAN_OVERFLOW_CAPACITY={overflow_capacity}\n")

fast_recurring = re.compile(r"-5-min-|-hourly-|up-or-down")
fast_shards = {index // mps for index, slug in enumerate(ordered) if fast_recurring.search(slug)}
fast_total = sum(1 for slug in ordered if fast_recurring.search(slug))
notes = [
    f"plan_shards: {total} unique markets ({duplicates} duplicate line(s) dropped), "
    f"markets_per_shard={mps}, target_shards={shard_count}, overflow_capacity={overflow_capacity}",
    f"plan_shards: {fast_total} fast-recurring slug(s) matched -5-min-/-hourly-/up-or-down",
]
if fast_shards:
    shard_list = ", ".join(str(s) for s in sorted(fast_shards))
    notes.append(
        f"plan_shards: fast-recurring slugs sorted into shard(s) {{{shard_list}}} -- "
        "daemon.rs sorts `markets` before chunking, so input order cannot place them; this "
        "is where they landed, not where anything asked them to land"
    )
    if (shard_count - 1) not in fast_shards:
        notes.append(
            f"plan_shards: WARNING: no fast-recurring slug sorted into the overflow shard "
            f"{shard_count - 1}; the S8b live leg (one session leases a new listing and "
            "observes a resolution) needs a fast-resolving market in THAT shard specifically, "
            "which this run's input order cannot guarantee -- see report deviation notes"
        )
with open(f"{workdir}/plan-notes.txt", "w", encoding="utf-8") as handle:
    for line in notes:
        handle.write(line + "\n")
        print(line)
PYEOF

# shellcheck disable=SC1090
. "$WORKDIR/shard-plan.env"
N=$PLAN_N
MPS=$PLAN_MPS
DUPLICATES=$PLAN_DUPLICATES
OVERFLOW_CAPACITY=$PLAN_OVERFLOW_CAPACITY
OVERFLOW_SHARD=$((TARGET_SHARDS - 1))
OVERFLOW_FILE="$WORKDIR/shard-$OVERFLOW_SHARD.slugs"
MAX_VENUE_CONNECTIONS=$((2 * TARGET_SHARDS))
MARKETS_TOML=$(cat "$WORKDIR/markets-toml.txt")

cat > "$CONFIG" <<CONFIGEOF
control_socket = "$SOCKET"
endpoint = "$ENDPOINT"
markets = [$MARKETS_TOML]
markets_per_shard = $MPS
max_venue_connections = $MAX_VENUE_CONNECTIONS
metrics_listen = "127.0.0.1:$METRICS_PORT"
lease_ttl_ms = $LEASE_TTL_MS

[delivery]
directory = "$WORKDIR"
CONFIGEOF

: > "$PLANNED"
echo "cargo build --release --locked" >> "$PLANNED"
echo "PMWS_LIB=$PMWS_LIB $REPO/target/release/pmwsd --config $CONFIG" >> "$PLANNED"
echo "$REPO/target/release/pmwsctl --socket $SOCKET status" >> "$PLANNED"
echo "curl -fsS 127.0.0.1:$METRICS_PORT/metrics > $WORKDIR/metrics-<point>.prom" >> "$PLANNED"

i=0
while [ "$i" -lt "$TARGET_SHARDS" ]; do
    SLUGFILE="$WORKDIR/shard-$i.slugs"
    LOGFILE="$WORKDIR/consumer-$i.log"
    ERRFILE="$WORKDIR/consumer-$i.err"
    mod=$((i % 2))
    if [ "$mod" -eq 0 ]; then
        BINDING=python
        LABEL="$HOST_LABEL, python binding consumer, shard $i of $TARGET_SHARDS"
        CMD="PMWS_LIB=$PMWS_LIB python3 $REPO/examples/bench_consumer.py --control $SOCKET --slugs $SLUGFILE --seconds $DURATION --lease-ttl-ms $LEASE_TTL_MS --spin-micros $SPIN_MICROS --label \"$LABEL\""
    else
        BINDING=typescript
        LABEL="$HOST_LABEL, typescript binding consumer, shard $i of $TARGET_SHARDS"
        CMD="PMWS_LIB=$PMWS_LIB node $REPO/examples/bench_consumer.ts --control $SOCKET --slugs $SLUGFILE --seconds $DURATION --lease-ttl-ms $LEASE_TTL_MS --spin-micros $SPIN_MICROS --label \"$LABEL\""
    fi
    echo "$CMD > $LOGFILE 2> $ERRFILE &" >> "$PLANNED"
    i=$((i + 1))
done
echo "python3 $REPO/bench/discover_markets.py --page1-only --known $MARKETS --known $APPENDED" >> "$PLANNED"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "run_fleet_bench.sh: --dry-run: config, $TARGET_SHARDS shard slug file(s) and $PLANNED written under $WORKDIR; nothing built, launched, or sent over the network" >&2
    exit 0
fi

# run_report_tool dispatches one shared python body by mode, so the JSON-reading logic that
# `summarize` and `diff` need is written once.
run_report_tool() {
    python3 - "$@" <<'PYEOF'
import json
import sys


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


mode = sys.argv[1]
if mode == "shard_check":
    status = load(sys.argv[2])
    want = int(sys.argv[3])
    if status is None:
        print("UNAVAILABLE")
    else:
        shards = status.get("shards", [])
        if len(shards) != want:
            print(f"COUNT_MISMATCH {len(shards)}")
        else:
            down = [s.get("shard") for s in shards if not s.get("connected")]
            print("READY" if not down else "DOWN " + ",".join(str(s) for s in down))
elif mode == "summarize":
    status = load(sys.argv[2])
    where = sys.argv[3]
    if status is None:
        print(f"{where}_status: unavailable")
        raise SystemExit(0)
    shards = status.get("shards", [])
    connected = sum(1 for shard in shards if shard.get("connected"))
    print(f"{where}_rss_kib: {status.get('rss_kib')}")
    print(f"{where}_attachments_refused: {status.get('attachments_refused')}")
    print(f"{where}_shards_connected: {connected}/{len(shards)}")
    print(f"{where}_segment_markets_total: {sum(s.get('segment_markets', 0) for s in shards)}")
    for shard in shards:
        age = shard.get("queue_age", {})
        print(
            f"{where}_shard_{shard.get('shard')}_queue_age_us: "
            f"samples={age.get('samples')} p50={age.get('p50_micros')} "
            f"p99={age.get('p99_micros')} max={age.get('max_micros')}"
        )
        print(f"{where}_shard_{shard.get('shard')}_attachments: {shard.get('attachments')}")
    rows = status.get("markets", [])
    leased = [row for row in rows if row.get("leases", 0) > 0]
    print(f"{where}_markets_reported: {len(rows)}")
    print(f"{where}_markets_leased: {len(leased)}")
    print(f"{where}_leases_total: {sum(row.get('leases', 0) for row in rows)}")
elif mode == "diff":
    start = load(sys.argv[2])
    end = load(sys.argv[3])
    if start is None or end is None:
        print("diff: unavailable")
        raise SystemExit(0)
    start_rows = {row["market"]["slug"]: row for row in start.get("markets", [])}
    end_rows = {row["market"]["slug"]: row for row in end.get("markets", [])}
    released = sorted(
        slug
        for slug, row in start_rows.items()
        if row.get("leases", 0) > 0 and end_rows.get(slug, {}).get("leases", 0) == 0
    )
    newly_leased = sorted(set(end_rows) - set(start_rows))
    print(f"released_mid_run_count: {len(released)}")
    for slug in released[:20]:
        print(f"  released: {slug} shard={end_rows.get(slug, start_rows[slug]).get('shard')}")
    print(f"newly_leased_count: {len(newly_leased)}")
    for slug in newly_leased[:20]:
        print(f"  newly_leased: {slug} shard={end_rows[slug].get('shard')}")
PYEOF
}

echo "run_fleet_bench.sh: building release" >&2
( cd "$REPO" && cargo build --release --locked )
[ -f "$PMWS_LIB" ] || { echo "run_fleet_bench.sh: $PMWS_LIB was not built" >&2; exit 1; }

rm -f "$SOCKET"
"$REPO/target/release/pmwsd" --config "$CONFIG" > "$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!

waited=0
until "$REPO/target/release/pmwsctl" --socket "$SOCKET" status > /dev/null 2>&1; do
    waited=$((waited + 1))
    [ "$waited" -lt 200 ] || { echo "run_fleet_bench.sh: pmwsd never answered on $SOCKET" >&2; exit 1; }
    sleep 0.1
done

snapshot() {
    "$REPO/target/release/pmwsctl" --socket "$SOCKET" status > "$WORKDIR/status-$1.json" 2>/dev/null || true
    curl -fsS "127.0.0.1:$METRICS_PORT/metrics" > "$WORKDIR/metrics-$1.prom" 2>/dev/null || true
}

shards_ready_start=$(date +%s)
last_down=""
while :; do
    "$REPO/target/release/pmwsctl" --socket "$SOCKET" status > "$WORKDIR/status-start.json.tmp" 2>/dev/null || true
    result=$(run_report_tool shard_check "$WORKDIR/status-start.json.tmp" "$TARGET_SHARDS")
    case "$result" in
        READY) break ;;
        DOWN*) last_down=${result#DOWN } ;;
        COUNT_MISMATCH*) last_down="shard count ${result#COUNT_MISMATCH }, expected $TARGET_SHARDS" ;;
    esac
    # Elapsed wall-clock time, not loop iterations: a `pmwsctl status` round-trip against a
    # large fleet is not free, so counting iterations would under-report how long this
    # actually waited.
    now=$(date +%s)
    if [ "$((now - shards_ready_start))" -ge "$SHARDS_READY_TIMEOUT" ]; then
        rm -f "$WORKDIR/status-start.json.tmp"
        echo "run_fleet_bench.sh: not all $TARGET_SHARDS shards connected after ${SHARDS_READY_TIMEOUT}s; down/mismatch: $last_down" >&2
        exit 1
    fi
    sleep 1
done
mv "$WORKDIR/status-start.json.tmp" "$WORKDIR/status-start.json"
curl -fsS "127.0.0.1:$METRICS_PORT/metrics" > "$WORKDIR/metrics-start.prom" 2>/dev/null || true

# Consumers launch only here, after the shards-ready gate and the start snapshot: a consumer
# started against a control socket the daemon has not finished standing up dies immediately,
# which is exactly what happened when this loop used to run before `cargo build`/`pmwsd`
# even started. `ALL_CONSUMER_PIDS` is never pruned after this point, unlike `CONSUMER_PIDS`,
# so the final wait below can still name every shard's pid once its consumer has exited.
i=0
while [ "$i" -lt "$TARGET_SHARDS" ]; do
    SLUGFILE="$WORKDIR/shard-$i.slugs"
    LOGFILE="$WORKDIR/consumer-$i.log"
    ERRFILE="$WORKDIR/consumer-$i.err"
    mod=$((i % 2))
    if [ "$mod" -eq 0 ]; then
        BINDING=python
        LABEL="$HOST_LABEL, python binding consumer, shard $i of $TARGET_SHARDS"
        python3 "$REPO/examples/bench_consumer.py" --control "$SOCKET" --slugs "$SLUGFILE" \
            --seconds "$DURATION" --lease-ttl-ms "$LEASE_TTL_MS" --spin-micros "$SPIN_MICROS" \
            --label "$LABEL" > "$LOGFILE" 2>"$ERRFILE" &
    else
        BINDING=typescript
        LABEL="$HOST_LABEL, typescript binding consumer, shard $i of $TARGET_SHARDS"
        node "$REPO/examples/bench_consumer.ts" --control "$SOCKET" --slugs "$SLUGFILE" \
            --seconds "$DURATION" --lease-ttl-ms "$LEASE_TTL_MS" --spin-micros "$SPIN_MICROS" \
            --label "$LABEL" > "$LOGFILE" 2>"$ERRFILE" &
    fi
    pid=$!
    CONSUMER_PIDS="$CONSUMER_PIDS $pid"
    ALL_CONSUMER_PIDS="$ALL_CONSUMER_PIDS $pid:$i:$BINDING"
    i=$((i + 1))
done
run_start=$(date +%s)

poll_loop() {
    new_slugs_cursor=0
    appended_count=0
    discovery_enabled=1
    while kill -0 "$DAEMON_PID" 2>/dev/null; do
        sleep "$POLL_INTERVAL"
        kill -0 "$DAEMON_PID" 2>/dev/null || break
        if [ "$appended_count" -ge "$OVERFLOW_CAPACITY" ]; then
            echo "run_fleet_bench.sh: overflow shard capacity ($OVERFLOW_CAPACITY) reached; poll loop stopping" >> "$WORKDIR/poll.log"
            break
        fi
        if [ -f "$NEW_SLUGS" ]; then
            grep -v '^[[:space:]]*#' "$NEW_SLUGS" 2>/dev/null | grep -v '^[[:space:]]*$' > "$WORKDIR/new-slugs.clean" || : > "$WORKDIR/new-slugs.clean"
            total=$(wc -l < "$WORKDIR/new-slugs.clean" | tr -d ' ')
            if [ "$total" -gt "$new_slugs_cursor" ]; then
                for slug in $(sed -n "$((new_slugs_cursor + 1)),${total}p" "$WORKDIR/new-slugs.clean"); do
                    [ "$appended_count" -lt "$OVERFLOW_CAPACITY" ] || break
                    echo "$slug" >> "$OVERFLOW_FILE"
                    echo "$slug" >> "$APPENDED"
                    appended_count=$((appended_count + 1))
                done
                new_slugs_cursor=$total
            fi
        fi
        # A non-zero exit from discover_markets.py -- including its own 3x429 abort -- is a
        # venue-pushback signal, not a transient hiccup to retry past: REST polling stops for
        # the rest of this run, permanently, while `--new-slugs` draining above and the run
        # itself keep going. Whether to abort the whole run stays the operator's call.
        if [ "$discovery_enabled" -eq 1 ]; then
            if discovered=$(python3 "$REPO/bench/discover_markets.py" --page1-only --known "$MARKETS" --known "$APPENDED" 2>>"$WORKDIR/discover-calls.log"); then
                for slug in $discovered; do
                    [ "$appended_count" -lt "$OVERFLOW_CAPACITY" ] || break
                    echo "$slug" >> "$OVERFLOW_FILE"
                    echo "$slug" >> "$APPENDED"
                    appended_count=$((appended_count + 1))
                done
            else
                pushback_message="run_fleet_bench.sh: VENUE PUSHBACK OR DISCOVERY FAILURE -- REST polling stopped; see discover-calls.log; operator decides whether to abort the run"
                echo "$pushback_message" >> "$WORKDIR/poll.log"
                echo "$pushback_message" >&2
                discovery_enabled=0
            fi
        fi
    done
}
poll_loop &
POLL_PID=$!

midpoint=$((DURATION / 2))
mid_taken=0
while [ -n "$CONSUMER_PIDS" ]; do
    still=""
    for pid in $CONSUMER_PIDS; do
        kill -0 "$pid" 2>/dev/null && still="$still $pid"
    done
    CONSUMER_PIDS="$still"
    # Checked by wall clock, and before the liveness break below, so a run short enough that
    # every consumer has already exited by the first liveness scan still gets its midpoint
    # snapshot rather than skipping straight to `snapshot end`.
    if [ "$mid_taken" -eq 0 ] && [ "$(($(date +%s) - run_start))" -ge "$midpoint" ]; then
        snapshot middle
        mid_taken=1
    fi
    [ -n "$CONSUMER_PIDS" ] || break
    sleep 5
done
# `CONSUMER_PIDS` was pruned to nothing by the liveness loop above; `ALL_CONSUMER_PIDS` never
# is, so this is what still names every shard's pid once its consumer has exited, and lets a
# poison-class abort (BenchError) show up as a recorded non-zero exit rather than a silently
# empty wait.
for entry in $ALL_CONSUMER_PIDS; do
    pid=${entry%%:*}
    rest=${entry#*:}
    shard=${rest%%:*}
    binding=${rest#*:}
    if wait "$pid" 2>/dev/null; then
        code=0
    else
        code=$?
    fi
    echo "$code" > "$WORKDIR/consumer-$shard.exit"
    echo "run_fleet_bench.sh: consumer shard $shard ($binding) exit $code" >&2
done
CONSUMER_PIDS=""

kill "$POLL_PID" 2>/dev/null || true
wait "$POLL_PID" 2>/dev/null || true
POLL_PID=""

snapshot end

REST_CALLS_TOTAL=$(grep -o 'rest_calls: [0-9]*' "$WORKDIR/discover-calls.log" 2>/dev/null | awk -F': ' '{s+=$2} END{print s+0}')

{
    echo "# pm-ws S8 full-fleet benchmark (fleet-sharded)"
    echo "host_label: $HOST_LABEL"
    echo "generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "uname: $(uname -a)"
    echo "commit: $(cd "$REPO" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "workdir: $WORKDIR"
    echo "control_socket: $SOCKET"
    echo "fleet_markets: $N"
    echo "target_shards: $TARGET_SHARDS"
    echo "markets_per_shard: $MPS"
    echo "overflow_shard: $OVERFLOW_SHARD"
    echo "overflow_capacity: $OVERFLOW_CAPACITY"
    echo "duplicates_dropped: $DUPLICATES"
    echo "seconds: $DURATION"
    echo "lease_ttl_ms: $LEASE_TTL_MS"
    echo "metrics_port: $METRICS_PORT"
    echo "rest_calls_total: $REST_CALLS_TOTAL"
    echo
    cat "$WORKDIR/plan-notes.txt"
    echo
    echo "## commands"
    cat "$PLANNED"
    echo
    echo "## daemon"
    run_report_tool summarize "$WORKDIR/status-start.json" start
    run_report_tool summarize "$WORKDIR/status-middle.json" middle
    run_report_tool summarize "$WORKDIR/status-end.json" end
    echo
    echo "## start-vs-end diff"
    run_report_tool diff "$WORKDIR/status-start.json" "$WORKDIR/status-end.json"
    echo
    echo "## middle-vs-end diff"
    run_report_tool diff "$WORKDIR/status-middle.json" "$WORKDIR/status-end.json"
    echo
    i=0
    while [ "$i" -lt "$TARGET_SHARDS" ]; do
        mod=$((i % 2))
        if [ "$mod" -eq 0 ]; then binding=python; else binding=typescript; fi
        exit_code=$(cat "$WORKDIR/consumer-$i.exit" 2>/dev/null || echo unknown)
        echo "## consumer: shard $i ($binding)"
        echo "consumer shard $i ($binding) exit $exit_code"
        if [ -f "$WORKDIR/consumer-$i.log" ]; then
            cat "$WORKDIR/consumer-$i.log"
        else
            echo "(no output captured)"
        fi
        if [ "$exit_code" != "0" ] && [ "$exit_code" != "unknown" ]; then
            echo "### last 20 lines of stderr (consumer-$i.err)"
            tail -n 20 "$WORKDIR/consumer-$i.err" 2>/dev/null || echo "(no stderr captured)"
        fi
        echo
        i=$((i + 1))
    done
    echo "## deviation from ship wording"
    echo "S8 ship wording says one Python and one TypeScript consumer; a consumer session maps one"
    echo "shard's segment, so a 20-shard fleet is observed by 10 Python + 10 TypeScript single-segment"
    echo "consumers, one per shard."
} > "$REPORT"

cat "$REPORT"
echo "run_fleet_bench.sh: report written to $REPORT" >&2
