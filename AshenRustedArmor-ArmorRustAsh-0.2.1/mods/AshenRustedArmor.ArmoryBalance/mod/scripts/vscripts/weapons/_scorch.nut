untyped

//		Initialization
//	Funcs
#if SERVER
global function ArmoryFixes_ThermiteTrail
global function ArmoryFixes_ThermiteDamage
global function Scorch_SelfDamageReduction
#endif

//Flamewall
const FLAMEWALL_SPLIT	= false
const FLAMEWALL_RADIUS_DEF	= 60

//	This one has been modified
const float SELFDAMAGE_SCALE_SP = 0.00
const float SELFDAMAGE_SCALE_DEF = 0.00
const float SELFDAMAGE_SCALE_MOD = 0.00

const float MOD_SPEED_BOOST = 0.10
const float MOD_DAMAGE_REDUCTION = 0.15
const float MOD_EFFECT_TIME = 0.2
const float MOD_EFFECT_FADE_TIME = 0.3

#if SERVER
//		Functionality
//	Trail creation
entity function ArmoryFixes_ThermiteTrail(	//	TODO: MOVE THIS!
	vector origin, vector angles,		//
	entity owner, entity inflictor,		//

	float lifetime,

	asset overrideFX	= METEOR_FX_TRAIL,
	int damageSourceId	= eDamageSourceId.mp_titanweapon_meteor_thermite,

	entity parentGeo	= null,
) {
	//		Sanity checks
	//	Owner validity
	Assert( IsValid( owner ) )

	//		Functionality
	int fxID = GetParticleSystemIndex( overrideFX )
	entity functionref( vector, vector ) spawnLambda = entity function( vector p, vector a ) : ( fxID ) {
		return StartParticleEffectInWorld_ReturnEntity( fxID, p, a )
	}

	//	Handle parented case
	array<entity> entsWithLifetime
	if( IsValid(parentGeo) ) {
		entity mover = CreateScriptMover( origin, angles )
		mover.SetParent( parentGeo, "", true, 0 )
		mover.SetOwner( owner )

		entsWithLifetime.append( mover )
		origin = mover.GetLocalOrigin()

		spawnLambda = entity function( vector p, vector a ) : ( fxID, parentGeo ) {
			return StartParticleEffectOnEntityWithPos_ReturnEntity( parentGeo, fxID, FX_PATTACH_CUSTOMORIGIN_FOLLOW, -1, p, a )
		}
	}

	//	Spawn particle
	entity fire = spawnLambda( origin, angles )
	fire.SetOwner( owner )

	entsWithLifetime.append( fire )

	//	Threads / cleanup
	AddActiveThermiteBurn( fire )
	thread ArmoryFixes_ThermiteDamage( fire, owner, inflictor, damageSourceId )

	if( lifetime <= 0.0 ) { return fire }	//	Early return
	foreach( entity e in entsWithLifetime ) {
		if( IsValid(e) ) EntFireByHandle(e, "Kill", "", lifetime, null, null);
	}

	//	Return
	return fire
}

//	Damage
void function ArmoryFixes_ThermiteDamage(
	entity trail, entity owner, entity inflictor,
	int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite,
	float minRadius = METEOR_RADIUS_DEF,
) {
	//		Sanity checks
	//	Owner validity
	Assert( IsValid( owner ) )

	//		Data retrieval
	//	DoT
	float tickDmg_pilot = METEOR_DAMAGE_PLAYER_TICK_PILOT
	float tickDmg_titan = METEOR_DAMAGE_PLAYER_TICK
	if ( owner.IsNPC() ) {
		tickDmg_pilot = METEOR_DAMAGE_NPC_TICK_PILOT
		tickDmg_titan = METEOR_DAMAGE_NPC_TICK
	}

	//		Signaling
	trail.EndSignal( "OnDestroy" )
	owner.EndSignal( "OnDestroy" )
	inflictor.EndSignal( "OnDestroy" )

	array<entity> fxArray
	if( "fxArray" in trail.e ) {
		fxArray.extend(trail.e.fxArray)
	} else {  } //fxArray.append(trail)

	OnThreadEnd( function() : ( fxArray ) {
		foreach ( fx in fxArray ) {
			if ( IsValid( fx ) )
				EffectStop( fx )
		}
	})

	//	Thread
	bool isPhysics = trail.IsProjectile()
	if( isPhysics ) { wait 0.2 }

	vector lastOrigin = trail.GetOrigin()
	for( ;; ) {
		float radius = minRadius

		// spread the circle while the particles are moving fast, could replace with trace
		vector currOrigin = trail.GetOrigin()
		if( isPhysics ) {
			radius = max(minRadius, Length(lastOrigin - currOrigin))
			lastOrigin = currOrigin
		}

		RadiusDamage(
			currOrigin,							// origin
			owner,								// owner
			inflictor,							// inflictor
			tickDmg_pilot,						// pilot damage
			tickDmg_titan,						// heavy armor damage
			radius,								// inner radius
			radius,								// outer radius
			SF_ENVEXPLOSION_NO_NPC_SOUND_EVENT,	// explosion flags
			0, 									// distanceFromAttacker
			0, 									// explosionForce
			DF_EXPLOSION,						// damage flags
			damageSourceId						// damage source id
		)

		WaitFrame()
	}
}

//	Passives
void function Scorch_SelfDamageReduction( entity target, var damageInfo ) {
	//	Sanity checks
	if( !IsAlive(target) ) { return }

	entity attacker = DamageInfo_GetAttacker( damageInfo )
	if( !IsValid(attacker) ) { return }

	if( target != attacker ) { return }

	entity soul = attacker.GetTitanSoul()
	if( !IsValid(soul) ) { return }

	//	Choose damage scale
	float scale = SELFDAMAGE_SCALE_DEF
	if( IsSingleplayer() ) scale = SELFDAMAGE_SCALE_SP;

	//	Thermite effect
	if( SoulHasPassive( soul, ePassives.PAS_SCORCH_SELFDMG ) ) {
		scale = SELFDAMAGE_SCALE_MOD

		print("[ArmoryBalance] mp_titanweapon_meteor: Added status effects")

		//	Add effects
		int speedStatusID = StatusEffect_AddTimed( soul, eStatusEffect.speed_boost, MOD_SPEED_BOOST, MOD_EFFECT_TIME, MOD_EFFECT_FADE_TIME )
		int damageStatusID = StatusEffect_AddTimed( soul, eStatusEffect.damage_reduction, MOD_DAMAGE_REDUCTION, MOD_EFFECT_TIME, MOD_EFFECT_FADE_TIME )

		// TODO Add UI/visual effects
		int cockpitStatusID = StatusEffect_AddTimed( soul, eStatusEffect.stim_visual_effect, 1.0, MOD_EFFECT_TIME, MOD_EFFECT_FADE_TIME ) //cockpitColor, COCKPIT_COLOR_YELLOW
	}

	//	Scale damage
	DamageInfo_ScaleDamage( damageInfo, scale )
}


void function ArmoryBalance_TurboUpdate( entity soul ) {
	//	Index
	if( !("lastBurnTime" in soul.s) ) {
		soul.s.lastBurnTime <- Time()
		thread ArmoryBalance_TurboVFX( soul )
	} else {
		soul.s.lastBurnTime = Time()
	}

	//	S2C Callback
	entity titan = soul.GetTitan()
	if ( IsValid( titan ) && titan.IsPlayer() ) Remote_CallFunction_NonReplay( titan, "S2C_ArmoryBalance_TurboUpdate" );
}
#else
void function S2C_ArmoryBalance_TurboUpdate() {
	//		Sanity checks
	//	Player disembark check
	entity player = GetLocalClientPlayer()
	if( !IsValid( player ) || !player.IsTitan() ) { return }

	//		Functionality
	if( !("lastBurnTime" in player.s) ) {
		player.s.lastBurnTime <- Time()
		thread ArmoryBalance_TurboVFX( player )
	} else {
		player.s.lastBurnTime = Time()
	}
}
#endif

//	Shamelessly plagarized from Dinorush's LTSRebalance code.
//	It works, I hate it, and the more I look at it the more sense it makes.
void function ArmoryBalance_TurboVFX( entity soul ) {
	//	Signaling
	soul.EndSignal( "OnDestroy" )

	//	Data
	float lastTime = 0
	#if SERVER
	entity lastTitan = soul.GetTitan()
	entity chargeFX = null
	#else
	int cockpitID = -1
	#endif

	//	Thread
	for(;;) {
		float currTime = Time()
		float burnTime = expect float( soul.s.lastBurnTime ) - currTime

		bool burnAlive = burnTime > 0
		bool firstTime = lastTime <= 0

		#if SERVER
		entity titan = soul.GetTitan()
		if( burnAlive && ( firstTime || lastTitan != titan ) && IsValid( titan ) ) {
			int index = titan.LookupAttachment( "hijack" )
			chargeFX = StartParticleEffectOnEntity_ReturnEntity( titan,
				GetParticleSystemIndex( $"P_titan_core_atlas_charge" ),
				FX_PATTACH_POINT_FOLLOW, index
			)

			chargeFX.kv.VisibilityFlags = (ENTITY_VISIBLE_TO_FRIENDLY | ENTITY_VISIBLE_TO_ENEMY) // everyone but owner
			chargeFX.SetOwner( titan )
		}
		#else
		if( burnAlive && firstTime ) {
			entity cockpit = soul.GetCockpit()
    		cockpitID = StartParticleEffectOnEntity( cockpit,
				GetParticleSystemIndex( $"P_core_DMG_boost_screen" ),
				FX_PATTACH_ABSORIGIN_FOLLOW, -1
			)
		}
		#endif

		else if( !firstTime && !burnAlive ) {
			#if SERVER
			if( IsValid(chargeFX) ) chargeFX.Destroy();
			#else
			if( EffectDoesExist(cockpitID) ) EffectStop( cockpitID, false, true );
			#endif
		}

		lastTime = burnTime
		#if SERVER
		lastTitan = titan
		#endif

		WaitFrame()
	}
}

void function ArmoryBalance_TurboStatus( entity soul ) {
	//	Signaling
	soul.EndSignal( "OnDestroy" )

	//	Data
	float lastTime = 0

	entity titan = soul.GetTitan() // "Gets the titan for this titanSoul entity" thanks Valve very descriptive

	//	Thread
	int speedStatusID = -1
	int damageStatusID = -1
	int cockpitStatusID = -1
	for(;;) {
		float currTime = Time()
		float burnTime = expect float( soul.s.lastBurnTime ) - currTime

		#if SERVER
		#else
		#endif

		//	Add effects
		speedStatusID = StatusEffect_AddEndless( soul, eStatusEffect.speed_boost, MOD_SPEED_BOOST )
		damageStatusID = StatusEffect_AddEndless( soul, eStatusEffect.damage_reduction, MOD_DAMAGE_REDUCTION )

		//	Add UI/visual effects
		cockpitStatusID = StatusEffect_AddEndless( soul, eStatusEffect.stim_visual_effect, 1.0 ) //cockpitColor, COCKPIT_COLOR_YELLOW
	}
}