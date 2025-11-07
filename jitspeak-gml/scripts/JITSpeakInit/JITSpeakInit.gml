#macro JITSpeak global.__jitspeak__
#macro JITSPEAK_VERSION "v0.0.1"

/// @description Initializes the library and makes sure the DLL is working.
/// This function follows the same rules as `catspeak_force_init` - only call this if
/// you are using JITSpeak in a global script or via gml_pragma.
function jitspeak_init() {
	
	if variable_global_exists("__jitspeak__") {
		return
	}
	
	jitspeak_log("Initializing", JITSPEAK_VERSION)
	
	// GMRT is not supported for obvious reasons
	if GM_runtime_type != "gms2" {
		jitspeak_throw("Unsupported runtime type " + GM_runtime_type)	
	}
	
	// Technically any runtime past 2024.1400.0.885 should work but like why
	if !JITSPEAK_DEBUG && !jitspeak_runtime_is_at_least(2024, 14, 0, 251) {
		 jitspeak_throw("Unsupported runtime version " + GM_runtime_version + " - JITSpeak requires at least 2024.14.0.251")	
	}
	
	// Due to the provided DLL, this is Windows-only for now.
	// This may change down the line, but no promises.
	if os_type != os_windows {
		jitspeak_throw("Only the Windows target is supported at this time")	
	}
	
	// YYC seems to explode when doing this, which is not surprising.
	if code_is_compiled() {
		jitspeak_throw("YYC export is unsupported")	
	}
    
    if jitspeak_init_extension() {
		jitspeak_catch_native_exceptions(JITSPEAK_CATCH_NATIVE_EXCEPTIONS)
	}
    else {
        jitspeak_throw("Failed to initialize extension")
    }
    
    catspeak_force_init()
	
	JITSpeak = {
		__masterNative: new JITSpeakMasterNative(),
		
		wrappers: [],
		
		pushWrapper: function(wrapper) {
			array_push(wrappers, { wrapper, name: wrapper.__nameString	})
		},
		
		stringTable: new JITSpeakStringTable(),
		compiler: new JITSpeakCompiler(),
		
        /// @self JITSpeakCompiler
    	/// Takes a Catspeak IR struct, and compiles it into a native Gamemaker method.
    	/// 
    	/// @param {Struct.CatspeakIR} ir The Catspeak IR to compile.
    	///
    	/// @return {Function} The native Gamemaker method object representing the IR.
		compile: function(ir) {
            // Can't just do `compile: compiler.compile` because that breaks the JSDoc
            return compiler.compile(ir)
        }
	}
}

jitspeak_init()