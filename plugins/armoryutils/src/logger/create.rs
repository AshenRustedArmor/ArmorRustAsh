use rrplug::prelude::*;

use super::{next_handle, get_loggers, LogFormat};

//	==========================================================
//						Parsers
//	==========================================================

/// Parses a layout string like `"{#phase:^7}{#level:^7}{message}"` into a
/// [`LogFormat`].
///
/// - Each `{...}` slot names a column. `message` (or `M`) is reserved for
///   the log message itself and always maps to position 0; every other
///   name is assigned the next free position, in first-seen order.
/// - A leading `#` on a name (e.g. `{#phase}`) marks that column as a
///   "break" column: a divider row is drawn whenever its value changes
///   between rows.
/// - `:spec` after a name is kept and later used to align/pad the value
///   (`<`, `>`, `^` plus a width, e.g. `{#phase:^7}`).
///
/// `separators_str` is a comma-separated list of exactly 3 values, in
/// order: `vertical, horizontal, corner`, e.g. `"|, -, +"`. These are used
/// only to draw divider rows between break columns (see `break_mask`
/// below) - iterable joining/wrapping is written directly into the message
/// via `%I{sep}` instead (see `write::format_message`).
pub fn parse_log_format(format_str: &str, separators_str: &str) -> Result<LogFormat, String> {
	let separators: Vec<String> = separators_str.split(',').map(|s| s.trim().to_string()).collect();
	if separators.len() != 3 {
		return Err(format!(
			"Expected 3 comma-separated separators (vertical, horizontal, corner), got {}",
			separators.len()
		));
	}

	// Split on the closing brace to isolate column slots; the tail after the
	// last '}' is trailing literal text with no slot of its own.
	let mut parts: Vec<&str> = format_str.split('}').collect();
	let last_part = parts.pop().unwrap_or("");

	let mut column_format = String::new();
	let mut column_keys: Vec<String> = Vec::new();
	let mut break_mask: u64 = 0;

	for (col_idx, part) in parts.into_iter().enumerate() {
		if col_idx >= 64 {
			return Err("Exceeded maximum layout limit of 64 columns".to_string());
		}

		// Find the boundary between the literal layout text and the column slot.
		let brace_idx = part
			.find('{')
			.ok_or_else(|| format!("Missing opening brace '{{' in format segment: \"{part}\""))?;

		let literal = &part[..brace_idx];
		let inner = &part[brace_idx + 1..];

		// Separate the token key name from alignment modifiers (e.g. "phase" and "^7").
		let (mut key, spec) = match inner.split_once(':') {
			Some((k, s)) => (k.trim(), Some(s)),
			None => (inner.trim(), None),
		};

		// Extract the "break on change" flag if the key is prefixed with '#'.
		let do_break = key.starts_with('#');
		if do_break {
			key = &key[1..];
		}

		// Resolve positional assignment: position 0 is reserved for the message.
		let pos_idx = match key {
			"M" | "message" => 0,
			custom => match column_keys.iter().position(|k| k == custom) {
				Some(pos) => pos + 1, // Key already registered; reuse its slot.
				None => {
					column_keys.push(custom.to_string());
					column_keys.len() // Newly registered key.
				}
			},
		};

		if do_break {
			break_mask |= 1u64 << pos_idx;
		}

		// Re-compile the segment using the positional index for runtime formatting.
		let new_brace = match spec {
			Some(s) => format!("{{{pos_idx}:{s}}}"),
			None => format!("{{{pos_idx}}}"),
		};

		column_format.push_str(literal);
		column_format.push_str(&new_brace);
	}

	// Append any trailing content sitting outside the final closing brace.
	column_format.push_str(last_part);

	let last_values = vec![String::new(); column_keys.len() + 1];

	Ok(LogFormat {
		column_format,
		separators,
		column_keys,
		break_mask,
		last_values,
		iter_queue: Vec::new(),
		dump_cache: Vec::new(),
	})
}

//	==========================================================
//						Squirrel Functions
//	==========================================================
#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryLog_Create"
)]
pub fn logger_create(format_str: String, separators_str: String) -> i32 {
	let id = next_handle();

	match parse_log_format(&format_str, &separators_str) {
		Ok(format) => {
			let mut loggers = get_loggers().lock().unwrap();
			loggers.insert(id, format);
			id
		}
		Err(err) => {
			log::error!("ArmoryLog_Create Parse Error: {}", err);
			-1
		}
	}
}
