# Polymarket venue shape — owner requirements ahead of the venue row

Owner directive 2026-08-31. Recorded so the Polymarket adapter is built against the right rails;
venue facts get their own pinned `docs/polymarket.md` (with retrieved-claim dates) when the venue
row opens — nothing here is a verified wire fact yet.

## What the owner pinned

- Polymarket exposes **tick size as a first-class WS event** (tick size changes at runtime).
- Polymarket does **not** resend full books per change: the book is maintained from a snapshot
  base plus first-class **`price_change` delta events**. The adapter must APPLY those deltas and
  expose them as source-reported diffs — it must NOT reconstruct diffs by comparing snapshots the
  venue never sent.

## What the core already supports

- Tier-1 invariant: source snapshots, source deltas, and derived diffs stay distinguishable, with
  provenance and continuity preserved. `Candidate::source_delta` exists
  (`src/observation.rs:154`, requires `VenueNative` + `SourceReported`), and delivered mutations
  carry `Origin::SourceReported` vs `Origin::LocallyDerived(SnapshotDiff)` — consumers can already
  tell a venue-reported delta from a locally derived diff.
- `docs/design.md`: "A source delta is applied only when the adapter can establish the required
  base and continuity"; recovery-base machinery (stale → fresh snapshot base, epoch+1, no diffs
  across the gap) is venue-agnostic and fits delta venues exactly — a missed delta genuinely
  breaks a delta-built book, unlike Limitless where the next snapshot self-heals.
- `OrderBook::apply_source_delta` (`src/book.rs`) applies `CandidateOperation::SourceDelta`
  candidates: gated on an established base and intact continuity, it mutates only the delta'd
  coordinates and emits the venue's own diff — one source-reported mutation per delta'd
  coordinate whose value actually changes, in the venue's own order — never a diff reconstructed
  by comparing snapshots.
- `OrderBook::apply_snapshot` already reconciles a mid-stream sync snapshot against a delta-built
  book: one that agrees economically refreshes provenance with zero mutations (the checkpoint
  case), and one that disagrees is a mutation-continuity break — it commits as a recovery base
  (epoch+1, no diffs across the gap) and surfaces `SyncDivergence` naming the invalidated delta
  count, never a fabricated correction diff. This covers the rhythm the owner pinned above
  (snapshot on subscribe, a run of `price_change` events, a `book` snapshot again)
  venue-agnostically.

## Gaps to close

Tick size as venue-native dynamic market metadata: reproduced faithfully as its own state
dimension (like lifecycle — independent of book state), surfaced to consumers; never an
enforcement gate that drops venue book data. Waits for the venue row.
