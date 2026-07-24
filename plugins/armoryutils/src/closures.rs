//		Imports
use rrplug::{
	bindings::squirreldatatypes::{SQObject},
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

//	Registration router
pub fn register_funcs() {
	register_sq_functions(closure_box);
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