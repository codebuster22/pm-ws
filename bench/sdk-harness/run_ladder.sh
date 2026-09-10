#!/usr/bin/env bash
# The S8c comparative ladder: the official Limitless SDKs against pm-ws, side by side on one
# host over an identical pinned market set, at CLOB set sizes 1, 10, 20, 50, 100, 200 and
# all-active. `bench/sdk-harness/README.md` is the authoritative spec -- leg inventory, the
# t_obs boundary, the content digest, the `.obs` format, the leg CLI contract, the market-set
# pinning method and the etiquette this script obeys. This file runs that spec and assembles
# `bench/reports/s8c-<host-label>.md`.
#
# One rung is one (language, size) pair. A rung stands up its own `pmwsd` over the rung's
# pinned set, waits for every shard to connect, then runs that language's legs together for
# the rung's duration: the SDK leg over the whole pinned set, the pm-ws binding/shm leg as one
# consumer per shard (a consumer session maps exactly one shard's segment), and for Rust the
# embedded leg over the whole set in one process. Every leg writes a `.obs` log;
# `match_events.py` then pairs the legs event for event and reports the signed delta.
#
# Shard arithmetic is `bench/run_fleet_bench.sh`'s, for the same reason: `src/daemon.rs` sorts
# the configured `markets` list before it chunks it, so this script chunks that same sorted
# list and each `shard-<i>.slugs` names markets the daemon actually co-locates in one segment.
# `markets_per_shard` is searched so the desired shard count lands exactly with overflow room;
# the search walks the shard count down until one fits, so it never refuses a set size.
#
# Etiquette: REST is used only to pin market sets -- one `discover_markets.py` sweep per
# session plus one page-1 poll per size-1 rung -- and the rolling-hour REST ledger aborts the
# ladder before any hour would exceed 60 calls. A watchdog reads the SDK leg's stderr for
# reconnect churn (>= 3 mentions in 60 s) or any refusal marker (429, rate limit, throttle,
# forbidden) and aborts the ladder on either, marking the report ABORTED-ETIQUETTE and
# assembling whatever rungs completed.
#
# Usage:
#   bench/sdk-harness/run_ladder.sh --host-label <name> --workdir <dir>
#                                   [--sizes "1 10 20 50 100 200 all"]
#                                   [--langs "rust ts py"] [--seconds 600]
#                                   [--all-active-seconds 900] [--metrics-port 9090]
#                                   [--socket <path>] [--endpoint <ws-url>] [--dry-run]
#                                   [--markets <file>] [--shard-size 32] [--max-shards 20]
#                                   [--window 32] [--trim-seconds 10] [--lease-ttl-ms 30000]
#                                   [--spin-micros 0] [--shards-ready-timeout 120]
#                                   [--leg-grace 120]
#
# `--markets <file>` skips the discovery sweep and pins that file as the all-active set; it is
# how a rerun reproduces a session's exact market list without spending REST again.
# `--dry-run` writes the per-rung configs and slug files from placeholder slugs, prints every
# command a real run would execute, runs `match_events.py --self-test`, and touches neither
# the venue nor `bench/reports/`.

set -euo pipefail

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HARNESS="$REPO/bench/sdk-harness"
MAX_SHARD_MARKETS=32768
REST_BUDGET_PER_HOUR=60
SWEEP_REST_ESTIMATE=26
PAGE1_REST_ESTIMATE=2
SIZE1_MAX_SECONDS=240
DEFAULT_ENDPOINT="wss://ws.limitless.exchange/socket.io/?EIO=4&transport=websocket"
BTC_5MIN_PREFIX="btc-up-or-down-5-min-"
WATCHDOG_RECONNECT_THRESHOLD=3
WATCHDOG_WINDOW_SECONDS=60

usage() {
    cat >&2 <<'USAGE'
usage: run_ladder.sh --host-label <name> --workdir <dir>
                     [--sizes "1 10 20 50 100 200 all"] [--langs "rust ts py"]
                     [--seconds 600] [--all-active-seconds 900] [--metrics-port 9090]
                     [--socket <path>] [--endpoint <ws-url>] [--dry-run]
                     [--markets <file>] [--shard-size 32] [--max-shards 20]
                     [--window 32] [--trim-seconds 10] [--lease-ttl-ms 30000]
                     [--spin-micros 0] [--shards-ready-timeout 120] [--leg-grace 120]
USAGE
    exit 2
}

HOST_LABEL=""
WORKDIR=""
SIZES="1 10 20 50 100 200 all"
LANGS="rust ts py"
RUN_SECONDS=600
ALL_ACTIVE_SECONDS=900
METRICS_PORT=9090
SOCKET=""
ENDPOINT="$DEFAULT_ENDPOINT"
ENDPOINT_EXPLICIT=0
DRY_RUN=0
MARKETS_FILE=""
SHARD_SIZE=32
MAX_SHARDS=20
MATCH_WINDOW=32
MATCH_TRIM_SECONDS=10
LEASE_TTL_MS=30000
SPIN_MICROS=0
SHARDS_READY_TIMEOUT=120
LEG_GRACE=120

while [ $# -gt 0 ]; do
    case "$1" in
        --host-label) HOST_LABEL=${2:?--host-label needs a value}; shift 2 ;;
        --workdir) WORKDIR=${2:?--workdir needs a value}; shift 2 ;;
        --sizes) SIZES=${2:?--sizes needs a value}; shift 2 ;;
        --langs) LANGS=${2:?--langs needs a value}; shift 2 ;;
        --seconds) RUN_SECONDS=${2:?--seconds needs a value}; shift 2 ;;
        --all-active-seconds) ALL_ACTIVE_SECONDS=${2:?--all-active-seconds needs a value}; shift 2 ;;
        --metrics-port) METRICS_PORT=${2:?--metrics-port needs a value}; shift 2 ;;
        --socket) SOCKET=${2:?--socket needs a value}; shift 2 ;;
        --endpoint) ENDPOINT=${2:?--endpoint needs a value}; ENDPOINT_EXPLICIT=1; shift 2 ;;
        --markets) MARKETS_FILE=${2:?--markets needs a value}; shift 2 ;;
        --shard-size) SHARD_SIZE=${2:?--shard-size needs a value}; shift 2 ;;
        --max-shards) MAX_SHARDS=${2:?--max-shards needs a value}; shift 2 ;;
        --window) MATCH_WINDOW=${2:?--window needs a value}; shift 2 ;;
        --trim-seconds) MATCH_TRIM_SECONDS=${2:?--trim-seconds needs a value}; shift 2 ;;
        --lease-ttl-ms) LEASE_TTL_MS=${2:?--lease-ttl-ms needs a value}; shift 2 ;;
        --spin-micros) SPIN_MICROS=${2:?--spin-micros needs a value}; shift 2 ;;
        --shards-ready-timeout) SHARDS_READY_TIMEOUT=${2:?--shards-ready-timeout needs a value}; shift 2 ;;
        --leg-grace) LEG_GRACE=${2:?--leg-grace needs a value}; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) echo "run_ladder.sh: unrecognized argument: $1" >&2; usage ;;
    esac
done

[ -n "$HOST_LABEL" ] || usage
[ -n "$WORKDIR" ] || usage

whole_number() {
    case "$2" in
        ''|*[!0-9]*) echo "run_ladder.sh: $1 must be a whole number" >&2; exit 2 ;;
    esac
}
positive_number() {
    whole_number "$1" "$2"
    [ "$2" -gt 0 ] || { echo "run_ladder.sh: $1 must be positive" >&2; exit 2; }
}

positive_number --seconds "$RUN_SECONDS"
positive_number --all-active-seconds "$ALL_ACTIVE_SECONDS"
positive_number --metrics-port "$METRICS_PORT"
positive_number --shard-size "$SHARD_SIZE"
positive_number --max-shards "$MAX_SHARDS"
positive_number --window "$MATCH_WINDOW"
positive_number --shards-ready-timeout "$SHARDS_READY_TIMEOUT"
whole_number --trim-seconds "$MATCH_TRIM_SECONDS"
whole_number --lease-ttl-ms "$LEASE_TTL_MS"
whole_number --spin-micros "$SPIN_MICROS"
whole_number --leg-grace "$LEG_GRACE"

for lang in $LANGS; do
    case "$lang" in
        rust|ts|py) ;;
        *) echo "run_ladder.sh: --langs takes rust, ts and py only; got '$lang'" >&2; exit 2 ;;
    esac
done
for size in $SIZES; do
    case "$size" in
        all) ;;
        ''|*[!0-9]*) echo "run_ladder.sh: --sizes takes whole numbers and 'all'; got '$size'" >&2; exit 2 ;;
        0) echo "run_ladder.sh: --sizes must not contain 0" >&2; exit 2 ;;
    esac
done

mkdir -p "$WORKDIR"
WORKDIR=$(CDPATH= cd -- "$WORKDIR" && pwd)

case "$(uname -s)" in
    Darwin) LIB_NAME=libpm_ws.dylib ;;
    *) LIB_NAME=libpm_ws.so ;;
esac
PMWS_LIB="$REPO/target/release/$LIB_NAME"
export PMWS_LIB

[ -n "$SOCKET" ] || SOCKET="/tmp/pmws-s8c-$$.sock"
SOCKET_BYTES=$(printf '%s' "$SOCKET" | wc -c | tr -d ' ')
if [ "$SOCKET_BYTES" -gt 100 ]; then
    echo "run_ladder.sh: the control socket path is $SOCKET_BYTES bytes and a unix socket address carries 100; pass a shorter --socket" >&2
    exit 2
fi

VENV="$HARNESS/python/.venv"
VENV_PYTHON="$VENV/bin/python"
PINNED_DIR="$WORKDIR/pinned"
ALL_ACTIVE_FILE="$PINNED_DIR/size-all.slugs"
REST_LEDGER="$WORKDIR/rest-ledger.txt"
PLANNED="$WORKDIR/planned-commands.txt"
TABLE_ROWS="$WORKDIR/table-rows.md"
RUNG_SECTIONS="$WORKDIR/rung-sections.md"
LADDER_LOG="$WORKDIR/ladder.log"
PIN_NOTES="$WORKDIR/pin-notes.txt"
WS_COUNTS="$WORKDIR/ws-counts.txt"
# Under --dry-run the report is assembled for real, into the workdir: report assembly is the
# one part a live run cannot afford to have untested, and `bench/reports/` stays untouched.
if [ "$DRY_RUN" -eq 1 ]; then
    REPORT="$WORKDIR/s8c-$HOST_LABEL.md"
else
    REPORT="$REPO/bench/reports/s8c-$HOST_LABEL.md"
fi
mkdir -p "$PINNED_DIR"
: > "$REST_LEDGER"
: > "$PLANNED"
: > "$TABLE_ROWS"
: > "$RUNG_SECTIONS"
: > "$LADDER_LOG"
: > "$PIN_NOTES"
: > "$WS_COUNTS"

REST_TOTAL=0
ABORT_REASON=""
RANK_SOURCE="none"
DAEMON_PID=""
BG_PIDS=()
LEG_PIDS=()
LEG_NAMES=()
LEG_LOGS=()

cleanup() {
    status=$?
    if [ ${#BG_PIDS[@]} -gt 0 ]; then
        for pid in "${BG_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    fi
    if [ ${#LEG_PIDS[@]} -gt 0 ]; then
        for pid in "${LEG_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    fi
    if [ -n "$DAEMON_PID" ]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -f "$SOCKET" "$SOCKET.lock"
    return $status
}
trap cleanup EXIT
on_signal() {
    ABORT_REASON="INTERRUPTED: $1 during the ladder"
    if declare -f assemble_report > /dev/null 2>&1; then
        assemble_report || true
    fi
    exit "$2"
}
trap 'on_signal SIGINT 130' INT
trap 'on_signal SIGTERM 143' TERM

log() {
    printf 'run_ladder.sh: %s\n' "$*" >&2
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LADDER_LOG"
}

plan() {
    printf '%s\n' "$*" >> "$PLANNED"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY %s\n' "$*"
    fi
}

fail() {
    echo "run_ladder.sh: $*" >&2
    exit 1
}

# `grep` exits non-zero when a marker is absent, which is ordinary here and must not trip
# `pipefail`; the scans below route through this helper for that reason.
rest_calls_in() {
    { grep -o 'rest_calls: [0-9]*' "$1" 2>/dev/null || true; } | awk -F': ' '{s+=$2} END{print s+0}'
}

rest_budget_check() {
    planned_calls=$1
    reason=$2
    now=$(date +%s)
    used=$(awk -v now="$now" '$1 >= now - 3600 {s += $2} END {print s+0}' "$REST_LEDGER")
    if [ "$((used + planned_calls))" -gt "$REST_BUDGET_PER_HOUR" ]; then
        ABORT_REASON="ABORTED-ETIQUETTE: REST budget -- $reason would take the rolling hour to $((used + planned_calls)) calls, over the $REST_BUDGET_PER_HOUR budget"
        log "$ABORT_REASON"
        return 1
    fi
    return 0
}

rest_record() {
    echo "$(date +%s) $1 $2" >> "$REST_LEDGER"
    REST_TOTAL=$((REST_TOTAL + $1))
}

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
    rows = status.get("markets", [])
    leased = [row for row in rows if row.get("leases", 0) > 0]
    print(f"{where}_markets_reported: {len(rows)}")
    print(f"{where}_markets_leased: {len(leased)}")
    print(f"{where}_leases_total: {sum(row.get('leases', 0) for row in rows)}")
    ages = [
        shard.get("queue_age", {}).get("p99_micros")
        for shard in shards
        if shard.get("queue_age", {}).get("p99_micros") is not None
    ]
    if ages:
        print(f"{where}_shard_queue_age_p99_micros_max: {max(ages)}")
PYEOF
}

# Chunks the same sorted list `src/daemon.rs` chunks, so a `shard-<i>.slugs` file names exactly
# the markets the daemon co-locates in one real shard. The shard count walks down from the
# desired one until an exact chunking with overflow room exists; a single shard with
# `markets_per_shard = N + 1` always satisfies that, so the search never fails.
plan_shards() {
    python3 - "$1" "$2" "$3" "$MAX_SHARD_MARKETS" <<'PYEOF'
import sys

slugs_path, rung_dir, desired_shards_s, max_shard_markets_s = sys.argv[1:5]
desired_shards = int(desired_shards_s)
max_shard_markets = int(max_shard_markets_s)

with open(slugs_path, "r", encoding="utf-8") as handle:
    raw = [
        line.strip()
        for line in handle
        if line.strip() and not line.strip().startswith("#")
    ]

seen = set()
ordered = []
for slug in raw:
    if slug not in seen:
        seen.add(slug)
        ordered.append(slug)
duplicates = len(raw) - len(ordered)
ordered.sort()
total = len(ordered)
if total == 0:
    print("run_ladder.sh: the pinned slug file names 0 markets", file=sys.stderr)
    raise SystemExit(2)

chosen = None
for shard_count in range(min(desired_shards, total), 0, -1):
    low = -(-total // shard_count)
    high = -(-(total + shard_count) // shard_count)
    for candidate in range(low, high + 1):
        if candidate > max_shard_markets:
            break
        if -(-total // candidate) == shard_count and shard_count * candidate > total:
            chosen = (shard_count, candidate)
            break
    if chosen is not None:
        break
if chosen is None:
    print(
        f"run_ladder.sh: no shard count in [1, {desired_shards}] chunks {total} markets with "
        f"markets_per_shard <= {max_shard_markets}",
        file=sys.stderr,
    )
    raise SystemExit(2)
shard_count, mps = chosen

for shard in range(shard_count):
    chunk = ordered[shard * mps : (shard + 1) * mps]
    with open(f"{rung_dir}/shard-{shard}.slugs", "w", encoding="utf-8") as handle:
        for slug in chunk:
            handle.write(slug + "\n")

with open(f"{rung_dir}/markets-toml.txt", "w", encoding="utf-8") as handle:
    handle.write(", ".join(f'"{slug}"' for slug in ordered))

with open(f"{rung_dir}/sorted.slugs", "w", encoding="utf-8") as handle:
    for slug in ordered:
        handle.write(slug + "\n")

with open(f"{rung_dir}/shard-plan.env", "w", encoding="utf-8") as handle:
    handle.write(f"PLAN_N={total}\n")
    handle.write(f"PLAN_MPS={mps}\n")
    handle.write(f"PLAN_SHARDS={shard_count}\n")
    handle.write(f"PLAN_DUPLICATES={duplicates}\n")
    handle.write(f"PLAN_OVERFLOW_CAPACITY={shard_count * mps - total}\n")
PYEOF
}

merge_obs() {
    python3 - "$@" <<'PYEOF'
import sys

out_path, size = sys.argv[1:3]
inputs = sys.argv[3:]

FOOTER_KEYS = ("events_total", "dropped")

header = []
header_taken = False
rows = []
dropped = 0
present = 0
for path in inputs:
    try:
        handle = open(path, "r", encoding="utf-8", errors="replace")
    except OSError:
        continue
    present += 1
    take_header = not header_taken
    header_taken = True
    seen_obs = False
    with handle:
        for raw in handle:
            stripped = raw.rstrip("\n")
            text = stripped.strip()
            if not text:
                continue
            if text.startswith("#"):
                body = text.lstrip("#").strip()
                key, separator, value = body.partition(":")
                if separator and key.strip() == "dropped":
                    try:
                        dropped += int(value.strip())
                    except ValueError:
                        pass
                if take_header and not seen_obs and key.strip() not in FOOTER_KEYS:
                    header.append(stripped)
                continue
            seen_obs = True
            rows.append(stripped)

if present == 0:
    raise SystemExit(f"merge_obs: none of {len(inputs)} input file(s) exist")

rewritten = []
saw_size = False
for line in header:
    body = line.lstrip("#").strip()
    key, separator, _ = body.partition(":")
    if separator and key.strip() == "size":
        rewritten.append(f"# size: {size}")
        saw_size = True
    else:
        rewritten.append(line)
if not saw_size:
    rewritten.append(f"# size: {size}")

with open(out_path, "w", encoding="utf-8") as handle:
    for line in rewritten:
        handle.write(line + "\n")
    for line in rows:
        handle.write(line + "\n")
    handle.write(f"# events_total: {len(rows)}\n")
    handle.write(f"# dropped: {dropped}\n")
print(f"merged {present}/{len(inputs)} shard log(s), {len(rows)} obs row(s) -> {out_path}")
PYEOF
}

start_sampler() {
    sampler_out=$1
    shift
    sampler_pids=$(printf '%s,' "$@")
    sampler_pids=${sampler_pids%,}
    : > "$sampler_out"
    (
        while :; do
            sample_now=$(date +%s)
            sample_line=$(ps -o rss=,pcpu= -p "$sampler_pids" 2>/dev/null \
                | awk -v t="$sample_now" '{r += $1; c += $2} END {if (NR > 0) printf "%s %d %.1f\n", t, r, c}' || true)
            if [ -n "$sample_line" ]; then
                echo "$sample_line" >> "$sampler_out"
            fi
            sleep 1
        done
    ) &
    BG_PIDS+=($!)
}

start_watchdog() {
    watch_stderr=$1
    trip_file=$2
    stop_file=$3
    rm -f "$trip_file"
    python3 - "$watch_stderr" "$trip_file" "$stop_file" \
        "$WATCHDOG_RECONNECT_THRESHOLD" "$WATCHDOG_WINDOW_SECONDS" >/dev/null 2>&1 <<'PYEOF' &
import os
import re
import sys
import time

stderr_path, trip_path, stop_path, threshold_s, window_s = sys.argv[1:6]
threshold = int(threshold_s)
window = float(window_s)

RECONNECT = re.compile(r"reconnect|re-connect|reconnecting", re.IGNORECASE)
REFUSAL = re.compile(
    r"\b429\b|too many requests|rate.?limit|throttl|\b403\b|forbidden|refused by|"
    r"connection refused by the venue",
    re.IGNORECASE,
)


def scan(path):
    reconnects = 0
    refusals = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if RECONNECT.search(line):
                    reconnects += 1
                if REFUSAL.search(line):
                    refusals.append(line.strip())
    except OSError:
        return None
    return reconnects, refusals


def trip(reason):
    with open(trip_path, "w", encoding="utf-8") as handle:
        handle.write(reason + "\n")


# `baseline` is the reconnect count as of one window ago, and starts at zero: the watchdog
# starts with the leg, so every mention it can see was logged inside the window.
baseline = 0
history = []
while not os.path.exists(stop_path):
    scanned = scan(stderr_path)
    if scanned is not None:
        reconnects, refusals = scanned
        if refusals:
            trip("venue refusal marker on the SDK leg stderr: " + refusals[0][:400])
            break
        now = time.monotonic()
        history.append((now, reconnects))
        kept = []
        for stamp, count in history:
            if now - stamp > window:
                baseline = count
            else:
                kept.append((stamp, count))
        history = kept
        if reconnects - baseline >= threshold:
            trip(
                f"SDK leg reconnect churn: {reconnects - baseline} reconnect mention(s) "
                f"within {int(window)}s"
            )
            break
    time.sleep(2)
PYEOF
    BG_PIDS+=($!)
}

snapshot() {
    "$REPO/target/release/pmwsctl" --socket "$SOCKET" status > "$1/status-$2.json" 2>/dev/null || true
    curl -fsS "127.0.0.1:$METRICS_PORT/metrics" > "$1/metrics-$2.prom" 2>/dev/null || true
}

# ---------------------------------------------------------------- build phase

build_phase() {
    plan "cd $REPO && cargo build --release --locked"
    plan "cd $REPO && cargo build --release --locked --examples"
    case " $LANGS " in *" rust "*) plan "cd $HARNESS/rust && cargo build --release" ;; esac
    case " $LANGS " in *" ts "*) plan "cd $HARNESS/ts && npm ci" ;; esac
    case " $LANGS " in *" py "*)
        plan "python3 -m venv $VENV"
        plan "$VENV/bin/pip install --disable-pip-version-check -r $HARNESS/python/requirements.txt"
        ;;
    esac
    plan "python3 $HARNESS/match_events.py --self-test"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "dry-run: skipping every build; running the matcher self-test only"
        python3 "$HARNESS/match_events.py" --self-test || fail "match_events.py --self-test failed"
        return 0
    fi

    log "building the daemon and its examples"
    ( cd "$REPO" && cargo build --release --locked ) || fail "cargo build --release failed"
    ( cd "$REPO" && cargo build --release --locked --examples ) || fail "cargo build --release --examples failed"
    [ -f "$PMWS_LIB" ] || fail "$PMWS_LIB was not built"

    case " $LANGS " in
        *" rust "*)
            [ -d "$HARNESS/rust" ] || fail "$HARNESS/rust does not exist; the rust SDK leg is not checked in"
            log "building the Rust SDK leg"
            ( cd "$HARNESS/rust" && cargo build --release ) || fail "the Rust SDK leg failed to build"
            ;;
    esac
    case " $LANGS " in
        *" ts "*)
            [ -d "$HARNESS/ts" ] || fail "$HARNESS/ts does not exist; the TypeScript SDK leg is not checked in"
            log "installing the TypeScript SDK leg"
            ( cd "$HARNESS/ts" && npm ci ) || fail "npm ci failed in $HARNESS/ts"
            ;;
    esac
    case " $LANGS " in
        *" py "*)
            [ -f "$HARNESS/python/requirements.txt" ] || fail "$HARNESS/python/requirements.txt does not exist"
            if [ -x "$VENV_PYTHON" ] && "$VENV_PYTHON" -m pip --version > /dev/null 2>&1; then
                log "reusing the existing Python SDK leg venv"
            else
                log "creating the Python SDK leg venv"
                python3 -m venv "$VENV" \
                    || fail "python3 -m venv $VENV failed (a host without ensurepip needs a pre-provisioned venv at $VENV)"
            fi
            "$VENV/bin/pip" install --disable-pip-version-check -q -r "$HARNESS/python/requirements.txt" \
                || fail "installing $HARNESS/python/requirements.txt failed"
            ;;
    esac

    python3 "$HARNESS/match_events.py" --self-test || fail "match_events.py --self-test failed"
}

# -------------------------------------------------------------- pinning phase

placeholder_slugs() {
    count=$1
    out=$2
    : > "$out"
    index=0
    while [ "$index" -lt "$count" ]; do
        printf 'dry-run-placeholder-market-%04d\n' "$index" >> "$out"
        index=$((index + 1))
    done
}

discover_all_active() {
    if [ -n "$MARKETS_FILE" ]; then
        [ -f "$MARKETS_FILE" ] || fail "--markets names $MARKETS_FILE, which does not exist"
        grep -v '^[[:space:]]*#' "$MARKETS_FILE" | grep -v '^[[:space:]]*$' > "$ALL_ACTIVE_FILE" || true
        echo "all-active set: pinned from --markets $MARKETS_FILE (no discovery sweep, no REST spent)" >> "$PIN_NOTES"
        return 0
    fi
    plan "python3 $REPO/bench/discover_markets.py > $ALL_ACTIVE_FILE"
    if [ "$DRY_RUN" -eq 1 ]; then
        placeholder_slugs 24 "$ALL_ACTIVE_FILE"
        echo "all-active set: dry-run placeholders, no discovery sweep was made" >> "$PIN_NOTES"
        return 0
    fi
    rest_budget_check "$SWEEP_REST_ESTIMATE" "the discovery sweep" || return 1
    log "discovery sweep for the all-active market set"
    if ! python3 "$REPO/bench/discover_markets.py" > "$ALL_ACTIVE_FILE" 2> "$WORKDIR/discover-sweep.err"; then
        rest_record "$(rest_calls_in "$WORKDIR/discover-sweep.err")" sweep-failed
        ABORT_REASON="ABORTED-ETIQUETTE: the discovery sweep failed or was refused; see $WORKDIR/discover-sweep.err"
        log "$ABORT_REASON"
        return 1
    fi
    rest_record "$(rest_calls_in "$WORKDIR/discover-sweep.err")" sweep
    echo "all-active set: one discover_markets.py sweep, $(rest_calls_in "$WORKDIR/discover-sweep.err") REST call(s)" >> "$PIN_NOTES"
    return 0
}

pin_size1() {
    out=$1
    plan "python3 $REPO/bench/discover_markets.py --page1-only | grep $BTC_5MIN_PREFIX | newest"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "${BTC_5MIN_PREFIX}0000000000" > "$out"
        return 0
    fi
    rest_budget_check "$PAGE1_REST_ESTIMATE" "the size-1 page-1 poll" || return 1
    if ! python3 "$REPO/bench/discover_markets.py" --page1-only > "$WORKDIR/page1.txt" 2> "$WORKDIR/page1.err"; then
        rest_record "$(rest_calls_in "$WORKDIR/page1.err")" page1-failed
        ABORT_REASON="ABORTED-ETIQUETTE: the size-1 page-1 poll failed or was refused; see $WORKDIR/page1.err"
        log "$ABORT_REASON"
        return 1
    fi
    rest_record "$(rest_calls_in "$WORKDIR/page1.err")" page1
    newest=$({ grep -F "$BTC_5MIN_PREFIX" "$WORKDIR/page1.txt" || true; } | sort -t- -k7,7n | tail -n 1)
    if [ -z "$newest" ]; then
        log "no ${BTC_5MIN_PREFIX}* listing on page 1; the size-1 rung is skipped"
        return 1
    fi
    echo "$newest" > "$out"
    echo "size 1: $newest (newest ${BTC_5MIN_PREFIX}* on page 1 at rung start)" >> "$PIN_NOTES"
    return 0
}

pin_from_ranking() {
    ranked=$1
    ranked_count=$(wc -l < "$ranked" | tr -d ' ')
    for size in $SIZES; do
        case "$size" in all|1) continue ;; esac
        if [ "$size" -gt "$ranked_count" ]; then
            echo "size $size: not pinned -- the venue lists only $ranked_count market(s)" >> "$PIN_NOTES"
            continue
        fi
        head -n "$size" "$ranked" > "$PINNED_DIR/size-$size.slugs"
        echo "size $size: top $size by observed update count ($RANK_SOURCE) -> $PINNED_DIR/size-$size.slugs" >> "$PIN_NOTES"
    done
}

rank_from_obs() {
    obs_file=$1
    ranked=$2
    awk '$1 == "obs" {count[$2] += 1} END {for (slug in count) printf "%d %s\n", count[slug], slug}' "$obs_file" \
        | sort -k1,1nr -k2,2 | awk '{print $2}' > "$ranked"
    [ -s "$ranked" ]
}

# ------------------------------------------------------------------ rung phase

# Sets RUNG_PMWS_MERGED / RUNG_EMBEDDED_OBS on a completed rung so the ladder can rank markets
# from the first all-active rung's pm-ws observations.
RUNG_PMWS_MERGED=""
RUNG_EMBEDDED_OBS=""

rung_failure_section() {
    {
        echo "### rung $1 -- FAILED before measurement"
        echo
        echo '```'
        echo "$3"
        echo "--- last 20 lines of pmwsd.log ---"
        tail -n 20 "$2/pmwsd.log" 2>/dev/null || echo "(no daemon log captured)"
        echo "(an 'address already in use' here is the metrics port: pass --metrics-port)"
        echo '```'
        echo
    } >> "$RUNG_SECTIONS"
}

run_rung() {
    rung_lang=$1
    rung_size=$2
    rung_slugs=$3
    rung_duration=$4

    rung_id="$rung_lang-$rung_size"
    rung_dir="$WORKDIR/rung-$rung_id"
    mkdir -p "$rung_dir"
    cp "$rung_slugs" "$rung_dir/pinned.slugs"
    RUNG_PMWS_MERGED=""
    RUNG_EMBEDDED_OBS=""

    rung_market_count=$(wc -l < "$rung_dir/pinned.slugs" | tr -d ' ')
    desired_shards=$(( (rung_market_count + SHARD_SIZE - 1) / SHARD_SIZE ))
    [ "$desired_shards" -ge 1 ] || desired_shards=1
    [ "$desired_shards" -le "$MAX_SHARDS" ] || desired_shards=$MAX_SHARDS

    plan_shards "$rung_dir/pinned.slugs" "$rung_dir" "$desired_shards" \
        || fail "shard planning failed for rung $rung_id"
    # shellcheck disable=SC1090
    . "$rung_dir/shard-plan.env"
    shards=$PLAN_SHARDS
    mps=$PLAN_MPS
    markets_toml=$(cat "$rung_dir/markets-toml.txt")
    config="$rung_dir/pmwsd.toml"

    cat > "$config" <<CONFIGEOF
control_socket = "$SOCKET"
endpoint = "$ENDPOINT"
markets = [$markets_toml]
markets_per_shard = $mps
max_venue_connections = $((2 * shards))
metrics_listen = "127.0.0.1:$METRICS_PORT"
lease_ttl_ms = $LEASE_TTL_MS

[delivery]
directory = "$rung_dir"
CONFIGEOF

    case "$rung_lang" in
        rust) sdk_leg=rust-sdk; pmws_leg=rust-shm ;;
        ts) sdk_leg=ts-sdk; pmws_leg=ts-binding ;;
        py) sdk_leg=py-sdk; pmws_leg=py-binding ;;
    esac
    sdk_obs="$rung_dir/$sdk_leg.obs"
    sdk_err="$rung_dir/$sdk_leg.err"
    embedded_obs="$rung_dir/rust-embedded.obs"

    plan "# rung $rung_id: $PLAN_N market(s), $shards shard(s), markets_per_shard=$mps, ${rung_duration}s"
    plan "$REPO/target/release/pmwsd --config $config > $rung_dir/pmwsd.log 2>&1 &"
    plan "$REPO/target/release/pmwsctl --socket $SOCKET status   # shards-ready gate, then start/middle/end snapshots"
    plan "curl -fsS 127.0.0.1:$METRICS_PORT/metrics > $rung_dir/metrics-<point>.prom"

    shard_index=0
    while [ "$shard_index" -lt "$shards" ]; do
        shard_file="$rung_dir/shard-$shard_index.slugs"
        shard_obs="$rung_dir/$pmws_leg.shard$shard_index.obs"
        shard_label="$HOST_LABEL, $pmws_leg, size $rung_size, shard $shard_index of $shards"
        case "$rung_lang" in
            rust)
                plan "$REPO/target/release/examples/matched_consumer --control $SOCKET --slugs $shard_file --seconds $rung_duration --obs-out $shard_obs --label \"$shard_label\" > $rung_dir/$pmws_leg.shard$shard_index.log 2> $rung_dir/$pmws_leg.shard$shard_index.err &"
                ;;
            ts)
                plan "PMWS_LIB=$PMWS_LIB node $REPO/examples/bench_consumer.ts --control $SOCKET --slugs $shard_file --seconds $rung_duration --lease-ttl-ms $LEASE_TTL_MS --spin-micros $SPIN_MICROS --label \"$shard_label\" --obs-out $shard_obs > $rung_dir/$pmws_leg.shard$shard_index.log 2> $rung_dir/$pmws_leg.shard$shard_index.err &"
                ;;
            py)
                plan "PMWS_LIB=$PMWS_LIB python3 $REPO/examples/bench_consumer.py --control $SOCKET --slugs $shard_file --seconds $rung_duration --lease-ttl-ms $LEASE_TTL_MS --spin-micros $SPIN_MICROS --label \"$shard_label\" --obs-out $shard_obs > $rung_dir/$pmws_leg.shard$shard_index.log 2> $rung_dir/$pmws_leg.shard$shard_index.err &"
                ;;
        esac
        shard_index=$((shard_index + 1))
    done

    if [ "$rung_lang" = rust ]; then
        plan "$REPO/target/release/examples/embedded_live --slugs $rung_dir/pinned.slugs --seconds $rung_duration --endpoint $ENDPOINT --markets-per-connection $mps --obs-out $embedded_obs --label \"$HOST_LABEL, rust-embedded, size $rung_size\" > $rung_dir/rust-embedded.log 2> $rung_dir/rust-embedded.err &"
    fi

    sdk_endpoint_note="the SDK's own default"
    sdk_endpoint_args=""
    if [ "$ENDPOINT_EXPLICIT" -eq 1 ]; then
        sdk_endpoint_note="$ENDPOINT"
        sdk_endpoint_args="--endpoint $ENDPOINT"
    fi
    case "$rung_lang" in
        rust) sdk_cmd="$HARNESS/rust/target/release/sdk_leg" ;;
        ts) sdk_cmd="node $HARNESS/ts/sdk_leg.ts" ;;
        py) sdk_cmd="$VENV_PYTHON $HARNESS/python/sdk_leg.py" ;;
    esac
    plan "$sdk_cmd --slugs $rung_dir/pinned.slugs --seconds $rung_duration $sdk_endpoint_args --obs-out $sdk_obs --label \"$HOST_LABEL, $sdk_leg, size $rung_size\" > $rung_dir/$sdk_leg.log 2> $sdk_err &"
    plan "ps -o rss=,pcpu= -p <leg pids>   # 1 Hz into $rung_dir/<leg>.res"

    if [ "$rung_lang" = rust ]; then embedded_connections=$shards; else embedded_connections=0; fi
    echo "$rung_id: daemon=$shards embedded=$embedded_connections sdk=1 total=$((shards + embedded_connections + 1))" >> "$WS_COUNTS"

    if [ "$DRY_RUN" -eq 1 ]; then
        {
            echo "### rung $rung_id (dry-run, not executed)"
            echo
            echo '```'
            echo "pinned_markets: $PLAN_N"
            echo "pinned_set_file: $rung_dir/pinned.slugs"
            echo "shards: $shards"
            echo "markets_per_shard: $mps"
            echo "seconds: $rung_duration"
            echo "sdk_leg: $sdk_leg (endpoint: $sdk_endpoint_note)"
            echo "pmws_leg: $pmws_leg ($shards consumer session(s), one per shard)"
            if [ "$rung_lang" = rust ]; then echo "embedded_leg: rust-embedded"; fi
            echo "ws_connection_estimate: daemon=$shards embedded=$embedded_connections sdk=1"
            echo '```'
            echo
        } >> "$RUNG_SECTIONS"
        plan_match_commands "$rung_lang" "$rung_size" "$rung_dir" "$sdk_leg" "$pmws_leg"
        return 0
    fi

    log "rung $rung_id: $PLAN_N market(s), $shards shard(s), ${rung_duration}s"
    rm -f "$SOCKET"
    "$REPO/target/release/pmwsd" --config "$config" > "$rung_dir/pmwsd.log" 2>&1 &
    DAEMON_PID=$!

    waited=0
    until "$REPO/target/release/pmwsctl" --socket "$SOCKET" status > /dev/null 2>&1; do
        waited=$((waited + 1))
        if [ "$waited" -ge 200 ]; then
            log "rung $rung_id: pmwsd never answered on $SOCKET"
            rung_failure_section "$rung_id" "$rung_dir" "pmwsd never answered on $SOCKET within 20s"
            stop_daemon
            return 1
        fi
        sleep 0.1
    done

    gate_start=$(date +%s)
    last_down=""
    while :; do
        "$REPO/target/release/pmwsctl" --socket "$SOCKET" status > "$rung_dir/status-start.json.tmp" 2>/dev/null || true
        gate=$(run_report_tool shard_check "$rung_dir/status-start.json.tmp" "$shards")
        case "$gate" in
            READY) break ;;
            DOWN*) last_down=${gate#DOWN } ;;
            COUNT_MISMATCH*) last_down="shard count ${gate#COUNT_MISMATCH }, expected $shards" ;;
            *) last_down="status unavailable" ;;
        esac
        if [ "$(($(date +%s) - gate_start))" -ge "$SHARDS_READY_TIMEOUT" ]; then
            log "rung $rung_id: not all $shards shard(s) connected after ${SHARDS_READY_TIMEOUT}s; down/mismatch: $last_down"
            rung_failure_section "$rung_id" "$rung_dir" \
                "not all $shards shard(s) connected after ${SHARDS_READY_TIMEOUT}s; down/mismatch: $last_down"
            stop_daemon
            return 1
        fi
        sleep 1
    done
    mv "$rung_dir/status-start.json.tmp" "$rung_dir/status-start.json"
    curl -fsS "127.0.0.1:$METRICS_PORT/metrics" > "$rung_dir/metrics-start.prom" 2>/dev/null || true

    LEG_PIDS=()
    LEG_NAMES=()
    LEG_LOGS=()
    pmws_pids=""
    shard_index=0
    while [ "$shard_index" -lt "$shards" ]; do
        shard_file="$rung_dir/shard-$shard_index.slugs"
        shard_obs="$rung_dir/$pmws_leg.shard$shard_index.obs"
        shard_label="$HOST_LABEL, $pmws_leg, size $rung_size, shard $shard_index of $shards"
        shard_log="$rung_dir/$pmws_leg.shard$shard_index.log"
        shard_err="$rung_dir/$pmws_leg.shard$shard_index.err"
        case "$rung_lang" in
            rust)
                "$REPO/target/release/examples/matched_consumer" --control "$SOCKET" \
                    --slugs "$shard_file" --seconds "$rung_duration" --obs-out "$shard_obs" \
                    --label "$shard_label" > "$shard_log" 2> "$shard_err" &
                ;;
            ts)
                node "$REPO/examples/bench_consumer.ts" --control "$SOCKET" --slugs "$shard_file" \
                    --seconds "$rung_duration" --lease-ttl-ms "$LEASE_TTL_MS" \
                    --spin-micros "$SPIN_MICROS" --label "$shard_label" --obs-out "$shard_obs" \
                    > "$shard_log" 2> "$shard_err" &
                ;;
            py)
                python3 "$REPO/examples/bench_consumer.py" --control "$SOCKET" --slugs "$shard_file" \
                    --seconds "$rung_duration" --lease-ttl-ms "$LEASE_TTL_MS" \
                    --spin-micros "$SPIN_MICROS" --label "$shard_label" --obs-out "$shard_obs" \
                    > "$shard_log" 2> "$shard_err" &
                ;;
        esac
        leg_pid=$!
        LEG_PIDS+=("$leg_pid")
        LEG_NAMES+=("$pmws_leg.shard$shard_index")
        LEG_LOGS+=("$rung_dir/$pmws_leg.shard$shard_index")
        pmws_pids="$pmws_pids $leg_pid"
        shard_index=$((shard_index + 1))
    done
    start_sampler "$rung_dir/$pmws_leg.res" $pmws_pids

    if [ "$rung_lang" = rust ]; then
        "$REPO/target/release/examples/embedded_live" --slugs "$rung_dir/pinned.slugs" \
            --seconds "$rung_duration" --endpoint "$ENDPOINT" --markets-per-connection "$mps" \
            --obs-out "$embedded_obs" --label "$HOST_LABEL, rust-embedded, size $rung_size" \
            > "$rung_dir/rust-embedded.log" 2> "$rung_dir/rust-embedded.err" &
        embedded_pid=$!
        LEG_PIDS+=("$embedded_pid")
        LEG_NAMES+=("rust-embedded")
        LEG_LOGS+=("$rung_dir/rust-embedded")
        start_sampler "$rung_dir/rust-embedded.res" "$embedded_pid"
    fi

    # shellcheck disable=SC2086
    case "$rung_lang" in
        rust)
            "$HARNESS/rust/target/release/sdk_leg" --slugs "$rung_dir/pinned.slugs" \
                --seconds "$rung_duration" $sdk_endpoint_args --obs-out "$sdk_obs" \
                --label "$HOST_LABEL, $sdk_leg, size $rung_size" \
                > "$rung_dir/$sdk_leg.log" 2> "$sdk_err" &
            ;;
        ts)
            node "$HARNESS/ts/sdk_leg.ts" --slugs "$rung_dir/pinned.slugs" \
                --seconds "$rung_duration" $sdk_endpoint_args --obs-out "$sdk_obs" \
                --label "$HOST_LABEL, $sdk_leg, size $rung_size" \
                > "$rung_dir/$sdk_leg.log" 2> "$sdk_err" &
            ;;
        py)
            "$VENV_PYTHON" "$HARNESS/python/sdk_leg.py" --slugs "$rung_dir/pinned.slugs" \
                --seconds "$rung_duration" $sdk_endpoint_args --obs-out "$sdk_obs" \
                --label "$HOST_LABEL, $sdk_leg, size $rung_size" \
                > "$rung_dir/$sdk_leg.log" 2> "$sdk_err" &
            ;;
    esac
    sdk_pid=$!
    LEG_PIDS+=("$sdk_pid")
    LEG_NAMES+=("$sdk_leg")
    LEG_LOGS+=("$rung_dir/$sdk_leg")
    start_sampler "$rung_dir/$sdk_leg.res" "$sdk_pid"
    start_sampler "$rung_dir/pmwsd.res" "$DAEMON_PID"

    trip_file="$rung_dir/watchdog.trip"
    stop_file="$rung_dir/watchdog.stop"
    rm -f "$stop_file"
    start_watchdog "$sdk_err" "$trip_file" "$stop_file"

    run_start=$(date +%s)
    midpoint=$((rung_duration / 2))
    deadline=$((run_start + rung_duration + LEG_GRACE))
    mid_taken=0
    tripped=0
    overran=0
    while :; do
        alive=0
        for pid in "${LEG_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then alive=1; fi
        done
        now=$(date +%s)
        if [ "$mid_taken" -eq 0 ] && [ "$((now - run_start))" -ge "$midpoint" ]; then
            snapshot "$rung_dir" middle
            mid_taken=1
        fi
        if [ -f "$trip_file" ]; then
            tripped=1
            break
        fi
        if [ "$alive" -eq 0 ]; then break; fi
        if [ "$now" -ge "$deadline" ]; then
            overran=1
            break
        fi
        sleep 2
    done
    [ "$mid_taken" -eq 1 ] || snapshot "$rung_dir" middle
    : > "$stop_file"

    if [ "$tripped" -eq 1 ]; then
        ABORT_REASON="ABORTED-ETIQUETTE: $(cat "$trip_file" 2>/dev/null || echo 'watchdog tripped') (rung $rung_id)"
        log "$ABORT_REASON"
    elif [ "$overran" -eq 1 ]; then
        log "rung $rung_id: legs still alive ${LEG_GRACE}s past the run length; terminating"
    fi

    for pid in "${LEG_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    leg_index=0
    exit_summary=""
    while [ "$leg_index" -lt "${#LEG_PIDS[@]}" ]; do
        if wait "${LEG_PIDS[$leg_index]}" 2>/dev/null; then
            code=0
        else
            code=$?
        fi
        echo "$code" > "${LEG_LOGS[$leg_index]}.exit"
        exit_summary="$exit_summary
${LEG_NAMES[$leg_index]} exit $code"
        leg_index=$((leg_index + 1))
    done
    LEG_PIDS=()

    if [ ${#BG_PIDS[@]} -gt 0 ]; then
        for pid in "${BG_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
    fi
    BG_PIDS=()

    snapshot "$rung_dir" end
    stop_daemon

    merged_pmws="$rung_dir/$pmws_leg.merged.obs"
    shard_obs_files=""
    shard_index=0
    while [ "$shard_index" -lt "$shards" ]; do
        shard_obs_files="$shard_obs_files $rung_dir/$pmws_leg.shard$shard_index.obs"
        shard_index=$((shard_index + 1))
    done
    merge_note=""
    # shellcheck disable=SC2086
    if merge_note=$(merge_obs "$merged_pmws" "$rung_size" $shard_obs_files 2>&1); then
        RUNG_PMWS_MERGED="$merged_pmws"
    else
        log "rung $rung_id: merging $pmws_leg shard logs failed: $merge_note"
    fi
    if [ -f "$embedded_obs" ]; then RUNG_EMBEDDED_OBS="$embedded_obs"; fi

    {
        echo "### rung $rung_id"
        echo
        echo '```'
        echo "pinned_markets: $PLAN_N"
        echo "pinned_set_file: $rung_dir/pinned.slugs"
        echo "shards: $shards"
        echo "markets_per_shard: $mps"
        echo "seconds: $rung_duration"
        echo "sdk_leg: $sdk_leg (endpoint: $sdk_endpoint_note)"
        echo "pmws_leg: $pmws_leg ($shards consumer session(s), one per shard)"
        if [ "$rung_lang" = rust ]; then echo "embedded_leg: rust-embedded"; fi
        echo "ws_connection_estimate: daemon=$shards embedded=$embedded_connections sdk=1"
        echo "obs_merge: $merge_note"
        echo "leg exit codes:$exit_summary"
        echo '```'
        echo
        echo "#### leg internals"
        echo
        leg_index=0
        while [ "$leg_index" -lt "${#LEG_NAMES[@]}" ]; do
            leg_base="${LEG_LOGS[$leg_index]}"
            leg_code=$(cat "$leg_base.exit" 2>/dev/null || echo unknown)
            echo "\`${LEG_NAMES[$leg_index]}\` exit $leg_code"
            echo
            echo '```'
            if [ -s "$leg_base.log" ]; then cat "$leg_base.log"; else echo "(no stdout captured)"; fi
            if [ "$leg_code" != "0" ]; then
                echo "--- last 20 lines of stderr ---"
                tail -n 20 "$leg_base.err" 2>/dev/null || echo "(no stderr captured)"
            fi
            echo '```'
            echo
            leg_index=$((leg_index + 1))
        done
        echo "#### daemon"
        echo
        echo '```'
        run_report_tool summarize "$rung_dir/status-start.json" start
        run_report_tool summarize "$rung_dir/status-middle.json" middle
        run_report_tool summarize "$rung_dir/status-end.json" end
        echo '```'
        echo
    } >> "$RUNG_SECTIONS"

    run_match_pairs "$rung_lang" "$rung_size" "$rung_dir" "$sdk_leg" "$pmws_leg" "$merged_pmws" "$embedded_obs"

    if [ "$tripped" -eq 1 ]; then
        return 1
    fi
    return 0
}

stop_daemon() {
    if [ -n "$DAEMON_PID" ]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        DAEMON_PID=""
    fi
    rm -f "$SOCKET" "$SOCKET.lock"
}

# ----------------------------------------------------------------- match phase

match_pair() {
    match_size=$1
    match_dir=$2
    file_a=$3
    file_b=$4
    label_a=$5
    label_b=$6
    res_a=$7
    res_b=$8

    out="$match_dir/match-$label_a-vs-$label_b.txt"
    match_args="$file_a $file_b --label-a $label_a --label-b $label_b --size $match_size --window $MATCH_WINDOW --trim-seconds $MATCH_TRIM_SECONDS --markdown"
    plan "python3 $HARNESS/match_events.py $match_args --resources-a $res_a --resources-b $res_b > $out"
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi
    if [ ! -f "$file_a" ] || [ ! -f "$file_b" ]; then
        {
            echo "#### match: $label_a vs $label_b"
            echo
            echo '```'
            echo "not matched: missing $( [ -f "$file_a" ] || echo "$file_a" ) $( [ -f "$file_b" ] || echo "$file_b" )"
            echo '```'
            echo
        } >> "$RUNG_SECTIONS"
        return 0
    fi
    resource_args=""
    if [ -f "$res_a" ]; then resource_args="$resource_args --resources-a $res_a"; fi
    if [ -f "$res_b" ]; then resource_args="$resource_args --resources-b $res_b"; fi
    # shellcheck disable=SC2086
    if python3 "$HARNESS/match_events.py" "$file_a" "$file_b" --label-a "$label_a" \
        --label-b "$label_b" --size "$match_size" --window "$MATCH_WINDOW" \
        --trim-seconds "$MATCH_TRIM_SECONDS" --markdown $resource_args > "$out" 2>&1; then
        row=$(tail -n 1 "$out")
        case "$row" in
            "|"*) printf '%s\n' "$row" >> "$TABLE_ROWS" ;;
            *) log "match $label_a vs $label_b produced no markdown row" ;;
        esac
    else
        log "match_events.py failed for $label_a vs $label_b; see $out"
    fi
    {
        echo "#### match: $label_a vs $label_b"
        echo
        echo '```'
        cat "$out"
        echo '```'
        echo
    } >> "$RUNG_SECTIONS"
}

plan_match_commands() {
    match_lang=$1
    match_size=$2
    match_dir=$3
    match_sdk=$4
    match_pmws=$5
    plan "python3 $HARNESS/match_events.py <merge of $match_dir/$match_pmws.shard*.obs> ... --markdown"
    case "$match_lang" in
        rust)
            match_pair "$match_size" "$match_dir" "$match_dir/$match_sdk.obs" "$match_dir/$match_pmws.merged.obs" "$match_sdk" "$match_pmws" "$match_dir/$match_sdk.res" "$match_dir/$match_pmws.res"
            match_pair "$match_size" "$match_dir" "$match_dir/$match_sdk.obs" "$match_dir/rust-embedded.obs" "$match_sdk" "rust-embedded" "$match_dir/$match_sdk.res" "$match_dir/rust-embedded.res"
            match_pair "$match_size" "$match_dir" "$match_dir/rust-embedded.obs" "$match_dir/$match_pmws.merged.obs" "rust-embedded" "$match_pmws" "$match_dir/rust-embedded.res" "$match_dir/$match_pmws.res"
            ;;
        *)
            match_pair "$match_size" "$match_dir" "$match_dir/$match_sdk.obs" "$match_dir/$match_pmws.merged.obs" "$match_sdk" "$match_pmws" "$match_dir/$match_sdk.res" "$match_dir/$match_pmws.res"
            ;;
    esac
}

run_match_pairs() {
    match_lang=$1
    match_size=$2
    match_dir=$3
    match_sdk=$4
    match_pmws=$5
    merged=$6
    embedded=$7
    case "$match_lang" in
        rust)
            match_pair "$match_size" "$match_dir" "$match_dir/$match_sdk.obs" "$merged" "$match_sdk" "$match_pmws" "$match_dir/$match_sdk.res" "$match_dir/$match_pmws.res"
            match_pair "$match_size" "$match_dir" "$match_dir/$match_sdk.obs" "$embedded" "$match_sdk" "rust-embedded" "$match_dir/$match_sdk.res" "$match_dir/rust-embedded.res"
            match_pair "$match_size" "$match_dir" "$embedded" "$merged" "rust-embedded" "$match_pmws" "$match_dir/rust-embedded.res" "$match_dir/$match_pmws.res"
            ;;
        *)
            match_pair "$match_size" "$match_dir" "$match_dir/$match_sdk.obs" "$merged" "$match_sdk" "$match_pmws" "$match_dir/$match_sdk.res" "$match_dir/$match_pmws.res"
            ;;
    esac
}

# ---------------------------------------------------------------- report phase

assemble_report() {
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$REPO/bench/reports"
    fi
    {
        echo "# pm-ws S8c comparative benchmark -- SDK vs pm-ws ($HOST_LABEL)"
        echo
        echo '```'
        echo "host_label: $HOST_LABEL"
        echo "generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "uname: $(uname -a)"
        echo "commit: $(cd "$REPO" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
        echo "workdir: $WORKDIR"
        echo "control_socket: $SOCKET"
        echo "endpoint: $ENDPOINT (daemon and embedded leg; SDK legs use $( [ "$ENDPOINT_EXPLICIT" -eq 1 ] && echo "$ENDPOINT" || echo "the SDK's own default" ))"
        echo "sizes: $SIZES"
        echo "langs: $LANGS"
        echo "seconds: $RUN_SECONDS (all-active $ALL_ACTIVE_SECONDS, size 1 capped at $SIZE1_MAX_SECONDS)"
        echo "match_window: $MATCH_WINDOW"
        echo "match_trim_seconds: $MATCH_TRIM_SECONDS"
        echo "rest_calls_total: $REST_TOTAL (rolling-hour budget $REST_BUDGET_PER_HOUR, ledger $REST_LEDGER)"
        echo "ws_connections_per_rung:"
        sed 's/^/  /' "$WS_COUNTS"
        echo "ranking_source: $RANK_SOURCE"
        if [ -n "$ABORT_REASON" ]; then
            echo "ladder_status: $ABORT_REASON"
        else
            echo "ladder_status: completed"
        fi
        echo '```'
        echo
        echo "## boundary and method"
        echo
        echo "\`t_obs\` is stamped at the first instant strategy code holds the decoded update;"
        echo "the digest, the \`.obs\` format, the leg inventory and the leg CLI contract are"
        echo "defined in \`bench/sdk-harness/README.md\`, which is authoritative. Matched deltas"
        echo "are \`t_obs(pm-ws leg) - t_obs(reference leg)\` in nanoseconds, signed; a delta of"
        echo "one second or more is discarded as a clock step, counted, never clamped."
        echo "\`match_events.py <a.obs> <b.obs>\` reproduces any single pairing."
        echo
        echo "Market-set pinning:"
        echo
        echo '```'
        cat "$PIN_NOTES"
        echo '```'
        echo
        echo "## size x pair"
        echo
        echo "| size | pair | align | matched | matched frac | frac denom | implausible | tol rejected | tol blocked | censored frac | p50 us | p99 us | p99.9 us | pm-ws-first frac |"
        echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
        cat "$TABLE_ROWS"
        echo
        echo "\`align\` is \`rev\` when both legs emit a book revision (a pm-ws-vs-pm-ws pairing)"
        echo "and \`digest\` otherwise. The last column is the fraction of matched pairs whose"
        echo "delta is negative -- the pm-ws leg observed the event first. \`matched frac\` is"
        echo "matched pairs over \`min(obs_a, obs_b)\` after trimming and \`frac denom\` names the"
        echo "side that minimum came from; unmatched rows are pm-ws latest-state coalescing plus"
        echo "tolerance-rejected and window-bounded skips, so the fraction is not a coalescing"
        echo "measure. \`tol rejected\` counts every candidate the tolerance gate turned away and"
        echo "\`tol blocked\` the subset that lost a pairing; \`censored frac\` is"
        echo "(implausible + tol blocked) over (delta samples + implausible + tol blocked)."
        echo "A withheld percentile prints"
        echo "\`--\`: p99.9 needs 2000 samples, p99 needs 200."
        echo
        echo "## per-rung detail"
        echo
        cat "$RUNG_SECTIONS"
        echo "## notes"
        echo
        echo "- CPU percentages come from \`ps -o pcpu=\`, which is a process-lifetime average on"
        echo "  both macOS and Linux, not an instantaneous sample; \`mean CPU%\` is therefore a mean"
        echo "  of lifetime averages and must not be read as a duty cycle. RSS is the 1 Hz peak."
        echo "- One \`pmwsd\` per (language, size) rung rather than one shared across languages:"
        echo "  rungs run sequentially, so each language's binding leg still shares the daemon"
        echo "  topology the README describes, but never simultaneously with another language's."
        echo "- A multi-shard pm-ws leg is one consumer session per shard, because a session maps"
        echo "  exactly one shard's segment; the per-shard \`.obs\` logs are concatenated per leg"
        echo "  before matching, which is order-safe because markets never span shards."
        echo "- Regenerate with:"
        echo
        echo '```'
        echo "bench/sdk-harness/run_ladder.sh --host-label $HOST_LABEL --workdir $WORKDIR \\"
        echo "  --sizes \"$SIZES\" --langs \"$LANGS\" --seconds $RUN_SECONDS \\"
        echo "  --all-active-seconds $ALL_ACTIVE_SECONDS --metrics-port $METRICS_PORT"
        echo '```'
        echo
        echo "## commands"
        echo
        echo '```'
        cat "$PLANNED"
        echo '```'
    } > "$REPORT"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "dry-run: report assembled into $REPORT; bench/reports/ untouched"
    else
        log "report written to $REPORT"
    fi
}

# ------------------------------------------------------------------- the ladder

ordered_sizes() {
    has_all=0
    numeric=""
    for size in $SIZES; do
        if [ "$size" = all ]; then
            has_all=1
        else
            numeric="$numeric $size"
        fi
    done
    sorted=""
    if [ -n "$numeric" ]; then
        # shellcheck disable=SC2086
        sorted=$(printf '%s\n' $numeric | sort -nru | tr '\n' ' ')
    fi
    if [ "$has_all" -eq 1 ]; then
        echo "all $sorted"
    else
        echo "$sorted"
    fi
}

# Sets RUNG_SLUG_FILE rather than printing it: `plan` writes to stdout under --dry-run, so a
# command substitution here would swallow the planned commands into the path.
RUNG_SLUG_FILE=""
slug_file_for_size() {
    size=$1
    RUNG_SLUG_FILE=""
    if [ "$size" = all ]; then
        RUNG_SLUG_FILE="$ALL_ACTIVE_FILE"
        return 0
    fi
    if [ "$size" = 1 ]; then
        pin_size1 "$PINNED_DIR/size-1.slugs" || return 1
        RUNG_SLUG_FILE="$PINNED_DIR/size-1.slugs"
        return 0
    fi
    [ -f "$PINNED_DIR/size-$size.slugs" ] || return 1
    RUNG_SLUG_FILE="$PINNED_DIR/size-$size.slugs"
}

duration_for_size() {
    case "$1" in
        all) echo "$ALL_ACTIVE_SECONDS" ;;
        1) if [ "$RUN_SECONDS" -lt "$SIZE1_MAX_SECONDS" ]; then echo "$RUN_SECONDS"; else echo "$SIZE1_MAX_SECONDS"; fi ;;
        *) echo "$RUN_SECONDS" ;;
    esac
}

build_phase

if ! discover_all_active; then
    assemble_report
    exit 1
fi
ALL_ACTIVE_COUNT=$(wc -l < "$ALL_ACTIVE_FILE" | tr -d ' ')
[ "$ALL_ACTIVE_COUNT" -gt 0 ] || fail "the all-active market set is empty"
log "all-active set: $ALL_ACTIVE_COUNT market(s)"

ORDERED_SIZES=$(ordered_sizes)
FIRST_LANG=$(echo "$LANGS" | awk '{print $1}')
HAS_ALL=0
case " $ORDERED_SIZES " in *" all "*) HAS_ALL=1 ;; esac

DONE_FIRST_ALL=0
if [ "$HAS_ALL" -eq 1 ]; then
    log "first rung: $FIRST_LANG at all-active, which the ladder ranks the remaining sizes from"
    if run_rung "$FIRST_LANG" all "$ALL_ACTIVE_FILE" "$(duration_for_size all)"; then
        DONE_FIRST_ALL=1
    else
        DONE_FIRST_ALL=1
        log "the first all-active rung did not complete; the size ladder falls back to whatever ranking source is left"
    fi
fi

RANKED="$WORKDIR/ranked.slugs"
if [ -n "$ABORT_REASON" ]; then
    :
elif [ "$DRY_RUN" -eq 1 ]; then
    cp "$ALL_ACTIVE_FILE" "$RANKED"
    RANK_SOURCE="dry-run: the all-active file in sweep order, unranked"
    echo "ranked sizes: dry-run placeholders, first-N of the placeholder set" >> "$PIN_NOTES"
    pin_from_ranking "$RANKED"
elif [ "$DONE_FIRST_ALL" -eq 1 ] && [ -n "$RUNG_PMWS_MERGED" ] && rank_from_obs "$RUNG_PMWS_MERGED" "$RANKED"; then
    RANK_SOURCE="observed update count per market in $RUNG_PMWS_MERGED (the $FIRST_LANG all-active rung's pm-ws leg)"
    pin_from_ranking "$RANKED"
elif [ "$DONE_FIRST_ALL" -eq 1 ] && [ -n "$RUNG_EMBEDDED_OBS" ] && rank_from_obs "$RUNG_EMBEDDED_OBS" "$RANKED"; then
    RANK_SOURCE="observed update count per market in $RUNG_EMBEDDED_OBS (the $FIRST_LANG all-active rung's embedded leg; the shm leg's logs were unusable)"
    pin_from_ranking "$RANKED"
else
    sort "$ALL_ACTIVE_FILE" > "$RANKED"
    RANK_SOURCE="NO all-active rung observations were available; sizes are the first N of the sorted discovery sweep, NOT ranked by observed update count"
    echo "ranked sizes: $RANK_SOURCE" >> "$PIN_NOTES"
    pin_from_ranking "$RANKED"
fi

for lang in $LANGS; do
    [ -z "$ABORT_REASON" ] || break
    for size in $ORDERED_SIZES; do
        [ -z "$ABORT_REASON" ] || break
        if [ "$size" = all ] && [ "$lang" = "$FIRST_LANG" ] && [ "$DONE_FIRST_ALL" -eq 1 ]; then
            continue
        fi
        if [ "$size" != all ] && [ "$size" != 1 ] && [ "$size" -gt "$ALL_ACTIVE_COUNT" ]; then
            log "size $size exceeds the $ALL_ACTIVE_COUNT market(s) the venue lists; rung skipped"
            continue
        fi
        if ! slug_file_for_size "$size"; then
            log "no pinned set for size $size; rung $lang-$size skipped"
            continue
        fi
        run_rung "$lang" "$size" "$RUNG_SLUG_FILE" "$(duration_for_size "$size")" || true
    done
done

assemble_report

if [ -n "$ABORT_REASON" ]; then
    echo "run_ladder.sh: $ABORT_REASON" >&2
    exit 1
fi
log "ladder complete"
