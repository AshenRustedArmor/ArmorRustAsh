
/*		Notes
WeaponAttackWave:
	Args
	+	ent:		waveFunc arg, weapon or projectile
	+	projNum:	waveFunc arg
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
			+	retrieve movingGeo
			+	check waveFunc
			+	advance position
			+	continue

waveFunc
	Args
	+	proj:		Control point for FX & AI behavior, source of damage information
	+	projNum:	Projectile ID by number.
	+	inflictor:	Damage inflictor object,
	+	movingGeo:	Recieves moving geometry ent from WeaponAttackWave traces
	+	pos:		Segment position.
	+	ang:		Segment angles.
	+	waveNum:	Wave ID by number.
	Does
	+	Check for valid origin (do nothing)
	+	Get damage, including mods
	+	Start FX
*/

table< int, WaveAttackData > WaveAttacks
struct WaveAttackData {
	int waveID

	//		Damage-related data
	entity weapon
	entity attacker
	int damageSourceId

	//		Positional data
	vector origin
	vector angles
	float offset

	//		Geometric data
//	float range		//	Max traversed distance
//	float speed		//	Traversal speed
//	float spacing	//	Minimum node-to-node dist

	float stepDist	//	stepDist = range / ceil(range / spacing)
	float stepTime	//	stepTime = 0.1*max(1, floor(10*stepDist/speed + 0.5))

	float arcAngle	//	Wavefront swept angle (0 for flat)
	float arcWidth	//	Wavefront width (end-to-end for arcs)

	//		Function references
	bool functionref( WaveNode, vector, entity ) onWaveNodeCheck
	void functionref( WaveNode, vector, entity ) onWaveNodeSpawn
}

struct WaveFrontData {
	int				count = 0
	array<bool>		cleanup

	array<int>		waveID
	array<int>		frontID

	//	Position/location
	array<vector>	origin
	array<vector>	direction
	array<float>	distance

	//	Wave geometry
	array<float>	boundL
	array<float>	boundR
	array<bool>		isArc	//	bounds must be in degrees if arc

	//	Killcams
	array<entity>	inflictor
	array<bool>		ownsMover

	//	Timing
	array<float>	nextTime
} fronts

const int MAX_TRACE_JOBS = 1024
struct WaveTraceJobs {
	int count = 0

	array<int>		waveID	= array<int>	(MAX_TRACE_JOBS, 0)
	array<int>		frontID	= array<int>	(MAX_TRACE_JOBS, 0)
	array<bool>		occlude	= array<bool>	(MAX_TRACE_JOBS, false)

	array<float>	offset	= array<float>	(MAX_TRACE_JOBS, 0.)
	array<vector>	fwdDir	= array<vector>	(MAX_TRACE_JOBS, <0,0,0>)

	array<vector>	oldPos	= array<vector>	(MAX_TRACE_JOBS, <0,0,0>)
	array<vector>	newPos	= array<vector>	(MAX_TRACE_JOBS, <0,0,0>)
} jobs

/*	Front Propogation Algorithm
Description:
	The list of nodes is recorded as their arclength offsets (regular distance
	if flat) from the center. Compute the arclength of each curve, working in
	the modulus of the arclength, offset so zero is at the center. A node steps
	from its initial position (d_1, x_1) to (d_2, x_1 \pm NodeDist) (half for
	the first step); we know there will be extra space off to one side, so the
	algorithm can check the modulo distance between the first and last node and
	add a node in the center if there's space.

	Simply divide the signed arclength from the center by the current radius or
	range to get the angle, then take -dir rotated by this angle (or maybe dir
	rotated by negative angle?) to find the "previous" position.

	Rather than storing the node positions, the algorithm can simply store the
	occluded positions (if the occlusion range is known). Node positions can be
	"bricklayed" with each subsequent wavefront, excluding positions within the
	occlusion range of a recorded obstacle.

Node Placement:
	Inputs:
	+	Origin:		vector
	+	Distance:	float
	+	Direction:	vector
	+	Z offset:	float, but pack above
	+	Bounds:		float[2]
Angular bounds for arcs is easier to handle, no updating arclength

max range:	offset + range	- multiply by ceil(timestep) / timestep
timestep:	range / speed	- round to integer number of ticks
*/

void function WaveECS_MakeTraceJobs( float currTime ) {
	for (int i = 0; i < fronts.count; i++) {
		//		Sanity checks
		//	Non-initialized
		if (fronts.parentID[i] == 0) continue;
		int parentID = fronts.parentID[i]

		//	Paren't
		WaveAttackData parent
		if (!(parentID in WaveAttacks)) {
			fronts.cleanup[i] = true;
		} else { parent = WaveAttacks[parentID] }

		//	Should delete
		if (fronts.cleanup[i]) continue;

		//	Timing
		float nextTime = fronts.nextTime[i]
		if (currTime < nextTime) continue;
		//fronts.nextTime = currTime + parent.stepTime;

		//		Functionality
		//	Get and clamp bounds
		float oldDist = fronts.distance[i]
		float newDist = oldDist + parent.stepDist
		fronts.distance[i] = newDist

		float boundL = fronts.boundL[i]
		float boundR = fronts.boundR[i]

		vector bounds = Vector(boundL, boundR, boundR - boundL)
		if( fronts.isArc[i] ) {
			bounds *= DEG_TO_RAD
			bounds *= newDist
		}

		bounds += <0.5, -0.5, 1> * parent.spacing

		//	Find node positions
		int nodeCount = floor(bounds.z / parent.spacing) + 1
		array<float> range = ArmoryUtil_Range( bounds.x, bounds.y, nodeCount ) // TODO rename variable

		vector origin = fronts.origin[i]
		vector baseDir = fronts.direction[i]
		vector angles = VectorToAngles( baseDir )

		int jobID = jobs.count
		frontJobs[ fronts.frontID[i] ] = jobID
		if( isArc ) {
			foreach (float r in range) {
				vector fwd = AnglesToVector(angles + <0, r, 0>)

				//	Create job
				jobs.waveID[jobID] = fronts.waveID[i]
				jobs.frontID[jobID] = fronts.frontID[i]
				jobs.occlude[jobID] = false

				jobs.offset[jobID] = r
				jobs.fwdDir[jobID] = fwd

				jobs.oldPos[jobID] = origin + (fwd * oldDist)
				jobs.newPos[jobID] = origin + (fwd * newDist)

				jobID ++
			}
		} else {
			vector right = CrossProduct( baseDir, <0, 0, 1> )
			vector oldCenter = baseDir * oldDist
			vector newCenter = baseDir * newDist
			foreach (float r in range) {
				//	Create job
				jobs.waveID[jobID] = fronts.waveID[i]
				jobs.frontID[jobID] = fronts.frontID[i]
				jobs.occlude[jobID] = false

				jobs.offset[jobID] = r
				jobs.fwdDir[jobID] = baseDir

				vector offset = right * r
				jobs.oldPos[jobID] = origin + oldCenter + offset
				jobs.newPos[jobID] = origin + newCenter + offset

				jobID ++
			}
		}
		jobs.count = jobID
	}
}

void function WaveECS_ProcessTraceJobs( float currTime ) {
	for (int i = 0; i < fronts.count; i++) {

	}
}






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
		eDamageSourceId.mp_titancore_flame_wave
	)

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
		eDamageSourceId.mp_titanweapon_arc_wave
	)

	return true
}