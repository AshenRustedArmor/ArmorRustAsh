/// ╔══════════════════════════════════════════════════════════════════════════════════╗
/// ║                                                                                  ║
/// ║    █████████  █████  █████  █████████  ███████████    ███████    ██████   ██████ ║
/// ║   ███░░░░░███░░███  ░░███  ███░░░░░███░█░░░███░░░█  ███░░░░░███ ░░██████ ██████  ║
/// ║  ███     ░░░  ░███   ░███ ░███    ░░░ ░   ░███  ░  ███     ░░███ ░███░█████░███  ║
/// ║ ░███          ░███   ░███ ░░█████████     ░███    ░███      ░███ ░███░░███ ░███  ║
/// ║ ░███          ░███   ░███  ░░░░░░░░███    ░███    ░███      ░███ ░███ ░░░  ░███  ║
/// ║ ░░███     ███ ░███   ░███  ███    ░███    ░███    ░░███     ███  ░███      ░███  ║
/// ║  ░░█████████  ░░████████  ░░█████████     █████    ░░░███████░   █████     █████ ║
/// ║   ░░░░░░░░░    ░░░░░░░░    ░░░░░░░░░     ░░░░░       ░░░░░░░    ░░░░░     ░░░░░  ║
/// ║                                                                                  ║
/// ╚══════════════════════════════════════════════════════════════════════════════════╝

///	============================================================================
///							Data Storage + Handling
///	============================================================================
//		Options for data retrieval
//	Maps to GetDataTable[Type] functions.
enum eColType { NULL, BOOL, INT, FLOAT, VECTOR, STRING, ASSET }

//	Decides where data comes from.
enum eParamSource { DATATABLE, ROW_INDEX, STATIC_VAL }

//		ParamBinding
//	Links a column in registry.cache to a function parameter
struct ParamBinding {
	int priority = 0

	//	Binding destination & source
	string argName	//	Parsed or given parameter name
	string colName	//	Target DataTable column name
	int _idx = -1	//	Index of retrieved column

	//	Binding data handling
	int dataType	= eColType.STRING			//	Type fetched from datatable
	int dataSource	= eParamSource.DATATABLE	//	Controls retrieval function
	var value 		= null						//	Static val or column arr

	//	Value retrieval function
	var functionref( int ) Get = null			//	Getter assigned in ProcessBake
}

//	Cached data struct
struct RPakData {
	int numRows
	table< string, int > colTypes		//	"cost" -> eColType.INT
	table< string, array<var> > data	//	"cost" -> [ 1, 2, 3 ]
}

///	============================================================================
///								Tasks Structs by Phase
///	============================================================================
//	These structs and comments (indicating calls)
// 	are organized in consecutive call order.

//	Callback: OnRegistryInit
//	Task: Infers required parameters from passed arguments
struct TaskBindings_Infer {
	int jobID
	int priority = 0

	asset rpakPath

	var target
	table overrides
}

struct BindingsTask_Static {
	int jobID
	int priority = 0

	table overrides
}

struct BindingsTask_Custom {
	int jobID
	int priority = 0

	table overrides
}

//	Task: Consumes bindings to cache data
struct TaskCache_RPakData {
    asset rpakPath
}

//	Callback: OnRegistryMutate
//	Task: Mod-accessible mutations of the cache
struct TaskMutate_Modify {
	int jobID
	int priority = 0

	void functionref( int, array<ParamBinding> ) process
}

//	Callback: OnRegistryBake
//	Task: Bakes cached data into (Sub)ItemData the game understands
struct TaskBake_ItemData {
	int jobID
	int priority = 0

	asset rpakPath	//	TODO temp fix, Bake shouldn't know about the rpaks
	var target
}

///	============================================================================
///									Global State
///	============================================================================
//	Pre-computed map for strict O(1) inference matching
table< string, ParamBinding > inferences = {}

//	Registry
struct {
	// ========== CALLBACKS ==========
	array< void functionref() > cb_OnRegistryInit
	array< void functionref() > cb_OnRegistryMutate

	// ========== QUEUES ==========
	//	Bindings Phase
	array<TaskBindings_Infer>	queueBindings_Infer

	//	Cache Phase
	array<TaskCache_RPakData>	queueCache_RPakData

	//	Mutate Phase
	array<TaskMutate_Modify>	queueMutate_Modify

	//	Bake Phase
	array<TaskBake_ItemData>	queueBake_ItemData //BakeBaseItems 	//	Order required to ensure correct inheritance

	// ========== STATE ==========
	//	Generates jobID, used to prevent collisions from multiple calls
	int jobCounter = 0

	//	Maps job ID -> array of dependent bindings
	table< int, array<ParamBinding> > funcBindings

	//	Internally assets are just a string
	//	Maps rpakPath -> array of dependent bindings
	table< asset, array<ParamBinding> > rpakBindings

	//	Maps rpakPath -> { columnName -> [ row0, row1, ... ] }
	table< asset, RPakData > cache
} registry

///	============================================================================
///								Initialization
///	============================================================================
void function InitInferenceMap() {
	//	Structural Indices
	inferences.datatableindex	<- CreateParamBinding( "",				eColType.INT,		eParamSource.ROW_INDEX )
	inferences.index			<- CreateParamBinding( "",				eColType.INT,		eParamSource.ROW_INDEX )
	inferences.rowidx			<- CreateParamBinding( "",				eColType.INT,		eParamSource.ROW_INDEX )

	//	Types & References
	inferences.itemtype			<- CreateParamBinding( "type",			eColType.STRING )
	inferences.ref				<- CreateParamBinding( "ref",			eColType.STRING )
	inferences.itemref			<- CreateParamBinding( "itemRef",		eColType.STRING )
	inferences.parentref		<- CreateParamBinding( "parentRef",		eColType.STRING )
	inferences.weaponref		<- CreateParamBinding( "weaponRef",		eColType.STRING )
	inferences.nonprimeref		<- CreateParamBinding( "nonPrimeRef",	eColType.STRING )

	//	Display Data
	inferences.name				<- CreateParamBinding( "name",			eColType.STRING )
	inferences.desc				<- CreateParamBinding( "description",	eColType.STRING )
	inferences.longdesc			<- CreateParamBinding( "description",	eColType.STRING )
	inferences.image			<- CreateParamBinding( "image",			eColType.ASSET )
	inferences.model			<- CreateParamBinding( "model",			eColType.ASSET )

	//	Stats & Booleans
	inferences.cost				<- CreateParamBinding( "cost",			eColType.INT )
	inferences.hidden			<- CreateParamBinding( "hidden",			eColType.BOOL )
	inferences.isdamagesource	<- CreateParamBinding( "damageSource",	eColType.BOOL )

	//	Special Custom Parameters
	inferences.decalindex		<- CreateParamBinding( "decalIndex",		eColType.INT )
	inferences.skinindex		<- CreateParamBinding( "skinIndex",		eColType.INT )
	inferences.skintype			<- CreateParamBinding( "skinType",		eColType.INT )
}

ParamBinding function CreateParamBinding( string colName, int dataType, int dataSource = eParamSource.DATATABLE ) {
	ParamBinding b
	b.colName = colName

	b.dataType = dataType
	b.dataSource = dataSource

	return b
}

ParamBinding function InferParamBinding( string argName ) {
	//	Clone from inference
	ParamBinding b
	string lower = argName.tolower()
	if (lower in inferences) { b = clone inferences[lower]; }

	//	Set other parameters
	b.argName = argName

	return b
}

///	============================================================================
///								Job Builders
///	============================================================================
int function Registry_BlankJob() {
	//	Generate a unique identity for this specific factory function run
    int currentJobID = registry.jobCounter
	registry.jobCounter++

	return currentJobID
}

int function Registry_RPakJob( asset rpakPath, var target, table overrides = {} ) {
    //	Generate a unique identity for this specific factory function run
    int currentJobID = registry.jobCounter
	registry.jobCounter++

    //	1. Instantiate and queue the Parameter Inference Phase
    TaskBindings_Infer inferTask
    inferTask.jobID		= currentJobID
    inferTask.rpakPath	= rpakPath
    inferTask.target	= target
    inferTask.overrides	= overrides
    registry.queueBindings_Infer.append( inferTask )

    //	2. Instantiate and queue the Data Extraction/Caching Phase
    // ProcessCache() cleanly skips already cached or un-bound RPaks, so duplicate paths are harmless
    TaskCache_RPakData TaskCache_RPakData
    TaskCache_RPakData.rpakPath		= rpakPath
    registry.queueCache_RPakData.append( TaskCache_RPakData )

    //	3. Instantiate and queue the Execution/Bake Phase
    TaskBake_ItemData bakeTask
    bakeTask.jobID		= currentJobID
    bakeTask.rpakPath	= rpakPath
    bakeTask.target		= target
    registry.queueBake_ItemData.append( bakeTask )

	//	Return the ID
	return currentJobID
}


///	============================================================================
///								Task Processing
///	============================================================================
void function RegistryBindings_ProcessInfer() {
	foreach( TaskBindings_Infer task in registry.queueBindings_Infer ) {
		//	Get function information - name, arguments, defaults
		//local targetFunc = getroottable()[task.target]
		local infos = task.target.getinfos()

		array rawArgs = expect array(infos.parameters)
		if (rawArgs.len() > 0 && rawArgs[0] == "this") { rawArgs.remove(0) }

		array rawDefs = ("defparams" in infos) ? expect array(infos.defparams) : []
		int defsIdx = rawArgs.len() - rawDefs.len()

		//	1). Create bindings
		//	Arguments cannot be seperate, .acall() requires specific order
		array<ParamBinding> fromFunc = []
		array<ParamBinding> fromTable = []
		foreach (int i, string argName in rawArgs) {
			ParamBinding b = InferParamBinding(argName)

			//	Handle optional parameters: assign STATIC_VAL and fetch default
			if (i >= defsIdx) {
				b.dataSource = eParamSource.STATIC_VAL
				b.value = rawDefs[ i - defsIdx ]
			}

			//	Handle overrides: two types, column and data override
			if (argName in task.overrides) {
				var newVal = task.overrides[argName]
				if (typeof(newVal) == "string") {
					//	Remap columns
					b.colName = expect string( newVal )
				} else {
					//	Curry function definition
					b.dataSource = eParamSource.STATIC_VAL
					b.value = newVal
				}
			}

			//	Append: all bindings depend on func, some depend on the rpak
			if (b.dataSource == eParamSource.DATATABLE) { fromTable.append(b); }
			fromFunc.append(b)
		}

		//	2). Add to registry
		//	Index/extend rpakBindings
		if( task.rpakPath in registry.rpakBindings ) {
			registry.rpakBindings[task.rpakPath].extend(fromTable)
		} else { registry.rpakBindings[task.rpakPath] <- fromTable }

		//	Index funcBindings: jobID prevents collisions from multiple calls
		registry.funcBindings[task.jobID] <- fromFunc
	}

	registry.queueBindings_Infer.clear()
}

void function RegistryCache_ProcessRPaks() {
	foreach (TaskCache_RPakData task in registry.queueCache_RPakData) {
		//		Sanity checks
		//	We shouldn't be revisiting an rpak, since bindings are grouped by rpak
		if ( task.rpakPath in registry.cache ) { continue }
		if ( !(task.rpakPath in registry.rpakBindings) ) { continue }
		print("[REGISTRY] CACHE: Caching " + task.rpakPath)

		//		Access data
		var dt = GetDataTable(task.rpakPath)
		int numRows = GetDatatableRowCount( dt )

		//		Access bindings
		//	Only the RPak-dependent bindings need to be fetched
		array<ParamBinding> bindings = registry.rpakBindings[task.rpakPath]

		//	List of columns to fetch. Deduplicate to prevent multiple access
		table< string, array<int> > colsToFetch = {}
		foreach ( ParamBinding b in bindings ) {
			string msg = "[REGISTRY] CACHE PREPASS: Column " +b.colName

			//	Skip already tracked columns
			if (b.colName in colsToFetch) {
				printt(msg + " skipped, already cached");
				continue
			}

			//	Fetch numeric index for column, log error if not found
			int colIdx = GetDataTableColumnByName( dt, b.colName )
			if (colIdx == -1) {
				printt(msg + " missing!")
				continue
			}


			//	Index into colsToFetch
			colsToFetch[b.colName] <- [colIdx, b.dataType]
			printt(msg + " added [" +colIdx+ ", " + b.dataType + "]");
		}

		//		Cache RPak data
		RPakData rpak
		rpak.numRows = numRows

		//	Extract data
		foreach (string colName, array<int> idxAndType in colsToFetch) {
			//	List initialization
			array<var> colData
			rpak.data[colName] <- colData
			colData.resize( numRows, null )

			//	Unbox & set column type
			int colIdx				= idxAndType[0]
			rpak.colTypes[colName] <- idxAndType[1]

			//	Fill the array<var> inside the RPakData. Ideally done with a
			//	lambda to prevent having to switch on the enum every time.
			var functionref( int ) DataTableGet = null
			switch( idxAndType[1] ) {
				case eColType.BOOL:   DataTableGet = var function( int row ) : (dt, colIdx) { return GetDataTableBool(dt, row, colIdx) }; break
				case eColType.INT:    DataTableGet = var function( int row ) : (dt, colIdx) { return GetDataTableInt(dt, row, colIdx) }; break
				case eColType.FLOAT:  DataTableGet = var function( int row ) : (dt, colIdx) { return GetDataTableFloat(dt, row, colIdx) }; break
				case eColType.STRING: DataTableGet = var function( int row ) : (dt, colIdx) { return GetDataTableString(dt, row, colIdx) }; break
				case eColType.ASSET:  DataTableGet = var function( int row ) : (dt, colIdx) { return GetDataTableAsset(dt, row, colIdx) }; break
			}

			//	Iterate over the column and fetch the entire thing.
			for ( int r = 0; r < numRows; r++ ) {
				colData[r] = DataTableGet(r);
				printt("[REGISTRY] CACHE PASS: colData[" +r+ "] = " +colData[r])
			}
		}

		//	Link cache to bindings
		string msg = "[REGISTRY] CACHE: Keys = ["
		foreach (k, v in rpak.data) { msg += "'"+k+"',"}
		printt(msg+"]")

		foreach (ParamBinding b in bindings) {
			if (!(b.colName in rpak.data)) {
				printt("[REGISTRY] CACHE POSTPASS: Skipping binding " + b.colName);
			    continue
			}

			array<var> colData = rpak.data[b.colName]
			b.value = colData

			printt("[REGISTRY] CACHE POSTPASS: Binding " +b.colName+ " to " + typeof(b.value));
		}

		//		Save to central state
		registry.cache[task.rpakPath] <- rpak
	}

	registry.queueCache_RPakData.clear()
}

void function RegistryMutate_ProcessModify() {	//	TODO this needs to be extensively changed to make sense
	foreach ( TaskMutate_Modify task in registry.queueMutate_Modify ) {
		// Skip if the RPak isn't in memory (another script may have caused a fault)
		if ( !(task.rpakPath in registry.cache) ) { return }
		RPakData gridData = registry.cache[task.rpakPath]

		// Pass the flat grid to the modder's custom callback
		task.process( gridData )
	}
}

void function RegistryBake_ProcessItems( array<TaskBake_ItemData> queue ) {
	foreach (TaskBake_ItemData task in queue) {
		//		Sanity checks
		//	Unbound data
		if ( !(task.jobID in registry.funcBindings) ) { continue }

		//	Uncached data
		if ( !(task.rpakPath in registry.cache) ) { continue }

		//		Extract cached data & function bindings
		RPakData rpak = registry.cache[task.rpakPath]
		array<ParamBinding> bindings = registry.funcBindings[task.jobID]
		//local targetFunc = getroottable()[task.target]

		//		Define ParamBinding.Get(n) functions
		foreach (ParamBinding b in bindings) {
			string msg = "[REGISTRY] BAKE: Baking arg " +b.argName+ " type "
			foreach( s, i in eParamSource ) { if (i == b.dataSource) { msg += s; } }
			printt(msg + " column " + b.colName)

			switch (b.dataSource) {
				case eParamSource.ROW_INDEX:	b.Get = var function( int r ) { return r; }; break;
				case eParamSource.STATIC_VAL:	b.Get = var function( int r ) : (b) { return b.value; }; break;
				case eParamSource.DATATABLE:
					printt("[REGISTRY] BAKE: Binding '" +b.colName+ "' has value type '" + typeof(b.value) + "'")
					if (b.value == null) {
						printt("[REGISTRY] BAKE: Catastrophic error, binding '" +b.colName+ "' has null value")
						break;
					}

					array arr = expect array(b.value)

					if (b.argName == "itemType") {
						b.Get = var function( int r ) : (arr) {
							string typeStr = expect string( arr[r] )
                            return (typeStr in eItemTypes) ? eItemTypes[ typeStr ] : -1
						}; break;
					}

					b.Get = var function( int r ) : (arr) { return arr[r] }; break;
			}
		}

		//		Iterate over table
		for (int r = 0; r < rpak.numRows; r++) {
			//	Squirrel '.acall()' always requires the root environment at Index 0
			array args = [ getroottable() ]

			//	Iterate over bindings
			foreach ( ParamBinding b in bindings ) { args.append(b.Get(r)); }

			string msg = "[REGISTRY] Bake: Calling with args ["
			foreach ( a in args ) { msg += a + ","}
			printt(msg + "]")

			// Fire the deferred function
			task.target.acall( args )
		}
	}
}

void function Registry_ExecutePipeline() {
    //	Phase 1: Reflect on functions, handle defaults, map overrides
    RegistryBindings_ProcessInfer()

    //	Phase 2: Deduplicate columns across all jobs, query RPak files, populate RAM cache
    RegistryCache_ProcessRPaks()

    //	Phase 3: Optional mid-pipeline modifications by other sub-mods
    RegistryMutate_ProcessModify()

    //	Phase 4: Construct argument lists and unbox data natively into the factory methods
    RegistryBake_ProcessItems( registry.queueBake_ItemData )
}


	dataTable = GetDataTable( $"datatable/pilot_weapon_mods_common.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	table<string, modCommonDef> modCommonTable

	for ( int i = 0; i < numRows; i++ ) {
		modCommonDef modCommon
		modCommon.modType = ...
		modCommon.dataTableIndex = i

		string itemRef = GetDataTableString( dataTable, i, PILOT_WEAPON_MOD_COMMON_COLUMN )
		modCommonTable[ itemRef ] <- modCommon

		ItemData modCommonData
		if ( modCommon.modType == "attachment" ) { modCommonData = CreateBaseItemData( eItemTypes.SUB_PILOT_WEAPON_ATTACHMENT, itemRef, false ) }
		else { modCommonData = CreateBaseItemData( eItemTypes.SUB_PILOT_WEAPON_MOD, itemRef, false ) }

		modCommonData.name = ...
	}

	dataTable = GetDataTable( $"datatable/pilot_weapon_mods.rpak" )
	numRows = GetDatatableRowCount( dataTable )
	var weaponTable = GetDataTable( $"datatable/pilot_weapons.rpak" )
	for ( int i = 0; i < numRows; i++ )
	{
		string mod = ...

		int cost
		string xpPerLevelType = GetDataTableString( weaponTable, typeRow, GetDataTableColumnByName( weaponTable, "xpPerLevelType" ) )
		switch ( xpPerLevelType ) {
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