#pragma once

struct RValue {
	void* val;
	unsigned int flags;
	unsigned int kind;
};

struct MapElement {
	RValue* val;
	int k;
	int hash;
};

struct VarMap {
	int size;
	int used;
	int mask;
	int threshold;

	MapElement* elements;
};

// Everything after this point only has real fields for stuff I need

class YYObjectBase {
public:
	void* __vfptr;
	VarMap* vars;

	char pad[112];
};

// I don't want to talk about it
/*
class VMBuffer {
public:
	uint64* __vfptr;

	char pad[40];
};

class CCode {
public:
	char pad[0x68];

	VMBuffer* vmbuffer;

	char pad2[72];
};

class CScript {
public:
	void* __vfptr;
	CCode* code;

	char pad[0x28];
};

class CScriptRef : YYObjectBase {
public:
	CScript* script;

	char pad2[88];
};*/