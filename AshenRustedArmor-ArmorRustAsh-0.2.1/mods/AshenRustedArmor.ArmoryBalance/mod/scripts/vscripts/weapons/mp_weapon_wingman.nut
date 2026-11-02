global function OnWeaponPrimaryAttack_weapon_wingman
#if SERVER
global function OnWeaponNpcPrimaryAttack_weapon_wingman
#endif

var function OnWeaponPrimaryAttack_weapon_wingman( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	return PlayerOrNpcFire_Wingman( weapon, attackParams, false )
}
#if SERVER
var function OnWeaponNpcPrimaryAttack_weapon_wingman( entity weapon, WeaponPrimaryAttackParams attackParams ) {
	return PlayerOrNpcFire_Wingman( weapon, attackParams, false )
}
#endif

int function PlayerOrNpcFire_Wingman( entity weapon, WeaponPrimaryAttackParams attackParams, bool playerFired ) {
	weapon.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )
	ShotgunBlast( weapon, attackParams.pos, attackParams.dir, 1, weapon.GetWeaponDamageFlags() )

	//	Ammo cost
	return weapon.GetAmmoPerShot()
}