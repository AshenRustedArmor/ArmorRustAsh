global function ArmoryUtil_Registry_Init

global function ArmoryUtil_RegisterAbility
global function ArmoryUtil_RegisterWeapon
global function ArmoryUtil_RegisterPassive

global function ArmoryUtil_RegisterCommonMod
global function ArmoryUtil_RegisterWeaponMod
global function ArmoryUtil_RegisterWeaponFeature

global function ArmoryUtil_RegisterTitanBase

global function ArmoryUtil_RegisterMoveItem

/*	=======	ITEM REGISTRATION =======
	There are multiple item registry files. Of them, the one most relevant here
	is 'NorthstarMods/Northstar.CustomServers/mod/scripts/vscripts/_items.gnut'

	_items.gnut parses weapon tables (e.g. datatable/pilot_weapon.rpak) inside
	the function InitItems(). This adds information in the LOCAL struct 'file',
	which is how the game defines item data / menu information.

struct {
	array<GlobalItemRef> allItems
	table<string, int> itemRefToGuid
	table<int, string> guidToItemRef

	table<string, ItemData> itemData
	table<int, array<string> > itemsOfType

	...

	array<void functionref()> itemRegistrationCallbacks
} file

	This provides a few key pieces of information:
	-	file.itemData[ ref ]: Matches reference strings (e.g. "mp_weapon_car")
		to their ItemData, a global struct containing the relevant properties
		necessary to define an item in game / in the menu.
	-	file.itemsOfType[ itemType ]: Matches slot index to reference strings.

	See _items.gnut:543.
}
*/

struct {
	table< int, array<string> > itemRefArrs
	table< int, array<string> > typeRefArrs

	table< int, int > ctr
	table< int, int > pdefBounds

	array< void functionref() > registryQueue
} data

//		Initialization
void function ArmoryUtil_Registry_Init() {
	data.itemRefArrs = {}
	data.typeRefArrs = {}

	data.ctr = {}
	data.pdefBounds = {}

	data.registryQueue = []

	AddCallback_OnRegisterCustomItems( ArmoryUtil_Registry_InitInternal )
	printt( "[ArmoryUtil] Registry: Init call" )
}
void function ArmoryUtil_Registry_InitInternal() {
	//	1). Track the array counters
	for (int i = 0; i < eItemTypes.COUNT; i++ ) {
		data.typeRefArrs[i] <- GetAllRefsOfType(i)
		data.ctr[i] <- data.typeRefArrs[i].len()

		data.pdefBounds[i] <- data.typeRefArrs[i].len()
	}

	// 2). Execute all deferred registrations
	foreach ( void functionref() callback in data.registryQueue ) {
		printt( "[ArmoryUtil] Registry: running queued lambda" )
		callback()
	}

	printt( "[ArmoryUtil] Registry: Queue drained." )
}

//		Registration
//	Item creation
ItemData function _RegisterBaseData( string itemRef, int itemType, bool hidden = false ) {
	//		Sanity checks
	//	Get if already defined (_items.gnut:4183)
	if ( ItemDefined(itemRef) ) { return GetItemData(itemRef) }

	//		Functionality
	//	Accumulate counter
	int itemIdx = data.ctr[ itemType ]
	data.ctr[ itemType ]++

	//	Create base item data
	ItemData item = CreateBaseItemData( itemType, itemRef, hidden )
	item.persistenceId = itemIdx
	return item
}

//	Helper functions
void function _PopulateFromArgs( ItemData item, string name, string desc, asset image ) {
	item.name = name
	item.longname = name

	item.desc = desc
	item.longdesc = desc

	item.image = image
	item.imageAtlas = IMAGE_ATLAS_MENU
}

void function _PopulateFromFile( ItemData item, string itemRef ) {
	item.name	  = expect string( GetWeaponInfoFileKeyField_GlobalNotNull( itemRef, "shortprintname" ) )
	item.longname = expect string( GetWeaponInfoFileKeyField_GlobalNotNull( itemRef, "printname" ) )
	item.desc	  = expect string( GetWeaponInfoFileKeyField_GlobalNotNull( itemRef, "description" ) )
	item.longdesc = expect string( GetWeaponInfoFileKeyField_GlobalNotNull( itemRef, "longdesc" ) )

	asset image = GetWeaponInfoFileKeyFieldAsset_Global( itemRef, "menu_icon" )
	if ( image == $"" ) { item.image = $"ui/temp" } else { item.image = image }
}

void function _ApplyPersistence( ItemData item, string itemRef, int itemType ) {
	string persistenceStruct = ""

	switch ( itemType ) {
		case eItemTypes.PILOT_PRIMARY:
		case eItemTypes.PILOT_SECONDARY:
			string stringVal = GetWeaponInfoFileKeyField_GlobalString( itemRef, "menu_category" )
			item.i.menuCategory <- MenuCategoryStringToEnumValue( stringVal )

			stringVal = GetWeaponInfoFileKeyField_GlobalString( itemRef, "menu_anim_class" )
			item.i.menuAnimClass <- MenuAnimClassStringToEnumValue( stringVal )

			persistenceStruct = "pilotWeapons[" + item.persistenceId + "]"
			break

		case eItemTypes.PILOT_ORDNANCE:
			persistenceStruct = "pilotOffhands[" + item.persistenceId + "]"
			break

		case eItemTypes.PILOT_SPECIAL:
			item.imageAtlas = IMAGE_ATLAS_HUD
			persistenceStruct = "pilotOffhands[" + item.persistenceId + "]"
			break

		case eItemTypes.TITAN_PRIMARY:
			persistenceStruct = "titanWeapons[" + item.persistenceId + "]"
			break

		case eItemTypes.TITAN_SPECIAL:
		case eItemTypes.TITAN_ANTIRODEO:
		case eItemTypes.TITAN_ORDNANCE:
		case eItemTypes.TITAN_CORE_ABILITY:
			item.imageAtlas = IMAGE_ATLAS_HUD
			persistenceStruct = "titanOffhands[" + item.persistenceId + "]"
			break
	}

	if( item.persistenceId >= data.pdefBounds[ itemType ] ) {
		printt( "[ArmoryUtil] Registry: Persistence bypassed for custom item: " + itemRef )
		return
	}

	item.persistenceStruct = persistenceStruct
}

int function MenuCategoryStringToEnumValue( string stringVal ) {
	int enumVal = -1
	switch ( stringVal ) {
		case "ar":
			enumVal = ePrimaryWeaponCategory.AR
			break

		case "smg":
			enumVal = ePrimaryWeaponCategory.SMG
			break

		case "lmg":
			enumVal = ePrimaryWeaponCategory.LMG
			break

		case "sniper":
			enumVal = ePrimaryWeaponCategory.SNIPER
			break

		case "shotgun":
			enumVal = ePrimaryWeaponCategory.SHOTGUN
			break

		case "handgun":
			enumVal = ePrimaryWeaponCategory.HANDGUN
			break

		case "special":
			enumVal = ePrimaryWeaponCategory.SPECIAL
			break

		case "at":
			enumVal = eSecondaryWeaponCategory.AT
			break

		case "pistol":
			enumVal = eSecondaryWeaponCategory.PISTOL
			break

		default:
			Assert( 0, "Unknown stringVal: " + stringVal )
	}

	return enumVal
}

int function MenuAnimClassStringToEnumValue( string stringVal ) {
	int enumVal = -1

	switch ( stringVal ) {
		case "small":
			enumVal = eMenuAnimClass.SMALL
			break

		case "medium":
			enumVal = eMenuAnimClass.MEDIUM
			break

		case "large":
			enumVal = eMenuAnimClass.LARGE
			break

		case "custom":
			enumVal = eMenuAnimClass.CUSTOM
			break

		default:
			Assert( 0, "Unknown stringVal: " + stringVal )
	}

	return enumVal
}

void function _RegisterWeaponCamos( string itemRef ) {
	var camoSkinsDataTable = GetDataTable( $"datatable/camo_skins.rpak" )
	for ( int i = 0; i < GetDatatableRowCount( camoSkinsDataTable ); i++ ) {
		string camoRef = GetDataTableString( camoSkinsDataTable, i, GetDataTableColumnByName( camoSkinsDataTable, "camoRef" ) )
		int categoryId = GetDataTableInt( camoSkinsDataTable, i, GetDataTableColumnByName( camoSkinsDataTable, CAMO_CATEGORY_COLUMN_NAME ) )

		CreateGenericSubItemData( eItemTypes.CAMO_SKIN, itemRef, camoRef, 0, { categoryId = categoryId } )
	}
}

ItemData function _PopulateAbility(
	string itemRef, int itemType,
	int cost, bool hidden,
	bool isDamageSource,
) {
	//	1). Allocate
	ItemData item = _RegisterBaseData( itemRef, itemType, hidden )

	//	2). Map values
	item.cost = cost
	item.i.isDamageSource = isDamageSource

	_PopulateFromFile( item, itemRef )
	_ApplyPersistence( item, itemRef, itemType )

	return item
}

//	Registration functions
void function ArmoryUtil_RegisterAbility(
	string itemRef, int itemType,
	int cost = 0, bool hidden = false,
	bool isDamageSource = true,
) { data.registryQueue.append( void function(): (
	itemRef, itemType, cost, hidden, isDamageSource
) {
	//	1). Allocate
	ItemData item = _PopulateAbility( itemRef, itemType, cost, hidden, isDamageSource )

	//	2). Register damage source
	#if SERVER || CLIENT
	if( itemType != eItemTypes.NOT_LOADOUT  && isDamageSource ) {
		RegisterWeaponDamageSourceName( itemRef, expect string( GetWeaponInfoFileKeyField_GlobalNotNull( itemRef, "shortprintname" ) ) )
	}
	#endif
})}

void function ArmoryUtil_RegisterWeapon(
	string itemRef, int itemType,
	string xpPerLevelType = "default",
	int cost = 0, bool hidden = false,
) { data.registryQueue.append( void function() : (
	itemRef, itemType, xpPerLevelType, cost, hidden
) {
	//	1). Populate as ability
	ItemData item = _PopulateAbility( itemRef, itemType, cost, hidden, true )

	//	2). Fill weapon-specific info
	item.i.xpPerLevelType <- xpPerLevelType
	WeaponSetXPPerLevelType( itemRef, xpPerLevelType )

	_RegisterWeaponCamos( itemRef )

	//	2). Register damage source
	#if SERVER || CLIENT
	RegisterWeaponDamageSourceName( itemRef, expect string( GetWeaponInfoFileKeyField_GlobalNotNull( itemRef, "shortprintname" ) ) )
	#endif
})}

void function ArmoryUtil_RegisterPassive(
	string itemRef, int itemType,
	string name, string desc, asset image,
	int cost = 0, bool hidden = false,
) { data.registryQueue.append( void function() : (
	itemRef, itemType, name, desc, image, cost, hidden
) {
	//	1). Allocate
	ItemData item = _RegisterBaseData( itemRef, itemType, hidden )

	//	2). Map values
	item.cost = cost
	item.hidden = hidden

	_PopulateFromArgs( item, name, desc, image )
})}

void function ArmoryUtil_RegisterCommonMod(
	string modRef, string modType,
	string name, string desc, asset image,
	int cost = 0, int costSniper = 0, int costPistol = 0, int costAT = 0,
	bool hidden = false,
) { data.registryQueue.append( void function() : (
	modRef, modType, name, desc, image, cost, costSniper, costPistol, costAT, hidden
) {
	int itemType = (modType == "attachment") ? eItemTypes.SUB_PILOT_WEAPON_ATTACHMENT : eItemTypes.SUB_PILOT_WEAPON_MOD
	ItemData item = _RegisterBaseData( modRef, itemType, hidden )

	item.cost = cost
	_PopulateFromArgs( item, name, desc, image )

	//	Cost scalars go into the 'i' table for now
	item.i.modType <- modType
	item.i.costSniper <- costSniper
	item.i.costPistol <- costPistol
	item.i.costAT <- costAT
})}
void function ArmoryUtil_RegisterWeaponMod(
	string parentRef, string modRef,
	int cost = -1,
	int statDamage = 0, int statAccuracy = 0, int statRange = 0, int statFireRate = 0, int statClipSize = 0
) { data.registryQueue.append( void function() : (
	parentRef, modRef, cost, statDamage, statAccuracy, statRange, statFireRate, statClipSize,
) {
	Assert( ItemDefined( parentRef ), "[ArmoryUtil] Registry: Parent weapon not registered: " + parentRef )
	Assert( ItemDefined( modRef ), "[ArmoryUtil] Registry: Common mod not registered: " + modRef )

	ItemData parentItem = GetItemData( parentRef )
	ItemData commonModItem = GetItemData( modRef )

	string modType = expect string( commonModItem.i.modType )
	int weaponType = parentItem.itemType

	//	Resolve slot
	int subItemType = eItemTypes.PILOT_WEAPON_MOD3
	if ( modType == "attachment" ) {
		subItemType = eItemTypes.PILOT_PRIMARY_ATTACHMENT
	} else if ( modType == "mod" && weaponType == eItemTypes.PILOT_PRIMARY ) {
		subItemType = eItemTypes.PILOT_PRIMARY_MOD
	} else if ( modType == "mod" ) {
		subItemType = eItemTypes.PILOT_SECONDARY_MOD
	}

	//	Resolve cost
	int resolvedCost = (cost == -1) ? commonModItem.cost : cost
	if ( "xpPerLevelType" in parentItem.i ) {
		string xpType = expect string( parentItem.i.xpPerLevelType )

		if ( xpType == "sniper" ) { resolvedCost = expect int( commonModItem.i.costSniper ) }
		else if ( xpType == "pistol" ) { resolvedCost = expect int( commonModItem.i.costPistol ) }
		else if ( xpType == "antititan" ) { resolvedCost = expect int( commonModItem.i.costAT ) }
	}

	//	Populate subitem
	CreateGenericSubItemData( subItemType, parentRef, modRef, resolvedCost, {
		statDamage = statDamage,
		statRange = statRange,
		statAccuracy = statAccuracy,
		statFireRate = statFireRate,
		statClipSize = statClipSize,
	})
})}

void function ArmoryUtil_RegisterWeaponFeature(
	string parentRef, string featureRef,
	string name, string desc, asset image,
	int cost = 0, bool hidden = false,
) { data.registryQueue.append( void function() : (
	parentRef, featureRef, name, desc, image, cost, hidden
) {
	//	Define the parent feature, if not already defined
	if ( !ItemDefined( featureRef ) ) {
		ItemData featureItem = _RegisterBaseData( featureRef, eItemTypes.WEAPON_FEATURE, hidden )
		featureItem.cost = cost
		_PopulateFromArgs( featureItem, name, desc, image )
	}

	//	Populate subitem
	ItemData parentItem = GetItemData( parentRef )
	CreateGenericSubItemData( eItemTypes.WEAPON_FEATURE, parentRef, featureRef, cost )
})}

//void function ArmoryUtil_RegisterPilotExecution() {}
//void function ArmoryUtil_RegisterPilotSuit() {}

void function ArmoryUtil_RegisterTitanBase(
	string titanRef, string chassisRef,
	int cost = 0, bool hidden = false
) { data.registryQueue.append( void function() : (
	titanRef, chassisRef, cost, hidden
) {
	ItemData item = _RegisterBaseData( titanRef, eItemTypes.TITAN_CHASSIS, hidden )
	item.cost = cost
	item.hidden = hidden
})}

//void function ArmoryUtil_RegisterTitanPassive() {}
//void function ArmoryUtil_RegisterTitanPrimaryMod() {}
//void function ArmoryUtil_RegisterTitanOSVoice() {}
//void function ArmoryUtil_RegisterTitanExecution() {}

//void function ArmoryUtil_RegisterGameFeature() {}
//void function ArmoryUtil_RegisterGamePlaylist() {}

//		Re-registration
void function ArmoryUtil_RegisterMoveItem(
	string weaponRef, int newSlot
) { data.registryQueue.append( void function() : (weaponRef, newSlot) {
	//		Sanity checks
	//	Ensure the weapon exists (_items.gnut:4183)
	if ( !ItemDefined(weaponRef) ) { return }

	//	Skip if the item has already been moved
	ItemData item = GetItemData(weaponRef)	//	Retrieve item data (_items.gnut:4188)
	int oldSlot = item.itemType
	if ( oldSlot == newSlot ) { return }

	//		Functionality
	//	Fetch item ref array pointers
	array<string> oldTypeRefs = GetAllRefsOfType( oldSlot )
	array<string> newTypeRefs = GetAllRefsOfType( newSlot )

	//	Erase from oldTypeRefs
	int oldTypeIndex = oldTypeRefs.find( weaponRef )
	if( oldTypeIndex != -1 ) { oldTypeRefs.remove(oldTypeIndex) }

	//	Append to new location and update type
	oldTypeRefs.fastremovebyvalue( weaponRef )
	newTypeRefs.append( weaponRef )
	item.itemType = newSlot

	if ( "menuCategory" in item.i ) {
		string stringVal = GetWeaponInfoFileKeyField_GlobalString( weaponRef, "menu_category" )
		item.i.menuCategory = MenuCategoryStringToEnumValue( stringVal )
	}
	if ( "menuAnimClass" in item.i ) {
		string stringVal = GetWeaponInfoFileKeyField_GlobalString( weaponRef, "menu_anim_class" )
		item.i.menuAnimClass = MenuAnimClassStringToEnumValue( stringVal )
	}

	foreach ( string modRef, SubItemData subitem in item.subitems )
{
	// If moving from Primary to Secondary
	if ( newSlot == eItemTypes.PILOT_SECONDARY ) {
		if ( subitem.itemType == eItemTypes.PILOT_PRIMARY_MOD ||
			subitem.itemType == eItemTypes.PILOT_PRIMARY_ATTACHMENT
		) {
			subitem.itemType = eItemTypes.PILOT_SECONDARY_MOD
		}
	}

	else if ( newSlot == eItemTypes.PILOT_PRIMARY ) {
		if ( subitem.itemType == eItemTypes.PILOT_SECONDARY_MOD ) {
			// Note: Attachments like sights usually require a specific modType flag check,
			// but pushing them to primary mod works natively for stats
			subitem.itemType = eItemTypes.PILOT_PRIMARY_MOD
		}
	}
}

	//	Status message
	printt("[ArmoryUtil] Registry: Moved \'" +weaponRef+ "\' to slot " +newSlot)
})}