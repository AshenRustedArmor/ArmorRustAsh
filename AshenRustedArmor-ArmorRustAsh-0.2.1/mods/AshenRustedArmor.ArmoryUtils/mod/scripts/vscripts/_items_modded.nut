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
/*	Brief regex tangent that I'm proud of
Match:		const string (LOG|ERR|LOG_WARN)_(BIND|CCH|MUT|BAKE)_([\w|_]*?)(?:\s*)=\s"REGISTRY \[.*\]:\s(?:(?:ERROR|WARNING):\s)?(.*?)"
Replace:	const string $2_$1_$3\t\t\t= "$4"

Match:		const string (BIND|CCH|MUT|BAKE)_LOG(.*?\s\|\s Log:\[\%s\])
Replace:	const string $1_INFO
*/


///	===========================================================================
///							Error Formatting + Text
///	===========================================================================
//		Text definitions
//	General
const string PHASE_THROW					= "REGISTRY [%s] %s: %s"
const string PHASE_DUMP						= "Task '%s' encountered error | Log: $s"	//"[%s]"

//	INFER Phase
const string INFER_WARN_NULL				= "b.value != null"
const string INFER_INFO_GETTER_SET			= "Setting getters for Task '%s' | Log: $s"	//"[%s]

const string INFER_ERROR_OVERRIDE_INV		= "Task '%s' override '%s' invalid: target lacks this param"
const string INFER_ERROR_VALUE_NULL			= "Task '%s' crashed, argument '%s' has null value"

//	CACHE Phase
const string CACHE_MISC_RPAK_INDEX			= "%s#[%s]"

const string CACHE_INFO_CACHED				= "Task '%s' cached RPak %s (%d rows)"
const string CACHE_ERROR_NO_COLUMN			= "Task '%s' requested %s#\"%s\" which does not exist"

const string CACHE_ERROR_BAD_TASK			= "Requested task '%s', which does not exist"
const string CACHE_ERROR_INFERENCE_FAIL		= "Task '%s' argument '%s' cannot be inferred from '%s'. Missing override?"

//	PATCH Phase
const string PATCH_INFO_VALIDATED_BINDS		= "Mutator '%s' bindings validated | Log: $s"	//"[%s]"
const string PATCH_INFO_NO_DATA				= "Mutator '%s' has no data, skipping"

const string PATCH_INFO_ERROR				= "Task '%s' | Log: $s"	//"[%s]"

const string PATCH_ERROR_BIND_UNRESOLVED	= "Mutator '%s' argument '%s' has unresolved data binding."
const string PATCH_ERROR_GETTER_NULL		= "Mutator '%s' aborted: Getter for argument '%s' resolved to null."
const string PATCH_ERROR_BIND_MISSING		= "Mutator '%s' missing data binding for requested mutator param '%s'"
const string PATCH_ERROR_EXPECTED_TABLE		= "Mutator '%s' row %d returned '%s', expected table"

const string PATCH_ERROR_GEN_EXP_ARRAY		= "Generator '%s' expected array of tables, got %s"
const string PATCH_ERROR_GEN_ROW_ARRAY		= "Generator '%s' row %d expected array of tables, got %s"

//	BUILD Phase
const string BUILD_ERROR_GETTER_NULL		= "Factory '%s' row %d aborted: Getter for argument '%s' resolved to null."

///	===========================================================================
///							Data Storage + Handling
///	===========================================================================
//		Options for data retrieval
//	Maps to GetDataTable[Type] functions, allowing typed retrieval
enum eColType { NULL, BOOL, INT, FLOAT, VECTOR, STRING, ASSET }

//	Declares where data comes from, allowing pregeneration of getters
enum eParamSource { DATATABLE, ROW_INDEX, STATIC_VAL, GENERATED }

//		ParamBinding
//	Links a column in registry.cache to a function parameter
struct ParamBinding {
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

//		Cached data
struct RPakData {
	int numRows
	table< string, int > colTypes		//	"cost" -> eColType.INT
	table< string, array<var> > data	//	"cost" -> [ 1, 2, 3 ]
}

///	===========================================================================
///								Tasks Structs by Phase
///	===========================================================================
//		Task Handling
//	Necessary to extract internal task data, differentiate between target funcs
enum eTaskType { FACTORY, MUTATOR, GENERATOR, DATATABLE }

///	=== INFER PHASE ===========================================================
//		Function binding
//	Binds an arbitrary function, type of which is defined by eTaskType. This
//	replaces TaskInfer_Factory, TaskInfer_Mutator, etc.
struct TaskInfer_Function {
	string name
	int taskType

	var target
}

//	Intermediate representation for parameter extraction.
struct TaskInfer_Blueprint {
	string name

	//	Extracted functionality from the target
	array<string> rawArgs
	array<var> rawDefs
	int defsIdx

	//	Destination array used to build parameters
	array<ParamBinding> destArray
}

///	=== CACHE PHASE ===========================================================
//		Data binding
//	Applies overrides to datatable columns / argument values
struct TaskCache_BindData {
	string name

	asset rpakPath
	table overrides
}

//	Creates bindings for RPakData, including column + static overrides
struct TaskCache_BindRPak {
	string name

	asset rpakPath
	table overrides
}

//	Creates / manages bindings for generated data, very WIP. TODO
struct TaskCache_Generated {
	string name

	array<string> argNames
	table overrides
}


//	Consumes bindings to cache data from RPaks
// struct TaskCache_BindRPak {
// 	int jobID

// 	asset rpakPath
// }

///	=== PATCH PHASE ===========================================================
//	Ordered tasks with an internal data struct. Necessary for the Mutate phase
//	where order-of-execution matters a great deal
struct TaskOrdered {
	string name
	int taskType

	var i
}

//	Mutate the cache with "table functionref target( ... )"
struct TaskPatchMutate {
	var target
}

//	Generate new data, very WIP. TODO
struct TaskPatchGenerate {
	var target
	// some other stuff too...
}

///	=== BUILD PHASE ===========================================================
//	Bakes cached data into (Sub)ItemData the game understands
struct TaskBuild_ItemData {
	string name
	var target
}

///	============================================================================
///									Global State
///	============================================================================
//	Pre-computed map for strict O(1) inference matching
table< string, ParamBinding > inferences = {}

//	Registry
struct {
	table logger = {}
	int topoID = -1

	/// === CALLBACKS =========================================================
//	array< void functionref() > cb_OnRegistryInit
//	array< void functionref() > cb_OnRegistryMutate

	/// === QUEUES ============================================================
	//	Bindings Phase
	array<TaskInfer_Function>	queueInfer_Function
	array<TaskInfer_Blueprint>	queueInfer_Blueprint

	//	Cache Phase
	array<TaskCache_BindData>	queueCache_BindData
	array<TaskCache_BindRPak>	queueCache_BindRPak

	//	Mutate Phase
	array<TaskOrdered>			queuePatchAllTasks

	//	Bake Phase
	array<TaskBuild_ItemData>	queueBuild_ItemData //BakeBaseItems 	//	Order required to ensure correct inheritance

	/// === BINDINGS ==========================================================
	//	Appends nubmers to name to prevent collisions from multiple calls
	table< string, int > taskCounter

	//	Maps task name -> array of dependent bindings
	table< string, array<ParamBinding> > allBindings

	table< string, array<ParamBinding> > facBindings
	table< string, array<ParamBinding> > mutBindings
	table< string, array<ParamBinding> > genBindings

//	table< string, array<ParamBinding> > jobBindings

	//	Internally assets are just a string
	//	Maps rpakPath -> array of dependent bindings
	table< asset, array<ParamBinding> > rpakBindings

	/// === CACHE =============================================================
	//	Maps rpakPath -> { columnName -> [ row0, row1, ... ] }
	table< asset, RPakData > cache


} registry

///	============================================================================
///								Initialization
///	============================================================================
void function RegistryPipelineInit() {
	//		Reset state
	registry.logger = ArmoryUtil_CreateLogger()
	registry.logger.SetPhase("INIT")

	registry.topoID = Topo_Create()

	//	Clear queues
	registry.queueInfer_Function.clear()
	registry.queueInfer_Blueprint.clear()

	registry.queueCache_BindData.clear()
	registry.queueCache_BindRPak.clear()

	registry.queuePatchAllTasks.clear()

	registry.queueBuild_ItemData.clear()

	//	Reset bindings
	registry.taskCounter = {}

	registry.facBindings.clear()
	registry.mutBindings.clear()
	registry.genBindings.clear()

	//	Clear cache
	registry.cache.clear()

	//		Init inference map
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

///	===========================================================================
///								Job Builders
///	===========================================================================
TaskInfer_Blueprint function Registry_ReflectFunc( var target ) {
	TaskInfer_Blueprint bp

	local infos = target.getinfos()

	array rawArgs = expect array(infos.parameters)
	foreach( a in rawArgs ) { bp.rawArgs.append(expect string(a)); }
	if (bp.rawArgs.len() > 0 && bp.rawArgs[0] == "this") { bp.rawArgs.remove(0) }

	array rawDefs = ("defparams" in infos) ? expect array(infos.defparams) : []
	foreach( d in rawDefs ) { bp.rawDefs.append(expect string(d)); }
	bp.defsIdx = bp.rawArgs.len() - bp.rawDefs.len()

	return bp
}

void function Registry_InferFunction(
	var target, int taskType, string taskName,
	array<string> before = [], array<string> after = []
) {
	//		Allow developers to enter a sequence of tasks w/o duplicated args
	//	Check to registry to see if this is a repeat name
	int taskNum = 0
	if (taskName in registry.taskCounter) {
		taskNum = registry.taskCounter[taskName]

		string prevName = format("%s_%3d", taskName, taskNum-1)
		before.append(prevName)
	} else { registry.taskCounter[taskName] <- taskNum }
	registry.taskCounter[taskName] ++

	//	Adjust name
	string currName = format("%s_%3d", taskName, taskNum)

	//		Register task and dependencies
	Topo_AddNode( registry.topoID, currName )
	foreach (string b in before) { Topo_AddEdge(registry.topoID, b, currName) }
	foreach (string a in after) { Topo_AddEdge(registry.topoID, currName, a) }

	//		Initiate and queue task for parameter inference phase
	//	the TaskInfer_Function should be doing the "build blueprint" block above
	TaskInfer_Function taskInfer
	taskInfer.name		= currName
	taskInfer.taskType	= taskType
	taskInfer.target	= target
	registry.queueInfer_Function.append(taskInfer)

	if (taskType == eTaskType.FACTORY) {
		//	Initiate and queue task for ItemData building phase
		TaskBuild_ItemData taskBuild
		taskBuild.name		= currName
		taskBuild.target	= target
		registry.queueBuild_ItemData.append(taskBuild)

		//	That's it
		return
	}

	//	Initiate and queue task for patching phase
	TaskOrdered patchTask
	patchTask.name		= currName
	patchTask.taskType	= taskType
	patchTask.i			= target
	registry.queuePatchAllTasks.append(patchTask)
}

void function Registry_InferRPakData(
	string taskName, asset rpakPath, table overrides = {},
) {
	//		Find parameter destination
	if (!(taskName in registry.taskCounter)) {
		registry.logger.Warn("Attempted to bind data to unknown task '%s'", taskName)
		return
	}

	//	Retrieve tasks bound to this name
	array<string> taskNames = []
	for (int i = 0; i < registry.taskCounter[taskName]; i++) {
		taskNames.append( format("%s_%3d", taskName, i) )
	}

	//		Instantiate tasks
	//	Instantiate and queue tasks for caching phase
	foreach (string currName in taskNames) {
		TaskCache_BindRPak taskPatch
		taskPatch.name		= currName
		taskPatch.rpakPath	= rpakPath
		taskPatch.overrides	= overrides
		registry.queueCache_BindData.append(taskCache)

		TaskCache_BindRPak taskCache
		taskCache.name		= currName
		taskCache.rpakPath	= rpakPath
		taskCache.overrides	= overrides
		registry.queueCache_BindRPak.append(taskCache)
	}
}

///	============================================================================
///								Task Processing
///	============================================================================
void function Registry_InferPhase() {
	registry.logger.SetPhase("INFER")

	//	Infer bindings from function parameter reflection
	foreach (TaskInfer_Function task in registry.queueInfer_Function) {
		//		Sanity checks
		//	Preemptive null name check - can't index
		if (task.name == "") { continue; }

		//	Preemptive null target check - nothing to read
		if (task.target == null) { continue; }

		//	Ensure the function signature matches taskType
		/* implementation... */

		//		Build Blueprint
		//	Retrieve base data
		TaskInfer_Blueprint bp = Registry_ReflectFunc( target )

		//	Initialize bindings from target
		array<ParamBinding> fromFunc = []
		foreach (int i, string argName in task.rawArgs) {
			ParamBinding b = InferParamBinding(argName)

			//	Handle optional parameters: assign STATIC_VAL and fetch default
			if (i >= task.defsIdx) {
				b.dataSource = eParamSource.STATIC_VAL
				b.value = task.rawDefs[ i - task.defsIdx ]
			}

			//	Append to list
			fromFunc.append(b)
		}

		//		Populate registry
		//	Index bindings into registry
		table< string, array<ParamBinding> > destTable = {}
		switch (taskType) {
			case eTaskType.FACTORY:		destTable = registry.facBindings; break;
			case eTaskType.MUTATOR:		destTable = registry.mutBindings; break;
			case eTaskType.GENERATOR:	destTable = registry.genBindings; break;

			default:
				break;
		}

		//	Link ParamBinding arrays
		destTable[task.name] <- fromFunc
		registry.allBindings[task.name] <- fromFunc
		bp.destArray = destTable[task.name]
	}

	//*		Blueprints
	foreach (TaskInfer_Blueprint task in registry.queueInfer_Blueprint) {
		//		Initialize get functions
		//	This was initially done in the Bake phase, but has been moved here
		//	to allow the Mutate phase to access the Get functions. 'fromFunc'
		//	contains all bindings, so only this needs to be mapped over.
		registry.logger.Info(INFER_INFO_GETTER_SET, task.name)
		foreach (ParamBinding b in fromFunc) {
			registry.logger.Iter( b.argName )	//	Using this function automatically adds to a log line

			switch (b.dataSource) {
				case eParamSource.ROW_INDEX:	b.Get = var function( int r ) { return r; }; break;
				case eParamSource.STATIC_VAL:	b.Get = var function( int r ) : (b) { return b.value; }; break;

				case eParamSource.GENERATED:
				case eParamSource.DATATABLE:
					if (b.argName == "itemType") { b.Get = var function( int r ) : (b, task, logStr) {
						if (b.value == null) {
							registry.logger.Fatal( INFER_ERROR_VALUE_NULL, task.name, b.colName );
						}

						array arr = expect array(b.value)
						string typeStr = expect string( arr[r] )
						return (typeStr in eItemTypes) ? eItemTypes[ typeStr ] : "PIPELINE_SKIP"
					}; break; }

					b.Get = var function( int r ) : (b, task, logStr) {
						if (b.value == null) {
							registry.logger.Fatal( INFER_ERROR_VALUE_NULL, task.name, b.colName );
						}

						return (expect array(b.value))[r]
					}; break;
			}
		}
	}

	//		Clear queues
	registry.queueInfer_Function.clear()
	registry.queueInfer_RPakData.clear()
	registry.queueInfer_Blueprint.clear()
}

void function Registry_CachePhase() {
	registry.logger.SetPhase("CACHE")

	//		Process overrides, link bindings
	foreach (TaskCache_BindRPak task in registry.queueCache_BindRPak) {
		//		Retrieve task-specific bindings
		//	Can't operate on something that isn't indexed
		if( !(task.name in registry.allBindings) ) {
			registry.logger.Fatal( CACHE_ERROR_BAD_TASK, task.name)
		}

		array<ParamBinding> taskBindings = registry.allBindings[task.name]

		//	1).	Validate overrides against arguments
		//	First block of deprecated TaskBindings_Blueprint code, can't fetch
		//	columns that aren't part of the datatable
		foreach (string key, var val in task.overrides) {
            bool isValid = false
            foreach (ParamBinding b in taskBindings) {
				isValid = (b.argName == key) || isValid
            }

            if (!isValid) {
				registry.logger.Fatal( CACHE_ERROR_INVALID_OVERRIDE, task.name, key )
			}
        }

		//	2).	Apply overrides
		//	Second block excerpt, allows for flexible overriding - type,
		//	column, static values, etc. Essential for type compatibility
		array<ParamBinding> fromTable = []
		foreach (ParamBinding b in taskBindings) {
			if (b.argName in task.overrides) {
				var newVal = task.overrides[b.argName]
				switch (typeof(newVal)) {
					case "array":
						array arr = expect array(newVal)
						b.colName = b.argName

						//	Column type override
						b.dataType = expect int(arr[0])

						//	Column name override (optional)
						if (arr.len()< 2) { break; }
						b.colName = expect string(arr[1])
						break;

					case "string":
						b.colName = expect string(newVal)
						break;

					default:
						b.dataSource = eParamSource.STATIC_VAL
						b.value = newVal
						break;
				}
			}

			//	3).	Queue datatable dependencies
			//	Third block, directly links ParamBindings to RPaks
			if (b.dataSource == eParamSource.DATATABLE) {
				if (b.colName == "") {
					registry.logger.Fatal( CACHE_ERROR_INFERENCE_FAIL, task.name, b.argName, task.rpakPath )
				}

				fromTable.append(b)
			}
		}

		//	Patch over rpakBindings
		if( task.rpakPath in registry.rpakBindings ) {
			registry.rpakBindings[task.rpakPath].extend(fromTable)
		} else { registry.rpakBindings[task.rpakPath] <- fromTable }
	}

	//	Second pass
	foreach (TaskCache_BindRPak task in registry.queueCache_BindRPak) {
		//		Sanity checks
		//	Can't retrieve from something that's not cached
		asset rpakPath = task.rpakPath
		if (!(rpakPath in registry.rpakBindings)) { continue }

		//	Can't do shit without bindings
		array<ParamBinding> bindings = registry.rpakBindings[task.rpakPath]

		//	Shouldn't be revisiting rpaks, since bindings are grouped by rpak

		//	[A] Cache Hit
		//	Link b.value to the cache - huge time saver
		if (rpakPath in registry.cache) {
			RPakData rpak = registry.cache[rpakPath]
			foreach ( ParamBinding b in bindings ) {
				if ( b.value == null && b.colName in rpak.data ) {
					b.value = rpak.data[ b.colName ]
				}
			}

			continue
		}

		//	[B] Cache Miss
		//	Access data from disk
		var dt = GetDataTable(rpakPath)
		int numRows = GetDatatableRowCount(dt)

		//	Access bindings
		// Only the RPak-dependent bindings need to be fetched
		// Deduplicate columns to prevent multiple access
		table< string, array<int> > colsToFetch = {}
		foreach ( ParamBinding b in bindings ) {
			//	Skip already tracked columns
			if (b.colName in colsToFetch) {
				continue
			}

			registry.logger.Iter( b.colName )

			//	Fetch numeric index for column, throw error if not found
			int colIdx = GetDataTableColumnByName( dt, b.colName )
			if (colIdx == -1) {
				registry.logger.Fatal(CACHE_ERROR_NO_COLUMN, task.name, rpakPath, b.colName )
			}

			//	Index into colsToFetch
			colsToFetch[b.colName] <- [colIdx, b.dataType]
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
			}
		}

		//	Link cache to bindings
		foreach (ParamBinding b in bindings) {
			if (!(b.colName in rpak.data)) { continue; }
			b.value = rpak.data[b.colName]
		}

		//		Save to central state
		registry.cache[rpakPath] <- rpak
		registry.logger.Info( CACHE_INFO_CACHED, task.name, rpakPath, numRows )
	}

	//		Clear queues
	registry.queueCache_BindRPak.clear()
}

void function Registry_PatchPhase() {
	registry.logger.SetPhase("PATCH")

	//	Processing functions

	//		1).	Verification
	//	Verify patch bindings independently, seperate from patch application
	//	Individual patches won't use all bindings assigned to a single job.
	foreach (TaskOrdered task in registry.queuePatchAllTasks) {
		//		Retrieve bindings based on task type
		//	Switching the source table allows for one inclusion check
		table< string, array<ParamBinding> > srcTable
		switch (task.taskType) {
			case eTaskType.MUTATOR:		srcTable = registry.mutBindings; break;
			case eTaskType.GENERATOR:	srcTable = registry.genBindings; break;
			default:
				registry.logger.Warn("Task '%s' in registry.queuePatchAllTasks is unpermitted type", task.name)
				break;
		}

		//	Grab the bindings
		array<ParamBinding> taskBindings
		if(!(task.taskName in srcTable)) {
			registry.logger.Warn("Task '%s' could not be found in the registry", task.name)
			continue
		} else { taskBindings = srcTable[task.taskName]; }
		/* ... some sanity checks here ... */

		//		Gather execution context
		//	Row count is necessary for iteration later
		int numRows = 0
		foreach (ParamBinding b in taskBindings) {
			if (b.dataSource == eParamSource.DATATABLE && b.value != null) {
				numRows = (expect array(b.value)).len()
				break
			}
		}

		//		Validate bindings
		//	Ensure the binding values are non-null, unless generated
		foreach (ParamBinding b in taskBindings) {
			//	Log the active parameter
			registry.logger.Iter(b.argName)

			//	Validate value state before calling with parameters
			if (b.dataSource == eParamSource.DATATABLE && b.value == null) {
				registry.logger.Fatal(PATCH_ERROR_BIND_UNRESOLVED, task.name, b.argName)
			}

			//	Validate function getter
			if (b.Get == null) {
				registry.logger.Fatal(PATCH_ERROR_GETTER_NULL, task.name, b.argName)
			}
		}

		registry.logger.Info(PATCH_INFO_VALIDATED_BINDS, task.name)
	}

	//		2).	Data Initialization
	foreach (TaskOrdered task in registry.queuePatchAllTasks) {
		//		Retrieve bindings based on task type
		//	Switching the source table allows for one inclusion check
		table< string, array<ParamBinding> > srcTable
		switch (task.taskType) {
			case eTaskType.MUTATOR:		srcTable = registry.mutBindings; break;
			case eTaskType.GENERATOR:	srcTable = registry.genBindings; break;
			default: continue;
		}

		//	Grab the bindings
		if(!(task.taskName in srcTable)) { continue }
		array<ParamBinding> taskBindings = srcTable[task.taskName]

		//		;dkfjgha;dskrjg
		//	Reflect function info
		TaskInfer_Blueprint bp = Registry_ReflectFunc( task.i )

		//	Map task bindings to arg names for O(1) matching against function
		table<string, ParamBinding> mapBindings = {}
		foreach (ParamBinding b in taskBindings) { mapBindings[b.argName] <- b }

		//		Grab task-specific context
		//	Isolate only the active bindings required by the function
		array<ParamBinding> funcBindings = []
		foreach (string argName in bp.rawArgs) {
			if (!(argName in mapBindings)) {
				registry.logger.Fatal( PATCH_ERROR_BIND_MISSING, task.name, argName )
			}
			funcBindings.append(mapBindings[argName])
		}

		//	Determine grid depth
		int numRows = 0
		foreach (ParamBinding b in taskBindings) {
			if (b.dataSource == eParamSource.DATATABLE && b.value != null) {
				numRows = (expect array(b.value)).len()
				break
			}
		}

		//	Construct internal data
		task.i = {
			taskBindings	= taskBindings,
			funcBindings	= funcBindings,
			numRows			= numRows
		}

		//		Apply mutator/generator
		//	Generator initialization
		foreach (ParamBinding b in taskBindings) {
			if (b.dataSource == eParamSource.GENERATED && b.value == null && numRows > 0) {
				b.value = []
				b.value.resize(numRows, null)
			}
		}
	}

	//		3).	Application
	foreach (TaskOrdered task in registry.queuePatchAllTasks) {
		//		Sanity checks
		//	Skip tasks which haven't had their data filled out
		/* test if task.i table is empty */

		//	Mutator specific exit: abort if no data exists
		int numRows = expect int(task.i.numRows)
		if (task.taskType == eTaskType.MUTATOR && numRows == 0) {
			registry.logger.Info( PATCH_INFO_NO_DATA, task.name )
			continue
		}

		//		Retrieve data
		array<ParamBinding> taskBindings = expect array<ParamBinding>(task.i.taskBindings)
		array<ParamBinding> funcBindings = expect array<ParamBinding>(task.i.funcBindings)

		table< string, array > newOutputs = {}
		foreach (ParamBinding b in taskBindings) {
			if (b.dataSource == eParamSource.GENERATED && b.value == null && numRows > 0) {
				b.value = []
				b.value.resize(numRows, null)
			}
			if (task.taskType == eTaskType.GENERATOR) {
				newOutputs[b.argName] <- []
			}
		}

		//		Execution loop
		//	Generators with 0 rows execute exactly once. Otherwise, execute per row.
		int loopCount = (numRows == 0) ? 1 : numRows
		for (int r = 0; r < loopCount; r++) {
			array args = [ getroottable() ]
			bool skipRow = false

			//		Fetch runtime arguments
			//	Includes a skip check
			if (numRows > 0) {
				foreach (ParamBinding b in funcBindings) {
					var val = b.Get(r)
					if (typeof(val) == "string" && expect string(val) == "PIPELINE_SKIP") { skipRow = true; break; }
					args.append(val)
				}
				if (skipRow) { continue }
			}

			//	Execute shared function call
			var result = targetFunc.acall(args)

			//	Process Outputs by Task Type
			string expectType = ""
			string expectWarn = ""
			switch (task.taskType) {
				case eTaskType.MUTATOR: expectType = "table"; expectWarn = PATCH_ERROR_EXPECTED_TABLE; break;
				case eTaskType.GENERATOR: expectType = "array"; expectWarn = PATCH_ERROR_GEN_EXP_ARRAY; break;
			}

			if (result == null || typeof(result) != expectType) {
				if (numRows == 0 && expectType == "array") {
					registry.logger.Fatal( PATCH_ERROR_GEN_EXP_ARRAY, task.name, typeof(result) )
				}
				registry.logger.Fatal( PATCH_ERROR_EXPECTED_TYPE, task.name, expectType, typeof(result) )
			}

			switch (task.taskType) {
				case eTaskType.MUTATOR:
					//	Mutate existing tracked state in-line
					table resTable = expect table( result )
					foreach (ParamBinding b in funcBindings) {
						if ( b.dataSource == eParamSource.DATATABLE || (b.dataSource == eParamSource.GENERATED && (b.argName in resTable)) ) {
							(expect array(b.value))[r] = resTable[b.argName]
						}
					}

					break;
				case eTaskType.GENERATOR:
					//	Append expanded row generations to buffer
					foreach (var rowData in expect array(result)) {
						table resTable = expect table(rowData)
						foreach (ParamBinding b in taskBindings) {
							var val = (b.argName in resTable) ? resTable[b.argName] : (numRows > 0 ? b.Get(r) : null)
							newOutputs[b.argName].append(val)
						}
					}

					break;

				default: continue;
			}
		}

		//	Generator Cleanup: atomically swap pipeline layout references
		if (task.taskType == eTaskType.GENERATOR) {
			foreach (ParamBinding b in taskBindings) { b.value = newOutputs[b.argName] }
		}
	}

	//		Clear queues
	registry.queuePatchAllTasks.clear()
//	registry.queuePatchGenerate.clear()
}

void function Registry_BuildPhase( array<TaskBuild_ItemData> queue ) {
	//		ItemData baking
	foreach (TaskBuild_ItemData task in queue) {
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
	registry.queueBuild_ItemData.clear()
}

void function Registry_ExecutePipeline() {
	//	Phase 1: Reflect on functions, handle defaults, map overrides
//	registry.queueInfer_RPak.sort( PrioritySortComparator )
	Registry_InferPhase()

	//	Phase 2: Deduplicate columns across all jobs, query RPak files, populate RAM cache
	Registry_CachePhase()

	//	Phase 3: Optional mid-pipeline modifications by other sub-mods
//	registry.queuePatchModify.sort( PrioritySortComparator )
	Registry_PatchPhase()

	//	Phase 4: Construct argument lists and unbox data natively into the factory methods
//	registry.queueBuild_ItemData.sort( PrioritySortComparator )
	Registry_BuildPhase( registry.queueBuild_ItemData )
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