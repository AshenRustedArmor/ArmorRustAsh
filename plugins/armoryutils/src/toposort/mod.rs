use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use petgraph::graph::{Graph, NodeIndex};
use petgraph::Directed;

pub mod graph;
pub mod sort;

//	Graph struct
#[derive(Default)]
pub struct TopoGraph {
    pub graph: Graph<String, (), Directed>,
    pub nodes: HashMap<String, NodeIndex>,
}

// ==========================================================
//					Global State / Retrieval
// ==========================================================
//  Global state
static GRAPHS: OnceLock<Mutex<  HashMap<i32, TopoGraph>  >> = OnceLock::new();
static HANDLE_COUNTER: OnceLock<Mutex<  i32  >> = OnceLock::new();

pub fn next_handle() -> i32 {
    let mut counter = HANDLE_COUNTER.get_or_init(|| Mutex::new(0)).lock().unwrap();
    let current = *counter;
    *counter += 1;
    current
}

pub fn get_graphs() -> &'static Mutex<HashMap<i32, TopoGraph>> {
    GRAPHS.get_or_init(|| Mutex::new(HashMap::new()))
}

// ==========================================================
//					FFI function registry
// ==========================================================
pub fn register() {
    crate::register_multi!(
        graph::Topo_Create,
        graph::Topo_AddNode,
        graph::Topo_AddEdge,
		
        sort::TopoSort_Panic,
        sort::TopoSort_Error
    );
}