global function ArmoryBalance_Equipment_Init
void function ArmoryBalance_Equipment_Init() {
	ArmoryUtil_RegisterMoveItem( "mp_weapon_wingman_n", eItemTypes.PILOT_SECONDARY )
	ArmoryUtil_RegisterMoveItem( "mp_weapon_shotgun_pistol", eItemTypes.PILOT_SECONDARY )
}