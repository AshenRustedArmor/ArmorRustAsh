globalize_all_functions

void function ArmoryUtil_SetModState( entity weapon, string modName, bool applyMod ) {
	//		Sanity checks
	if( !IsValid( weapon ) )
		return

	if( modName == "" )
		return

	//	Functionality
	array <string> mods = weapon.GetMods()
	bool hasMod = mods.contains( modName )

	printt( "[ArmoryUtil] SetModState: mod = \'" +applyMod+ "\', has = " +hasMod+ ", set = " +applyMod )

	if( applyMod && !hasMod ) {
		mods.append( modName )
		weapon.SetMods( mods )
	} else if ( !applyMod && hasMod ) {
		mods.fastremovebyvalue( modName )
		weapon.SetMods( mods )
	}
}
