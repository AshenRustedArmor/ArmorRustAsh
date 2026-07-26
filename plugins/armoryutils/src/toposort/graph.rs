use rrplug::prelude::*;
//use rrplug::sqfunction;

use super::{get_graphs, next_handle, TopoGraph};

// ==========================================================
//					Fundamental Operations
// ==========================================================
#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryUtils_TopoCreate"
)]
pub fn topo_create_new() -> i32 {
	let handle = next_handle();
	get_graphs().lock().unwrap().insert(handle, TopoGraph::default());
	handle
}

#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryUtils_TopoNode"
)]
pub fn topo_add_node(handle: i32, name: String) {
	let mut map = get_graphs().lock().unwrap();
	if let Some(manager) = map.get_mut(&handle) {
		if !manager.nodes.contains_key(&name) {
			let idx = manager.graph.add_node(name.clone());
			manager.nodes.insert(name, idx);
		}
	}
}

#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryUtils_TopoEdge"
)]
pub fn topo_add_edge(handle: i32, before: String, after: String) {
	let mut map = get_graphs().lock().unwrap();
	if let Some(manager) = map.get_mut(&handle) {
		// Ensure both nodes exist implicitly if an edge is created between them
		let before_idx = *manager.nodes
			.entry(before.clone())
			.or_insert_with(|| manager.graph.add_node(before));
		
		let after_idx = *manager.nodes
			.entry(after.clone())
			.or_insert_with(|| manager.graph.add_node(after));

		manager.graph.add_edge(before_idx, after_idx, ());
	}
}