use std::collections::HashMap;

use super::LogFormat;

//	============================================================================
//								Helpers
//	============================================================================

/// Builds the message column for one log call.
///
/// Two token forms are recognized, scanned left to right:
/// - `{}` is replaced with the next value from `args`, in order. Leftover
///   `{}` (more placeholders than args) are left untouched.
/// - `%I{sep}` is replaced with every fragment queued by `Iter` calls since
///   the last time an `%I{sep}` token was actually consumed, joined with
///   `sep` (e.g. `%I{, }` -> `"a, b, c"`). Consuming it clears `iter_queue`.
///   If `message` has no `%I{...}` token, `iter_queue` is left untouched -
///   it carries forward to whichever future call does consume it.
///
/// Everything else is copied through literally, so e.g. the surrounding
/// `[` `]` in `"[%I{, }]"` are just ordinary message text.
fn format_message(message: &str, args: &[String], iter_queue: &mut Vec<String>) -> String {
	let mut out = String::new();
	let mut args_iter = args.iter();
	let mut rest = message;

	while !rest.is_empty() {
		if let Some(after_tag) = rest.strip_prefix("%I{") {
			if let Some(end) = after_tag.find('}') {
				let sep = &after_tag[..end];
				out.push_str(&iter_queue.join(sep));
				iter_queue.clear();
				rest = &after_tag[end + 1..];
				continue;
			}
			// No closing '}' - not a valid token, emit the tag literally.
			out.push_str("%I{");
			rest = after_tag;
			continue;
		}

		if let Some(after_arg) = rest.strip_prefix("{}") {
			match args_iter.next() {
				Some(arg) => out.push_str(arg),
				None => out.push_str("{}"),
			}
			rest = after_arg;
			continue;
		}

		let mut chars = rest.chars();
		out.push(chars.next().expect("rest is non-empty"));
		rest = chars.as_str();
	}

	out
}

/// Applies a `<width`, `>width` or `^width` alignment spec to `value`.
/// An absent/empty spec returns `value` unchanged.
fn apply_spec(value: &str, spec: Option<&str>) -> String {
	let spec = match spec {
		Some(s) if !s.is_empty() => s,
		_ => return value.to_string(),
	};

	let mut chars = spec.chars();
	let (align, rest) = match chars.next() {
		Some(c @ ('<' | '>' | '^')) => (Some(c), chars.as_str()),
		_ => (None, spec),
	};

	let width: usize = rest.trim().parse().unwrap_or(0);

	match align {
		Some('<') | None => format!("{value:<width$}"),
		Some('>') => format!("{value:>width$}"),
		Some('^') => format!("{value:^width$}"),
		_ => value.to_string(),
	}
}

/// Renders `format.column_format` (a template using positional "{N}" or
/// "{N:spec}" tokens, as produced by `create::parse_log_format`) against
/// `values`, where `values[N]` is substituted into token `{N}`.
fn render_row(template: &str, values: &[String]) -> String {
	let mut out = String::new();
	let mut chars = template.chars().peekable();

	while let Some(c) = chars.next() {
		if c != '{' {
			out.push(c);
			continue;
		}

		let mut token = String::new();
		let mut closed = false;
		for nc in chars.by_ref() {
			if nc == '}' {
				closed = true;
				break;
			}
			token.push(nc);
		}

		if !closed {
			// Unterminated brace - nothing sensible to parse, emit literally.
			out.push('{');
			out.push_str(&token);
			continue;
		}

		let (idx_str, spec) = match token.split_once(':') {
			Some((idx, s)) => (idx, Some(s)),
			None => (token.as_str(), None),
		};

		match idx_str.parse::<usize>() {
			Ok(idx) => {
				let value = values.get(idx).map(String::as_str).unwrap_or("");
				out.push_str(&apply_spec(value, spec));
			}
			Err(_) => {
				// Not a valid positional token - emit literally.
				out.push('{');
				out.push_str(&token);
				out.push('}');
			}
		}
	}

	out
}

/// Builds a divider line the same width as `rendered_row`: the vertical
/// separator becomes the corner/cross char and everything else becomes the
/// horizontal fill char. Assumes single-character separators.
fn build_divider(rendered_row: &str, vert: &str, horz: &str, cross: &str) -> String {
	let vert_char = vert.chars().next();
	let horz_char = horz.chars().next().unwrap_or('-');
	let cross_char = cross.chars().next().unwrap_or('+');

	rendered_row
		.chars()
		.map(|c| if Some(c) == vert_char { cross_char } else { horz_char })
		.collect()
}

/// Finds the 1-based column position of `key` in `column_keys`
/// (position 0 is always reserved for the message).
fn find_position(column_keys: &[String], key: &str) -> Option<usize> {
	column_keys.iter().position(|k| k == key).map(|i| i + 1)
}

//	============================================================================
//								Internal
//	============================================================================

/// Runs break detection against `format.last_values`, draws a divider row
/// first if needed, then renders and appends `values` to `dump_cache`.
fn emit_row(format: &mut LogFormat, values: Vec<String>) {
	let has_previous_row = !format.dump_cache.is_empty();

	let vert = format.separators.first().map(String::as_str).unwrap_or("");
	let horz = format.separators.get(1).map(String::as_str).unwrap_or("-");
	let cross = format.separators.get(2).map(String::as_str).unwrap_or("+");

	let should_break = has_previous_row
		&& values.iter().enumerate().any(|(pos, value)| {
			let is_break_col = format.break_mask & (1u64 << pos) != 0;
			let changed = format.last_values.get(pos).map(String::as_str) != Some(value.as_str());
			is_break_col && changed
		});

	let rendered = render_row(&format.column_format, &values);

	if should_break {
		format.dump_cache.push(build_divider(&rendered, vert, horz, cross));
	}

	format.dump_cache.push(rendered);
	format.last_values = values;
}

//	============================================================================
//								Logging Functions
//	============================================================================

/// Formats one log call (`msg` + `args` become the message column,
/// `custom_cols` supplies any other named columns) and appends it to
/// `format.dump_cache`. If `msg` contains an `%I{sep}` token, it's replaced
/// with the fragments queued by `Iter` since the last such token was
/// consumed; otherwise the queue is left untouched for a later call.
pub fn process_log(format: &mut LogFormat, custom_cols: &HashMap<String, String>, msg: &str, args: &[String]) {
	let mut values = if format.last_values.len() == format.column_keys.len() + 1 {
		format.last_values.clone()
	} else {
		vec![String::new(); format.column_keys.len() + 1]
	};

	for (key, value) in custom_cols {
		if let Some(pos) = find_position(&format.column_keys, key) {
			values[pos] = value.clone();
		}
	}

	values[0] = format_message(msg, args, &mut format.iter_queue);

	emit_row(format, values);
}
