globalize_all_functions
globalize_all_classes

const string MSG_UNWRAP_NONE = "Called Option.unwrap() on a 'None' value."
class Option {
	private var value = null
	private bool isSome = false
	constructor( var v, bool s ) { value = v; isSome = s }

	bool function IsSome() { return  isSome }
	bool function IsNone() { return !isSome }

	var function expect( string msg ) {
		if (!isSome) { throw msg }
		return value
	}

	var function unwrap() {
		if (!isSome) { throw msg }
		return value
	}

	var function unwrap_or( var fallback ) {
		return isSome ? value : fallback
	}
}

Option function Some( var val ) { return Option( val, true ) }
Option function None() { return Option( null, false ) }
Option function OptionFrom( var nullable ) {
	if (nullable == null) { return None() }
	return Some( nullable )
}