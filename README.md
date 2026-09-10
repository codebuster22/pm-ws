# pm-ws

A venue-agnostic prediction-market data-feed daemon: it connects to venue WebSocket feeds (Limitless first),
keeps authoritative binary-market order books, and publishes latest state plus level mutations to local
consumers at ultra-low latency over redundant connections.

- `docs/design.md` — behavior and invariants
- `docs/limitless.md` — venue facts and live etiquette
- `docs/roadmap.md` — the ordered work list
- `AGENTS.md` — project rules

## Operate

```sh
cargo install --git https://github.com/codebuster22/pm-ws --locked pm-ws
```

or, from a clone, `cargo install --path . --locked`. Either installs `pmwsd` (the daemon),
`pmwsctl` (control CLI: add/remove/status), and `pmws-run` (single-market live tool).

The quickest look is one live market, no config file:

```sh
pmws-run --market <market-slug> --seconds 30 --print-book
```

Market identity is venue-native; `docs/limitless.md` covers market discovery and live etiquette.

A minimal config, e.g. `pmwsd.toml`:

```toml
control_socket = "/tmp/pmwsd.sock"
endpoint = "wss://ws.limitless.exchange/socket.io/?EIO=4&transport=websocket"
markets = ["btc-up-or-down-5-min-<epoch>"]
metrics_listen = "127.0.0.1:9090"
```

Run the daemon, then inspect it:

```sh
pmwsd --config pmwsd.toml
pmwsctl --socket /tmp/pmwsd.sock status
curl 127.0.0.1:9090/metrics
```

`pmwsctl add <slugs...>` / `remove <slugs...>` change the operator-pinned market set at
runtime. See `docs/design.md` for behavior and invariants, `docs/limitless.md` for venue
facts and live etiquette.

## Consume

The daemon maps each shard's books into a shared-memory segment file under the `[delivery]`
directory (default `/tmp`, one `pmws-<instance>-<shard>.seg` per shard). Consumers attach
read-only and follow latest state plus the mutation stream, with every price and quantity an
exact scaled decimal, never a float.

Python (`bindings/python/pmws.py`, standard library only):

```python
import pmws
with pmws.Segment("/tmp/pmws-<instance>-<shard>.seg") as segment:
    market = segment.resolve("limitless", "slug", "<market-slug>")
    state, stream = market.attach()
    print(state.best("Bid"), state.best("Ask"))
```

TypeScript: `bindings/node/pmws.ts`, the same `Segment`/`Market`/`EventStream` shape. Rust:
embed the crate, or read a segment directly (`examples/reader.rs`). Runnable strategy-shaped
consumers ship as examples:

```sh
python3 examples/bbo.py --segment <path> --market <slug> --events
node examples/bbo.ts --segment <path> --market <slug>
```

Both bindings load the daemon's compiled library from `target/release`, so consumers run from
a clone built with `cargo build --release`.

## Verify

```sh
./check
```

Runs `cargo fmt --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, and
`cargo test --workspace --locked`. Before a release or a dependency change, also run:

```sh
cargo deny check && cargo audit
```

Before a release, also regenerate third-party notices:

```sh
cargo about generate about.hbs -o THIRD-PARTY-NOTICES.md
```

Pinned tools: `cargo-deny 0.20.2`, `cargo-audit 0.22.2`, `cargo-about 0.9.2`. Toolchain is
pinned in `rust-toolchain.toml`.

## Benchmark

`bench/make_table.sh` produces the ship benchmark deterministically, with no venue traffic.
`bench/reports/` holds the checked-in results, each with the command that produced it.

## Licence

MIT, Chaain Labs — see `LICENSE`. Third-party crate notices, including full licence texts,
are in `THIRD-PARTY-NOTICES.md`.
