#!/usr/bin/env node
/**
 * The S8c `ts-sdk` leg: a consumer over the official `@limitless-exchange/sdk` (pinned
 * `1.1.0`), side by side with the `ts-binding` leg (`examples/bench_consumer.ts --obs-out`)
 * against the identical pinned market set. See `bench/sdk-harness/README.md` for the full
 * method — the boundary definition, the canonical-decimal and FNV-1a 64 digest, and the
 * `.obs` file format this leg and its binding counterpart both write, matched afterward by
 * `bench/sdk-harness/match_events.py`.
 *
 * This leg subscribes every slug in one call to `subscribe_market_prices` and stamps
 * `t_obs` inside the synchronous `orderbookUpdate` callback, immediately after the update
 * is stored into this leg's own slug -> book map — its own "minimal book handling" — and
 * before anything else, per the README's boundary definition. Digesting and recording
 * happen strictly after the stamp.
 *
 * Usage:
 *     node sdk_leg.ts --slugs <file> --seconds <n> --obs-out <path> --label <text>
 *                      [--endpoint <url>]
 *     node sdk_leg.ts --self-test
 *
 * `--self-test` checks the canonical-decimal vectors and the FNV-1a 64 digest against a
 * golden value shared with `examples/bench_consumer.ts`'s own `--self-test`, and exits
 * without opening any socket or reading `--slugs`.
 *
 * **Clock domain.** `t_obs` is CLOCK_REALTIME epoch nanoseconds, the same domain the daemon
 * stamps `arrival_time`/`commit_time` in and `bench_consumer.ts` derives for its own `t_obs`.
 * Node exposes no epoch-nanosecond clock, so this leg derives the realtime-minus-monotonic
 * offset the identical way `bench_consumer.ts` does: a keeper thread performs
 * millisecond-edge derivations once a second, projects the published offset forward at the
 * window's own divergence rate, and poisons a generation that disagrees with its own
 * projection by more than a clock-step threshold. That whole mechanism — every constant,
 * every guard, the reasoning for each — is copied verbatim from `examples/bench_consumer.ts`
 * below; see that file's header comment for the full measurement history (macOS M1 and
 * Linux i9-14900K/WSL2 divergence and step figures) behind every constant here. This file
 * duplicates it rather than importing it: `bench/sdk-harness/ts` is an isolated npm project
 * and never imports from the main crate's `examples/`.
 *
 * Unlike `bench_consumer.ts`, this leg never blocks the event loop on a native call, so the
 * calibration this leg reads is cached and refreshed on its own timer rather than read fresh
 * inside the hot callback: a seqlock retry loop is pre-stamp work, and the README is explicit
 * that only digesting, logging, and bookkeeping belong after `t_obs`, never before it.
 *
 * **Reconnection.** The installed `@limitless-exchange/sdk@1.1.0` source
 * (`node_modules/@limitless-exchange/sdk/dist/index.mjs`) resubscribes every remembered
 * channel itself: `WebSocketClient.connect()` registers `this.socket.io.on("reconnect", ...)`
 * inside `setupEventHandlers()`, and that handler calls the client's own `resubscribeAll()`,
 * which replays `subscribe(channel, options)` for every entry in the `subscriptions` map this
 * leg's one `subscribe('subscribe_market_prices', { marketSlugs: [...] })` call populated.
 * This leg therefore never re-sends the subscription itself — doing so as well would emit a
 * second `subscribe_market_prices` per reconnect against a venue this benchmark is under an
 * etiquette budget with, and, if the server honors it, would double-deliver
 * `orderbookUpdate` and corrupt the very digest/event-count comparison this leg exists to
 * produce. It only counts reconnects, on the public `connect` event (which the underlying
 * `socket.io` `Socket` re-emits on every reconnection, unlike the `reconnecting` event this
 * SDK's own public type declares: that one is wired to a literal event named `"reconnecting"`
 * on the `Socket`, which nothing in the installed source ever emits — only the *manager's*
 * differently-named `reconnect_attempt` does, one layer down at `this.socket.io`, which the
 * public API never exposes).
 *
 * `maxReconnectAttempts` is capped, not left at the SDK's own default (`Infinity`): with the
 * default `reconnectDelay` of 1000 ms, `index.mjs`'s own connect() caps the backoff at
 * `min(reconnectDelay * 32, 60_000)` = 32 s once it saturates, so a cap must be at least
 * `ceil(longest_rung_seconds / 32)` to be reachable inside one run rather than exhausting the
 * run first — `ceil(900 / 32)` = 29 for the longest all-active rung this harness runs
 * (`--all-active-seconds 900`). `RECONNECT_ATTEMPTS_CAP` below is set well above that floor,
 * a safety bound against a truly dead venue rather than a policy that can bite inside a rung.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { isMainThread, parentPort, workerData, Worker } from "node:worker_threads";
import { WebSocketClient } from "@limitless-exchange/sdk";
import type { OrderbookUpdate } from "@limitless-exchange/sdk";

const SDK_PIN = "@limitless-exchange/sdk@1.1.0";

const MAX_SECONDS = 86_400;
const MAX_SLUGS = 4_096;
const MAX_OBS_ROWS = 4_000_000;

const RECONNECT_ATTEMPTS_CAP = 40;
const RECONNECT_DELAY_MS = 1_000;
const CALIBRATION_CACHE_REFRESH_MS = 100;

const CALIBRATION_WARMUP_MS = 200;
const CALIBRATION_INTERVAL_MS = 1_000;
const CALIBRATION_EDGES = 4;
const CALIBRATION_WINDOW = 16;
const CALIBRATION_READY_TIMEOUT_MS = 15_000;
const KEEPER_POLL_MS = 20;

const CLOCK_ORIGIN = 0;
const CLOCK_OFFSET = 1;
const CLOCK_RATE = 2;
const CLOCK_DERIVATIONS = 3;
const CLOCK_WORDS = 4;

/** The widest realtime-against-monotonic divergence this leg will project at, in thousandths
 * of a nanosecond per second — 200 µs/s, about 200 ppm. Copied from `bench_consumer.ts`;
 * see that file's header comment for the measurement behind it. */
const MAX_DIVERGENCE_MILLI_NS_PER_S = 200_000_000n;

/** How far one derivation may disagree with the previous calibration's projection before it
 * is read as a host clock step rather than drift. Copied from `bench_consumer.ts`. */
const CLOCK_STEP_THRESHOLD_NS = 2_000_000n;

/** How far the published calibration may disagree with `Date.now()` before it is refused.
 * Copied from `bench_consumer.ts`. */
const CLOCK_SANITY_LOW_NS = -2_000_000n;
const CLOCK_SANITY_HIGH_NS = 3_000_000n;

const CONTROL_VERSION = 0;
const CONTROL_STOP = 1;
const CONTROL_SLEEPER = 2;
const CONTROL_CLOCK_GENERATION = 3;
const CONTROL_CLOCK_POISONED = 4;
const CONTROL_CLOCK_STEPS = 5;
const CONTROL_CLOCK_REJECTED = 6;
const CONTROL_WORDS = 7;

/** The cross-thread clock surface, copied verbatim from `bench_consumer.ts`: the derived
 * clock plus the calibration worker's own counters. This leg holds no control-channel
 * session at all, so unlike `bench_consumer.ts` there was never anything else to put here. */
interface Shared {
  clock: BigInt64Array;
  control: Int32Array;
}

function sharedViews(buffer: SharedArrayBuffer): Shared {
  return {
    clock: new BigInt64Array(buffer, 0, CLOCK_WORDS),
    control: new Int32Array(buffer, CLOCK_WORDS * 8, CONTROL_WORDS),
  };
}

function sharedBuffer(): SharedArrayBuffer {
  return new SharedArrayBuffer(CLOCK_WORDS * 8 + CONTROL_WORDS * 4);
}

interface Derivation {
  hr: bigint;
  estimate: bigint;
}

/** One millisecond-edge derivation of the realtime-minus-monotonic offset. Copied verbatim
 * from `bench_consumer.ts`; see that file's header comment for why this is a lower bound and
 * why the best of several edges is kept rather than a maximum over the whole window. */
function deriveOffset(): Derivation {
  let best: bigint | null = null;
  let bestHr = 0n;
  for (let edge = 0; edge < CALIBRATION_EDGES; edge += 1) {
    const start = Date.now();
    let ms = start;
    let hr = 0n;
    do {
      ms = Date.now();
      hr = process.hrtime.bigint();
    } while (ms === start);
    const estimate = BigInt(ms) * 1_000_000n - hr;
    if (best === null || estimate > best) {
      best = estimate;
      bestHr = hr;
    }
  }
  return { hr: bestHr, estimate: best as bigint };
}

/** The divergence rate the window implies, in thousandths of a nanosecond per second. Copied
 * verbatim from `bench_consumer.ts`. */
function divergenceRate(window: Derivation[]): bigint {
  if (window.length < 2) {
    return 0n;
  }
  const slopes: bigint[] = [];
  for (let i = 1; i < window.length; i += 1) {
    const span = window[i].hr - window[i - 1].hr;
    if (span > 0n) {
      slopes.push(((window[i].estimate - window[i - 1].estimate) * 1_000_000_000_000n) / span);
    }
  }
  if (slopes.length === 0) {
    return 0n;
  }
  slopes.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const median = slopes[Math.floor(slopes.length / 2)];
  if (median > MAX_DIVERGENCE_MILLI_NS_PER_S) {
    return MAX_DIVERGENCE_MILLI_NS_PER_S;
  }
  if (median < -MAX_DIVERGENCE_MILLI_NS_PER_S) {
    return -MAX_DIVERGENCE_MILLI_NS_PER_S;
  }
  return median;
}

interface Calibration {
  offset: bigint;
  rate: bigint;
  generation: number;
}

/** Reads the keeper's published calibration without tearing, through the sequence counter
 * the keeper brackets every publication with. Copied verbatim from `bench_consumer.ts`. This
 * leg never calls it from the hot `orderbookUpdate` path — see the file header — only from
 * the periodic cache refresh and from startup. */
function readCalibration(shared: Shared): Calibration {
  for (;;) {
    const first = Atomics.load(shared.control, CONTROL_VERSION);
    if ((first & 1) === 1) {
      continue;
    }
    const offset = Atomics.load(shared.clock, CLOCK_OFFSET);
    const rate = Atomics.load(shared.clock, CLOCK_RATE);
    const generation = Atomics.load(shared.control, CONTROL_CLOCK_GENERATION);
    if (Atomics.load(shared.control, CONTROL_VERSION) === first) {
      return { offset, rate, generation };
    }
  }
}

/** CLOCK_REALTIME epoch nanoseconds for a monotonic reading, under `calibration`. Copied
 * verbatim from `bench_consumer.ts`. */
function epochNanos(hr: bigint, origin: bigint, calibration: Calibration): bigint {
  return hr + calibration.offset + (calibration.rate * (hr - origin)) / 1_000_000_000_000n;
}

interface KeeperOptions {
  buffer: SharedArrayBuffer;
}

/** The keeper thread: the clock calibration alone, copied verbatim from
 * `bench_consumer.ts`'s own keeper — that file's copy no longer holds any session either, so
 * there was nothing to leave out. See its header comment for the full reasoning behind the
 * step and sanity guards. */
function runKeeper(options: KeeperOptions): void {
  const shared = sharedViews(options.buffer);
  let nextCalibration = 0;
  let derivations = 0;
  let published: Calibration | null = null;
  const window: Derivation[] = [];

  const calibrate = (): void => {
    derivations += 1;
    const derived = deriveOffset();
    const origin = Atomics.load(shared.clock, CLOCK_ORIGIN);

    if (published !== null) {
      const projected =
        published.offset + (published.rate * (derived.hr - origin)) / 1_000_000_000_000n;
      const disagreement = derived.estimate - projected;
      if (disagreement > CLOCK_STEP_THRESHOLD_NS || disagreement < -CLOCK_STEP_THRESHOLD_NS) {
        Atomics.add(shared.control, CONTROL_CLOCK_STEPS, 1);
        Atomics.store(shared.control, CONTROL_CLOCK_POISONED, published.generation);
      }
    }

    window.push(derived);
    if (window.length > CALIBRATION_WINDOW) {
      window.shift();
    }
    const rate = divergenceRate(window);
    const offset = derived.estimate - (rate * (derived.hr - origin)) / 1_000_000_000_000n;

    const hr = process.hrtime.bigint();
    const disagreement =
      hr + offset + (rate * (hr - origin)) / 1_000_000_000_000n - BigInt(Date.now()) * 1_000_000n;
    if (disagreement < CLOCK_SANITY_LOW_NS || disagreement > CLOCK_SANITY_HIGH_NS) {
      Atomics.add(shared.control, CONTROL_CLOCK_REJECTED, 1);
      if (published !== null) {
        Atomics.store(shared.control, CONTROL_CLOCK_POISONED, published.generation);
      }
      return;
    }

    const generation = (published?.generation ?? 0) + 1;
    Atomics.add(shared.control, CONTROL_VERSION, 1);
    Atomics.store(shared.clock, CLOCK_OFFSET, offset);
    Atomics.store(shared.clock, CLOCK_RATE, rate);
    Atomics.store(shared.clock, CLOCK_DERIVATIONS, BigInt(derivations));
    Atomics.store(shared.control, CONTROL_CLOCK_GENERATION, generation);
    Atomics.add(shared.control, CONTROL_VERSION, 1);
    published = { offset, rate, generation };
  };

  while (Atomics.load(shared.control, CONTROL_STOP) === 0) {
    const now = Date.now();
    if (now >= nextCalibration) {
      calibrate();
      nextCalibration =
        Date.now() +
        (window.length < CALIBRATION_WINDOW ? CALIBRATION_WARMUP_MS : CALIBRATION_INTERVAL_MS);
    }
    Atomics.wait(shared.control, CONTROL_SLEEPER, 0, KEEPER_POLL_MS);
  }
}

/** One level's price and quantity as decimal text, the shared digest's only input shape.
 *
 * Identical in `examples/bench_consumer.ts`: there `text` is the ABI's own exact decimal
 * lexeme, here it is `String(n)` on the SDK's float, per the README's canonicalization rule
 * for each source. */
interface DigestLevel {
  price: string;
  qty: string;
}

const EXPONENTIAL_RE = /^([+-]?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$/;

/** Expands `e`/`E` scientific notation to plain decimal digits, exactly, with no floating
 * arithmetic. `String(1e-7) === "1e-7"` is exactly the case this exists for: the vector is
 * `"1e-7" -> "0.0000001"`. Identical in `examples/bench_consumer.ts`. */
function expandExponential(raw: string): string {
  const match = EXPONENTIAL_RE.exec(raw);
  if (match === null) {
    return raw;
  }
  const sign = match[1];
  const intPart = match[2];
  const fracPart = match[3] ?? "";
  const exponent = Number.parseInt(match[4], 10);
  const digits = intPart + fracPart;
  const pointPosition = intPart.length + exponent;
  let magnitude: string;
  if (pointPosition <= 0) {
    magnitude = `0.${"0".repeat(-pointPosition)}${digits}`;
  } else if (pointPosition >= digits.length) {
    magnitude = `${digits}${"0".repeat(pointPosition - digits.length)}`;
  } else {
    magnitude = `${digits.slice(0, pointPosition)}.${digits.slice(pointPosition)}`;
  }
  return sign + magnitude;
}

/** Strips redundant leading zeros from the integer part (`"007"` -> `"7"`), leaving a lone
 * `"0"` alone. Identical in `examples/bench_consumer.ts`. */
function stripLeadingZeros(raw: string): string {
  const negative = raw.startsWith("-");
  const unsigned = negative ? raw.slice(1) : raw;
  const dot = unsigned.indexOf(".");
  const intPart = dot === -1 ? unsigned : unsigned.slice(0, dot);
  const fracPart = dot === -1 ? null : unsigned.slice(dot + 1);
  const strippedInt = intPart.replace(/^0+(?=\d)/, "");
  return (negative ? "-" : "") + strippedInt + (fracPart === null ? "" : `.${fracPart}`);
}

/** Strips trailing fractional zeros, then a bare trailing `.`. Identical in
 * `examples/bench_consumer.ts`. */
function stripTrailingZerosAndDot(raw: string): string {
  if (!raw.includes(".")) {
    return raw;
  }
  return raw.replace(/0+$/, "").replace(/\.$/, "");
}

/** The canonical decimal form `bench/sdk-harness/README.md` specifies: expand scientific
 * notation, strip a leading `+`, strip redundant leading zeros, then (if a `.` remains)
 * strip trailing zeros and a bare trailing `.`. Identical in `examples/bench_consumer.ts`. */
function canonicalDecimal(raw: string): string {
  let value = expandExponential(raw);
  if (value.startsWith("+")) {
    value = value.slice(1);
  }
  value = stripLeadingZeros(value);
  value = stripTrailingZerosAndDot(value);
  return value;
}

const FNV_OFFSET_BASIS = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const FNV_MASK_64 = (1n << 64n) - 1n;

/** FNV-1a 64-bit over `input`'s UTF-8 bytes, printed as 16 lowercase hex digits. Identical in
 * `examples/bench_consumer.ts`. */
function fnv1a64Hex(input: string): string {
  let hash = FNV_OFFSET_BASIS;
  const bytes = new TextEncoder().encode(input);
  for (let i = 0; i < bytes.length; i += 1) {
    hash ^= BigInt(bytes[i]);
    hash = (hash * FNV_PRIME) & FNV_MASK_64;
  }
  return hash.toString(16).padStart(16, "0");
}

/** The content digest `bench/sdk-harness/README.md` specifies: exclude zero-quantity levels,
 * sort bids price-descending and asks price-ascending, serialize as
 * `B` + `price:qty;`* + `|A` + `price:qty;`* using canonical decimals, then FNV-1a 64 the
 * UTF-8 bytes. Identical in `examples/bench_consumer.ts`. */
function canonicalDigest(bids: DigestLevel[], asks: DigestLevel[]): string {
  const nonZero = (level: DigestLevel): boolean => canonicalDecimal(level.qty) !== "0";
  const byPriceAscending = (a: DigestLevel, b: DigestLevel): number =>
    Number(canonicalDecimal(a.price)) - Number(canonicalDecimal(b.price));
  const sortedBids = bids.filter(nonZero).sort((a, b) => byPriceAscending(b, a));
  const sortedAsks = asks.filter(nonZero).sort(byPriceAscending);
  let serialized = "B";
  for (const level of sortedBids) {
    serialized += `${canonicalDecimal(level.price)}:${canonicalDecimal(level.qty)};`;
  }
  serialized += "|A";
  for (const level of sortedAsks) {
    serialized += `${canonicalDecimal(level.price)}:${canonicalDecimal(level.qty)};`;
  }
  return fnv1a64Hex(serialized);
}

/** The canonicalization vectors and one digest golden value `bench/sdk-harness/README.md`
 * pins, asserted identically by `examples/bench_consumer.ts --self-test`. Runs no network
 * code and reads no `--slugs` file. */
function selfTest(): number {
  let failures = 0;
  const vectors: Array<[string, string]> = [
    ["0.530", "0.53"],
    ["1000000.0", "1000000"],
    ["100", "100"],
    ["0.5", "0.5"],
    ["1e-7", "0.0000001"],
    ["0.0", "0"],
  ];
  for (const [input, expected] of vectors) {
    const actual = canonicalDecimal(input);
    if (actual !== expected) {
      failures += 1;
      console.error(`canonicalDecimal(${JSON.stringify(input)}) = ${actual}, expected ${expected}`);
    }
  }
  const sdkFloatCase = canonicalDecimal(String(1e-7));
  if (sdkFloatCase !== "0.0000001") {
    failures += 1;
    console.error(`canonicalDecimal(String(1e-7)) = ${sdkFloatCase}, expected 0.0000001`);
  }
  const goldenInput = "B0.6:10;0.5:20;|A0.7:5;0.8:15;";
  const goldenDigest = "8e46092ae63fb7c8";
  const sorted = canonicalDigest(
    [
      { price: "0.6", qty: "10" },
      { price: "0.5", qty: "20" },
    ],
    [
      { price: "0.7", qty: "5" },
      { price: "0.8", qty: "15" },
    ],
  );
  if (sorted !== goldenDigest) {
    failures += 1;
    console.error(`canonicalDigest(presorted) = ${sorted}, expected ${goldenDigest} for "${goldenInput}"`);
  }
  const unsorted = canonicalDigest(
    [
      { price: "0.5", qty: "20" },
      { price: "0.9", qty: "0" },
      { price: "0.6", qty: "10" },
    ],
    [
      { price: "0.8", qty: "15" },
      { price: "0.7", qty: "5" },
    ],
  );
  if (unsorted !== goldenDigest) {
    failures += 1;
    console.error(`canonicalDigest(unsorted+zero-qty) = ${unsorted}, expected ${goldenDigest}`);
  }
  if (failures === 0) {
    console.log(
      `self-test: PASS -- ${vectors.length + 1} canonicalization checks, digest golden ` +
        `${goldenDigest} for "${goldenInput}" (presorted and unsorted+zero-filtered inputs)`,
    );
    return 0;
  }
  console.error(`self-test: FAIL (${failures} failing checks)`);
  return 1;
}

class UsageError extends Error {}

interface Args {
  slugs: string;
  seconds: number;
  obsOut: string;
  label: string;
  endpoint: string | null;
}

function usage(): string {
  return (
    "usage: sdk_leg.ts --slugs <file> --seconds <n> --obs-out <path> --label <text> " +
    "[--endpoint <url>]\n       sdk_leg.ts --self-test"
  );
}

function parseArgs(argv: string[]): Args {
  let slugs: string | undefined;
  let seconds: number | undefined;
  let obsOut: string | undefined;
  let label: string | undefined;
  let endpoint: string | null = null;

  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const next = (): string => {
      i += 1;
      const value = argv[i];
      if (value === undefined) {
        throw new UsageError(`${flag} needs a value\n${usage()}`);
      }
      return value;
    };
    switch (flag) {
      case "--slugs":
        slugs = next();
        break;
      case "--seconds": {
        const value = Number(next());
        if (!Number.isFinite(value) || value <= 0 || value > MAX_SECONDS) {
          throw new UsageError(`--seconds must be in (0, ${MAX_SECONDS}]\n${usage()}`);
        }
        seconds = value;
        break;
      }
      case "--obs-out":
        obsOut = next();
        break;
      case "--label":
        label = next();
        break;
      case "--endpoint":
        endpoint = next();
        break;
      default:
        throw new UsageError(`unrecognized argument: ${flag}\n${usage()}`);
    }
  }
  if (slugs === undefined) throw new UsageError(`--slugs is required\n${usage()}`);
  if (seconds === undefined) throw new UsageError(`--seconds is required\n${usage()}`);
  if (obsOut === undefined) throw new UsageError(`--obs-out is required\n${usage()}`);
  if (label === undefined) throw new UsageError(`--label is required\n${usage()}`);
  return { slugs, seconds, obsOut, label, endpoint };
}

/** Every venue-native key `path` names, in file order, without blanks or comments. */
function readSlugFile(path: string): string[] {
  return readFileSync(path, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"));
}

/** One market's latest book, as this leg's own minimal book handling stores it: the raw
 * `OrderbookEntry` arrays reduced to the digest's `{price, qty}` shape. */
interface Book {
  bids: DigestLevel[];
  asks: DigestLevel[];
}

/** The observation log this run accumulates, flushed once at the end or on `SIGTERM`. Rows
 * are pre-allocated up to `MAX_OBS_ROWS`; anything past that is counted in `dropped` instead
 * of stored, per `bench/sdk-harness/README.md`'s cap. */
interface ObsRecorder {
  rows: (string | null)[];
  count: number;
  dropped: number;
  eventsTotal: number;
  seqByMarket: Map<string, number>;
  path: string;
}

function createObsRecorder(path: string): ObsRecorder {
  return {
    rows: new Array(MAX_OBS_ROWS).fill(null),
    count: 0,
    dropped: 0,
    eventsTotal: 0,
    seqByMarket: new Map<string, number>(),
    path,
  };
}

/** Records one observation, or counts it dropped past `MAX_OBS_ROWS`. `eventsTotal` counts
 * every row attempted, matched only by `count + dropped` -- the invariant the `.obs` file's
 * own `dropped` trailer is meaningful against. */
function recordObs(recorder: ObsRecorder, slug: string, tObsNs: bigint, digest: string): void {
  recorder.eventsTotal += 1;
  const seq = recorder.seqByMarket.get(slug) ?? 0;
  recorder.seqByMarket.set(slug, seq + 1);
  if (recorder.count >= MAX_OBS_ROWS) {
    recorder.dropped += 1;
    return;
  }
  recorder.rows[recorder.count] = `obs ${slug} ${tObsNs} ${digest} ${seq}`;
  recorder.count += 1;
}

function flushObsRecorder(recorder: ObsRecorder, label: string, marketCount: number): void {
  const lines: string[] = [
    "# pmws-obs v1",
    "# leg: ts-sdk",
    `# host: ${label}`,
    "# clock: epoch_ns",
    `# size: ${marketCount}`,
    `# pin: ${SDK_PIN}`,
  ];
  for (let i = 0; i < recorder.count; i += 1) {
    lines.push(recorder.rows[i] as string);
  }
  lines.push(`# events_total: ${recorder.eventsTotal}`);
  lines.push(`# dropped: ${recorder.dropped}`);
  writeFileSync(recorder.path, `${lines.join("\n")}\n`);
}

async function run(args: Args): Promise<number> {
  const slugs = readSlugFile(args.slugs);
  if (slugs.length === 0) {
    console.error(`sdk_leg.ts: ${args.slugs} names no market`);
    return 1;
  }
  if (slugs.length > MAX_SLUGS) {
    console.error(`sdk_leg.ts: ${args.slugs} names more than ${MAX_SLUGS} markets`);
    return 1;
  }

  const buffer = sharedBuffer();
  const shared = sharedViews(buffer);
  const origin = process.hrtime.bigint();
  Atomics.store(shared.clock, CLOCK_ORIGIN, origin);
  const keeper = new Worker(new URL(import.meta.url), { workerData: { buffer } });
  keeper.unref();

  const readyBy = Date.now() + CALIBRATION_READY_TIMEOUT_MS;
  const sleeper = new Int32Array(new SharedArrayBuffer(4));
  while (Atomics.load(shared.clock, CLOCK_DERIVATIONS) < BigInt(CALIBRATION_WINDOW)) {
    if (Date.now() > readyBy) {
      break;
    }
    Atomics.wait(sleeper, 0, 0, CALIBRATION_WARMUP_MS);
  }
  if (Atomics.load(shared.clock, CLOCK_DERIVATIONS) === 0n) {
    Atomics.store(shared.control, CONTROL_STOP, 1);
    console.error("sdk_leg.ts: the keeper thread never published a clock calibration");
    return 1;
  }

  let cachedCalibration = readCalibration(shared);
  const calibrationTimer = setInterval(() => {
    cachedCalibration = readCalibration(shared);
  }, CALIBRATION_CACHE_REFRESH_MS);
  calibrationTimer.unref();

  const recorder = createObsRecorder(args.obsOut);
  const books = new Map<string, Book>();
  let hasConnectedOnce = false;
  let reconnects = 0;
  let disconnects = 0;
  let errors = 0;
  let stopped = false;
  const startedAt = process.hrtime.bigint();

  const ws = new WebSocketClient({
    url: args.endpoint ?? undefined,
    autoReconnect: true,
    reconnectDelay: RECONNECT_DELAY_MS,
    maxReconnectAttempts: RECONNECT_ATTEMPTS_CAP,
  });

  ws.on("connect", () => {
    if (hasConnectedOnce) {
      reconnects += 1;
    } else {
      hasConnectedOnce = true;
    }
  });
  ws.on("disconnect", () => {
    disconnects += 1;
  });
  ws.on("error", () => {
    errors += 1;
  });
  ws.on("orderbookUpdate", (data: OrderbookUpdate) => {
    const book: Book = {
      bids: data.orderbook.bids.map((entry) => ({ price: String(entry.price), qty: String(entry.size) })),
      asks: data.orderbook.asks.map((entry) => ({ price: String(entry.price), qty: String(entry.size) })),
    };
    books.set(data.marketSlug, book);
    const tObsNs = epochNanos(process.hrtime.bigint(), origin, cachedCalibration);
    const digest = canonicalDigest(book.bids, book.asks);
    recordObs(recorder, data.marketSlug, tObsNs, digest);
  });

  await ws.connect();
  await ws.subscribe("subscribe_market_prices", { marketSlugs: slugs });

  const shutdown = (): { elapsedSeconds: number } => {
    const elapsedSeconds = Number(process.hrtime.bigint() - startedAt) / 1e9;
    return { elapsedSeconds };
  };

  const finish = async (): Promise<number> => {
    if (stopped) {
      return 0;
    }
    stopped = true;
    clearInterval(calibrationTimer);
    Atomics.store(shared.control, CONTROL_STOP, 1);
    Atomics.notify(shared.control, CONTROL_SLEEPER);
    const { elapsedSeconds } = shutdown();
    flushObsRecorder(recorder, args.label, slugs.length);
    const calibration = readCalibration(shared);
    const out: string[] = [];
    out.push(`label: ${args.label}`);
    out.push("consumer: sdk_leg.ts");
    out.push(`runtime: node ${process.version}`);
    out.push(`sdk_pin: ${SDK_PIN}`);
    out.push(`endpoint: ${args.endpoint ?? "sdk default"}`);
    out.push(`duration_seconds: ${elapsedSeconds.toFixed(3)}`);
    out.push(`markets_subscribed: ${slugs.length}`);
    out.push(`markets_active: ${books.size}`);
    out.push(`events_total: ${recorder.eventsTotal}`);
    const rate = elapsedSeconds > 0 ? recorder.eventsTotal / elapsedSeconds : 0;
    out.push(`events_per_second: ${rate.toFixed(3)}`);
    const perMarketCounts = [...recorder.seqByMarket.values()];
    const perMarketMean =
      perMarketCounts.length > 0 ? perMarketCounts.reduce((a, b) => a + b, 0) / perMarketCounts.length : 0;
    out.push(`events_per_market_mean: ${perMarketMean.toFixed(3)}`);
    out.push(`events_per_market_min: ${perMarketCounts.length > 0 ? Math.min(...perMarketCounts) : 0}`);
    out.push(`events_per_market_max: ${perMarketCounts.length > 0 ? Math.max(...perMarketCounts) : 0}`);
    out.push(`obs_rows_written: ${recorder.count}`);
    out.push(`obs_dropped: ${recorder.dropped}`);
    out.push(`reconnects: ${reconnects}`);
    out.push(`disconnects: ${disconnects}`);
    out.push(`errors: ${errors}`);
    out.push(`clock_derivations: ${Atomics.load(shared.clock, CLOCK_DERIVATIONS)}`);
    out.push(`clock_divergence_ns_per_s: ${Number(calibration.rate) / 1000}`);
    out.push(`clock_steps_detected: ${Atomics.load(shared.control, CONTROL_CLOCK_STEPS)}`);
    out.push(`clock_calibrations_rejected: ${Atomics.load(shared.control, CONTROL_CLOCK_REJECTED)}`);
    process.stdout.write(`${out.join("\n")}\n`);
    try {
      await ws.disconnect();
    } catch {
      // The socket may already be gone; nothing left to report about it.
    }
    return 0;
  };

  return await new Promise<number>((resolve) => {
    const timer = setTimeout(() => {
      finish().then(resolve);
    }, Math.round(args.seconds * 1000));
    process.once("SIGTERM", () => {
      clearTimeout(timer);
      finish().then(resolve);
    });
  });
}

async function main(): Promise<number> {
  const argv = process.argv.slice(2);
  if (argv.includes("--self-test")) {
    return selfTest();
  }
  let args: Args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    console.error(error instanceof UsageError ? error.message : String(error));
    return 2;
  }
  try {
    return await run(args);
  } catch (error) {
    console.error(`sdk_leg.ts: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

if (isMainThread) {
  main().then((code) => {
    process.exitCode = code;
  });
} else {
  const options = workerData as KeeperOptions;
  try {
    runKeeper(options);
  } catch (error) {
    parentPort?.postMessage(String(error));
  }
}
