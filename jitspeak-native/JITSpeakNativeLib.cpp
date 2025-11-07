#define GDKEXTENSION_EXPORTS
#define __YYDEFINE_EXTENSION_FUNCTIONS__

#include <windows.h>
#include <errhandlingapi.h>
#include <iostream>

// Requires the YYRunnerInterface header file from the runtime YYC includes.
// It will likely not compile unedited, as there is a char* where there should be a const char*.
// Just make that change when it comes up.

#include "YYRunnerInterface.h"
#include "YYLib.h"

#define LOG(x) std::cout << "[JITSpeak]: " << x << std::endl
#define ERR(x) std::cerr << "[JITSpeak]: " << x << std::endl

static bool set_interface = false;
static YYRunnerInterface* g_pYYRunnerInterface = nullptr;

__declspec(dllexport) void YYExtensionInitialise(const YYRunnerInterface* pRunnerInterface, size_t _functions_size) {
	if (_functions_size != sizeof(YYRunnerInterface)) {
		ERR("Provided YYRunnerInterface size != sizeof(YYRunnerInterface) (" << _functions_size << " != " << sizeof(YYRunnerInterface) << ")");
		return;
	}

	LOG("YYRunnerInterface provided " << (unsigned long long)pRunnerInterface << " size " << _functions_size);

	if (g_pYYRunnerInterface) {
		free(g_pYYRunnerInterface);
		set_interface = false;
	}

	g_pYYRunnerInterface = (YYRunnerInterface*)malloc(_functions_size);
	if (!g_pYYRunnerInterface) {
		ERR("Failed to allocate YYRunnerInterface");
		return;
	}

	memcpy(g_pYYRunnerInterface, pRunnerInterface, _functions_size);
	set_interface = true;
}

static bool handler_enabled = false;
static DWORD previous_error_mode = 0;
static LPTOP_LEVEL_EXCEPTION_FILTER previous_handler = nullptr;

LONG exception_handler(PEXCEPTION_POINTERS e) {
	YYError("Internal error occurred: %08x at %p", e->ExceptionRecord->ExceptionCode, e->ExceptionRecord->ExceptionAddress);

	if (previous_handler) {
		return previous_handler(e);
	}

	return EXCEPTION_EXECUTE_HANDLER;
}

extern "C" __declspec(dllexport) double jitspeak_catch_native_exceptions(double toggle) {
	if (set_interface && handler_enabled != (bool)toggle) {
		if (toggle) {
			previous_error_mode = GetErrorMode();
			SetErrorMode(previous_error_mode | SEM_NOGPFAULTERRORBOX);
			previous_handler = SetUnhandledExceptionFilter(exception_handler);
		}
		else {
			SetErrorMode(previous_error_mode);
			SetUnhandledExceptionFilter(previous_handler);
			previous_handler = nullptr;
		}
		handler_enabled = toggle;
		return 1;
	}
	return 0;
}

extern "C" __declspec(dllexport) double jitspeak_init_extension() {
	return set_interface;
}

// This function was written before including YYRunnerInterface
extern "C" __declspec(dllexport) double jitspeak_inject_native(YYObjectBase* destObj, double varHash, YYObjectBase* fakeObj) {
	if (!set_interface) {
		return -3;
	}

	if (destObj->vars == NULL || destObj->vars->elements == NULL) {
		return -1;
	}

	int hash = (int)varHash;
	VarMap* vars = destObj->vars;

	MapElement* elements = vars->elements;
	size_t len = vars->size;

	// Fast path
	RValue* val;
	uint32 index = ((1 + hash) & ~0x80000000) & vars->mask;

	if (index < len && elements[index].k == hash) {
		val = elements[index].val;
		val->val = fakeObj;
		val->kind = 6;
		return 0;
	}

	// Really make sure we didn't miss it
	for (size_t i = 0; i < len; i++) {
		MapElement element = elements[i];
		if (element.hash != 0 && element.k == hash) {
			val = element.val;
			val->val = fakeObj;
			val->kind = 6;
			return 0;
		}
	}

	return -2;
}