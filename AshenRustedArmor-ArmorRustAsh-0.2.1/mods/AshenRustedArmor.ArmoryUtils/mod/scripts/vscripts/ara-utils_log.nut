untyped

global function ArmoryUtils_CreateLogger

///	===========================================================================
///						Helper functions - file scope
///	===========================================================================
string function _RepeatString( string char, int count ) {
    string out = ""; for (int i = 0; i < count; i++) out += char; return out
}

string function _FormatArray( string fmtStr, array args ) {
    if ( args.len() == 0 ) return fmtStr
    array callArgs = [ getroottable(), fmtStr ]
    callArgs.extend( args )
    return expect string( format.acall( callArgs ) )
}

///	===========================================================================
///						Internal Logger Functions
///	===========================================================================
void function Logger_SetPhase( string phase ) {
    this.currPhase = phase
}

array<string> function Logger_PushRow( string level, string message ) {
    this.colPhase.append( this.currPhase )
    this.colLevel.append( level )
    this.colText.append( message )
    return [ expect string(this.currPhase), level, message ]
}


string function Logger_Format() {
    if ( this.printIndex >= this.colPhase.len() ) return ""

    table cfgFmt = expect table(this.configFormat)
    table cfgStat = expect table(this.configStatus)

    // 1. Build alignment modifiers (-1 = left justified, 1 = right justified)
    string alignPrefix = cfgFmt.justifyPrefix == -1 ? "-" : ""
    string alignPhase  = cfgFmt.justifyPhase  == -1 ? "-" : ""
    string alignLevel  = cfgFmt.justifyLevel  == -1 ? "-" : ""

    // 2. Generate dynamic format template (e.g., "%-2s%s%-7s%s%-7s%s%s\n")
    string rowFmt = format( "%%%s%ds%%s%%%s%ds%%s%%%s%ds%%s%%s\n",
        alignPrefix, cfgFmt.paddingPrefix,
        alignPhase,  cfgFmt.paddingPhase,
        alignLevel,  cfgFmt.paddingLevel
    )

    // 3. Pre-calculate horizontal line segments
    int contentWidth = 80 - expect int(cfgFmt.paddingPrefix + cfgFmt.paddingPhase + cfgFmt.paddingLevel + 6)
    if ( contentWidth < 10 ) contentWidth = 10

    string linePhase = _RepeatString(expect string(cfgFmt.charHorz), expect int(cfgFmt.paddingPhase))
    string lineLevel = _RepeatString(expect string(cfgFmt.charHorz), expect int(cfgFmt.paddingLevel))
    string lineContent = _RepeatString(expect string(cfgFmt.charHorz), contentWidth )

    // 4. Build output string
    string output = ""

    for (; expect int(this.printIndex) < expect array(this.colPhase).len(); this.printIndex++) {
        int i = expect int(this.printIndex)
        string currPhase = expect string(this.colPhase[i])
        string currLevel = expect string(this.colLevel[i])
        string currText = expect string(this.colText[i])

        bool changePhase = (i > 0 && currPhase != this.colPhase[i-1])
        bool changeLevel = (i > 0 && currLevel != this.colLevel[i-1])

        //	Draw Boundary Separators
        if ( (cfgStat.breakPhase && changePhase) || (cfgStat.breakLevel && changeLevel) ) {
            string activePrefix = changePhase ? expect string(cfgStat.prefixPhase) : expect string(cfgStat.prefixLevel)

            output += format( rowFmt,
                activePrefix, expect string(cfgFmt.charBoth),
                linePhase,    expect string(cfgFmt.charBoth),
                lineLevel,    expect string(cfgFmt.charBoth),
                lineContent
            )
        }

        // B. Visually deduplicate repeated phases/levels on continuous lines
        string displayPhase = (expect bool(cfgStat.breakPhase) && !changePhase && i > 0) ? "" : currPhase
        string displayLevel = (expect bool(cfgStat.breakLevel) && !changeLevel && i > 0) ? "" : currLevel

        // C. Append the actual log row
        output += format( rowFmt,
            "", expect string(cfgFmt.charVert),
            displayPhase, expect string(cfgFmt.charVert),
            displayLevel, expect string(cfgFmt.charVert),
            currText
        )
    }

    return output
}

///	===========================================================================
///						External Logger Functions
///	===========================================================================
void function Logger_Iter( string fmtStr, ... ) {
    string text = _FormatArray( fmtStr, vargv )
    int lastIdx = this.colText.len() - 1

    // Start new bracket if empty or previous row wasn't ITER
    if ( lastIdx < 0 || this.colLevel[lastIdx] != "ITER" ) {
        this.Push( "ITER", format( this.configIter.brackets, text ) )
    } else {
        // Splice into existing bracket
        string existing = this.colText[lastIdx]
        string stripped = existing.slice( 0, existing.len() - 1 )
        this.colText[lastIdx] = stripped + this.configIter.separator + text + "]"
    }
}

void function Logger_Debug( string fmtStr, ... ) {
    #if DEBUG
    this.Push( "DEBUG", _FormatArray(fmtStr, vargv) )
    #endif
}

void function Logger_Info( string fmtStr, ... )  { this.Push( "INFO",  _FormatArray(fmtStr, vargv) ) }
void function Logger_Warn( string fmtStr, ... )  { this.Push( "WARN",  _FormatArray(fmtStr, vargv) ) }
void function Logger_Error( string fmtStr, ... ) { this.Push( "ERROR", _FormatArray(fmtStr, vargv) ) }

void function Logger_Fatal( string fmtStr, ... ) {
    string text = _FormatArray( fmtStr, vargv )
    array<string> err = this.Push( "FATAL", text )

    printt( this.Build() ) // Dump everything leading up to the crash
    throw format( "REGISTRY [%s] FATAL: %s", err[0], err[2] )
}

///	===========================================================================
///								Logger Factory
///		Return a table that imitates functionality of a class instance
///	===========================================================================
table function ArmoryUtils_CreateLogger(
	string initPhase	= "INIT",
	table customFormat	= {},
    table customStatus	= {},
    table customIter	= {}
) {
    //	Initialize table state
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
            vertChar = "| ",    horzChar = "-",     bothChar = "+"
        }

        configStatus = {
            breakPhase = true,  breakLevel = false,
            prefixPhase = "#",  prefixLevel = ">"
        }

        configIter = {
            brackets = "[%s]",  separator = ", ",   missing = "~"
        }
    }

	//	Safely merge user configuration
	foreach (key, val in customFormat) {
		if (key in logger.configFormat) { logger.configFormat[key] = val }
    }

	foreach (key, val in customStatus) {
		if (key in logger.configStatus) { logger.configStatus[key] = val }
    }

	foreach (key, val in customIter) {
		if (key in logger.configIter) { logger.configIter[key] = val }
    }

    //	Bind methods to table
    logger.SetPhase <- Logger_SetPhase
    logger.Push     <- Logger_Push
    logger.Build    <- Logger_Format

    logger.Iter     <- Logger_Iter
    logger.Debug    <- Logger_Debug
    logger.Info     <- Logger_Info
    logger.Warn     <- Logger_Warn
    logger.Error    <- Logger_Error
    logger.Fatal    <- Logger_Fatal

    return logger
}