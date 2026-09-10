#!/bin/sh
# The S8 integrated table: latency distributions, queue age, drop counters and RSS at a
# stated market count, update rate and book depth, on one named host, with the command that
# produced it printed above the table.
#
# This script never talks to a venue. Every row is a deterministic local run: `examples/table_peer.rs`
# binds a loopback port and serves the Limitless `/markets` dialect at a stated rate, `pmwsd`
# ingests it over a real WebSocket, and two `latency_probe` consumers -- one parked, one
# spinning -- attach by descriptor transfer through the daemon's control socket and report
# socket-arrival -> consumer-observable distributions. The arrival stamps are real; the update
# cadence is synthetic, and every row states the rate it was offered alongside the rate the
# daemon actually ingested.
#
# Rows are independent. A row that cannot start, cannot reach its market count, or whose probe
# exits non-zero is recorded as a failure and the remaining rows still run; the failures are
# printed under the table. A row whose probe ran but kept too few samples to report percentiles
# still contributes its row, with the latency cells reading "withheld" and the sample count that
# withheld them. Nothing is ever filled in from a previous run.
#
# Usage:
#   bench/make_table.sh <output.md> [--markets "1 100 10000"] [--rates "200 20 2"]
#                       [--seconds 60] [--warmup 5] [--depth 5] [--shards 0]
#                       [--ready-timeout 120] [--workdir <dir>] [--socket <path>] [--keep]
#
# `--markets` and `--rates` are whitespace-separated lists of the same length: one row each,
# `--rates` giving that row's per-market updates per second. `--seconds` is the measured
# window; a smoke run passes a short one (`--seconds 10`) and the checked-in table uses the
# default.
#
# `--shards` is a TARGET number of shards -- and therefore of venue connections -- for every
# row. The daemon does not cap shard count, so neither does this harness: pass `--shards 20`
# to drive the twenty-connection fleet shape. It is a target rather than an exact count
# because the daemon is configured with `markets_per_shard`: the target picks that, and the
# count the daemon actually runs is the market list divided by it, rounded up. 129 markets at
# a target of 20 is 7 markets a shard and so 19 shards; the harness prints both when they
# differ and waits on the 19. Only a target larger than the market count is refused, since a
# shard with no market connects to nothing. The default, 0, means "let the row choose": one
# shard while the market count fits the common delivery profile, two beyond it, which is what
# the checked-in table was measured with.
#
# The control socket does NOT default into the workdir: a Unix domain socket address carries
# about a hundred bytes and a scratch workdir path alone can exceed that, so it goes under
# /tmp unless `--socket` names somewhere else.
#
# Needs `python3` (metrics scraping, TOML generation, table rendering) and `ps`, both of which
# `pmwsctl status` already depends on.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The invocation, requoted so the line printed above the table is the line that reproduces it.
COMMAND="bench/make_table.sh"
for argument in "$@"; do
    case "$argument" in
        ''|*[!A-Za-z0-9./_=:-]*)
            quoted=$(printf '%s' "$argument" | sed "s/'/'\\\\''/g")
            COMMAND="$COMMAND '$quoted'"
            ;;
        *) COMMAND="$COMMAND $argument" ;;
    esac
done

usage() {
    cat >&2 <<'USAGE'
usage: make_table.sh <output.md> [--markets "1 100 10000"] [--rates "200 20 2"]
                     [--seconds 60] [--warmup 5] [--depth 5] [--shards 0]
                     [--ready-timeout 120] [--workdir <dir>] [--socket <path>] [--keep]
USAGE
    exit 2
}

OUTPUT=""
MARKET_COUNTS="1 100 10000"
RATES="200 20 2"
SECONDS_PER_ROW=60
WARMUP=5
DEPTH=5
SHARDS=0
READY_TIMEOUT=120
WORKDIR=""
SOCKET=""
KEEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --markets) MARKET_COUNTS=${2:?--markets needs a value}; shift 2 ;;
        --rates) RATES=${2:?--rates needs a value}; shift 2 ;;
        --seconds) SECONDS_PER_ROW=${2:?--seconds needs a value}; shift 2 ;;
        --warmup) WARMUP=${2:?--warmup needs a value}; shift 2 ;;
        --depth) DEPTH=${2:?--depth needs a value}; shift 2 ;;
        --shards) SHARDS=${2:?--shards needs a value}; shift 2 ;;
        --ready-timeout) READY_TIMEOUT=${2:?--ready-timeout needs a value}; shift 2 ;;
        --workdir) WORKDIR=${2:?--workdir needs a value}; shift 2 ;;
        --socket) SOCKET=${2:?--socket needs a value}; shift 2 ;;
        --keep) KEEP=1; shift ;;
        -h|--help) usage ;;
        --*) echo "make_table.sh: unrecognized argument: $1" >&2; usage ;;
        *) [ -z "$OUTPUT" ] || { echo "make_table.sh: only one output file" >&2; usage; }
           OUTPUT=$1; shift ;;
    esac
done

[ -n "$OUTPUT" ] || usage
for value in "$SECONDS_PER_ROW" "$WARMUP" "$DEPTH" "$SHARDS" "$READY_TIMEOUT"; do
    case "$value" in
        ''|*[!0-9]*) echo "make_table.sh: --seconds, --warmup, --depth, --shards and --ready-timeout take whole numbers" >&2; exit 2 ;;
    esac
done
[ "$SECONDS_PER_ROW" -ge 1 ] || { echo "make_table.sh: --seconds must be at least 1" >&2; exit 2; }
[ "$DEPTH" -ge 1 ] || { echo "make_table.sh: --depth must be at least 1" >&2; exit 2; }

ROW_COUNT=0
for _n in $MARKET_COUNTS; do ROW_COUNT=$((ROW_COUNT + 1)); done
RATE_COUNT=0
for _r in $RATES; do RATE_COUNT=$((RATE_COUNT + 1)); done
[ "$ROW_COUNT" -eq "$RATE_COUNT" ] || {
    echo "make_table.sh: --markets names $ROW_COUNT row(s) and --rates names $RATE_COUNT; they pair one to one" >&2
    exit 2
}

case "$OUTPUT" in
    /*) ;;
    *) OUTPUT="$PWD/$OUTPUT" ;;
esac

if [ -z "$WORKDIR" ]; then
    WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/pmws-table.XXXXXX")
else
    mkdir -p "$WORKDIR"
    WORKDIR=$(CDPATH= cd -- "$WORKDIR" && pwd)
fi

[ -n "$SOCKET" ] || SOCKET="/tmp/pmws-table-$$.sock"
SOCKET_BYTES=$(printf '%s' "$SOCKET" | wc -c | tr -d ' ')
if [ "$SOCKET_BYTES" -gt 100 ]; then
    echo "make_table.sh: the control socket path is $SOCKET_BYTES bytes and a unix socket address carries 100; pass a shorter --socket" >&2
    exit 2
fi

PEER_PID=""
DAEMON_PID=""
PARKED_PID=""
SPIN_PID=""

kill_quietly() {
    [ -n "$1" ] || return 0
    kill "$1" 2>/dev/null || true
}

teardown_row() {
    kill_quietly "$PARKED_PID"; PARKED_PID=""
    kill_quietly "$SPIN_PID"; SPIN_PID=""
    if [ -n "$DAEMON_PID" ]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        DAEMON_PID=""
    fi
    kill_quietly "$PEER_PID"; PEER_PID=""
    rm -f "$SOCKET" "$SOCKET.lock"
}

cleanup() {
    status=$?
    teardown_row
    if [ "$KEEP" -eq 0 ]; then
        rm -rf "$WORKDIR"
    fi
    return $status
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PMWSD="$REPO/target/release/pmwsd"
PMWSCTL="$REPO/target/release/pmwsctl"
PROBE="$REPO/target/release/examples/latency_probe"
PEER="$REPO/target/release/examples/table_peer"

echo "make_table.sh: building release binaries and examples" >&2
( cd "$REPO" && cargo build --release --locked --bins --examples )
for binary in "$PMWSD" "$PMWSCTL" "$PROBE" "$PEER"; do
    [ -x "$binary" ] || { echo "make_table.sh: $binary was not built" >&2; exit 1; }
done

# The daemon's default markets-per-shard, which is also the largest market set the common
# delivery profile carries on one shard. A row whose per-shard market count is past it takes
# the scale profile, whose shallower declared book depth is what makes the larger count fit
# one segment region.
COMMON_MARKETS_PER_SHARD=128
# The deepest book the scale profile accepts. A row that generates deeper books than its own
# profile accepts would have every snapshot refused and measure nothing.
SCALE_LEVEL_CAPACITY=256

FAILURES="$WORKDIR/failures.txt"
ROWS="$WORKDIR/rows.json"
CONFIGS="$WORKDIR/configs.txt"
: > "$FAILURES"
: > "$ROWS"
: > "$CONFIGS"

fail_row() {
    echo "- **$1 markets** — $2" >> "$FAILURES"
    echo "make_table.sh: row $1 FAILED: $2" >&2
}

# Scrapes the exposition into a file and prints the wall-clock instant it was taken, as
# seconds since the epoch. The instants of two scrapes are what turn counter deltas into rates:
# the probes are separate processes whose start-up is not instantaneous, so the measured window
# is the interval between the scrapes and never the probe's own `--seconds`.
metrics_fetch() {
    python3 - "$1" "$2" <<'PYEOF'
import sys, time, urllib.request
try:
    with urllib.request.urlopen(f"http://{sys.argv[1]}/metrics", timeout=10) as answer:
        body = answer.read().decode("utf-8", "replace")
except Exception as error:
    print(f"metrics fetch failed: {error}", file=sys.stderr)
    raise SystemExit(1)
taken = time.time()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    handle.write(body)
print(f"{taken:.3f}")
PYEOF
}

# Sums one gauge or counter over every shard label in a scraped exposition, or prints the
# maximum when asked for one. Absent series print 0 rather than an empty cell, because a
# daemon that never bound the series is a fact the table should carry as a zero it can explain.
metrics_value() {
    python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
name, how = sys.argv[2], sys.argv[3]
values = []
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        head, _, value = line.rpartition(" ")
        series = head.split("{", 1)[0]
        if series != name:
            continue
        try:
            values.append(float(value))
        except ValueError:
            continue
print(int(sum(values)) if how == "sum" else int(max(values) if values else 0))
PYEOF
}

run_row() {
    markets=$1
    rate=$2
    row_dir="$WORKDIR/n$markets"
    rm -rf "$row_dir"
    mkdir -p "$row_dir"

    # Shard count follows what the run was told to use. Nothing caps it: the daemon sizes its
    # shard count to the configured market list, so a harness that refused to drive more than
    # a couple of connections could not measure the fleet shape the daemon is built for.
    #
    # `--shards` is a TARGET, because the daemon is configured with `markets_per_shard` and
    # derives its shard count from that by the same ceiling division. A target of 20 over 129
    # markets is 7 markets a shard, and 129 markets at 7 a shard is 19 shards, not 20. A
    # harness that waited for 20 would wait forever. So the target picks `per_shard`, and the
    # actual count is recomputed from `per_shard` exactly as the daemon computes it; every
    # wait, override and reported figure below uses the actual count.
    if [ "$SHARDS" -gt 0 ]; then
        target=$SHARDS
    elif [ "$markets" -le "$COMMON_MARKETS_PER_SHARD" ]; then
        target=1
    else
        target=2
    fi
    if [ "$target" -gt "$markets" ]; then
        fail_row "$markets" "--shards $target asks for more shards than there are markets; a shard with no market connects to nothing"
        return 1
    fi
    per_shard=$(( (markets + target - 1) / target ))
    shards=$(( (markets + per_shard - 1) / per_shard ))
    if [ "$shards" -ne "$target" ]; then
        echo "make_table.sh: $markets markets at a target of $target shards is $per_shard markets a shard, so $shards shards is what the daemon will run" >&2
    fi
    if [ "$per_shard" -le "$COMMON_MARKETS_PER_SHARD" ]; then
        profile=common
        slots=0
        if [ "$shards" -eq 1 ]; then
            overrides=""
        else
            overrides="markets_per_shard = $per_shard"
        fi
    else
        profile=scale
        slots=$(( per_shard + per_shard / 4 ))
        overrides="markets_per_shard = $per_shard"
        if [ "$DEPTH" -gt "$SCALE_LEVEL_CAPACITY" ]; then
            fail_row "$markets" "--depth $DEPTH is deeper than the scale profile's level capacity of $SCALE_LEVEL_CAPACITY; every snapshot would be refused"
            return 1
        fi
    fi

    "$PEER" --rate "$rate" --depth "$DEPTH" > "$row_dir/peer.out" 2> "$row_dir/peer.err" &
    PEER_PID=$!
    endpoint=""
    waited=0
    while [ -z "$endpoint" ]; do
        endpoint=$(sed -n 's/^endpoint: //p' "$row_dir/peer.out")
        [ -z "$endpoint" ] || break
        kill -0 "$PEER_PID" 2>/dev/null || { fail_row "$markets" "the peer exited before announcing its endpoint: $(tail -n 2 "$row_dir/peer.err")"; return 1; }
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 10))" ] || { fail_row "$markets" "the peer never announced a bound endpoint within ${READY_TIMEOUT}s: $(tail -n 2 "$row_dir/peer.err")"; return 1; }
        sleep 0.1
    done

    python3 - "$row_dir" "$SOCKET" "$endpoint" "$markets" "$profile" "$overrides" "$slots" <<'PYEOF'
import sys

row_dir, socket, endpoint, markets, profile, overrides, slots = sys.argv[1:8]
slugs = [f"bench-market-{index:06d}" for index in range(int(markets))]

head = [
    f'control_socket = "{socket}"',
    f'endpoint = "{endpoint}"',
    'metrics_listen = "127.0.0.1:0"',
    "lease_ttl_ms = 30000",
]
if overrides:
    head.append(overrides)

tail = ["", "[delivery]", f'directory = "{row_dir}"', f'profile = "{profile}"']
if profile == "scale":
    tail.append(f"segment_slots = {slots}")

listed = ", ".join(f'"{slug}"' for slug in slugs)
with open(f"{row_dir}/pmwsd.toml", "w", encoding="utf-8") as handle:
    handle.write("\n".join(head + [f"markets = [{listed}]"] + tail) + "\n")

redacted = f"markets = [ {len(slugs)} generated slugs, {slugs[0]} .. {slugs[-1]} ]"
with open(f"{row_dir}/pmwsd.display.toml", "w", encoding="utf-8") as handle:
    handle.write("\n".join(head + [redacted] + tail) + "\n")

with open(f"{row_dir}/anchor.txt", "w", encoding="utf-8") as handle:
    handle.write(slugs[0] + "\n")
PYEOF
    anchor=$(cat "$row_dir/anchor.txt")

    rm -f "$SOCKET" "$SOCKET.lock"
    "$PMWSD" --config "$row_dir/pmwsd.toml" > "$row_dir/pmwsd.log" 2>&1 &
    DAEMON_PID=$!

    waited=0
    until "$PMWSCTL" --socket "$SOCKET" status > "$row_dir/status-start.json" 2>/dev/null; do
        kill -0 "$DAEMON_PID" 2>/dev/null || { fail_row "$markets" "pmwsd exited at startup: $(tail -n 2 "$row_dir/pmwsd.log")"; return 1; }
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 5))" ] || { fail_row "$markets" "pmwsd never answered on $SOCKET"; return 1; }
        sleep 0.2
    done

    metrics_address=$(python3 - "$row_dir/status-start.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)
print(status.get("metrics_listen") or "")
PYEOF
)
    [ -n "$metrics_address" ] || { fail_row "$markets" "pmwsd reported no resolved metrics address"; return 1; }
    daemon_pid=$(python3 - "$row_dir/status-start.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle).get("pid", 0))
PYEOF
)

    waited=0
    while : ; do
        kill -0 "$DAEMON_PID" 2>/dev/null || { fail_row "$markets" "pmwsd exited while subscribing: $(tail -n 2 "$row_dir/pmwsd.log")"; return 1; }
        if metrics_fetch "$metrics_address" "$row_dir/metrics-ready.txt" > /dev/null 2>&1; then
            connected=$(metrics_value "$row_dir/metrics-ready.txt" pmws_shard_connected sum)
            published=$(metrics_value "$row_dir/metrics-ready.txt" pmws_shard_segment_markets sum)
            if [ "$connected" -eq "$shards" ] && [ "$published" -ge "$markets" ]; then
                break
            fi
        fi
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 2))" ] || {
            fail_row "$markets" "only ${published:-0} of $markets markets reached the segment on ${connected:-0}/$shards connected shard(s) within ${READY_TIMEOUT}s"
            return 1
        }
        sleep 0.5
    done

    [ "$WARMUP" -eq 0 ] || sleep "$WARMUP"

    label_host=$(host_label)
    "$PROBE" --control "$SOCKET" --market "$anchor" --mode parked --seconds "$SECONDS_PER_ROW" \
        --label "$label_host, table_peer $rate upd/market/s over $markets market(s), depth $DEPTH" \
        > "$row_dir/probe-parked.txt" 2> "$row_dir/probe-parked.err" &
    PARKED_PID=$!
    "$PROBE" --control "$SOCKET" --market "$anchor" --mode spin --seconds "$SECONDS_PER_ROW" \
        --label "$label_host, table_peer $rate upd/market/s over $markets market(s), depth $DEPTH" \
        > "$row_dir/probe-spin.txt" 2> "$row_dir/probe-spin.err" &
    SPIN_PID=$!

    # The window opens once both consumers hold the segment, not when they were spawned: a
    # cold binary's start-up is seconds on a loaded machine, and counting those seconds into the
    # window would report an ingest rate the run never offered.
    waited=0
    while : ; do
        if metrics_fetch "$metrics_address" "$row_dir/metrics-attach.txt" > /dev/null 2>&1; then
            attached=$(metrics_value "$row_dir/metrics-attach.txt" pmws_shard_segment_attachments sum)
            [ "$attached" -lt 2 ] || break
        fi
        kill -0 "$PARKED_PID" 2>/dev/null && kill -0 "$SPIN_PID" 2>/dev/null || break
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 10))" ] || break
        sleep 0.1
    done
    baseline_stamp=$(metrics_fetch "$metrics_address" "$row_dir/metrics-baseline.txt") || { fail_row "$markets" "the baseline metrics scrape failed"; return 1; }

    parked_status=0
    spin_status=0
    wait "$PARKED_PID" || parked_status=$?
    wait "$SPIN_PID" || spin_status=$?
    PARKED_PID=""
    SPIN_PID=""

    final_stamp=$(metrics_fetch "$metrics_address" "$row_dir/metrics-final.txt") || { fail_row "$markets" "the closing metrics scrape failed"; return 1; }
    rss_kib=$(ps -o rss= -p "$daemon_pid" 2>/dev/null | tr -d ' ')
    [ -n "$rss_kib" ] || rss_kib=0

    [ "$parked_status" -eq 0 ] || { fail_row "$markets" "the parked probe exited $parked_status: $(tail -n 2 "$row_dir/probe-parked.err")"; return 1; }
    [ "$spin_status" -eq 0 ] || { fail_row "$markets" "the spin probe exited $spin_status: $(tail -n 2 "$row_dir/probe-spin.err")"; return 1; }

    {
        echo "### $markets markets"
        echo
        echo '```toml'
        cat "$row_dir/pmwsd.display.toml"
        echo '```'
        echo
        echo "peer: \`table_peer --rate $rate --depth $DEPTH\`"
        echo
    } >> "$CONFIGS"

    python3 - "$markets" "$rate" "$DEPTH" "$shards" "$SECONDS_PER_ROW" "$rss_kib" \
        "$row_dir/metrics-baseline.txt" "$row_dir/metrics-final.txt" \
        "$row_dir/probe-parked.txt" "$row_dir/probe-spin.txt" \
        "$baseline_stamp" "$final_stamp" >> "$ROWS" <<'PYEOF'
import json, sys

markets, rate, depth, shards, seconds, rss_kib = (int(value) for value in sys.argv[1:7])
baseline_path, final_path, parked_path, spin_path = sys.argv[7:11]
window = max(float(sys.argv[12]) - float(sys.argv[11]), 0.001)


def series(path):
    found = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            head, _, value = line.rpartition(" ")
            name = head.split("{", 1)[0]
            try:
                found.setdefault(name, []).append(float(value))
            except ValueError:
                continue
    return found


def total(found, name):
    return int(sum(found.get(name, [])))


def peak(found, name):
    values = found.get(name, [])
    return int(max(values)) if values else 0


def report(path):
    fields = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            key, _, value = line.partition(":")
            if value:
                fields[key.strip()] = value.strip()
    return fields


baseline, final = series(baseline_path), series(final_path)
parked, spin = report(parked_path), report(spin_path)

print(json.dumps({
    "markets": markets,
    "rate": rate,
    "depth": depth,
    "shards": shards,
    "seconds": seconds,
    "window": round(window, 3),
    "rss_kib": rss_kib,
    "connected": total(final, "pmws_shard_connected"),
    "frames": total(final, "pmws_shard_frames_seen") - total(baseline, "pmws_shard_frames_seen"),
    "snapshots": total(final, "pmws_shard_snapshots_applied") - total(baseline, "pmws_shard_snapshots_applied"),
    "overload_drops": total(final, "pmws_shard_overload_drops") - total(baseline, "pmws_shard_overload_drops"),
    "continuity_losses": total(final, "pmws_shard_continuity_losses") - total(baseline, "pmws_shard_continuity_losses"),
    "decode_failures": total(final, "pmws_shard_decode_failures") - total(baseline, "pmws_shard_decode_failures"),
    "connection_attempts": total(final, "pmws_shard_connection_attempts") - total(baseline, "pmws_shard_connection_attempts"),
    "markets_dropped": total(final, "pmws_shard_markets_dropped") - total(baseline, "pmws_shard_markets_dropped"),
    "queue_p50": peak(final, "pmws_shard_queue_age_p50_micros"),
    "queue_p99": peak(final, "pmws_shard_queue_age_p99_micros"),
    "queue_max": peak(final, "pmws_shard_queue_age_max_micros"),
    "queue_samples": total(final, "pmws_shard_queue_age_samples"),
    "parked": parked,
    "spin": spin,
}))
PYEOF
    return 0
}

host_label() {
    machine=$(uname -m)
    system=$(uname -s)
    release=$(uname -r)
    chip=""
    if [ "$system" = "Darwin" ]; then
        chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
    elif [ -r /proc/cpuinfo ]; then
        chip=$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -n 1)
    fi
    [ -n "$chip" ] || chip="unknown cpu"
    echo "$chip, $system $release $machine"
}

HOST_LABEL=$(host_label)

index=0
for markets in $MARKET_COUNTS; do
    index=$((index + 1))
    rate=$(echo "$RATES" | awk -v i="$index" '{print $i}')
    echo "make_table.sh: row $markets market(s) at $rate upd/market/s for ${SECONDS_PER_ROW}s" >&2
    run_row "$markets" "$rate" || true
    teardown_row
    rm -rf "$WORKDIR/n$markets"/*.seg
done

python3 - "$OUTPUT" "$HOST_LABEL" "$COMMAND" "$ROWS" "$FAILURES" "$CONFIGS" "$REPO" <<'PYEOF'
import json, subprocess, sys, time

output, host, command, rows_path, failures_path, configs_path, repo = sys.argv[1:8]

rows = []
with open(rows_path, "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

with open(failures_path, "r", encoding="utf-8") as handle:
    failures = handle.read().strip()
with open(configs_path, "r", encoding="utf-8") as handle:
    configs = handle.read().strip()

try:
    commit = subprocess.run(
        ["git", "-C", repo, "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
except Exception:
    commit = "unknown"


def micros(fields, key):
    value = fields.get(key)
    return value if value else "withheld"


def latency(fields):
    if "p50_us" not in fields:
        return f"withheld ({fields.get('samples_kept', '0')} samples)"
    deep = micros(fields, "p99.99_us") if "p99.99_us" in fields else "--"
    return (
        f"{micros(fields, 'p50_us')} / {micros(fields, 'p95_us')}"
        f" / {micros(fields, 'p99_us')} / {deep}"
    )


lines = [
    "# pm-ws S8 integrated table",
    "",
    f"host: {host}",
    f"commit: {commit}",
    f"generated_at: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
    "",
    "Produced by, from the repository root:",
    "",
    "```sh",
    command,
    "```",
    "",
    "Every row is a local run against `examples/table_peer.rs` on a loopback socket. **No venue",
    "traffic of any kind.** The socket-arrival stamps are real WebSocket frame arrivals; the update",
    "cadence is synthetic, which is why each row states the rate it was offered and the rate the",
    "daemon actually ingested.",
    "",
    "- **Latency** is socket-arrival -> consumer-observable, in microseconds, measured by",
    "  `examples/latency_probe.rs` attached by descriptor transfer through the control socket. Both",
    "  consumers read the whole segment, so the sampled workload is every market on the shard they",
    "  attached to, not only the market they leased to get there. A parked cell that says",
    "  \"ran as spin\" is a run whose doorbell could not be parked on and fell back.",
    "- **The two consumers run concurrently, for the same window.** The parked figures are therefore",
    "  measured with a busy-polling consumer resident on the same host, which is the two-consumer",
    "  workload the row states and *not* a parked-alone measurement. A parked-alone number is a",
    "  different run: one consumer, `--mode parked`, nothing else attached.",
    "- **Socket coverage** is connected shards over configured shards. `pmwsd` holds one venue",
    "  connection per shard and no hot standby in this configuration, so replicas per book is 1 and",
    "  the shard count is the socket count. Each row states the shard count it was configured with;",
    "  nothing here caps it.",
    "  The gauge is read at the closing scrape, so the connection attempts started inside the window",
    "  are reported beside it: zero of them is what makes \"connected throughout\" more than",
    "  \"connected at the end\".",
    "- **Ingested frames/s** is the `pmws_shard_frames_seen` delta over the measured window, which",
    "  opens once both consumers hold the segment and closes at the final scrape. It counts every",
    "  WebSocket message the shard read, which includes one Engine.IO ping per connection per second.",
    "- **Queue age** is the shard's own ingest-queue age histogram. It is cumulative over the",
    "  daemon's whole life and therefore includes the initial subscription burst, and each of p50,",
    "  p99 and max is the worst value across shards, so the three need not come from one shard.",
    "  Drop, loss and decode counters are deltas across the measured window.",
    "- **RSS** is the daemon's resident set as `ps -o rss=` reports it at the end of the window.",
    "- **Latency percentiles** are nearest-rank over the kept samples; p99 is the figure to cite.",
    "  A p99.99 cell prints `--` below its 20,000-sample floor rather than dressing one or two",
    "  outliers up as a distribution. The queue-age gauge exports p50/p99/max only, so that",
    "  column keeps its own shape.",
    "",
    "| markets | offered upd/s (per market / aggregate) | ingested frames/s | depth (levels/side) | consumers | shards connected / configured | parked p50/p95/p99/p99.99 µs | spin p50/p95/p99/p99.99 µs | queue age p50/p99/max µs | overload drops | continuity losses | decode failures | RSS |",
    "| ---: | --- | ---: | ---: | ---: | :---: | --- | --- | --- | ---: | ---: | ---: | ---: |",
]

for row in rows:
    parked, spin = row["parked"], row["spin"]
    achieved = row["frames"] / row["window"]
    effective = parked.get("mode_effective")
    parked_cell = latency(parked)
    if effective and effective != "parked":
        parked_cell += f" (ran as {effective})"
    lines.append(
        "| {markets} | {rate} / {aggregate} | {achieved:.0f} | {depth} | 2 (1 parked, 1 spin) | "
        "{connected} / {shards} | {parked} | {spin} | {q50} / {q99} / {qmax} | {drops} | "
        "{losses} | {decode} | {rss} MiB |".format(
            markets=row["markets"],
            rate=row["rate"],
            aggregate=row["rate"] * row["markets"],
            achieved=achieved,
            depth=row["depth"],
            connected=row["connected"],
            shards=row["shards"],
            parked=parked_cell,
            spin=latency(spin),
            q50=row["queue_p50"],
            q99=row["queue_p99"],
            qmax=row["queue_max"],
            drops=row["overload_drops"],
            losses=row["continuity_losses"],
            decode=row["decode_failures"],
            rss=f"{row['rss_kib'] / 1024:.0f}",
        )
    )

lines += ["", "## What each row observed", ""]
lines.append(
    "| markets | probe seconds | counter window s | parked samples / markets seen | "
    "spin samples / markets seen | parked wakes/s | spin rescans | snapshots applied | "
    "queue-age samples | markets dropped | connection attempts in window |"
)
lines.append("| ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for row in rows:
    parked, spin = row["parked"], row["spin"]
    lines.append(
        "| {markets} | {seconds} | {window} | {ps} / {pm} | {ss} / {sm} | {wakes} | {rescans} | "
        "{snapshots} | {qsamples} | {dropped} | {attempts} |".format(
            markets=row["markets"],
            seconds=row["seconds"],
            window=f"{row['window']:.1f}",
            ps=parked.get("samples_kept", "?"),
            pm=parked.get("markets_seen", "?"),
            ss=spin.get("samples_kept", "?"),
            sm=spin.get("markets_seen", "?"),
            wakes=parked.get("wakes_per_second", "?"),
            rescans=spin.get("rescans", "?"),
            snapshots=row["snapshots"],
            qsamples=row["queue_samples"],
            dropped=row["markets_dropped"],
            attempts=row["connection_attempts"],
        )
    )

if failures:
    lines += ["", "## Rows that did not run", "", failures]
else:
    lines += ["", "Every requested row ran.", ""]

if configs:
    lines += ["", "## The configuration each row ran under", "", configs]

with open(output, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines).rstrip() + "\n")
print(f"make_table.sh: table written to {output}", file=sys.stderr)
PYEOF

cat "$OUTPUT"
