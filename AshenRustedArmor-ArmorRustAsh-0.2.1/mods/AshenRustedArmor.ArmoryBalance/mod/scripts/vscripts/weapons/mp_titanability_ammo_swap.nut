
global function MpTitanAbilityAmmoSwap_Init
global function OnWeaponOwnerChanged_titanability_ammo_swap

global function OnWeaponPrimaryAttack_ammo_swap
#if SERVER
global function OnWeaponNpcPrimaryAttack_ammo_swap

global function AddAmmoStatusEffect

struct AmmoSwapStruct {
	int statusEffectId
	entity weaponOwner
}

struct {
	array<AmmoSwapStruct> ammoSwapStatusEffects
} file
#endif

const asset POWER_SHOT_ICON_CLOSE = $"rui/titan_loadout/ordnance/concussive_shot_short"
const asset POWER_SHOT_ICON_FAR = $"rui/titan_loadout/ordnance/concussive_shot_long"

void function MpTitanAbilityAmmoSwap_Init() {
	#if CLIENT
	PrecacheHUDMaterial( POWER_SHOT_ICON_CLOSE )
	PrecacheHUDMaterial( POWER_SHOT_ICON_FAR )
	#endif
}

//	     :::       ::: ::::::::::     :::     :::::::::   ::::::::  ::::    :::
//	    :+:       :+: :+:          :+: :+:   :+:    :+: :+:    :+: :+:+:   :+:
//	   +:+       +:+ +:+         +:+   +:+  +:+    +:+ +:+    +:+ :+:+:+  +:+
//	  +#+  +:+  +#+ +#++:++#   +#++:++#++: +#++:++#+  +#+    +:+ +#+ +:+ +#+
//	 +#+ +#+#+ +#+ +#+        +#+     +#+ +#+        +#+    +#+ +#+  +#+#+#
//	 #+#+# #+#+#  #+#        #+#     #+# #+#        #+#    #+# #+#   #+#+#
//	 ###   ###   ########## ###     ### ###         ########  ###    ####

void function OnWeaponOwnerChanged_titanability_ammo_swap( entity weapon, WeaponOwnerChangedParams changeParams ) {
	#if SERVER
	if ( IsValid( changeParams.newOwner ) && changeParams.newOwner.IsPlayer() ) {
		AddAmmoStatusEffect( changeParams.newOwner )
	}

	if ( IsValid( changeParams.oldOwner ) && changeParams.oldOwner.IsPlayer() )
		RemoveAmmoStatusEffect( changeParams.oldOwner )

	if ( IsValid( changeParams.oldOwner ) && !IsValid( changeParams.newOwner ) ) {
		foreach ( effect in weapon.w.fxHandles ) {
			EffectStop( effect )
		}
		weapon.w.fxHandles = []
	}
	#endif
}

int function OnWeaponPrimaryAttack_ammo_swap( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	PlayerOrNPCFire_ammo_swap( weapon, attackParams, true )
}

#if SERVER
int function OnWeaponNpcPrimaryAttack_ammo_swap( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	PlayerOrNPCFire_ammo_swap( weapon, attackParams, false )
}
#endif

const string SWITCH_SFX_LRB_1P = "weapon_predator_rangeswitch_tolong_1p"
const string SWITCH_SFX_LRB_3P = "weapon_predator_rangeswitch_tolong_3p"
const string SWITCH_SFX_CQB_1P = "weapon_predator_rangeswitch_toshort_1p"
const string SWITCH_SFX_CQB_3P = "weapon_predator_rangeswitch_toshort_3p"
int function PlayerOrNPCFire_ammo_swap( entity weapon, WeaponPrimaryAttackParams attackParams, bool playerFired ) {
	//		Sanity checks
	//	Minigun validity check
	array<entity> weapons = GetPrimaryWeapons( owner )
	entity minigun = weapons[0]
	if ( !IsValid( minigun ) )
		return 0

	//	No swap while reloading
	if ( minigun.IsReloading() )
		return 0

	//	No swap during power shot
	if ( minigun.HasMod( "LongRangePowerShot" ) || minigun.HasMod( "CloseRangePowerShot" ) )
		return 0

	//	Owner check
	entity owner = weapon.GetWeaponOwner()
	if ( owner.ContextAction_IsActive() )
		return 0

	//	No swap during melee
	if ( playerFired && owner.PlayerMelee_GetState() != PLAYER_MELEE_STATE_NONE )
		return 0

	//	Minigun isn't active
	if ( !IsPredatorCannonActive( owner, false ) )
		return 0

	//


	//		Functionality
	//	Offhand trigger
	owner.e.ammoSwapPlaying = true
	if ( playerFired )
		PlayerUsedOffhand( owner, weapon )

	//	Switch sounds - why wasn't this done in the keyvars?
	string switchSFX_1P = SWITCH_SFX_CQB_1P
	string switchSFX_3P = SWITCH_SFX_CQB_3P
	if ( minigun.HasMod( "LongRangeAmmo") ) {
		switchSFX_1P = SWITCH_SFX_LRB_1P
		switchSFX_3P = SWITCH_SFX_LRB_1P
	}
	weapon.EmitWeaponSound_1p3p( switchSFX_1P, switchSFX_3P )

	//	Ammo mods
	thread ToggleAmmoMods( weapon, minigun, owner )

	//	Ammo
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

void function AddAmmoStatusEffect( entity player ) {
	array<entity> weapons = GetPrimaryWeapons( player )
	if ( weapons.len() == 0 )
		return

	entity primaryWeapon = weapons[0]
	if ( !IsValid( primaryWeapon ) )
		return

	RemoveAmmoStatusEffect( player )
	float cockpitColor
	if( primaryWeapon.HasMod( "Smart_Core" ) ) {
		cockpitColor = COCKPIT_COLOR_HIDDEN
	} else if( primaryWeapon.HasMod( "LongRangeAmmo" ) ) {
		cockpitColor = COCKPIT_COLOR_RED
	} else {
		cockpitColor = COCKPIT_COLOR_YELLOW
	}

	AmmoSwapStruct info
	info.weaponOwner = player
	info.statusEffectId = StatusEffect_AddEndless( player, eStatusEffect.cockpitColor, cockpitColor )
	file.ammoSwapStatusEffects.append( info )
}

void function RemoveAmmoStatusEffect( entity player ) {
	for ( int i = file.ammoSwapStatusEffects.len() - 1; i >= 0; i-- ) {
		entity owner = file.ammoSwapStatusEffects[i].weaponOwner
		if ( !IsValid( owner ) ) {
			file.ammoSwapStatusEffects.remove( i )
			continue
		}
		if ( owner == player ) {
			StatusEffect_Stop( player, file.ammoSwapStatusEffects[i].statusEffectId )
			file.ammoSwapStatusEffects.remove( i )
		}
	}
}

void function HACK_Delayed_PushForceADS( entity minigun ) {
	EndSignal( minigun, "OnDestroy" )
	WaitFrame() // doesn't work until you wait a frame... WHY
	minigun.SetForcedADS()
}
#endif

void function ToggleAmmoMods( entity weapon, entity minigun, entity owner ) {
	minigun.EndSignal( "OnDestroy" )

	owner.EndSignal( "OnDeath" )
	owner.EndSignal( "OnDestroy" )
	owner.EndSignal( "DisembarkingTitan" )
	owner.EndSignal( "TitanEjectionStarted" )
	owner.EndSignal( "SettingsChanged")

	if ( owner.IsPlayer() ) {
		string attackerAnim1p = "ACT_SCRIPT_CUSTOM_ATTACK"
		owner.Weapon_StartCustomActivity( attackerAnim1p, false )
		#if SERVER
		owner.SetMeleeDisabled()
		if ( IsMultiplayer() ) {
			string anim3p = "ACT_SCRIPT_CUSTOM_ATTACK"
			owner.Anim_PlayGesture( anim3p, 0.2, 0.2, -1.0 )
		}
		#endif
	}

	OnThreadEnd( function() : ( owner, minigun, weapon ) {
			owner.e.ammoSwapPlaying = false

			#if SERVER
			ToggleWeaponMods( owner, minigun, weapon )
			#endif
	}	)

	if ( owner.IsPlayer() ) {
		entity viewModel = owner.GetViewModelEntity()
		float animDuration = viewModel.GetSequenceDuration( "ammo_swap_seq" )

		wait animDuration
	}
}

void function ToggleMod( entity weapon, string modName ) {
	if ( weapon.HasMod( modName ) ) {
		RemoveMod( weapon, modName )
	} else {
		array<string> mods = weapon.GetMods()

		if ( modName != "" )
			mods.append( modName )

		weapon.SetMods( mods )
	}
}

void function RemoveMod( entity weapon, string modName ) {
	array<string> mods = weapon.GetMods()
	mods.fastremovebyvalue( modName )
	weapon.SetMods( mods )
}

#if SERVER
void function ToggleWeaponMods( entity owner, entity minigun, entity weapon ) {
	if( IsValid( minigun ) ) {
		// JFS: defensive fix since sometimes this can trigger while the power shot is active
		if ( minigun.HasMod( "LongRangePowerShot" ) || minigun.HasMod( "CloseRangePowerShot" ) )
			return

		ToggleMod( minigun, "LongRangeAmmo" )
	}

	if ( IsValid( weapon ) ) {
		ToggleMod( weapon, "ammo_swap_ranged_mode" )
	}

	if ( IsValid( owner ) ) {
		entity powerShotWeapon = owner.GetOffhandWeapon( OFFHAND_RIGHT )
		if ( IsValid( powerShotWeapon ) ) {
			ToggleMod( powerShotWeapon, "power_shot_ranged_mode" )
		}
	}

	if ( owner.IsPlayer() ) {
		AddAmmoStatusEffect( owner )
		owner.ClearMeleeDisabled()
	}
}
#endif