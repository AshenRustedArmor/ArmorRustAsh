use rrplug::{
	bindings::squirreldatatypes::{
		SQClosure
		SQObject,
		SQArray,
		SQTable,
	},
	high::squirrel::{SQHandle, call_sq_object_function},
	prelude::*
};

//use rrplug::bindings::s_sqobject::SQObject;

use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Clone, Debug)]
pub struct BoxedClosure {
	pub closure: SQObject,
}

static NEXT_IDX: Mutex<i32> = Mutex::new(1);
static CLOSURES: Mutex<HashMap<i32, BoxedClosure>> = Mutex::new(HashMap::new());

// ======================================================
//						Boxing
// ======================================================
#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = "ArmoryUtils_ClosureBox")]
pub fn closure_box(closure: SQHandle<SQClosure>) -> Result<i32, rrplug::errors::CallError> {
	let mut next_id = NEXT_IDX.lock().unwrap();
	let id = *next_id;
	*next_id += 1;

	CLOSURES.lock().unwrap().insert(id, BoxedClosure { closure });
    Ok(id)
}

pub fn closure_unbox(handle: i32) -> Result<SQHandle<SQClosure>, rrplug::errors::CallError> {
	// Fetch the closure
	let vault = CLOSURES.lock().unwrap;
	let boxed = vault.get(&handle).ok_or_else(||{
        rrplug::errors::CallError::FunctionFailedToExecute(format!("Invalid closure handle: {}", handle))
	})?;

	// Cloning the handle boosts the engine's internal ref-count, allowing
	// safe returns while releasing the global Mutex guard.
	Ok(boxed.closure.clone())
}

pub fn closure_call(
	handle: i32,
	args: SQObject
) -> Result<(), rrplug::errors::CallError> {
	let closure = closure_unbox(handle)?;
	let _array_handle = SQHandle::<SQArray>::try_new(args.clone()).map_err(|_|{
		rrplug::errors::CallError::FunctionFailed("Arguments must be an Array".to_string())
	})?;

	unsafe {
		let array_ptr = args._val.asArray;
		let array_len = (*array_ptr)._usedSlots as usize;
		let array_slice = slice_from_raw_parts((*array_ptr)._values, array_len).as_ref()
			.ok_or_else(|| rrplug::errors::CallError::FunctionFailed("Failed to read array".to_string()))?;

		//	1.	Push closure to the stack
		let mut raw_closure = *closure.get_inner();
        (sq_functions.sq_pushobject)(sqvm.as_ptr(), &mut raw_closure);
        (sq_functions.sq_pushroottable)(sqvm.as_ptr());

		//	2. Push parameters onto the execution stack
		for item in array_slice {
			let mut arg_obj = *item; 
			(sq_functions.sq_pushobject)(sqvm.as_ptr(), &mut arg_obj);
		}

		//	3. Fire native closure: sq_call(vm, params (args + 'this'), retval, raise_error)
		let num_params = (array_len + 1) as i32;
		let result = (sq_functions.sq_call)(sqvm.as_ptr(), num_params, 0, 1);

		if result < 0 {
			return Err(rrplug::errors::CallError::FunctionFailed(format!(
				"Execution failed for handle {}", handle
			)));
		}

		//	Clean up the stack
		(sq_functions.sq_pop)(sqvm.as_ptr(), 1);
	}

	Ok(())
}

// ======================================================
//					Metadata reflection
// ======================================================
#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = "ArmoryUtils_ClosureGetName")]
pub fn closure_get_name(handle: i32) -> Result<String, rrplug::errors::CallError> {
	//	Fetch the closure
	let closure = closure_unbox(handle)?;

	//	Unsafe block
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

#[rrplug::sqfunction(VM = "SERVER | CLIENT | UI", ExportName = "ArmoryUtils_ClosureGetParams")]
pub fn closure_get_params(handle: i32) -> Result<Vec<String>, rrplug::errors::CallError> {
	//	Fetch the closure
	let closure = closure_unbox(handle)?;
	let mut params = Vec::new();

	unsafe {
		let closure_ptr = closure.get_inner()._val.asClosure;
		let proto = (*closure_ptr)._function;
		
		let n_params = (*proto)._nparameters as usize;
		let param_array = slice_from_raw_parts((*proto)._parameters, n_params)
			.as_ref().unwrap_or(&[]);

		for (i, param_obj) in param_array.iter().enumerate() {
			if i == 0 { continue; } // Skip 'this' pointer context boundary
			
			if param_obj._Type == SQObjectType::OT_STRING {
				params.push(String::get_from_sqobject(param_obj));
			}
		}
	}

	Ok(params)
}