enum JITSpeakVarOp {
	GET,
	SET
}

enum JITSpeakNativeResult {
	SUCCESS      =  0,
	EMPTY_STRUCT = -1,
	NOT_SET      = -2,
	IFACE_ERROR  = -3
}