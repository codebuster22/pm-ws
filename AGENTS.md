# pm-ws — project rules

## The product

A Rust daemon that connects to prediction-market venue WebSocket feeds (Limitless first), keeps authoritative
binary-market order books, and publishes latest state plus level mutations to local Rust, Python, and TypeScript
consumers at ultra-low latency over redundant connections. Nothing else. Venues are added in-tree by this team;
venue-specific behavior stays inside that venue's adapter and the core stays venue-agnostic.
`docs/design.md` describes behavior and invariants, `docs/limitless.md` pins venue facts and live etiquette,
`docs/roadmap.md` is the ordered work list, `docs/notes/` holds reusable research. Keep the document set that small.

## Invariants — tier 1

Changing one of these needs a test that fails without the change and one bounded adversarial review.

- No floating point in authoritative prices, quantities, or depths. Parse venue decimals exactly into scaled
  integers; reject unrepresentable precision rather than rounding.
- One writer per authoritative book. Readers read published state, never the writer's lock.
- Every queue and mutation ring is bounded and states its overflow behavior. A slow consumer never blocks
  ingestion.
- Book authority is evidence-based. A quiet subscribed book stays live; no inactivity timer makes it stale
  unless the venue guarantees a cadence.
- Reproduce venue-reported data; never invent market policy. Lifecycle and book state are independent.
- Public identity is venue-native and venue-scoped. Internal handles are process-local routing aids, never
  external identifiers.
- A mirrored binary market is one physical book with two views; never double-count its liquidity.
- Redundant connections publish through the venue-key gate where the venue's declared key semantics
  admit it, and nothing rolls a published book backward. Where they do not — and for the rest of the
  process after a conformance violation — one publishing primary, independent hot standbys. A divergent
  standby is never promoted without venue ordering proof or a fresh recovery base; availability
  pressure is not proof.
- Ingestion is WebSocket-only; recovery is resubscribe then reconnect; REST recovery is opt-in only.
- Source snapshots, source deltas, and derived diffs stay distinguishable; provenance and continuity are
  preserved; malformed input, gap, overload, disconnect, and divergence stay distinct reasons.
- No blocking I/O, persistence, or consumer backpressure on the update path.
- Controllers submit desired market sets; they never inject market data.

Everything else — tooling, fixtures, prototypes, benchmarks, docs — is tier 2: make it work, test it normally,
move on.

## Product contracts

The full text lives in `docs/design.md`; these are behavior, not hazards. Each venue owns its transport,
protocol, ordering, subscription, and recovery rail. Strategies get a normalized economic book by default and a
venue-native view on request. NegRisk grouping is outside the daemon. Latest-state and mutation delivery are two
coordinated outputs of one book. Demand is operator-pinned sets plus reference-counted client leases. Observed
raw venue frames are kept as decoder regression tests. Latency is reported as distributions and queue age, never
averages alone.

## Proportionality

- Done means observable: a command shows the behavior. "Evidence produced" and "reviewed" are not done.
- One command proves a change: `./check` (fmt, clippy `-D warnings`, test). Green before merge.
  `cargo deny check && cargo audit` before a release or a dependency change.
- At most two review cycles on anything. Then decide: accept with named residual risks, or change the design.
  A finding with no user-visible consequence is a note, not a blocker. Tier-2 work needs no formal review.
- Rigor follows blast radius. A twenty-line fix costs a test and a sentence.
- Briefs state an outcome and a maximum: bounded new source, no new framework; if it will not fit, stop and say so.
- Evidence is generated, not written. If rerunning a command cannot reproduce a record, do not keep it.
  A latency claim names the machine and the workload.
- No mandatory planning session. Ask, decide, build. Stop and ask the owner only before altering a tier-1
  invariant, adding a runtime dependency, or sending live venue traffic beyond the etiquette in `docs/limitless.md`.
- Do not build a component whose only consumer is another component of the same task.

## Code

- No inline `//` comments by default — names, types, and tests carry the meaning. Exceptions: a temporary
  workaround, genuinely complex mechanics, and `// SAFETY:` on every `unsafe` block.
- Doc comments state contract behavior: inputs, outputs, failures, invariants, units. New public APIs are
  documented as they are written; the salvaged surface gets its docs as the S-items touch it.
- No comment is a ledger: no history, status, plans, task lists, ownership, or quality claims.
- `Cargo.lock` is committed. New dependencies are explicit, minimal, and needed by the daemon.

## Agents

- Always pass an explicit model. Claude: Sonnet 5 mechanical/medium, Haiku pure-mechanical, Opus 5 high
  reasoning. Codex: GPT-5.6 Sol for bounded adversarial review (fresh session per cycle, max two, structured
  brief — ~300k context), Terra ≈ Opus/Sonnet, Luna ≈ Haiku, GPT-6 Astra (standalone `codex`
  CLI, `codex update` first) for broad read-only audits.
- Do not use `superpowers:*` skills here.
- `CLAUDE.local.md` is the handoff: what is being built, what is broken, the exact next step. Current facts
  only — rewrite it, never append. No credentials.
