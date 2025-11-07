function JITSpeakNativeWrapper(codeName, bytecode = undefined) constructor {
	// There's a lot of magic numbers here, just trust the process.
	// Initial structure layouts were taken from YYToolKit, while
	// also being supplemented by my own reverse-engineering work.
	
	// https://github.com/AurieFramework/YYToolkit/blob/5a95e46cc4b4e99f16ee3dc0f2ab9ea3c77d18db/YYToolkit/source/YYTK/Shared/YYTK_Shared_Types.hpp
    
    // TODO: move all of this into the native library
	
	static methodClassName = int64(buffer_get_address(jitspeak_str_to_buff("method")))
	
	cscriptref = buffer_create(0xe0, buffer_fixed, 1)
	buffer_poke(cscriptref, 0x74, buffer_u64, 3)
	buffer_poke(cscriptref, 0x58, buffer_u32, 0x10)
	buffer_poke(cscriptref, 0x28, buffer_u64, methodClassName)

	cscript = buffer_create(0x38, buffer_fixed, 1)
	ccode = buffer_create(0xb8, buffer_fixed, 1)

	buffer_poke(cscript, 0x08, buffer_u64, int64(buffer_get_address(ccode)))
	buffer_poke(cscriptref, 0x80, buffer_u64, int64(buffer_get_address(cscript)))

	vmbuffer = buffer_create(0x30, buffer_fixed, 1)

	name = jitspeak_str_to_buff(codeName)
	
	var nameAddr = int64(buffer_get_address(name))
	
	buffer_poke(cscriptref, 0xd0, buffer_u64, nameAddr)
	buffer_poke(cscript, 0x28, buffer_u64, nameAddr)

	buffer_poke(ccode, 0x68, buffer_u64, int64(buffer_get_address(vmbuffer)))
	buffer_poke(ccode, 0x18, buffer_u64, nameAddr)
	buffer_poke(ccode, 0x80, buffer_u64, nameAddr)
	
	__nameString = codeName
	
	boundSelf = undefined
	
	context = undefined
	native = undefined
	
	code = -1
	
	static setLocalCount = function(count) {
		buffer_poke(vmbuffer, 0x0c, buffer_u32, count)
		buffer_poke(ccode, 0xa0, buffer_u32, count)
	}
	
	static setArgumentCount = function(count) {
		buffer_poke(vmbuffer, 0x10, buffer_u32, count)
		buffer_poke(ccode, 0xa4, buffer_u32, count)	
	}
	
	static setContext = function(context) {
		self.context = context	
	}
	
	static setBytecode = function(bytecode) {
		
		var code_len;
		if is_array(bytecode) {
			var array_len = array_length(bytecode)
			for(var i = 0; i < array_len; i++) {
				var val = bytecode[i]
				if !is_numeric(val) {
					throw $"Invalid value in bytecode array at index {i}: expected numeric value, got {typeof(val)}."	
				}
			}
			
			if buffer_exists(code) {
				buffer_delete(code)
			}
			
			code_len = array_len * 4
			code = buffer_create(code_len, buffer_fixed, 1)
			for(var i = 0; i < array_len; i++) {
				buffer_poke(code, i * 4, buffer_u32, bytecode[i] & 0xffffffff)
			}	
		}
		else if is_numeric(bytecode) && buffer_exists(bytecode) {
			if buffer_exists(code) {
				buffer_delete(code)
			}
			code_len = buffer_get_size(bytecode)
			code = buffer_create(code_len, buffer_fixed, 1)
			buffer_copy(bytecode, 0, code_len, code, 0)
		}
		else {
			throw "Invalid parameter 'bytecode' - must be a buffer or array."
		}
	
		buffer_poke(vmbuffer, 0x08, buffer_u32, code_len)
		buffer_poke(vmbuffer, 0x18, buffer_u64, int64(buffer_get_address(code)))
	}
	
	static getNative = function() {
		if is_undefined(native) {
			if JITSPEAK_DEBUG jitspeak_log("Creating native for", __nameString)
			native = JITSpeak.__masterNative.createNative(self)
			
			// Apparently there's like 3-4 different places that a static
			// struct can be located and struct_set/get does not point to
			// the one method entries care about so that's what this is.
			buffer_poke(ccode, 0xb0, buffer_u64, int64(ptr(context.statics)))
			static_set(native, context.statics)
			
			native.toString = method({ name: "function " + __nameString }, function() { return name })
			native.context = context
			
			native.getSelf = method(self, function() {
				return boundSelf	
			})
			
			native.setSelf = method(self, function(newSelf) {
				boundSelf = catspeak_special_to_struct(newSelf)
				
				if is_undefined(boundSelf) {
					__updateSelf(0, 0, RValueKind.UNDEFINED)
				}
				else {
					__updateSelf(ptr(boundSelf), 0, RValueKind.OBJECT)	
				}
			})
			
			native.getGlobals = method(self, function() {
				return context.globals	
			})
			
			native.setGlobals = method(self, function(globals) {
                
                var newGlb = catspeak_special_to_struct(globals)
                
                if is_undefined(newGlb) {
                    jitspeak_throw("Cannot use undefined as global struct")
                }
                
				context.globals = newGlb
                array_foreach(context.functions, method( { hashes: static_get(JITSpeakCompiler), context }, function(func, i) {
					var statics = static_get(func)
					
					if is_undefined(statics) {
						statics = {}
						struct_set_from_hash(statics, hashes.localInterfaceVar & 0xffffff, context.interface)
						struct_set_from_hash(statics, hashes.localFunctionsVar & 0xffffff, context.functions)
						

						with func.context.wrapper {
							buffer_poke(ccode, 0xb0, buffer_u64, int64(ptr(statics)))	
						}
						
						// Just in case
						static_set(func, statics)
					}
					
					struct_set_from_hash(statics, hashes.localGlobalVar & 0xffffff, context.globals)
                }))
			})
			
			if JITSPEAK_DEBUG __logPointers()
		}
		return native
	}
	
	static __logPointers = function() {
		jitspeak_log("Self:      ", ptr(self))
		jitspeak_log("Native:    ", is_struct(native) ? ptr(native) : "<error>")
		jitspeak_log("CScriptRef:", buffer_get_address(cscriptref))
		jitspeak_log("CScript:   ", buffer_get_address(cscript))
		jitspeak_log("CCode:     ", buffer_get_address(ccode))
		jitspeak_log("VMBuffer:  ", buffer_get_address(vmbuffer))
		jitspeak_log("Name:      ", buffer_get_address(name), __nameString)
		jitspeak_log("Globals:   ", is_struct(context) ? ptr(context.globals) : "<not set>")
	}
	
	static __updateSelf = function(val, flags, kind) {
		buffer_poke(cscriptref, 0xa8, buffer_u64, int64(val))
		buffer_poke(cscriptref, 0xb0, buffer_u32, flags)
		buffer_poke(cscriptref, 0xb4, buffer_u32, kind)
	}
	
	// The reason these objects need to stick around is because the natives are flagged to never be
	// garbage collected, as having the GC process those causes a hard crash cause 
	// I'm not filling out all the fields. It would also free the memory behind the buffers which is
	// probably not a good idea.
	JITSpeak.pushWrapper(self)
	
	if !is_undefined(bytecode) {
		setBytecode(bytecode)	
	}
}

// There's a reason for this being its own constructor which
// is not present in this project at this time.
function JITSpeakMasterNative() constructor {
	
	native = { target: 0 }
	
	static init = function() {}
	
	static createNative = function(wrapper) {
		static hash = variable_get_hash("target")
		
		if !jitspeak_init_extension() {
			jitspeak_throw("Extension not initialized")	
		}
		
		var res = jitspeak_inject_native(ptr(native), hash, buffer_get_address(wrapper.cscriptref))
		if(res != 0) {
			jitspeak_throw("Failed to create native object, got error " + string(res))	
		}
		
		return native.target;
	}
}