untyped

global function ArmoryUtils_CreateLogger

/// ===========================================================================
///					 Helper functions - file scope
/// ===========================================================================
string function _RepeatString( string char, int count ) {
	string out = ""
	for (int i = 0; i < count; i++) { out += char }
	return out
}

string function _FormatArray( string fmtStr, array args ) {
	if ( args.len() == 0 ) { return fmtStr }

	array callArgs = [ getroottable(), fmtStr ]
	callArgs.extend( args )

    var out = format.acall( callArgs )
	return expect string(out)
}

/// ===========================================================================
///					 Internal Logger Functions
/// ===========================================================================
void function Logger_SetPhase( string phase ) {
	this.currPhase = phase
}

array<string> function Logger_PushRow( string level, string message ) {
	array colPhase = expect array(this.colPhase)
	array colLevel = expect array(this.colLevel)
	array colText  = expect array(this.colText)
	string currPhase = expect string(this.currPhase)

	colPhase.append( currPhase )
	colLevel.append( level )
	colText.append( message )

	return [ currPhase, level, message ]
}

string function Logger_Format() {
	array colPhase = expect array(this.colPhase)
	array colLevel = expect array(this.colLevel)
	array colText  = expect array(this.colText)
	int printIndex = expect int(this.printIndex)

	if ( printIndex >= colPhase.len() ) { return ""}

	table cfgFmt = expect table(this.configFormat)
	table cfgStat = expect table(this.configStatus)

	// 1. Unbox configurations
	int padPrefix = expect int(cfgFmt.paddingPrefix)
	int padPhase  = expect int(cfgFmt.paddingPhase)
	int padLevel  = expect int(cfgFmt.paddingLevel)

	string charHorz = expect string(cfgFmt.horzChar)
	string charVert = expect string(cfgFmt.vertChar)
	string charBoth = expect string(cfgFmt.bothChar)

	bool breakPhase = expect bool(cfgStat.breakPhase)
	bool breakLevel = expect bool(cfgStat.breakLevel)
	string prefixPhase = expect string(cfgStat.prefixPhase)
	string prefixLevel = expect string(cfgStat.prefixLevel)

	// 2. Build alignment modifiers
	string alignPrefix = (expect int(cfgFmt.justifyPrefix) == -1) ? "-" : ""
	string alignPhase  = (expect int(cfgFmt.justifyPhase) == -1) ? "-" : ""
	string alignLevel  = (expect int(cfgFmt.justifyLevel) == -1) ? "-" : ""

	// 3. Generate dynamic format template
	string rowFmt = format( "%%%s%ds%%s%%%s%ds%%s%%%s%ds%%s%%s\n",
		alignPrefix, padPrefix,
		alignPhase,  padPhase,
		alignLevel,  padLevel
	)

	// 4. Pre-calculate horizontal line segments
	int contentWidth = 80 - (padPrefix + padPhase + padLevel + 6)
	if ( contentWidth < 10 ) contentWidth = 10

	string linePhase	= _RepeatString(charHorz, padPhase)
	string lineLevel	= _RepeatString(charHorz, padLevel)
	string lineContent  = _RepeatString(charHorz, contentWidth)

	// 5. Build output string
	string output = ""
	for (; printIndex < colPhase.len(); printIndex++) {
		var currPhase   = colPhase[printIndex]
		var currLevel   = colLevel[printIndex]
		var currText    = colText[printIndex]

        bool changePhase = false; bool changeLevel = false
		if (printIndex > 0) {
			var prevPhase = colPhase[printIndex-1]; var prevLevel = colLevel[printIndex-1]
			changePhase = (expect string(currPhase) != expect string(prevPhase))
			changeLevel = (expect string(currLevel) != expect string(prevLevel))
		}

		// Draw Boundary Separators
		if ( (breakPhase && changePhase) || (breakLevel && changeLevel) ) {
			string activePrefix = changePhase ? prefixPhase : prefixLevel
			output += format( rowFmt,
				activePrefix, charBoth,
				linePhase,	charBoth,
				lineLevel,	charBoth,
				lineContent
			)
		}

		// Visually deduplicate repeated phases/levels on continuous lines
		string displayPhase = (breakPhase && !changePhase && printIndex > 0) ? "" : expect string(currPhase)
		string displayLevel = (breakLevel && !changeLevel && printIndex > 0) ? "" : expect string(currLevel)

		// Append the actual log row
		output += format( rowFmt,
			"", charVert,
			displayPhase, charVert,
			displayLevel, charVert,
			expect string(currText)
		)
	}

	this.printIndex = printIndex
	return output
}

/// ===========================================================================
///					 External Logger Functions
/// ===========================================================================
void function Logger_Iter( string fmtStr, ... ) {
	array args = []
	for (int i = 0; i < vargc; i++) { args.append(vargv[i]) }

	string text = _FormatArray( fmtStr, args )

	array colText = expect array(this.colText)
	array colLevel = expect array(this.colLevel)
	int lastIdx = colText.len() - 1

	table cfgIter = expect table(this.configIter)
	string brackets = expect string(cfgIter.brackets)
	string separator = expect string(cfgIter.separator)

	// Start new bracket if empty or previous row wasn't ITER
	if ( lastIdx < 0 || colLevel[lastIdx] != "ITER" ) {
		this.Push( "ITER", format( brackets, text ) )
	} else {
		// Splice into existing bracket
		var oldText = colText[lastIdx]
		string existing = expect string(oldText)
		string stripped = existing.slice( 0, existing.len() - 1 )
		colText[lastIdx] = stripped + separator + text + "]"
	}
}

void function Logger_Debug( string fmtStr, ... ) {
	#if DEV
	array args = []
	for (int i = 0; i < vargc; i++) { args.append(vargv[i]) }
	this.Push( "DEBUG", _FormatArray(fmtStr, args) )
	#endif
}

void function Logger_Info( string fmtStr, ... )  {
	array args = []
	for (int i = 0; i < vargc; i++) { args.append(vargv[i]) }
	this.Push( "INFO",  _FormatArray(fmtStr, args) )
}
void function Logger_Warn( string fmtStr, ... )  {
	array args = []
	for (int i = 0; i < vargc; i++) { args.append(vargv[i]) }
	this.Push( "WARN",  _FormatArray(fmtStr, args) )
}
void function Logger_Error( string fmtStr, ... ) {
	array args = []
	for (int i = 0; i < vargc; i++) { args.append(vargv[i]) }
	this.Push( "ERROR", _FormatArray(fmtStr, args) )
}

void function Logger_Fatal( string fmtStr, ... ) {
	array args = []
	for (int i = 0; i < vargc; i++) { args.append(vargv[i]) }
	string text = _FormatArray( fmtStr, args )

	// Unbox safely from a dynamic function call
	array err = expect array( this.Push( "FATAL", text ) )

	printt( this.Build() ) // Dump everything leading up to the crash

	var errPhase = err[0]; var errText = err[2]
	throw format("REGISTRY [%s] FATAL: %s", expect string(errPhase), expect string(errText))
}

/// ===========================================================================
///							 Logger Factory
///	 Return a table that imitates functionality of a class instance
/// ===========================================================================
table function ArmoryUtils_CreateLogger(
	string initPhase	= "INIT",
	table customFormat  = {},
	table customStatus  = {},
	table customIter	= {}
) {
	//  Initialize table state
	table logger = {
		currPhase  = initPhase
		printIndex = 0

		colPhase = []
		colLevel = []
		colText  = []

		configFormat = {
			paddingPrefix = 2,  justifyPrefix = 1,
			paddingPhase  = 7,  justifyPhase  = -1,
			paddingLevel  = 7,  justifyLevel  = -1,
			vertChar = "| ",	horzChar = "-",	 bothChar = "+"
		}

		configStatus = {
			breakPhase = true,  breakLevel = false,
			prefixPhase = "#",  prefixLevel = ">"
		}

		configIter = {
			brackets = "[%s]",  separator = ", ",	missing = "~"
		}
	}

	//  Safely merge user configuration
	foreach (key, val in customFormat) {
		if (key in logger.configFormat) { logger.configFormat[key] = val }
	}

	foreach (key, val in customStatus) {
		if (key in logger.configStatus) { logger.configStatus[key] = val }
	}

	foreach (key, val in customIter) {
		if (key in logger.configIter) { logger.configIter[key] = val }
	}

	//  Bind methods to table
	logger.SetPhase	<- Logger_SetPhase
	logger.Push		<- Logger_PushRow
	logger.Build	<- Logger_Format

	logger.Iter		<- Logger_Iter
	logger.Debug	<- Logger_Debug
	logger.Info		<- Logger_Info
	logger.Warn		<- Logger_Warn
	logger.Error	<- Logger_Error
	logger.Fatal	<- Logger_Fatal

	return logger
}