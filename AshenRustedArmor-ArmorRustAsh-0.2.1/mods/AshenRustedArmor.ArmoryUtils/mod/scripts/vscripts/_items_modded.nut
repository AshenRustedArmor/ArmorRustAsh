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
	int priority = -1

	//	Binding destination & source
	string argName	//	Parsed or given parameter name
	string colName	//	Target DataTable column name

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
struct TaskBindings_Factory {
	int jobID
	int priority = 0

	asset rpakPath
	var target
	table overrides
}

struct TaskBindings_Mutator {
	int jobID
	int priority = 0

	var target
	table rpak2args
}

struct TaskBindings_Blueprint {
	int jobID
	asset rpakPath

	array<string> rawArgs
	array<var> rawDefs
	int defsIdx

	table overrides

	array<ParamBinding> destArray
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

	var target
}

struct TaskMutate_Generate {
	int jobID
	int priority = 0

	var target
}

//	Callback: OnRegistryBake
//	Task: Bakes cached data into (Sub)ItemData the game understands
struct TaskBake_ItemData {
	int jobID
	int priority = 0

	asset rpakPath	//	TODO temp fix, Bake shouldn't know about the rpaks
	var target
}

int function PrioritySortComparator( a, b ) {
    return expect int(b.priority - a.priority)
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
	array<TaskBindings_Factory>	queueBindings_Factory
	array<TaskBindings_Mutator>	queueBindings_Mutator
	array<TaskBindings_Blueprint> queueBindings_Blueprint

	//	Cache Phase
	array<TaskCache_RPakData>	queueCache_RPakData

	//	Mutate Phase
	array<TaskMutate_Modify>	queueMutate_Modify
	array<TaskMutate_Generate>	queueMutate_Generate

	//	Bake Phase
	array<TaskBake_ItemData>	queueBake_ItemData //BakeBaseItems 	//	Order required to ensure correct inheritance

	// ========== STATE ==========
	//	Generates jobID, used to prevent collisions from multiple calls
	int jobCounter = 0

	//	Maps job ID -> array of dependent bindings
	table< int, array<ParamBinding> > funcBindings
	table< int, array<ParamBinding> > mut8Bindings

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
	inferences.hidden			<- CreateParamBinding( "hidden",		eColType.BOOL )
	inferences.isdamagesource	<- CreateParamBinding( "damageSource",	eColType.BOOL )

	//	Special Custom Parameters
	inferences.decalindex		<- CreateParamBinding( "decalIndex",	eColType.INT )
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
	else {
	    b.colName = argName;
	}

	//	We can always assume the argName is the passed value, override later
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
    TaskBindings_Factory inferTask
    inferTask.jobID		= currentJobID
    inferTask.rpakPath	= rpakPath
    inferTask.target	= target
    inferTask.overrides	= overrides
    registry.queueBindings_Factory.append( inferTask )

    //	2. Instantiate and queue the Data Extraction/Caching Phase
    // ProcessCache() cleanly skips already cached or un-bound RPaks, so duplicate paths are harmless
    TaskCache_RPakData cacheTask
    cacheTask.rpakPath	= rpakPath
    registry.queueCache_RPakData.append( cacheTask )

    //	3. Instantiate and queue the Execution/Bake Phase
    TaskBake_ItemData bakeTask
    bakeTask.jobID		= currentJobID
    bakeTask.rpakPath	= rpakPath
    bakeTask.target		= target
    registry.queueBake_ItemData.append( bakeTask )

	//	Return the ID
	return currentJobID
}

//  Attaches an in-place modifier (filtering/editing) to a job
void function Registry_ModifyJob( int jobID, int priority, var target, table rpak2args = {} ) {
	//	1. Instantiate and queue the Parameter Inference Phase
    TaskBindings_Mutator bindTask
    bindTask.jobID		= jobID
	bindTask.priority	= priority

    bindTask.target		= target
    bindTask.rpak2args	= rpak2args

	registry.queueBindings_Mutator.append( bindTask )

	//	2. Instantiate and queue the Mutation Phase
	// skdlhg;ak.sjdhg lakdfjg
	TaskMutate_Modify modifyTask
	modifyTask.jobID	= jobID
	modifyTask.priority = priority
	modifyTask.target	= target

	registry.queueMutate_Modify.append( modifyTask )
}

///	============================================================================
///								Task Processing
///	============================================================================
void function Registry_ProcessBindings() {
	table<int, asset> job2rpak = {}

	//		Inferred bindings
	foreach (TaskBindings_Factory task in registry.queueBindings_Factory) {
		//		Sanity Checks
		//	Preemptive null check for safety
		if (task.target == null) {
			printt("REGISTRY [BIND]: WARNING: task.target == null")
			continue
		}

		/// =========== Functionality ===========
		TaskBindings_Blueprint bp
		bp.jobID	= task.jobID
		bp.rpakPath	= task.rpakPath

		job2rpak[task.jobID] <- task.rpakPath

		//	Get function information - name, arguments, defaults
		local infos = task.target.getinfos()

		array rawArgs = expect array(infos.parameters)
		foreach( a in rawArgs ) { bp.rawArgs.append(expect string(a)); }
		if (bp.rawArgs.len() > 0 && bp.rawArgs[0] == "this") { bp.rawArgs.remove(0) }

		array rawDefs = ("defparams" in infos) ? expect array(infos.defparams) : []
		foreach( d in rawDefs ) { bp.rawDefs.append(expect string(d)); }
		bp.defsIdx = bp.rawArgs.len() - bp.rawDefs.len()

		//	Overrides / etc
		bp.overrides = task.overrides

		//	Initialize global env and give the bp a reference
		if(!(task.jobID in registry.funcBindings)) {
			registry.funcBindings[task.jobID] <- []
		}
		bp.destArray = registry.funcBindings[task.jobID]
		registry.queueBindings_Blueprint.append(bp)
	}

	//		Mutator bindings
	foreach (TaskBindings_Mutator task in registry.queueBindings_Mutator) {
		/// =========== Functionality ===========
		TaskBindings_Blueprint bp
		bp.jobID = task.jobID

		if (task.jobID in job2rpak) {
			bp.rpakPath = job2rpak[task.jobID]
		}

		//	Get function information - name, arguments, defaults
		local infos = task.target.getinfos()

		array rawArgs = expect array(infos.parameters)
		foreach( a in rawArgs ) { bp.rawArgs.append(expect string(a)); }
		if (bp.rawArgs.len() > 0 && bp.rawArgs[0] == "this") { bp.rawArgs.remove(0) }

		array rawDefs = ("defparams" in infos) ? expect array(infos.defparams) : []
		foreach( d in rawDefs ) { bp.rawDefs.append(expect string(d)); }
		bp.defsIdx = bp.rawArgs.len() - bp.rawDefs.len()

		//	2). Iterate over the args
		bp.overrides = {}
		foreach (var key, var args in task.rpak2args) { switch (typeof(key)) {
			case "asset":
				bp.rpakPath = expect asset(key)
				foreach (string arg in expect array(args)) { bp.overrides[arg] <- arg }
				break;

			case "string":
				bp.overrides[expect string(key)] <- args
				break;

			default:
				throw "REGISTRY [BIND]: ERROR: Job " + task.jobID +
					" specified invalid key type '" + typeof(key) +
					"'. Expected asset, string, or tuple."
				break;
		}}

		if (!(task.jobID in registry.mut8Bindings)) {
			registry.mut8Bindings[task.jobID] <- []
		}
		bp.destArray = registry.mut8Bindings[task.jobID]
		registry.queueBindings_Blueprint.append(bp)
	}

	//		Blueprints
	foreach (TaskBindings_Blueprint task in registry.queueBindings_Blueprint) {
		foreach (string key, var val in task.overrides) {
			bool isValid = false
			foreach( string argName in task.rawArgs) {
				isValid = (argName == key) || isValid
			}

			if (!isValid) {
				throw "REGISTRY [BIND]: ERROR: Job " + task.jobID +
					" override '" + key + "' invalid: target lacks this param"
			}
		}
		//	1). Create bindings
		//	Arguments cannot be seperate, .acall() requires specific order
		array<ParamBinding> fromFunc = task.destArray
		array<ParamBinding> fromTable = []
		foreach (int i, string argName in task.rawArgs) {
			ParamBinding b = InferParamBinding(argName)

			//	Handle optional parameters: assign STATIC_VAL and fetch default
			if (i >= task.defsIdx) {
				b.dataSource = eParamSource.STATIC_VAL
				b.value = task.rawDefs[ i - task.defsIdx ]
			}

			//	Handle overrides: column, type, and data override
			if (argName in task.overrides) {
				var newVal = task.overrides[argName]
				switch (typeof(newVal)) {
					case "array":
						array arr = expect array(newVal)
						b.colName = argName

						//	Column type override
						b.dataType = expect int(arr[0])

						//	Column name override
						if (arr.len()< 2) { break; }
						b.colName = expect string(arr[1])
						break;
					case "string":
						//b.dataSource = eParamSource.DATATABLE
						b.colName = expect string(newVal)
						break;
					default:
						b.dataSource = eParamSource.STATIC_VAL
						b.value = newVal
						break;
				}
			}

			//	Append: all bindings depend on func, some depend on the rpak
			if (b.dataSource == eParamSource.DATATABLE) {
				if (b.colName == "") {
					throw "REGISTRY [BIND]: ERROR: Job " +
						task.jobID + " param '" + argName +
						"' cannot be inferred from '" + task.rpakPath +
						"'. Missing override?"
				}

				fromTable.append(b)
			}

			fromFunc.append(b)
		}

		//	2). Initialize get functions
		//	This was initially done in the Bake phase, but has been moved here
		//	to allow the Mutate phase to access the Get functions. 'fromFunc'
		//	contains all bindings, so only this needs to be mapped over.
		string logStr = ""
		foreach (ParamBinding b in fromFunc) {
			logStr += b.argName + ", "
			switch (b.dataSource) {
				case eParamSource.ROW_INDEX:	b.Get = var function( int r ) { return r; }; break;
				case eParamSource.STATIC_VAL:	b.Get = var function( int r ) : (b) { return b.value; }; break;
				case eParamSource.DATATABLE:
					if (b.argName == "itemType") { b.Get = var function( int r ) : (b, task, logStr) {
						if (b.value == null) {
							printt("REGISTRY [BIND]: Processing job " + task.jobID + " encountered error | Log: [" + logStr + "]")
							throw "REGISTRY [BIND]: Crashed on job " +
								task.jobID + ", parameter '" +
								b.colName + "' has null value"
						}

						array arr = expect array(b.value)
						string typeStr = expect string( arr[r] )
						return (typeStr in eItemTypes) ? eItemTypes[ typeStr ] : "PIPELINE_SKIP"
					}; break; }

					b.Get = var function( int r ) : (b, task, logStr) {
						if (b.value == null) {
							printt("REGISTRY [BIND]: Processing job " + task.jobID + " encountered error | Log: [" + logStr + "]")
							throw "REGISTRY [BIND]: Crashed on job " +
								task.jobID + ", parameter '" +
								b.colName + "' has null value"
						}
						return (expect array(b.value))[r]
					}; break;
			}
		}
		printt("REGISTRY [BIND]: Setting getters for job " + task.jobID + " | Log: [" + logStr + "]")

		//	3). Add to registry
		//	Index/extend rpakBindings
		if( task.rpakPath in registry.rpakBindings ) {
			registry.rpakBindings[task.rpakPath].extend(fromTable)
		} else { registry.rpakBindings[task.rpakPath] <- fromTable }
	}

	//		Clear queues
	registry.queueBindings_Mutator.clear()
	registry.queueBindings_Factory.clear()
}

void function Registry_ProcessCache() {
	//		RPakData caching
	foreach (TaskCache_RPakData task in registry.queueCache_RPakData) {
		//		Sanity checks
		//	We shouldn't be revisiting an rpak, since bindings are grouped by rpak
		if ( !(task.rpakPath in registry.rpakBindings) ) { continue }

		//		Cache Hit
		if ( task.rpakPath in registry.cache ) {
			RPakData rpak = registry.cache[task.rpakPath]
			foreach ( ParamBinding b in registry.rpakBindings[task.rpakPath] ) {
				if ( b.value == null && b.colName in rpak.data ) {
					b.value = rpak.data[ b.colName ]
				}
			}

			continue
		}

		//		Cache miss
		//	Access data from disk
		var dt = GetDataTable(task.rpakPath)
		int numRows = GetDatatableRowCount( dt )

		string log = "REGISTRY [CCH0]: " + task.rpakPath + "\"#["

		//	Access bindings
		// Only the RPak-dependent bindings need to be fetched
		// Deduplicate columns to prevent multiple access
		array<ParamBinding> bindings = registry.rpakBindings[task.rpakPath]
		table< string, array<int> > colsToFetch = {}
		foreach ( ParamBinding b in bindings ) {
			log += "\"" + b.colName + "\""

			//	Skip already tracked columns
			if (b.colName in colsToFetch) { log += " (skipped), "; continue; }

			//	Fetch numeric index for column, throw error if not found
			int colIdx = GetDataTableColumnByName( dt, b.colName )
			if (colIdx == -1) {
				throw "REGISTRY [CCH0]: ERROR: " + task.rpakPath + "#\"" + b.colName + "\" does not exist"
			}

			//	Index into colsToFetch
			colsToFetch[b.colName] <- [colIdx, b.dataType]
			log += " (" + colIdx + ", " + b.dataType + "), "
		}
		printt(log + "\b\b]")

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
			}
		}

		//	Link cache to bindings
		foreach (ParamBinding b in bindings) {
			if (!(b.colName in rpak.data)) { continue; }
			b.value = rpak.data[b.colName]
		}

		//		Save to central state
		registry.cache[task.rpakPath] <- rpak
		printt("REGISTRY [CCH1]: Cached asset grid for RPak: " + task.rpakPath + "\" (" + numRows + " rows)")
	}

	//		Clear queues
	registry.queueCache_RPakData.clear()
}

void function Registry_ProcessMutate() {
	foreach ( TaskMutate_Modify task in registry.queueMutate_Modify ) {
		if (!(task.jobID in registry.mut8Bindings)) { continue; }

		array<ParamBinding> bindings = registry.mut8Bindings[ task.jobID ]

		int numRows = 0
		string logStr = ""
		foreach ( ParamBinding b in bindings ) {
			//	Validate value state before calling with parameters
			if (b.dataSource == eParamSource.DATATABLE) {
				if (b.value == null) {
					printt("REGISTRY [MUT8]: Error on job " + task.jobID + " | Log: [" + logStr + "]")
					throw "REGISTRY [MUT8]: Job " + task.jobID + " param '" + b.argName + "' has unresolved data binding."
				}

				if (numRows == 0) { numRows = (expect array( b.value )).len(); }
			}


			if (b.Get == null) {
				throw "REGISTRY [MUT8]: ERROR: Job " + task.jobID +
					" aborted: Getter for parameter '" +
					b.argName + "' resolved to null."
			}


			logStr += b.argName + ": " + typeof( b.value ) + ", "
		}

		//	Skip if there's nothing to mutate
		if (numRows == 0) { continue; }
		printt( "REGISTRY [MUT8]: Executing job " + task.jobID + " | Input Schema: ( " + logStr + ")" )

		for (int r = 0; r < numRows; r++) {
			array args = [ getroottable() ]

			bool skipRow = false
			foreach (ParamBinding b in bindings) {
				if ( b.Get == null ) {
					throw "REGISTRY [BAKE]: ERROR: Job " + task.jobID +
						" row " + r + " aborted: Getter for parameter '" +
						b.argName + "' resolved to null."
				}

				if (typeof(val)=="string" && val == "PIPELINE_SKIP") { skipRow = true; break; }
				args.append( b.Get(r) )
			}

			if (skipRow) { continue; }
			var result = task.target.acall(args)

			if (result == null || typeof(result) != "table") { throw "REGISTRY [MUT8]: Job " +
				task.jobID + " row " + r + " returned '" + typeof(result) + "', expected table"
			}

			table resTable = expect table( result )
			foreach (ParamBinding b in bindings) {
				if ( b.dataSource == eParamSource.DATATABLE && (b.argName in resTable) ) {
					(expect array(b.value))[r] = resTable[b.argName]
				}
			}
		}
	}

	//		Clear queues
	registry.queueMutate_Modify.clear()
}

void function Registry_ProcessBake( array<TaskBake_ItemData> queue ) {
	//		ItemData baking
	foreach (TaskBake_ItemData task in queue) {
		//		Sanity checks
		//	Unbound data
		if ( !(task.jobID in registry.funcBindings) ) { continue }

		//	Uncached data
		if ( !(task.rpakPath in registry.cache) ) { continue }

		//		Extract cached data & function bindings
		RPakData rpak = registry.cache[task.rpakPath]
		array<ParamBinding> bindings = registry.funcBindings[task.jobID]
		string log = ""

		//		Iterate over table
		for (int r = 0; r < rpak.numRows; r++) {
			//	Squirrel '.acall()' always requires the root environment at Index 0
			array args = [ getroottable() ]

			//	Iterate over bindings
			bool skipRow = false
			foreach ( ParamBinding b in bindings ) {
				if ( b.Get == null ) {
					throw "REGISTRY [BAKE]: ERROR: Job " + task.jobID +
						" row " + r + " aborted: Getter for parameter '" +
						b.argName + "' resolved to null."
				}

				var val = b.Get(r)
				if (typeof(val)=="string" && val == "PIPELINE_SKIP") { skipRow = true; break; }
				args.append(val)
			}

			// Fire the deferred function
			if (skipRow) { continue; }
			task.target.acall( args )
		}
	}

	//		Clear queues
	registry.queueBake_ItemData.clear()
}

void function Registry_ExecutePipeline() {
    //	Phase 1: Reflect on functions, handle defaults, map overrides
	registry.queueBindings_Factory.sort( PrioritySortComparator )
    Registry_ProcessBindings()

    //	Phase 2: Deduplicate columns across all jobs, query RPak files, populate RAM cache
    Registry_ProcessCache()

    //	Phase 3: Optional mid-pipeline modifications by other sub-mods
	registry.queueMutate_Modify.sort( PrioritySortComparator )
    Registry_ProcessMutate()

    //	Phase 4: Construct argument lists and unbox data natively into the factory methods
	registry.queueBake_ItemData.sort( PrioritySortComparator )
    Registry_ProcessBake( registry.queueBake_ItemData )
}

/// ╔═════════════════════════════════════════════════════════════════════════════════════════╗
/// ║                                                                                         ║
/// ║  █████   █████   █████████   ██████   █████ █████ █████       █████         █████████   ║
/// ║ ░░███   ░░███   ███░░░░░███ ░░██████ ░░███ ░░███ ░░███       ░░███         ███░░░░░███  ║
/// ║  ░███    ░███  ░███    ░███  ░███░███ ░███  ░███  ░███        ░███        ░███    ░███  ║
/// ║  ░███    ░███  ░███████████  ░███░░███░███  ░███  ░███        ░███        ░███████████  ║
/// ║  ░░███   ███   ░███░░░░░███  ░███ ░░██████  ░███  ░███        ░███        ░███░░░░░███  ║
/// ║   ░░░█████░    ░███    ░███  ░███  ░░█████  ░███  ░███      █ ░███      █ ░███    ░███  ║
/// ║     ░░███      █████   █████ █████  ░░█████ █████ ███████████ ███████████ █████   █████ ║
/// ║      ░░░      ░░░░░   ░░░░░ ░░░░░    ░░░░░ ░░░░░ ░░░░░░░░░░░ ░░░░░░░░░░░ ░░░░░   ░░░░░  ║
/// ║                                                                                         ║
/// ╚═════════════════════════════════════════════════════════════════════════════════════════╝