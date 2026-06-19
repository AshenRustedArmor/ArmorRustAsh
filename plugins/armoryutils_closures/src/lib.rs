use rrplug::prelude::*;

pub mod state;
pub mod api;
pub mod tasks;

#[derive(Debug)]
pub struct ArmoryPlugin_Registry;
impl Plugin for ArmoryPlugin_Registry {
    const PLUGIN_INFO: PluginInfo = PluginInfo::new(
        c"ARMORYUTILS_REGISTRY",          // name
        c"ARMORY RG",   //  Keep consistent - 9 chars long.
        c"ARMORYUTILS_REGISTRY",  // Dependency string for mods
        PluginContext::all(), // context -> if it has only client it will not load on dedicated servers
    );

    fn new(_reloaded: bool) -> Self {
        log::info!("[ArmoryUtils] Registry Plugin Initialized!");

        register_sq_functions(example_function);

        Self {}
    }

    // omg some more functions in the trait
}

entry!(ArmoryPlugin_Registry);

#[rrplug::sqfunction(VM = "CLIENT | UI | SERVER", ExportName = "ExampleFunction")]
fn example_function(name: String) -> String {
    format!("hello, {}", name)
}