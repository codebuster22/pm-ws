//! `rust-sdk` leg of the S8c comparative benchmark: the official
//! `limitless-exchange-rust-sdk` WebSocket client, subscribed to a pinned
//! market-slug set, emitting one `.obs` log per `bench/sdk-harness/README.md`.
//!
//! Isolated from the daemon's dependency graph: this is its own cargo
//! project with its own `Cargo.lock`, detached from the root workspace.

mod digest;

use std::collections::HashMap;
use std::fmt::Write as _;
use std::fs::{self, File};
use std::io::{BufWriter, Write as _};
use std::process::ExitCode;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use limitless_exchange_rust_sdk::{
    OrderbookData, OrderbookUpdate, SubscriptionChannel, SubscriptionOptions, WebSocketClient,
    WebSocketConfig, WebSocketState,
};

use digest::{book_digest, digest_hex};

const MAX_OBS_ROWS: usize = 4_000_000;
const SDK_PIN: &str = "limitless-exchange-rust-sdk@b1ad2e1";
const TOP_MARKETS_PRINTED: usize = 10;

struct Args {
    slugs_path: String,
    seconds: u64,
    obs_out: String,
    label: String,
    endpoint: Option<String>,
}

fn print_usage_and_exit() -> ! {
    eprintln!(
        "usage: sdk_leg --slugs <file> --seconds <n> --obs-out <path> --label <text> [--endpoint <url>]"
    );
    std::process::exit(2);
}

fn parse_args() -> Args {
    let mut slugs_path = None;
    let mut seconds = None;
    let mut obs_out = None;
    let mut label = None;
    let mut endpoint = None;

    let mut raw = std::env::args().skip(1);
    while let Some(flag) = raw.next() {
        let value = raw.next().unwrap_or_else(|| print_usage_and_exit());
        match flag.as_str() {
            "--slugs" => slugs_path = Some(value),
            "--seconds" => seconds = Some(value.parse::<u64>().unwrap_or_else(|_| print_usage_and_exit())),
            "--obs-out" => obs_out = Some(value),
            "--label" => label = Some(value),
            "--endpoint" => endpoint = Some(value),
            _ => print_usage_and_exit(),
        }
    }

    Args {
        slugs_path: slugs_path.unwrap_or_else(|| print_usage_and_exit()),
        seconds: seconds.unwrap_or_else(|| print_usage_and_exit()),
        obs_out: obs_out.unwrap_or_else(|| print_usage_and_exit()),
        label: label.unwrap_or_else(|| print_usage_and_exit()),
        endpoint,
    }
}

fn read_slugs(path: &str) -> Vec<String> {
    let contents = fs::read_to_string(path)
        .unwrap_or_else(|err| panic!("sdk_leg: failed to read --slugs file {path}: {err}"));
    contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect()
}

fn now_ns() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before unix epoch")
        .as_nanos() as u64
}

struct ObsRecord {
    slug: String,
    t_obs_ns: u64,
    digest: u64,
    seq: u64,
}

struct ObsLogInner {
    rows: Vec<ObsRecord>,
    seqs: HashMap<String, u64>,
    dropped: u64,
}

struct ObsLog {
    cap: usize,
    inner: Mutex<ObsLogInner>,
}

impl ObsLog {
    fn new(cap: usize) -> Self {
        Self {
            cap,
            inner: Mutex::new(ObsLogInner {
                rows: Vec::with_capacity(cap),
                seqs: HashMap::new(),
                dropped: 0,
            }),
        }
    }

    fn push(&self, slug: String, t_obs_ns: u64, digest: u64) {
        let mut inner = self.inner.lock().unwrap_or_else(|err| err.into_inner());
        let seq_slot = inner.seqs.entry(slug.clone()).or_insert(0);
        let seq = *seq_slot;
        *seq_slot += 1;

        if inner.rows.len() < self.cap {
            inner.rows.push(ObsRecord {
                slug,
                t_obs_ns,
                digest,
                seq,
            });
        } else {
            inner.dropped += 1;
        }
    }
}

/// Extracts `(price, size)` pairs from the SDK's decoded book, in the shape
/// [`digest::book_digest`] expects.
fn price_size_pairs(entries: &[limitless_exchange_rust_sdk::OrderBookEntry]) -> Vec<(f64, f64)> {
    entries.iter().map(|entry| (entry.price, entry.size)).collect()
}

fn on_orderbook_update(
    update: OrderbookUpdate,
    books: &Mutex<HashMap<String, OrderbookData>>,
    obs_log: &ObsLog,
    events_total: &AtomicU64,
) {
    let OrderbookUpdate {
        market_slug,
        orderbook,
        ..
    } = update;

    {
        let mut books = books.lock().unwrap_or_else(|err| err.into_inner());
        books.insert(market_slug.clone(), orderbook.clone());
    }
    let t_obs_ns = now_ns();

    events_total.fetch_add(1, Ordering::Relaxed);
    let bids = price_size_pairs(&orderbook.bids);
    let asks = price_size_pairs(&orderbook.asks);
    let digest = book_digest(&bids, &asks);
    obs_log.push(market_slug, t_obs_ns, digest);
}

/// Renders the complete `.obs` file body (header, one `obs` row per record in
/// `rows`, then the `events_total`/`dropped` trailers) as specified in
/// `bench/sdk-harness/README.md`'s "Observation log" section.
fn render_obs_file(
    label: &str,
    slug_count: usize,
    rows: &[ObsRecord],
    events_total: u64,
    dropped: u64,
) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# pmws-obs v1");
    let _ = writeln!(out, "# leg: rust-sdk");
    let _ = writeln!(out, "# host: {label}");
    let _ = writeln!(out, "# clock: epoch_ns");
    let _ = writeln!(out, "# size: {slug_count}");
    let _ = writeln!(out, "# pin: {SDK_PIN}");

    for row in rows {
        let _ = writeln!(
            out,
            "obs {} {} {} {}",
            row.slug,
            row.t_obs_ns,
            digest_hex(row.digest),
            row.seq
        );
    }

    let _ = writeln!(out, "# events_total: {events_total}");
    let _ = writeln!(out, "# dropped: {dropped}");
    out
}

fn write_obs_file(
    path: &str,
    label: &str,
    slug_count: usize,
    obs_log: &ObsLog,
    events_total: u64,
) -> std::io::Result<()> {
    let inner = obs_log.inner.lock().unwrap_or_else(|err| err.into_inner());
    let content = render_obs_file(label, slug_count, &inner.rows, events_total, inner.dropped);
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);
    writer.write_all(content.as_bytes())?;
    writer.flush()
}

fn print_summary(
    label: &str,
    duration: Duration,
    events_total: u64,
    dropped: u64,
    reconnect_attempts: u64,
    final_state: WebSocketState,
    obs_log: &ObsLog,
) {
    let inner = obs_log.inner.lock().unwrap_or_else(|err| err.into_inner());
    let mut per_market: Vec<(&String, &u64)> = inner.seqs.iter().collect();
    per_market.sort_by(|a, b| b.1.cmp(a.1));

    println!("sdk_leg summary");
    println!("  label: {label}");
    println!("  duration_s: {:.3}", duration.as_secs_f64());
    println!("  events_total: {events_total}");
    println!("  dropped: {dropped}");
    println!("  reconnect_attempts: {reconnect_attempts}");
    println!("  final_state: {final_state:?}");
    println!("  top {TOP_MARKETS_PRINTED} markets by event count:");
    for (slug, count) in per_market.into_iter().take(TOP_MARKETS_PRINTED) {
        println!("    {slug}: {count}");
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args = parse_args();
    let slugs = read_slugs(&args.slugs_path);
    if slugs.is_empty() {
        return Err("sdk_leg: --slugs file contained no markets".into());
    }

    let books: Arc<Mutex<HashMap<String, OrderbookData>>> = Arc::new(Mutex::new(HashMap::new()));
    let obs_log = Arc::new(ObsLog::new(MAX_OBS_ROWS));
    let events_total = Arc::new(AtomicU64::new(0));
    let reconnect_attempts = Arc::new(AtomicU64::new(0));

    let mut config = WebSocketConfig {
        api_key: None,
        hmac_credentials: None,
        auto_reconnect: true,
        max_reconnect_attempts: 5,
        ..WebSocketConfig::default()
    };
    if let Some(endpoint) = &args.endpoint {
        config.url = endpoint.clone();
    }

    let client = WebSocketClient::new(Some(config));

    {
        let reconnect_attempts = reconnect_attempts.clone();
        client.on("reconnecting", move |_| {
            reconnect_attempts.fetch_add(1, Ordering::Relaxed);
        });
    }
    {
        let books = books.clone();
        let obs_log = obs_log.clone();
        let events_total = events_total.clone();
        client.on_orderbook_update(move |update| {
            on_orderbook_update(update, &books, &obs_log, &events_total);
        });
    }

    client.connect().await?;
    client
        .subscribe(
            SubscriptionChannel::SubscribeMarketPrices,
            SubscriptionOptions {
                market_slugs: slugs.clone(),
                ..Default::default()
            },
        )
        .await?;

    let started_at = Instant::now();
    tokio::select! {
        _ = tokio::time::sleep(Duration::from_secs(args.seconds)) => {}
        _ = wait_for_sigterm() => {}
    }
    let duration = started_at.elapsed();
    let final_state = client.state();

    let _ = tokio::time::timeout(Duration::from_secs(2), client.disconnect()).await;

    let events_total = events_total.load(Ordering::Relaxed);
    let reconnect_attempts = reconnect_attempts.load(Ordering::Relaxed);
    let dropped = obs_log.inner.lock().unwrap_or_else(|err| err.into_inner()).dropped;

    write_obs_file(&args.obs_out, &args.label, slugs.len(), &obs_log, events_total)?;
    print_summary(
        &args.label,
        duration,
        events_total,
        dropped,
        reconnect_attempts,
        final_state,
        &obs_log,
    );

    Ok(())
}

#[cfg(unix)]
async fn wait_for_sigterm() {
    match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(mut sigterm) => {
            sigterm.recv().await;
        }
        Err(_) => std::future::pending::<()>().await,
    }
}

#[cfg(not(unix))]
async fn wait_for_sigterm() {
    std::future::pending::<()>().await
}

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("sdk_leg: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn obs_log_assigns_per_market_seq_from_zero() {
        let log = ObsLog::new(MAX_OBS_ROWS);
        log.push("btc-up-or-down".to_string(), 100, 0xaaaa);
        log.push("eth-up-or-down".to_string(), 101, 0xbbbb);
        log.push("btc-up-or-down".to_string(), 102, 0xcccc);

        let inner = log.inner.lock().unwrap();
        assert_eq!(inner.rows.len(), 3);
        assert_eq!(inner.rows[0].seq, 0);
        assert_eq!(inner.rows[1].seq, 0);
        assert_eq!(inner.rows[2].seq, 1);
        assert_eq!(inner.dropped, 0);
    }

    #[test]
    fn obs_log_drops_past_its_capacity_but_keeps_counting_seq() {
        let log = ObsLog::new(2);
        log.push("btc-up-or-down".to_string(), 100, 1);
        log.push("btc-up-or-down".to_string(), 101, 2);
        log.push("btc-up-or-down".to_string(), 102, 3);

        let inner = log.inner.lock().unwrap();
        assert_eq!(inner.rows.len(), 2);
        assert_eq!(inner.dropped, 1);
        assert_eq!(*inner.seqs.get("btc-up-or-down").unwrap(), 3);
    }

    #[test]
    fn render_obs_file_matches_the_spec_layout_exactly() {
        let rows = vec![
            ObsRecord {
                slug: "btc-up-or-down-5-min-1".to_string(),
                t_obs_ns: 1_700_000_000_000_000_001,
                digest: 0x12c2_5d94_2bca_fca2,
                seq: 0,
            },
            ObsRecord {
                slug: "eth-up-or-down-5-min-1".to_string(),
                t_obs_ns: 1_700_000_000_000_000_501,
                digest: 0x1689_3f19_b12e_316e,
                seq: 0,
            },
            ObsRecord {
                slug: "btc-up-or-down-5-min-1".to_string(),
                t_obs_ns: 1_700_000_000_001_000_001,
                digest: 0x12c2_5d94_2bca_fca2,
                seq: 1,
            },
        ];

        let rendered = render_obs_file("m1", 2, &rows, 4, 1);

        let expected = concat!(
            "# pmws-obs v1\n",
            "# leg: rust-sdk\n",
            "# host: m1\n",
            "# clock: epoch_ns\n",
            "# size: 2\n",
            "# pin: limitless-exchange-rust-sdk@b1ad2e1\n",
            "obs btc-up-or-down-5-min-1 1700000000000000001 12c25d942bcafca2 0\n",
            "obs eth-up-or-down-5-min-1 1700000000000000501 16893f19b12e316e 0\n",
            "obs btc-up-or-down-5-min-1 1700000000001000001 12c25d942bcafca2 1\n",
            "# events_total: 4\n",
            "# dropped: 1\n",
        );

        assert_eq!(rendered, expected);
    }

    #[test]
    fn render_obs_file_with_no_rows_still_has_a_well_formed_header_and_trailer() {
        let rendered = render_obs_file("box", 0, &[], 0, 0);
        let expected = concat!(
            "# pmws-obs v1\n",
            "# leg: rust-sdk\n",
            "# host: box\n",
            "# clock: epoch_ns\n",
            "# size: 0\n",
            "# pin: limitless-exchange-rust-sdk@b1ad2e1\n",
            "# events_total: 0\n",
            "# dropped: 0\n",
        );
        assert_eq!(rendered, expected);
    }
}
