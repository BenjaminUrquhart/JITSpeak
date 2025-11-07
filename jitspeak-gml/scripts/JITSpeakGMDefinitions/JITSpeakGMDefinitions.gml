enum VMOpcode {
	CONV = 0x07,
	MUL  = 0x08,
	DIV  = 0x09,
	REM  = 0x0a,
	MOD  = 0x0b,
	ADD  = 0x0c,
	SUB  = 0x0d,
	AND  = 0x0e,
	OR   = 0x0f,
	XOR  = 0x10,
	NEG  = 0x11,
	NOT  = 0x12,
	SHL  = 0x13, // shift left
	SHR  = 0x14, // shift right
	CMP  = 0x15,
	POP  = 0x45,
	DUP  = 0x86,
	RET  = 0x9c,
	EXIT = 0x9d,
	POPZ = 0x9e, // pop and discard
	B    = 0xb6, // unconditional branch
	BT   = 0xb7, // branch true
	BF   = 0xb8, // branch false
	
	PUSHENV = 0xba, // start with statement
	POPENV  = 0xbb, // end with statement
	
	PUSH     = 0xc0,
	PUSHLOC  = 0xc1,
	PUSHGLB  = 0xc2,
	PUSHBLTN = 0xc3,
	PUSHI    = 0x84,
	CALL     = 0xd9,
	CALLV    = 0x99, // call variable
	BREAK    = 0xff  // originally a debug break, is now an "extended" opcode of sorts
}

enum VMOpcodeExt {
	CHKINDEX    = -1,
	PUSHAF      = -2,
	POPAF       = -3,
	PUSHAC      = -4,
	SETOWNER    = -5,
	ISSTATICOK  = -6,
	SETSTATIC   = -7,
	SAVEAREF    = -8,
	RESTOREAREF = -9,
	ISNULLISH   = -10,
	PUSHREF     = -11
}

enum VMArgType {
	DOUBLE,
	FLOAT,
	INT,
	LONG,
	BOOL,
	VARIABLE,
	STRING,
	STRING_PATCH,
	DELETE,
	UNDEFINED,
	PTR,
	
	ERROR = 0xf,
	
	WITH_MARKER = 0xff // not an actual type, used internally by the compiler to keep track of with statements
}

enum VMCmpType {
	NONE,
	LT,
	LTE,
	EQ,
	NEQ,
	GTE,
	GT
}

enum RValueKind {
	REAL,
	STRING,
	ARRAY,
	PTR,
	VEC3,
	UNDEFINED,
	OBJECT,
	INT32,
	VEC4,
	VEC44,
	INT64,
	ACCESSOR,
	NULL,
	BOOL,
	ITERATOR,
	REF,
	
	UNSET = 0xffffff
}

