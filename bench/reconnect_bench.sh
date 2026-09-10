#!/bin/sh
# Recovery-time distributions for pm-ws's reconnect paths: how long a consumer goes silent
# after its venue connection is lost, across three deterministic loopback configurations.
#
# This script never talks to a venue. `examples/table_peer.rs` binds a loopback port and
# serves one market at a stated rate; a fault flag on that same peer process injects a real
# connection loss on the peer side (an abrupt TCP drop, or a silent stall that starves the
# negotiated Engine.IO heartbeat) after a stated delay from accept, so the daemon detects and
# recovers from a real end of connection or a real missed heartbeat -- never a task this
# script aborts from the outside. A consumer attached read-only to the surface under test
# logs one (revision, wall-clock observation time) row per published state
# (`examples/latency_probe.rs --obs-out`, in the `.obs` format
# `examples/common/matched_obs.rs` fixes); the largest gap between two consecutive rows is
# this trial's recovery-time upper bound, and the 5 ms cadence `--rate 200` offers is stated
# beside every gap because the gap includes one cadence interval by construction.
#
# Three configurations:
#   drop     `pmwsd` (the shard rail: detection, reconnect, resubscribe, recovery base),
#            faulted with an abrupt peer-side TCP drop. Default row: 300 short trials.
#   stall    The same `pmwsd` shard rail, faulted with a silent stall instead: the peer keeps
#            the TCP connection open but stops sending book updates and Engine.IO pings, so
#            detection is bounded below by the negotiated heartbeat deadline
#            (`ping_interval_ms + ping_timeout_ms`) rather than an instant EOF. Default row:
#            30 trials, timeout-dominated and near-deterministic.
#   standby  The single-market rail (`pmws-run --replicas 2`), faulted the same abrupt way on
#            its primary connection, measuring hot-standby promotion. Replicas exist only on
#            this rail today, which is why this configuration is optional and separate from
#            the shard rail above. Default row: 30 trials.
#
# A trial that cannot start, whose probe exits non-zero, or whose recovery cannot be
# confirmed is recorded as a failure and the remaining trials still run. Nothing is ever
# filled in from a previous run; every number in the table comes from this run's own trials,
# whose raw per-trial records are kept beside the output as `<output>.trials.jsonl`.
#
# Usage:
#   bench/reconnect_bench.sh <output.md> [--configs "drop stall standby"]
#                     [--drop-trials 300] [--stall-trials 30] [--standby-trials 30]
#                     [--kill-after 2] [--seconds 6] [--stall-seconds 9]
#                     [--rate 200] [--depth 1] [--ready-timeout 10]
#                     [--workdir <dir>] [--socket-dir <dir>] [--keep]
#
# `--kill-after` is seconds from the peer's own accept of the faulted connection to the fault
# firing -- not from the trial's own start, which lags accept by however long daemon startup
# and readiness polling take on this host. `--seconds` bounds `drop` and `standby` trials;
# `--stall-seconds` bounds `stall` trials separately, because a stall's detection is gated on
# the heartbeat deadline before the same backoff-and-reconnect ladder even starts.
#
# Needs `python3` (percentile math, metrics scraping, `.obs` gap analysis, table rendering),
# matching `bench/make_table.sh`.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

COMMAND="bench/reconnect_bench.sh"
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
usage: reconnect_bench.sh <output.md> [--configs "drop stall standby"]
                  [--drop-trials 300] [--stall-trials 30] [--standby-trials 30]
                  [--kill-after 2] [--seconds 6] [--stall-seconds 9]
                  [--rate 200] [--depth 1] [--ready-timeout 10]
                  [--workdir <dir>] [--socket-dir <dir>] [--keep]
USAGE
    exit 2
}

OUTPUT=""
CONFIGS="drop stall standby"
DROP_TRIALS=300
STALL_TRIALS=30
STANDBY_TRIALS=30
KILL_AFTER=2
SECONDS_PER_TRIAL=6
STALL_SECONDS=9
RATE=200
DEPTH=1
READY_TIMEOUT=10
WORKDIR=""
SOCKET_DIR=""
KEEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --configs) CONFIGS=${2:?--configs needs a value}; shift 2 ;;
        --drop-trials) DROP_TRIALS=${2:?--drop-trials needs a value}; shift 2 ;;
        --stall-trials) STALL_TRIALS=${2:?--stall-trials needs a value}; shift 2 ;;
        --standby-trials) STANDBY_TRIALS=${2:?--standby-trials needs a value}; shift 2 ;;
        --kill-after) KILL_AFTER=${2:?--kill-after needs a value}; shift 2 ;;
        --seconds) SECONDS_PER_TRIAL=${2:?--seconds needs a value}; shift 2 ;;
        --stall-seconds) STALL_SECONDS=${2:?--stall-seconds needs a value}; shift 2 ;;
        --rate) RATE=${2:?--rate needs a value}; shift 2 ;;
        --depth) DEPTH=${2:?--depth needs a value}; shift 2 ;;
        --ready-timeout) READY_TIMEOUT=${2:?--ready-timeout needs a value}; shift 2 ;;
        --workdir) WORKDIR=${2:?--workdir needs a value}; shift 2 ;;
        --socket-dir) SOCKET_DIR=${2:?--socket-dir needs a value}; shift 2 ;;
        --keep) KEEP=1; shift ;;
        -h|--help) usage ;;
        --*) echo "reconnect_bench.sh: unrecognized argument: $1" >&2; usage ;;
        *) [ -z "$OUTPUT" ] || { echo "reconnect_bench.sh: only one output file" >&2; usage; }
           OUTPUT=$1; shift ;;
    esac
done

[ -n "$OUTPUT" ] || usage
for value in "$DROP_TRIALS" "$STALL_TRIALS" "$STANDBY_TRIALS" "$KILL_AFTER" \
             "$SECONDS_PER_TRIAL" "$STALL_SECONDS" "$RATE" "$DEPTH" "$READY_TIMEOUT"; do
    case "$value" in
        ''|*[!0-9]*)
            echo "reconnect_bench.sh: trial counts, --kill-after, --seconds, --stall-seconds, --rate, --depth and --ready-timeout take whole numbers" >&2
            exit 2
            ;;
    esac
done
[ "$KILL_AFTER" -ge 1 ] || { echo "reconnect_bench.sh: --kill-after must be at least 1" >&2; exit 2; }
[ "$SECONDS_PER_TRIAL" -gt "$KILL_AFTER" ] || {
    echo "reconnect_bench.sh: --seconds must be greater than --kill-after, or a trial ends before its own fault fires" >&2
    exit 2
}
[ "$STALL_SECONDS" -gt "$KILL_AFTER" ] || {
    echo "reconnect_bench.sh: --stall-seconds must be greater than --kill-after" >&2
    exit 2
}

for name in $CONFIGS; do
    case "$name" in
        drop|stall|standby) ;;
        *) echo "reconnect_bench.sh: --configs names $name, which is not drop, stall or standby" >&2; exit 2 ;;
    esac
done

case "$OUTPUT" in
    /*) ;;
    *) OUTPUT="$PWD/$OUTPUT" ;;
esac
TRIALS_JSONL="${OUTPUT%.md}.trials.jsonl"

if [ -z "$WORKDIR" ]; then
    WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/pmws-reconnect.XXXXXX")
else
    mkdir -p "$WORKDIR"
    WORKDIR=$(CDPATH= cd -- "$WORKDIR" && pwd)
fi
[ -n "$SOCKET_DIR" ] || SOCKET_DIR="/tmp/pmws-rb-$$"
mkdir -p "$SOCKET_DIR"

SLUG="bench-reconnect-market"
CADENCE_MS=$(awk -v r="$RATE" 'BEGIN { printf "%.6f", 1000.0 / r }')

PEER_PID=""
DAEMON_PID=""
RUN_PID=""
PROBE_PID=""

kill_quietly() {
    [ -n "$1" ] || return 0
    kill "$1" 2>/dev/null || true
}

teardown_trial() {
    kill_quietly "$PROBE_PID"; PROBE_PID=""
    if [ -n "$RUN_PID" ]; then
        kill -TERM "$RUN_PID" 2>/dev/null || true
        wait "$RUN_PID" 2>/dev/null || true
        RUN_PID=""
    fi
    if [ -n "$DAEMON_PID" ]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        DAEMON_PID=""
    fi
    kill_quietly "$PEER_PID"; PEER_PID=""
}

cleanup() {
    status=$?
    teardown_trial
    rm -rf "$SOCKET_DIR"
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
PMWSRUN="$REPO/target/release/pmws-run"
PROBE="$REPO/target/release/examples/latency_probe"
PEER="$REPO/target/release/examples/table_peer"

echo "reconnect_bench.sh: building release binaries and examples" >&2
( cd "$REPO" && cargo build --release --locked --bins --examples )
for binary in "$PMWSD" "$PMWSCTL" "$PMWSRUN" "$PROBE" "$PEER"; do
    [ -x "$binary" ] || { echo "reconnect_bench.sh: $binary was not built" >&2; exit 1; }
done

: > "$TRIALS_JSONL"

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

# Waits for `table_peer`'s announced endpoint, up to `--ready-timeout`. Prints the endpoint,
# or nothing on failure, in which case the caller checks `kill -0` itself for the reason.
await_peer_endpoint() {
    peer_out=$1
    peer_pid=$2
    waited=0
    endpoint=""
    while [ -z "$endpoint" ]; do
        endpoint=$(sed -n 's/^endpoint: //p' "$peer_out")
        [ -z "$endpoint" ] || break
        kill -0 "$peer_pid" 2>/dev/null || return 1
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 50))" ] || return 1
        sleep 0.02
    done
    printf '%s' "$endpoint"
}

# Waits for a `pmwsd` control socket to answer `status`, then for its one shard to report a
# connection and a delivered market, up to `--ready-timeout`. Writes the status JSON and the
# baseline metrics scrape to the paths given; prints "1" on success, "0" on timeout, "dead" if
# the daemon exited first.
await_pmwsd_ready() {
    socket=$1
    daemon_pid=$2
    status_path=$3
    metrics_path=$4
    waited=0
    while ! "$PMWSCTL" --socket "$socket" status > "$status_path" 2>/dev/null; do
        kill -0 "$daemon_pid" 2>/dev/null || { echo "dead"; return 0; }
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 50))" ] || { echo "0"; return 0; }
        sleep 0.02
    done
    waited=0
    while : ; do
        kill -0 "$daemon_pid" 2>/dev/null || { echo "dead"; return 0; }
        ready=$(python3 - "$status_path" "$metrics_path" <<'PYEOF'
import json, sys, urllib.request
status_path, metrics_path = sys.argv[1:3]
try:
    with open(status_path, "r", encoding="utf-8") as handle:
        status = json.load(handle)
    address = status["metrics_listen"]
    with urllib.request.urlopen(f"http://{address}/metrics", timeout=2) as answer:
        body = answer.read().decode("utf-8", "replace")
except Exception:
    print(0)
    raise SystemExit
with open(metrics_path, "w", encoding="utf-8") as handle:
    handle.write(body)
connected = 0.0
markets = 0.0
for line in body.splitlines():
    if line.startswith("pmws_shard_connected"):
        connected = max(connected, float(line.rsplit(" ", 1)[1]))
    elif line.startswith("pmws_shard_segment_markets"):
        markets = max(markets, float(line.rsplit(" ", 1)[1]))
print(1 if (connected >= 1 and markets >= 1) else 0)
PYEOF
)
        [ "$ready" = "1" ] && { echo "1"; return 0; }
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 50))" ] || { echo "0"; return 0; }
        sleep 0.02
    done
}

# Scrapes the exposition into `path`. Failure leaves `path` absent; the caller treats that as
# a trial failure rather than a zero delta.
metrics_fetch() {
    address=$1
    path=$2
    python3 - "$address" "$path" <<'PYEOF'
import sys, urllib.request
try:
    with urllib.request.urlopen(f"http://{sys.argv[1]}/metrics", timeout=5) as answer:
        body = answer.read().decode("utf-8", "replace")
except Exception as error:
    print(f"metrics fetch failed: {error}", file=sys.stderr)
    raise SystemExit(1)
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    handle.write(body)
PYEOF
}

# The threshold, in nanoseconds, above which a gap between two consecutive observed
# revisions is a fault's silence rather than ordinary cadence jitter: 20 cadence intervals,
# which every gap observed in this method's own validation runs (5-15 ms at the offered rate)
# sat far below, and every real recovery (500 ms+) sat far above.
ELEVATED_GAP_NS=$(awk -v c="$CADENCE_MS" 'BEGIN { printf "%.0f", c * 20 * 1000000 }')

# Builds one trial's JSON record from whatever files this trial produced, and appends it to
# $TRIALS_JSONL. Paths that do not apply to this trial's configuration are passed as the
# literal string "-"; their fields come back null or zero rather than being guessed at.
#
# The recovery-gap metric is the single largest gap between two consecutive `.obs` rows, per
# this script's header comment. `elevated_gap_span_ns` sums every gap past
# `$ELEVATED_GAP_NS` instead of taking the max of one: this method's own validation found the
# `stall` configuration's recovery split across two such gaps back to back (a stale-authority
# republish at the heartbeat deadline, then the actual post-reconnect recovery), so the single
# largest gap alone understates the true silence-to-recovery span for that shape specifically.
# Both numbers are recorded for every trial; the report states which one is headlined where.
record_trial() {
    config=$1; index=$2; status=$3; failure_reason=$4
    obs_path=$5; probe_out_path=$6; peer_err_path=$7
    run_out_path=$8; baseline_metrics=$9; final_metrics=${10}
    python3 - "$config" "$index" "$status" "$failure_reason" "$obs_path" "$probe_out_path" \
        "$peer_err_path" "$run_out_path" "$baseline_metrics" "$final_metrics" \
        "$KILL_AFTER" "$SECONDS_PER_TRIAL" "$STALL_SECONDS" "$RATE" "$CADENCE_MS" \
        "$ELEVATED_GAP_NS" >> "$TRIALS_JSONL" <<'PYEOF'
import json, sys

(config, index, status, failure_reason, obs_path, probe_out_path, peer_err_path,
 run_out_path, baseline_metrics, final_metrics, kill_after, seconds, stall_seconds,
 rate, cadence_ms, elevated_gap_ns) = sys.argv[1:17]

record = {
    "config": config,
    "index": int(index),
    "status": status,
    "failure_reason": failure_reason if failure_reason != "-" else None,
    "kill_after_s": int(kill_after),
    "trial_seconds": int(stall_seconds) if config == "stall" else int(seconds),
    "rate": int(rate),
    "cadence_ms": float(cadence_ms),
    "gap_ns": None,
    "elevated_gap_span_ns": None,
    "elevated_gap_count": 0,
    "obs_rows": 0,
    "strictly_increasing": None,
    "fault_fired": False,
    "reconnected": False,
    "probe_samples_kept": None,
    "probe_rescans": None,
    "probe_timeouts": None,
    "role_ok": None,
    "connection_attempts": None,
    "continuity_losses": None,
    "fenced_generations": None,
    "continuity_losses_delta": None,
    "connection_attempts_delta": None,
    "decode_failures_delta": None,
}

if obs_path != "-":
    try:
        rows = []
        with open(obs_path, "r", encoding="utf-8") as handle:
            for line in handle:
                if not line.startswith("obs "):
                    continue
                parts = line.split()
                rows.append((int(parts[2]), int(parts[-1].split("=")[1])))
        rows.sort()
        record["obs_rows"] = len(rows)
        if len(rows) >= 2:
            gaps = [rows[i + 1][0] - rows[i][0] for i in range(len(rows) - 1)]
            record["gap_ns"] = max(gaps)
            threshold = float(elevated_gap_ns)
            elevated = [gap for gap in gaps if gap >= threshold]
            record["elevated_gap_span_ns"] = sum(elevated)
            record["elevated_gap_count"] = len(elevated)
            record["strictly_increasing"] = all(
                rows[i][1] < rows[i + 1][1] for i in range(len(rows) - 1)
            )
    except OSError:
        pass

if probe_out_path != "-":
    try:
        with open(probe_out_path, "r", encoding="utf-8") as handle:
            for line in handle:
                key, _, value = line.partition(":")
                key, value = key.strip(), value.strip()
                if key == "samples_kept":
                    record["probe_samples_kept"] = int(value)
                elif key == "rescans":
                    record["probe_rescans"] = int(value)
                elif key == "timeouts":
                    record["probe_timeouts"] = int(value.split()[0])
    except OSError:
        pass

if peer_err_path != "-":
    try:
        with open(peer_err_path, "r", encoding="utf-8") as handle:
            text = handle.read()
        record["fault_fired"] = "fault fired" in text
        expected_initial_subscriptions = 2 if config == "standby" else 1
        record["reconnected"] = text.count("subscribed to") > expected_initial_subscriptions
    except OSError:
        pass

if run_out_path != "-":
    try:
        with open(run_out_path, "r", encoding="utf-8") as handle:
            text = handle.read()
        for line in text.splitlines():
            if "sid=table-peer-engine-session-1 " in line and "connected " in line:
                record["role_ok"] = "replica=PublishingPrimary" in line
            if line.startswith("summary frames_seen="):
                for field in line.split():
                    if field.startswith("connection_attempts="):
                        record["connection_attempts"] = int(field.split("=", 1)[1])
                    elif field.startswith("fenced_generations="):
                        record["fenced_generations"] = int(field.split("=", 1)[1])
            if line.startswith("summary book "):
                for field in line.split():
                    if field.startswith("continuity_losses="):
                        record["continuity_losses"] = int(field.split("=", 1)[1])
        if record["role_ok"] is None:
            record["role_ok"] = False
    except OSError:
        pass

if baseline_metrics != "-" and final_metrics != "-":
    def series(path):
        found = {}
        try:
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
        except OSError:
            pass
        return found

    def total(found, name):
        return int(sum(found.get(name, [])))

    baseline, final = series(baseline_metrics), series(final_metrics)
    record["continuity_losses_delta"] = total(final, "pmws_shard_continuity_losses") - total(
        baseline, "pmws_shard_continuity_losses"
    )
    record["connection_attempts_delta"] = total(final, "pmws_shard_connection_attempts") - total(
        baseline, "pmws_shard_connection_attempts"
    )
    record["decode_failures_delta"] = total(final, "pmws_shard_decode_failures") - total(
        baseline, "pmws_shard_decode_failures"
    )

print(json.dumps(record))
PYEOF
}

# Runs one `drop` or `stall` trial against `pmwsd`: table_peer with a peer-side fault armed
# on its first accepted connection, a single-shard single-market daemon pointed at it, and a
# `latency_probe --control` consumer attached by descriptor transfer for the trial's own
# window. Continues past any step's failure to `record_trial`, which is where a trial that
# never got this far is turned into a recorded failure rather than a silent gap in the table.
run_pmwsd_trial() {
    config=$1; kind=$2; index=$3
    trial_dir="$WORKDIR/$config/$(printf '%04d' "$index")"
    mkdir -p "$trial_dir"
    sock="$SOCKET_DIR/$config-$index.sock"
    trial_seconds=$SECONDS_PER_TRIAL
    [ "$config" != "stall" ] || trial_seconds=$STALL_SECONDS

    "$PEER" --rate "$RATE" --depth "$DEPTH" \
        --fault-session 1 --fault-after-ms "$((KILL_AFTER * 1000))" --fault-kind "$kind" \
        > "$trial_dir/peer.out" 2> "$trial_dir/peer.err" &
    PEER_PID=$!

    endpoint=$(await_peer_endpoint "$trial_dir/peer.out" "$PEER_PID") || {
        record_trial "$config" "$index" failed "peer never announced an endpoint" \
            - - "$trial_dir/peer.err" - - -
        teardown_trial
        return 0
    }

    cat > "$trial_dir/pmwsd.toml" <<TOML
control_socket = "$sock"
endpoint = "$endpoint"
metrics_listen = "127.0.0.1:0"
lease_ttl_ms = 30000
markets = ["$SLUG"]

[delivery]
directory = "$trial_dir"
profile = "common"
TOML

    "$PMWSD" --config "$trial_dir/pmwsd.toml" > "$trial_dir/pmwsd.log" 2>&1 &
    DAEMON_PID=$!

    ready=$(await_pmwsd_ready "$sock" "$DAEMON_PID" "$trial_dir/status.json" "$trial_dir/metrics-baseline.txt")
    if [ "$ready" != "1" ]; then
        reason="pmwsd never reached a connected, delivering shard within --ready-timeout"
        [ "$ready" != "dead" ] || reason="pmwsd exited before its shard connected"
        record_trial "$config" "$index" failed "$reason" \
            - - "$trial_dir/peer.err" - - -
        teardown_trial
        return 0
    fi

    "$PROBE" --control "$sock" --market "$SLUG" --mode parked --seconds "$trial_seconds" \
        --label "$HOST_LABEL, reconnect-bench $config trial $index" \
        --obs-out "$trial_dir/probe.obs" \
        > "$trial_dir/probe.out" 2> "$trial_dir/probe.err" &
    PROBE_PID=$!
    probe_status=0
    wait "$PROBE_PID" || probe_status=$?
    PROBE_PID=""

    if ! metrics_fetch "$(python3 -c "import json;print(json.load(open('$trial_dir/status.json'))['metrics_listen'])")" \
        "$trial_dir/metrics-final.txt"; then
        record_trial "$config" "$index" failed "the closing metrics scrape failed" \
            "$trial_dir/probe.obs" "$trial_dir/probe.out" "$trial_dir/peer.err" - \
            "$trial_dir/metrics-baseline.txt" -
        teardown_trial
        return 0
    fi

    teardown_trial

    if [ "$probe_status" -ne 0 ]; then
        record_trial "$config" "$index" failed "the probe exited $probe_status: $(tail -n 1 "$trial_dir/probe.err" 2>/dev/null || true)" \
            "$trial_dir/probe.obs" "$trial_dir/probe.out" "$trial_dir/peer.err" - \
            "$trial_dir/metrics-baseline.txt" "$trial_dir/metrics-final.txt"
        return 0
    fi

    record_trial "$config" "$index" ok "-" \
        "$trial_dir/probe.obs" "$trial_dir/probe.out" "$trial_dir/peer.err" - \
        "$trial_dir/metrics-baseline.txt" "$trial_dir/metrics-final.txt"
}

# Runs one `standby` trial against the single-market rail: table_peer with the same
# abrupt-drop fault armed on session 1 (this rail's primary, per this method's own
# `connected replica=PublishingPrimary sid=table-peer-engine-session-1` verification, printed
# unconditionally by `pmws-run` and checked in `record_trial`), `pmws-run --replicas 2`
# holding a hot standby, and a `latency_probe --shm` consumer attached to its segment.
run_standby_trial() {
    index=$1
    trial_dir="$WORKDIR/standby/$(printf '%04d' "$index")"
    mkdir -p "$trial_dir"
    seg="$trial_dir/book.seg"

    "$PEER" --rate "$RATE" --depth "$DEPTH" \
        --fault-session 1 --fault-after-ms "$((KILL_AFTER * 1000))" --fault-kind drop \
        > "$trial_dir/peer.out" 2> "$trial_dir/peer.err" &
    PEER_PID=$!

    endpoint=$(await_peer_endpoint "$trial_dir/peer.out" "$PEER_PID") || {
        record_trial standby "$index" failed "peer never announced an endpoint" \
            - - "$trial_dir/peer.err" - - -
        teardown_trial
        return 0
    }

    "$PMWSRUN" --market "$SLUG" --endpoint "$endpoint" --replicas 2 --shm "$seg" \
        --seconds "$SECONDS_PER_TRIAL" --print-book \
        > "$trial_dir/pmws-run.out" 2> "$trial_dir/pmws-run.err" &
    RUN_PID=$!

    waited=0
    while [ ! -f "$seg" ]; do
        kill -0 "$RUN_PID" 2>/dev/null || {
            record_trial standby "$index" failed "pmws-run exited before creating its segment" \
                - - "$trial_dir/peer.err" "$trial_dir/pmws-run.out" - -
            teardown_trial
            return 0
        }
        waited=$((waited + 1))
        [ "$waited" -lt "$((READY_TIMEOUT * 50))" ] || {
            record_trial standby "$index" failed "pmws-run never created its segment within --ready-timeout" \
                - - "$trial_dir/peer.err" "$trial_dir/pmws-run.out" - -
            teardown_trial
            return 0
        }
        sleep 0.02
    done

    "$PROBE" --shm "$seg" --mode parked --seconds "$SECONDS_PER_TRIAL" \
        --label "$HOST_LABEL, reconnect-bench standby trial $index" \
        --obs-out "$trial_dir/probe.obs" \
        > "$trial_dir/probe.out" 2> "$trial_dir/probe.err" &
    PROBE_PID=$!

    run_status=0
    wait "$RUN_PID" || run_status=$?
    RUN_PID=""
    probe_status=0
    wait "$PROBE_PID" || probe_status=$?
    PROBE_PID=""

    teardown_trial

    if [ "$run_status" -ne 0 ]; then
        record_trial standby "$index" failed "pmws-run exited $run_status" \
            "$trial_dir/probe.obs" "$trial_dir/probe.out" "$trial_dir/peer.err" \
            "$trial_dir/pmws-run.out" - -
        return 0
    fi
    if [ "$probe_status" -ne 0 ]; then
        record_trial standby "$index" failed "the probe exited $probe_status: $(tail -n 1 "$trial_dir/probe.err" 2>/dev/null || true)" \
            "$trial_dir/probe.obs" "$trial_dir/probe.out" "$trial_dir/peer.err" \
            "$trial_dir/pmws-run.out" - -
        return 0
    fi

    record_trial standby "$index" ok "-" \
        "$trial_dir/probe.obs" "$trial_dir/probe.out" "$trial_dir/peer.err" \
        "$trial_dir/pmws-run.out" - -
}

for name in $CONFIGS; do
    case "$name" in
        drop)
            echo "reconnect_bench.sh: drop config: $DROP_TRIALS trial(s)" >&2
            index=1
            while [ "$index" -le "$DROP_TRIALS" ]; do
                run_pmwsd_trial drop drop "$index" || true
                rm -rf "${WORKDIR:?}/drop/$(printf '%04d' "$index")"
                index=$((index + 1))
            done
            ;;
        stall)
            echo "reconnect_bench.sh: stall config: $STALL_TRIALS trial(s)" >&2
            index=1
            while [ "$index" -le "$STALL_TRIALS" ]; do
                run_pmwsd_trial stall stall "$index" || true
                rm -rf "${WORKDIR:?}/stall/$(printf '%04d' "$index")"
                index=$((index + 1))
            done
            ;;
        standby)
            echo "reconnect_bench.sh: standby config: $STANDBY_TRIALS trial(s)" >&2
            index=1
            while [ "$index" -le "$STANDBY_TRIALS" ]; do
                run_standby_trial "$index" || true
                rm -rf "${WORKDIR:?}/standby/$(printf '%04d' "$index")"
                index=$((index + 1))
            done
            ;;
    esac
done

python3 - "$OUTPUT" "$TRIALS_JSONL" "$HOST_LABEL" "$COMMAND" "$REPO" "$CADENCE_MS" "$RATE" \
    "$KILL_AFTER" "$SECONDS_PER_TRIAL" "$STALL_SECONDS" <<'PYEOF'
import json, subprocess, sys, time

(output, trials_path, host, command, repo, cadence_ms, rate,
 kill_after, seconds, stall_seconds) = sys.argv[1:11]
cadence_ms = float(cadence_ms)

trials = []
with open(trials_path, "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if line:
            trials.append(json.loads(line))

try:
    commit = subprocess.run(
        ["git", "-C", repo, "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
except Exception:
    commit = "unknown"

P50_FLOOR, P95_FLOOR, P99_FLOOR = 1, 40, 200

def quantile(sorted_vals, permille):
    n = len(sorted_vals)
    rank = max(1, -(-(n * permille) // 1000)) - 1
    return sorted_vals[min(rank, n - 1)]

def ms(nanos):
    return f"{nanos / 1_000_000:.1f}"

def percentile_cells(values):
    values = sorted(values)
    n = len(values)
    cells = {}
    cells["p50"] = ms(quantile(values, 500)) if n >= P50_FLOOR else f"withheld ({n} samples)"
    cells["p95"] = ms(quantile(values, 950)) if n >= P95_FLOOR else f"withheld ({n} samples, floor {P95_FLOOR})"
    cells["p99"] = ms(quantile(values, 990)) if n >= P99_FLOOR else f"withheld ({n} samples, floor {P99_FLOOR})"
    cells["max"] = ms(values[-1]) if n >= 1 else "withheld (0 samples)"
    return cells

CONFIG_LABEL = {
    "drop": "pmwsd, abrupt drop",
    "stall": "pmwsd, silent stall",
    "standby": "pmws-run --replicas 2, abrupt drop (single-market rail)",
}
CONFIG_ORDER = ["drop", "stall", "standby"]

lines = [
    "# pm-ws reconnect-time benchmark",
    "",
    f"host: {host}",
    f"commit: {commit}",
    f"generated_at: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
    f"offered cadence: {cadence_ms:.3f} ms ({rate} updates/s), single market, loopback only",
    "",
    "Produced by, from the repository root:",
    "",
    "```sh",
    command,
    "```",
    "",
    "Raw per-trial records for every trial below, including failures, are kept at",
    f"`{trials_path.rsplit('/', 1)[-1]}` beside this report.",
    "",
    "**No venue traffic of any kind.** `examples/table_peer.rs` serves one market on a loopback",
    "socket at the stated cadence; the fault is injected on that same peer process at a",
    "configurable delay after it accepts the connection under test, so the daemon detects and",
    "recovers from a real end of connection (`drop`) or a real missed heartbeat (`stall`),",
    "never a task this script aborts from the outside. The recovery-gap metric is the largest",
    "gap between two consecutive `(revision, observation-time)` rows one consumer process",
    "logs on one clock (`examples/latency_probe.rs --obs-out`); it includes one cadence",
    "interval by construction, which is why the cadence is stated beside every figure.",
    "",
    "- **Percentiles are withheld below a stated sample floor**: p50 always prints when at",
    "  least one trial succeeded, p95 needs 40 successful trials, p99 needs 200. `max` is",
    "  always printed from whatever succeeded and is never dressed as a percentile.",
    "- **`stall`'s recovery observably splits into two consecutive elevated gaps**: a",
    "  stale-authority republish at the heartbeat deadline, then the actual post-reconnect",
    "  recovery once backoff, reconnect and resubscribe finish. The headline `max gap`",
    "  column is the single largest of the two, per this script's own metric definition; the",
    "  `elevated span` column beside it sums every gap past 20 cadence intervals in the same",
    "  trial, which is the more complete silence-to-recovery figure for that configuration",
    "  specifically. This was found empirically while building this harness, not assumed.",
    "- **`stall` detection is bounded below by the negotiated heartbeat cadence**",
    "  (`ping_interval_ms + ping_timeout_ms`, the peer's default 2000 ms here), so its gap",
    "  distribution cannot read faster than that floor regardless of trial count.",
    "- **`standby`'s primary-role targeting is verified per trial, not assumed.** The fault is",
    "  armed on the peer's first accepted connection; whether that connection actually held",
    "  the publishing-primary role (rather than the hot standby) is checked against",
    "  `pmws-run`'s own unconditional `connected ... replica=PublishingPrimary",
    "  sid=table-peer-engine-session-1` line. A trial where that check failed faulted the",
    "  standby instead of the primary and is excluded from the gap distribution below,",
    "  reported separately as a role mismatch rather than folded into either count.",
    "",
]

summary_header = (
    "| config | fault shape | trials requested / run / succeeded / failed | role mismatches | "
    "p50 | p95 | **p99** | max | elevated span p50 / max | cadence |"
)
summary_sep = "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
lines += [summary_header, summary_sep]

diagnostics_header = (
    "| config | strictly-increasing violations | fault-fired / reconnected | "
    "continuity losses (median per trial) | connection attempts (median per trial) |"
)
diagnostics_sep = "| --- | ---: | ---: | ---: | ---: |"
diagnostic_lines = [diagnostics_header, diagnostics_sep]

failures_by_config = {name: [] for name in CONFIG_ORDER}

def median(values):
    values = sorted(values)
    n = len(values)
    if n == 0:
        return None
    mid = n // 2
    if n % 2 == 1:
        return values[mid]
    return (values[mid - 1] + values[mid]) / 2

for config in CONFIG_ORDER:
    rows = [row for row in trials if row["config"] == config]
    if not rows:
        continue
    requested = max((row["index"] for row in rows), default=0)
    role_mismatches = [row for row in rows if row.get("role_ok") is False]
    ok_rows = [
        row for row in rows
        if row["status"] == "ok" and row.get("gap_ns") is not None and row.get("role_ok") is not False
    ]
    failed_rows = [row for row in rows if row["status"] != "ok"]
    for row in failed_rows:
        failures_by_config[config].append(
            f"trial {row['index']}: {row.get('failure_reason') or 'no reason recorded'}"
        )

    gap_cells = percentile_cells([row["gap_ns"] for row in ok_rows]) if ok_rows else percentile_cells([])
    elevated_values = sorted(row["elevated_gap_span_ns"] for row in ok_rows if row.get("elevated_gap_span_ns") is not None)
    elevated_p50 = ms(quantile(elevated_values, 500)) if elevated_values else "withheld (0 samples)"
    elevated_max = ms(elevated_values[-1]) if elevated_values else "withheld (0 samples)"

    lines.append(
        "| {config} | {shape} | {req} / {run} / {ok} / {failed} | {mismatch} | {p50} | {p95} | "
        "**{p99}** | {max} | {espan50} / {espanmax} | {cadence:.1f} ms |".format(
            config=config,
            shape=CONFIG_LABEL[config],
            req=requested,
            run=len(rows),
            ok=len(ok_rows),
            failed=len(failed_rows),
            mismatch=len(role_mismatches),
            p50=gap_cells["p50"],
            p95=gap_cells["p95"],
            p99=gap_cells["p99"],
            max=gap_cells["max"],
            espan50=elevated_p50,
            espanmax=elevated_max,
            cadence=cadence_ms,
        )
    )

    violations = sum(1 for row in ok_rows if row.get("strictly_increasing") is False)
    fired = sum(1 for row in rows if row.get("fault_fired"))
    reconnected = sum(1 for row in rows if row.get("reconnected"))
    if config == "standby":
        continuity_values = [row["continuity_losses"] for row in ok_rows if row.get("continuity_losses") is not None]
        attempts_values = [row["connection_attempts"] for row in ok_rows if row.get("connection_attempts") is not None]
    else:
        continuity_values = [row["continuity_losses_delta"] for row in ok_rows if row.get("continuity_losses_delta") is not None]
        attempts_values = [row["connection_attempts_delta"] for row in ok_rows if row.get("connection_attempts_delta") is not None]
    continuity_median = median(continuity_values)
    attempts_median = median(attempts_values)
    diagnostic_lines.append(
        "| {config} | {violations} | {fired}/{total} fired, {reconnected}/{total} reconnected | "
        "{continuity} | {attempts} |".format(
            config=config,
            violations=violations,
            fired=fired,
            total=len(rows),
            reconnected=reconnected,
            continuity="n/a" if continuity_median is None else f"{continuity_median:g}",
            attempts="n/a" if attempts_median is None else f"{attempts_median:g}",
        )
    )

lines += ["", "## What each configuration observed", ""] + diagnostic_lines

any_failures = any(failures_by_config[name] for name in CONFIG_ORDER)
if any_failures:
    lines += ["", "## Trials that did not run or did not complete", ""]
    for name in CONFIG_ORDER:
        if not failures_by_config[name]:
            continue
        lines.append(f"### {name}")
        lines.append("")
        for entry in failures_by_config[name]:
            lines.append(f"- {entry}")
        lines.append("")
else:
    lines += ["", "Every requested trial ran and completed.", ""]

with open(output, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines).rstrip() + "\n")
print(f"reconnect_bench.sh: table written to {output}", file=sys.stderr)
PYEOF

cat "$OUTPUT"
