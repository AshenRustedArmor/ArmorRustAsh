///	============================================================================
///								Task Processing
///	============================================================================

void function Registry_ProcessBindings() {
	// -------------------------------------------------------------------------
	// 1. Mutator Bindings Phase
	// -------------------------------------------------------------------------
	foreach ( TaskBindings_Mutator task in registry.queueBindings_Mutator ) {
		local infos = task.target.getinfos()
		array rawArgs = expect array( infos.parameters )
		if ( rawArgs.len() > 0 && rawArgs[0] == "this" ) { rawArgs.remove( 0 ) }

		// Inherit bindings from the parent function
		array<ParamBinding> fromParent = registry.funcBindings[ task.jobID ]
		foreach ( ParamBinding b in fromParent ) {
			if ( !( b.argName in rawArgs ) ) { continue } [cite: 16, 17]
			rawArgs.fastremovebyvalue( b.argName )
		}

		// Iterate over the keys of rpak2args
		foreach ( var key, var args in task.rpak2args ) {
			switch ( typeof( key ) ) {
				case "asset":
					// FIX: Convert the modder's array pattern into a table mapping for the infer engine
					table overridesTable = {}
					foreach ( var arg in expect array( args ) ) {
						overridesTable[ expect string( arg ) ] <- expect string( arg )
					}

					TaskBindings_Infer newInfer
					newInfer.jobID     = task.jobID
					newInfer.priority  = task.priority + 1
					newInfer.rpakPath  = expect asset( key )
					newInfer.target    = null
					newInfer.overrides = overridesTable

					registry.queueBindings_Infer.append( newInfer )
					break

				case "string":
					ParamBinding b
					b.argName    = expect string( key )
					b.dataSource = eParamSource.STATIC_VAL
					b.value      = args

					registry.funcBindings[ task.jobID ].append( b )
					break

				default:
					throw "[REGISTRY ERROR] Job " + task.jobID + " specified an invalid key type '" + typeof( key ) + "' inside rpak2args. Keys must be asset or string."
			}
		}
	}

	// -------------------------------------------------------------------------
	// 2. Inferred Bindings Phase
	// -------------------------------------------------------------------------
	foreach ( TaskBindings_Infer task in registry.queueBindings_Infer ) {
		array rawArgs = []
		array rawDefs = []
		int defsIdx = 0

		if ( task.target != null ) {
			local infos = task.target.getinfos()
			rawArgs = expect array( infos.parameters )
			if ( rawArgs.len() > 0 && rawArgs[0] == "this" ) { rawArgs.remove( 0 ) }

			rawDefs = ( "defparams" in infos ) ? expect array( infos.defparams ) : []
			defsIdx = rawArgs.len() - rawDefs.len()
		}

		array<ParamBinding> fromFunc = []
		array<ParamBinding> fromTable = []

		foreach ( int i, string argName in rawArgs ) {
			ParamBinding b = InferParamBinding( argName )

			// Assign optional parameters
			if ( i >= defsIdx ) {
				b.dataSource = eParamSource.STATIC_VAL
				b.value      = rawDefs[ i - defsIdx ]
			}

			// Handle overrides
			if ( argName in task.overrides ) {
				var newVal = task.overrides[ argName ]
				if ( typeof( newVal ) == "string" ) {
					b.colName = expect string( newVal )
				} else {
					b.dataSource = eParamSource.STATIC_VAL
					b.value      = newVal
				}
			}

			// PROACTIVE VALIDATION: Catch parameters that couldn't resolve columns or statics
			if ( b.colName == "" && b.dataSource == eParamSource.DATATABLE ) {
				throw "[REGISTRY ERROR] Job " + task.jobID + " requested parameter '" + argName + "' which cannot be auto-inferred from RPak '" + task.rpakPath + "'. Did you forget an override declaration?"
			}

			if ( b.dataSource == eParamSource.DATATABLE ) { fromTable.append( b ) }
			fromFunc.append( b )
		}

		// Index and map out dependencies
		if ( task.rpakPath in registry.rpakBindings ) {
			registry.rpakBindings[ task.rpakPath ].extend( fromTable )
		} else {
			registry.rpakBindings[ task.rpakPath ] <- fromTable
		}

		registry.funcBindings[ task.jobID ] <- fromFunc
	}

	registry.queueBindings_Mutator.clear()
	registry.queueBindings_Infer.clear()
}

void function Registry_ProcessCache() {
	foreach ( TaskCache_RPakData task in registry.queueCache_RPakData ) {
		// ARCHITECTURAL DOCUMENTATION:
		// We perform a full-RPak top-level check here before any resource querying occurs.
		// If an RPak asset is shared across multiple factory functions, the entire data grid
		// is cached in a single pass. This prevents redundant IO reads and array generation.
		if ( task.rpakPath in registry.cache ) { continue }
		if ( !( task.rpakPath in registry.rpakBindings ) ) { continue }

		var dt      = GetDataTable( task.rpakPath )
		int numRows = GetDatatableRowCount( dt )

		array<ParamBinding> bindings = registry.rpakBindings[ task.rpakPath ]
		table< string, array<int> > colsToFetch = {}

		// Gather distinct required columns
		foreach ( ParamBinding b in bindings ) {
			if ( b.colName in colsToFetch ) { continue } [cite: 22, 23]

			int colIdx = GetDataTableColumnByName( dt, b.colName )
			if ( colIdx == -1 ) {
				throw "[REGISTRY ERROR] RPak file '" + task.rpakPath + "' is missing the required column '" + b.colName + "'."
			}

			colsToFetch[ b.colName ] <- [ colIdx, b.dataType ]
		}

		RPakData rpak
		rpak.numRows = numRows

		// Unbox and map data columns out dynamically via type lambdas
		foreach ( string colName, array<int> idxAndType in colsToFetch ) {
			array<var> colData
			rpak.data[ colName ] <- colData
			colData.resize( numRows, null )

			int colIdx            = idxAndType[0]
			rpak.colTypes[colName] <- idxAndType[1]

			var functionref( int ) DataTableGet = null
			switch ( idxAndType[1] ) {
				case eColType.BOOL:   DataTableGet = var function( int row ) : ( dt, colIdx ) { return GetDataTableBool( dt, row, colIdx ) }; break [cite: 26, 27]
				case eColType.INT:    DataTableGet = var function( int row ) : ( dt, colIdx ) { return GetDataTableInt( dt, row, colIdx ) }; break [cite: 27, 28]
				case eColType.FLOAT:  DataTableGet = var function( int row ) : ( dt, colIdx ) { return GetDataTableFloat( dt, row, colIdx ) }; break [cite: 28, 29]
				case eColType.STRING: DataTableGet = var function( int row ) : ( dt, colIdx ) { return GetDataTableString( dt, row, colIdx ) }; break [cite: 29, 30]
				case eColType.ASSET:  DataTableGet = var function( int row ) : ( dt, colIdx ) { return GetDataTableAsset( dt, row, colIdx ) }; break [cite: 30, 31]
			}

			for ( int r = 0; r < numRows; r++ ) {
				colData[r] = DataTableGet( r )
			}
		}

		// Link cache structures back to parameters
		foreach ( ParamBinding b in bindings ) {
			if ( !( b.colName in rpak.data ) ) { continue } [cite: 32, 33]
			b.value = rpak.data[ b.colName ]
		}

		registry.cache[ task.rpakPath ] <- rpak
		printt( "[REGISTRY] [INFO] Cached asset grid for RPak: " + task.rpakPath + " (" + numRows + " rows)" )
	}

	registry.queueCache_RPakData.clear()
}

void function Registry_ProcessMutate() {
	// -------------------------------------------------------------------------
	// 3. Reflection-Based Mutation Phase
	// -------------------------------------------------------------------------
	foreach ( TaskMutate_Modify task in registry.queueMutate_Modify ) {
		if ( !( task.jobID in registry.funcBindings ) ) { continue }

		array<ParamBinding> bindings = registry.funcBindings[ task.jobID ]
		array args = [ getroottable() ]
		string schemaLog = ""

		foreach ( ParamBinding b in bindings ) {
			// PROACTIVE VALIDATION: Validate value state before calling parameters
			if ( b.value == null ) {
				throw "[REGISTRY ERROR] Mutator Job " + task.jobID + " parameter '" + b.argName + "' failed to resolve data bindings prior to execution."
			}

			// Pass reference of the full column data array or static values directly
			args.append( b.value )
			schemaLog += b.argName + ": " + typeof( b.value ) + ", "
		}

		printt( "[REGISTRY] [MUTATE] Executing Job " + task.jobID + " | Input Schema: ( " + schemaLog + ")" )
		task.target.acall( args )
	}

	registry.queueMutate_Modify.clear()
}

void function Registry_ProcessBake( array<TaskBake_ItemData> queue ) {
	// -------------------------------------------------------------------------
	// 4. Data Baking Phase
	// -------------------------------------------------------------------------
	foreach ( TaskBake_ItemData task in queue ) {
		if ( !( task.jobID in registry.funcBindings ) ) { continue }
		if ( !( task.rpakPath in registry.cache ) ) { continue }

		RPakData rpak                = registry.cache[ task.rpakPath ] [cite: 34, 35]
		array<ParamBinding> bindings = registry.funcBindings[ task.jobID ]

		string schemaLog = ""

		// Establish per-row access parameters
		foreach ( ParamBinding b in bindings ) {
			schemaLog += b.argName + ", "
			switch ( b.dataSource ) {
				case eParamSource.ROW_INDEX:
					b.Get = var function( int r ) { return r }; break [cite: 36, 37]

				case eParamSource.STATIC_VAL:
					b.Get = var function( int r ) : ( b ) { return b.value }; break [cite: 37, 38]

				case eParamSource.DATATABLE:
					if ( b.value == null ) {
						throw "[REGISTRY ERROR] Bake Phase crashed on Job " + task.jobID + ". Parameter '" + b.argName + "' has a null data binding."
					}

					array arr = expect array( b.value )
					if ( b.argName == "itemType" ) {
						b.Get = var function( int r ) : ( arr ) {
							string typeStr = expect string( arr[r] )
							return ( typeStr in eItemTypes ) ? eItemTypes[ typeStr ] : -1
						}
						break
					}

					b.Get = var function( int r ) : ( arr ) { return arr[r] }; break [cite: 40, 41]
			}
		}

		printt( "[REGISTRY] [BAKE] Processing Job " + task.jobID + " | Schema: ( " + schemaLog + ")" )

		// Row-by-row invocation pass
		for ( int r = 0; r < rpak.numRows; r++ ) {
			array args = [ getroottable() ]

			foreach ( ParamBinding b in bindings ) {
				// PROACTIVE VALIDATION: Catch structural assignment failures before the engine level crashes
				if ( b.Get == null ) {
					throw "[REGISTRY ERROR] Call abort on Job " + task.jobID + ", Row " + r + ". Assigned getter for parameter '" + b.argName + "' resolved to null."
				}
				args.append( b.get( r ) )
			}

			task.target.acall( args )
		}
	}
}