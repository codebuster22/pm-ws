#!/usr/bin/env python3
"""The S8c `py-sdk` leg: the official Limitless Python SDK (`limitless-sdk==1.1.0`) consumed
standalone, outside pm-ws's own dependency graph, per `bench/sdk-harness/README.md`.

Connects one `limitless_sdk.websocket.WebSocketClient` to the venue's `/markets` Socket.IO
namespace, subscribes every pinned slug in one `subscribe_market_prices` call (a second
subscribe call would replace the first, per venue semantics -- this leg never issues one),
and times every `orderbookUpdate` event against the boundary `bench/sdk-harness/README.md`
defines for SDK legs: inside the callback, after the update is stored into this leg's own
slug -> book map, before anything else. `time.time_ns()` reads `CLOCK_REALTIME` directly, the
same clock domain `examples/bench_consumer.py` reads on this same host.

The venue's `orderbookUpdate` payload (`limitless_sdk.websocket.types.OrderbookUpdate`) is
`{"marketSlug": str, "orderbook": {"bids": [{"price": float, "size": float}, ...], "asks":
[...], "tokenId": str, "adjustedMidpoint": float, "maxSpread": float, "minSize": float},
"timestamp": ...}`; each book is the full resting depth, not a delta, so this leg's own
"minimal book handling" is a bare overwrite of the previous entry in its slug -> book map.
Bid/ask entries are read defensively (a mapping with `price`/`size` keys, or a two-element
pair) because the SDK's `OrderbookEntry` is a `TypedDict` -- a plain `dict` at runtime with
no schema enforcement of its own.

Auto-reconnect is left on (venue drops are the daemon's problem to survive, and this leg's
own job is to measure what the SDK delivers, reconnects included) but capped at 5 attempts,
past `docs/limitless.md`'s etiquette: a leg that cannot reach the venue in 5 tries stops
trying rather than hammering it. SIGTERM (and SIGINT, for a local Ctrl-C) end the run early
and take the same flush path `--seconds` elapsing does: disconnect, write the `.obs` file,
print the summary.

Usage:
    sdk_leg.py --slugs <file> --seconds <n> --obs-out <path> --label <text>
               [--endpoint <url>]
    sdk_leg.py --self-test

`--slugs` names a file of one venue-native market slug per line; blank lines and lines
starting with `#` are ignored. `--endpoint` overrides the SDK's own default WebSocket URL
(`wss://ws.limitless.exchange`) and is only ever pointed at the venue itself -- there is no
sandbox to redirect it to. `--self-test` runs the canonical-decimal vectors and one digest
golden value from `bench/sdk-harness/README.md`, plus an import/construction check (a
`WebSocketClient` is built but never connected), and exits without touching the network.
"""

import argparse
import asyncio
import os
import platform
import signal
import sys
import tempfile
import time
from collections import Counter
from decimal import Decimal, InvalidOperation

from limitless_sdk import WebSocketClient, WebSocketConfig

MAX_SECONDS = 86_400
MAX_OBS_ROWS = 4_000_000
MAX_RECONNECT_ATTEMPTS = 5
DEFAULT_RECONNECT_DELAY_SECONDS = 1.0
SUBSCRIBE_CHANNEL = "subscribe_market_prices"
SDK_PIN = "limitless-sdk==1.1.0"


def canonical_decimal(text):
    """The canonical form of a decimal lexeme, per `bench/sdk-harness/README.md`'s Content
    digest section: e-notation expanded to plain decimal first, a leading `+` stripped,
    redundant leading zeros stripped, and -- when a `.` is present -- trailing zeros then a
    trailing `.` stripped. Identical to the copy in `examples/bench_consumer.py`.
    """
    value = text
    if "e" in value or "E" in value:
        value = format(Decimal(value), "f")
    sign = ""
    if value.startswith("+"):
        value = value[1:]
    elif value.startswith("-"):
        sign = "-"
        value = value[1:]
    if "." in value:
        int_part, frac_part = value.split(".", 1)
    else:
        int_part, frac_part = value, None
    int_part = int_part.lstrip("0") or "0"
    if frac_part is not None:
        frac_part = frac_part.rstrip("0")
        value = int_part if frac_part == "" else f"{int_part}.{frac_part}"
    else:
        value = int_part
    return sign + value


def fnv1a_64_hex(data):
    """FNV-1a 64-bit digest of `data` (UTF-8 bytes) as 16 lowercase hex digits. Identical to
    the copy in `examples/bench_consumer.py`.
    """
    digest = 0xCBF29CE484222325
    for byte in data:
        digest ^= byte
        digest = (digest * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return format(digest, "016x")


def digest_book(bids, asks):
    """FNV-1a 64 digest of one book's content. `bids`/`asks` are each an iterable of
    `(price_numeric, price_text, qty_numeric, qty_text)`; zero-quantity levels are excluded,
    bids are ordered by price descending and asks ascending, and the digest input is `B` +
    `price:qty;` per bid + `|A` + `price:qty;` per ask, using canonical decimals. Identical
    to the copy in `examples/bench_consumer.py`.
    """
    kept_bids = sorted(
        (level for level in bids if level[2]), key=lambda level: level[0], reverse=True
    )
    kept_asks = sorted((level for level in asks if level[2]), key=lambda level: level[0])
    parts = ["B"]
    for _, price_text, _, qty_text in kept_bids:
        parts.append(f"{canonical_decimal(price_text)}:{canonical_decimal(qty_text)};")
    parts.append("|A")
    for _, price_text, _, qty_text in kept_asks:
        parts.append(f"{canonical_decimal(price_text)}:{canonical_decimal(qty_text)};")
    return fnv1a_64_hex("".join(parts).encode("utf-8"))


CANONICAL_VECTORS = (
    ("0.530", "0.53"),
    ("1000000.0", "1000000"),
    ("100", "100"),
    ("0.5", "0.5"),
    ("1e-7", "0.0000001"),
    ("0.0", "0"),
)
GOLDEN_BIDS = ((0.61, repr(0.61), 12, repr(12)),)
GOLDEN_ASKS = ((0.62, repr(0.62), 13, repr(13)),)
GOLDEN_DIGEST = "a9c3f0bc66964c0a"


def read_slug_file(path):
    """Every venue-native slug the file names, in file order, without blanks or comments."""
    slugs = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if text and not text.startswith("#"):
                slugs.append(text)
    return slugs


def _extract_levels(entries):
    """Turns one side's raw SDK entries into `digest_book`'s `(price_numeric, price_text,
    qty_numeric, qty_text)` shape, reading each entry defensively: a `{"price", "size"}`
    mapping (the SDK's actual `OrderbookEntry` shape) or a two-element `(price, size)` pair.
    A malformed entry is skipped, never raised on.

    A string value is passed through as its own text unchanged -- a decimal lexeme is exact
    digest input, `repr()` of a string is not (it would wrap it in quotes) -- and parsed
    through `Decimal` for the numeric sort/zero-quantity key; a non-string value is `repr()`'d
    for its text (matching the SDK's actual `float` payload today) and used numerically as
    read. An entry whose price or size cannot be read as a decimal is skipped.
    """
    levels = []
    for entry in entries:
        if isinstance(entry, dict):
            price = entry.get("price")
            qty = entry.get("size")
        elif isinstance(entry, (list, tuple)) and len(entry) >= 2:
            price, qty = entry[0], entry[1]
        else:
            continue
        if price is None or qty is None:
            continue
        price_text = price if isinstance(price, str) else repr(price)
        qty_text = qty if isinstance(qty, str) else repr(qty)
        try:
            price_numeric = Decimal(price_text) if isinstance(price, str) else price
            qty_numeric = Decimal(qty_text) if isinstance(qty, str) else qty
        except InvalidOperation:
            continue
        levels.append((price_numeric, price_text, qty_numeric, qty_text))
    return levels


class RunStats:
    """Everything one run observed, in the order `print_summary` emits it.

    `reconnects` is derived from `connects` (`max(connects - 1, 0)`), not counted directly:
    python-socketio's `AsyncClient` has no `reconnect`/`reconnect_attempt` event of its own --
    its internal `_handle_reconnect` retries silently and a successful attempt simply refires
    `connect` -- so `on_connect` firing more than once is the only observable signal a
    reconnect happened at all. A failed attempt (the SDK gives up after `--max-reconnect-
    attempts`) fires no event this leg can see, so attempts are not reported, only outcomes.
    """

    def __init__(self):
        self.books = {}
        self.events_total = 0
        self.market_counts = Counter()
        self.obs_rows = []
        self.dropped = 0
        self.connects = 0
        self.disconnects = 0
        self.elapsed = 0.0

    @property
    def reconnects(self):
        return max(self.connects - 1, 0)


def register_handlers(client, stats, per_market_seq):
    """Wires the boundary-defining `orderbookUpdate` handler and the connection-lifecycle
    handlers this leg's summary reports on.
    """

    @client.on("orderbookUpdate")
    async def on_orderbook_update(data):
        slug = data.get("marketSlug")
        if slug is None:
            return
        orderbook = data.get("orderbook") or {}
        stats.books[slug] = orderbook
        t_obs = time.time_ns()
        digest = digest_book(
            _extract_levels(orderbook.get("bids") or []),
            _extract_levels(orderbook.get("asks") or []),
        )
        seq = per_market_seq[slug]
        per_market_seq[slug] += 1
        stats.events_total += 1
        stats.market_counts[slug] += 1
        if len(stats.obs_rows) < MAX_OBS_ROWS:
            stats.obs_rows.append((slug, t_obs, digest, seq))
        else:
            stats.dropped += 1

    @client.on("connect")
    async def on_connect():
        stats.connects += 1

    @client.on("disconnect")
    async def on_disconnect():
        stats.disconnects += 1


def build_config(args):
    kwargs = dict(
        auto_reconnect=True,
        reconnect_delay=DEFAULT_RECONNECT_DELAY_SECONDS,
        max_reconnect_attempts=MAX_RECONNECT_ATTEMPTS,
    )
    if args.endpoint:
        kwargs["url"] = args.endpoint
    return WebSocketConfig(**kwargs)


async def run(args):
    slugs = read_slug_file(args.slugs)
    if not slugs:
        raise SystemExit(f"{args.slugs} names no market")

    stats = RunStats()
    per_market_seq = Counter()
    client = WebSocketClient(config=build_config(args), logger=None)
    register_handlers(client, stats, per_market_seq)

    await client.connect()
    try:
        await client.subscribe(SUBSCRIBE_CHANNEL, {"marketSlugs": slugs})

        stop = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            try:
                loop.add_signal_handler(sig, stop.set)
            except (NotImplementedError, RuntimeError):
                pass

        start = time.monotonic()
        try:
            await asyncio.wait_for(stop.wait(), timeout=args.seconds)
        except asyncio.TimeoutError:
            pass
        stats.elapsed = time.monotonic() - start
    finally:
        await client.disconnect()

    write_obs_file(args.obs_out, args.label, len(slugs), stats)
    print_summary(args, len(slugs), stats)
    return 0


def write_obs_file(path, label, size, stats):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("# pmws-obs v1\n")
        handle.write("# leg: py-sdk\n")
        handle.write(f"# host: {label}\n")
        handle.write("# clock: epoch_ns\n")
        handle.write(f"# size: {size}\n")
        handle.write(f"# pin: {SDK_PIN}\n")
        for slug, t_obs, digest, seq in stats.obs_rows:
            handle.write(f"obs {slug} {t_obs} {digest} {seq}\n")
        handle.write(f"# events_total: {stats.events_total}\n")
        handle.write(f"# dropped: {stats.dropped}\n")


def print_summary(args, size, stats):
    print(f"label: {args.label}")
    print("leg: py-sdk")
    print(f"consumer: sdk_leg.py ({SDK_PIN})")
    print(f"runtime: python {platform.python_version()}")
    print("clock: CLOCK_REALTIME epoch nanoseconds, read directly (time.time_ns)")
    print(f"duration_seconds: {stats.elapsed:.3f}")
    print(f"markets_pinned: {size}")
    print(f"events_total: {stats.events_total}")
    rate = stats.events_total / stats.elapsed if stats.elapsed > 0 else 0.0
    print(f"events_per_second: {rate:.3f}")
    print(f"obs_rows_kept: {len(stats.obs_rows)}")
    print(f"dropped: {stats.dropped}")
    print(f"connects: {stats.connects}")
    print(f"disconnects: {stats.disconnects}")
    print(f"reconnects: {stats.reconnects}")
    print("top_markets_by_count:")
    for slug, count in stats.market_counts.most_common(10):
        print(f"  {slug}: {count}")


def _check_obs_file(path, expected_leg, expected_rows, expected_dropped):
    """Asserts one written `.obs` file matches `bench/sdk-harness/README.md`'s shape: the six
    header lines in order, one `obs` row per kept observation, and the two trailers last.
    Identical in shape to `examples/bench_consumer.py`'s own copy.
    """
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    assert lines[0] == "# pmws-obs v1", lines[0]
    assert lines[1] == f"# leg: {expected_leg}", lines[1]
    assert lines[2].startswith("# host: "), lines[2]
    assert lines[3] == "# clock: epoch_ns", lines[3]
    assert lines[4].startswith("# size: "), lines[4]
    assert lines[5].startswith("# pin: "), lines[5]
    obs_lines = [line for line in lines if line.startswith("obs ")]
    assert len(obs_lines) == expected_rows, obs_lines
    for line in obs_lines:
        fields = line.split(" ")
        assert len(fields) >= 4, line
        assert len(fields[3]) == 16, line
    assert lines[-2].startswith("# events_total: "), lines[-2]
    assert lines[-1] == f"# dropped: {expected_dropped}", lines[-1]


def self_test():
    """Runs the canonical-decimal vectors and the shared digest golden value from
    `bench/sdk-harness/README.md`, exercises `write_obs_file` against a synthetic
    `RunStats`, and constructs (never connects) a `WebSocketClient` as an import/API-shape
    check. Touches no network.
    """
    for text, expected in CANONICAL_VECTORS:
        got = canonical_decimal(text)
        if got != expected:
            print(
                f"FAIL canonical_decimal({text!r}) == {got!r}, expected {expected!r}",
                file=sys.stderr,
            )
            return 1
    digest = digest_book(GOLDEN_BIDS, GOLDEN_ASKS)
    if digest != GOLDEN_DIGEST:
        print(
            f"FAIL digest_book(...) == {digest!r}, expected {GOLDEN_DIGEST!r}",
            file=sys.stderr,
        )
        return 1
    stats = RunStats()
    stats.events_total = 2
    stats.obs_rows = [
        ("golden-market", 1_700_000_000_000_000_000, digest, 0),
        ("golden-market", 1_700_000_000_100_000_000, digest, 1),
    ]
    stats.dropped = 3
    handle, path = tempfile.mkstemp(prefix="sdk_leg_self_test_", suffix=".obs")
    os.close(handle)
    try:
        write_obs_file(path, "self-test", 1, stats)
        _check_obs_file(path, "py-sdk", len(stats.obs_rows), stats.dropped)
    finally:
        os.remove(path)
    try:
        WebSocketClient(config=WebSocketConfig(), logger=None)
    except Exception as error:  # noqa: BLE001 -- any construction failure is the finding
        print(f"FAIL WebSocketClient construction raised {error!r}", file=sys.stderr)
        return 1
    print("self-test passed")
    print(f"golden digest: {digest}")
    return 0


def bounded_seconds(text):
    value = float(text)
    if not 0 < value <= MAX_SECONDS:
        raise argparse.ArgumentTypeError(f"--seconds must be in (0, {MAX_SECONDS}]")
    return value


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="pm-ws S8c py-sdk leg: official limitless-sdk consumer"
    )
    parser.add_argument("--slugs")
    parser.add_argument("--seconds", type=bounded_seconds)
    parser.add_argument("--obs-out")
    parser.add_argument("--label")
    parser.add_argument("--endpoint", default=None)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return args
    missing = [
        name
        for name, value in (
            ("--slugs", args.slugs),
            ("--seconds", args.seconds),
            ("--obs-out", args.obs_out),
            ("--label", args.label),
        )
        if value is None
    ]
    if missing:
        parser.error(f"the following arguments are required unless --self-test: {', '.join(missing)}")
    return args


def main():
    args = parse_args()
    if args.self_test:
        return self_test()
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
