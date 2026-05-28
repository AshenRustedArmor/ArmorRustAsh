untyped

global function MpTitanweaponMeteor_Init

global function OnWeaponActivate_Meteor
global function OnWeaponDeactivate_Meteor

global function OnWeaponPrimaryAttack_Meteor
#if SERVER
global function OnWeaponNpcPrimaryAttack_Meteor
global function GetMeteorRadiusDamage
#endif // #if SERVER

global function OnProjectileCollision_Meteor

#if CLIENT
const INDICATOR_IMAGE = $"ui/menu/common/locked_icon"
#endif

//	Meteor Launcher
//Damage statistics
global const SP_THERMITE_DURATION_SCALE = 1.25

global const METEOR_DAMAGE_PLAYER_TICK = 100.0
global const METEOR_DAMAGE_PLAYER_TICK_PILOT = 20.0

global const METEOR_DAMAGE_NPC_TICK = 100.0
global const METEOR_DAMAGE_NPC_TICK_PILOT = 20.0

global const METEOR_RADIUS_DEF = 45

global struct MeteorRadiusDamage {
	float pilotDamage
	float heavyArmorDamage
}

const float METEOR_LIFETIME	= 1.2
const int METEOR_DAMAGE_FLAGS = damageTypes.gibBullet | DF_IMPACT | DF_EXPLOSION

//FX
global const METEOR_FX_TRAIL	= $"P_wpn_meteor_exp_trail"
global const METEOR_FX_BASE		= $"P_wpn_meteor_exp"

const METEOR_FX_CHARGED			= $"P_wpn_meteor_exp_amp"
const METEOR_FX_EJECT			= $"models/Weapons/shellejects/shelleject_40mm.mdl"
const METEOR_FX_LOOP			= "Weapon_Sidwinder_Projectile"



//Passive

//	Init
function MpTitanweaponMeteor_Init() {
	PrecacheParticleSystem( $"wpn_mflash_40mm_smoke_side_FP" )
	PrecacheParticleSystem( $"wpn_mflash_40mm_smoke_side" )
	PrecacheParticleSystem( $"P_scope_glint" )

	PrecacheParticleSystem( $"P_team_jet_hover_HLD" )
	PrecacheParticleSystem( $"P_enemy_jet_hover_HLD" )

	PrecacheModel( $"models/dev/empty_physics.mdl" )

	PrecacheParticleSystem( METEOR_FX_TRAIL )
	PrecacheParticleSystem( METEOR_FX_CHARGED )

	#if SERVER
	AddDamageCallbackSourceID( eDamageSourceId.mp_titanweapon_meteor_thermite, MeteorThermite_DamagedTarget )

	PrecacheParticleSystem( THERMITE_GRENADE_FX )
	PrecacheModel( METEOR_FX_EJECT )

	FlagInit( "SP_MeteorIncreasedDuration" )
	FlagSet( "SP_MeteorIncreasedDuration" )
	#endif

	#if CLIENT
	PrecacheMaterial( INDICATOR_IMAGE )
	RegisterSignal( "NewOwner" )
	#endif

	MpTitanweaponFlameWall_Init()
}

//	     :::       ::: ::::::::::     :::     :::::::::   ::::::::  ::::    :::
//	    :+:       :+: :+:          :+: :+:   :+:    :+: :+:    :+: :+:+:   :+:
//	   +:+       +:+ +:+         +:+   +:+  +:+    +:+ +:+    +:+ :+:+:+  +:+
//	  +#+  +:+  +#+ +#++:++#   +#++:++#++: +#++:++#+  +#+    +:+ +#+ +:+ +#+
//	 +#+ +#+#+ +#+ +#+        +#+     +#+ +#+        +#+    +#+ +#+  +#+#+#
//	 #+#+# #+#+#  #+#        #+#     #+# #+#        #+#    #+# #+#   #+#+#
//	 ###   ###   ########## ###     ### ###         ########  ###    ####

void function OnWeaponActivate_Meteor( entity weapon ) {  }
void function OnWeaponDeactivate_Meteor( entity weapon ) {  }

var function OnWeaponPrimaryAttack_Meteor( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	weapon.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )
	return PlayerOrNPCFire_Meteor( attackParams, true, weapon )
}

var function OnWeaponNpcPrimaryAttack_Meteor( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	weapon.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )
	return PlayerOrNPCFire_Meteor( attackParams, false, weapon )
}

int function PlayerOrNPCFire_Meteor( WeaponPrimaryAttackParams attackParams, bool playerFired, entity weapon ) {
	//entity owner = weapon.GetWeaponOwner()
	bool shouldCreateProjectile = false
	if ( IsServer() || weapon.ShouldPredictProjectiles() )
		shouldCreateProjectile = true
	#if CLIENT
	if ( !playerFired )
		shouldCreateProjectile = false
	#endif

	if ( shouldCreateProjectile ) {
		float speed	= 1.0 // 2200.0

 		//TODO:: Calculate better attackParams.dir if auto-titan using mortarShots
		entity bolt = weapon.FireWeaponBolt( attackParams.pos, attackParams.dir, speed, METEOR_DAMAGE_FLAGS, METEOR_DAMAGE_FLAGS, playerFired , 0 )
		if ( bolt != null )
			EmitSoundOnEntity( bolt, "weapon_thermitelauncher_projectile_3p" )
	}

	return 1
}

/*
void function MeteorAirburst( entity bolt ) {
	bolt.EndSignal( "OnDestroy" )
	bolt.GetOwner().EndSignal( "OnDestroy" )
	wait METEOR_LIFETIME
	thread Proto_MeteorCreatesThermite( bolt )
	bolt.Destroy()
} //*/

void function OnProjectileCollision_Meteor(
	entity projectile,
	vector pos, vector normal,
	entity hitEnt, int hitbox,
	bool isCritical
) {
	#if SERVER
	if ( projectile.proj.projectileBounceCount > 0 )
		return

	projectile.proj.projectileBounceCount++

	entity owner = projectile.GetOwner()
	if ( !IsValid( owner ) )
		return

	thread Proto_MeteorCreatesThermite( projectile, hitEnt )
	#endif
}

//	       :::::::::: :::    ::: ::::    :::  :::::::: ::::::::::: ::::::::::: ::::::::  ::::    :::  ::::::::
//	      :+:        :+:    :+: :+:+:   :+: :+:    :+:    :+:         :+:    :+:    :+: :+:+:   :+: :+:    :+:
//	     +:+        +:+    +:+ :+:+:+  +:+ +:+           +:+         +:+    +:+    +:+ :+:+:+  +:+ +:+
//	    :#::+::#   +#+    +:+ +#+ +:+ +#+ +#+           +#+         +#+    +#+    +:+ +#+ +:+ +#+ +#++:++#++
//	   +#+        +#+    +#+ +#+  +#+#+# +#+           +#+         +#+    +#+    +#+ +#+  +#+#+#        +#+
//	  #+#        #+#    #+# #+#   #+#+# #+#    #+#    #+#         #+#    #+#    #+# #+#   #+#+# #+#    #+#
//	 ###         ########  ###    ####  ########     ###     ########### ########  ###    ####  ########

#if SERVER
//		Fire creation
int ANGLE_RANGE = 360
function Proto_MeteorCreatesThermite( entity projectile, entity hitEnt = null ) {
	//	Get owner
	entity owner = projectile.GetOwner()
	Assert( IsValid( owner ) )

	//	Set fire speed from parent
	vector projVel = projectile.GetVelocity()
	float speed = min( Length( projVel ), 2500 )

	float speedScale = 0.25
	if ( IsSingleplayer() ) {
		speedScale = 0.35
	}

	projVel = Normalize( projVel ) * speed * speedScale

	vector normal = <0,0,1>

	vector origin = projectile.GetOrigin()
	vector angles = VectorToAngles( normal )

	//DebugDrawLine( origin, origin + projVel * 10, 255, 0, 0, true, 5.0 )
	//EmitSoundAtPosition( owner.GetTeam(), origin, "Explo_MeteorGun_Impact_3P" )

	//	Get fire information
	float thermiteLifetimeMin = 2.0
	float thermiteLifetimeMax = 2.5
	if ( IsSingleplayer() ) {
		if ( owner.IsPlayer() || Flag( "SP_MeteorIncreasedDuration" ) ) {
			thermiteLifetimeMin *= SP_THERMITE_DURATION_SCALE
			thermiteLifetimeMax *= SP_THERMITE_DURATION_SCALE
		}
	}

	//	Create inflictor
	entity inflictor = CreateOncePerTickDamageInflictorHelper( thermiteLifetimeMax )

	//	Get fire counts
	int fireCount = 4
	float fireSpeed = 50

	array<string> mods = projectile.ProjectileGetMods()
	if ( mods.contains( "pas_scorch_weapon" ) ) {
		fireCount = 8
		fireSpeed = 200
	}

	//	Spawn fires
	vector fireVel = projVel
	float fireTime = thermiteLifetimeMax
	for (int i = 0; i < fireCount+1; i++ ) {
		//	Spawn fire first, then change variables
		entity fire = CreatePhysicsThermiteTrail(
			origin, fireVel, fireTime,
			owner, inflictor, projectile
		)

		fire.SetAngles( angles )

		//	First ent stick
		if ( i == 0 && hitEnt != null && hitEnt.IsWorld() )
			fire.StopPhysics()

		//	Random angles/velocity
		angles = Vector(
			RandomFloatRange(-ANGLE_RANGE, ANGLE_RANGE),
			RandomFloatRange(-ANGLE_RANGE, ANGLE_RANGE),
			RandomFloatRange(-ANGLE_RANGE, ANGLE_RANGE)
		)

		vector fwd = AnglesToForward( angles )
		vector up = AnglesToUp( angles )
		fireVel = projVel + (fwd + up) * fireSpeed
	}
}

entity function CreatePhysicsThermiteTrail(
	vector origin, vector velocity, float lifetime,
	entity owner, entity inflictor, entity projectile,
	//	Actually utilizing these nice defaults`
	asset overrideFX = METEOR_FX_TRAIL,
	int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite
) {
	//	Sanity checks
	Assert( IsValid( owner ) )

	//		Physics-enabled props
	//	Create
	entity fire = CreateEntity( "prop_physics" )
	fire.SetOwner( owner )

	//	Render
	fire.SetValueForModelKey( $"models/dev/empty_physics.mdl" )
	fire.kv.fadedist = 2000
	fire.kv.renderamt = 255
	fire.kv.rendercolor = "255 255 255"
	fire.Hide()

	fire.kv.minhealthdmg = 9999
	fire.kv.nodamageforces = 1
	fire.kv.inertiaScale = 1.0

	//	Physics
	fire.kv.CollisionGroup = TRACE_COLLISION_GROUP_DEBRIS
	fire.kv.spawnflags = 4 /* SF_PHYSPROP_DEBRIS */
	fire.SetOrigin( origin )

	DispatchSpawn( fire )

	//	PFX
	entity fx = StartParticleEffectOnEntity_ReturnEntity( fire,
		GetParticleSystemIndex( overrideFX ),
		FX_PATTACH_POINT_FOLLOW_NOROTATE,
		fire.LookupAttachment( "origin" )
	)

	fx.SetOwner( owner )
	fire.e.fxArray.append( fx )
	AddActiveThermiteBurn( fx )

	fire.SetVelocity( velocity )

	//	Lifetime / time before kill
	if( lifetime > 0 ) { EntFireByHandle( fire, "Kill", "", lifetime, null, null ) }

	//	AI
	AI_CreateDangerousArea( fire, projectile, METEOR_RADIUS_DEF, TEAM_INVALID, true, false )

	//	Damage
	thread ArmoryFixes_ThermiteDamage( fire, owner, inflictor, damageSourceId )

	return fire
}

MeteorRadiusDamage function GetMeteorRadiusDamage( entity owner ) {
	MeteorRadiusDamage meteorRadiusDamage
	if ( owner.IsNPC() ) {
		meteorRadiusDamage.pilotDamage = METEOR_DAMAGE_NPC_TICK_PILOT
		meteorRadiusDamage.heavyArmorDamage = METEOR_DAMAGE_NPC_TICK
	} else {
		meteorRadiusDamage.pilotDamage = METEOR_DAMAGE_PLAYER_TICK_PILOT
		meteorRadiusDamage.heavyArmorDamage = METEOR_DAMAGE_PLAYER_TICK
	}

	return meteorRadiusDamage
}

void function MeteorThermite_DamagedTarget( entity target, var damageInfo ) {
	//	Sanity checks
	if( !IsValid( target ) )
		return

	//
	Thermite_DamagePlayerOrNPCSounds( target )
	Scorch_SelfDamageReduction( target, damageInfo )

	entity attacker = DamageInfo_GetAttacker( damageInfo )
	if ( !IsValid( attacker ) || attacker.GetTeam() == target.GetTeam() )
		return

	array<entity> weapons = attacker.GetMainWeapons()
	if ( weapons.len() > 0 ) {
		if ( weapons[0].HasMod( "fd_fire_damage_upgrade" )  )
			DamageInfo_ScaleDamage( damageInfo, FD_FIRE_DAMAGE_SCALE )
		if ( weapons[0].HasMod( "fd_hot_streak" ) )
			UpdateScorchHotStreakCoreMeter( attacker, DamageInfo_GetDamage( damageInfo ) )
	}
}
#endif