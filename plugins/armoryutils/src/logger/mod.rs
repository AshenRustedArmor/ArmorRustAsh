use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use rrplug::prelude::*;

pub mod create;
pub mod log;
pub mod write;

#[derive(Default)]

//	==========================================================
//						Data structures
//	==========================================================
#[derive(Debug, Clone)]
pub struct LogFormat {
	//	Formatting
//	pub columns:	Vec<LogColumn>,
	pub column_format: String,		//	e.g. "{1:^7}{0}"
	pub separators:	Vec<String>,	//	Table drawing chars - vert, horz, cross, iter sep, etc.

	pub column_keys: Vec<String>,	//	stores string keys for numeric cols - idx 0 reserved
	pub break_mask: u64,			//	which columns to break on change, assuming 64 columns max
	pub last_values: Vec<String>,	//	stores last recorded string value for each

	//	Data
	pub iter_queue:	Vec<String>,	//	This is iteratively appended to
	pub dump_cache:	Vec<String>,	//	Plaintext rows for file dumping
}

//	==========================================================
//					Global State / Retrieval
//	==========================================================
//  Global state
static LOGGERS: OnceLock<Mutex<  HashMap<i32, LogFormat>  >> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<  i32  >> = OnceLock::new();

pub fn next_handle() -> i32 {
	let mut counter = NEXT_ID.get_or_init(|| Mutex::new(0)).lock().unwrap();
	let current = *counter;
	*counter += 1;
	current
}

pub fn get_loggers() -> &'static Mutex<HashMap<i32, LogFormat>> {
	LOGGERS.get_or_init(|| Mutex::new(HashMap::new()))
}

//	==========================================================
//					FFI function registry
//	==========================================================
pub fn register() {
	/*
	crate::register_multi!(
	); // */
}