untyped
//		Declaration
//	Global functions
global function ArmoryUtils_CreateLogger

global function LogPhase
global function LogPush
global function LogFormat

global function LogIter
global function LogDebug
global function LogInfo
global function LogWarn
global function LogError
global function LogFatal

//	Logger state structs
global struct LoggerConfigFormat {
	int paddingPrefix = 4
	int paddingPhase  = 7
	int paddingLevel  = 7

	int justifyPrefix = 1
	int justifyPhase = -1
	int justifyLevel = -1

	string vertChar = "|"
	string horzChar = "-"
	string bothChar = "+"
}

global struct LoggerConfigStatus {
	bool breakPhase = true
	bool breakLevel = false

	string prefixPhase = "#"
	string prefixLevel = ">"
}

global struct LoggerConfigIter {
	string brackets	= "[%s]"
	string separator = ", "
	string missing = "~"
}

global struct LoggerState {
	string currPhase = "INIT"
	int printIndex = 0

	array<string> colPhase
	array<string> colLevel
	array<string> colText

	LoggerConfigFormat	cfgFormat
	LoggerConfigStatus	cfgStatus
	LoggerConfigIter	cfgIter
}

/// ===========================================================================
///                     		HELPER FUNCTIONS
/// ===========================================================================
//	Repeats the string 'rep' 'count' times.
string function _RepeatString( string rep, int count ) {
	string out = ""
	for (int i = 0; i < count; i++) { out += rep }
	return out
}

//	Refactor of the 'format' function to accept an array
string function FormatArray( string fmtStr, array args ) {
	if ( args.len() == 0 ) { return fmtStr }

	array callArgs = [ getroottable(), fmtStr ]
	callArgs.extend( args )

	return expect string( format.acall( callArgs ) )
}

string function FormatRow( LoggerConfigFormat cfg ) {
	string alignPrefix	= (cfg.justifyPrefix == -1) ? "-" : ""
	string alignPhase	= (cfg.justifyPhase == -1) ? "-" : ""
	string alignLevel	= (cfg.justifyLevel == -1) ? "-" : ""

	return format( "\n%%%s%ds%%s%%%s%ds%%s%%%s%ds%%s%%s\n",
		alignPrefix, cfg.paddingPrefix,
		alignPhase,  cfg.paddingPhase,
		alignLevel,  cfg.paddingLevel
	)
}

string function DrawBreak( LoggerState state, bool changePhase, bool changeLevel, string rowFmt ) {
	//	Return null string if
	bool doPhase = (state.cfgStatus.breakPhase && changePhase)
	bool doLevel = (state.cfgStatus.breakLevel && changeLevel)
	if ( !doPhase && !doLevel ) { return "" }

	string activePrefix = state.cfgStatus.prefixLevel
	if (changePhase) { activePrefix = state.cfgStatus.prefixPhase }

	int padPhase = state.cfgFormat.paddingPhase
	int padLevel = state.cfgFormat.paddingLevel
	int contentWidth = 80 - (state.cfgFormat.paddingPrefix + padPhase + padLevel + 6)
	if ( contentWidth < 10 ) { contentWidth = 10 }

	string charHorz = state.cfgFormat.horzChar
	string charBoth = state.cfgFormat.bothChar

	return format( rowFmt,
		activePrefix, charBoth,
		_RepeatString(charHorz, padPhase), charBoth,
		_RepeatString(charHorz, padLevel), charBoth,
		_RepeatString(charHorz, contentWidth)
	)
}

string function DrawRow( LoggerState state, int idx, string rowFmt ) {
	string currPhase = state.colPhase[idx]
	string currLevel = state.colLevel[idx]
	string currText  = state.colText[idx]

	bool changePhase = false
	bool changeLevel = false

	if (idx > 0) {
		changePhase = (currPhase != state.colPhase[idx-1])
		changeLevel = (currLevel != state.colLevel[idx-1])
	}

	string output = DrawBreak( state, changePhase, changeLevel, rowFmt )

	string dispPhase = currPhase
	string dispLevel = currLevel
	if (state.cfgStatus.breakPhase && !changePhase && idx > 0) { dispPhase = "" }
	if (state.cfgStatus.breakLevel && !changeLevel && idx > 0) { dispLevel = "" }

	output += format( rowFmt,
		"", state.cfgFormat.vertChar,
		dispPhase, state.cfgFormat.vertChar,
		dispLevel, state.cfgFormat.vertChar,
		currText
	)

	return output
}

///	===========================================================================
///								LOGGER CONFIGURATION
///	===========================================================================
LoggerState function ArmoryUtils_CreateLogger( string initPhase = "INIT" ) {
	LoggerState state
	state.currPhase = initPhase
	return state
}

void function LogPhase( LoggerState state, string phase ) {
	state.currPhase = phase
}

///	===========================================================================
///								INTERNAL FUNCTIONALITY
///	===========================================================================
array<string> function LogPush( LoggerState state, string level, string message ) {
	state.colPhase.append( state.currPhase )
	state.colLevel.append( level )
	state.colText.append( message )
	return [ state.currPhase, level, message ]
}

string function LogFormat( LoggerState state ) {
	int maxLen = state.colPhase.len()
	if ( state.printIndex >= maxLen ) { return "" }

	string rowFmt = FormatRow( state.cfgFormat )
	string output = ""

	for (; state.printIndex < maxLen; state.printIndex++) {
		output += DrawRow( state, state.printIndex, rowFmt )
	}

	return output
}

///	===========================================================================
///								LOGGER FUNCTIONS
///	===========================================================================
void function LogIter( LoggerState state, string fmtStr, ... ) {
	string text = FormatArray( fmtStr, vargv )
	int lastIdx = state.colText.len() - 1

	if (lastIdx < 0 || state.colLevel[lastIdx] != "ITER") {
		LogPush( state, "ITER", format( state.cfgIter.brackets, text ) )
		return
	}

	string existing = state.colText[lastIdx]
	string stripped = existing.slice( 0, existing.len() - 1 )
	state.colText[lastIdx] = stripped + state.cfgIter.separator + text + "]"
}

void function LogDebug( LoggerState state, string fmtStr, ... ) {
	#if DEBUG
	LogPush( state, "DEBUG", FormatArray(fmtStr, vargv) )
	#endif
}

void function LogInfo( LoggerState state, string fmtStr, ... )  { LogPush( state, "INFO",  FormatArray(fmtStr, vargv) ) }
void function LogWarn( LoggerState state, string fmtStr, ... )  { LogPush( state, "WARN",  FormatArray(fmtStr, vargv) ) }
void function LogError( LoggerState state, string fmtStr, ... ) { LogPush( state, "ERROR", FormatArray(fmtStr, vargv) ) }

void function LogFatal( LoggerState state, string fmtStr, ... ) {
	string text = FormatArray( fmtStr, vargv )
	array<string> err = LogPush( state, "FATAL", text )

	printt( LogFormat(state) )
	throw format( "REGISTRY [%s] FATAL: %s", err[0], err[2] )
}