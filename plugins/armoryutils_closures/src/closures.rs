//		Imports
use rrplug::{
	bindings::squirreldatatypes::{
		SQObject, SQClosure
	},
	high::{
		squirrel::SQHandle,
	},
	prelude::*,
};

//		Macros
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
/// Setting 'ReturnOverwrite' is unnecessary as the default is already 'var'.
#[rrplug::sqfunction(
	VM = "SERVER | CLIENT | UI", 
	ExportName = "ArmoryUtils_ClosureBox"
)]
pub fn closure_box(obj: SQObject) -> SQObject { obj }