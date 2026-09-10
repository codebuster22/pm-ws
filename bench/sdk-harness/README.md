# S8c comparative harness — SDK vs pm-ws

Measures what pm-ws buys over consuming the Limitless WebSocket feed through the official
SDKs. Two stacks run side by side on the same host,
subscribed to the identical pinned market set; the same venue event is matched across legs
by market and book-content digest; the metric is the signed per-event observation delta at
an identical boundary, as p50/p99/p99.9 distributions, with each leg's own internals,
CPU/RSS, and saturation behavior alongside.

Everything in this directory is tier-2 bench tooling. The SDK legs live here, outside the
daemon's dependency graph: the daemon's `Cargo.lock`, `cargo deny`, and `cargo audit`
stay about the daemon. The pm-ws legs are examples in the main crate and are covered by
`./check`.

## Leg inventory

| Leg id | Language | What it runs | Where |
|---|---|---|---|
| `rust-sdk` | Rust | official `limitless-exchange-rust-sdk`, git-pinned `b1ad2e108e96f05b615d513d3f32237a775177f8` | `bench/sdk-harness/rust/` |
| `rust-embedded` | Rust | pm-ws venue rails + `BookWriter`/`BookObserver` in-process, no shm | `examples/embedded_live.rs` |
| `rust-shm` | Rust | `pmwsd` + `SegmentReader` consumer in a second process | `examples/matched_consumer.rs` |
| `ts-sdk` | TypeScript | official `@limitless-exchange/sdk` `=1.1.0` | `bench/sdk-harness/ts/` |
| `ts-binding` | TypeScript | `pmwsd` + `bindings/node/pmws.ts` consumer | `examples/bench_consumer.ts --obs-out` |
| `py-sdk` | Python | official `limitless-sdk==1.1.0` | `bench/sdk-harness/python/` |
| `py-binding` | Python | `pmwsd` + `bindings/python/pmws.py` consumer | `examples/bench_consumer.py --obs-out` |

Rust runs three legs simultaneously (the three-way split isolates the engine's worth
in-process and the IPC hop's true cost); TypeScript and Python run their SDK leg against
their binding leg, sharing one daemon with the Rust `rust-shm` topology.

## The boundary

`t_obs` is stamped at the first instant strategy code holds the decoded update — the book
content for the market is readable in the leg's own representation. Concretely:

- SDK legs: inside the `orderbookUpdate` callback, after the update is stored into the
  leg's own slug -> book map (its "minimal book handling"), before anything else.
- Binding / shm legs: after `read_state()` returned the published state for the dirty
  market, before anything else.
- Embedded leg: after the observer delivered and `latest()` returned the published book.

Digest computation, logging, and any bookkeeping happen strictly after the stamp: they are
harness cost, not boundary cost, though they do occupy the leg between events and are the
same work in every leg.

All legs stamp with the wall clock as nanoseconds since the Unix epoch: Rust
`SystemTime::now().duration_since(UNIX_EPOCH)`, Python `time.time_ns()`, TypeScript the
calibrated monotonic->realtime `epochNanos` worker copied from `examples/bench_consumer.ts`.
Matched deltas are `t_obs(pm-ws leg) - t_obs(reference leg)` in nanoseconds, signed;
positive means the pm-ws leg observed later. A delta with absolute value >= 1s is
discarded as implausible (clock step), never clamped, and counted.

## Content digest

The venue `orderbookUpdate` carries the full book, one event advances one pm-ws book
revision, and neither the venue `timestamp` nor `version` crosses the segment ABI — so
legs match on book content. Each observation digests its decoded book:

1. Exclude levels with zero quantity.
2. Sort bids by price descending, asks by price ascending.
3. Serialize as `B` + `price:qty;` per bid + `|A` + `price:qty;` per ask, using canonical
   decimals (below).
4. FNV-1a 64-bit over the UTF-8 bytes (offset `0xcbf29ce484222325`, prime
   `0x100000001b3`), printed as 16 lowercase hex digits.

Canonical decimal, from a decimal string (pm-ws `text` lexeme, or the shortest-round-trip
formatting of the SDK's float: Rust `{}`, JS `String(n)`, Python `repr(n)`):

- If the string contains `e`/`E`, expand to plain decimal notation first.
- Strip a leading `+`.
- Strip redundant leading zeros (`007` -> `7`; `0.53` stays `0.53`; `0` stays `0`).
- If it contains `.`: strip trailing zeros, then a trailing `.`.

Vectors: `0.530` -> `0.53` · `1000000.0` -> `1000000` · `100` -> `100` · `0.5` -> `0.5` ·
`1e-7` -> `0.0000001` · `0.0` -> `0`.

pm-ws latest-state delivery coalesces bursts by design: a pm-ws leg may observe fewer
states than the SDK leg observes events, and one 900 s box run at size all recorded
31184 SDK rows against 25589 pm-ws rows over the identical pinned set. Coalescing is
one source of unmatched rows and it is not the only one, so an unmatched count is not
a coalescing measure. A second source: the SDKs parse book values into floats, so a
venue decimal lexeme that does not survive an f64 round-trip digests differently from
the pm-ws exact-lexeme side and the event goes unmatched rather than wrongly matched.
A third and a fourth come from the matcher itself -- candidates the tolerance gate
rejects, and re-synchronisations that fall outside the look-ahead window. All four land
in the same counts, which is why `unmatched_a` and `unmatched_b` are reported
separately. The matched fraction is reported alongside them and is not comparable
across pairings: its denominator is `min(obs_a, obs_b)`, and which side that minimum
comes from changes between rows -- a leg that stalls mid-run takes the denominator away
from the leg that coalesces -- so the reported fraction names its denominator side.

## Matching

`match_events.py <a.obs> <b.obs>` aligns two logs market by market and reports the
signed delta distribution. It picks one of two alignments (`--alignment auto`).

Rev-keyed, the primary for a pm-ws-vs-pm-ws pairing. Both pm-ws legs emit
`rev=<book revision>`, which is the venue's own event ordering, so when every row of
both logs carries one the matcher pairs by revision correspondence instead of by
digest: per market the modal offset `mode(rev_b - rev_a)` is estimated over the
digest-equal candidate pairs, rows then pair where `rev_b - rev_a` equals that mode,
digest equality is verified on every paired row (`rev_digest_disagreements`, expected
zero), and the per-market share of candidates sitting on the mode is reported as the
estimate's own diagnostic. The offset estimate runs over the ungated digest alignment,
so it does not depend on the tolerance below. No SDK leg emits a revision, so an SDK
pairing always falls back to digest alignment.

Digest, the fallback. Order-preserving and greedy with a bounded look-ahead
(`--window`, default 32), never an LCS: equal digests at both cursors pair and both
advance; otherwise the nearest forward re-synchronisation inside the window is taken --
the smaller of "skip in A" and "skip in B" -- and when neither side can re-synchronise
both cursors advance by one and the two entries drop unmatched. A tie skips in A,
because B is conventionally the pm-ws leg and pm-ws coalesces, so the surplus is more
often A's. That tie-break is an assumption about which leg leads, not a fact: a stalled
SDK leg inverts it, and such a row is not citable.

Digests repeat -- the venue re-broadcasts an unchanged book -- so digest equality alone
does not identify an event, and occurrence-order pairing of a repeated digest can slip
by several events, each slipped pair carrying one inter-event gap (200-1000 ms
observed). A re-synchronisation candidate is therefore accepted only if its digest
matches AND `|t_candidate - t_anchor| <= --tolerance-ms`, default 150 ms. That default
sits between two numbers only a factor of two apart: the measured inter-connection skew
ceiling is 119 ms (rev-keyed, size 50) and the slip quantum is one inter-event gap,
200-300 ms on the busy markets. Only the first digest-equal candidate in the window is
considered -- scanning past it for a time-plausible one would select the pairing that
flatters the metric. The gate is a stopgap, not a repair: it does not reach head-to-head
pairing of repeated digests, so a content-digest matcher cannot be fully rescued. The
real fix is carrying a venue-side opaque match key through the bench build.

Censoring is reported, never silent. `tolerance_rejected` counts every candidate the
gate turned away; `tolerance_blocked` counts the subset where the rejection left no
candidate on either side, so a pairing was lost -- a rejection the other side rescued
redirects the alignment without removing anything from the distribution. The table
carries the implausible count, both gate counters, and
`censored frac = (implausible + tol blocked) / (delta samples + implausible + tol
blocked)`. A percentile is withheld from the table and printed `--` when the
distribution behind it is too small to carry it: p99.9 needs 2000 samples, p99 needs
200; the value stays in the plain output, flagged withheld.

## Observation log (`.obs`)

One text file per leg per run, buffered in memory (cap 4,000,000 rows; overflow counts as
dropped and is reported), written on exit:

```
# pmws-obs v1
# leg: rust-sdk
# host: <host label>
# clock: epoch_ns
# size: <market count>
# pin: <git rev of pm-ws, or SDK package pin>
obs <slug> <t_obs_ns> <digest16> <per-market-seq from 0>[ rev=<book_revision>]
# events_total: <n>
# dropped: <n>
```

Fields after the fourth are optional and matcher-ignored except `rev=`. Every leg also
prints its usual internals summary to stdout (binding legs keep their three-way
arrival/commit/observed split; SDK legs report event counts, per-market rates, and any
reconnects the SDK performed).

## Leg CLI contract

Every leg accepts: `--slugs <file>` (one slug per line), `--seconds <n>`,
`--obs-out <path>`, `--label <text>`. Legs that dial the venue accept `--endpoint <url>`
(SDK legs default to the SDK's own default). Binding/shm legs accept `--control <socket>`
plus their existing lease flags. The embedded leg accepts `--markets-per-connection <n>`
and mirrors the daemon's own sort-then-chunk sharding arithmetic.

## Etiquette

Live legs obey `docs/limitless.md`. SDK auto-reconnect is capped where the SDK exposes a
cap; the runner watches SDK legs for reconnect churn and aborts the ladder on any venue
pushback (429, refusal, throttle) — descend, record, tell the owner. REST is used only to
pin market sets: one `bench/discover_markets.py` sweep per ladder session (~24 calls)
plus single page-1 polls for the 5-minute size-1 market; any rolling hour stays <= 60.

## Market-set pinning

`all-active` is the venue's full CLOB list from one discovery sweep, pinned at ladder
start. The first all-active rung's pm-ws obs logs rank markets by observed update count;
sizes 200/100/50/20/10 are the top-N of that ranking, pinned for the whole session.
Size 1 is the newest `btc-up-or-down-5-min-*` listing at rung start (its life is ~5
minutes, so the size-1 rung runs 240 s). The report records every pinned set.

## Regeneration

```
bench/sdk-harness/run_ladder.sh --host-label <name> --workdir <dir> \
  [--sizes "1 10 20 50 100 200 all"] [--langs "rust ts py"] [--seconds 600] \
  [--all-active-seconds 900] [--metrics-port <p>]
```

builds the pm-ws release binaries and examples, the SDK harness legs (each inside this
directory only: `cargo build --release` in `rust/`, `npm ci` in `ts/`, a venv from
`python/requirements.txt`), runs the ladder, and assembles
`bench/reports/s8c-<host-label>.md` — the size x leg table of matched-event delta
distributions plus per-leg internals, CPU/RSS (1 Hz `ps` samples), machine and workload
named. `match_events.py <a.obs> <b.obs> [--window 32] [--trim-seconds 10] [--tolerance-ms 150]
[--alignment auto|digest|rev] [--markdown]` reproduces any single pairing, and
`match_events.py --self-test` checks the alignment and the statistics against
hand-computed expectations.
