//		Initialization
//	Functions
global function MpTitanAbilitySmartCore_Init

global function OnWeaponPrimaryAttack_titancore_siege_mode

//	Consts
const asset SMART_CORE_LASER_SIGHT_FX = $"P_wpn_lasercannon_aim_short"


//	Init
void function MpTitanAbilitySmartCore_Init() {
	PrecacheParticleSystem( SMART_CORE_LASER_SIGHT_FX )

	#if CLIENT
	RegisterSignal( "SmartCoreHUD_End" )
	AddTitanCockpitManagedRUI( SmartCore_CreateHud, SmartCore_DestroyHud, SmartCore_ShouldCreateHud, RUI_DRAW_HUD )
	StatusEffect_RegisterEnabledCallback( eStatusEffect.smartCore, SmartCoreEnabled )
	StatusEffect_RegisterDisabledCallback( eStatusEffect.smartCore, SmartCoreDisabled )
	#endif
}

//	     :::       ::: ::::::::::     :::     :::::::::   ::::::::  ::::    :::
//	    :+:       :+: :+:          :+: :+:   :+:    :+: :+:    :+: :+:+:   :+:
//	   +:+       +:+ +:+         +:+   +:+  +:+    +:+ +:+    +:+ :+:+:+  +:+
//	  +#+  +:+  +#+ +#++:++#   +#++:++#++: +#++:++#+  +#+    +:+ +#+ +:+ +#+
//	 +#+ +#+#+ +#+ +#+        +#+     +#+ +#+        +#+    +#+ +#+  +#+#+#
//	 #+#+# #+#+#  #+#        #+#     #+# #+#        #+#    #+# #+#   #+#+#
//	 ###   ###   ########## ###     ### ###         ########  ###    ####

var function OnWeaponPrimaryAttack_titancore_siege_mode( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	//		Sanity checks
	//	Core is ready
	if ( !CheckCoreAvailable( weapon ) )
		return 0

	//	Titan soul is valid
	entity owner = weapon.GetWeaponOwner()
	entity soul = owner.GetTitanSoul()
	if ( !IsValid( soul ) )
		return 0

	//	Predator cannon is valid
	PredatorCannonData data = GetPredatorCannonData( owner )
	entity minigun = data.weaponPredatorCannon
	if ( !IsValid( minigun ) )
		return 0

	//	Not reloading
	if ( minigun.IsReloading() )
		return 0

	//		Functionality
	OnAbilityCharge_TitanCore( weapon )

	float coreDuration = weapon.GetCoreDuration()

	#if SERVER
	int weaponOwnerTeam = owner.GetTeam()
	array<entity> players = GetPlayerArray()
	foreach( player in players ) {
		if ( player.GetTeam() != weaponOwnerTeam )
			EmitSoundOnEntityOnlyToPlayer( owner, player, "diag_gs_titanLegion_smartCoreUse3p" )
	}

	//thread SmartCoreThread( weapon, coreDuration )
	#endif

	thread SmartCoreThread( weapon, coreDuration )
	OnAbilityStart_TitanCore( weapon )
	//thread SmartCoreFX( weapon, coreDuration )

	return 1
}

//	       :::::::::: :::    ::: ::::    :::  :::::::: ::::::::::: ::::::::::: ::::::::  ::::    :::  ::::::::
//	      :+:        :+:    :+: :+:+:   :+: :+:    :+:    :+:         :+:    :+:    :+: :+:+:   :+: :+:    :+:
//	     +:+        +:+    +:+ :+:+:+  +:+ +:+           +:+         +:+    +:+    +:+ :+:+:+  +:+ +:+
//	    :#::+::#   +#+    +:+ +#+ +:+ +#+ +#+           +#+         +#+    +#+    +:+ +#+ +:+ +#+ +#++:++#++
//	   +#+        +#+    +#+ +#+  +#+#+# +#+           +#+         +#+    +#+    +#+ +#+  +#+#+#        +#+
//	  #+#        #+#    #+# #+#   #+#+# #+#    #+#    #+#         #+#    #+#    #+# #+#   #+#+# #+#    #+#
//	 ###         ########  ###    ####  ########     ###     ########### ########  ###    ####  ########

void function SmartCoreThread( entity weapon, entity owner, float coreDuration ) {
	//	Data retrieval
	entity soul = owner.GetTitanSoul()

	PredatorCannonData data = GetPredatorCannonData( owner )
	entity minigun = expect entity( data.weaponPredatorCannon )

	#if SERVER
	//	SFX
	EmitSoundOnEntityOnlyToPlayer( owner, owner, "Titan_Legion_Smart_Core_Activated_1P" )
	EmitSoundOnEntityOnlyToPlayer( owner, owner, "Titan_Legion_Smart_Core_ActiveLoop_1P" )
	EmitSoundOnEntityExceptToPlayer( owner, owner, "Titan_Legion_Smart_Core_Activated_3P" )

	ArmoryUtil_SetModState( minigun, "AmmoSwap_Smart", true )

	data.damageStatusID = StatusEffect_AddEndless( soul, eStatusEffect.titan_damage_amp, 0.20 )
	if( owner.IsPlayer() ) {
		data.coreStatusID = StatusEffect_AddEndless( owner, eStatusEffect.smartCore, 1.00 ) //StatusEffect_AddTimed( owner, eStatusEffect.smartCore, 1.0, coreDuration, 0.0 )
		AmmoSwap_SetCockpitColor( owner, true )
	}
	#endif

	//	Signaling
	weapon.EndSignal( "OnDestroy" )

	owner.EndSignal( "OnDestroy" )
	owner.EndSignal( "OnDeath" )
	owner.EndSignal( "DisembarkingTitan" )
	owner.EndSignal( "TitanEjectionStarted" )
	owner.EndSignal( "SettingsChanged")

	OnThreadEnd(function() : (weapon, owner, soul, minigun, data) {
			//	SmartCoreFX
			if( IsValid(minigun) ) {
				minigun.StopWeaponEffect( SMART_CORE_LASER_SIGHT_FX, SMART_CORE_LASER_SIGHT_FX )
			}

			#if SERVER
			//	SmartCoreThink
			if( IsValid(owner) ) {
				StopSoundOnEntity( owner, "Titan_Legion_Smart_Core_ActiveLoop_1P" )
				EmitSoundOnEntityOnlyToPlayer( owner, owner, "Titan_Legion_Smart_Core_Deactivated_1P" )

				ArmoryUtil_SetModState( minigun, "AmmoSwap_Smart", false )

				if( owner.IsPlayer() ) {
					AmmoSwap_SetCockpitColor( owner, true )
					StatusEffect_Stop( owner, statusEffectSmartCore )
				}
			}

			if( IsValid(weapon) ) {
				if ( IsValid(owner) )
					CoreDeactivate( owner, weapon )
				OnAbilityChargeEnd_TitanCore( weapon )
			}

			if ( IsValid(soul) ) {
				CleanupCoreEffect(soul)
				StatusEffect_Stop( soul, statusEffect )
			}
			#endif
	}	)

	//	Thread
	float endTime = Time() + coreDuration

	while( !IsPredatorCannonActive( owner, false ) ) { wait 0.1 }

	minigun.PlayWeaponEffectNoCull( SMART_CORE_LASER_SIGHT_FX, SMART_CORE_LASER_SIGHT_FX, "muzzle_flash" )

	wait endTime - Time()

	#if CLIENT
	if ( owner.IsPlayer() ) { TitanCockpit_PlayDialog( owner, "smartCoreOffline" ) }
	#endif
}

#if CLIENT
var function SmartCore_CreateHud() {
	Assert( file.smartCoreHud == null )

	entity player = GetLocalViewPlayer()

	file.smartCoreHud = CreateTitanCockpitRui( $"ui/smart_core.rpak" )
	RuiTrackFloat( file.smartCoreHud, "smartCoreStatus", player, RUI_TRACK_STATUS_EFFECT_SEVERITY, eStatusEffect.smartCore )
	return file.smartCoreHud
}

void function SmartCore_DestroyHud() {
	TitanCockpitDestroyRui( file.smartCoreHud )
	file.smartCoreHud = null
}

bool function SmartCore_ShouldCreateHud() {
	entity player = GetLocalViewPlayer()
	if ( !IsValid( player ) )
		return false

	entity core = player.GetOffhandWeapon( OFFHAND_EQUIPMENT )
	if ( !IsValid( core ) )
		return false

	if ( core.GetWeaponClassName() != "mp_titancore_siege_mode" )
		return false

	return true
}

void function SmartCoreEnabled( entity ent, int statusEffect, bool actuallyChanged ) {
	if ( !IsValid( ent ) )
		return

	if ( ent != GetLocalViewPlayer() )
		return

	thread SmartCore_RuiThink( ent )
}

void function SmartCoreDisabled( entity ent, int statusEffect, bool actuallyChanged ) {
	if ( !IsValid( ent ) )
		return

	if ( ent != GetLocalViewPlayer() )
		return

	ent.Signal( "SmartCoreHUD_End")
}

void function SmartCore_RuiThink( entity player ) {
	player.EndSignal( "SmartCoreHUD_End")

	array<entity> primaryWeapons = GetPrimaryWeapons( player )
	if ( primaryWeapons.len() == 0 )
		return

	OnThreadEnd( function() : ( player ) {
			if ( IsValid( player ) )
				player.p.smartCoreKills = 0
	}	)

	entity weapon = primaryWeapons[ 0 ]
	entity soul = player.GetTitanSoul()

	while ( file.smartCoreHud != null && IsValid( weapon ) ) {
		bool isLocked = false
		if ( weapon.SmartAmmo_IsEnabled() ) {
			var targets = weapon.SmartAmmo_GetTargets()
			foreach ( target in targets ) {
				if ( target.fraction >= 1.0 ) {
					isLocked = true
					break
				}
			}
		}

		RuiSetBool( file.smartCoreHud, "isLocked", isLocked )
		RuiSetString( file.smartCoreHud, "remainingTime", TimeToString( soul.GetCoreChargeExpireTime() - Time(), true, true ) )

		string killCountText = "X " + player.p.smartCoreKills
		RuiSetString( file.smartCoreHud, "killCountText", killCountText )
		RuiSetFloat( file.smartCoreHud, "zoomFrac", player.GetZoomFrac() )
		RuiSetBool( file.smartCoreHud, "hasCloseRangeAmmo", !( weapon.HasMod( "LongRangeAmmo" ) || weapon.HasMod( "LongRangePowerShot" ) ) )

		WaitFrame()
	}
}
#endif
