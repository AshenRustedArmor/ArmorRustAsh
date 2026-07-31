use std::collections::HashMap;

use rrplug::prelude::*;

use super::get_loggers;
use crate::logger::write::process_log;

//	==========================================================
//                     Iterable Logging
//	==========================================================
#[rrplug::sqfunction(
    VM = "SERVER | CLIENT | UI", 
    ExportName = "ArmoryLog_Iter"
)]
pub fn logger_iter(id: i32, data: String) -> i32 {
    let mut loggers = get_loggers().lock().unwrap();
    
    match loggers.get_mut(&id) {
		Some(format) => {
			format.iter_queue.push(data);
			0
		}
		None => {
			log::error!("ArmoryLog_Iter: Invalid logger ID {}", id);
			-1
		}
	}
}

//	==========================================================
//                     Log Level FFI Endpoints
//	==========================================================
macro_rules! define_log_level {
	($func_name:ident, $export_name:expr, $level_str:expr) => {
		#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = $export_name)]
		pub fn $func_name(id: i32, custom_raw: Vec<String>, msg: String, args: Vec<String>) -> i32 {
			let mut loggers = get_loggers().lock().unwrap();

			let format = match loggers.get_mut(&id) {
				Some(format) => format,
				None => {
					log::error!("{}: Invalid logger ID {}", $export_name, id);
					return -1;
				}
			};

			if custom_raw.len() % 2 != 0 {
				log::error!(
					"{}: custom_raw must have an even number of elements (key/value pairs)",
					$export_name
				);
				return -1;
			}

			//  Build a key -> value map from the flat custom_raw pairs.
			let mut custom_cols = HashMap::new();
			for chunk in custom_raw.chunks_exact(2) {
				custom_cols.insert(chunk[0].clone(), chunk[1].clone());
			}
			custom_cols.insert("level".to_string(), $level_str.to_string());

			//  Delegate formatting / row assembly to write.rs.
			let last_msg = process_log(format, &custom_cols, &msg, &args);

			match $level_str {
				"INFO"	=> rrplug::prelude::log::info!("{}", last_msg),
				"WARN"	=> rrplug::prelude::log::warn!("{}", last_msg),
				"ERROR"	=> rrplug::prelude::log::error!("{}", format.dump_cache.join("\n")),
				_		=> rrplug::prelude::log::info!("{}", last_msg),
			}

			0
		}
	};
}


// Generate the FFI functions
define_log_level!(logger_info,  "ArmoryLog_Info",  "INFO");
define_log_level!(logger_warn,  "ArmoryLog_Warn",  "WARN");
define_log_level!(logger_error, "ArmoryLog_Error", "ERROR");