#!/usr/bin/env python3
"""Matches two S8c observation logs event for event and reports the signed delta.

Reads two `.obs` files in the format `bench/sdk-harness/README.md` pins, aligns them per
market slug, and reports the distribution of `delta = t_obs(file B) - t_obs(file A)` over
the matched pairs. B is conventionally the pm-ws leg, so a positive delta means pm-ws
observed later; the labels printed with the distribution say which file is which.

Two alignments, chosen automatically (`--alignment auto`, the default):

`rev` -- the primary for a pm-ws-vs-pm-ws pairing. When every row of both files carries
`rev=<book revision>`, the legs are two views of the same book and their revisions are the
venue's own event ordering. Per market the modal revision offset `mode(rev_b - rev_a)` is
estimated over the digest-equal candidate pairs, then rows are paired by
`rev_b - rev_a == mode`. Digest equality is verified on every paired row and any
disagreement is counted (`rev_digest_disagreements`), and the per-market share of candidate
pairs sitting on the mode is reported as the estimate's own diagnostic. The offset estimate
deliberately runs over the ungated digest alignment so that the estimate does not depend on
`--tolerance-ms`.

`digest` -- the fallback, and the only alignment available for an SDK-vs-pm-ws pairing
because no SDK leg emits a revision. It is order-preserving and greedy with a bounded
look-ahead (`--window`, default 32), never an LCS: at each position, equal digests pair and
both cursors advance; otherwise the nearest forward re-synchronisation within the window is
taken -- the smaller of "skip entries in A" and "skip entries in B" -- and when neither side
can re-synchronise inside the window both cursors advance by one and the two entries are
dropped unmatched. A tie is resolved by skipping in A, because B is conventionally the pm-ws
leg and pm-ws latest-state delivery coalesces bursts, so the sequence with the surplus
entries is more often A. That tie-break is an assumption about which leg leads, not a fact:
a stalled SDK leg inverts it, and such a row is not citable.

Book digests repeat -- the venue re-broadcasts an unchanged book -- so digest equality alone
does not identify an event, and occurrence-order pairing of a repeated digest can slip by
several events. A resync candidate is therefore accepted only if its digest matches AND
`|t_candidate - t_anchor| <= --tolerance-ms` (default 150 ms). Only the first digest-equal
candidate in the window is considered: scanning past it for a time-plausible one would pick
the pairing that flatters the metric. A candidate rejected for time is counted in
`tolerance_rejected` and reported, never silently dropped.

Tolerated by construction: gaps on either side (coalescing, a brief disconnect), duplicate
digests, and unmatched prefixes and suffixes (the legs start and stop at different instants).
`--trim-seconds` additionally drops the first N seconds of each log, measured from that
log's own earliest observation, so subscription ramp does not skew the distribution.

A pair whose `|delta|` is at least one second is a clock step, not a measurement: it is
counted as implausible and excluded from the distribution, never clamped.

Two counters keep the gate visible. `tolerance_rejected` counts every candidate the gate
turned away, per side. `tolerance_blocked` counts the subset of positions where the
rejection left no candidate on either side, so a pairing the ungated matcher would have made
was lost -- a rejection the other side rescued redirects the alignment but removes nothing
from the distribution, so only the blocked subset is censoring:
`censored_fraction = (implausible + tolerance_blocked) / (delta_samples + implausible + tolerance_blocked)`.

Percentiles are nearest-rank over the signed nanosecond deltas, by the same arithmetic
`examples/latency_probe.rs` and `examples/bench_consumer.py` use, so a p99 here is the same
statistic as a p99 there. A percentile is withheld from the markdown table (printed `--`)
when the distribution behind it is too small to carry it: p99.9 needs 2000 samples, p99
needs 200. The value is still printed in the plain output, flagged withheld.

Usage:
    match_events.py <a.obs> <b.obs> [--label-a <text>] [--label-b <text>] [--size <text>]
                    [--window 32] [--trim-seconds 10] [--tolerance-ms 150]
                    [--alignment auto|digest|rev] [--markdown]
                    [--resources-a <file>] [--resources-b <file>] [--resources <file>]
    match_events.py --self-test
"""

import argparse
import sys
from collections import Counter

OBS_VERSION_HEADER = "# pmws-obs v1"
IMPLAUSIBLE_NS = 1_000_000_000
DEFAULT_WINDOW = 32
DEFAULT_TRIM_SECONDS = 10
DEFAULT_TOLERANCE_MS = 150
NANOS_PER_SECOND = 1_000_000_000
NANOS_PER_MILLI = 1_000_000
P99_MIN_SAMPLES = 200
P999_MIN_SAMPLES = 2000
WITHHELD_CELL = "--"


class MatchError(Exception):
    pass


class Observation:
    """One `obs` row: market key, observation stamp, book digest, sequence, book revision.

    `rev` is the `rev=<n>` trailing field when the leg emits one, else None.
    """

    __slots__ = ("slug", "t_ns", "digest", "seq", "rev")

    def __init__(self, slug, t_ns, digest, seq, rev=None):
        self.slug = slug
        self.t_ns = t_ns
        self.digest = digest
        self.seq = seq
        self.rev = rev


class ObsLog:
    """A parsed observation log: header values, rows in file order, malformed-line count.

    `rows` keeps file order; `by_slug` groups them per market, preserving that order, which
    is the per-market time order every leg writes.
    """

    def __init__(self, source, headers, rows, malformed):
        self.source = source
        self.headers = headers
        self.rows = rows
        self.malformed = malformed
        self.by_slug = {}
        for row in rows:
            self.by_slug.setdefault(row.slug, []).append(row)

    @property
    def t0_ns(self):
        return min((row.t_ns for row in self.rows), default=None)

    def has_revisions(self):
        """True when the log is non-empty and every row carries a `rev=` field."""
        return bool(self.rows) and all(row.rev is not None for row in self.rows)

    def leg(self):
        return self.headers.get("leg", "")

    def size(self):
        return self.headers.get("size", "")

    def trimmed(self, trim_seconds):
        """This log with every row inside the first `trim_seconds` of its own span dropped."""
        if trim_seconds <= 0 or not self.rows:
            return self
        cutoff = self.t0_ns + trim_seconds * NANOS_PER_SECOND
        kept = [row for row in self.rows if row.t_ns >= cutoff]
        return ObsLog(self.source, self.headers, kept, self.malformed)


def parse_obs(lines, source):
    """Parses `.obs` text into an `ObsLog`.

    Header lines (`# key: value`) are collected first-wins. A data line is
    `obs <slug> <t_obs_ns> <digest> <seq>` plus any number of trailing fields, of which only
    `rev=<integer>` is read; a line that is neither, or whose stamp or sequence is not an
    integer, is counted as malformed rather than raising -- every leg is stopped with
    SIGTERM, so a truncated final line is ordinary. A `rev=` that is not an integer leaves
    the revision unset. The digest is kept as an opaque token, never parsed as a number.
    """
    headers = {}
    rows = []
    malformed = 0
    for raw in lines:
        stripped = raw.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            body = stripped.lstrip("#").strip()
            key, separator, value = body.partition(":")
            if separator:
                headers.setdefault(key.strip(), value.strip())
            continue
        fields = stripped.split()
        if len(fields) < 5 or fields[0] != "obs":
            malformed += 1
            continue
        try:
            t_ns = int(fields[2])
            seq = int(fields[4])
        except ValueError:
            malformed += 1
            continue
        rev = None
        for extra in fields[5:]:
            if extra.startswith("rev="):
                try:
                    rev = int(extra[4:])
                except ValueError:
                    rev = None
        rows.append(Observation(fields[1], t_ns, fields[3], seq, rev))
    return ObsLog(source, headers, rows, malformed)


def read_obs_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return parse_obs(handle, path)
    except OSError as error:
        raise MatchError(f"cannot read {path}: {error}") from error


def _first_candidate(entries, start, stop, digest, anchor_t_ns, tolerance_ns):
    """The first digest-equal resync candidate in `[start, stop)`, gated on time.

    Returns `(index, rejected)`. Only the first digest-equal entry is considered: scanning
    past it for a time-plausible one would select the pairing that minimises the reported
    delta. When that entry is further than `tolerance_ns` from the anchor stamp the result
    is `(None, True)` -- no candidate, and one rejection to report. `tolerance_ns <= 0`
    disables the gate.
    """
    for index in range(start, stop):
        if entries[index].digest == digest:
            if tolerance_ns > 0 and abs(entries[index].t_ns - anchor_t_ns) > tolerance_ns:
                return None, True
            return index, False
    return None, False


def align(entries_a, entries_b, window, tolerance_ns):
    """Order-preserving greedy digest alignment of two per-market observation sequences.

    Returns `(pairs, skipped_a, skipped_b, resyncs, tolerance_rejected, tolerance_blocked)`
    where `pairs` is the list of `(a_entry, b_entry)` matched in order, `skipped_*` counts
    entries each side advanced past without a partner (including the unmatched suffix),
    `resyncs` counts the positions where neither side could re-synchronise inside `window`
    and both entries were dropped, `tolerance_rejected` counts every digest-equal candidate
    the tolerance gate turned away (one per side), and `tolerance_blocked` counts the
    positions where that rejection left no candidate at all -- one pairing the ungated
    matcher would have made and this one refuses.
    """
    pairs = []
    skipped_a = 0
    skipped_b = 0
    resyncs = 0
    tolerance_rejected = 0
    tolerance_blocked = 0
    index_a = 0
    index_b = 0
    length_a = len(entries_a)
    length_b = len(entries_b)
    while index_a < length_a and index_b < length_b:
        if entries_a[index_a].digest == entries_b[index_b].digest:
            pairs.append((entries_a[index_a], entries_b[index_b]))
            index_a += 1
            index_b += 1
            continue
        found_a, rejected_a = _first_candidate(
            entries_a,
            index_a + 1,
            min(length_a, index_a + 1 + window),
            entries_b[index_b].digest,
            entries_b[index_b].t_ns,
            tolerance_ns,
        )
        found_b, rejected_b = _first_candidate(
            entries_b,
            index_b + 1,
            min(length_b, index_b + 1 + window),
            entries_a[index_a].digest,
            entries_a[index_a].t_ns,
            tolerance_ns,
        )
        tolerance_rejected += int(rejected_a) + int(rejected_b)
        if found_a is None and found_b is None:
            if rejected_a or rejected_b:
                tolerance_blocked += 1
            skipped_a += 1
            skipped_b += 1
            resyncs += 1
            index_a += 1
            index_b += 1
            continue
        if found_b is None or (
            found_a is not None and (found_a - index_a) <= (found_b - index_b)
        ):
            skipped_a += found_a - index_a
            index_a = found_a
        else:
            skipped_b += found_b - index_b
            index_b = found_b
    skipped_a += length_a - index_a
    skipped_b += length_b - index_b
    return pairs, skipped_a, skipped_b, resyncs, tolerance_rejected, tolerance_blocked


def revision_offset_mode(pairs):
    """`(mode, votes_on_mode, votes_total)` of `rev_b - rev_a` over candidate pairs.

    Returns None when no candidate pair carries a revision on both sides.
    """
    offsets = [
        entry_b.rev - entry_a.rev
        for entry_a, entry_b in pairs
        if entry_a.rev is not None and entry_b.rev is not None
    ]
    if not offsets:
        return None
    mode, votes = Counter(offsets).most_common(1)[0]
    return mode, votes, len(offsets)


def rev_align(entries_a, entries_b, offset):
    """Pairs two per-market sequences by revision correspondence at a fixed offset.

    A row of B pairs with the row of A whose revision is `rev_b - offset`; revisions are
    unique per market per leg, so the map is first-wins and the pairing is one to one.
    Returns `(pairs, unmatched_a, unmatched_b, digest_disagreements)`.
    """
    by_rev_a = {}
    for entry in entries_a:
        if entry.rev is not None:
            by_rev_a.setdefault(entry.rev, entry)
    pairs = []
    matched_a = set()
    unmatched_b = 0
    disagreements = 0
    for entry_b in entries_b:
        entry_a = by_rev_a.get(entry_b.rev - offset) if entry_b.rev is not None else None
        if entry_a is None:
            unmatched_b += 1
            continue
        matched_a.add(entry_a.rev)
        if entry_a.digest != entry_b.digest:
            disagreements += 1
        pairs.append((entry_a, entry_b))
    return pairs, len(entries_a) - len(matched_a), unmatched_b, disagreements


def quantile(sorted_samples, permille):
    """The `permille`-th value of a sorted sample set by nearest rank; 0 when empty.

    Identical arithmetic to `examples/latency_probe.rs` and `examples/bench_consumer.py`.
    """
    if not sorted_samples:
        return 0
    count = len(sorted_samples)
    rank = max(-(-count * permille // 1000), 1) - 1
    return sorted_samples[min(rank, count - 1)]


def parse_resources(lines):
    """Parses `epoch_s rss_kib pcpu` sample lines into peak RSS and mean CPU.

    Returns None when no sample parsed; otherwise a dict with `samples`, `max_rss_kib`,
    `max_rss_mib` and `mean_pcpu`. Blank lines, `#` comments and unparsable lines are ignored.
    """
    samples = 0
    max_rss_kib = 0
    cpu_total = 0.0
    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split()
        if len(fields) < 3:
            continue
        try:
            rss_kib = float(fields[1])
            pcpu = float(fields[2])
        except ValueError:
            continue
        samples += 1
        if rss_kib > max_rss_kib:
            max_rss_kib = rss_kib
        cpu_total += pcpu
    if samples == 0:
        return None
    return {
        "samples": samples,
        "max_rss_kib": max_rss_kib,
        "max_rss_mib": max_rss_kib / 1024.0,
        "mean_pcpu": cpu_total / samples,
    }


def read_resources_file(path):
    if path is None:
        return None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return parse_resources(handle)
    except OSError:
        return None


def choose_alignment(requested, log_a, log_b):
    """Resolves `--alignment` against what the two logs actually carry.

    `auto` is `rev` when both logs carry a revision on every row, else `digest`. `rev` is
    an error when either log does not.
    """
    both_have_rev = log_a.has_revisions() and log_b.has_revisions()
    if requested == "rev":
        if not both_have_rev:
            raise MatchError(
                "--alignment rev needs rev= on every row of both logs; "
                f"a={'yes' if log_a.has_revisions() else 'no'} "
                f"b={'yes' if log_b.has_revisions() else 'no'}"
            )
        return "rev"
    if requested == "digest":
        return "digest"
    return "rev" if both_have_rev else "digest"


def compare(
    log_a,
    log_b,
    window=DEFAULT_WINDOW,
    trim_seconds=DEFAULT_TRIM_SECONDS,
    tolerance_ns=DEFAULT_TOLERANCE_MS * NANOS_PER_MILLI,
    alignment="auto",
):
    """Aligns two logs market by market and summarises the signed delta distribution.

    `delta = t_obs(B) - t_obs(A)` in nanoseconds. Pairs with `|delta| >= 1s` are counted as
    implausible and excluded from the distribution; every other pair contributes one sample.
    """
    trimmed_a = log_a.trimmed(trim_seconds)
    trimmed_b = log_b.trimmed(trim_seconds)
    mode = choose_alignment(alignment, trimmed_a, trimmed_b)
    shared = [slug for slug in trimmed_a.by_slug if slug in trimmed_b.by_slug]
    shared.sort()

    deltas = []
    pairs_total = 0
    implausible = 0
    skipped_a = 0
    skipped_b = 0
    resyncs = 0
    tolerance_rejected = 0
    tolerance_blocked = 0
    per_market = []
    shared_a_rows = 0
    shared_b_rows = 0
    rev_markets_keyed = 0
    rev_markets_unkeyed = 0
    rev_markets_nonconstant = 0
    rev_mode_votes = 0
    rev_offset_votes = 0
    rev_digest_disagreements = 0
    for slug in shared:
        entries_a = trimmed_a.by_slug[slug]
        entries_b = trimmed_b.by_slug[slug]
        shared_a_rows += len(entries_a)
        shared_b_rows += len(entries_b)
        (
            candidates,
            market_skipped_a,
            market_skipped_b,
            market_resyncs,
            market_rejected,
            market_blocked,
        ) = align(entries_a, entries_b, window, 0 if mode == "rev" else tolerance_ns)
        market_offset = None
        if mode == "rev":
            estimate = revision_offset_mode(candidates)
            if estimate is None:
                rev_markets_unkeyed += 1
                skipped_a += len(entries_a)
                skipped_b += len(entries_b)
                continue
            market_offset, votes_on_mode, votes_total = estimate
            rev_markets_keyed += 1
            rev_mode_votes += votes_on_mode
            rev_offset_votes += votes_total
            if votes_on_mode != votes_total:
                rev_markets_nonconstant += 1
            pairs, market_skipped_a, market_skipped_b, disagreements = rev_align(
                entries_a, entries_b, market_offset
            )
            rev_digest_disagreements += disagreements
            market_resyncs = 0
            market_rejected = 0
            market_blocked = 0
        else:
            pairs = candidates
        market_implausible = 0
        market_deltas = []
        for entry_a, entry_b in pairs:
            delta = entry_b.t_ns - entry_a.t_ns
            if abs(delta) >= IMPLAUSIBLE_NS:
                market_implausible += 1
                continue
            market_deltas.append(delta)
        pairs_total += len(pairs)
        implausible += market_implausible
        skipped_a += market_skipped_a
        skipped_b += market_skipped_b
        resyncs += market_resyncs
        tolerance_rejected += market_rejected
        tolerance_blocked += market_blocked
        deltas.extend(market_deltas)
        per_market.append(
            {
                "slug": slug,
                "obs_a": len(entries_a),
                "obs_b": len(entries_b),
                "pairs": len(pairs),
                "implausible": market_implausible,
                "rev_offset": market_offset,
            }
        )

    ordered = sorted(deltas)
    total_a = len(trimmed_a.rows)
    total_b = len(trimmed_b.rows)
    denominator_side = "a" if total_a <= total_b else "b"
    denominator = min(total_a, total_b)
    shared_denominator = min(shared_a_rows, shared_b_rows)
    negative = sum(1 for delta in ordered if delta < 0)
    censoring_base = len(ordered) + implausible + tolerance_blocked
    return {
        "alignment": mode,
        "window": window,
        "trim_seconds": trim_seconds,
        "tolerance_ns": tolerance_ns,
        "a": trimmed_a,
        "b": trimmed_b,
        "a_t0_ns": log_a.t0_ns,
        "b_t0_ns": log_b.t0_ns,
        "a_obs_before_trim": len(log_a.rows),
        "b_obs_before_trim": len(log_b.rows),
        "a_obs": total_a,
        "b_obs": total_b,
        "a_markets": len(trimmed_a.by_slug),
        "b_markets": len(trimmed_b.by_slug),
        "markets_matched": len(shared),
        "matched_pairs": pairs_total,
        "matched_fraction": (pairs_total / denominator) if denominator else 0.0,
        "matched_fraction_denominator": denominator_side,
        "matched_fraction_denominator_obs": denominator,
        "matched_fraction_shared": (
            (pairs_total / shared_denominator) if shared_denominator else 0.0
        ),
        "implausible": implausible,
        "tolerance_rejected": tolerance_rejected,
        "tolerance_blocked": tolerance_blocked,
        "censored_fraction": (
            ((implausible + tolerance_blocked) / censoring_base) if censoring_base else 0.0
        ),
        "delta_samples": len(ordered),
        "skipped_a": skipped_a,
        "skipped_b": skipped_b,
        "resyncs": resyncs,
        "rev_markets_keyed": rev_markets_keyed,
        "rev_markets_unkeyed": rev_markets_unkeyed,
        "rev_markets_nonconstant_offset": rev_markets_nonconstant,
        "rev_offset_mode_share": (
            (rev_mode_votes / rev_offset_votes) if rev_offset_votes else 0.0
        ),
        "rev_digest_disagreements": rev_digest_disagreements,
        "negative": negative,
        "negative_fraction": (negative / len(ordered)) if ordered else 0.0,
        "p50_ns": quantile(ordered, 500),
        "p90_ns": quantile(ordered, 900),
        "p99_ns": quantile(ordered, 990),
        "p999_ns": quantile(ordered, 999),
        "p99_withheld": len(ordered) < P99_MIN_SAMPLES,
        "p999_withheld": len(ordered) < P999_MIN_SAMPLES,
        "mean_ns": (sum(ordered) / len(ordered)) if ordered else 0.0,
        "min_ns": ordered[0] if ordered else 0,
        "max_ns": ordered[-1] if ordered else 0,
        "per_market": per_market,
    }


def micros(nanos):
    return nanos / 1000.0


def percentile_cell(result, key):
    """The table cell for a percentile: `--` when the sample floor withholds it."""
    if result[f"{key}_withheld"]:
        return WITHHELD_CELL
    return f"{micros(result[f'{key}_ns']):.1f}"


def label_for(explicit, log, fallback):
    if explicit:
        return explicit
    leg = log.leg()
    if leg:
        return leg
    return fallback


def print_summary(result, label_a, label_b, size, resources_a, resources_b):
    print("# match_events v2")
    print(f"label_a: {label_a}")
    print(f"file_a: {result['a'].source}")
    print(f"label_b: {label_b}")
    print(f"file_b: {result['b'].source}")
    print(f"size: {size}")
    print("delta_definition: t_obs(B) - t_obs(A) nanoseconds, signed")
    print(f"alignment: {result['alignment']}")
    print(f"window: {result['window']}")
    print(f"trim_seconds: {result['trim_seconds']}")
    print(f"tolerance_ms: {result['tolerance_ns'] / NANOS_PER_MILLI:g}")
    print(f"a_t0_epoch_ns: {result['a_t0_ns']}")
    print(f"b_t0_epoch_ns: {result['b_t0_ns']}")
    print(f"a_obs_before_trim: {result['a_obs_before_trim']}")
    print(f"b_obs_before_trim: {result['b_obs_before_trim']}")
    print(f"a_obs_total: {result['a_obs']}")
    print(f"b_obs_total: {result['b_obs']}")
    print(f"a_markets: {result['a_markets']}")
    print(f"b_markets: {result['b_markets']}")
    print(f"markets_in_both: {result['markets_matched']}")
    print(f"a_malformed_lines: {result['a'].malformed}")
    print(f"b_malformed_lines: {result['b'].malformed}")
    print(f"a_dropped_header: {result['a'].headers.get('dropped', 'unknown')}")
    print(f"b_dropped_header: {result['b'].headers.get('dropped', 'unknown')}")
    print(f"matched_pairs: {result['matched_pairs']}")
    print(f"matched_fraction: {result['matched_fraction']:.4f}")
    print(f"matched_fraction_denominator_side: {result['matched_fraction_denominator']}")
    print(f"matched_fraction_denominator_obs: {result['matched_fraction_denominator_obs']}")
    print(f"matched_fraction_shared_markets: {result['matched_fraction_shared']:.4f}")
    print(f"unmatched_a: {result['skipped_a']}")
    print(f"unmatched_b: {result['skipped_b']}")
    print(f"resync_failures: {result['resyncs']}")
    print(f"tolerance_rejected: {result['tolerance_rejected']}")
    print(f"tolerance_blocked: {result['tolerance_blocked']}")
    print(f"implausible_discarded: {result['implausible']}")
    print(f"censored_fraction: {result['censored_fraction']:.4f}")
    if result["alignment"] == "rev":
        print(f"rev_markets_keyed: {result['rev_markets_keyed']}")
        print(f"rev_markets_unkeyed: {result['rev_markets_unkeyed']}")
        print(
            "rev_markets_nonconstant_offset: "
            f"{result['rev_markets_nonconstant_offset']}"
        )
        print(f"rev_offset_mode_share: {result['rev_offset_mode_share']:.4f}")
        print(f"rev_digest_disagreements: {result['rev_digest_disagreements']}")
    print(f"delta_samples: {result['delta_samples']}")
    print(f"delta_p50_us: {micros(result['p50_ns']):.1f}")
    print(f"delta_p90_us: {micros(result['p90_ns']):.1f}")
    print(f"delta_p99_us: {micros(result['p99_ns']):.1f}")
    print(f"delta_p99_withheld: {'true' if result['p99_withheld'] else 'false'}")
    print(f"delta_p999_us: {micros(result['p999_ns']):.1f}")
    print(f"delta_p999_withheld: {'true' if result['p999_withheld'] else 'false'}")
    print(f"delta_mean_us: {micros(result['mean_ns']):.1f}")
    print(f"delta_min_us: {micros(result['min_ns']):.1f}")
    print(f"delta_max_us: {micros(result['max_ns']):.1f}")
    print(f"delta_negative_pairs: {result['negative']}")
    print(f"delta_negative_fraction: {result['negative_fraction']:.4f}")
    for name, resources in (("a", resources_a), ("b", resources_b)):
        if resources is None:
            continue
        print(f"{name}_res_samples: {resources['samples']}")
        print(f"{name}_max_rss_mib: {resources['max_rss_mib']:.1f}")
        print(f"{name}_mean_cpu_percent: {resources['mean_pcpu']:.1f}")


MARKDOWN_HEADER = (
    "| size | pair | align | matched | matched frac | frac denom | implausible | "
    "tol rejected | tol blocked | censored frac | p50 us | p99 us | p99.9 us | "
    "pm-ws-first frac |"
)
MARKDOWN_RULE = "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"


def markdown_row(result, label_a, label_b, size):
    return (
        f"| {size} | {label_a} vs {label_b} | {result['alignment']} | "
        f"{result['matched_pairs']} | {result['matched_fraction']:.4f} | "
        f"{result['matched_fraction_denominator']}"
        f"({result['matched_fraction_denominator_obs']}) | "
        f"{result['implausible']} | {result['tolerance_rejected']} | "
        f"{result['tolerance_blocked']} | "
        f"{result['censored_fraction']:.4f} | {micros(result['p50_ns']):.1f} | "
        f"{percentile_cell(result, 'p99')} | {percentile_cell(result, 'p999')} | "
        f"{result['negative_fraction']:.4f} |"
    )


def obs_lines(leg, size, rows, host="self-test", pin="self-test"):
    """Renders `(slug, t_ns, digest[, rev])` tuples as `.obs` text, numbering sequences."""
    out = [
        OBS_VERSION_HEADER,
        f"# leg: {leg}",
        f"# host: {host}",
        "# clock: epoch_ns",
        f"# size: {size}",
        f"# pin: {pin}",
    ]
    counters = {}
    for row in rows:
        slug, t_ns, digest = row[0], row[1], row[2]
        rev = row[3] if len(row) > 3 else None
        seq = counters.get(slug, 0)
        counters[slug] = seq + 1
        suffix = f" rev={rev}" if rev is not None else ""
        out.append(f"obs {slug} {t_ns} {digest} {seq}{suffix}")
    out.append(f"# events_total: {len(rows)}")
    out.append("# dropped: 0")
    return out


class SelfTestFailure(Exception):
    pass


def check(name, actual, expected):
    if actual != expected:
        raise SelfTestFailure(f"{name}: expected {expected!r}, got {actual!r}")


def self_test():
    """Exercises the alignment and the statistics against hand-computed expectations."""
    base = 1_700_000_000_000_000_000
    tolerance = DEFAULT_TOLERANCE_MS * NANOS_PER_MILLI
    failures = []

    def run(name, body):
        try:
            body()
        except SelfTestFailure as error:
            failures.append(f"{name}: {error}")
        else:
            print(f"ok: {name}")

    def compare_rows(
        rows_a,
        rows_b,
        window=DEFAULT_WINDOW,
        trim_seconds=0,
        tolerance_ns=tolerance,
        alignment="auto",
    ):
        log_a = parse_obs(obs_lines("a-leg", 1, rows_a), "<a>")
        log_b = parse_obs(obs_lines("b-leg", 1, rows_b), "<b>")
        return compare(
            log_a,
            log_b,
            window=window,
            trim_seconds=trim_seconds,
            tolerance_ns=tolerance_ns,
            alignment=alignment,
        )

    def case_exact_percentiles():
        rows_a = [("m1", base + index * 10_000_000, f"d{index:04d}") for index in range(100)]
        rows_b = [
            ("m1", base + index * 10_000_000 + (index + 1) * 1000, f"d{index:04d}")
            for index in range(100)
        ]
        result = compare_rows(rows_a, rows_b)
        check("alignment", result["alignment"], "digest")
        check("matched_pairs", result["matched_pairs"], 100)
        check("delta_samples", result["delta_samples"], 100)
        check("matched_fraction", round(result["matched_fraction"], 6), 1.0)
        check("p50_ns", result["p50_ns"], 50_000)
        check("p90_ns", result["p90_ns"], 90_000)
        check("p99_ns", result["p99_ns"], 99_000)
        check("p999_ns", result["p999_ns"], 100_000)
        check("min_ns", result["min_ns"], 1_000)
        check("max_ns", result["max_ns"], 100_000)
        check("mean_ns", result["mean_ns"], 50_500.0)
        check("negative_fraction", result["negative_fraction"], 0.0)
        check("implausible", result["implausible"], 0)
        check("tolerance_rejected", result["tolerance_rejected"], 0)
        check("censored_fraction", result["censored_fraction"], 0.0)

    def case_coalescing_gap():
        rows_a = [("m1", base + index * 1_000_000, f"c{index}") for index in range(10)]
        rows_b = [
            ("m1", base + index * 1_000_000 + 500, f"c{index}")
            for index in range(10)
            if index not in (3, 4, 5)
        ]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 7)
        check("unmatched_a", result["skipped_a"], 3)
        check("unmatched_b", result["skipped_b"], 0)
        check("matched_fraction", round(result["matched_fraction"], 6), 1.0)
        check("frac_denominator_side", result["matched_fraction_denominator"], "b")
        check("frac_denominator_obs", result["matched_fraction_denominator_obs"], 7)
        check("resyncs", result["resyncs"], 0)
        check("tolerance_rejected", result["tolerance_rejected"], 0)
        check("p50_ns", result["p50_ns"], 500)

    def case_duplicate_digests():
        rows_a = [("m1", base + index * 1_000_000, "same") for index in range(3)]
        rows_b = [("m1", base + index * 1_000_000 + 700, "same") for index in range(2)]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 2)
        check("unmatched_a", result["skipped_a"], 1)
        check("delta_samples", result["delta_samples"], 2)
        check("p50_ns", result["p50_ns"], 700)

    def case_interleaved_duplicates():
        digests_a = ["D1", "D2", "D1", "D3"]
        digests_b = ["D2", "D1", "D3"]
        rows_a = [
            ("m1", base + index * 1_000_000, digest) for index, digest in enumerate(digests_a)
        ]
        rows_b = [
            ("m1", base + (index + 1) * 1_000_000 + 250, digest)
            for index, digest in enumerate(digests_b)
        ]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 3)
        check("unmatched_a", result["skipped_a"], 1)
        check("unmatched_b", result["skipped_b"], 0)
        check("tolerance_rejected", result["tolerance_rejected"], 0)
        check("p50_ns", result["p50_ns"], 250)
        check("max_ns", result["max_ns"], 250)

    def case_disjoint_start_stop():
        rows_a = [("m1", base + index * 1_000_000, f"e{index}") for index in range(10)]
        rows_b = [
            ("m1", base + index * 1_000_000 + 900, f"e{index}") for index in range(3, 13)
        ]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 7)
        check("unmatched_a", result["skipped_a"], 3)
        check("unmatched_b", result["skipped_b"], 3)
        check("matched_fraction", round(result["matched_fraction"], 4), 0.7)

    def case_implausible_and_signs():
        digests = ["s0", "s1", "s2", "s3"]
        offsets = [-5000, -1000, 2000, 2_000_000_000]
        rows_a = [
            ("m1", base + index * 10_000_000, digest) for index, digest in enumerate(digests)
        ]
        rows_b = [
            ("m1", base + index * 10_000_000 + offsets[index], digest)
            for index, digest in enumerate(digests)
        ]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 4)
        check("implausible", result["implausible"], 1)
        check("delta_samples", result["delta_samples"], 3)
        check("censored_fraction", round(result["censored_fraction"], 6), round(1 / 4, 6))
        check("min_ns", result["min_ns"], -5000)
        check("max_ns", result["max_ns"], 2000)
        check("p50_ns", result["p50_ns"], -1000)
        check("p99_ns", result["p99_ns"], 2000)
        check("negative_pairs", result["negative"], 2)
        check("negative_fraction", round(result["negative_fraction"], 6), round(2 / 3, 6))

    def case_gap_wider_than_window():
        digests_a = ["g0", "x1", "x2", "x3", "x4", "x5", "g1"]
        rows_a = [
            ("m1", base + index * 1_000_000, digest) for index, digest in enumerate(digests_a)
        ]
        rows_b = [("m1", base + 300, "g0"), ("m1", base + 6_000_000 + 300, "g1")]
        result = compare_rows(rows_a, rows_b, window=2)
        check("matched_pairs", result["matched_pairs"], 1)
        check("resyncs", result["resyncs"], 1)
        check("tolerance_rejected", result["tolerance_rejected"], 0)
        check("delta_samples", result["delta_samples"], 1)
        check("p50_ns", result["p50_ns"], 300)
        wide = compare_rows(rows_a, rows_b, window=DEFAULT_WINDOW)
        check("wide_window_matched", wide["matched_pairs"], 2)
        check("wide_window_resyncs", wide["resyncs"], 0)

    def case_tolerance_gate_blocks_slip():
        """A coalesced burst of one repeated digest: the ungated matcher slips by 4 events."""
        rows_a = [("m1", base, "head")] + [
            ("m1", base + (index + 1) * 300_000_000, "burst") for index in range(4)
        ]
        rows_b = [("m1", base + 4 * 300_000_000 + 2_000, "burst")]
        ungated = compare_rows(rows_a, rows_b, tolerance_ns=0)
        check("ungated_matched", ungated["matched_pairs"], 1)
        check("ungated_p50_ns", ungated["p50_ns"], 900_000_000 + 2_000)
        check("ungated_tolerance_rejected", ungated["tolerance_rejected"], 0)
        gated = compare_rows(rows_a, rows_b)
        check("gated_matched", gated["matched_pairs"], 0)
        check("gated_tolerance_rejected", gated["tolerance_rejected"], 1)
        check("gated_tolerance_blocked", gated["tolerance_blocked"], 1)
        check("gated_resyncs", gated["resyncs"], 1)
        check("gated_delta_samples", gated["delta_samples"], 0)
        check("gated_unmatched_a", gated["skipped_a"], 5)
        check("gated_unmatched_b", gated["skipped_b"], 1)
        check("gated_censored_fraction", gated["censored_fraction"], 1.0)
        wide_tolerance = compare_rows(rows_a, rows_b, tolerance_ns=NANOS_PER_SECOND)
        check("wide_tolerance_matched", wide_tolerance["matched_pairs"], 1)

    def case_tolerance_rejection_the_other_side_rescues():
        """One side's candidate is out of tolerance; the other side's is not, so a pair forms.

        The gate rewrote the alignment without censoring anything, which is why
        `tolerance_rejected` and `tolerance_blocked` are separate counters.
        """
        rows_a = [("m1", base, "P"), ("m1", base + 500_000_000, "Q")]
        rows_b = [("m1", base + 300_000_000, "Q"), ("m1", base + 1_000, "P")]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 1)
        check("tolerance_rejected", result["tolerance_rejected"], 1)
        check("tolerance_blocked", result["tolerance_blocked"], 0)
        check("resyncs", result["resyncs"], 0)
        check("unmatched_a", result["skipped_a"], 1)
        check("unmatched_b", result["skipped_b"], 1)
        check("censored_fraction", result["censored_fraction"], 0.0)
        check("p50_ns", result["p50_ns"], 1_000)
        ungated = compare_rows(rows_a, rows_b, tolerance_ns=0)
        check("ungated_matched", ungated["matched_pairs"], 1)
        check("ungated_p50_ns", ungated["p50_ns"], -200_000_000)
        check("ungated_tolerance_rejected", ungated["tolerance_rejected"], 0)

    def case_tolerance_gate_keeps_real_skew():
        """A genuine 100 ms skew is inside the window and must still pair."""
        rows_a = [("m1", base + index * 1_000_000, f"w{index}") for index in range(6)]
        rows_b = [
            ("m1", base + index * 1_000_000 + 100_000_000, f"w{index}")
            for index in range(6)
            if index != 2
        ]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 5)
        check("tolerance_rejected", result["tolerance_rejected"], 0)
        check("p50_ns", result["p50_ns"], 100_000_000)

    def case_rev_keyed_offset_and_gap():
        rows_a = [
            ("m1", base + index * 1_000_000, f"r{index}", index + 1) for index in range(12)
        ]
        rows_b = [
            ("m1", base + index * 1_000_000 + 2_000, f"r{index}", index + 11)
            for index in range(12)
            if index != 4
        ]
        rows_a += [("m2", base + index * 1_000_000, f"e{index}", index + 1) for index in range(5)]
        rows_b += [
            (
                "m2",
                base + index * 1_000_000 + 3_000,
                "XX" if index == 2 else f"e{index}",
                index + 11,
            )
            for index in range(5)
        ]
        result = compare_rows(rows_a, rows_b)
        check("alignment", result["alignment"], "rev")
        check("matched_pairs", result["matched_pairs"], 16)
        check("unmatched_a", result["skipped_a"], 1)
        check("unmatched_b", result["skipped_b"], 0)
        check("rev_markets_keyed", result["rev_markets_keyed"], 2)
        check("rev_markets_unkeyed", result["rev_markets_unkeyed"], 0)
        check("rev_markets_nonconstant", result["rev_markets_nonconstant_offset"], 0)
        check("rev_offset_mode_share", result["rev_offset_mode_share"], 1.0)
        check("rev_digest_disagreements", result["rev_digest_disagreements"], 1)
        check("rev_offset_m1", result["per_market"][0]["rev_offset"], 10)
        check("rev_offset_m2", result["per_market"][1]["rev_offset"], 10)
        check("p50_ns", result["p50_ns"], 2_000)
        check("max_ns", result["max_ns"], 3_000)
        forced = compare_rows(rows_a, rows_b, alignment="digest")
        check("forced_digest_alignment", forced["alignment"], "digest")
        check("forced_digest_rev_markets", forced["rev_markets_keyed"], 0)

    def case_rev_absent_falls_back():
        rows_a = [("m1", base + index * 1_000_000, f"f{index}") for index in range(4)]
        rows_b = [
            ("m1", base + index * 1_000_000 + 400, f"f{index}", index + 1) for index in range(4)
        ]
        result = compare_rows(rows_a, rows_b)
        check("alignment", result["alignment"], "digest")
        check("matched_pairs", result["matched_pairs"], 4)
        log_a = parse_obs(obs_lines("a-leg", 1, rows_a), "<a>")
        log_b = parse_obs(obs_lines("b-leg", 1, rows_b), "<b>")
        try:
            compare(log_a, log_b, trim_seconds=0, alignment="rev")
        except MatchError:
            pass
        else:
            raise SelfTestFailure("forcing --alignment rev without rev= must fail")

    def case_censoring_columns():
        rows_a = [("m1", base + index * 10_000_000, f"z{index}") for index in range(10)]
        rows_b = [
            (
                "m1",
                base
                + index * 10_000_000
                + (2_000_000_000 if index in (2, 7) else 1_000),
                f"z{index}",
            )
            for index in range(10)
        ]
        rows_a += [("m2", base, "head")] + [
            ("m2", base + (index + 1) * 300_000_000, "burst") for index in range(4)
        ]
        rows_b += [("m2", base + 4 * 300_000_000 + 2_000, "burst")]
        result = compare_rows(rows_a, rows_b)
        check("matched_pairs", result["matched_pairs"], 10)
        check("implausible", result["implausible"], 2)
        check("tolerance_rejected", result["tolerance_rejected"], 1)
        check("tolerance_blocked", result["tolerance_blocked"], 1)
        check("delta_samples", result["delta_samples"], 8)
        check("censored_fraction", round(result["censored_fraction"], 6), round(3 / 11, 6))
        check("p99_withheld", result["p99_withheld"], True)
        check("p999_withheld", result["p999_withheld"], True)

    def case_sample_floors():
        def floors_for(count):
            rows_a = [("m1", base + index * 1_000_000, f"n{index}") for index in range(count)]
            rows_b = [
                ("m1", base + index * 1_000_000 + 1_000, f"n{index}") for index in range(count)
            ]
            return compare_rows(rows_a, rows_b)

        small = floors_for(199)
        check("small_p99_withheld", small["p99_withheld"], True)
        check("small_p999_withheld", small["p999_withheld"], True)
        check("small_p99_cell", percentile_cell(small, "p99"), WITHHELD_CELL)
        middle = floors_for(1999)
        check("middle_p99_withheld", middle["p99_withheld"], False)
        check("middle_p999_withheld", middle["p999_withheld"], True)
        check("middle_p99_cell", percentile_cell(middle, "p99"), "1.0")
        large = floors_for(2000)
        check("large_p99_withheld", large["p99_withheld"], False)
        check("large_p999_withheld", large["p999_withheld"], False)
        check("large_p999_cell", percentile_cell(large, "p999"), "1.0")

    def case_trim():
        ramp_a = [("m1", base + index * NANOS_PER_SECOND, f"r{index}") for index in range(5)]
        tail_a = [
            ("m1", base + (11 + index) * NANOS_PER_SECOND, f"t{index}") for index in range(5)
        ]
        ramp_b = [
            ("m1", base + index * NANOS_PER_SECOND + 400, f"r{index}") for index in range(5)
        ]
        tail_b = [
            ("m1", base + (11 + index) * NANOS_PER_SECOND + 400, f"t{index}")
            for index in range(5)
        ]
        untrimmed = compare_rows(ramp_a + tail_a, ramp_b + tail_b, trim_seconds=0)
        check("untrimmed_pairs", untrimmed["matched_pairs"], 10)
        result = compare_rows(
            ramp_a + tail_a, ramp_b + tail_b, trim_seconds=DEFAULT_TRIM_SECONDS
        )
        check("trimmed_pairs", result["matched_pairs"], 5)
        check("trimmed_a_obs", result["a_obs"], 5)
        check("trimmed_b_obs", result["b_obs"], 5)
        check("a_obs_before_trim", result["a_obs_before_trim"], 10)
        check("p50_ns", result["p50_ns"], 400)

    def case_multi_market():
        rows_a = []
        rows_b = []
        for index in range(6):
            slug = "m1" if index % 2 == 0 else "m2"
            rows_a.append((slug, base + index * 1_000_000, f"{slug}-{index}"))
            rows_b.append((slug, base + index * 1_000_000 + 100, f"{slug}-{index}"))
        rows_a.append(("m3", base + 9_000_000, "m3-only"))
        result = compare_rows(rows_a, rows_b)
        check("a_markets", result["a_markets"], 3)
        check("b_markets", result["b_markets"], 2)
        check("markets_in_both", result["markets_matched"], 2)
        check("matched_pairs", result["matched_pairs"], 6)
        check("a_obs_total", result["a_obs"], 7)
        check("matched_fraction", round(result["matched_fraction"], 6), 1.0)
        check("frac_denominator_side", result["matched_fraction_denominator"], "b")
        check("matched_fraction_shared", round(result["matched_fraction_shared"], 6), 1.0)

    def case_malformed_lines():
        good = obs_lines("a-leg", 1, [("m1", base, "h0"), ("m1", base + 1_000_000, "h1")])
        broken = list(good)
        broken.insert(7, "obs m1 notanumber h9 0")
        broken.append("obs m1 1700000000000000000")
        log = parse_obs(broken, "<broken>")
        check("malformed", log.malformed, 2)
        check("rows", len(log.rows), 2)
        check("leg_header", log.headers.get("leg"), "a-leg")
        check("events_total_header", log.headers.get("events_total"), "2")
        check("has_revisions", log.has_revisions(), False)
        rev = parse_obs(
            [OBS_VERSION_HEADER, f"obs m1 {base} abcd 0 rev=12 extra"], "<rev>"
        )
        check("rev_rows", len(rev.rows), 1)
        check("rev_digest", rev.rows[0].digest, "abcd")
        check("rev_value", rev.rows[0].rev, 12)
        check("rev_has_revisions", rev.has_revisions(), True)
        bad_rev = parse_obs(
            [OBS_VERSION_HEADER, f"obs m1 {base} abcd 0 rev=notanumber"], "<badrev>"
        )
        check("bad_rev_value", bad_rev.rows[0].rev, None)
        check("bad_rev_has_revisions", bad_rev.has_revisions(), False)

    def case_resources():
        resources = parse_resources(
            [
                "# comment",
                "1700000000 1024 10.0",
                "1700000001 4096 20.0",
                "bad line",
                "1700000002 2048 30.0",
            ]
        )
        check("samples", resources["samples"], 3)
        check("max_rss_mib", round(resources["max_rss_mib"], 6), 4.0)
        check("mean_pcpu", round(resources["mean_pcpu"], 6), 20.0)
        check("empty", parse_resources([]), None)

    def case_markdown_row():
        rows_a = [("m1", base + index * 1_000_000, f"k{index}") for index in range(4)]
        rows_b = [("m1", base + index * 1_000_000 + 1500, f"k{index}") for index in range(4)]
        result = compare_rows(rows_a, rows_b)
        row = markdown_row(result, "rust-sdk", "rust-shm", "10")
        check(
            "row",
            row,
            "| 10 | rust-sdk vs rust-shm | digest | 4 | 1.0000 | a(4) | 0 | 0 | 0 | "
            "0.0000 | 1.5 | -- | -- | 0.0000 |",
        )
        check("header_columns", MARKDOWN_HEADER.count("|"), row.count("|"))
        check("rule_columns", MARKDOWN_RULE.count("|"), row.count("|"))

    run("exact percentiles", case_exact_percentiles)
    run("coalescing gap", case_coalescing_gap)
    run("duplicate digests", case_duplicate_digests)
    run("interleaved duplicates", case_interleaved_duplicates)
    run("disjoint start and stop", case_disjoint_start_stop)
    run("implausible clock step and signs", case_implausible_and_signs)
    run("gap wider than the window", case_gap_wider_than_window)
    run("tolerance gate blocks a slip", case_tolerance_gate_blocks_slip)
    run(
        "tolerance rejection the other side rescues",
        case_tolerance_rejection_the_other_side_rescues,
    )
    run("tolerance gate keeps real skew", case_tolerance_gate_keeps_real_skew)
    run("rev-keyed offset and coalesced gap", case_rev_keyed_offset_and_gap)
    run("rev absent falls back to digest", case_rev_absent_falls_back)
    run("censoring columns", case_censoring_columns)
    run("percentile sample floors", case_sample_floors)
    run("trim seconds", case_trim)
    run("multiple markets", case_multi_market)
    run("malformed lines", case_malformed_lines)
    run("resource samples", case_resources)
    run("markdown row", case_markdown_row)

    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        print(f"match_events.py: {len(failures)} self-test failure(s)", file=sys.stderr)
        return 1
    print("match_events.py: self-test passed")
    return 0


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("obs_a", nargs="?", help="reference leg observation log")
    parser.add_argument("obs_b", nargs="?", help="pm-ws leg observation log")
    parser.add_argument("--label-a", default=None)
    parser.add_argument("--label-b", default=None)
    parser.add_argument("--size", default=None)
    parser.add_argument("--window", type=int, default=DEFAULT_WINDOW)
    parser.add_argument("--trim-seconds", type=int, default=DEFAULT_TRIM_SECONDS)
    parser.add_argument("--tolerance-ms", type=int, default=DEFAULT_TOLERANCE_MS)
    parser.add_argument(
        "--alignment", choices=("auto", "digest", "rev"), default="auto"
    )
    parser.add_argument("--markdown", action="store_true")
    parser.add_argument("--resources-a", default=None)
    parser.add_argument("--resources-b", default=None)
    parser.add_argument("--resources", action="append", default=[])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return args
    if not args.obs_a or not args.obs_b:
        parser.error("two .obs files are required (or --self-test)")
    if args.window < 1:
        parser.error("--window must be at least 1")
    if args.trim_seconds < 0:
        parser.error("--trim-seconds must not be negative")
    if args.tolerance_ms < 0:
        parser.error("--tolerance-ms must not be negative (0 disables the gate)")
    if len(args.resources) > 2:
        parser.error("--resources accepts at most two files: A then B")
    if args.resources:
        if args.resources_a is None:
            args.resources_a = args.resources[0]
        if len(args.resources) > 1 and args.resources_b is None:
            args.resources_b = args.resources[1]
    return args


def main(argv=None):
    args = parse_args(argv)
    if args.self_test:
        return self_test()
    try:
        log_a = read_obs_file(args.obs_a)
        log_b = read_obs_file(args.obs_b)
        result = compare(
            log_a,
            log_b,
            window=args.window,
            trim_seconds=args.trim_seconds,
            tolerance_ns=args.tolerance_ms * NANOS_PER_MILLI,
            alignment=args.alignment,
        )
    except MatchError as error:
        print(f"match_events.py: {error}", file=sys.stderr)
        return 1
    label_a = label_for(args.label_a, log_a, args.obs_a)
    label_b = label_for(args.label_b, log_b, args.obs_b)
    size = args.size or log_b.size() or log_a.size() or "unknown"
    resources_a = read_resources_file(args.resources_a)
    resources_b = read_resources_file(args.resources_b)
    print_summary(result, label_a, label_b, size, resources_a, resources_b)
    if args.markdown:
        print(markdown_row(result, label_a, label_b, size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
