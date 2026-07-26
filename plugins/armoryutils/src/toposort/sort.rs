use rrplug::prelude::*;
//use rrplug::sqfunction;

use super::get_graphs;

use petgraph::algo::toposort;

//	Returns a Result. If a cycle is detected, RRPlug translates the Err into a 
//	native script error, immediately halting the Squirrel VM and printing to the console.
#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryUtils_TopoSortUnsafe"
)]
pub fn toposort_unsafe(handle: i32) -> Result<Vec<String>, String> {
	let mut map = get_graphs().lock().unwrap();
	let manager = map.remove(&handle).ok_or_else(|| "Graph handle not found".to_string())?;

	match toposort(&manager.graph, None) {
		Ok(sorted_indices) => {
			Ok(sorted_indices
				.into_iter()
				.map(|idx| manager.graph[idx].clone())
				.collect())
		}

		//  Throw an error and crash the VM
		Err(cycle) => {
			let cycle_node = &manager.graph[cycle.node_id()];
			Err(format!("TopoSort: Cyclic dependency involving {}", cycle_node))
		}
	}
}

//	Returns a guaranteed array. If successful, contains the sorted node names.
//	If a cycle is detected, it returns an array containing an error token as the 
//	first element, followed by the node that caused the cycle.
#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryUtils_TopoSortSafe"
)]
pub fn toposort_safe(handle: i32) -> Vec<String> {
	let mut map = get_graphs().lock().unwrap();
	let manager = match map.remove(&handle) {
		Some(m) => m,
		None => return vec!["__ERROR_INVALID_HANDLE__".to_string()],
	};

	match toposort(&manager.graph, None) {
		Ok(sorted_indices) => {
			sorted_indices
				.into_iter()
				.map(|idx| manager.graph[idx].clone())
				.collect()
		}

		//  Return [err msg, cycle node]
		Err(cycle) => {
			let cycle_node = &manager.graph[cycle.node_id()];
			vec!["__CYCLE__".to_string(), cycle_node.clone()]
		}
	}
}