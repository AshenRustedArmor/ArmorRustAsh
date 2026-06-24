use rrplug::prelude::*;
mod closures;

#[derive(Debug)]
pub struct ArmoryPluginClosures;
impl Plugin for ArmoryPluginClosures {
	const PLUGIN_INFO: PluginInfo = PluginInfo::new(
		c"ARMORY_UTILS_CLOSURES",	// name
		c"ARMORYCLS",				//  Keep consistent - 9 chars long.
		c"ARMORY_UTILS_CLOSURES",	// Dependency string for mods
		PluginContext::all(),		// context -> if it has only client it will not load on dedicated servers
	);

	fn new(_reloaded: bool) -> Self {
		log::info!("[ArmoryUtils] Registry Plugin Initialized!");

		register_sq_functions(closures::closure_box);

		Self {}
	}

	// omg some more functions in the trait
	}

entry!(ArmoryPluginClosures);