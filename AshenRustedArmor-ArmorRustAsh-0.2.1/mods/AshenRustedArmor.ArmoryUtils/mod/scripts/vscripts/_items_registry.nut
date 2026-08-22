{
	///	========================================
	///			MP features + playlist	//	GOOD
	///	========================================
	array<int> featState = [0]
	var CreateMpFeature = ArmoryUtils_ClosureBox(void function(
		string featureRef, string featureName, string featureDesc,
		asset image, int cost, string specificType
	) : (featState) {
		ItemData featureItem = CreateGenericItem( featState[0], eItemTypes.FEATURE, featureRef, featureName, featureDesc, "", image, cost, false )
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

	Registry_InferFunction( CreateMpFeature, eTaskType.FACTORY, "vanilla_mp_features" )
	Registry_InferRPakData( "vanilla_mp_features", $"datatable/features_mp.rpak", { image = ["featureIcon", eColType.ASSET] } )

	Registry_InferFunction( CreatePlaylistItem, eTaskType.FACTORY, "vanilla_mp_gamemodes", [], ["vanilla_mp_features_000"] )
	Registry_InferRPakData( "vanilla_mp_gamemodes", $"datatable/playlist_items.rpak", { image = ["image", eColType.ASSET] } )

	/// ====================================================
	/// 			PILOT WEAPON FEATURE DATA	//	ISSUE - MENU CRASH
	// / ====================================================
	// var AttachmentSlotsGenerate = ArmoryUtils_ClosureBox(array function( string itemRef, string type ) {
	// 	bool primary = eItemTypes[type] == eItemTypes.PILOT_PRIMARY
	// 	string m2 = primary ? "primarymod2" : "secondarymod2"
	// 	string m3 = primary ? "primarymod3" : "secondarymod3"

	// 	return [
	// 		{parentRef = itemRef, itemRef = m2},
	// 		{parentRef = itemRef, itemRef = m3}
	// 	]
	// })

	// var AttachmentSlotsModify = ArmoryUtils_ClosureBox(table function( string itemRef ) {
	// 	table out = { cost = 0, itemType = eItemTypes.WEAPON_FEATURE }
	// 	if (itemRef in file.itemData) { out.cost = file.itemData[itemRef].cost }
	// 	return out
	// })

	// Registry_InferFunction(ArmoryUtils_ClosureBox(CreateGenericItem), eTaskType.FACTORY, "vanilla_pilot_weapon_features")
	// Registry_InferRPakData("vanilla_pilot_weapon_features", $"datatable/pilot_weapon_features.rpak", {
	// 	ref = ["featureRef"], name = ["featureName"], description = ["featureDesc"], image = ["featureIcon", eColType.ASSET]
	// 	itemType = eItemTypes.WEAPON_FEATURE, longdesc = "", isHidden = false
	// })

	// Registry_InferFunction(AttachmentSlotsGenerate, eTaskType.GENERATOR, "vanilla_pilot_attachments")
	// Registry_InferFunction(AttachmentSlotsModify, eTaskType.MUTATOR, "vanilla_pilot_attachments", [], ["vanilla_pilot_weapon_features_000"])
	// Registry_InferFunction(ArmoryUtils_ClosureBox(CreateGenericSubItemData), eTaskType.FACTORY, "vanilla_pilot_attachments")
	// Registry_InferRPakData("vanilla_pilot_attachments", $"datatable/pilot_weapons.rpak", { parentRef = ["itemRef"], t = {} })

	//*
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
	}	//*/

	/// ====================================================
	/// 				TITAN LOADOUT DATA	//
	/// ====================================================
	var TitanModelPrecache = ArmoryUtils_ClosureBox(table function( string titanRef ) {
		if (IsDisabledRef( titanRef )) { return {}; }
	})


	//*
	var titanPropertiesDataTable = GetDataTable( $"datatable/titan_properties.rpak" )
	var titansMpDataTable = GetDataTable( $"datatable/titans_mp.rpak" )
	numRows = GetDatatableRowCount( titansMpDataTable )
	for ( int i = 0; i < numRows; i++ ) {
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
			foreach ( item in items ) {
				CreateGenericSubItemData( passive1Type, titanRef, item.ref, GetItemCost( item.ref ) )
			}
		}

		if ( passive1Type != passive2Type ) {
			array<ItemData> items = GetAllItemsOfType( passive2Type )
			foreach ( item in items ) {
				CreateGenericSubItemData( passive2Type, titanRef, item.ref, GetItemCost( item.ref ) )
			}
		}

		if ( passive3Type != passive1Type && passive3Type != passive2Type ) {
			array<ItemData> items = GetAllItemsOfType( passive3Type )
			foreach ( item in items ) {
				CreateGenericSubItemData( passive3Type, titanRef, item.ref, GetItemCost( item.ref ) )
			}
		}

		array<ItemData> passive4items = GetAllItemsOfType( passive4Type )
		foreach ( item in passive4items ) {
			CreateGenericSubItemData( passive4Type, titanRef, item.ref, GetItemCost( item.ref ) )
		}

		array<ItemData> passive5items = GetAllItemsOfType( passive5Type )
		foreach ( item in passive5items ) {
			CreateGenericSubItemData( passive5Type, titanRef, item.ref, GetItemCost( item.ref ) )
		}

		array<ItemData> passive6items = GetAllItemsOfType( passive6Type )
		foreach ( item in passive6items ) {
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
		if ( primeSetFile != "" ) {
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
}