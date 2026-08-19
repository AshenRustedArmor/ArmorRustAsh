void function InitItems()
{
	file.unlocks = {}
	file.entitlementUnlocks = {}

	file.allItems = []
	file.itemRefToGuid = {}
	file.guidToItemRef = {}
	file.guidToItemRef[ 0 ] <- "reserved"

	file.itemData = {}
	file.itemsOfType = {}

	file.displayDataCache = {}

	for ( int i = 0; i < eItemTypes.COUNT; i++ )
	{
		file.itemsOfType[ i ] <- []
		file.globalItemRefsOfType[ i ] = []
	}

	#if SERVER
		AddClientCommandCallback( "BuyItem", ClientCommand_BuyItem )
		AddClientCommandCallback( "BuyTicket", ClientCommand_BuyTicket )
		AddClientCommandCallback( "ClearNewStatus", ClientCommand_ClearNewStatus )
		AddClientCommandCallback( "UseDoubleXP", ClientCommand_UseDoubleXP )
		AddClientCommandCallback( "DEV_GiveFDUnlockPoint", ClientCommand_DEV_GiveFDUnlockPoint )
		AddClientCommandCallback( "DEV_ResetTitanProgression", ClientCommand_DEV_ResetTitanProgression )
	#endif

	#if UI
		uiGlobal.itemsInitialized = true
	#endif

	#if CLIENT
		ClearItemTypes()
	#endif

	if ( IsSingleplayer() )
	{
		InitTitanWeaponDataSP()
		return
	}

	#if DEV
		// Updated with DLC 4
		ValidateDataTableCRC( $"datatable/burn_meter_rewards.rpak", 13, -195196861 )
		ValidateDataTableCRC( $"datatable/calling_cards.rpak", 379, -93927632 )
		ValidateDataTableCRC( $"datatable/callsign_icons.rpak", 167, 2015621078 )
		ValidateDataTableCRC( $"datatable/camo_skins.rpak", 140, -320502469 )
		ValidateDataTableCRC( $"datatable/faction_leaders.rpak", 7, -686839648 )
		ValidateDataTableCRC( $"datatable/features_mp.rpak", 18, 1879135085 )
		ValidateDataTableCRC( $"datatable/pilot_abilities.rpak", 15, 2112045689 )
		ValidateDataTableCRC( $"datatable/pilot_executions.rpak", 10, 1341275658 )
		ValidateDataTableCRC( $"datatable/pilot_passives.rpak", 8, 981112716 )
		ValidateDataTableCRC( $"datatable/pilot_properties.rpak", 7, -1114320894 )
		ValidateDataTableCRC( $"datatable/pilot_weapon_features.rpak", 4, 439636371 )
		ValidateDataTableCRC( $"datatable/pilot_weapon_mods.rpak", 249, 2010060417 )
		ValidateDataTableCRC( $"datatable/pilot_weapon_mods_common.rpak", 25, -761470088 )
		ValidateDataTableCRC( $"datatable/pilot_weapons.rpak", 32, 1625188373 )
		ValidateDataTableCRC( $"datatable/playlist_items.rpak", 19, -1360623070 )
		ValidateDataTableCRC( $"datatable/titan_nose_art.rpak", 150, 1922555441 )
		ValidateDataTableCRC( $"datatable/titan_passives.rpak", 51, 1139205682 )
		ValidateDataTableCRC( $"datatable/titan_primary_mods.rpak", 0, 0 )
		ValidateDataTableCRC( $"datatable/titan_primary_mods_common.rpak", 0, 0 )
		ValidateDataTableCRC( $"datatable/titan_properties.rpak", 8, -1270130815 )
		ValidateDataTableCRC( $"datatable/titan_skins.rpak", 42, 1057626784 )
		ValidateDataTableCRC( $"datatable/titan_voices.rpak", 8, -1605184394 )
		ValidateDataTableCRC( $"datatable/titans_mp.rpak", 7, 420442720 )
	#endif

	var dataTable
	int numRows

	// ==========================================================
	//					Armory Registry Pipeline
	// ==========================================================
	RegistryPipelineInit()

	// //////////////////
	// CAMO SKINS DATA
	// //////////////////
	// CreateBaseItemData( eItemTypes.FEATURE, "no_item", true )

	dataTable = GetDataTable( $"datatable/camo_skins.rpak" )
	table<int, int> categoryCounts = {}
	for ( int row = 0; row < GetDatatableRowCount( dataTable ); row++ )
	{
		string camoRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_REF_COLUMN_NAME ) )
		string pilotCamoRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_PILOT_REF_COLUMN_NAME ) )
		string titanCamoRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_TITAN_REF_COLUMN_NAME ) )
		asset image = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_IMAGE_COLUMN_NAME ) )
		string name = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_NAME_COLUMN_NAME ) )
		string desc = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_DESCRIPTION_COLUMN_NAME ) )
		int pilotCost = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_PILOT_COST_COLUMN_NAME ) )
		int categoryId = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, CAMO_CATEGORY_COLUMN_NAME ) )

		if ( !( categoryId in categoryCounts ) )
			categoryCounts[ categoryId ] <- 0

		categoryCounts[ categoryId ]++

		int datatableIndex = row

		const bool IS_HIDDEN_ARG = false

		ItemData item
		item = CreateGenericItem( datatableIndex, eItemTypes.CAMO_SKIN_PILOT, pilotCamoRef, name, desc, desc, image, pilotCost, IS_HIDDEN_ARG )
		item.imageAtlas = IMAGE_ATLAS_CAMO
		item.i.categoryId <- categoryId

		item = CreateGenericItem( datatableIndex, eItemTypes.CAMO_SKIN_TITAN, titanCamoRef, name, desc, desc, image, 0, IS_HIDDEN_ARG )
		item.imageAtlas = IMAGE_ATLAS_CAMO
		item.i.categoryId <- categoryId

		item = CreateGenericItem( datatableIndex, eItemTypes.CAMO_SKIN, camoRef, name, desc, desc, image, 0, IS_HIDDEN_ARG )
		item.imageAtlas = IMAGE_ATLAS_CAMO
		item.i.categoryId <- categoryId
	}

	InitTitanWeaponDataMP()

	// //////////////////
	// PILOT WEAPON DATA
	// //////////////////

	dataTable = GetDataTable( $"datatable/pilot_weapons.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string itemRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "itemRef" ) )
		int itemType = eItemTypes[ GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) ) ]
		bool hidden = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "hidden" ) )
		string xpPerLevelType = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "xpPerLevelType" ) )
		int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )
		WeaponSetXPPerLevelType( itemRef, xpPerLevelType )

		CreateWeaponData( i, itemType, hidden, itemRef, true, cost )

		var camoSkinsDataTable = GetDataTable( $"datatable/camo_skins.rpak" )
		for ( int camoRow = 0; camoRow < GetDatatableRowCount( camoSkinsDataTable ); camoRow++ )
		{
			string camoRef = GetDataTableString( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_REF_COLUMN_NAME ) )
			int weaponCamoCost = GetDataTableInt( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_PILOT_WEAPON_COST_COLUMN_NAME ) )
			int categoryId = GetDataTableInt( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_CATEGORY_COLUMN_NAME ) )

			CreateGenericSubItemData( eItemTypes.CAMO_SKIN, itemRef, camoRef, weaponCamoCost, { categoryId = categoryId } )
		}
	}

	SetupWeaponSkinData()

	// Registry_RPakJob( $"datatable/pilot_abilities.rpak", ArmoryUtils_ClosureBox(CreateWeaponData), {
	// 	ref="itemRef"})

	//	SCRIPT ERROR: [UI] The index "mp_ability_grapple" does not exist
	// Registry_InferFunction(ArmoryUtils_ClosureBox(CreateWeaponData), eTaskType.FACTORY, "vanilla_pilot_abilities")
	// Registry_InferRPakData( "vanilla_pilot_abilities", $"datatable/pilot_abilities.rpak", { ref = "itemRef" })

	dataTable = GetDataTable( $"datatable/pilot_abilities.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string itemRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "itemRef" ) )
		int itemType = eItemTypes[ GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) ) ]
		bool isDamageSource = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "damageSource" ) )
		bool hidden = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "hidden" ) )
		int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

		CreateWeaponData( i, itemType, hidden, itemRef, isDamageSource, cost )
	}

	// //////////////////////
	// PILOT MODS/ATTACHMENTS
	// //////////////////////

	dataTable = GetDataTable( $"datatable/pilot_weapon_mods_common.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	table<string, modCommonDef> modCommonTable

	for ( int i = 0; i < numRows; i++ )
	{
		modCommonDef modCommon
		modCommon.modType = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_COMMON_TYPE_COLUMN )
		Assert( modCommon.modType == "attachment" || modCommon.modType == "mod" || modCommon.modType == "mod3" )

		modCommon.name = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_COMMON_NAME_COLUMN )
		modCommon.description = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_COMMON_DESCRIPTION_COLUMN )
		modCommon.image = GetDataTableAsset( dataTable, i, PILOT_WEAPON_MOD_COMMON_IMAGE_COLUMN )
		modCommon.cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )
		modCommon.costSniper = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "costSniper" ) )
		modCommon.costPistol = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "costPistol" ) )
		modCommon.costAT = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "costAT" ) )

		modCommon.dataTableIndex = i

		string itemRef = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_COMMON_COLUMN )
		modCommonTable[ itemRef ] <- modCommon

		ItemData modCommonData
		if ( modCommon.modType == "attachment" )
			modCommonData = CreateBaseItemData( eItemTypes.SUB_PILOT_WEAPON_ATTACHMENT, itemRef, false )
		else
			modCommonData = CreateBaseItemData( eItemTypes.SUB_PILOT_WEAPON_MOD, itemRef, false )

		modCommonData.name = modCommon.name
		modCommonData.longname = modCommon.name
		modCommonData.desc = modCommon.description
		modCommonData.image = modCommon.image
		modCommonData.persistenceId = modCommon.dataTableIndex
		modCommonData.imageAtlas = IMAGE_ATLAS_MENU
	}

	dataTable = GetDataTable( $"datatable/pilot_weapon_mods.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	var weaponTable = GetDataTable( $"datatable/pilot_weapons.rpak" )
	for ( int i = 0; i < numRows; i++ )
	{
		string mod = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_COLUMN )
		string weapon = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_WEAPON_COLUMN )
		bool hidden = GetDataTableBool( dataTable, i, PILOT_WEAPON_MOD_HIDDEN_COLUMN )

		int typeRow = GetDataTableRowMatchingStringValue( weaponTable, GetDataTableColumnByName( weaponTable, "itemRef" ), weapon )
		int weaponType = eItemTypes[ GetDataTableString( weaponTable, typeRow, GetDataTableColumnByName( weaponTable, "type" ) ) ]

		int cost
		string xpPerLevelType = GetDataTableString( weaponTable, typeRow, GetDataTableColumnByName( weaponTable, "xpPerLevelType" ) )
		switch ( xpPerLevelType )
		{
			case "sniper":
				cost = modCommonTable[ mod ].costSniper
				break

			case "pistol":
				cost = modCommonTable[ mod ].costPistol
				break

			case "antititan":
				cost = modCommonTable[ mod ].costAT
				break

			default:
				cost = modCommonTable[ mod ].cost
		}

		if ( modCommonTable[ mod ].modType == "attachment" )
		{
			Assert( weaponType == eItemTypes.PILOT_PRIMARY )

			CreateModData( eItemTypes.PILOT_PRIMARY_ATTACHMENT, weapon, mod, cost )
		}
		else if ( modCommonTable[ mod ].modType == "mod" )
		{
			Assert( weaponType == eItemTypes.PILOT_PRIMARY || weaponType == eItemTypes.PILOT_SECONDARY )
			int itemType = weaponType == eItemTypes.PILOT_PRIMARY ? eItemTypes.PILOT_PRIMARY_MOD : eItemTypes.PILOT_SECONDARY_MOD

			int damageDisplay = GetDataTableInt( dataTable, i, PILOT_WEAPON_MOD_DAMAGEDISPLAY_COLUMN )
			int accuracyDisplay = GetDataTableInt( dataTable, i, PILOT_WEAPON_MOD_ACCURACYDISPLAY_COLUMN )
			int rangeDisplay = GetDataTableInt( dataTable, i, PILOT_WEAPON_MOD_RANGEDISPLAY_COLUMN )
			int fireRateDisplay = GetDataTableInt( dataTable, i, PILOT_WEAPON_MOD_FIRERATEDISPLAY_COLUMN )
			int clipSizeDisplay = GetDataTableInt( dataTable, i, PILOT_WEAPON_MOD_CLIPSIZEDISPLAY_COLUMN )

			CreateModData( itemType, weapon, mod, cost, damageDisplay, accuracyDisplay, rangeDisplay, fireRateDisplay, clipSizeDisplay )
		}
		else
		{
			Assert( modCommonTable[ mod ].modType == "mod3" )
			CreateModData( eItemTypes.PILOT_WEAPON_MOD3, weapon, mod, cost )
		}
	}


	/// //////////////////
	/// PILOT PASSIVE DATA
	/// //////////////////
	// Registry_RPakJob( $"datatable/pilot_passives.rpak", ArmoryUtils_ClosureBox(CreatePassiveData), {
	// 	ref="passive" })

	Registry_InferFunction( ArmoryUtils_ClosureBox(CreatePassiveData), eTaskType.FACTORY, "vanilla_pilot_passives" )
	Registry_InferRPakData( "vanilla_pilot_passives", $"datatable/pilot_passives.rpak", { ref = "passive" } )

	// dataTable = GetDataTable( $"datatable/pilot_passives.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string itemRef      = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "passive" ) )
	// 	int itemType        = eItemTypes[ GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) ) ]
	// 	string name			= GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "name" ) )
	// 	string description	= GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "description" ) )
	// 	asset image			= GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "image" ) )
	// 	bool hidden			= GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "hidden" ) )
	// 	int cost			= GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

	// 	CreatePassiveData( i, itemType, hidden, itemRef, name, description, description, image, cost )
	// }

	/// //////////////////
	/// SUIT DATA
	/// //////////////////

	// Suits
	// Registry_RPakJob( $"datatable/pilot_properties.rpak", ArmoryUtils_ClosureBox(CreatePilotSuitData), {
	// 	ref="type", itemType=eItemTypes.PILOT_SUIT })

	//	SCRIPT ERROR: [SERVER] The index "grapple" does not exist
	// Registry_InferFunction(ArmoryUtils_ClosureBox(CreatePassiveData), eTaskType.FACTORY, "vanilla_pilot_suits")
	// Registry_InferRPakData( "vanilla_pilot_suits", $"datatable/pilot_passives.rpak", {
	// 	ref = "type", itemType = eItemTypes.PILOT_SUIT
	// })

	CreateBaseItemData( eItemTypes.RACE, "race_human_male", false )
	CreateBaseItemData( eItemTypes.RACE, "race_human_female", false )

	dataTable = GetDataTable( $"datatable/pilot_properties.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string itemRef	= GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) )
		asset image		= GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "image" ) )
		int cost		= GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

		CreatePilotSuitData( i, eItemTypes.PILOT_SUIT, itemRef, image, cost )
	}



	//	Executions
	var FilterDisabledRef = ArmoryUtils_ClosureBox(table function( string ref ) {
		return { ref = IsDisabledRef(ref) ? "PIPELINE_SKIP" : ref }
	})

	Registry_InferFunction(ArmoryUtils_ClosureBox(CreatePassiveData), eTaskType.FACTORY, "vanilla_pilot_taunts")
	Registry_InferFunction(FilterDisabledRef, eTaskType.MUTATOR, "vanilla_pilot_taunts")
	Registry_InferRPakData("vanilla_pilot_taunts", $"datatable/pilot_executions.rpak", {
		itemType = eItemTypes.PILOT_EXECUTION
	})

	Registry_InferFunction(ArmoryUtils_ClosureBox(CreatePassiveData), eTaskType.FACTORY, "vanilla_titan_taunts")
	Registry_InferFunction(FilterDisabledRef, eTaskType.MUTATOR, "vanilla_titan_taunts")
	Registry_InferRPakData("vanilla_titan_taunts", $"datatable/titan_executions.rpak", {
		itemType = eItemTypes.PILOT_EXECUTION
	})

	// dataTable = GetDataTable( $"datatable/pilot_executions.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string ref = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "ref" ) )
	// 	string name = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "name" ) )
	// 	string description = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "description" ) )
	// 	asset image = GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "image" ) )
	// 	bool hidden = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "hidden" ) )
	// 	int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

	// 	if ( IsDisabledRef( ref ) )
	// 		continue

	// 	CreatePassiveData( i, eItemTypes.PILOT_EXECUTION, hidden, ref, name, description, description, image, cost )
	// }

	// ///////////////////
	// TITAN EXECUTION DATA
	// ///////////////////

	// dataTable = GetDataTable( $"datatable/titan_executions.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	bool hidden = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "hidden" ) )
	// 	if ( hidden == true )
	// 		continue

	// 	string ref = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "ref" ) )
	// 	int itemType = eItemTypes[ GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) ) ]
	// 	string name = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "name" ) )
	// 	string description = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "description" ) )
	// 	asset image = GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "image" ) )
	// 	int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )
	// 	bool reqPrime = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "reqPrime" ) )

	// 	if ( IsDisabledRef( ref ) )
	// 		continue

	// 	CreateTitanExecutionData( i, itemType, hidden, ref, name, description, description, image, cost, reqPrime )
	// }

	///	========================================
	///			MP features + playlist
	///	========================================
	array<int> featState = [0]
	var CreateMpFeature = ArmoryUtils_ClosureBox(void function(
		string featureRef, string featureName, string featureDesc,
		asset featureIcon, int cost, string specificType
	) : (featState) {
		ItemData featureItem = CreateGenericItem( featState[0], eItemTypes.FEATURE, featureRef, featureName, featureDesc, "", featureIcon, cost, false )
		featureItem.i.specificType <- specificType
		featState[0]++
	})

	var CreatePlaylistItem = ArmoryUtils_ClosureBox(void function(
		string playlist, string name, asset image, int cost
	) : (featState) {
		ItemData featureItem = CreateGenericItem( featState[0], eItemTypes.FEATURE, playlist, name, "", "", image, cost, false )
		featureItem.i.specificType <- "#ITEM_TYPE_PLAYLIST"
		featureItem.i.isPlaylist <- true

		featState[0]++
	})

	// Registry_RPakJob( $"datatable/features_mp.rpak", CreateMpFeature, {featureIcon = [eColType.ASSET]})
	// Registry_RPakJob( $"datatable/playlist_items.rpak", CreatePlaylistItem, {image = [eColType.ASSET]})

	Registry_InferFunction( CreateMpFeature, eTaskType.FACTORY, "vanilla_mp_features" )
	Registry_InferRPakData( "vanilla_mp_features", $"datatable/features_mp.rpak", { featureIcon = [eColType.ASSET] } )

	Registry_InferFunction( CreatePlaylistItem, eTaskType.FACTORY, "vanilla_mp_gamemodes", [], ["vanilla_mp_features_000"] )
	Registry_InferRPakData( "vanilla_mp_gamemodes", $"datatable/playlist_items.rpak", { image = [eColType.ASSET] } )

	// dataTable = GetDataTable( $"datatable/features_mp.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// int featureIndex = 0
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string featureRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "featureRef" ) )
	// 	string name = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "featureName" ) )
	// 	string desc = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "featureDesc" ) )
	// 	asset image = GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "featureIcon" ) )
	// 	int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )
	// 	string specificType = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "specificType" ) )

	// 	const bool IS_HIDDEN_ARG = false
	// 	ItemData featureItem = CreateGenericItem( featureIndex, eItemTypes.FEATURE, featureRef, name, desc, "", image, cost, IS_HIDDEN_ARG )
	// 	featureItem.i.specificType <- specificType

	// 	featureIndex++
	// }

	// dataTable = GetDataTable( $"datatable/playlist_items.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string playlistRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "playlist" ) )
	// 	string name = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "name" ) )
	// 	asset image = GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "image" ) )
	// 	int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

	// 	const bool IS_HIDDEN_ARG = false
	// 	ItemData featureItem = CreateGenericItem( featureIndex, eItemTypes.FEATURE, playlistRef, name, "", "", image, cost, IS_HIDDEN_ARG )
	// 	featureItem.i.specificType <- "#ITEM_TYPE_PLAYLIST"
	// 	featureItem.i.isPlaylist <- true

	// 	featureIndex++
	// }

	// {
	// 	int featureIndex = 0
	// 	int gameModeCount = PersistenceGetEnumCount( "gameModes" )
	// 	for ( int modeIndex = 0; modeIndex < gameModeCount; modeIndex++ )
	// 	{
	// 		string gameModeRef = PersistenceGetEnumItemNameForIndex( "gameModes", modeIndex )
	// 		if ( !IsRefValid( gameModeRef ) )
	// 		{
	// 			string name = GameMode_GetName( gameModeRef )
	// 			string desc = GameMode_GetDesc( gameModeRef )
	// 			asset image = GameMode_GetIcon( gameModeRef )
	// 			int cost = 0
//
	// 			CreateGenericItem( featureIndex, eItemTypes.GAME_MODE, gameModeRef, name, desc, "", image, cost )
	// 			featureIndex++
	// 		}
	// 	}
	// }

	// RPakJob( $"datatable/pilot_weapon_features.rpak", ArmoryUtils_ClosureBox(CreateGenericItem), {
	// 	ref = "featureRef", name = "featureName", description = "featureDesc",
	// 	itemType = eItemTypes.WEAPON_FEATURE, longdesc = "", isHidden = false,
	// 	image = [ eColType.ASSET, "featureIcon" ]
	// })

	// ///////////////////
	// PILOT SECONDARY MOD SLOTS
	// ///////////////////
	dataTable = GetDataTable( $"datatable/pilot_weapon_features.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string featureRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "featureRef" ) )
		string name = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "featureName" ) )
		string desc = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "featureDesc" ) )
		asset image = GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "featureIcon" ) )
		int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )
		int dataTableIndex = i
		const bool IS_HIDDEN_ARG = false
		CreateGenericItem( dataTableIndex, eItemTypes.WEAPON_FEATURE, featureRef, name, desc, "", image, cost, IS_HIDDEN_ARG )
	}

	dataTable = GetDataTable( $"datatable/pilot_weapons.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string weaponRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "itemRef" ) )
		int weaponType = eItemTypes[ GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) ) ]
		if ( weaponType == eItemTypes.PILOT_PRIMARY )
		{
			CreateGenericSubItemData( eItemTypes.WEAPON_FEATURE, weaponRef, "primarymod2", file.itemData[ "primarymod2" ].cost )
			CreateGenericSubItemData( eItemTypes.WEAPON_FEATURE, weaponRef, "primarymod3", file.itemData[ "primarymod3" ].cost )
		}
		else
		{
			CreateGenericSubItemData( eItemTypes.WEAPON_FEATURE, weaponRef, "secondarymod2", file.itemData[ "secondarymod2" ].cost )
			CreateGenericSubItemData( eItemTypes.WEAPON_FEATURE, weaponRef, "secondarymod3", file.itemData[ "secondarymod3" ].cost )
		}
	}

	// ///////////////////
	// FACTION DATA # NOT THIS
	// ///////////////////
	// var CreateFaction = ArmoryUtils_ClosureBox(void function(
	// 	int dataTableIndex, string persistenceRef, string factionName, asset logo, int cost
	// ) {
	// 	ItemData item = CreateBaseItemData( eItemTypes.FACTION, persistenceRef, false )
	// 	item.name = factionName

	// 	item.imageAtlas = IMAGE_ATLAS_FACTION_LOGO
	// 	item.image = logo
	// 	item.cost = cost

	// 	item.persistenceId = dataTableIndex
	// })
	// Registry_RPakJob( $"datatable/faction_leaders.rpak", CreateFaction, {
	// 	logo = [ eColType.ASSET ] })

	dataTable = GetDataTable( $"datatable/faction_leaders.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string factionRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "persistenceRef" ) )
		asset logo = GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "logo" ) )
		string name = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "factionName" ) )
		int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

		ItemData item = CreateBaseItemData( eItemTypes.FACTION, factionRef, false )
		item.image = logo
		item.name = name
		item.cost = cost
		item.imageAtlas = IMAGE_ATLAS_FACTION_LOGO
		item.persistenceId = i
	}

	// ///////////////
	// TITAN MOD DATA
	// ///////////////
	dataTable = GetDataTable( $"datatable/titan_primary_mods_common.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	modCommonTable.clear()

	for ( int i = 0; i < numRows; i++ )
	{
		modCommonDef modCommon
		modCommon.name = GetDataTableString( dataTable, i, TITAN_PRIMARY_MOD_COMMON_NAME_COLUMN )
		modCommon.description = GetDataTableString( dataTable, i, TITAN_PRIMARY_MOD_COMMON_DESCRIPTION_COLUMN )
		modCommon.image = GetDataTableAsset( dataTable, i, TITAN_PRIMARY_MOD_COMMON_IMAGE_COLUMN )

		modCommon.dataTableIndex = i

		string itemRef = GetDataTableString( dataTable, i, TITAN_PRIMARY_MOD_COMMON_COLUMN )
		modCommonTable[ itemRef ] <- modCommon
	}

	dataTable = GetDataTable( $"datatable/titan_primary_mods.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string mod = GetDataTableString( dataTable, i, TITAN_PRIMARY_MOD_COLUMN )
		string weapon = GetDataTableString( dataTable, i, TITAN_PRIMARY_MOD_WEAPON_COLUMN )

		string name = modCommonTable[ mod ].name
		string description = modCommonTable[ mod ].description
		asset image = modCommonTable[ mod ].image
		int dataTableIndex = modCommonTable[ mod ].dataTableIndex

		int damageDisplay = GetDataTableInt( dataTable, i, TITAN_PRIMARY_MOD_DAMAGEDISPLAY_COLUMN )
		int accuracyDisplay = GetDataTableInt( dataTable, i, TITAN_PRIMARY_MOD_ACCURACYDISPLAY_COLUMN )
		int rangeDisplay = GetDataTableInt( dataTable, i, TITAN_PRIMARY_MOD_RANGEDISPLAY_COLUMN )
		int fireRateDisplay = GetDataTableInt( dataTable, i, TITAN_PRIMARY_MOD_FIRERATEDISPLAY_COLUMN )
		int clipSizeDisplay = GetDataTableInt( dataTable, i, TITAN_PRIMARY_MOD_CLIPSIZEDISPLAY_COLUMN )

		bool hidden = GetDataTableBool( dataTable, i, TITAN_PRIMARY_MOD_HIDDEN_COLUMN )
		// 		CreateModData( dataTableIndex, eItemTypes.TITAN_PRIMARY_MOD, weapon, mod, name, description,
		// description, image, damageDisplay, accuracyDisplay, rangeDisplay, fireRateDisplay, clipSizeDisplay )
	}

	/// ====================================================
	/// 				TITAN PASSIVE DATA
	/// ====================================================
	//	Causes error '[SERVER] Persistent data not available.'

	// Registry_RPakJob( $"datatable/titan_passives.rpak", ArmoryUtils_ClosureBox(CreatePassiveData), {
	// 	ref = TITAN_PASSIVE_COLUMN,
	// 	itemType = TITAN_PASSIVE_TYPE_COLUMN,
	//	name = TITAN_PASSIVE_NAME_COLUMN
	// 	desc = TITAN_PASSIVE_DESCRIPTION_COLUMN,
	// 	longdesc = TITAN_PASSIVE_LONGDESCRIPTION_COLUMN
	//	image = TITAN_PASSIVE_IMAGE_COLUMN
	// 	hidden = TITAN_PASSIVE_HIDDEN_COLUMN
	// })

	dataTable = GetDataTable( $"datatable/titan_passives.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string itemRef = GetDataTableString( dataTable, i, TITAN_PASSIVE_COLUMN )
		int itemType = eItemTypes[ GetDataTableString( dataTable, i, TITAN_PASSIVE_TYPE_COLUMN ) ]
		string name = GetDataTableString( dataTable, i, TITAN_PASSIVE_NAME_COLUMN )
		string description = GetDataTableString( dataTable, i, TITAN_PASSIVE_DESCRIPTION_COLUMN )
		string longDescription = GetDataTableString( dataTable, i, TITAN_PASSIVE_LONGDESCRIPTION_COLUMN )
		asset image = GetDataTableAsset( dataTable, i, TITAN_PASSIVE_IMAGE_COLUMN )
		bool hidden = GetDataTableBool( dataTable, i, TITAN_PASSIVE_HIDDEN_COLUMN )
		int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

		CreatePassiveData( i, itemType, hidden, itemRef, name, description, longDescription, image, cost )
	}

	// ///////////////////
	// TITAN OS DATA
	// ///////////////////
	// Registry_RPakJob( $"datatable/titan_voices.rpak", ArmoryUtils_ClosureBox(CreateGenericItem), {
	// 	ref = TITAN_VOICE_COLUMN, name = TITAN_VOICE_NAME_COLUMN,
	// 	itemType = eItemTypes.TITAN_OS, cost = 0, isHidden = false
	// })

	dataTable = GetDataTable( $"datatable/titan_voices.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string itemRef = GetDataTableString( dataTable, i, TITAN_VOICE_COLUMN )
		string name = GetDataTableString( dataTable, i, TITAN_VOICE_NAME_COLUMN )
		string description = GetDataTableString( dataTable, i, TITAN_VOICE_DESCRIPTION_COLUMN )
		asset image = GetDataTableAsset( dataTable, i, TITAN_VOICE_IMAGE_COLUMN )
		bool hidden = GetDataTableBool( dataTable, i, TITAN_VOICE_HIDDEN_COLUMN )

		const bool IS_HIDDEN_ARG = false
		CreateGenericItem( i, eItemTypes.TITAN_OS, itemRef, name, description, description, image, 0, IS_HIDDEN_ARG )
	}

	// var BakeTitan = ArmoryUtils_ClosureBox(void function(
	// 	int dataTableIndex, string titanRef, int cost, asset image, asset coreIcon, string name, string desc, string propertiesDesc,
	// 	int speedDisplay, int healthDisplay, int damageDisplay, int dashDisplay, int titanExecution,
	// 	int passive1Type, int passive2Type, int passive3Type, int passive4Type, int passive5Type, int passive6Type
	// ) {
	// 	ItemData item = CreateBaseItemData( eItemTypes.TITAN, titanRef, false )
	// 	item.name = name; item.desc = desc; item.longdesc = propertiesDesc;
	// 	item.image = image; item.imageAtlas = IMAGE_ATLAS_HUD; item.cost = cost;

	// 	// Shorthand injection to populate item.i
	// 	table i = {
	// 		coreIcon = coreIcon, statSpeed = speedDisplay, statHealth = healthDisplay,
	// 		statDamage = damageDisplay, statDash = dashDisplay, titanExecution = titanExecution,
	// 		passive1Type = passive1Type, passive2Type = passive2Type, passive3Type = passive3Type,
	// 		passive4Type = passive4Type, passive5Type = passive5Type, passive6Type = passive6Type
	// 	}
	// 	foreach ( k, v in i ) { item.i[k] <- v }

	// 	item.persistenceStruct = "titanChassis[" + dataTableIndex + "]"
	// 	item.persistenceId = dataTableIndex
	// })

	// var ResolveTitanSettings = ArmoryUtils_ClosureBox(table function(
	// 	string setFile, string primeSetFile, string desc,
	// 	int speedDisplay, int healthDisplay, int damageDisplay, int dashDisplay
	// ) {
	// 	#if SERVER || CLIENT
	// 	PrecacheModel( GetPlayerSettingsAssetForClassName( setFile, "bodymodel" ) )
	// 	PrecacheModel( GetPlayerSettingsAssetForClassName( setFile, "armsmodel" ) )
	// 	if ( primeSetFile != "" ) {
	// 		PrecacheModel( GetPlayerSettingsAssetForClassName( primeSetFile, "bodymodel" ) )
	// 		PrecacheModel( GetPlayerSettingsAssetForClassName( primeSetFile, "armsmodel" ) )
	// 	}
	// 	#endif

	// 	table res = {
	// 		name = expect string( GetPlayerSettingsFieldForClassName( setFile, "printname" ) ),
	// 		desc = expect string( GetPlayerSettingsFieldForClassName( setFile, "description" ) ),
	// 		titanExecution = GetTitanLoadoutPropertyExecutionType( setFile, "titanExecution" )
	// 	}

	// 	for ( int i = 1; i <= 6; i++ ) {
	// 		res["passive" + i + "Type"] <- GetTitanLoadoutPropertyPassiveType( setFile, "passive" + i )
	// 	}

	// 	return res
	// })

	// // Note the use of eParamSource.GENERATED to safely allocate RAM for these injected stats
	// int titanJobID = Registry_RPakJob( $"datatable/titans_mp.rpak", BakeTitan, {
	// 	name = [ eColType.STRING, "", eParamSource.GENERATED ], desc = [ eColType.STRING, "", eParamSource.GENERATED ], propertiesDesc = [ eColType.STRING, "desc", eParamSource.GENERATED ],

	// 	titanExecution = [ eColType.INT, "", eParamSource.GENERATED ],
	// 	speedDisplay = [ eColType.INT, "", eParamSource.GENERATED ], healthDisplay = [ eColType.INT, "", eParamSource.GENERATED ], damageDisplay = [ eColType.INT, "", eParamSource.GENERATED ], dashDisplay = [ eColType.INT, "", eParamSource.GENERATED ],
	// 	passive1Type = [ eColType.INT, "", eParamSource.GENERATED ], passive2Type = [ eColType.INT, "", eParamSource.GENERATED ], passive3Type = [ eColType.INT, "", eParamSource.GENERATED ],
	// 	passive4Type = [ eColType.INT, "", eParamSource.GENERATED ], passive5Type = [ eColType.INT, "", eParamSource.GENERATED ], passive6Type = [ eColType.INT, "", eParamSource.GENERATED ]
	// })

	// Registry_ModifyJob( titanJobID, 0, FilterDisabledRef, { ref = "titanRef" } )
	// Registry_ModifyJob( titanJobID, 1, ResolveTitanSettings, {
	// 	[$"datatable/titan_properties.rpak"] = [
	// 		"setFile", "primeSetFile", "desc", "speedDisplay",
	// 		"healthDisplay", "damageDisplay", "dashDisplay"
	// 	]
	// })

	// Registry_ExecutePipeline()

	//*
	var titanPropertiesDataTable = GetDataTable( $"datatable/titan_properties.rpak" )
	var titansMpDataTable = GetDataTable( $"datatable/titans_mp.rpak" )
	numRows = GetDatatableRowCount( titansMpDataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string titanRef = GetDataTableString( titansMpDataTable, i, GetDataTableColumnByName( titansMpDataTable, "titanRef" ) )
		int cost = GetDataTableInt( titansMpDataTable, i, GetDataTableColumnByName( titansMpDataTable, "cost" ) )
		asset image = GetDataTableAsset( titansMpDataTable, i, GetDataTableColumnByName( titansMpDataTable, "image" ) )
		asset coreIcon = GetDataTableAsset( titansMpDataTable, i, GetDataTableColumnByName( titansMpDataTable, "coreIcon" ) )

		if ( IsDisabledRef( titanRef ) )
			continue

		CreateTitanData( i, titanRef, cost, image, coreIcon )

		ItemData itemData = GetItemData( titanRef )
		int passive1Type = expect int( itemData.i.passive1Type )
		int passive2Type = expect int( itemData.i.passive2Type )
		int passive3Type = expect int( itemData.i.passive3Type )
		int passive4Type = expect int( itemData.i.passive4Type )
		int passive5Type = expect int( itemData.i.passive5Type )
		int passive6Type = expect int( itemData.i.passive6Type )

		{
			array<ItemData> items = GetAllItemsOfType( passive1Type )
			foreach ( item in items )
			{
				CreateGenericSubItemData( passive1Type, titanRef, item.ref, GetItemCost( item.ref ) )
			}
		}

		if ( passive1Type != passive2Type )
		{
			array<ItemData> items = GetAllItemsOfType( passive2Type )
			foreach ( item in items )
			{
				CreateGenericSubItemData( passive2Type, titanRef, item.ref, GetItemCost( item.ref ) )
			}
		}

		if ( passive3Type != passive1Type && passive3Type != passive2Type )
		{
			array<ItemData> items = GetAllItemsOfType( passive3Type )
			foreach ( item in items )
			{
				CreateGenericSubItemData( passive3Type, titanRef, item.ref, GetItemCost( item.ref ) )
			}
		}

		array<ItemData> passive4items = GetAllItemsOfType( passive4Type )
		foreach ( item in passive4items )
		{
			CreateGenericSubItemData( passive4Type, titanRef, item.ref, GetItemCost( item.ref ) )
		}

		array<ItemData> passive5items = GetAllItemsOfType( passive5Type )
		foreach ( item in passive5items )
		{
			CreateGenericSubItemData( passive5Type, titanRef, item.ref, GetItemCost( item.ref ) )
		}

		array<ItemData> passive6items = GetAllItemsOfType( passive6Type )
		foreach ( item in passive6items )
		{
			CreateGenericSubItemData( passive6Type, titanRef, item.ref, GetItemCost( item.ref ) )
		}

		{
			var camoSkinsDataTable = GetDataTable( $"datatable/camo_skins.rpak" )
			for ( int camoRow = 0; camoRow < GetDatatableRowCount( camoSkinsDataTable ); camoRow++ )
			{
				string camoRef = GetDataTableString( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_REF_COLUMN_NAME ) )
				string titanCamoRef = GetDataTableString( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_TITAN_REF_COLUMN_NAME ) )
				int titanWeaponCost = GetDataTableInt( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_TITAN_WEAPON_COST_COLUMN_NAME ) )
				int titanCost = GetDataTableInt( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_TITAN_COST_COLUMN_NAME ) )
				int categoryId = GetDataTableInt( camoSkinsDataTable, camoRow, GetDataTableColumnByName( camoSkinsDataTable, CAMO_CATEGORY_COLUMN_NAME ) )

				CreateGenericSubItemData( eItemTypes.CAMO_SKIN, titanRef, camoRef, titanWeaponCost, { categoryId = categoryId } )
				CreateGenericSubItemData( eItemTypes.CAMO_SKIN_TITAN, titanRef, titanCamoRef, titanCost, { categoryId = categoryId } )
			}
		}

		#if SERVER || CLIENT
			int propertyRow = GetDataTableRowMatchingStringValue( titanPropertiesDataTable, GetDataTableColumnByName( titanPropertiesDataTable, "titanRef" ), titanRef )
			string setFile = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "setFile" ) )
			PrecacheModel( GetPlayerSettingsAssetForClassName( setFile, "bodymodel" ) )
			PrecacheModel( GetPlayerSettingsAssetForClassName( setFile, "armsmodel" ) )
			string primeSetFile = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "primeSetFile" ) )
			if ( primeSetFile != "" )
			{
				PrecacheModel( GetPlayerSettingsAssetForClassName( primeSetFile, "bodymodel" ) )
				PrecacheModel( GetPlayerSettingsAssetForClassName( primeSetFile, "armsmodel" ) )
			}
		#endif
		// string primary = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "primary" ) )
		// string melee = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "melee" ) )
		// string ordnance = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "ordnance" ) )
		// string special = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "special" ) )
		// string antirodeo = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "antirodeo" ) )
		// string coreAbility = GetDataTableString( titanPropertiesDataTable, propertyRow, GetDataTableColumnByName( titanPropertiesDataTable, "coreAbility" ) )
	} //*/

	// ////////////////////////
	// DLC1
	// ////////////////////////
	// Need to be moved up here for prime_titan_nose_art to work
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "ion_prime", "ion", true )
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "tone_prime", "tone", true )
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "scorch_prime", "scorch", true )
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "legion_prime", "legion", true )
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "ronin_prime", "ronin", true )
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "northstar_prime", "northstar", true )
	CreatePrimeTitanData( eItemTypes.PRIME_TITAN, "vanguard_prime", "vanguard", true )

	dataTable = GetDataTable( $"datatable/titan_nose_art.rpak" )
	table<string, int> decalIndexTable
	for ( int row = 0; row < GetDatatableRowCount( dataTable ); row++ )
	{
		string titanRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, "titanRef" ) )
		string ref = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, "ref" ) )
		asset image = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, "image" ) )
		string name = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, "name" ) )
		int cost = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, "cost" ) )

		if ( IsDisabledRef( titanRef ) )
			continue

		if ( !( titanRef in decalIndexTable ) )
			decalIndexTable[ titanRef ] <- 0
		else
			decalIndexTable[ titanRef ]++

		// CreateGenericItem( datatableIndex, eItemTypes.TITAN_NOSE_ART, ref, name, "", "", image )
		// CreateBaseItemData( eItemTypes.TITAN_NOSE_ART, ref, false )
		CreateNoseArtData( decalIndexTable[ titanRef ], eItemTypes.TITAN_NOSE_ART, false, ref, name, image, decalIndexTable[ titanRef ] )
		CreateGenericSubItemData( eItemTypes.TITAN_NOSE_ART, titanRef, ref, cost )

		if ( !( titanRef in file.titanClassAndPersistenceValueToNoseArtRefTable ) )
			file.titanClassAndPersistenceValueToNoseArtRefTable[ titanRef ] <- {}

		file.titanClassAndPersistenceValueToNoseArtRefTable[ titanRef ][ decalIndexTable[ titanRef ] ] <- ref
	}

	dataTable = GetDataTable( $"datatable/titan_skins.rpak" )
	for ( int row = 0; row < GetDatatableRowCount( dataTable ); row++ )
	{
		string titanRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, "titanRef" ) )
		string ref = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, "ref" ) )
		asset image = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, "image" ) )
		string name = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, "name" ) )
		int cost = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, "cost" ) )
		int skinIndex = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, "skinIndex" ) )
		int datatableIndex = row

		if ( IsDisabledRef( titanRef ) || IsDisabledRef( ref ) )
			continue

		CreateSkinData( datatableIndex, eItemTypes.TITAN_WARPAINT, false, ref, name, image, skinIndex )
		CreateGenericSubItemData( eItemTypes.TITAN_WARPAINT, titanRef, ref, cost, { skinIndex = skinIndex } )

		if ( !( titanRef in file.titanClassAndPersistenceValueToSkinRefTable ) )
			file.titanClassAndPersistenceValueToSkinRefTable[ titanRef ] <- {}

		file.titanClassAndPersistenceValueToSkinRefTable[ titanRef ][ skinIndex ] <- ref
	}


	/// =========== Persona customization ============
	// var PlayerProfileCreate = ArmoryUtils_ClosureBox(void function(
	// 	int dataTableIndex, int itemType, string ref, string name, asset image, int cost, bool hidden,
	// ) {
	// 	CreateGenericItem( dataTableIndex, itemType, ref, name, "", "", image, cost, hidden )
	// 	GetItemData( ref ).imageAtlas = IMAGE_ATLAS_CALLINGCARD
	// })

	// var PlayerProfileValidate = ArmoryUtils_ClosureBox(table function( string ref, int cost, bool hidden ) {
	// 	return { ref = IsDisabledRef(ref) ? "PIPELINE_SKIP" : ref, hidden = (cost < 0), cost = max(cost, 0) }
	// })

	// jobID = Registry_RPakJob( $"datatable/calling_cards.rpak", PlayerProfileCreate, {
	// 	itemType = eItemTypes.CALLING_CARD,
	// 	ref = CALLING_CARD_REF_COLUMN_NAME,
	// 	name = CALLING_CARD_NAME_COLUMN_NAME,
	// 	image = CALLING_CARD_IMAGE_COLUMN_NAME,
	// 	hidden = false
	// })
	// Registry_ModifyJob( jobID, 0, FilterDisabledRef, {ref = CALLING_CARD_REF_COLUMN_NAME})
	// Registry_ModifyJob( jobID, 0, PlayerProfileValidate, {ref = CALLING_CARD_REF_COLUMN_NAME})

	// jobID = Registry_RPakJob( $"datatable/callsign_icons.rpak", PlayerProfileCreate, {
	// 	itemType = eItemTypes.CALLSIGN_ICON,
	// 	ref = CALLSIGN_ICON_REF_COLUMN_NAME
	// 	name = CALLSIGN_ICON_NAME_COLUMN_NAME,
	// 	image = CALLSIGN_ICON_IMAGE_COLUMN_NAME,
	// 	hidden = false
	// })
	// Registry_ModifyJob( jobID, 0, FilterDisabledRef, {ref = CALLSIGN_ICON_REF_COLUMN_NAME})
	// Registry_ModifyJob( jobID, 0, PlayerProfileValidate, {ref = CALLSIGN_ICON_REF_COLUMN_NAME})

	{
		var dataTable = GetDataTable( $"datatable/calling_cards.rpak" )
		for ( int row = 0; row < GetDatatableRowCount( dataTable ); row++ )
		{
			string cardRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CALLING_CARD_REF_COLUMN_NAME ) )
			string name = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CALLING_CARD_NAME_COLUMN_NAME ) )
			asset image = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, CALLING_CARD_IMAGE_COLUMN_NAME ) )
			int cost = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, "cost" ) )
			bool isHidden = false
			if ( cost < 0 )
			{
				isHidden = true
				cost = 0
			}

			string desc = "Undefined"
			string longdesc = "Undefined"

			int datatableIndex = row

			CreateGenericItem( datatableIndex, eItemTypes.CALLING_CARD, cardRef, name, desc, longdesc, image, cost, isHidden )
			GetItemData( cardRef ).imageAtlas = IMAGE_ATLAS_CALLINGCARD
		}
	}

	{
		var dataTable = GetDataTable( $"datatable/callsign_icons.rpak" )
		for ( int row = 0; row < GetDatatableRowCount( dataTable ); row++ )
		{
			string iconRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CALLSIGN_ICON_REF_COLUMN_NAME ) )
			string name = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, CALLSIGN_ICON_NAME_COLUMN_NAME ) )
			asset image = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, CALLSIGN_ICON_IMAGE_COLUMN_NAME ) )
			int cost = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, "cost" ) )
			bool isHidden = false
			if ( cost < 0 )
			{
				isHidden = true
				cost = 0
			}

			string desc = "Undefined"
			string longdesc = "Undefined"

			int datatableIndex = row

			if ( IsDisabledRef( iconRef ) )
				continue

			CreateGenericItem( datatableIndex, eItemTypes.CALLSIGN_ICON, iconRef, name, desc, longdesc, image, cost, isHidden )
			GetItemData( iconRef ).imageAtlas = IMAGE_ATLAS_CALLINGCARD
		}
	}

	// ///////////////////
	// NON-LOADOUT WEAPONS
	// ///////////////////

	dataTable = GetDataTable( $"datatable/non_loadout_weapons.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	for ( int i = 0; i < numRows; i++ )
	{
		string weapon = GetDataTableString( dataTable, i, NON_LOADOUT_WEAPON_COLUMN )

		#if SERVER || CLIENT
			if ( !IsDisabledRef( weapon ) )
				PrecacheWeapon( weapon )
		#endif
		// CreateWeaponData( i, eItemTypes.NOT_LOADOUT, true, weapon, true )
	}

	// ///////////////////
	// NON-LOADOUT MODS
	// ///////////////////

	// dataTable = GetDataTable( $"datatable/non_loadout_mods.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string mod = GetDataTableString( dataTable, i, NON_LOADOUT_MOD_COLUMN )
	// 	string parentItem = GetDataTableString( dataTable, i, NON_LOADOUT_MOD_PARENT_COLUMN )
	// 	string name = GetDataTableString( dataTable, i, NON_LOADOUT_MOD_NAME_COLUMN )
	// 	string description = GetDataTableString( dataTable, i, NON_LOADOUT_MOD_DESCRIPTION_COLUMN )
	// 	asset image = GetDataTableAsset( dataTable, i, NON_LOADOUT_MOD_IMAGE_COLUMN )
	//
	// 	CreateModData( -1, eItemTypes.NOT_LOADOUT, parentItem, mod, name, description, description, image )
	// }

	// ///////////////////
	// BURN METER REWARD DATA
	// ///////////////////
	/*
	var CreateBurnMeter = ArmoryUtils_ClosureBox(void function(
		int datatableIndex, string ref, string name, int cost,
		asset image, asset model, bool hidden
	) {
		//	Client script error happens w/o server precache
		#if SERVER || CLIENT
		PrecacheModel( model )
		#endif

		CreateGenericItem( datatableIndex, eItemTypes.BURN_METER_REWARD, ref, name, name, name, image, cost, hidden )
	}) //*/

	// jobID = Registry_RPakJob($"datatable/burn_meter_rewards.rpak", ArmoryUtils_ClosureBox(CreateGenericItem), {
	// 	ref = BURN_REF_COLUMN_NAME, itemType = eItemTypes.BURN_METER_REWARD, name = BURN_NAME_COLUMN_NAME,
	// 	desc = BURN_NAME_COLUMN_NAME, isHidden = [eColType.BOOL, "selectable"] })
	// Registry_ModifyJob( jobID, 0, FilterDisabledRef, {ref = BURN_REF_COLUMN_NAME})

	// var InvertHidden = ArmoryUtils_ClosureBox(table function(bool hidden) { return { hidden = !hidden }; })
	// Registry_ModifyJob( jobID, 0, InvertHidden, {hidden = "selectable"})

	// #if SERVER || CLIENT
	// var ModelPrecache = ArmoryUtils_ClosureBox(table function(asset model) { PrecacheModel( model ); return {} })
	// table rpak2args = {}; rpak2args[$"datatable/burn_meter_rewards.rpak"] <- ["model"]
	// Registry_ModifyJob( jobID, 0, ModelPrecache, rpak2args)
	// #endif

	//*
	dataTable = GetDataTable( $"datatable/burn_meter_rewards.rpak" )
	for ( int row = 0; row < GetDatatableRowCount( dataTable ); row++ )
	{
		string itemRef = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, BURN_REF_COLUMN_NAME ) )
		string name = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, BURN_NAME_COLUMN_NAME ) )
		string description = GetDataTableString( dataTable, row, GetDataTableColumnByName( dataTable, BURN_NAME_COLUMN_NAME ) )
		int cost = GetDataTableInt( dataTable, row, GetDataTableColumnByName( dataTable, "cost" ) )
		asset image = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, "image" ) )

		if ( IsDisabledRef( itemRef ) )
			continue

		// Why does the server need this? Client script error happens otherwise.
		#if SERVER || CLIENT
			asset model = GetDataTableAsset( dataTable, row, GetDataTableColumnByName( dataTable, "model" ) )
			PrecacheModel( model )
		#endif // SERVER || CLIENT

		bool hidden = !GetDataTableBool( dataTable, row, GetDataTableColumnByName( dataTable, "selectable" ) )
		CreateGenericItem( row, eItemTypes.BURN_METER_REWARD, itemRef, name, description, description, image, cost, hidden )
	} //*/

	//		Execute
	Registry_ExecutePipeline()

	InitRandomUnlocks()

	SetupFrontierDefenseItems()

	InitUnlocks()