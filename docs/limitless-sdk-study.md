# Official Rust SDK study

Reviewed on: 2026-08-25

Purpose: use the official SDK as protocol and payload evidence while designing a smaller feed-only client. The daemon will not depend on or copy the SDK. Venue documentation and live conformance remain authoritative over SDK behavior.

## Source pin

| Field | Value |
|---|---|
| Repository | [limitless-exchange-rust-sdk](https://github.com/limitless-labs-group/limitless-exchange-rust-sdk) |
| Reviewed commit | [`b1ad2e108e96f05b615d513d3f32237a775177f8`](https://github.com/limitless-labs-group/limitless-exchange-rust-sdk/tree/b1ad2e108e96f05b615d513d3f32237a775177f8) |
| Commit date | 2026-08-11 |
| Package version | `1.1.0` |
| Declared Rust version | `1.74` |
| Licence | MIT |
| WebSocket implementation | `src/websocket.rs`, 1,846 lines at the reviewed commit |
| WebSocket source SHA-256 | `13acb731f99f73c7a5d497a284a66165fd09cd54e7a166b208cb4e1d1e928a4a` |
| Markets source SHA-256 | `59087f04cc908400716aac22c6d69aedbbb80b77abc34424086a8a5b363d1299` |
| Manifest SHA-256 | `7530f75cf22741f901c5ebbaeffa95a1c09366becbd2b2ab245548b3791d3c86` |

The inspected source was cloned into a temporary directory and was not added to this repository.

## Main conclusion

The SDK validates that Limitless does not require a large general-purpose Socket.IO dependency. Its client implements a limited Engine.IO v4 and Socket.IO v5 path directly over `tokio-tungstenite`, Rustls, and Tokio.

That approach matches this project's intended direction, but the SDK implementation itself is not suitable for the daemon. It is a full trading SDK with unconditional HTTP, signing, order, retry, and market dependencies; it uses floating point for authoritative book values; and its callback, reconnection, subscription, and continuity behavior does not meet this daemon's bounded low-latency contracts.

The project should therefore implement and conformance-test only the protocol subset required by the Limitless feed rail.

## Minimal public-feed interaction

The required wire flow, subject to live conformance, is:

1. Resolve `ws.limitless.exchange`, establish TCP and TLS, and enable WebSocket control-frame processing with explicit frame and message bounds.
2. Send a WebSocket upgrade request to `/socket.io/?EIO=4&transport=websocket`. Public market data requires no authentication. Do not claim the official SDK's tracking headers.
3. Receive an Engine.IO `open` packet. Parse and retain `sid`, `pingInterval`, `pingTimeout`, and `maxPayload`; reject missing, invalid, or out-of-policy values.
4. Send the Socket.IO namespace connect packet for `/markets` inside an Engine.IO message.
5. Accept namespace readiness only after a matching Socket.IO connect response for `/markets`. A connect-error packet fails the protocol session.
6. Emit one aggregate `subscribe_market_prices` event containing the complete current `marketSlugs` set assigned to that connection. A later call replaces the earlier set.
7. Decode `orderbookUpdate`, `marketResolved`, `system`, and `exception` events needed by the accepted scope. Preserve unknown events or variants according to the adapter's bounded native-event policy rather than treating them as book mutations.
8. Respond to every Engine.IO server ping with its matching pong and fail the connection if no ping arrives within the server-advertised interval plus timeout. WebSocket ping/pong remains a separate framing mechanism.
9. On shutdown, send the `/markets` namespace disconnect where practical, then close the WebSocket. On failure, discard the connection generation and recover from the newest desired set.

For reference, an ordinary event without an acknowledgment is encoded by Socket.IO as packet type, optional namespace, then JSON payload, and is wrapped in an Engine.IO message. Acknowledgment IDs follow the namespace, not precede it. The project should use acknowledgments only for venue operations whose response behavior has been observed and pinned.

## Required protocol subset

The first Limitless rail needs:

- Engine.IO open, close, ping, pong, and message packets over WebSocket-only transport.
- Socket.IO namespace connect, disconnect, event, connect-error, and any acknowledgment form proven necessary by conformance.
- Text events used by public CLOB books, resolution, system responses, and exceptions.
- WebSocket fragmentation and control-frame handling supplied by the selected WebSocket layer.
- Explicit limits for HTTP upgrade bytes, WebSocket frame/message bytes, Engine.IO opening values, JSON nesting, number of book levels, identifier length, and command size.

Binary Socket.IO attachments, polling upgrades, authenticated order/position channels, AMM price streams, and general callback registration are outside the required first rail. If the server sends an unsupported required packet, the rail reports a protocol failure and recovers; it does not silently ignore data that could affect continuity.

## Useful SDK evidence

The SDK provides useful evidence for:

- Direct WebSocket transport at `/socket.io/?EIO=4&transport=websocket`.
- The `/markets` namespace connection sequence.
- Server-initiated Engine.IO ping and client pong handling.
- Event framing for `subscribe_market_prices` and public server events.
- `TCP_NODELAY`, Rustls, WebSocket upgrade validation, and bounded HTTP-upgrade response bytes.
- Re-emitting subscriptions after a new session.
- The current typed payload inventory, including a source expectation that the live book may contain `tokenId` and additional book metadata not shown in the public event example.

SDK behavior is implementation evidence, not a venue guarantee. In particular, the documented WebSocket example omits `orderbook.tokenId`, while the SDK makes it required. Live captures must settle that difference.

## Mechanics not to copy

### Dependency and scope weight

The crate has no feed-only feature boundary. Its manifest unconditionally includes HTTP, cryptographic signing, big integers, order construction, retry, and trading dependencies in addition to its WebSocket stack. Using it would import unrelated behavior and make hot-path dependency review much larger.

### Authoritative numerics

The SDK deserializes order-book price and size into `f64`, and its flexible scalar wrapper also converts strings or JSON numbers to `f64`. That violates this project's exact-authoritative-state invariant and loses the original numeric lexeme needed for precision validation.

### Read-loop callbacks

SDK handlers are synchronous callbacks invoked directly by the socket read loop. A slow handler therefore delays heartbeat and subsequent frame processing. The daemon instead needs minimal decode on the connection task followed by a bounded handoff to the owning book writer.

### Replacement-subscription replay

The SDK retains subscriptions in a hash map keyed by channel and options and replays every entry after reconnect. Limitless documents `subscribe_market_prices` as replacement of the previous set. Replaying several saved calls in unspecified hash-map order can leave an unpredictable final server set.

The daemon must retain exactly one aggregate desired set per replacement-style channel and connection, serialize set transitions, and never replay historical commands.

### Authority and generations

The SDK exposes connection state but has no connection-generation token carried through reads, subscriptions, callbacks, and state mutation. An old task can therefore race a newly installed socket. The daemon must make all work from an obsolete generation ineligible before a replacement becomes current.

### Heartbeat supervision

The SDK parses the Engine.IO opening JSON only as an untyped value and does not retain `pingInterval`, `pingTimeout`, or `maxPayload`. It responds when a ping arrives but does not establish the client-side deadline required to detect a missing server ping. The daemon must use the negotiated heartbeat values as connection liveness evidence.

### Reconnection policy

The SDK uses exponential delay without jitter, resets attempts immediately after protocol connect, and has no stable-live reset interval. Its reconnect path does not apply the initial connection timeout around the whole attempt, ignores resubscription emission failures, and declares connected before any book regains authority. The daemon's connection, subscription, and per-book authority states must remain separate.

### Socket.IO acknowledgment parsing

The reviewed SDK constructs acknowledgment-bearing custom-namespace packets with the ID before the namespace and parses acknowledgments as if the ID were first. Socket.IO v5 specifies namespace before acknowledgment ID. This source path must not be treated as protocol truth; any acknowledgment needed by the daemon requires protocol-suite and live-venue tests.

### Error and logging behavior

Some invalid binary data and unsupported packet variants are ignored, typed event parse failures become log messages, and optional debug logging formats complete outbound packets. The daemon must produce typed bounded failure reasons, prevent sensitive payload logging, and make continuity consequences explicit.

## Subscription and resolution consequences

Default resolution coverage follows the concrete CLOB markets already subscribed through `subscribe_market_prices`, because the venue documents `marketResolved` delivery to existing per-market rooms. A separate venue-wide lifecycle mode may be requested explicitly; it is not required to maintain books.

When both paths are enabled, the same resolution may arrive through the lifecycle room and a per-market room without a stable event ID. The daemon does not infer exact duplication. It preserves each accepted native arrival with delivery-path provenance and updates the bounded latest resolution observation for retained desired markets.

The global lifecycle path must not allocate permanent state for every market. Events for targets outside the retained desired set are reactive, bounded, and subject to explicit event-window continuity.

## Market and outcome identity

The documented order-book event is keyed by market slug and its public example omits token identifiers. The reviewed SDK expects a `tokenId` inside the book, while `GET /markets/{slug}` exposes optional YES and NO token metadata.

The first WebSocket-only rail therefore treats the slug as the canonical subscription identity and YES/NO as venue outcome sides. It preserves a token identifier when actually present on the WebSocket payload but does not invent the missing opposite token.

Additional token aliases may be supplied by a versioned external market descriptor through the control boundary. This metadata is not authoritative book data and must be provenance-tagged and checked against any token identifier later observed on the feed. The daemon does not add a hidden REST dependency for metadata bootstrap. A future built-in metadata query requires explicit SRS review.

## Conformance questions

The questions this study raised are merged with the feed contract's open items and the SRS vendor-assumption table in [what the first live connection must settle](./limitless.md#what-the-first-live-connection-must-settle).
