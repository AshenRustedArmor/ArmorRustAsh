
global function MpTitanAbilityAmmoSwap_Init

global function OnWeaponActivate_ammo_swap
global function OnWeaponOwnerChanged_titanability_ammo_swap

global function OnWeaponPrimaryAttack_ammo_swap
#if SERVER
global function OnWeaponNpcPrimaryAttack_ammo_swap

global function AddAmmoStatusEffect
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

void function OnWeaponActivate_ammo_swap( entity weapon ) {
	//		Sanity checks
	entity owner = weapon.GetWeaponOwner()
	if( !IsValid(owner) )
		return

	//		Functionality
	PredatorCannonData data = GetPredatorCannonData( owner )
	data.weaponPowerShot = weapon
}

void function OnWeaponOwnerChanged_titanability_ammo_swap( entity weapon, WeaponOwnerChangedParams changeParams ) {
	#if SERVER
	if ( IsValid( changeParams.newOwner ) && changeParams.newOwner.IsPlayer() ) {
		SetCockpitColor( changeParams.newOwner, true )
	}

	if ( IsValid( changeParams.oldOwner ) && changeParams.oldOwner.IsPlayer() )
		SetCockpitColor( changeParams.oldOwner, false)

	if ( IsValid( changeParams.oldOwner ) && !IsValid( changeParams.newOwner ) ) {
		foreach ( effect in weapon.w.fxHandles ) {
			EffectStop( effect )
		}
		weapon.w.fxHandles = []
	}
	#endif
}

var function OnWeaponPrimaryAttack_ammo_swap( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	return PlayerOrNPC_Fire( weapon, attackParams, true )
}

#if SERVER
var function OnWeaponNpcPrimaryAttack_ammo_swap( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	return PlayerOrNPC_Fire( weapon, attackParams, false )
}
#endif

const string SWITCH_SFX_LRB_1P = "weapon_predator_rangeswitch_tolong_1p"
const string SWITCH_SFX_LRB_3P = "weapon_predator_rangeswitch_tolong_3p"
const string SWITCH_SFX_CQB_1P = "weapon_predator_rangeswitch_toshort_1p"
const string SWITCH_SFX_CQB_3P = "weapon_predator_rangeswitch_toshort_3p"
int function PlayerOrNPC_Fire( entity weapon, WeaponPrimaryAttackParams attackParams, bool playerFired ) {
	//		Sanity checks
	//	Owner validity check
	entity owner = weapon.GetWeaponOwner()
	if( !IsValid(owner) ) return 0

	//	Minigun validity check
	PredatorCannonData data = GetPredatorCannonData( owner )
	entity minigun = data.weaponPredatorCannon
	if ( !IsValid( minigun ) ) return 0

	if ( minigun.IsReloading() ) return 0													//	No swap while reloading
	if ( minigun.HasMod( "PowerShot_Common" ) ) return 0									//	No swap during power shot

	if ( owner.ContextAction_IsActive() ) return 0											//	Owner animation check?
	if ( playerFired && owner.PlayerMelee_GetState() != PLAYER_MELEE_STATE_NONE ) return 0	//	No swap during melee
	if ( !IsPredatorCannonActive( owner, false ) ) return 0									//	Minigun isn't active

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
	thread ToggleAmmoMods( owner )

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
void function SetCockpitColor( entity player, bool add ) {
	//		Sanity checks
	PredatorCannonData data = GetPredatorCannonData( player )

	//	Minigun exists
	entity minigun = data.weaponPredatorCannon
	if ( !IsValid( minigun ) )
		return

	//		Functionality
	//	Swap cockpit color
	if( add ) {
		float cockpitColor = COCKPIT_COLOR_YELLOW
		if( minigun.HasMod( "AmmoSwap_Smart" ) ) {
			cockpitColor = COCKPIT_COLOR_HIDDEN
		} else if( minigun.HasMod( "AmmoSwap_CQB" ) ) {
			cockpitColor = COCKPIT_COLOR_RED
		}

		data.statusEffectId = StatusEffect_AddEndless( player, eStatusEffect.cockpitColor, cockpitColor )
		return
	}

	//	Remove old color
	if ( data.statusEffectId != -1 ) {
		StatusEffect_Stop( player, data.statusEffectId )
		data.statusEffectId = -1
	}
}

//	This should be deprecated, but I'm not sure where this is used.
void function AddAmmoStatusEffect( entity player ) { SetCockpitColor( player, true ) }

void function HACK_Delayed_PushForceADS( entity minigun ) {
	EndSignal( minigun, "OnDestroy" )
	WaitFrame() // doesn't work until you wait a frame... WHY
	minigun.SetForcedADS()
}
#endif

const string ATTACK_ANIM_1P = "ACT_SCRIPT_CUSTOM_ATTACK"
const string ATTACK_ANIM_3p = "ACT_SCRIPT_CUSTOM_ATTACK"
void function ToggleAmmoMods( entity owner ) {
	if ( owner.IsPlayer() ) {
		owner.Weapon_StartCustomActivity( ATTACK_ANIM_1P, false )
		#if SERVER
		owner.SetMeleeDisabled()
		if ( IsMultiplayer() ) {
			owner.Anim_PlayGesture( ATTACK_ANIM_3p, 0.2, 0.2, -1.0 )
		}
		#endif
	}

	//	Threading
	PredatorCannonData data = GetPredatorCannonData( owner )

	data.weaponPredatorCannon.EndSignal( "OnDestroy" )

	owner.EndSignal( "OnDeath" )
	owner.EndSignal( "OnDestroy" )
	owner.EndSignal( "DisembarkingTitan" )
	owner.EndSignal( "TitanEjectionStarted" )
	owner.EndSignal( "SettingsChanged")


	OnThreadEnd( function() : ( owner, data ) {
			owner.e.ammoSwapPlaying = false

			#if SERVER
			data.isCQB = !data.isCQB

			//	Set minigun mods
			entity minigun = data.weaponPredatorCannon
			if( IsValid(minigun)) {
				if( minigun.HasMod("PowerShot_Common") )
					return

				SetModState( minigun, "AmmoSwap_CQB", data.isCQB )
			}

			entity ammoSwap = data.weaponAmmoSwap
			if( IsValid(ammoSwap) ) {
				SetModState( ammoSwap, "AmmoSwap_CQB", data.isCQB )
			}

			entity powerShot = data.weaponPowerShot
			if( IsValid(powerShot) ) {
				SetModState( powerShot, "AmmoSwap_CQB", data.isCQB )
			}

			//	Update UI
			if ( owner.IsPlayer() ) {
				SetCockpitColor( owner, true )
				owner.ClearMeleeDisabled()
			}
			#endif
	}	)

	//	Thread
	if ( owner.IsPlayer() ) {
		entity viewModel = owner.GetViewModelEntity()
		float animDuration = viewModel.GetSequenceDuration( "ammo_swap_seq" )

		wait animDuration
	}
}

void function SetModState( entity weapon, string modName, bool applyMod ) {
	//		Sanity checks
	if( !IsValid( weapon ) )
		return

	if( modName == "" )
		return

	//	Functionality
	array <string> mods = weapon.GetMods()
	bool hasMod = mods.contains( modName )

	if( applyMod && !hasMod ) {
		mods.append( modName )
		weapon.SetMods( mods )
	} else if ( !applyMod && hasMod ) {
		mods.fastremovebyvalue( modName )
		weapon.SetMods( mods )
	}
}
