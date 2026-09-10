# Rust decisions — working notes

Design notes only, not policy — nothing may cite this file as a requirement source. Salvaged 2026-08-31 and collapsed from `docs/rust-best-practices/` (7 files, 668 lines), itself pinned from package metadata retrieved 2026-08-25. Versions and disposition drift as soon as they are revalidated against the locked graph.

## 1. Crate shortlist

The direct dependency set, pinned exactly in `Cargo.toml`:

| Role | Crate, pin | Why it earns its place |
|---|---|---|
| Runtime | tokio 1.51.4 | Selected features only (`rt`, `macros`, `time`, `net`, `sync`, `signal`, `io-util`), no `full`. |
| WebSocket | tokio-tungstenite 0.30.0 | Baseline for plain-WebSocket venues, TLS via `rustls-tls-webpki-roots`. Does not implement Socket.IO — the adapter owns that layer. |
| TLS | rustls 0.23.43 | `default-features = false`; explicit crypto provider and protocol features (`ring`, `std`, `tls12`, `logging`), no default bloat. |
| Async combinators | futures-util 0.3.34 | `default-features = false`; `sink` + `std` only, for the WebSocket read/write layer. |
| Serialization | serde 1.0.229 | `derive` only; typed venue envelopes. |
| JSON | serde_json 1.0.151 | Correctness baseline; parse numeric fields exactly. |
| Raw syscalls | libc 0.2.189 | `default-features = false`, `std` only; the Unix ABI beneath the shared-memory doorbell/wait-on-address path. |
| Memory mapping | memmap2 0.9.11 | Mapping primitive only; we own ABI and sync. |
| Config | toml 1.1.4+spec-1.1.0 | `default-features = false`; `std` + `serde` + `parse`; typed startup config, reject unknown fields. |

Dev-dependency: proptest 1.11.0 (`default-features = false`, `std`) for property-based testing.

### Rejections (with reasons — the most valuable part of this list)

- **Official Limitless Rust SDK** (`limitless-exchange-rust-sdk`, package 1.1.0, MIT). Bundled with unrelated trading/API dependencies; parses authoritative book values through `f64`; runs callbacks inline on the read loop; reconnect/subscription ownership doesn't meet our generation and replacement-set contracts. Useful only as pinned conformance evidence for observed wire behavior — never a runtime dependency.
- **rust_socketio 0.6.0.** Async client documented beta/experimental, last released 2024-04-16. Comparison only, not the authoritative client.
- **socketioxide 0.18.6.** A Socket.IO server implementation, not a venue client — wrong shape entirely.
- **shared_memory 0.12.4.** 2022-03-01 release, thin retrieved documentation, doesn't solve ABI/atomic safety.
- **sonic-rs 0.5.8.** A second SIMD JSON parser adds portability/unsafe-review cost before serde_json is proven inadequate.
- **rust_decimal 1.42.1.** Fine as a cold-path oracle; its general 96-bit representation is too broad for the compact scaled-integer hot representation.
- **kanal 0.1.1.** Low-level handoff/unsafe surface with no demonstrated need over topology-specific bounded queues.

## 2. Runtime and networking

Plain WebSocket is not Socket.IO. WebSocket gives framing, control frames, and fragmentation; Socket.IO adds an Engine.IO handshake (`sid`, `pingInterval`, `pingTimeout`, `maxPayload`), namespaces, event envelopes, acks, and binary attachment framing, currently Socket.IO protocol rev 5 over Engine.IO protocol rev 4. A plain-WebSocket crate alone is not a valid Limitless client — the adapter owns both layers with separate failure reasons.

Socket.IO client risk: no reviewed Rust client is production-approved. `sioc 0.5.0` is a young (first release May 2026) async Socket.IO v5/Engine.IO v4 candidate needing independent conformance validation; the alternative is a small hand-rolled Engine.IO/Socket.IO layer over tokio-tungstenite, checked against the official SDK as a behavioral reference only. Socket.IO guarantees intra-session ordering but defaults to at-most-once delivery with no server-side buffering for a disconnected client — this establishes nothing about ordering *between* redundant connections and does not remove the need for snapshot recovery.

Connection lifecycle states: resolving, dialing, TLS, protocol handshake, authenticated (if applicable), subscribing, snapshot-awaiting, live, continuity-lost, backing off, closed. Every in-progress step with an expected completion carries a deadline and a reason; stable-live and ordinary silence do not. An open TCP socket alone is not "healthy." Assign a monotonically increasing local connection generation per reconnect and carry it through decode/ingress/provenance/publication so a stale task can't mutate the new generation.

Reconnect rules: detect venue heartbeat failure separately from WebSocket ping failure; capped exponential backoff with full jitter per endpoint/account, honoring venue limits; reset backoff only after a defined stable-live interval, not on raw TCP connect; rate-limit startup/mass recovery so a large subscription set can't cause a handshake storm; resubscribe from the current desired set, wait for a valid venue snapshot, publish continuity-restored state only once venue rules allow it; keep the old book explicitly stale/unavailable, never silently current; use a monotonic clock for deadlines/latency, wall time only as separately sourced metadata.

## 3. Order book and concurrency

Parse venue decimal text directly into a fixed-width scaled integer; reject overflow/excess precision rather than rounding through `f64`. Select the smallest integer widths only after captured, documented venue ranges prove them; floating point stays acceptable only for non-authoritative telemetry where the metric contract allows it.

For a venue whose conformance evidence shows exact mirrored binary liquidity, store one physical ladder and expose two outcome views by a deterministic transform — never two independently mutable copies, which doubles memory and invites divergence.

One long-lived owner mutates each authoritative book (single-writer sharding). Assign many books per shard rather than a thread/task per market; avoid `Arc<Mutex<Book>>`, shared maps touched by transport tasks, or work-stealing of individual mutations — they obscure ordering and make overload behavior scheduler-dependent. Reads happen through published state, never by taking the writer's lock.

Every edge (queue/ring) declares producer count, consumer count, capacity, memory cost, wakeup policy, and overflow behavior — "bounded" without a stated overflow contract is incomplete. Authoritative ingress cannot silently drop: if its bounded queue can't accept an event, that's a distinct local-overload continuity failure that invalidates the affected candidate and recovers through venue rules, not a silent skip. Consumer mutation rings may overwrite only when the contract gives per-slot sequence numbers and explicit lag detection — a lagged consumer rereads state and cannot claim it saw every mutation.

## 4. Shared memory and clients

Never map a Rust struct graph directly — a stable segment needs a specified binary ABI: magic/version/byte-order/length/schema-hash/feature-bits, instance ID/generation/epoch/heartbeat, fixed-width integer fields at explicit offsets, explicit alignment/padding/reserved bytes/sentinels/atomic-width requirements, directory entries from local handles to venue-native identity, per-book state slots plus a separate mutation ring — no pointers, references, `usize`, Rust `bool`, `repr(Rust)` enums, or language-owned object headers.

The ABI defines integer units and scale directly; it never exposes a floating authoritative field. Consumers validate the entire header and every offset before reading anything else; unknown major versions fail closed, and minor versions may only add behavior through declared, compatible reserved fields. `memmap2` is the baseline mapping primitive, not a synchronization solution — the project owns file creation, sizing, lifetime, and permissions, and exposes read-only mappings to clients where possible.

**Seqlock warning:** a conventional seqlock that writes ordinary non-atomic Rust fields while another process reads them is not automatically valid — Rust forbids conflicting non-synchronized accesses, and mixing atomic and non-atomic access on the same memory can be undefined behavior. Mapping bytes does not relax Rust's memory rules; every concurrently-written word needs to be an actual atomic of the right width, and the design needs a written protocol plus cross-process evidence on every supported architecture before it can be called sound, not a claim that "the copy is usually fast."

Public identities stay venue-native and venue-scoped; compact handles are valid only for the advertised instance/generation and are never exposed as public identity.

## 5. Observability

Metric labels use small bounded dimensions only (venue, adapter/rail, event class, failure class, maybe a configured shard index). Never label a general metric by market ID, outcome ID, subscription ID, connection UUID, client ID, error string, URL, or sequence number — that's unbounded cardinality against a venue with thousands of markets. Market-specific inspection belongs in bounded, on-demand diagnostics, not steady-state metrics.

## 6. Toolchain

Don't optimize allocator choice, SIMD parsing, custom WebSocket framing, busy polling, CPU affinity, huge pages, LTO/PGO, or lock-free IPC before profiling identifies the actual cost. First remove steady-state allocation, cloning, formatting, and lock contention from the update path — toolchain tuning cannot compensate for an allocation-heavy or incorrectly shared design.
