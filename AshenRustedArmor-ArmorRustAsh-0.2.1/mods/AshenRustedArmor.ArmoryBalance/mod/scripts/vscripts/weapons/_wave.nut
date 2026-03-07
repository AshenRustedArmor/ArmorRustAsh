
/*		Notes
WeaponAttackWave:
	Args
	+	ent:		waveFunc arg, weapon or projectile
	+	projCt:		waveFunc arg
	+	inflictor:	waveFunc arg
	+	pos:		ground pos @ start
	+	dir:		travel direction
	+	waveFunc:	Continue check, damage handling
	Does
	+	Normalizes dir
	+	Get: stepCt, stepDist, damage, owner
	+	Step dir*stepDist stepCt times
		+	Vortex trace (just dir * stepDist):
			+	drain vortex weapon
			+	drain vortex health
			+	continue
		+	Forward trace (dir*stepDist + small z offset):
			+	ensure hits nothing (no wall)
			+	ensure floor exists
			+	retrieve movingGeo
			+	check waveFunc
			+	advance position
			+	continue
		+	Upwards trace:
			+	hits nothing (wall): break

waveFunc
	Args
	+
	+	movingGeo:	Recievesmoving geometry ent from WeaponAttackWave traces
	Does

*/


//		   :::     :::     :::     ::::    ::: ::::::::::: :::        :::            :::
//		  :+:     :+:   :+: :+:   :+:+:   :+:     :+:     :+:        :+:          :+: :+:
//		 +:+     +:+  +:+   +:+  :+:+:+  +:+     +:+     +:+        +:+         +:+   +:+
//		+#+     +:+ +#++:++#++: +#+ +:+ +#+     +#+     +#+        +#+        +#++:++#++:
//		+#+   +#+  +#+     +#+ +#+  +#+#+#     +#+     +#+        +#+        +#+     +#+
//		#+#+#+#   #+#     #+# #+#   #+#+#     #+#     #+#        #+#        #+#     #+#
//		 ###     ###     ### ###    #### ########### ########## ########## ###     ###

//		Wave attack function
void function WeaponAttackWave(
	entity ent,
	int projectileCount,
	entity inflictor,
	vector pos, vector dir,
	bool functionref( entity, int, entity, entity, vector, vector, int ) waveFunc
) {
	ent.EndSignal( "OnDestroy" )

	entity weapon
	entity projectile
	int maxCount
	float step
	entity owner
	int damageNearValueTitanArmor
	int count = 0
	array<vector> positions = []
	vector lastDownPos
	bool firstTrace = true

	dir = <dir.x, dir.y, 0.0>
	dir = Normalize( dir )
	vector angles = VectorToAngles( dir )

	if( ent.IsProjectile() ) {
		projectile = ent
		string chargedPrefix = ""
		if ( ent.proj.isChargedShot )
			chargedPrefix = "charge_"

		maxCount = expect int( ent.ProjectileGetWeaponInfoFileKeyField( chargedPrefix + "wave_max_count" ) )
		step = expect float( ent.ProjectileGetWeaponInfoFileKeyField( chargedPrefix + "wave_step_dist" ) )
		owner = ent.GetOwner()

		damageNearValueTitanArmor = projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value_titanarmor )
	} else {
		weapon = ent
		maxCount = expect int( ent.GetWeaponInfoFileKeyField( "wave_max_count" ) )
		step = expect float( ent.GetWeaponInfoFileKeyField( "wave_step_dist" ) )
		owner = ent.GetWeaponOwner()

		damageNearValueTitanArmor = weapon.GetWeaponSettingInt( eWeaponVar.damage_near_value_titanarmor )
	}

	owner.EndSignal( "OnDestroy" )

	for ( int i = 0; i < maxCount; i++ ) {
		vector newPos = pos + dir * step

		vector traceStart = pos
		vector traceEndUnder = newPos
		vector traceEndOver = newPos

		if ( !firstTrace ) {
			traceStart = lastDownPos + <0.0, 0.0, 80.0 >
			traceEndUnder = <newPos.x, newPos.y, traceStart.z - 40.0 >
			traceEndOver = <newPos.x, newPos.y, traceStart.z + step * 0.57735056839> // The over height is to cover the case of a sheer surface that then continues gradually upwards (like mp_box)
		}
		firstTrace = false

		VortexBulletHit ornull vortexHit = VortexBulletHitCheck( owner, traceStart, traceEndOver )
		if ( vortexHit ) {
			expect VortexBulletHit( vortexHit )
			entity vortexWeapon = vortexHit.vortex.GetOwnerWeapon()

			if ( vortexWeapon && vortexWeapon.GetWeaponClassName() == "mp_titanweapon_vortex_shield" )
				VortexDrainedByImpact( vortexWeapon, weapon, projectile, null ) // drain the vortex shield
			else if ( IsVortexSphere( vortexHit.vortex ) )
				VortexSphereDrainHealthForDamage( vortexHit.vortex, damageNearValueTitanArmor )

			WaitFrame()
			continue
		}

		//DebugDrawLine( traceStart, traceEndUnder, 0, 255, 0, true, 25.0 )
		array ignoreArray = []
		if ( IsValid( inflictor ) && inflictor.GetOwner() != null )
			ignoreArray.append( inflictor.GetOwner() )

		TraceResults forwardTrace = TraceLine( traceStart, traceEndUnder, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
		if ( forwardTrace.fraction == 1.0 ) {
			//DebugDrawLine( forwardTrace.endPos, forwardTrace.endPos + <0.0, 0.0, -1000.0>, 255, 0, 0, true, 25.0 )
			TraceResults downTrace = TraceLine( forwardTrace.endPos, forwardTrace.endPos + <0.0, 0.0, -1000.0>, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
			if ( downTrace.fraction == 1.0 )
				break

			entity movingGeo = null
			if ( downTrace.hitEnt && downTrace.hitEnt.HasPusherRootParent() && !downTrace.hitEnt.IsMarkedForDeletion() )
				movingGeo = downTrace.hitEnt

			if ( !waveFunc( ent, projectileCount, inflictor, movingGeo, downTrace.endPos, angles, i ) )
				return

			lastDownPos = downTrace.endPos
			pos = forwardTrace.endPos

			WaitFrame()
			continue
		} else {
			bool hitEntIsValid = IsValid( forwardTrace.hitEnt )
			bool hitAmpsWeapon = StatusEffect_Get( forwardTrace.hitEnt, eStatusEffect.pass_through_amps_weapon ) > 0
			bool hitPassesThru = !CheckPassThroughDir( forwardTrace.hitEnt, forwardTrace.surfaceNormal, forwardTrace.endPos )
			if (hitEntIsValid && hitAmpsWeapon && hitPassesThru) break;
		}

		TraceResults upwardTrace = TraceLine( traceStart, traceEndOver, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
		//DebugDrawLine( traceStart, traceEndOver, 0, 0, 255, true, 25.0 )
		if ( upwardTrace.fraction < 1.0 ) {
			if ( IsValid( upwardTrace.hitEnt ) ) {
				if ( upwardTrace.hitEnt.IsWorld() || upwardTrace.hitEnt.IsPlayer() || upwardTrace.hitEnt.IsNPC() )
					break
			}
		} else {
			TraceResults downTrace = TraceLine( upwardTrace.endPos, upwardTrace.endPos + <0.0, 0.0, -1000.0>, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
			if ( downTrace.fraction == 1.0 )
				break

			entity movingGeo = null
			if ( downTrace.hitEnt && downTrace.hitEnt.HasPusherRootParent() && !downTrace.hitEnt.IsMarkedForDeletion() )
				movingGeo = downTrace.hitEnt

			if ( !waveFunc( ent, projectileCount, inflictor, movingGeo, downTrace.endPos, angles, i ) )
				return

			lastDownPos = downTrace.endPos
			pos = forwardTrace.endPos
		}

		WaitFrame()
	}
}

//		     :::    :::  ::::::::      :::      ::::::::  ::::::::::
//		    :+:    :+: :+:    :+:   :+: :+:   :+:    :+: :+:
//		   +:+    +:+ +:+         +:+   +:+  +:+        +:+
//		  +#+    +:+ +#++:++#++ +#++:++#++: :#:        +#++:++#
//		 +#+    +#+        +#+ +#+     +#+ +#+   +#+# +#+
//		#+#    #+# #+#    #+# #+#     #+# #+#    #+# #+#
//		########   ########  ###     ###  ########  ##########

//		Passed functions
//	Flame wall
bool function CreateThermiteWallSegment(
	entity projectile, int projectileCount,
	entity inflictor, entity movingGeo,
	vector pos, vector angles,
	int waveCount
) {
	projectile.SetOrigin( pos )
	entity owner = projectile.GetOwner()

	if ( projectile.proj.savedOrigin != < -999999.0, -999999.0, -999999.0 > ) {
		array<string> mods = projectile.ProjectileGetMods()
		float duration
		int damageSource
		if ( mods.contains( "pas_scorch_flamecore" ) ) {
			damageSource = eDamageSourceId.mp_titancore_flame_wave_secondary
			duration = 1.5
		} else {
			damageSource = eDamageSourceId.mp_titanweapon_flame_wall
			duration = mods.contains( "pas_scorch_firewall" ) ? PAS_SCORCH_FIREWALL_DURATION : FLAME_WALL_THERMITE_DURATION
		}

		if ( IsSingleplayer() ) {
			if ( owner.IsPlayer() || Flag( "SP_MeteorIncreasedDuration" ) ) {
				duration *= SP_FLAME_WALL_DURATION_SCALE
			}
		}

		entity thermiteParticle
		//regular script path
		if ( !movingGeo ) {
			thermiteParticle = CreateThermiteTrail( pos, angles, owner, inflictor, duration, FLAME_WALL_FX, damageSource )
			EffectSetControlPointVector( thermiteParticle, 1, projectile.proj.savedOrigin )
			AI_CreateDangerousArea_Static( thermiteParticle, projectile, METEOR_THERMITE_DAMAGE_RADIUS_DEF, TEAM_INVALID, true, true, pos )
		} else {
			if ( GetMapName() == "sp_s2s" ) {
				angles = <0,90,0>//wind dir
				thermiteParticle = CreateThermiteTrailOnMovingGeo( movingGeo, pos, angles, owner, inflictor, duration, FLAME_WALL_FX_S2S, damageSource )
			} else {
				thermiteParticle = CreateThermiteTrailOnMovingGeo( movingGeo, pos, angles, owner, inflictor, duration, FLAME_WALL_FX, damageSource )
			}

			if ( movingGeo == projectile.proj.savedMovingGeo ) {
				thread EffectUpdateControlPointVectorOnMovingGeo( thermiteParticle, 1, projectile.proj.savedRelativeDelta, projectile.proj.savedMovingGeo )
			} else {
				thread EffectUpdateControlPointVectorOnMovingGeo( thermiteParticle, 1, GetRelativeDelta( pos, movingGeo ), movingGeo )
			}
			AI_CreateDangerousArea( thermiteParticle, projectile, METEOR_THERMITE_DAMAGE_RADIUS_DEF, TEAM_INVALID, true, true )
		}

		//EmitSoundOnEntity( thermiteParticle, FLAME_WALL_GROUND_SFX )
		int maxSegments = expect int( projectile.ProjectileGetWeaponInfoFileKeyField( "wave_max_count" ) )
		//figure out why it's starting at 1 but ending at 14.
		if ( waveCount == 1 )
			EmitSoundOnEntity( thermiteParticle, FLAME_WALL_GROUND_BEGINNING_SFX )
		else if ( waveCount == ( maxSegments - 1 ) )
			EmitSoundOnEntity( thermiteParticle, FLAME_WALL_GROUND_END_SFX )
		else if ( waveCount == maxSegments / 2  )
			EmitSoundOnEntity( thermiteParticle, FLAME_WALL_GROUND_MIDDLE_SFX )
	}

	projectile.proj.savedOrigin = pos
	if ( IsValid( movingGeo ) ) {
		projectile.proj.savedRelativeDelta = GetRelativeDelta( pos, movingGeo )
		projectile.proj.savedMovingGeo = movingGeo
	}

	return true
}

//	Scorch trap
bool function CreateSlowTrapSegment(
	entity projectile, int projectileCount,
	entity inflictor, entity movingGeo,
	vector pos, vector angles,
	int waveCount
) {
	projectile.SetOrigin( pos )
	entity owner = projectile.GetOwner()

	if ( projectile.proj.savedOrigin != < -999999.0, -999999.0, -999999.0 > ) {
		float duration = FLAME_WALL_THERMITE_DURATION

		if ( GAMETYPE == GAMEMODE_SP )
			duration *= SP_FLAME_WALL_DURATION_SCALE

		if ( !movingGeo ) {
			if ( projectileCount in inflictor.e.fireTrapEndPositions )
				inflictor.e.fireTrapEndPositions[projectileCount] = pos
			else
				inflictor.e.fireTrapEndPositions[projectileCount] <- pos

			thread FireTrap_DamageAreaOverTime( owner, inflictor, pos, duration )
		} else {
			vector relativeDelta = GetRelativeDelta( pos, movingGeo )

			if ( projectileCount in inflictor.e.fireTrapEndPositions )
				inflictor.e.fireTrapEndPositions[projectileCount] = relativeDelta
			else
				inflictor.e.fireTrapEndPositions[projectileCount] <- relativeDelta

			if ( projectileCount in inflictor.e.fireTrapMovingGeo )
				inflictor.e.fireTrapMovingGeo[projectileCount] = movingGeo
			else
				inflictor.e.fireTrapMovingGeo[projectileCount] <- movingGeo

			thread FireTrap_DamageAreaOverTimeOnMovingGeo( owner, inflictor, movingGeo, relativeDelta, duration )
		}

	}

	projectile.proj.savedOrigin = pos
	return true
}

//	Flame core
bool function CreateFlameWaveSegment(
	entity projectile, int projectileCount,
	entity inflictor, entity movingGeo,
	vector pos, vector angles,
	int waveCount
) {
	array<string> mods = projectile.ProjectileGetMods()
	projectile.SetOrigin( pos + < 0, 0, 100 > )
	projectile.SetAngles( angles )

	int flags = DF_EXPLOSION | DF_STOPS_TITAN_REGEN | DF_DOOM_FATALITY | DF_SKIP_DAMAGE_PROT

	if( !( waveCount in inflictor.e.waveLinkFXTable ) ) {
		entity waveEffectLeft = StartParticleEffectInWorld_ReturnEntity( GetParticleSystemIndex( FLAMEWAVE_EFFECT_CONTROL ), pos, angles )
		entity waveEffectRight = StartParticleEffectInWorld_ReturnEntity( GetParticleSystemIndex( FLAMEWAVE_EFFECT_CONTROL ), pos, angles )
		EntFireByHandle( waveEffectLeft, "Kill", "", 3.0, null, null )
		EntFireByHandle( waveEffectRight, "Kill", "", 3.0, null, null )
		vector leftOffset = pos + projectile.GetRightVector() * FLAME_WALL_MAX_HEIGHT
		vector rightOffset = pos + projectile.GetRightVector() * -FLAME_WALL_MAX_HEIGHT
		EffectSetControlPointVector( waveEffectLeft, 1, leftOffset )
		EffectSetControlPointVector( waveEffectRight, 1, rightOffset )
		array<entity> rowFxArray = [ waveEffectLeft, waveEffectRight ]
		inflictor.e.waveLinkFXTable[ waveCount ] <- rowFxArray
	} else {
		array<entity> rowFxArray = inflictor.e.waveLinkFXTable[ waveCount ]
		if ( projectileCount == 1 ) {
			foreach( fx in rowFxArray ) {
				fx.SetOrigin( pos )
				fx.SetAngles( angles )
			}
		}
		vector rightOffset = pos + projectile.GetRightVector() * -FLAME_WALL_MAX_HEIGHT
		EffectSetControlPointVector( rowFxArray[1], 1, rightOffset )

		//Catches the case where the middle projectile is destroyed and two outer waves continue forward.
		if ( Distance2D( rowFxArray[1].GetOrigin(), rightOffset ) > PROJECTILE_SEPARATION + FLAME_WALL_MAX_HEIGHT ) {
			rowFxArray[0].SetOrigin( rowFxArray[0].GetOrigin() + rowFxArray[0].GetRightVector() * -FLAME_WALL_MAX_HEIGHT )
			vector leftOffset = pos + projectile.GetRightVector() * FLAME_WALL_MAX_HEIGHT
			rowFxArray[1].SetOrigin( leftOffset )
		}
	}

	// radiusHeight = sqr( FLAME_WALL_MAX_HEIGHT^2 + PROJECTILE_SEPARATION^2 )
	RadiusDamage(
			pos,
			projectile.GetOwner(), //attacker
			inflictor, //inflictor
			projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value ),
			projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value_titanarmor ),
			180, // inner radius
			180, // outer radius
			SF_ENVEXPLOSION_NO_DAMAGEOWNER | SF_ENVEXPLOSION_MASK_BRUSHONLY | SF_ENVEXPLOSION_NO_NPC_SOUND_EVENT,
			0, // distanceFromAttacker
			0, // explosionForce
			flags,
			eDamageSourceId.mp_titancore_flame_wave )

	return true
}

bool function CreateEmpWaveSegment(
	entity projectile, int projectileCount,
	entity inflictor, entity movingGeo,
	vector pos, vector angles,
	int waveCount
) {
	projectile.SetOrigin( pos )

	float damageScalar
	int fxId
	if ( !projectile.proj.isChargedShot ) {
		damageScalar = 1.0
		fxId = GetParticleSystemIndex( $"P_arcwave_exp" )
	} else {
		damageScalar = 1.5
		fxId = GetParticleSystemIndex( $"P_arcwave_exp_charged" )
	}

	StartParticleEffectInWorld( fxId, pos, angles )
	int pilotDamage = int( float( projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value ) ) * damageScalar )
	int titanDamage = int( float( projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value_titanarmor ) ) * damageScalar )

	RadiusDamage(
		pos,
		projectile.GetOwner(), //attacker
		inflictor, //inflictor
		pilotDamage,
		titanDamage,
		112, // inner radius
		112, // outer radius
		SF_ENVEXPLOSION_NO_DAMAGEOWNER | SF_ENVEXPLOSION_MASK_BRUSHONLY | SF_ENVEXPLOSION_NO_NPC_SOUND_EVENT,
		0, // distanceFromAttacker
		0, // explosionForce
		DF_ELECTRICAL | DF_STOPS_TITAN_REGEN,
		eDamageSourceId.mp_titanweapon_arc_wave )

	return true
}