use rrplug::{
	bindings::squirreldatatypes::{
		SQClosure, SQObject, SQArray, SQTable,
		SQObjectType,
	},
	high::{
		squirrel::SQHandle,
		squirrel_traits::GetFromSQObject,
	},
	prelude::*
};

use std::sync::Mutex;
use std::collections::HashMap;
use std::ptr::slice_from_raw_parts;

macro_rules! get_handle {
    ($obj:expr, $ty:ident) => {{
        ::rrplug::high::squirrel::SQHandle::<::rrplug::bindings::squirreldatatypes::$ty>::try_new(
            ($obj).clone(),
        )
        .map_err(|_| ::rrplug::errors::CallError::FunctionFailed(
            format!("Argument validation failed: expected {}", stringify!($ty))
        ))
    }};
}

// ======================================================
//						Boxing
// ======================================================
/// Bounces a typed closure off the FFI boundary to strip its type.
/// By setting `ReturnOverwrite = "var"`, the Squirrel compiler "forgets" 
/// the strict function signature, allowing you to pass it freely in script.
#[rrplug::sqfunction(
    VM = "SERVER | CLIENT | UI", 
    ExportName = "ArmoryUtils_ClosureBox",
    ReturnOverwrite = "var" 
)]
pub fn closure_box(obj: SQObject) -> SQObject { obj }

/*
#[derive(Clone, Debug)]
pub struct BoxedClosure {
	pub closure: SQHandle<SQClosure>,
}

static NEXT_IDX: Mutex<i32> = Mutex::new(1);
static CLOSURES: Mutex<HashMap<i32, BoxedClosure>> = Mutex::new(HashMap::new());

#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = "ArmoryUtils_ClosureBox")]
pub fn closure_box(
	closure: SQHandle<SQClosure>
) -> Result<i32, rrrplug::errors::CallEror> {
	//	NEXT_IDX mutex lock aquired and dropped here
	let id = {
		let mut next_id = NEXT_IDX.lock().unwrap();
		let current = *next_id;
		*next_id += 1;
		current
	};

	//	CLOSURES mutex lock aquired and dropped here
	{
		let mut vault = CLOSURES.lock().unwrap()
		vault.insert(id, BoxedClosure{ closure })
	}

    Ok(id)
}

pub fn closure_unbox(
	handle: i32
) -> Result<SQHandle<SQClosure>, rrplug::errors::CallError> {
	//	CLOSURES mutex lock aquired and dropped here
	let closure = {
		let vault = CLOSURES.lock().unwrap;
		let boxed = vault.get(&handle).ok_or_else(||{
			rrplug::errors::CallError::FunctionFailed(format!("Invalid closure handle: {}", handle))
		})?;
		boxed.closure.clone()
	};

	Ok(closure)
} // */

// ======================================================
//					Metadata reflection
// ======================================================
fn get_closure_params(handle: &SQHandle<SQClosure>) -> Vec<String> {
	let mut params = Vec::new();
	unsafe {
		let closure_ptr = handle.get_inner()._val.asClosure;
		let proto = (*closure_ptr)._function;
		
		let n_params = (*proto)._nparameters as usize;
		let param_array = slice_from_raw_parts((*proto)._parameters, n_params)
			.as_ref().unwrap_or(&[]);

		for (i, param_obj) in param_array.iter().enumerate() {
			if i == 0 { continue; } //	Skip 'this'
			if param_obj._Type == SQObjectType::OT_STRING {
				params.push(String::get_from_sqobject(param_obj)); //
			}
		}
	}
	params
}

#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = "ArmoryUtils_ClosureName")]
pub fn closure_name(closure_obj: SQObject) -> Result<String, rrplug::errors::CallError> {
	let closure = get_handle!(closure_obj, SQClosure)?;
	unsafe {
		let closure_ptr = closure.get_inner()._val.asClosure;
		let proto = (*closure_ptr)._function;
		let name_obj = (*proto)._name;
		
		if name_obj._Type == SQObjectType::OT_STRING {
			return Ok(String::get_from_sqobject(&name_obj));
		}
	}

	Ok("anonymous".to_string())
}

#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = "ArmoryUtils_ClosureParams")]
pub fn closure_params(closure_obj: SQObject) -> Result<Vec<String>, rrplug::errors::CallError> {
	let closure = get_handle!(closure_obj, SQClosure)?;
    Ok(get_closure_params(&closure))
}


// ======================================================
//						Execution
// ======================================================
pub fn closure_call(
	closure_obj: SQObject,
	args_obj: SQObject
) -> Result<(), rrplug::errors::CallError> {
	//	1. Validate generic SQObjects
	let closure_handle = get_handle!(closure_obj, SQClosure)?;
	let table_handle = get_handle!(args_obj, SQTable)?;

	//	2. Fetch the required parameter names from the closure
	let required_params = extract_closure_params(&closure_handle);
    let mut arg_objs: Vec<SQObject> = Vec::with_capacity(required_params.len());

	unsafe {
		//	3. Push the args table onto the VM stack
		let table_ptr = table_handle.get_inner();
		let num_nodes = (*table_ptr)._numOfNodes as usize;
		let nodes_slice = slice_from_raw_parts((*table_ptr)._nodes, num_nodes).as_ref()
			.ok_or_else(|| rrplug::errors::CallError::FunctionFailed("Failed to read table nodes".to_string()))?;

		//	 4. Extract via stack
		for name in &required_params {
			let found_node = nodes_slice.iter().find(|node| {
				node.key._Type == SQObjectType::OT_STRING && 
				String::get_from_sqobject(&node.key) == *name
			});

			if let Some(node) = found_node {
				arg_objects.push(node.val); // Grab the raw SQObject value
			} else {
				// Instantly throw the Squirrel exception if a required argument is missing
				return Err(rrplug::errors::CallError::FunctionFailed(
					format!("Missing required parameter '{}' in args table.", name)
				));
			}
		}

		//	5. Execution setup & Fire
		let mut raw_closure = *closure_handle.get_inner();
		(sq_functions.sq_pushobject)(sqvm.as_ptr(), &mut raw_closure);
		(sq_functions.sq_pushroottable)(sqvm.as_ptr());

		//	Push precisely the arguments the closure asked for
		for mut obj in arg_objects {
			(sq_functions.sq_pushobject)(sqvm.as_ptr(), &mut obj);
		}

		let num_params = (required_params.len() + 1) as i32;
		let result = (sq_functions.sq_call)(sqvm.as_ptr(), num_params, 0, 1);

		if result < 0 {
			return Err(rrplug::errors::CallError::FunctionFailed(
				"Execution failed for dynamically punned closure".to_string()
			));
		}

		(sq_functions.sq_pop)(sqvm.as_ptr(), 1);
	}

	Ok(())
}