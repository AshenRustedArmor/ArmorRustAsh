use rrplug::prelude::*;
use super::{get_graphs, next_handle, TopoGraph};

// ==========================================================
//					Fundamental Operations
// ==========================================================
#[sqfunction(VM = "Server")]
pub fn Topo_Create() -> i32 {
    let handle = next_handle();
    get_graphs().lock().unwrap().insert(handle, TopoGraph::default());
    handle
}

#[sqfunction(VM = "Server")]
pub fn Topo_AddNode(handle: i32, name: String) {
    let mut map = get_graphs().lock().unwrap();
    if let Some(manager) = map.get_mut(&handle) {
        if !manager.nodes.contains_key(&name) {
            let idx = manager.graph.add_node(name.clone());
            manager.nodes.insert(name, idx);
        }
    }
}

#[sqfunction(VM = "Server")]
pub fn Topo_AddEdge(handle: i32, before: String, after: String) {
    let mut map = get_graphs().lock().unwrap();
    if let Some(manager) = map.get_mut(&handle) {
        // Ensure both nodes exist implicitly if an edge is created between them
        let before_idx = *manager.nodes.get(&before).unwrap_or_else(|| {
            let idx = manager.graph.add_node(before.clone());
            manager.nodes.insert(before.clone(), idx);
            &idx
        });
        
        let after_idx = *manager.nodes.get(&after).unwrap_or_else(|| {
            let idx = manager.graph.add_node(after.clone());
            manager.nodes.insert(after.clone(), idx);
            &idx
        });

        manager.graph.add_edge(before_idx, after_idx, ());
    }
}