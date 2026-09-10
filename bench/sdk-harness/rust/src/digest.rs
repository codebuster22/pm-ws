//! Content digest and canonical decimal formatting for the `rust-sdk` leg,
//! per `bench/sdk-harness/README.md`'s "Content digest" section.

const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

/// FNV-1a 64-bit hash over `bytes`, matching the spec's offset and prime.
pub fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = FNV_OFFSET_BASIS;
    for &byte in bytes {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// Canonical decimal string for an SDK book value, from its shortest
/// round-trip `f64` formatting (Rust `{}` never emits scientific notation,
/// but the canonicalization rules below are written to also accept a
/// scientific-notation input string, matching the spec's generic algorithm).
pub fn canonical_decimal(value: f64) -> String {
    canonicalize_decimal_string(&format!("{value}"))
}

/// Applies the spec's canonicalization rules to an already-formatted decimal
/// or scientific-notation string: expand `e`/`E` notation to plain decimal,
/// strip a leading `+`, strip redundant leading zeros, then strip a trailing
/// fractional `.0...0` down to a bare integer.
pub fn canonicalize_decimal_string(input: &str) -> String {
    let expanded = if input.contains('e') || input.contains('E') {
        expand_scientific(input)
    } else {
        input.to_string()
    };
    let unsigned = expanded.strip_prefix('+').unwrap_or(&expanded);
    let without_leading_zeros = strip_leading_zeros(unsigned);
    strip_trailing_fraction_zeros(&without_leading_zeros)
}

fn expand_scientific(input: &str) -> String {
    let lower = input.to_ascii_lowercase();
    let mut split = lower.splitn(2, 'e');
    let mantissa = split.next().unwrap_or("0");
    let exponent: i32 = split.next().and_then(|e| e.parse().ok()).unwrap_or(0);

    let negative = mantissa.starts_with('-');
    let unsigned_mantissa = mantissa.trim_start_matches(['+', '-']);
    let (int_part, frac_part) = match unsigned_mantissa.split_once('.') {
        Some((int_part, frac_part)) => (int_part, frac_part),
        None => (unsigned_mantissa, ""),
    };

    let digits = format!("{int_part}{frac_part}");
    let point_pos = int_part.len() as i32 + exponent;

    let magnitude = if point_pos <= 0 {
        format!("0.{}{}", "0".repeat((-point_pos) as usize), digits)
    } else if (point_pos as usize) >= digits.len() {
        format!("{digits}{}", "0".repeat(point_pos as usize - digits.len()))
    } else {
        let (whole, frac) = digits.split_at(point_pos as usize);
        format!("{whole}.{frac}")
    };

    if negative {
        format!("-{magnitude}")
    } else {
        magnitude
    }
}

fn strip_leading_zeros(input: &str) -> String {
    let (int_part, frac_part) = match input.split_once('.') {
        Some((int_part, frac_part)) => (int_part, Some(frac_part)),
        None => (input, None),
    };
    let trimmed = int_part.trim_start_matches('0');
    let normalized = if trimmed.is_empty() { "0" } else { trimmed };
    match frac_part {
        Some(frac) => format!("{normalized}.{frac}"),
        None => normalized.to_string(),
    }
}

fn strip_trailing_fraction_zeros(input: &str) -> String {
    if !input.contains('.') {
        return input.to_string();
    }
    let trimmed = input.trim_end_matches('0');
    trimmed.strip_suffix('.').unwrap_or(trimmed).to_string()
}

/// Digest of one decoded book: excludes zero-quantity levels, sorts bids
/// price-descending and asks price-ascending, serializes as
/// `B` + `price:qty;` per bid + `|A` + `price:qty;` per ask with canonical
/// decimals, then FNV-1a 64-bit hashes the UTF-8 bytes.
pub fn book_digest(bids: &[(f64, f64)], asks: &[(f64, f64)]) -> u64 {
    let mut bid_levels: Vec<(f64, f64)> = bids.iter().copied().filter(|&(_, qty)| qty != 0.0).collect();
    let mut ask_levels: Vec<(f64, f64)> = asks.iter().copied().filter(|&(_, qty)| qty != 0.0).collect();
    bid_levels.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    ask_levels.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    let mut serialized = String::from("B");
    for (price, qty) in &bid_levels {
        serialized.push_str(&canonical_decimal(*price));
        serialized.push(':');
        serialized.push_str(&canonical_decimal(*qty));
        serialized.push(';');
    }
    serialized.push_str("|A");
    for (price, qty) in &ask_levels {
        serialized.push_str(&canonical_decimal(*price));
        serialized.push(':');
        serialized.push_str(&canonical_decimal(*qty));
        serialized.push(';');
    }

    fnv1a64(serialized.as_bytes())
}

/// `book_digest`'s result as 16 lowercase hex digits.
pub fn digest_hex(hash: u64) -> String {
    format!("{hash:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonicalizes_spec_vectors() {
        assert_eq!(canonicalize_decimal_string("0.530"), "0.53");
        assert_eq!(canonicalize_decimal_string("1000000.0"), "1000000");
        assert_eq!(canonicalize_decimal_string("100"), "100");
        assert_eq!(canonicalize_decimal_string("0.5"), "0.5");
        assert_eq!(canonicalize_decimal_string("1e-7"), "0.0000001");
        assert_eq!(canonicalize_decimal_string("0.0"), "0");
    }

    #[test]
    fn canonicalizes_additional_shapes() {
        assert_eq!(canonicalize_decimal_string("007"), "7");
        assert_eq!(canonicalize_decimal_string("+0.5"), "0.5");
        assert_eq!(canonicalize_decimal_string("100.00"), "100");
        assert_eq!(canonicalize_decimal_string("1E-7"), "0.0000001");
        assert_eq!(canonicalize_decimal_string("1.5e3"), "1500");
    }

    #[test]
    fn rust_float_display_never_emits_scientific_notation() {
        assert_eq!(canonical_decimal(1e-7), "0.0000001");
        assert_eq!(canonical_decimal(0.53), "0.53");
        assert_eq!(canonical_decimal(100.0), "100");
    }

    #[test]
    fn book_digest_excludes_zero_size_levels_and_sorts() {
        let bids = [(0.53, 10.0), (0.52, 0.0)];
        let asks = [(0.55, 5.0)];
        assert_eq!(book_digest(&bids, &asks), 0x12c2_5d94_2bca_fca2);
        assert_eq!(digest_hex(book_digest(&bids, &asks)), "12c25d942bcafca2");
    }

    #[test]
    fn book_digest_of_empty_book_is_stable() {
        assert_eq!(digest_hex(book_digest(&[], &[])), "16893f19b12e316e");
    }
}
