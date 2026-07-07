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

// struct PriorityTask {
// 	int jobID
// 	int priority = 0

// 	var data
// }

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
	registry.queueBindings_Factory.clear()
	registry.queueBindings_Mutator.clear()
	registry.queueBindings_Blueprint.clear()

	registry.queueCache_RPakData.clear()

	registry.queueMutate_Modify.clear()
	registry.queueMutate_Generate.clear()

	registry.queueBake_ItemData.clear()


	registry.jobCounter = 0
	registry.funcBindings.clear()
	registry.mut8Bindings.clear()
	registry.rpakBindings.clear()

	registry.cache.clear()

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

				if (typeof(b.value)=="string" && b.value == "PIPELINE_SKIP") { skipRow = true; break; }
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
//	registry.queueBindings_Factory.sort( PrioritySortComparator )
	Registry_ProcessBindings()

	//	Phase 2: Deduplicate columns across all jobs, query RPak files, populate RAM cache
	Registry_ProcessCache()

	//	Phase 3: Optional mid-pipeline modifications by other sub-mods
//	registry.queueMutate_Modify.sort( PrioritySortComparator )
	Registry_ProcessMutate()

	//	Phase 4: Construct argument lists and unbox data natively into the factory methods
//	registry.queueBake_ItemData.sort( PrioritySortComparator )
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
	InitInferenceMap()

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


	Registry_RPakJob( $"datatable/pilot_abilities.rpak", ArmoryUtils_ClosureBox(CreateWeaponData), {
		ref="itemRef"})

	// dataTable = GetDataTable( $"datatable/pilot_abilities.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string itemRef = GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "itemRef" ) )
	// 	int itemType = eItemTypes[ GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) ) ]
	// 	bool isDamageSource = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "damageSource" ) )
	// 	bool hidden = GetDataTableBool( dataTable, i, GetDataTableColumnByName( dataTable, "hidden" ) )
	// 	int cost = GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

	// 	CreateWeaponData( i, itemType, hidden, itemRef, isDamageSource, cost )
	// }

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
	Registry_RPakJob( $"datatable/pilot_passives.rpak", ArmoryUtils_ClosureBox(CreatePassiveData), {
		ref="passive" })

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
	Registry_RPakJob( $"datatable/pilot_properties.rpak", ArmoryUtils_ClosureBox(CreatePilotSuitData), {
		ref="type", itemType=eItemTypes.PILOT_SUIT })


	// dataTable = GetDataTable( $"datatable/pilot_properties.rpak" )
	// numRows = GetDatatableRowCount( dataTable )
	// for ( int i = 0; i < numRows; i++ )
	// {
	// 	string itemRef	= GetDataTableString( dataTable, i, GetDataTableColumnByName( dataTable, "type" ) )
	// 	asset image		= GetDataTableAsset( dataTable, i, GetDataTableColumnByName( dataTable, "image" ) )
	// 	int cost		= GetDataTableInt( dataTable, i, GetDataTableColumnByName( dataTable, "cost" ) )

	// 	CreatePilotSuitData( i, eItemTypes.PILOT_SUIT, itemRef, image, cost )
	// }

	CreateBaseItemData( eItemTypes.RACE, "race_human_male", false )
	CreateBaseItemData( eItemTypes.RACE, "race_human_female", false )

	//	Executions
	int jobID = 0
	var FilterDisabledRef = ArmoryUtils_ClosureBox(table function( string ref, bool hidden ) {
		return { hidden = hidden || IsDisabledRef(ref) }
	})

	jobID = Registry_RPakJob( $"datatable/pilot_executions.rpak", ArmoryUtils_ClosureBox(CreatePassiveData), {
		itemType=eItemTypes.PILOT_EXECUTION })
	Registry_ModifyJob( jobID, 0, FilterDisabledRef, {ref = "ref", hidden = "hidden"})

	jobID = Registry_RPakJob( $"datatable/titan_executions.rpak", ArmoryUtils_ClosureBox(CreateTitanExecutionData), {
		reqPrime = [ eColType.BOOL ] })
	Registry_ModifyJob( jobID, 0, FilterDisabledRef, {ref = "ref", hidden = "hidden"})


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
	// ///////////////////

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

	Registry_RPakJob( $"datatable/features_mp.rpak", CreateMpFeature, {featureIcon = [eColType.ASSET]})
	Registry_RPakJob( $"datatable/playlist_items.rpak", CreatePlaylistItem, {image = [eColType.ASSET]})

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

	// Registry_RPakJob( $"datatable/pilot_weapon_features.rpak", ArmoryUtils_ClosureBox(CreateGenericItem), {
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
	// FACTION DATA
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
	// Registry_RPakJob( $"datatable/faction_leaders.rpak", CreateFaction )

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

	// ///////////////////
	// TITAN PASSIVE DATA
	// ///////////////////

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
	}

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
	// 	int dataTableIndex, int itemType, string ref, string name, asset image, int cost
	// ) {
	// 	CreateGenericItem( dataTableIndex, itemType, ref, name, "", "", image, cost, false )
	// 	GetItemData( ref ).imageAtlas = IMAGE_ATLAS_CALLINGCARD
	// })

	// var PlayerProfileValidate = ArmoryUtils_ClosureBox(table function( string ref, int cost, bool isHidden ) {
	// 	return { ref = IsDisabledRef(ref) ? "PIPELINE_SKIP" : ref, isHidden = (cost < 0), cost = max(cost, 0) }
	// })

	// jobID = Registry_RPakJob( $"datatable/calling_cards.rpak", PlayerProfileCreate, {
	// 	itemType = eItemTypes.CALLING_CARD, ref = CALLING_CARD_REF_COLUMN_NAME, image = [eColType.ASSET] })
	// Registry_ModifyJob( jobID, 0, PlayerProfileValidate, {ref = CALLING_CARD_REF_COLUMN_NAME})

	// jobID = Registry_RPakJob( $"datatable/callsign_icons.rpak", PlayerProfileCreate, {
	// 	itemType = eItemTypes.CALLSIGN_ICON, ref = CALLSIGN_ICON_REF_COLUMN_NAME, image = [eColType.ASSET] })
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
	}

	//		Execute
	Registry_ExecutePipeline()

	InitRandomUnlocks()

	SetupFrontierDefenseItems()

	InitUnlocks()

	foreach ( item in file.itemData )
	{
		if ( item.persistenceStruct != "" )
			file.itemsWithPersistenceStruct[ item.persistenceStruct ] <- item
	}

	// northstar hook: custom item registrations
	foreach ( void functionref() callback in file.itemRegistrationCallbacks )
		callback()

	//	More unmodded stuff
}