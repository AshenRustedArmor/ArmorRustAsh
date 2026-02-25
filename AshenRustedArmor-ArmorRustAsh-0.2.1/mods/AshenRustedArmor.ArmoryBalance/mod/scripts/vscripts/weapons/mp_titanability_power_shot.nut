untyped

//		Declarations
//	Funcs
global function MpTitanAbilityPowerShot_Init

global function OnWeaponActivate_power_shot

global function OnWeaponPrimaryAttack_power_shot
#if SERVER
global function OnWeaponNpcPrimaryAttack_power_shot
#endif

//	Init
void function MpTitanAbilityPowerShot_Init() {
	#if SERVER
	AddDamageCallbackSourceID( eDamageSourceId.mp_titanweapon_predator_cannon, PowerShot_DamagedEntity )
	RegisterSignal( "PowerShotCleanup" )
	#endif
}

//	     :::       ::: ::::::::::     :::     :::::::::   ::::::::  ::::    :::
//	    :+:       :+: :+:          :+: :+:   :+:    :+: :+:    :+: :+:+:   :+:
//	   +:+       +:+ +:+         +:+   +:+  +:+    +:+ +:+    +:+ :+:+:+  +:+
//	  +#+  +:+  +#+ +#++:++#   +#++:++#++: +#++:++#+  +#+    +:+ +#+ +:+ +#+
//	 +#+ +#+#+ +#+ +#+        +#+     +#+ +#+        +#+    +#+ +#+  +#+#+#
//	 #+#+# #+#+#  #+#        #+#     #+# #+#        #+#    #+# #+#   #+#+#
//	 ###   ###   ########## ###     ### ###         ########  ###    ####

void function OnWeaponActivate_power_shot( entity weapon ) {
	//		Sanity checks
	entity owner = weapon.GetWeaponOwner()
	if( !IsValid(owner) )
		return

	//		Functionality
	PredatorCannonData data = GetPredatorCannonData( weapon )
	data.weaponPowerShot = weapon
}

int function OnWeaponPrimaryAttack_power_shot( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	return PlayerOrNPC_FirePowerShot( weapon, attackParams, true )
}

#if SERVER
int function OnWeaponNpcPrimaryAttack_power_shot( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	return PlayerOrNPC_FirePowerShot( weapon, attackParams, false )
}
#endif

int function PlayerOrNPC_FirePowerShot( entity weapon, WeaponPrimaryAttackParams attackParams, bool playerFired ) {
	//		Sanity checks
	//	Owner must be valid & committing
	entity owner = weapon.GetWeaponOwner()
	if ( owner.ContextAction_IsActive() || (playerFired && owner.PlayerMelee_GetState() != PLAYER_MELEE_STATE_NONE) )
		return 0

	//	Prevent power shot during ammo swap
	array<entity> weapons = GetPrimaryWeapons( owner )
	entity minigun = weapons[0]
	if ( !IsValid( minigun ) || minigun.IsReloading() || owner.e.ammoSwapPlaying == true )
		return 0

	//	Prevent power shot during reload
	int milestone = minigun.GetReloadMilestoneIndex()
	if ( milestone != 0 )
		return 0

	//	Prevent firing without the mod?
	if ( minigun.HasMod( "PowerShot_Common" ) )
		return 0

	//	Prevent power shot without ammo
	int rounds = minigun.GetWeaponPrimaryClipCount()
	if ( rounds == 0 )
		return 0

	#if SERVER
	PredatorCannonData data = GetPredatorCannonData( minigun )

	//		Player functionality
	//	Force players to commit
	data.forceCommit = playerFired

	if ( playerFired ) {
		owner.SetTitanDisembarkEnabled( false )
		owner.SetMeleeDisabled()
		PlayerUsedOffhand( owner, weapon )

		minigun.SetForcedADS()
	}

	//	Retrieve mods
	data.normalShotMods = minigun.GetMods()
	activeMods = clone data.normalShotMods

	string powerShotName = "PowerShot_LRB_Shot"
	if ( activeMods.contains("CQB_ModeSwap") ) {
		activeMods.fastremovebyvalue("CQB_ModeSwap")
		powerShotName = "PowerShot_CQB_Slug"

		//	Not sure what to replace this with
		if ( activeMods.contains("fd_longrange_helper") )
			activeMods.append("fd_LongRangePowerShot")
	} else if ( activeMods.contains("fd_closerange_helper") ) {
		activeMods.append( "fd_CloseRangePowerShot" )
	}

	activeMods.append( "PowerShot_Common" )
	activeMods.append( powerShotName )
	minigun.SetMods( activeMods )

	//	Cleanup thread
	thread PowerShotThreadedCleanup( owner, minigun, data )
	#endif

	//	Handle ammo
	return weapon.GetAmmoPerShot()
}

//	       :::::::::: :::    ::: ::::    :::  :::::::: ::::::::::: ::::::::::: ::::::::  ::::    :::  ::::::::
//	      :+:        :+:    :+: :+:+:   :+: :+:    :+:    :+:         :+:    :+:    :+: :+:+:   :+: :+:    :+:
//	     +:+        +:+    +:+ :+:+:+  +:+ +:+           +:+         +:+    +:+    +:+ :+:+:+  +:+ +:+
//	    :#::+::#   +#+    +:+ +#+ +:+ +#+ +#+           +#+         +#+    +#+    +:+ +#+ +:+ +#+ +#++:++#++
//	   +#+        +#+    +#+ +#+  +#+#+# +#+           +#+         +#+    +#+    +#+ +#+  +#+#+#        +#+
//	  #+#        #+#    #+# #+#   #+#+# #+#    #+#    #+#         #+#    #+#    #+# #+#   #+#+# #+#    #+#
//	 ###         ########  ###    ####  ########     ###     ########### ########  ###    ####  ########

#if SERVER
void function PowerShotThreadedCleanup( entity owner, entity weapon, PredatorCannonData data ) {
	//		Sanity checks
	//	Owner validity check
	if( !IsValid(owner) )
		return

	//	Weapon validity check
	if( !IsValid(weapon) )
		return

	//		Ending functionality
	OnThreadEnd( function() : ( owner, weapon, data ) {
			//	Clear status
			if (IsValid(owner) && data.forceCommit) {
				owner.ClearMeleeDisabled()
				owner.SetTitanDisembarkEnabled( true )
			}

			if( IsValid(weapon) ) {
				weapon.ClearForcedADS()
				data.forceCommit = false

				weapon.SetMods(data.normalShotMods)
			}
	}	)

	//		Threading
	//	Termination signals
	owner.EndSignal("OnDeath")
	owner.EndSignal("TitanEjectionStarted")

	weapon.EndSignal( "OnDestroy" )
	weapon.EndSignal( "PowerShotCleanup" )

	WaitForever()
}

void function PowerShot_DamagedEntity( entity victim, var damageInfo ) {
	int scriptDamageType = DamageInfo_GetCustomDamageType( damageInfo )

	if ( scriptDamageType & DF_KNOCK_BACK && !IsHumanSized( victim ) ) {
		entity attacker = DamageInfo_GetAttacker( damageInfo )

		float distance = Distance( victim.GetOrigin(), attacker.GetOrigin() )
		vector pushback = Normalize( victim.GetOrigin() - attacker.GetOrigin() )
		pushback *= 500 * 1.0 - StatusEffect_Get( victim, eStatusEffect.pushback_dampen ) * GraphCapped( distance, 0, 1200, 1.0, 0.25 )

		PushPlayerAway( victim, pushback )
	}
}
#endif