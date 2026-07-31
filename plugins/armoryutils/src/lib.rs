//		Imports
//	rrplug utils
use rrplug::prelude::*;

//	modules
mod closures;
mod toposort;
mod logger;

//		Macros
//	This macro allows multiple
#[macro_export]
macro_rules! register_multi {
	($($func:path),* $(,)?) => {
		$(
			rrplug::prelude::register_sq_functions($func);
		)*
	}
}

//		Functionality
#[derive(Debug)]
pub struct ArmoryUtilsPlugin;
impl Plugin for ArmoryUtilsPlugin {
	const PLUGIN_INFO: PluginInfo = PluginInfo::new(
		c"ARMORY_UTILS",			// name
		c"ARMORYUTL",				//  Keep consistent - 9 chars long.
		c"ARMORY_UTILS",			// Dependency string for mods
		PluginContext::all(),		// context -> if it has only client it will not load on dedicated servers
	);

	fn new(_reloaded: bool) -> Self {
		log::info!("[ArmoryUtils] Utility plugin initialized!");

		closures::register();
		toposort::register();
		//register_sq_functions(closure_box);

		Self {}
	}

	// omg some more functions in the trait
}

entry!(ArmoryUtilsPlugin);
